#!/usr/bin/env bats
# Module-level tests for lib/worktree/dispatcher.zsh.
# Verifies routing, help, and fuzzy-suggest behaviour.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: run dispatcher in a zsh subshell with all its dependencies sourced
# and named subcommand handlers stubbed.
_run_dispatch() {
    run env HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "
            source \"$REPO_ROOT/lib/core/fuzzy.zsh\"
            source \"$REPO_ROOT/lib/core/style.zsh\"
            source \"$REPO_ROOT/lib/core/help.zsh\"
            source \"$REPO_ROOT/lib/worktree/args.zsh\"
            source \"$REPO_ROOT/lib/worktree/dispatcher.zsh\"
            _ckipper_worktree_run() { echo 'STUB-RUN' \"\$@\"; }
            _ckipper_worktree_list_worktrees() { echo 'STUB-LIST'; }
            _ckipper_worktree_remove_worktree() { echo 'STUB-RM' \"\$@\"; }
            _ckipper_worktree_build_image() { echo 'STUB-REBUILD'; }
            _ckipper_worktree_dispatch $*
        "
}

@test "dispatch routes 'list' to _ckipper_worktree_list_worktrees" {
    _run_dispatch list

    [ "$status" -eq 0 ]
    [ "$output" = "STUB-LIST" ]
}

@test "dispatch routes 'run myproj feat' to _ckipper_worktree_run" {
    _run_dispatch run myproj feat

    [ "$status" -eq 0 ]
    [[ "$output" =~ "STUB-RUN myproj feat" ]]
}

@test "dispatch routes 'rm myproj feat' to _ckipper_worktree_remove_worktree" {
    _run_dispatch rm myproj feat

    [ "$status" -eq 0 ]
    [[ "$output" =~ "STUB-RM myproj feat" ]]
}

@test "dispatch 'rm --force myproj feat' passes positionals through" {
    _run_dispatch rm --force myproj feat

    [ "$status" -eq 0 ]
    [[ "$output" =~ "STUB-RM myproj feat" ]]
}

@test "dispatch 'rm' with no args prints help and returns 1" {
    _run_dispatch rm

    [ "$status" -ne 0 ]
    [[ "$output" =~ "ckipper worktree rm" ]]
}

@test "dispatch routes 'rebuild-image' to _ckipper_worktree_build_image" {
    _run_dispatch rebuild-image

    [ "$status" -eq 0 ]
    [ "$output" = "STUB-REBUILD" ]
}

@test "dispatch short-circuits 'run --help'" {
    _run_dispatch run --help

    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper worktree run" ]]
    [[ "$output" =~ "--docker" ]]
}

@test "dispatch with no args prints overview help" {
    _run_dispatch

    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper worktree" ]]
    [[ "$output" =~ "Short form" ]]
}

@test "dispatch fuzzy-suggests on close typo" {
    _run_dispatch lst

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Unknown command: 'lst'. Did you mean: 'list'?" ]]
}

@test "dispatch prints bare unknown-command line on far-off typo" {
    _run_dispatch xyzzy

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Unknown command: 'xyzzy'." ]]
    [[ ! "$output" =~ "Did you mean" ]]
}
