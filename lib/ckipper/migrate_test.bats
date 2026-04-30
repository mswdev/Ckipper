#!/usr/bin/env bats
# Unit tests for lib/ckipper/migrate.zsh helpers.
# Sources ckipper.zsh (which wires up all lib/core/ + lib/ckipper/ modules).

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

# Helper: run a zsh expression with stdin input piped in (for interactive prompts).
# The expression should `printf` or `echo` the result to stdout — bats captures it.
# Extra env vars (like _CKIPPER_TEST_OSTYPE override) can be passed via $extra_env.
run_helper_with_input() {
    local expression="$1"
    local stdin_input="$2"
    local extra_env="${3:-}"
    run env \
        HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        _CKIPPER_TEST_OSTYPE="${_CKIPPER_TEST_OSTYPE_OVERRIDE:-linux}" \
        CKIPPER_FORCE=1 \
        $extra_env \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; $expression" <<< "$stdin_input"
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

# ── _ckipper_migrate_rollback ─────────────────────────────────────────

@test "rollback restores the target dir to the legacy path when step >= 1" {
    # Simulate a mid-migration state: target dir was created, no .claude exists.
    local target_dir="$TMP_HOME/.claude-personal"
    local legacy_dir="$TMP_HOME/.claude"
    mkdir -p "$target_dir"

    run_helper "_CKIPPER_MIGRATE_STEP=1; _CKIPPER_MIGRATE_BACKUP=\"\"
        typeset -gA _CKIPPER_MIGRATE_CTX
        _CKIPPER_MIGRATE_CTX[name]=\"personal\"
        _CKIPPER_MIGRATE_CTX[target_dir]=\"$target_dir\"
        _CKIPPER_MIGRATE_CTX[legacy_claude]=\"$legacy_dir\"
        _CKIPPER_MIGRATE_CTX[legacy_homejson]=\"$TMP_HOME/.claude.json\"
        _ckipper_migrate_rollback \"failed\""

    [ "$status" -eq 0 ]
    # The target dir should be moved back to the legacy location.
    [ -d "$legacy_dir" ]
    [ ! -d "$target_dir" ]
}

@test "rollback is idempotent — running twice on already-restored state is safe" {
    local target_dir="$TMP_HOME/.claude-personal"
    local legacy_dir="$TMP_HOME/.claude"
    mkdir -p "$target_dir"

    # First rollback — restores legacy dir.
    run_helper "_CKIPPER_MIGRATE_STEP=1; _CKIPPER_MIGRATE_BACKUP=\"\"
        typeset -gA _CKIPPER_MIGRATE_CTX
        _CKIPPER_MIGRATE_CTX[name]=\"personal\"
        _CKIPPER_MIGRATE_CTX[target_dir]=\"$target_dir\"
        _CKIPPER_MIGRATE_CTX[legacy_claude]=\"$legacy_dir\"
        _CKIPPER_MIGRATE_CTX[legacy_homejson]=\"$TMP_HOME/.claude.json\"
        _ckipper_migrate_rollback \"failed\""
    [ "$status" -eq 0 ]
    [ -d "$legacy_dir" ]

    # Second rollback — target_dir no longer exists, so no move happens; legacy_dir stays.
    run_helper "_CKIPPER_MIGRATE_STEP=1; _CKIPPER_MIGRATE_BACKUP=\"\"
        typeset -gA _CKIPPER_MIGRATE_CTX
        _CKIPPER_MIGRATE_CTX[name]=\"personal\"
        _CKIPPER_MIGRATE_CTX[target_dir]=\"$target_dir\"
        _CKIPPER_MIGRATE_CTX[legacy_claude]=\"$legacy_dir\"
        _CKIPPER_MIGRATE_CTX[legacy_homejson]=\"$TMP_HOME/.claude.json\"
        _ckipper_migrate_rollback \"failed\""
    [ "$status" -eq 0 ]
    [ -d "$legacy_dir" ]
}

# ── _ckipper_migrate_prompt_account_name ──────────────────────────────
# These tests verify that the captured stdout is ONLY the chosen name —
# regression guard for the "stdout pollution on retry" bug where validation
# error messages would leak into the captured value, corrupting the registry.

@test "prompt_account_name accepts the default on empty input" {
    run_helper_with_input \
        'name=$(_ckipper_migrate_prompt_account_name); printf "RESULT=[%s]" "$name"' \
        $'\n'

    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT=[personal]"* ]]
}

@test "prompt_account_name returns ONLY the valid name after a name-collision retry" {
    # First pick collides (~/.claude-personal exists); user retries with a different name.
    mkdir -p "$TMP_HOME/.claude-personal"

    run_helper_with_input \
        'name=$(_ckipper_migrate_prompt_account_name); printf "RESULT=[%s]" "$name"' \
        $'personal\nwork\n'

    [ "$status" -eq 0 ]
    # The captured value must be exactly "work" — not "<error>\nwork".
    [[ "$output" == *"RESULT=[work]"* ]]
    [[ "$output" != *"RESULT=[already exists"* ]]
    [[ "$output" != *"RESULT=[$TMP_HOME"* ]]
}

@test "prompt_account_name returns ONLY the valid name after an invalid-format retry" {
    run_helper_with_input \
        'name=$(_ckipper_migrate_prompt_account_name); printf "RESULT=[%s]" "$name"' \
        $'BAD NAME!\nwork\n'

    [ "$status" -eq 0 ]
    # The captured value must be exactly "work" — not "Account name must match...\nwork".
    [[ "$output" == *"RESULT=[work]"* ]]
    [[ "$output" != *"RESULT=[Account name"* ]]
}

# ── _ckipper_migrate_detect_keychain ──────────────────────────────────

@test "detect_keychain returns empty string on non-darwin platforms" {
    run_helper '_ckipper_migrate_detect_keychain; echo "RESULT=[$?]"'

    [ "$status" -eq 0 ]
    [[ "$output" == "RESULT=[0]" ]]
}

@test "detect_keychain returns ONLY the user input from the fallback prompt path" {
    # Simulate macOS but with no matching Keychain entry — exercises the fallback prompt.
    # The user types "MyCustomService".

    run env \
        HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        _CKIPPER_TEST_OSTYPE="darwin25.0.0" \
        SECURITY_STUB_FAIL_FIND=1 \
        CKIPPER_FORCE=1 \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; svc=\$(_ckipper_migrate_detect_keychain); printf 'RESULT=[%s]' \"\$svc\"" \
        <<< $'MyCustomService\n'

    [ "$status" -eq 0 ]
    # Captured value must be exactly "MyCustomService" — not "Warning: ...\nMyCustomService".
    [[ "$output" == *"RESULT=[MyCustomService]"* ]]
    [[ "$output" != *"RESULT=[Warning"* ]]
    [[ "$output" != *"RESULT=[Listing"* ]]
}

# ── _ckipper_migrate_print_plan ───────────────────────────────────────

@test "print_plan emits the migration plan from the migration context" {
    run_helper "typeset -gA _CKIPPER_MIGRATE_CTX
        _CKIPPER_MIGRATE_CTX[legacy_claude]=\"$TMP_HOME/.claude\"
        _CKIPPER_MIGRATE_CTX[legacy_homejson]=\"$TMP_HOME/.claude.json\"
        _CKIPPER_MIGRATE_CTX[target_dir]=\"$TMP_HOME/.claude-personal\"
        _CKIPPER_MIGRATE_CTX[name]=\"personal\"
        _ckipper_migrate_print_plan"

    [ "$status" -eq 0 ]
    [[ "$output" == *"This migration will:"* ]]
    [[ "$output" == *"Rename $TMP_HOME/.claude → $TMP_HOME/.claude-personal."* ]]
    [[ "$output" == *"Register 'personal'"* ]]
}
