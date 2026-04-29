#!/usr/bin/env bats
# Unit tests for lib/ckipper/sync.zsh helpers.
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

# ── _ckipper_sync_parse_flags ─────────────────────────────────────────

@test "parse_flags sets mode_all=1 when no flags given" {
    run_helper 'mode_mcp=0; mode_settings=0; dry_run=0; mode_all=0
        _ckipper_sync_parse_flags
        echo "mode_all=$mode_all"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "mode_all=1" ]]
}

@test "parse_flags sets dry_run=1 for --dry-run flag" {
    run_helper 'mode_mcp=0; mode_settings=0; dry_run=0; mode_all=0
        _ckipper_sync_parse_flags --dry-run
        echo "dry_run=$dry_run"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "dry_run=1" ]]
}

@test "parse_flags sets mode_mcp=1 for --mcp flag" {
    run_helper 'mode_mcp=0; mode_settings=0; dry_run=0; mode_all=0
        _ckipper_sync_parse_flags --mcp
        echo "mode_mcp=$mode_mcp"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "mode_mcp=1" ]]
}

@test "parse_flags sets mode_settings=1 for --settings flag" {
    run_helper 'mode_mcp=0; mode_settings=0; dry_run=0; mode_all=0
        _ckipper_sync_parse_flags --settings "enabledPlugins"
        echo "mode_settings=$mode_settings"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "mode_settings=1" ]]
}

@test "parse_flags returns 1 and prints error for unknown flag" {
    run_helper 'mode_mcp=0; mode_settings=0; dry_run=0; mode_all=0
        _ckipper_sync_parse_flags --bogus-flag'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Unknown flag" ]]
}

# ── _ckipper_sync_mcp_servers ─────────────────────────────────────────

@test "sync_mcp_servers merges MCP servers into the destination claude.json" {
    local from_dir="$TMP_HOME/.claude-src"
    local to_dir="$TMP_HOME/.claude-dst"
    mkdir -p "$from_dir" "$to_dir"
    printf '{"mcpServers":{"testserver":{"command":"npx","args":["-y","test-mcp"]}}}' \
        > "$from_dir/.claude.json"
    printf '{"mcpServers":{}}' > "$to_dir/.claude.json"

    run_helper 'pending_msgs=()
        _ckipper_sync_mcp_servers "'"$from_dir"'" "dst" "'"$to_dir"'" "" "0"
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
        _ckipper_sync_mcp_servers "'"$from_dir"'" "dst" "'"$to_dir"'" "" "1"'

    [ "$status" -eq 0 ]
    # Destination must be unchanged in dry-run mode.
    local after_dst; after_dst=$(cat "$to_dir/.claude.json")
    [ "$before_dst" = "$after_dst" ]
}
