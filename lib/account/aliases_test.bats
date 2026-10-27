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

# ── _ckipper_account_regenerate_aliases ───────────────────────────────────────

@test "regenerate_aliases creates aliases.zsh with mode 644" {
    echo '{"version":3,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_regenerate_aliases'

    local out="$CKIPPER_DIR/aliases.zsh"
    assert_file_exists "$out"
    assert_file_mode "$out" "644"
}

@test "regenerate_aliases includes a launcher function for each registered account" {
    echo '{"version":3,"default":"dev","accounts":{"dev":{"config_dir":"/tmp/.claude-dev","keychain_service":null}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_regenerate_aliases'

    local out="$CKIPPER_DIR/aliases.zsh"
    assert_file_exists "$out"
    grep -q "claude-dev()" "$out"
}

# ── _ckipper_account_generate_account_launcher_function ───────────────────────

@test "generate_account_launcher_function emits a claude-<name> function" {
    run_helper '_ckipper_account_generate_account_launcher_function "work" "/tmp/.claude-work"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "claude-work()" ]]
}

@test "generate_account_launcher_function sets CLAUDE_CONFIG_DIR in the emitted body" {
    run_helper '_ckipper_account_generate_account_launcher_function "work" "/tmp/.claude-work"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "CLAUDE_CONFIG_DIR" ]]
    [[ "$output" =~ "/tmp/.claude-work" ]]
}
