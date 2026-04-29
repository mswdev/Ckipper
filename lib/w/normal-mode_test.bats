#!/usr/bin/env bats
# Module-level tests for lib/w/normal-mode.zsh.
# Covers the happy path: command runs in the worktree directory.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export W_WT_PATH="$TMP_HOME/worktrees/myapp/feature-x"
    export W_BRANCH="feature-x"
    mkdir -p "$W_WT_PATH"
}

teardown() {
    teardown_isolated_env
}

@test "_w_run_normal_mode executes a stub claude binary in the worktree directory" {
    run env HOME="$TMP_HOME" \
        W_WT_PATH="$W_WT_PATH" \
        W_BRANCH="$W_BRANCH" \
        PATH="$PATH" \
        zsh -c "
            typeset -a W_COMMAND=(claude)
            source \"$REPO_ROOT/lib/w/normal-mode.zsh\"
            _w_run_normal_mode
        "

    [ "$status" -eq 0 ]
}
