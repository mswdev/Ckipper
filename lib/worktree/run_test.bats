#!/usr/bin/env bats
# Module-level tests for lib/worktree/run.zsh.
# Verifies the orchestration: bad arg combos, mode selection (docker vs normal).

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: run _ckipper_worktree_run in a zsh subshell with stubs for
# resolve-account, create-worktree, docker-mode, normal-mode, and help.
_run_run() {
    run env HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "
            source \"$REPO_ROOT/lib/worktree/args.zsh\"
            source \"$REPO_ROOT/lib/worktree/run.zsh\"
            _ckipper_worktree_resolve_account() { echo 'STUB-RESOLVE'; }
            _ckipper_worktree_create_worktree() { echo 'STUB-CREATE' \"\$@\"; }
            _ckipper_worktree_run_docker_mode() { echo 'STUB-DOCKER'; }
            _ckipper_worktree_run_normal_mode() { echo 'STUB-NORMAL'; }
            _ckipper_worktree_help_for() { echo \"STUB-HELP-FOR \$@\"; }
            _ckipper_worktree_run $*
        "
}

@test "run with no args prints help and exits 1" {
    _run_run

    [ "$status" -eq 1 ]
    [[ "$output" =~ "STUB-HELP-FOR run" ]]
}

@test "run with only project prints help and exits 1" {
    _run_run myproj

    [ "$status" -eq 1 ]
    [[ "$output" =~ "STUB-HELP-FOR run" ]]
}

@test "run with --firewall but no --docker exits 1 with error" {
    _run_run myproj feat --firewall

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: --firewall requires --docker" ]]
}

@test "run normal-mode happy path calls resolve, create, normal" {
    _run_run myproj feat

    [ "$status" -eq 0 ]
    [[ "$output" =~ "STUB-RESOLVE" ]]
    [[ "$output" =~ "STUB-CREATE myproj feat" ]]
    [[ "$output" =~ "STUB-NORMAL" ]]
    [[ ! "$output" =~ "STUB-DOCKER" ]]
}

@test "run docker-mode happy path calls resolve, create, docker" {
    _run_run myproj feat --docker

    [ "$status" -eq 0 ]
    [[ "$output" =~ "STUB-RESOLVE" ]]
    [[ "$output" =~ "STUB-CREATE myproj feat" ]]
    [[ "$output" =~ "STUB-DOCKER" ]]
    [[ ! "$output" =~ "STUB-NORMAL" ]]
}

@test "run docker + firewall happy path calls docker mode" {
    _run_run myproj feat --docker --firewall

    [ "$status" -eq 0 ]
    [[ "$output" =~ "STUB-DOCKER" ]]
}
