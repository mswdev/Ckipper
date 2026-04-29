#!/usr/bin/env bats
# Unit tests for lib/ckipper/migrate.zsh helpers.
# Sources ckipper.zsh (which wires up all lib/core/ + lib/ckipper/ modules).
#
# Interactive-prompt helpers (_ckipper_migrate_prompt_account_name,
# _ckipper_migrate_confirm_plan, _ckipper_migrate_detect_keychain) are skipped
# because they block on stdin; the full end-to-end flow is covered by
# the characterization tests in ckipper_test.bats.

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

# ── _ckipper_migrate_check_state ──────────────────────────────────────

@test "check_state returns 1 (no state) when neither legacy dir nor home json exist" {
    # Fresh TMP_HOME has no .claude or .claude.json.
    run_helper '_ckipper_migrate_check_state "$HOME/.claude" "$HOME/.claude.json"; echo "rc=$?"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "rc=1" ]]
}

@test "check_state returns 0 (needs migration) when home-root .claude.json exists" {
    echo '{}' > "$TMP_HOME/.claude.json"

    run_helper '_ckipper_migrate_check_state "$HOME/.claude" "$HOME/.claude.json"; echo "rc=$?"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "rc=0" ]]
}

@test "check_state returns 2 (already migrated) when registry has accounts and no legacy state" {
    echo '{"version":1,"default":"personal","accounts":{"personal":{"config_dir":"/tmp/.claude-personal","keychain_service":null}}}' > "$CKIPPER_REGISTRY"
    echo '{}' > "$TMP_HOME/.claude.json"

    run_helper '_ckipper_migrate_check_state "$HOME/.claude" "$HOME/.claude.json"; echo "rc=$?"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "rc=2" ]]
}

# ── _ckipper_migrate_preflight ────────────────────────────────────────

@test "preflight passes when neither legacy path is a symlink" {
    mkdir -p "$TMP_HOME/.claude"
    echo '{}' > "$TMP_HOME/.claude.json"

    run_helper '_ckipper_migrate_preflight "$HOME/.claude" "$HOME/.claude.json"'

    [ "$status" -eq 0 ]
}

@test "preflight fails when legacy claude dir is a symlink" {
    mkdir -p "$TMP_HOME/.claude-target"
    ln -s "$TMP_HOME/.claude-target" "$TMP_HOME/.claude"

    run_helper '_ckipper_migrate_preflight "$HOME/.claude" "$HOME/.claude.json"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "symlink" ]]
}

# ── _ckipper_migrate_rename_dirs ──────────────────────────────────────

@test "rename_dirs moves legacy claude dir to the target directory" {
    mkdir -p "$TMP_HOME/.claude"
    local target_dir="$TMP_HOME/.claude-personal"

    run_helper "_ckipper_migrate_rename_dirs \"$TMP_HOME/.claude\" \"$TMP_HOME/.claude.json\" \"$target_dir\""

    [ "$status" -eq 0 ]
    [ -d "$target_dir" ]
    [ ! -d "$TMP_HOME/.claude" ]
}

@test "rename_dirs also moves home-root .claude.json into the target dir" {
    mkdir -p "$TMP_HOME/.claude"
    echo '{"projects":[]}' > "$TMP_HOME/.claude.json"
    local target_dir="$TMP_HOME/.claude-personal"

    run_helper "_ckipper_migrate_rename_dirs \"$TMP_HOME/.claude\" \"$TMP_HOME/.claude.json\" \"$target_dir\""

    [ "$status" -eq 0 ]
    [ -f "$target_dir/.claude.json" ]
    [ ! -f "$TMP_HOME/.claude.json" ]
}
