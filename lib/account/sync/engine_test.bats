#!/usr/bin/env bats
# Unit tests for lib/account/sync/engine.zsh skeleton.

load "${BATS_TEST_DIRNAME}/../../../tests/lib/test-helper.bash"

setup() { setup_isolated_env; }
teardown() { teardown_isolated_env; }

run_in_zsh() {
    run env CKIPPER_DIR="$CKIPPER_DIR" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/registry.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/engine.zsh\"; $*"
}

@test "_ckipper_account_sync_strategy_fn returns the expected naming convention" {
    run_in_zsh 'echo "$(_ckipper_account_sync_strategy_fn mcp enumerate)"'
    [ "$status" -eq 0 ]
    [[ "$output" == "_ckipper_account_sync_mcp_enumerate" ]]
}

@test "_ckipper_account_sync_strategy_fn handles hyphenated type ids" {
    run_in_zsh 'echo "$(_ckipper_account_sync_strategy_fn claude-md compare)"'
    [ "$status" -eq 0 ]
    [[ "$output" == "_ckipper_account_sync_claude-md_compare" ]]
}

@test "engine sources without errors" {
    run_in_zsh 'echo OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "_ckipper_account_sync_assert_dst_idle returns 0 when no claude running" {
    # The pgrep stub returns no matches by default in the test env.
    run env CKIPPER_DIR="$CKIPPER_DIR" TMP_HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/core/keychain.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/engine.zsh\"; \
                _ckipper_account_sync_assert_dst_idle '$TMP_HOME/dst' false && echo OK"
    [[ "$output" == *"OK"* ]]
}

@test "_ckipper_account_sync_assert_dst_idle returns 1 when claude is running on dst" {
    # Stage a fake pgrep stub that prints a process referencing dst.
    local fake_pgrep="$TMP_HOME/bin/pgrep"
    mkdir -p "$TMP_HOME/bin"
    cat > "$fake_pgrep" <<EOH
#!/usr/bin/env bash
echo "12345 claude --config-dir $TMP_HOME/dst"
EOH
    chmod +x "$fake_pgrep"
    run env PATH="$TMP_HOME/bin:$PATH" CKIPPER_DIR="$CKIPPER_DIR" TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/core/keychain.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/engine.zsh\"; \
                _ckipper_account_sync_assert_dst_idle '$TMP_HOME/dst' false"
    [ "$status" -ne 0 ]
}

@test "_ckipper_account_sync_assert_dst_idle bypassed by --force" {
    local fake_pgrep="$TMP_HOME/bin/pgrep"
    mkdir -p "$TMP_HOME/bin"
    cat > "$fake_pgrep" <<EOH
#!/usr/bin/env bash
echo "12345 claude --config-dir $TMP_HOME/dst"
EOH
    chmod +x "$fake_pgrep"
    run env PATH="$TMP_HOME/bin:$PATH" CKIPPER_DIR="$CKIPPER_DIR" TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/core/keychain.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/engine.zsh\"; \
                _ckipper_account_sync_assert_dst_idle '$TMP_HOME/dst' true && echo OK"
    [[ "$output" == *"OK"* ]]
}

@test "_ckipper_account_sync_validate_pair: rejects when source == target" {
    run_in_zsh '_ckipper_account_sync_validate_pair personal personal'
    [ "$status" -ne 0 ]
}

@test "_ckipper_account_sync_validate_pair: accepts distinct names" {
    run_in_zsh '_ckipper_account_sync_validate_pair personal work && echo OK'
    [[ "$output" == *"OK"* ]]
}

@test "_ckipper_account_sync_build_change_set walks each type's enumerate + compare" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"mcpServers":{"github":{"command":"x"}}}' > "$src/.claude.json"
    echo '{"mcpServers":{}}' > "$dst/.claude.json"
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/registry.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/engine.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/_shared.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/structured.zsh\"; \
                _ckipper_account_sync_build_change_set '$src' '$dst' src dst mcp"
    [[ "$output" == *"mcp"$'\t'"github"$'\t'* ]]
    [[ "$output" == *"new"* ]]
}

@test "_ckipper_account_sync_build_summaries dispatches each type's _summary fn" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"mcpServers":{"github":{"command":"new"}}}' > "$src/.claude.json"
    echo '{"mcpServers":{"github":{"command":"old"}}}' > "$dst/.claude.json"
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/registry.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/engine.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/_shared.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/structured.zsh\"; \
                printf 'mcp\tgithub\tgithub\toverwrite\n' \
                  | _ckipper_account_sync_build_summaries '$src' '$dst' src dst"
    [[ "$output" == *"mcp"$'\t'"github"$'\t'*"overwrite"* ]]
    [[ "$output" == *"server config changed"* ]]
}

@test "_ckipper_account_sync_build_summaries skips unchanged rows" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"mcpServers":{}}' > "$src/.claude.json"
    echo '{"mcpServers":{}}' > "$dst/.claude.json"
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/registry.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/engine.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/_shared.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/structured.zsh\"; \
                printf 'mcp\tunchanged-srv\tunchanged-srv\tunchanged\n' \
                  | _ckipper_account_sync_build_summaries '$src' '$dst' src dst | wc -l | tr -d ' '"
    [[ "$output" == *"0"* ]]
}

