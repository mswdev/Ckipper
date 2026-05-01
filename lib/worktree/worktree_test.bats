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

@test "_ckipper_worktree_resolve_base_branch resolves origin/HEAD when set to main" {
    cd "$BATS_TEST_TMPDIR"
    git init -q origin && (
        cd origin && git checkout -qb main
        echo "x" > a && git add a
        git -c user.email=t@t -c user.name=t commit -qm i
    )
    git clone -q origin work
    cd work
    git remote set-head origin --auto >/dev/null 2>&1 || true
    run zsh -c "source \"$REPO_ROOT/lib/worktree/worktree.zsh\"; _ckipper_worktree_resolve_base_branch"
    [ "$status" -eq 0 ]
    [ "$output" = "main" ]
}

@test "_ckipper_worktree_resolve_base_branch falls back to CKIPPER_DEFAULT_BRANCH" {
    cd "$BATS_TEST_TMPDIR"
    git init -q work_no_origin
    cd work_no_origin
    run env CKIPPER_DEFAULT_BRANCH=stage zsh -c "source \"$REPO_ROOT/lib/worktree/worktree.zsh\"; _ckipper_worktree_resolve_base_branch"
    [ "$status" -eq 0 ]
    [ "$output" = "stage" ]
}

@test "_ckipper_worktree_resolve_base_branch falls back to develop when nothing else is set" {
    cd "$BATS_TEST_TMPDIR"
    git init -q work_naked
    cd work_naked
    run env -u CKIPPER_DEFAULT_BRANCH zsh -c "source \"$REPO_ROOT/lib/worktree/worktree.zsh\"; _ckipper_worktree_resolve_base_branch"
    [ "$status" -eq 0 ]
    [ "$output" = "develop" ]
}

@test "_ckipper_worktree_post_create_setup runs the configured dep install command" {
    cd "$BATS_TEST_TMPDIR"
    mkdir wt && cd wt && git init -q
    run env HOME="$BATS_TEST_TMPDIR" \
            CKIPPER_DEP_INSTALL_CMD="echo INSTALLED" \
            CKIPPER_WT_PATH="$PWD" \
            CKIPPER_PROJECTS_DIR="$BATS_TEST_TMPDIR" \
        zsh -c "source \"$REPO_ROOT/lib/worktree/worktree.zsh\"; _ckipper_worktree_post_create_setup wt"
    [[ "$output" =~ "INSTALLED" ]]
}

@test "_ckipper_worktree_post_create_setup skips deps when CKIPPER_DEP_INSTALL_CMD is empty" {
    cd "$BATS_TEST_TMPDIR"
    mkdir wt2 && cd wt2 && git init -q
    run env HOME="$BATS_TEST_TMPDIR" \
            CKIPPER_DEP_INSTALL_CMD="" \
            CKIPPER_WT_PATH="$PWD" \
            CKIPPER_PROJECTS_DIR="$BATS_TEST_TMPDIR" \
        zsh -c "source \"$REPO_ROOT/lib/worktree/worktree.zsh\"; _ckipper_worktree_post_create_setup wt2"
    [[ ! "$output" =~ "Installing dependencies" ]]
}
