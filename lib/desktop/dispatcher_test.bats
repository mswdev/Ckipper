#!/usr/bin/env bats
# Module-level tests for lib/desktop/dispatcher.zsh.
# Verifies routing, help, macOS-guard, and fuzzy-suggest behaviour.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export _CKIPPER_TEST_OSTYPE="darwin19.0"
}

teardown() {
    teardown_isolated_env
}

# Helper: run desktop dispatcher in a zsh subshell with all its dependencies
# (fuzzy.zsh, style.zsh, help.zsh, desktop help.zsh, desktop dispatcher.zsh)
# sourced and the subcommand handlers stubbed so routing can be exercised
# independently of feature code.
_run_dispatch() {
    run env HOME="$TMP_HOME" PATH="$PATH" _CKIPPER_TEST_OSTYPE="$_CKIPPER_TEST_OSTYPE" \
        zsh -c "
            source \"$REPO_ROOT/lib/core/fuzzy.zsh\"
            source \"$REPO_ROOT/lib/core/style.zsh\"
            source \"$REPO_ROOT/lib/core/help.zsh\"
            source \"$REPO_ROOT/lib/desktop/help.zsh\"
            source \"$REPO_ROOT/lib/desktop/dispatcher.zsh\"
            _ckipper_desktop_add()    { echo 'STUB-ADD' \"\$@\"; }
            _ckipper_desktop_list()   { echo 'STUB-LIST'; }
            _ckipper_desktop_remove() { echo 'STUB-REMOVE'; }
            _ckipper_desktop_rename() { echo 'STUB-RENAME'; }
            _ckipper_desktop_login()  { echo 'STUB-LOGIN'; }
            _ckipper_desktop_launch() { echo 'STUB-LAUNCH'; }
            _ckipper_desktop_dispatch $*
        "
}

@test "dispatch routes 'list' to _ckipper_desktop_list" {
    _run_dispatch list

    [ "$status" -eq 0 ]
    [ "$output" = "STUB-LIST" ]
}

@test "dispatch routes 'add' with arguments to _ckipper_desktop_add" {
    _run_dispatch add work

    [ "$status" -eq 0 ]
    [[ "$output" =~ "STUB-ADD" ]]
}

@test "dispatch short-circuits 'add --help' to per-subcommand help" {
    _run_dispatch add --help

    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper desktop add" ]]
}

@test "dispatch short-circuits 'login -h' to per-subcommand help" {
    _run_dispatch login -h

    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper desktop login" ]]
    [[ "$output" =~ "claude://" ]]
}

@test "dispatch with no args prints overview help" {
    _run_dispatch

    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper desktop" ]]
    [[ "$output" =~ "login" ]]
    [[ "$output" =~ "Short form" ]]
}

@test "dispatch with 'help' prints overview help" {
    _run_dispatch help

    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper desktop" ]]
}

@test "dispatch suggests on typo" {
    _run_dispatch addd

    [ "$status" -ne 0 ]
    [[ "$output" =~ "add" ]] || [[ "$output" =~ "Did you mean" ]]
}

@test "dispatch refuses on non-macOS" {
    _CKIPPER_TEST_OSTYPE="linux-gnu" _run_dispatch list

    [ "$status" -ne 0 ]
    [[ "$output" =~ "macOS" ]] || [[ "$output" =~ "darwin" ]]
}
