#!/usr/bin/env bats
# Module-level tests for lib/worktree/args.zsh.
# Verifies the per-subcommand parsers (_ckipper_worktree_parse_run_args,
# _ckipper_worktree_parse_rm_args) set the correct CKIPPER_WT_* globals.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: source args.zsh, call $parser with provided args, then print the
# value of $var_name to stdout.
_parse_and_print() {
    local parser="$1" var_name="$2"; shift 2
    run env HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/worktree/args.zsh\"; ${parser} $*; print -r -- \"\$${var_name}\""
}

# ── _ckipper_worktree_parse_run_args ─────────────────────────────────

@test "parse_run_args sets CKIPPER_WT_PROJECT from first positional" {
    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_PROJECT myapp feature-x

    [ "$status" -eq 0 ]
    [ "$output" = "myapp" ]
}

@test "parse_run_args sets CKIPPER_WT_BRANCH from second positional" {
    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_BRANCH myapp feature-x

    [ "$status" -eq 0 ]
    [ "$output" = "feature-x" ]
}

@test "parse_run_args sets CKIPPER_WT_FLAG_DOCKER for --docker" {
    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_FLAG_DOCKER myapp feature-x --docker

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "parse_run_args sets CKIPPER_WT_FLAG_FIREWALL for --firewall" {
    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_FLAG_FIREWALL myapp feature-x --docker --firewall

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "parse_run_args sets CKIPPER_WT_CLI_ACCOUNT for --account" {
    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_CLI_ACCOUNT myapp feature-x --account work

    [ "$status" -eq 0 ]
    [ "$output" = "work" ]
}

@test "parse_run_args defaults CKIPPER_WT_FLAG_DOCKER to false" {
    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_FLAG_DOCKER myapp feature-x

    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

# ── --no-* flags + EXPLICIT trackers ─────────────────────────────────

@test "parse_run_args --docker sets DOCKER_EXPLICIT=true (regression)" {
    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_FLAG_DOCKER_EXPLICIT myapp feature-x --docker

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "parse_run_args --no-docker sets DOCKER=false and DOCKER_EXPLICIT=true" {
    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_FLAG_DOCKER myapp feature-x --no-docker

    [ "$status" -eq 0 ]
    [ "$output" = "false" ]

    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_FLAG_DOCKER_EXPLICIT myapp feature-x --no-docker

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "parse_run_args --firewall sets FIREWALL_EXPLICIT=true (regression)" {
    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_FLAG_FIREWALL_EXPLICIT myapp feature-x --docker --firewall

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "parse_run_args --no-firewall sets FIREWALL=false and FIREWALL_EXPLICIT=true" {
    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_FLAG_FIREWALL myapp feature-x --no-firewall

    [ "$status" -eq 0 ]
    [ "$output" = "false" ]

    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_FLAG_FIREWALL_EXPLICIT myapp feature-x --no-firewall

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "parse_run_args --ssh-forward sets SSH_FORWARD=true and SSH_FORWARD_EXPLICIT=true" {
    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_FLAG_SSH_FORWARD myapp feature-x --ssh-forward

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]

    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_FLAG_SSH_FORWARD_EXPLICIT myapp feature-x --ssh-forward

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "parse_run_args --no-ssh-forward sets SSH_FORWARD=false and SSH_FORWARD_EXPLICIT=true" {
    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_FLAG_SSH_FORWARD myapp feature-x --no-ssh-forward

    [ "$status" -eq 0 ]
    [ "$output" = "false" ]

    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_FLAG_SSH_FORWARD_EXPLICIT myapp feature-x --no-ssh-forward

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "parse_run_args without docker flag leaves DOCKER_EXPLICIT=false" {
    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_FLAG_DOCKER_EXPLICIT myapp feature-x

    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "parse_run_args without ssh flag leaves SSH_FORWARD=true and SSH_FORWARD_EXPLICIT=false" {
    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_FLAG_SSH_FORWARD myapp feature-x

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]

    _parse_and_print _ckipper_worktree_parse_run_args CKIPPER_WT_FLAG_SSH_FORWARD_EXPLICIT myapp feature-x

    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

# ── _ckipper_worktree_parse_rm_args ──────────────────────────────────

@test "parse_rm_args sets CKIPPER_WT_PROJECT and CKIPPER_WT_BRANCH" {
    _parse_and_print _ckipper_worktree_parse_rm_args CKIPPER_WT_PROJECT myapp feature-x

    [ "$status" -eq 0 ]
    [ "$output" = "myapp" ]
}

@test "parse_rm_args defaults CKIPPER_WT_FLAG_FORCE to false" {
    _parse_and_print _ckipper_worktree_parse_rm_args CKIPPER_WT_FLAG_FORCE myapp feature-x

    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "parse_rm_args sets CKIPPER_WT_FLAG_FORCE for --force" {
    _parse_and_print _ckipper_worktree_parse_rm_args CKIPPER_WT_FLAG_FORCE --force myapp feature-x

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "parse_rm_args sets CKIPPER_WT_FLAG_FORCE for -f shorthand" {
    _parse_and_print _ckipper_worktree_parse_rm_args CKIPPER_WT_FLAG_FORCE -f myapp feature-x

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "parse_rm_args strips --force before consuming positionals" {
    _parse_and_print _ckipper_worktree_parse_rm_args CKIPPER_WT_PROJECT --force myapp feature-x

    [ "$status" -eq 0 ]
    [ "$output" = "myapp" ]
}

# ── _ckipper_worktree_validate_branch_name ───────────────────────────

# Helper: source args.zsh and call $validator with $candidate as its sole
# argument (passed via the env so leading dashes and special chars don't get
# mangled by the outer shell quoting). Captures combined stdout/stderr.
_run_validator() {
    local validator="$1" candidate="$2"
    run env HOME="$TMP_HOME" PATH="$PATH" CKIPPER_TEST_CANDIDATE="$candidate" \
        zsh -c "source \"$REPO_ROOT/lib/worktree/args.zsh\"; ${validator} \"\$CKIPPER_TEST_CANDIDATE\" 2>&1"
}

@test "validate_branch_name accepts a normal feature branch" {
    _run_validator _ckipper_worktree_validate_branch_name "feature/foo-bar"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "validate_branch_name rejects a name that starts with a dash" {
    _run_validator _ckipper_worktree_validate_branch_name "--upload-pack=/tmp/x"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid branch name" ]]
}

@test "validate_branch_name rejects a leading-dash short flag (-h)" {
    _run_validator _ckipper_worktree_validate_branch_name "-h"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid branch name" ]]
}

@test "validate_branch_name rejects a name with .. (path traversal)" {
    _run_validator _ckipper_worktree_validate_branch_name "feature/..foo"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid branch name" ]]
}

@test "validate_branch_name rejects an empty name" {
    _run_validator _ckipper_worktree_validate_branch_name ""

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid branch name" ]]
}

# ── _ckipper_worktree_validate_project_name ──────────────────────────

@test "validate_project_name accepts a normal namespaced project" {
    _run_validator _ckipper_worktree_validate_project_name "mswdev/ckipper"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "validate_project_name accepts a single-segment project" {
    _run_validator _ckipper_worktree_validate_project_name "myapp"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "validate_project_name rejects a path with a .. component" {
    _run_validator _ckipper_worktree_validate_project_name "../../etc"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid project path" ]]
}

@test "validate_project_name rejects a path with .. inside a segment chain" {
    _run_validator _ckipper_worktree_validate_project_name "myorg/../etc"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid project path" ]]
}

@test "validate_project_name allows .. as a substring inside a segment" {
    _run_validator _ckipper_worktree_validate_project_name "myorg/my..app"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "validate_project_name rejects a name with shell metacharacters" {
    _run_validator _ckipper_worktree_validate_project_name "myorg/app;rm"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid project path" ]]
}

@test "validate_project_name rejects a name that starts with a dash" {
    _run_validator _ckipper_worktree_validate_project_name "-rf"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid project path" ]]
}

@test "validate_project_name rejects an empty name" {
    _run_validator _ckipper_worktree_validate_project_name ""

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid project path" ]]
}
