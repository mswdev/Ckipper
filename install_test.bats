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

@test "install.sh renames W_* assignments to CKIPPER_* during migration" {
    mkdir -p "$TMP_HOME/.ckipper/docker"
    cat > "$TMP_HOME/.ckipper/docker/w-config.zsh" << 'EOF'
# pre-merge user config — every customizable variable
W_PROJECTS_DIR="$HOME/myrepos"
W_WORKTREES_DIR="$HOME/myworktrees"
W_PORTS=(3000 8080 9090 12345)
W_EXTRA_VOLUMES=("/data:/data:ro")
W_EXTRA_ENV=("CUSTOM_KEY=v")
# Comment with W_PORTS in it should NOT be rewritten.
EOF

    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" \
        run "$REPO_ROOT/install.sh"

    [ "$status" -eq 0 ]
    local cfg="$TMP_HOME/.ckipper/docker/ckipper-config.zsh"
    grep -q '^CKIPPER_PROJECTS_DIR=' "$cfg"
    grep -q '^CKIPPER_WORKTREES_DIR=' "$cfg"
    grep -q '^CKIPPER_PORTS=(3000 8080 9090 12345)' "$cfg"
    grep -q '^CKIPPER_EXTRA_VOLUMES=' "$cfg"
    grep -q '^CKIPPER_EXTRA_ENV=' "$cfg"
    # Comment lines must not be rewritten — preserve original W_PORTS reference.
    grep -q '# Comment with W_PORTS in it' "$cfg"
    # No leftover W_* assignments (excluding the comment).
    ! grep -qE '^[[:space:]]*W_(PROJECTS_DIR|WORKTREES_DIR|PORTS|EXTRA_VOLUMES|EXTRA_ENV)=' "$cfg"

    # Functional check: post-install ckipper.zsh sees the renamed variables.
    run zsh -c "source '$REPO_ROOT/ckipper.zsh'; print -r -- \"\${CKIPPER_PORTS[*]}\""
    [ "$status" -eq 0 ]
    [[ "$output" =~ "3000 8080 9090 12345" ]]
}

@test "install.sh rewrites pre-merge ~/.zshrc source line with trailing comment" {
    cat > "$HOME/.zshrc" << 'EOF'
# Some user config
source "$HOME/.ckipper/docker/w-function.zsh" # ckipper bootstrap
EOF

    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" \
        run "$REPO_ROOT/install.sh"

    [ "$status" -eq 0 ]
    grep -q 'ckipper/docker/ckipper\.zsh' "$HOME/.zshrc"
    ! grep -q 'ckipper/docker/w-function\.zsh' "$HOME/.zshrc"
}

@test "install.sh creates timestamped backup, does not clobber on second run" {
    cat > "$HOME/.zshrc" << 'EOF'
source "$HOME/.ckipper/docker/w-function.zsh"
EOF

    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" \
        run "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]

    local first_backup
    first_backup=$(ls "$HOME"/.zshrc.ckipper-bak.* 2>/dev/null | head -1)
    [ -n "$first_backup" ]
    grep -q 'ckipper/docker/w-function\.zsh' "$first_backup"

    # Second install run on already-rewritten zshrc — must not clobber backup.
    sleep 1
    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" \
        run "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]
    [ -f "$first_backup" ]
    grep -q 'ckipper/docker/w-function\.zsh' "$first_backup"
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
