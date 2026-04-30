#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

@test "install.sh fresh install creates ~/.ckipper/docker/ tree with lib/" {
    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" \
        run "$REPO_ROOT/install.sh"

    [ "$status" -eq 0 ]
    [ -d "$TMP_HOME/.ckipper/docker/lib/core" ]
    [ -d "$TMP_HOME/.ckipper/docker/lib/account" ]
    [ -d "$TMP_HOME/.ckipper/docker/lib/worktree" ]
    [ -f "$TMP_HOME/.ckipper/docker/ckipper.zsh" ]
    [ -f "$TMP_HOME/.ckipper/docker/ckipper-config.zsh" ]
}

@test "install.sh excludes test files from deployed lib/" {
    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" \
        run "$REPO_ROOT/install.sh"

    [ "$status" -eq 0 ]
    run find "$TMP_HOME/.ckipper/docker/lib" \( -name '*_test.*' -o -name '__pycache__' \)
    [ -z "$output" ]
}

@test "install.sh re-run preserves customised ckipper-config.zsh" {
    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" run "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]
    echo 'CUSTOM_VALUE="preserve_me"' >> "$TMP_HOME/.ckipper/docker/ckipper-config.zsh"

    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" \
        run "$REPO_ROOT/install.sh"

    [ "$status" -eq 0 ]
    grep -q 'CUSTOM_VALUE="preserve_me"' "$TMP_HOME/.ckipper/docker/ckipper-config.zsh"
}

@test "install.sh deletes stale w-function.zsh from a pre-merge install" {
    mkdir -p "$TMP_HOME/.ckipper/docker"
    echo "# stale w-function" > "$TMP_HOME/.ckipper/docker/w-function.zsh"

    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" \
        run "$REPO_ROOT/install.sh"

    [ "$status" -eq 0 ]
    [ ! -f "$TMP_HOME/.ckipper/docker/w-function.zsh" ]
}

@test "install.sh deletes stale _w completion file from a pre-merge install" {
    mkdir -p "$HOME/.zsh/completions"
    echo "# stale _w" > "$HOME/.zsh/completions/_w"

    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" \
        run "$REPO_ROOT/install.sh"

    [ "$status" -eq 0 ]
    [ ! -f "$TMP_HOME/.zsh/completions/_w" ]
}

@test "install.sh migrates pre-merge w-config.zsh into ckipper-config.zsh" {
    mkdir -p "$TMP_HOME/.ckipper/docker"
    cat > "$TMP_HOME/.ckipper/docker/w-config.zsh" << 'EOF'
# pre-merge user config
CUSTOM_VALUE="from_old_config"
EOF

    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" \
        run "$REPO_ROOT/install.sh"

    [ "$status" -eq 0 ]
    [ ! -f "$TMP_HOME/.ckipper/docker/w-config.zsh" ]
    [ -f "$TMP_HOME/.ckipper/docker/ckipper-config.zsh" ]
    grep -q 'CUSTOM_VALUE="from_old_config"' "$TMP_HOME/.ckipper/docker/ckipper-config.zsh"
}

@test "install.sh rewrites pre-merge ~/.zshrc source line to ckipper.zsh" {
    cat > "$HOME/.zshrc" << 'EOF'
# Some user config
source "$HOME/.ckipper/docker/w-function.zsh"
EOF

    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" \
        run "$REPO_ROOT/install.sh"

    [ "$status" -eq 0 ]
    grep -q 'ckipper/docker/ckipper\.zsh' "$HOME/.zshrc"
    ! grep -q 'ckipper/docker/w-function\.zsh' "$HOME/.zshrc"
}
