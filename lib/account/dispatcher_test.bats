#!/usr/bin/env bats
# Module-level tests for lib/account/dispatcher.zsh.
# Verifies routing, help, and fuzzy-suggest behaviour.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: run dispatcher in a zsh subshell with all its dependencies
# (fuzzy.zsh, dispatcher.zsh) sourced and named subcommand handlers stubbed.
_run_dispatch() {
    run env HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "
            source \"$REPO_ROOT/lib/core/fuzzy.zsh\"
            source \"$REPO_ROOT/lib/account/dispatcher.zsh\"
            _ckipper_account_list() { echo 'STUB-LIST'; }
            _ckipper_account_add() { echo 'STUB-ADD' \"\$@\"; }
            _ckipper_account_dispatch $*
        "
}

@test "dispatch routes 'list' to _ckipper_account_list" {
    _run_dispatch list

    [ "$status" -eq 0 ]
    [ "$output" = "STUB-LIST" ]
}

@test "dispatch routes 'add' with arguments to _ckipper_account_add" {
    _run_dispatch add personal

    [ "$status" -eq 0 ]
    [[ "$output" =~ "STUB-ADD personal" ]]
}

@test "dispatch short-circuits 'add --help' to per-subcommand help" {
    _run_dispatch add --help

    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper account add" ]]
    [[ "$output" =~ "--adopt" ]]
}

@test "dispatch short-circuits 'list -h' to per-subcommand help" {
    _run_dispatch list -h

    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper account list" ]]
}

@test "dispatch with no args prints overview help" {
    _run_dispatch

    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper account" ]]
    [[ "$output" =~ "Short form" ]]
}

@test "dispatch with 'help' prints overview help" {
    _run_dispatch help

    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper account" ]]
}

@test "dispatch fuzzy-suggests on close typo" {
    _run_dispatch lst

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Unknown command: 'lst'. Did you mean: 'list'?" ]]
    [[ "$output" =~ "ckipper account help" ]]
}

@test "dispatch prints bare unknown-command line on far-off typo" {
    _run_dispatch xyzzy

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Unknown command: 'xyzzy'." ]]
    [[ ! "$output" =~ "Did you mean" ]]
}
