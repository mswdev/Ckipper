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

@test "_core_account_sync_strategy_fn returns the expected naming convention" {
    run_in_zsh 'echo "$(_core_account_sync_strategy_fn mcp enumerate)"'
    [ "$status" -eq 0 ]
    [[ "$output" == "_ckipper_account_sync_mcp_enumerate" ]]
}

@test "_core_account_sync_strategy_fn handles hyphenated type ids" {
    run_in_zsh 'echo "$(_core_account_sync_strategy_fn claude-md compare)"'
    [ "$status" -eq 0 ]
    [[ "$output" == "_ckipper_account_sync_claude-md_compare" ]]
}

@test "engine sources without errors" {
    run_in_zsh 'echo OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "_core_account_sync_assert_dst_idle returns 0 when no claude running" {
    # The pgrep stub returns no matches by default in the test env.
    run env CKIPPER_DIR="$CKIPPER_DIR" TMP_HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/core/keychain.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/engine.zsh\"; \
                _core_account_sync_assert_dst_idle '$TMP_HOME/dst' false && echo OK"
    [[ "$output" == *"OK"* ]]
}

@test "_core_account_sync_assert_dst_idle returns 1 when claude is running on dst" {
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
                _core_account_sync_assert_dst_idle '$TMP_HOME/dst' false"
    [ "$status" -ne 0 ]
}

@test "_core_account_sync_assert_dst_idle bypassed by --force" {
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
                _core_account_sync_assert_dst_idle '$TMP_HOME/dst' true && echo OK"
    [[ "$output" == *"OK"* ]]
}

@test "_core_account_sync_validate_pair: rejects when source == target" {
    run_in_zsh '_core_account_sync_validate_pair personal personal'
    [ "$status" -ne 0 ]
}

@test "_core_account_sync_validate_pair: accepts distinct names" {
    run_in_zsh '_core_account_sync_validate_pair personal work && echo OK'
    [[ "$output" == *"OK"* ]]
}

@test "_core_account_sync_build_change_set walks each type's enumerate + compare" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"mcpServers":{"github":{"command":"x"}}}' > "$src/.claude.json"
    echo '{"mcpServers":{}}' > "$dst/.claude.json"
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/registry.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/engine.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/structured.zsh\"; \
                _core_account_sync_build_change_set '$src' '$dst' src dst mcp"
    [[ "$output" == *"mcp"$'\t'"github"$'\t'* ]]
    [[ "$output" == *"new"* ]]
}

@test "_core_account_sync_apply_target writes changes and records manifest" {
    local src="$TMP_HOME/src" dst="$TMP_HOME/dst"
    mkdir -p "$src" "$dst"
    echo '{"mcpServers":{"github":{"command":"x"}}}' > "$src/.claude.json"
    echo '{"mcpServers":{}}' > "$dst/.claude.json"
    run env HOME="$HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        TMP_HOME="$TMP_HOME" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/registry.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/backup.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/engine.zsh\"; \
                source \"$REPO_ROOT/lib/account/sync/strategies/structured.zsh\"; \
                printf 'mcp\tgithub\tgithub\tnew\n' \
                  | _core_account_sync_apply_target '$src' '$dst' src dst
                jq '.mcpServers.github.command' '$dst/.claude.json'
                ls '$dst/.ckipper-sync-backups'/*-from-src/.ckipper-sync-manifest.json"
    [[ "$output" == *'"x"'* ]]
    [[ "$output" == *".ckipper-sync-manifest.json"* ]]
}
