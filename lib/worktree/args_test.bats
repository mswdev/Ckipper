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
