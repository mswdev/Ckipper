#!/usr/bin/env bats
# Unit tests for lib/account/sync/dispatcher.zsh — arg parsing skeleton.

load "${BATS_TEST_DIRNAME}/../../../tests/lib/test-helper.bash"

setup() { setup_isolated_env; }
teardown() { teardown_isolated_env; }

run_in_zsh() {
    run env CKIPPER_DIR="$CKIPPER_DIR" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/registry.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/dispatcher.zsh\"; $*"
}

@test "parse_args identifies --dry-run flag" {
    run_in_zsh '
        _ckipper_account_sync_parse_args personal work --dry-run
        echo "from=$_CKIPPER_SYNC_FROM"
        echo "targets=${_CKIPPER_SYNC_TARGETS[*]}"
        echo "dry_run=$_CKIPPER_SYNC_DRY_RUN"'
    [[ "$output" == *"from=personal"* ]]
    [[ "$output" == *"targets=work"* ]]
    [[ "$output" == *"dry_run=true"* ]]
}

@test "parse_args identifies --yes flag" {
    run_in_zsh '
        _ckipper_account_sync_parse_args personal work --yes
        echo "yes=$_CKIPPER_SYNC_YES"'
    [[ "$output" == *"yes=true"* ]]
}

@test "parse_args identifies multiple targets" {
    run_in_zsh '
        _ckipper_account_sync_parse_args personal work client1 client2
        echo "targets=${(j:,:)_CKIPPER_SYNC_TARGETS}"'
    [[ "$output" == *"targets=work,client1,client2"* ]]
}

@test "parse_args identifies --include with comma list" {
    run_in_zsh '
        _ckipper_account_sync_parse_args personal work --include mcp,settings
        echo "include=$_CKIPPER_SYNC_INCLUDE"'
    [[ "$output" == *"include=mcp,settings"* ]]
}

@test "parse_args identifies --exclude with comma list" {
    run_in_zsh '
        _ckipper_account_sync_parse_args personal work --include all --exclude prefs
        echo "include=$_CKIPPER_SYNC_INCLUDE"
        echo "exclude=$_CKIPPER_SYNC_EXCLUDE"'
    [[ "$output" == *"include=all"* ]]
    [[ "$output" == *"exclude=prefs"* ]]
}

@test "parse_args identifies --force" {
    run_in_zsh '
        _ckipper_account_sync_parse_args personal work --force
        echo "force=$_CKIPPER_SYNC_FORCE"'
    [[ "$output" == *"force=true"* ]]
}

@test "parse_args returns 1 on unknown flag" {
    run_in_zsh '_ckipper_account_sync_parse_args personal work --bogus'
    [ "$status" -ne 0 ]
}

@test "parse_args allows empty positionals (drop-to-picker)" {
    run_in_zsh '
        _ckipper_account_sync_parse_args
        echo "from=${_CKIPPER_SYNC_FROM:-EMPTY}"
        echo "n_targets=${#_CKIPPER_SYNC_TARGETS[@]}"'
    [[ "$output" == *"from=EMPTY"* ]]
    [[ "$output" == *"n_targets=0"* ]]
}

# ── Integration: end-to-end dispatch with seeded accounts ────────────────

setup_two_accounts() {
    cat > "$CKIPPER_REGISTRY" <<JSON
{"version":2,"default":"src","accounts":{
    "src":{"config_dir":"$TMP_HOME/src","keychain_service":null,"registered_at":"t","preferences":{"always_docker":true,"always_firewall":false,"ssh_forward":true}},
    "dst":{"config_dir":"$TMP_HOME/dst","keychain_service":null,"registered_at":"t","preferences":{"always_docker":false,"always_firewall":false,"ssh_forward":false}}
}}
JSON
    chmod 600 "$CKIPPER_REGISTRY"
    mkdir -p "$TMP_HOME/src" "$TMP_HOME/dst"
    echo '{"mcpServers":{"github":{"command":"x"}}}' > "$TMP_HOME/src/.claude.json"
    echo '{"mcpServers":{}}' > "$TMP_HOME/dst/.claude.json"
}

run_full() {
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        CKIPPER_NO_GUM=1 CKIPPER_FORCE=1 TMP_HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; $*"
}

@test "ckipper account sync src dst --include mcp --yes applies the merge" {
    setup_two_accounts
    run_full 'ckipper account sync src dst --include mcp --yes'
    [ "$status" -eq 0 ]
    local merged
    merged=$(jq -r '.mcpServers.github.command' "$TMP_HOME/dst/.claude.json")
    [[ "$merged" == "x" ]]
}

