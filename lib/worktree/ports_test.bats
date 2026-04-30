#!/usr/bin/env bats
# Module-level tests for lib/worktree/ports.zsh.
# Covers _ckipper_worktree_bind_port success path and fallback when ports are busy.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    # Default: lsof stub treats all ports as free (exit 1 = not in use).
    export LSOF_STUB_BUSY=""
}

teardown() {
    teardown_isolated_env
}

# Helper: source ports.zsh and run a ports expression.
_run_ports() {
    local zsh_cmd="$1"
    run env HOME="$TMP_HOME" PATH="$PATH" \
        LSOF_STUB_BUSY="${LSOF_STUB_BUSY:-}" \
        zsh -c "
            source \"$REPO_ROOT/lib/worktree/ports.zsh\"
            typeset -a W_DOCKER_ARGS=()
            typeset -a W_RESOLVED_PORTS=()
            $zsh_cmd
        "
}

@test "_ckipper_worktree_bind_port appends a -p flag to W_DOCKER_ARGS when port is free" {
    _run_ports '_ckipper_worktree_bind_port 3000; print -r -- "${W_DOCKER_ARGS[*]}"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "-p 127.0.0.1:3000:3000" ]]
}

@test "_ckipper_worktree_bind_port logs a warning when all fallback ports are busy" {
    # Mark every port from 3000 through 3009 as busy in the lsof stub.
    export LSOF_STUB_BUSY="3000 3001 3002 3003 3004 3005 3006 3007 3008 3009"

    _run_ports '_ckipper_worktree_bind_port 3000'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "no available host port" ]]
}
