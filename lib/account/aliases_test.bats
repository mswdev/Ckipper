#!/usr/bin/env bats
# Unit tests for lib/account/aliases.zsh helpers.
# Sources ckipper.zsh (which wires up all lib/core/ + lib/account/ modules).

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: run a zsh expression with the full ckipper environment sourced.
run_helper() {
    run env \
        HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        _CKIPPER_TEST_OSTYPE="linux" \
        CKIPPER_FORCE=1 \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; $*"
}

# ── _ckipper_regenerate_aliases ───────────────────────────────────────

@test "regenerate_aliases creates aliases.zsh with mode 644" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_regenerate_aliases'

    local out="$CKIPPER_DIR/aliases.zsh"
    assert_file_exists "$out"
    assert_file_mode "$out" "644"
}

@test "regenerate_aliases includes a launcher function for each registered account" {
    echo '{"version":1,"default":"dev","accounts":{"dev":{"config_dir":"/tmp/.claude-dev","keychain_service":null}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_regenerate_aliases'

    local out="$CKIPPER_DIR/aliases.zsh"
    assert_file_exists "$out"
    grep -q "claude-dev()" "$out"
}

# ── _ckipper_generate_account_launcher_function ───────────────────────

@test "generate_account_launcher_function emits a claude-<name> function" {
    run_helper '_ckipper_generate_account_launcher_function "work" "/tmp/.claude-work"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "claude-work()" ]]
}

@test "generate_account_launcher_function sets CLAUDE_CONFIG_DIR in the emitted body" {
    run_helper '_ckipper_generate_account_launcher_function "work" "/tmp/.claude-work"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "CLAUDE_CONFIG_DIR" ]]
    [[ "$output" =~ "/tmp/.claude-work" ]]
}

# ── _ckipper_sync_hooks_for ──────────────────────────────────────────

@test "sync_hooks_for copies hooks into the account directory" {
    echo '{"version":1,"default":"dev","accounts":{"dev":{"config_dir":"'"$TMP_HOME"'/.claude-dev","keychain_service":null}}}' > "$CKIPPER_REGISTRY"
    mkdir -p "$TMP_HOME/.claude-dev"
    # Seed the shared hooks directory with a test hook.
    mkdir -p "$CKIPPER_DIR/hooks"
    echo "#!/bin/sh" > "$CKIPPER_DIR/hooks/test-hook.sh"

    run_helper '_ckipper_sync_hooks_for "dev"'

    [ "$status" -eq 0 ]
    [ -f "$TMP_HOME/.claude-dev/hooks/test-hook.sh" ]
}

@test "sync_hooks_for rewrites dollar-HOME hook paths in settings.json" {
    echo '{"version":1,"default":"dev","accounts":{"dev":{"config_dir":"'"$TMP_HOME"'/.claude-dev","keychain_service":null}}}' > "$CKIPPER_REGISTRY"
    mkdir -p "$TMP_HOME/.claude-dev/hooks"
    # settings.json has a literal $HOME placeholder in a hook path.
    printf '{"hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"$HOME/.ckipper/hooks/pre.sh"}]}]}}' \
        > "$TMP_HOME/.claude-dev/settings.json"

    run_helper '_ckipper_sync_hooks_for "dev"'

    # After rewriting, the path should point to the account's hooks dir.
    grep -q "$TMP_HOME/.claude-dev/hooks/pre.sh" "$TMP_HOME/.claude-dev/settings.json"
}

# ── _ckipper_sync_hooks ───────────────────────────────────────────────

@test "sync_hooks iterates all registered accounts and copies hooks to each" {
    local dir_a="$TMP_HOME/.claude-alpha"
    local dir_b="$TMP_HOME/.claude-beta"
    mkdir -p "$dir_a" "$dir_b"
    echo '{"version":1,"default":"alpha","accounts":{"alpha":{"config_dir":"'"$dir_a"'","keychain_service":null},"beta":{"config_dir":"'"$dir_b"'","keychain_service":null}}}' > "$CKIPPER_REGISTRY"
    mkdir -p "$CKIPPER_DIR/hooks"
    echo "#!/bin/sh" > "$CKIPPER_DIR/hooks/shared-hook.sh"

    run_helper '_ckipper_sync_hooks'

    [ "$status" -eq 0 ]
    [ -f "$dir_a/hooks/shared-hook.sh" ]
    [ -f "$dir_b/hooks/shared-hook.sh" ]
}