@test "ckipper account sync src dst --include mcp --dry-run does not apply" {
    setup_two_accounts
    run_full 'ckipper account sync src dst --include mcp --dry-run'
    [ "$status" -eq 0 ]
    local n; n=$(jq '.mcpServers | length' "$TMP_HOME/dst/.claude.json")
    [[ "$n" == "0" ]]
}

# Regression: dry-run is read-only; the running-Claude refusal exists to
# prevent races with writes. A user previewing changes while their session
# is still open must not be blocked.
@test "ckipper account sync --dry-run is not blocked when Claude is running on dst" {
    setup_two_accounts
    run_full '
        # Stub: pretend claude is running and its argv includes the dst path.
        _core_running_claude_processes() { echo "12345 claude $TMP_HOME/dst"; }
        ckipper account sync src dst --include mcp --dry-run'
    [ "$status" -eq 0 ]
    [[ "$output" != *"Refusing to sync"* ]]
}

# Companion check: without --dry-run (and without --force), the same scenario
# must still abort — the dry-run skip is the only carve-out.
@test "ckipper account sync without --dry-run IS blocked when Claude is running on dst" {
    setup_two_accounts
    run_full '
        _core_running_claude_processes() { echo "12345 claude $TMP_HOME/dst"; }
        ckipper account sync src dst --include mcp --yes'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Refusing to sync"* ]]
}

@test "ckipper account sync rejects unregistered source" {
    setup_two_accounts
    run_full 'ckipper account sync ghost dst --include mcp --yes'
    [ "$status" -ne 0 ]
}

@test "ckipper account sync src src is rejected (identity)" {
    setup_two_accounts
    run_full 'ckipper account sync src src --include mcp --yes'
    [ "$status" -ne 0 ]
}

# Bug B: undo_dispatch used to read $_CKIPPER_SYNC_FORCE directly, which leaked
# state from a prior sync invocation in the same shell. A user who ran
# `sync ... --force` (setting _CKIPPER_SYNC_FORCE=true) and then ran `sync undo`
# without --force would silently bypass the running-Claude refusal because
# parse_args resets _CKIPPER_SYNC_FORCE only on the sync path. Fix: undo uses a
# local force var, defaulting to false.
@test "sync undo does NOT inherit --force from a prior sync invocation (Bug B)" {
    setup_two_accounts
    run_full '
        # Apply a sync first WITH --force so _CKIPPER_SYNC_FORCE leaks to module state.
        _core_running_claude_processes() { return 0; }
        ckipper account sync src dst --include mcp --yes --force >/dev/null 2>&1
        # Now undo without --force; running Claude should block it again.
        _core_running_claude_processes() { echo "12345 claude"; }
        ckipper account sync undo dst'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Refusing to sync"* ]]
}

# Bug B (companion): sync undo --force still works on its own.
@test "sync undo --force bypasses the running-Claude refusal" {
    setup_two_accounts
    # Need at least one backup to exist for undo to do anything past the gate.
    run_full '
        _core_running_claude_processes() { return 0; }
        ckipper account sync src dst --include mcp --yes >/dev/null 2>&1
        _core_running_claude_processes() { echo "12345 claude"; }
        ckipper account sync undo dst --force'
    [ "$status" -eq 0 ]
}

# Regression: when the user picks "View changes" then "Apply", the diff
# output written by drill_down_loop must NOT pollute the captured action,
# else the [[ "$action" == "apply" ]] check downstream silently skips apply.
# The mock _core_prompt_choose persists state via a flag file because each
# choice=$(...) call inside preview_prompt opens a fresh subshell.
@test "preview_prompt View changes then Apply yields exactly 'apply'" {
    run_in_zsh '
        _CKIPPER_SYNC_FROM=src
        items=$(mktemp); echo "x" > "$items"
        _CKIPPER_SYNC_CTX[dst_name]=dst
        _CKIPPER_SYNC_CTX[items]=$items
        export _PROMPT_FLAG=$(mktemp)
        _core_prompt_choose() {
            if [[ -e "$_PROMPT_FLAG" ]]; then
                rm "$_PROMPT_FLAG"
                echo "View changes"
            else
                echo "Apply"
            fi
        }
        _ckipper_account_sync_drill_down_loop() {
            echo "── source diff ──"
            echo "+++ added line"
            echo "(Press enter to return to picker)"
        }
        action=$(_ckipper_account_sync_preview_prompt)
        rm -f "$items"
        echo "ACTION=[$action]"'
    [[ "$output" == *"ACTION=[apply]"* ]]
}
