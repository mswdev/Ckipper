#!/usr/bin/env bats
# Module-level tests for lib/run/dispatcher.zsh.
#
# `_ckipper_run` is a thin top-level shortcut that forwards to
# `_ckipper_worktree_run`. These tests stub the worktree handler so the
# forwarding contract can be exercised without sourcing the rest of the
# worktree namespace.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: source dispatcher.zsh in a zsh subshell with a stub
# `_ckipper_worktree_run` that echoes its args, then run the supplied command.
#
# Args: $1 — zsh command to execute after the stub + source line.
# Side effect: populates $status / $output / $lines as with bats `run`.
_run_run_dispatcher() {
    run env HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "
            _ckipper_worktree_run() { echo STUB-RUN \"\$@\"; return 0; }
            source \"$REPO_ROOT/lib/core/style.zsh\"
            source \"$REPO_ROOT/lib/core/help.zsh\"
            source \"$REPO_ROOT/lib/run/dispatcher.zsh\"
            $1
        "
}

@test "_ckipper_run forwards all args to _ckipper_worktree_run" {
    _run_run_dispatcher "_ckipper_run myorg/app feature --docker"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "STUB-RUN myorg/app feature --docker" ]]
}

@test "_ckipper_run --help prints help and does not invoke worktree run" {
    _run_run_dispatcher "_ckipper_run --help"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper run" ]]
    [[ "$output" =~ "Shortcut" ]]
    [[ ! "$output" =~ "STUB-RUN" ]]
}

@test "_ckipper_run -h is equivalent to --help" {
    _run_run_dispatcher "_ckipper_run -h"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper run" ]]
    [[ ! "$output" =~ "STUB-RUN" ]]
}
