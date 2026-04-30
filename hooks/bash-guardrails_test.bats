#!/usr/bin/env bats
# Module-level tests for hooks/bash-guardrails.sh.
# Uses CKIPPER_DOCKERENV to simulate being inside a Docker container.

load "${BATS_TEST_DIRNAME}/../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export CKIPPER_DOCKERENV="$TMP_HOME/fake-dockerenv"
    touch "$CKIPPER_DOCKERENV"
}

teardown() {
    teardown_isolated_env
}

# Helper: pipe JSON command input to the hook.
_run_guardrails() {
    local cmd="$1"
    local input_json="{\"tool_input\":{\"command\":\"$cmd\"}}"
    run env CKIPPER_DOCKERENV="$CKIPPER_DOCKERENV" \
        bash "$REPO_ROOT/hooks/bash-guardrails.sh" <<< "$input_json"
}

@test "bash-guardrails blocks rm -rf on non-build-artifact paths" {
    _run_guardrails "rm -rf /home/user/important-files"

    [ "$status" -eq 2 ]
    [[ "$output" =~ "Blocked" ]]
}

@test "bash-guardrails allows a safe read-only command" {
    _run_guardrails "ls /workspace/src"

    [ "$status" -eq 0 ]
}

@test "bash-guardrails fails closed on invalid JSON input" {
    run env CKIPPER_DOCKERENV="$CKIPPER_DOCKERENV" \
        bash "$REPO_ROOT/hooks/bash-guardrails.sh" <<< "not-json"

    [ "$status" -eq 2 ]
    [[ "$output" =~ "Error" || "$output" =~ "error" || "$output" =~ "JSON" ]]
}
