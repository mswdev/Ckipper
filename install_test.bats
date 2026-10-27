#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Run install.sh against the isolated $TMP_HOME.
run_install() {
    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" run "$REPO_ROOT/install.sh"
}

@test "install.sh fresh install deploys ckipper.zsh and lib/ under ~/.ckipper" {
    run_install

    [ "$status" -eq 0 ]
    [ -f "$TMP_HOME/.ckipper/ckipper.zsh" ]
    [ -d "$TMP_HOME/.ckipper/lib/core" ]
    [ -d "$TMP_HOME/.ckipper/lib/account" ]
    [ -d "$TMP_HOME/.ckipper/lib/desktop" ]
    [ ! -e "$TMP_HOME/.ckipper/docker" ]
}

@test "install.sh excludes test files from deployed lib/" {
    run_install

    [ "$status" -eq 0 ]
    run find "$TMP_HOME/.ckipper/lib" -name '*_test.*'
    [ -z "$output" ]
}

@test "install.sh leaves accounts.json, desktop.json and aliases.zsh alone" {
    echo '{"version":3,"default":null,"accounts":{}}' > "$CKIPPER_DIR/accounts.json"
    echo '{"version":1,"instances":{}}' > "$CKIPPER_DIR/desktop.json"
    echo '# generated' > "$CKIPPER_DIR/aliases.zsh"

    run_install

    [ "$status" -eq 0 ]
    grep -q '"version":3' "$CKIPPER_DIR/accounts.json"
    grep -q '"instances"' "$CKIPPER_DIR/desktop.json"
    grep -q '# generated' "$CKIPPER_DIR/aliases.zsh"
}

@test "install.sh removes the old Docker-era files" {
    mkdir -p "$CKIPPER_DIR/docker/lib" "$CKIPPER_DIR/hooks"
    echo '# old' > "$CKIPPER_DIR/docker/ckipper.zsh"
    echo '# old' > "$CKIPPER_DIR/hooks/bash-guardrails.sh"
    echo '{}' > "$CKIPPER_DIR/settings-template.json"

    run_install

    [ "$status" -eq 0 ]
    [ ! -e "$CKIPPER_DIR/docker" ]
    [ ! -e "$CKIPPER_DIR/hooks" ]
    [ ! -e "$CKIPPER_DIR/settings-template.json" ]
}

@test "install.sh appends a source line when ~/.zshrc has none" {
    echo '# Some user config' > "$HOME/.zshrc"

    run_install

    [ "$status" -eq 0 ]
    grep -qF 'source "$HOME/.ckipper/ckipper.zsh"' "$HOME/.zshrc"
    grep -q '# Some user config' "$HOME/.zshrc"
}

@test "install.sh rewrites the old docker/ckipper.zsh source line in place" {
    cat > "$HOME/.zshrc" << 'EOF'
# Some user config
source "$HOME/.ckipper/docker/ckipper.zsh"
[[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh
EOF

    run_install

    [ "$status" -eq 0 ]
    [ "$(sed -n 2p "$HOME/.zshrc")" = 'source "$HOME/.ckipper/ckipper.zsh"' ]
    ! grep -q 'docker/ckipper\.zsh' "$HOME/.zshrc"
    grep -q 'ckipper/aliases.zsh' "$HOME/.zshrc"
}

@test "install.sh rewrites a pre-merge w-function.zsh line with a trailing comment" {
    cat > "$HOME/.zshrc" << 'EOF'
source "$HOME/.ckipper/docker/w-function.zsh" # ckipper bootstrap
EOF

    run_install

    [ "$status" -eq 0 ]
    grep -qF 'source "$HOME/.ckipper/ckipper.zsh"' "$HOME/.zshrc"
    ! grep -q 'w-function\.zsh' "$HOME/.zshrc"
}

@test "install.sh is idempotent: second run keeps one source line and the first backup" {
    echo 'source "$HOME/.ckipper/docker/ckipper.zsh"' > "$HOME/.zshrc"
    run_install
    [ "$status" -eq 0 ]
    local first_backup
    first_backup=$(ls "$HOME"/.zshrc.ckipper-bak.* 2>/dev/null | head -1)
    [ -n "$first_backup" ]

    run_install

    [ "$status" -eq 0 ]
    [ "$(grep -cF 'source "$HOME/.ckipper/ckipper.zsh"' "$HOME/.zshrc")" -eq 1 ]
    grep -q 'docker/ckipper\.zsh' "$first_backup"
}

@test "install.sh leaves the user's git core.hooksPath alone" {
    run_install

    [ "$status" -eq 0 ]
    run git config --global --get core.hooksPath
    [ -z "$output" ]
}

@test "install.sh fails fast when gum is missing" {
    # Build a PATH where jq/security exist as no-op stubs but gum does NOT —
    # coreutils (/usr/bin, /bin) stay reachable so install.sh's pre-check
    # shell plumbing (dirname, pwd, uname) still works.
    local fake_path="$BATS_TEST_TMPDIR/fake_bin"
    mkdir -p "$fake_path"
    for cmd in jq security; do
        printf '#!/bin/sh\nexit 0\n' > "$fake_path/$cmd"
        chmod +x "$fake_path/$cmd"
    done

    run env HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" \
        PATH="$fake_path:/usr/bin:/bin" "$REPO_ROOT/install.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *"gum"* ]]
}
