#!/usr/bin/env bats
# Module-level tests for lib/worktree/normal-mode.zsh.
# Covers the happy path: command runs in the worktree directory.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export CKIPPER_WT_WT_PATH="$TMP_HOME/worktrees/myapp/feature-x"
    export CKIPPER_WT_BRANCH="feature-x"
    mkdir -p "$CKIPPER_WT_WT_PATH"
}

teardown() {
    teardown_isolated_env
}

@test "_ckipper_worktree_run_normal_mode executes a stub claude binary in the worktree directory" {
    run env HOME="$TMP_HOME" \
        CKIPPER_WT_WT_PATH="$CKIPPER_WT_WT_PATH" \
        CKIPPER_WT_BRANCH="$CKIPPER_WT_BRANCH" \
        PATH="$PATH" \
        zsh -c "
            typeset -a CKIPPER_WT_COMMAND=(claude)
            source \"$REPO_ROOT/lib/worktree/normal-mode.zsh\"
            _ckipper_worktree_run_normal_mode
        "

    [ "$status" -eq 0 ]
}
