#!/usr/bin/env bats
# Unit tests for lib/account/sync.zsh helpers.
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

# ── _ckipper_account_sync_parse_flags ─────────────────────────────────────────

@test "parse_flags sets mode_all=true when no flags given" {
    run_helper 'mode_mcp="false"; mode_settings="false"; is_dry_run="false"; mode_all="false"
        _ckipper_account_sync_parse_flags
        echo "mode_all=$mode_all"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "mode_all=true" ]]
}

@test "parse_flags sets is_dry_run=true for --dry-run flag" {
    run_helper 'mode_mcp="false"; mode_settings="false"; is_dry_run="false"; mode_all="false"
        _ckipper_account_sync_parse_flags --dry-run
        echo "is_dry_run=$is_dry_run"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "is_dry_run=true" ]]
}

@test "parse_flags sets mode_mcp=true for --mcp flag" {
    run_helper 'mode_mcp="false"; mode_settings="false"; is_dry_run="false"; mode_all="false"
        _ckipper_account_sync_parse_flags --mcp
        echo "mode_mcp=$mode_mcp"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "mode_mcp=true" ]]
}

@test "parse_flags sets mode_settings=true for --settings flag" {
    run_helper 'mode_mcp="false"; mode_settings="false"; is_dry_run="false"; mode_all="false"
        _ckipper_account_sync_parse_flags --settings "enabledPlugins"
        echo "mode_settings=$mode_settings"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "mode_settings=true" ]]
}

@test "parse_flags returns 1 and prints error for unknown flag" {
    run_helper 'mode_mcp="false"; mode_settings="false"; is_dry_run="false"; mode_all="false"
        _ckipper_account_sync_parse_flags --bogus-flag'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Unknown flag" ]]
}

# ── _ckipper_account_sync_mcp_servers ─────────────────────────────────────────

@test "sync_mcp_servers merges MCP servers into the destination claude.json" {
    local from_dir="$TMP_HOME/.claude-src"
    local to_dir="$TMP_HOME/.claude-dst"
    mkdir -p "$from_dir" "$to_dir"
    printf '{"mcpServers":{"testserver":{"command":"npx","args":["-y","test-mcp"]}}}' \
        > "$from_dir/.claude.json"
    printf '{"mcpServers":{}}' > "$to_dir/.claude.json"

    run_helper 'pending_msgs=()
        typeset -gA _CKIPPER_SYNC_CTX
        _CKIPPER_SYNC_CTX[from_dir]="'"$from_dir"'"
        _CKIPPER_SYNC_CTX[to_dir]="'"$to_dir"'"
        _CKIPPER_SYNC_CTX[dry_run]="false"
        _ckipper_account_sync_mcp_servers "dst" ""
        echo "${pending_msgs[@]}"'

    [ "$status" -eq 0 ]
    # The destination should now contain the server from the source.
    local dst_content; dst_content=$(cat "$to_dir/.claude.json")
    [[ "$dst_content" =~ "testserver" ]]
}

@test "sync_mcp_servers is a no-op in dry-run mode (no writes)" {
    local from_dir="$TMP_HOME/.claude-src"
    local to_dir="$TMP_HOME/.claude-dst"
    mkdir -p "$from_dir" "$to_dir"
    printf '{"mcpServers":{"myserver":{"command":"node","args":[]}}}' \
        > "$from_dir/.claude.json"
    printf '{"mcpServers":{}}' > "$to_dir/.claude.json"

    local before_dst; before_dst=$(cat "$to_dir/.claude.json")

    run_helper 'pending_msgs=()
        typeset -gA _CKIPPER_SYNC_CTX
        _CKIPPER_SYNC_CTX[from_dir]="'"$from_dir"'"
        _CKIPPER_SYNC_CTX[to_dir]="'"$to_dir"'"
        _CKIPPER_SYNC_CTX[dry_run]="true"
        _ckipper_account_sync_mcp_servers "dst" ""'

    [ "$status" -eq 0 ]
    # Destination must be unchanged in dry-run mode.
    local after_dst; after_dst=$(cat "$to_dir/.claude.json")
    [ "$before_dst" = "$after_dst" ]
}

# ── _ckipper_account_sync_settings_keys ───────────────────────────────────────

@test "sync_settings_keys copies matching keys from source settings.json to destination" {
    local from_dir="$TMP_HOME/.claude-src"
    local to_dir="$TMP_HOME/.claude-dst"
    mkdir -p "$from_dir" "$to_dir"
    printf '{"model":"claude-opus-4-5","enabledPlugins":["myplugin"],"other":"value"}' \
        > "$from_dir/settings.json"
    printf '{}' > "$to_dir/settings.json"

    run_helper 'pending_msgs=()
        typeset -gA _CKIPPER_SYNC_CTX
        _CKIPPER_SYNC_CTX[from_dir]="'"$from_dir"'"
        _CKIPPER_SYNC_CTX[to_dir]="'"$to_dir"'"
        _CKIPPER_SYNC_CTX[dry_run]="false"
        _ckipper_account_sync_settings_keys "src" "dst" "model,enabledPlugins"'

    [ "$status" -eq 0 ]
    local dst; dst=$(cat "$to_dir/settings.json")
    [[ "$dst" =~ "model" ]]
    [[ "$dst" =~ "enabledPlugins" ]]
    # The "other" key was not in the sync list — it must not appear in the destination.
    [[ ! "$dst" =~ '"other"' ]]
}

@test "sync_settings_keys is a no-op in dry-run mode (no writes)" {
    local from_dir="$TMP_HOME/.claude-src"
    local to_dir="$TMP_HOME/.claude-dst"
    mkdir -p "$from_dir" "$to_dir"
    printf '{"model":"claude-opus-4-5"}' > "$from_dir/settings.json"
    printf '{}' > "$to_dir/settings.json"

    local before_dst; before_dst=$(cat "$to_dir/settings.json")

    run_helper 'pending_msgs=()
        typeset -gA _CKIPPER_SYNC_CTX
        _CKIPPER_SYNC_CTX[from_dir]="'"$from_dir"'"
        _CKIPPER_SYNC_CTX[to_dir]="'"$to_dir"'"
        _CKIPPER_SYNC_CTX[dry_run]="true"
        _ckipper_account_sync_settings_keys "src" "dst" "model"'

    [ "$status" -eq 0 ]
    local after_dst; after_dst=$(cat "$to_dir/settings.json")
    [ "$before_dst" = "$after_dst" ]
}

# ── _ckipper_account_sync_print_summary ───────────────────────────────────────

@test "print_summary prints 'Synced' header and lists all pending messages" {
    run_helper 'pending_msgs=("MCP servers → dst: server1 " "Settings keys → dst: model ")
        _ckipper_account_sync_print_summary "dst" "false"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Synced" ]]
    [[ "$output" =~ "MCP servers" ]]
    [[ "$output" =~ "Settings keys" ]]
}

@test "print_summary prints 'Dry run' header in dry-run mode" {
    run_helper 'pending_msgs=("MCP servers → dst: server1 ")
        _ckipper_account_sync_print_summary "dst" "true"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Dry run" ]]
}
