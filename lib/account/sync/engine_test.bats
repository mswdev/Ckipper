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
