#!/usr/bin/env bats
# Module-level tests for lib/worktree/worktree.zsh.
# Covers list (empty), remove (missing path), and create (project not found).

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export CKIPPER_PROJECTS_DIR="$TMP_HOME/Developer"
    export CKIPPER_WORKTREES_DIR="$TMP_HOME/Developer/.worktrees"
    mkdir -p "$CKIPPER_PROJECTS_DIR" "$CKIPPER_WORKTREES_DIR"
}

teardown() {
    teardown_isolated_env
}

# Helper: source worktree.zsh (with its utils, registry, and args.zsh deps —
# args.zsh provides the validate_*_name helpers worktree.zsh now calls) then
# run zsh_cmd.
_run_worktree() {
    local zsh_cmd="$1"
    run env HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        CKIPPER_PROJECTS_DIR="$CKIPPER_PROJECTS_DIR" \
        CKIPPER_WORKTREES_DIR="$CKIPPER_WORKTREES_DIR" \
        CKIPPER_WT_ACTIVE_ACCOUNT="${CKIPPER_WT_ACTIVE_ACCOUNT:-test}" \
        CKIPPER_WT_ACTIVE_CONFIG_DIR="${CKIPPER_WT_ACTIVE_CONFIG_DIR:-$TMP_HOME/.claude-test}" \
        CKIPPER_WT_FLAG_FORCE="${CKIPPER_WT_FLAG_FORCE:-false}" \
        PATH="$PATH" \
        zsh -c "
            source \"$REPO_ROOT/lib/core/utils.zsh\"
            source \"$REPO_ROOT/lib/core/registry.zsh\"
            source \"$REPO_ROOT/lib/worktree/args.zsh\"
            source \"$REPO_ROOT/lib/worktree/worktree.zsh\"
            $zsh_cmd
        "
}

@test "_ckipper_worktree_list_worktrees prints header and exits 0 when worktrees dir is empty" {
    _run_worktree "_ckipper_worktree_list_worktrees"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Worktrees" ]]
}

@test "_ckipper_worktree_remove_worktree fails when worktree path does not exist" {
    _run_worktree "_ckipper_worktree_remove_worktree myapp nonexistent-branch"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not found" || "$output" =~ "Worktree" ]]
}

@test "_ckipper_worktree_create_worktree fails when project directory does not exist" {
    _run_worktree "_ckipper_worktree_create_worktree nosuchproject feature-x"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not found" || "$output" =~ "Project" ]]
}

@test "_ckipper_worktree_create_worktree rejects a branch name starting with --" {
    _run_worktree '_ckipper_worktree_create_worktree myapp "--upload-pack=/tmp/x"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid branch name" ]]
}

@test "_ckipper_worktree_create_worktree rejects a project path with a .. component" {
    _run_worktree '_ckipper_worktree_create_worktree "../../etc" feature-x'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid project path" ]]
}

@test "_ckipper_worktree_remove_worktree rejects a branch name starting with -" {
    _run_worktree '_ckipper_worktree_remove_worktree myapp "-h"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid branch name" ]]
}

@test "_ckipper_worktree_remove_worktree rejects a project path with shell metacharacters" {
    _run_worktree '_ckipper_worktree_remove_worktree "myorg/app;rm" feature-x'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid project path" ]]
}
