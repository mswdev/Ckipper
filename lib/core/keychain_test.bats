#!/usr/bin/env bats
# Module-level tests for lib/core/keychain.zsh.
# Covers validate, snapshot_with_timeout, snapshot_fallback, running_claude_processes,
# and assert_no_running_claude.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export _CKIPPER_TEST_OSTYPE="darwin19.0"
}

teardown() {
    teardown_isolated_env
}

# Helper: source keychain.zsh and run zsh_cmd.
_run_keychain() {
    local zsh_cmd="$1"
    run env HOME="$TMP_HOME" \
        _CKIPPER_TEST_OSTYPE="${_CKIPPER_TEST_OSTYPE:-darwin19.0}" \
        CKIPPER_FORCE="${CKIPPER_FORCE:-0}" \
        PGREP_STUB_MATCH="${PGREP_STUB_MATCH:-0}" \
        SECURITY_STUB_DUMP="${SECURITY_STUB_DUMP:-}" \
        PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/core/keychain.zsh\"; $zsh_cmd"
}

@test "_core_keychain_validate accepts a valid service name" {
    _run_keychain '_core_keychain_validate "Claude Code-credentials"'

    [ "$status" -eq 0 ]
}

@test "_core_keychain_validate accepts a service name with hex suffix" {
    _run_keychain '_core_keychain_validate "Claude Code-credentials-abc123"'

    [ "$status" -eq 0 ]
}

@test "_core_keychain_validate rejects an empty service name" {
    _run_keychain '_core_keychain_validate ""'

    [ "$status" -ne 0 ]
}

@test "_core_keychain_validate rejects a name with wrong prefix" {
    _run_keychain '_core_keychain_validate "NotClaude-credentials"'

    [ "$status" -ne 0 ]
}

@test "_core_assert_no_running_claude passes when no Claude processes are running" {
    export PGREP_STUB_MATCH=0

    _run_keychain "_core_assert_no_running_claude"

    [ "$status" -eq 0 ]
}
