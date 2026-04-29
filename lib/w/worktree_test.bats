#!/usr/bin/env bats
# Module-level tests for lib/w/worktree.zsh.
# Covers list (empty), remove (missing path), and create (project not found).

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export W_PROJECTS_DIR="$TMP_HOME/Developer"
    export W_WORKTREES_DIR="$TMP_HOME/Developer/.worktrees"
    mkdir -p "$W_PROJECTS_DIR" "$W_WORKTREES_DIR"
}

teardown() {
    teardown_isolated_env
}

# Helper: source worktree.zsh (and its utils dep) then run zsh_cmd.
_run_worktree() {
    local zsh_cmd="$1"
    run env HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        W_PROJECTS_DIR="$W_PROJECTS_DIR" \
        W_WORKTREES_DIR="$W_WORKTREES_DIR" \
        W_ACTIVE_ACCOUNT="${W_ACTIVE_ACCOUNT:-test}" \
        W_ACTIVE_CONFIG_DIR="${W_ACTIVE_CONFIG_DIR:-$TMP_HOME/.claude-test}" \
        W_FLAG_FORCE="${W_FLAG_FORCE:-false}" \
        PATH="$PATH" \
        zsh -c "
            source \"$REPO_ROOT/lib/core/utils.zsh\"
            source \"$REPO_ROOT/lib/core/registry.zsh\"
            source \"$REPO_ROOT/lib/w/worktree.zsh\"
            $zsh_cmd
        "
}

@test "_w_list_worktrees prints header and exits 0 when worktrees dir is empty" {
    _run_worktree "_w_list_worktrees"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Worktrees" ]]
}

@test "_w_remove_worktree fails when worktree path does not exist" {
    _run_worktree "_w_remove_worktree myapp nonexistent-branch"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not found" || "$output" =~ "Worktree" ]]
}

@test "_w_create_worktree fails when project directory does not exist" {
    _run_worktree "_w_create_worktree nosuchproject feature-x"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not found" || "$output" =~ "Project" ]]
}