@test "_ckipper_account_sync_apply_target rolls back via manifest after mid-write failure" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"mcpServers":{"github":{"command":"new"}}}' > "$src/.claude.json"
    echo '{"mcpServers":{"github":{"command":"old"}},"keep":"this"}' > "$dst/.claude.json"
    # Stage a fake apply that backs up + then fails — simulates a mid-write crash.
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/registry.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/backup.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/engine.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/_shared.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/structured.zsh\"; \
                # Override mcp_apply to simulate a crashing strategy.
                _ckipper_account_sync_mcp_apply() {
                    _ckipper_account_sync_backup_file \"\$4\" \"\$2/.claude.json\" \".claude.json\"
                    echo 'corrupt-mid-write' > \"\$2/.claude.json\"
                    return 1
                }
                printf 'mcp\tgithub\tgithub\toverwrite\n' \
                  | _ckipper_account_sync_apply_target '$src' '$dst' src dst
                # Rollback should have restored the original.
                jq -r '.mcpServers.github.command' '$dst/.claude.json' 2>&1
                jq -r '.keep' '$dst/.claude.json' 2>&1"
    [[ "$output" == *"old"* ]]
    [[ "$output" == *"this"* ]]
}

@test "_ckipper_account_sync_apply_target writes changes and records manifest" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"mcpServers":{"github":{"command":"x"}}}' > "$src/.claude.json"
    echo '{"mcpServers":{}}' > "$dst/.claude.json"
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/registry.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/backup.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/engine.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/_shared.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/structured.zsh\"; \
                printf 'mcp\tgithub\tgithub\tnew\n' \
                  | _ckipper_account_sync_apply_target '$src' '$dst' src dst
                jq '.mcpServers.github.command' '$dst/.claude.json'
                ls '$dst/.ckipper-sync-backups'/*-from-src/.ckipper-sync-manifest.json"
    [[ "$output" == *'"x"'* ]]
    [[ "$output" == *".ckipper-sync-manifest.json"* ]]
}

# Bug E: change_status="new" (the SUB-KEY is new) used to be conflated with
# op="create" (the FILE didn't exist). When a user added a new MCP server
# to a destination that already had .claude.json with unrelated servers,
# the manifest recorded op=create, and rollback rm-rf'd the entire file —
# wiping unrelated servers. The fix derives op from file existence at apply
# time, so this scenario records op=overwrite and rollback restores from
# backup instead of deleting.
@test "apply_one records op=overwrite when destination file exists pre-apply (Bug E)" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"mcpServers":{"github":{"command":"x"}}}' > "$src/.claude.json"
    echo '{"mcpServers":{"existing":{"command":"y"}},"keep":"this"}' > "$dst/.claude.json"
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/registry.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/backup.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/engine.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/_shared.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/structured.zsh\"; \
                # change_status='new' but the FILE exists with unrelated content.
                printf 'mcp\tgithub\tgithub\tnew\n' \
                  | _ckipper_account_sync_apply_target '$src' '$dst' src dst
                # The manifest entry must record op=overwrite, NOT create.
                jq -r '.files[0].operation' \"\$(ls -d '$dst/.ckipper-sync-backups'/*-from-src)/.ckipper-sync-manifest.json\""
    [[ "$output" == *"overwrite"* ]]
    [[ "$output" != *"create"* ]]
}

# Bug E (companion): ensure op=create still fires when the file is genuinely absent.
@test "apply_one records op=create when destination file is absent pre-apply (Bug E)" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"mcpServers":{"github":{"command":"x"}}}' > "$src/.claude.json"
    # No .claude.json on dst — file genuinely doesn't exist.
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/registry.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/backup.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/engine.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/_shared.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/structured.zsh\"; \
                printf 'mcp\tgithub\tgithub\tnew\n' \
                  | _ckipper_account_sync_apply_target '$src' '$dst' src dst
                jq -r '.files[0].operation' \"\$(ls -d '$dst/.ckipper-sync-backups'/*-from-src)/.ckipper-sync-manifest.json\""
    [[ "$output" == *"create"* ]]
}

# Bug E end-to-end: rollback after a "new sub-key into existing file" sync
# must preserve the destination file's other content.
@test "rollback after new-sub-key sync preserves unrelated dst data (Bug E)" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"mcpServers":{"github":{"command":"x"}}}' > "$src/.claude.json"
    echo '{"mcpServers":{"existing":{"command":"y"}},"keep":"this"}' > "$dst/.claude.json"
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/registry.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/backup.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/engine.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/_shared.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/structured.zsh\"; \
                printf 'mcp\tgithub\tgithub\tnew\n' \
                  | _ckipper_account_sync_apply_target '$src' '$dst' src dst
                # Sync succeeded; now run undo via rollback_target.
                backup_dir=\$(ls -d '$dst/.ckipper-sync-backups'/*-from-src)
                _ckipper_account_sync_rollback_target \"\$backup_dir\" '$dst'
                # The file MUST still exist with the original content intact.
                [[ -e '$dst/.claude.json' ]] && echo FILE_PRESENT || echo FILE_DELETED
                jq -r '.keep' '$dst/.claude.json'
                jq -r '.mcpServers | keys | sort | join(\",\")' '$dst/.claude.json'"
    [[ "$output" == *"FILE_PRESENT"* ]]
    [[ "$output" == *"this"* ]]
    [[ "$output" == *"existing"* ]]
    [[ "$output" != *"github"* ]]
}
