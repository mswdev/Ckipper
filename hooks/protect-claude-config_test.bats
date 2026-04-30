#!/usr/bin/env bats
# Module-level tests for hooks/protect-claude-config.sh.
# Uses CKIPPER_DOCKERENV to simulate being inside a Docker container.

load "${BATS_TEST_DIRNAME}/../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    # Create a fake .dockerenv so the Docker-only check passes.
    export CKIPPER_DOCKERENV="$TMP_HOME/fake-dockerenv"
    touch "$CKIPPER_DOCKERENV"
}

teardown() {
    teardown_isolated_env
}

# Helper: pipe JSON input to the hook and capture exit code + output.
_run_protect() {
    local input_json="$1"
    run env CKIPPER_DOCKERENV="$CKIPPER_DOCKERENV" \
        bash "$REPO_ROOT/hooks/protect-claude-config.sh" <<< "$input_json"
}

@test "protect-claude-config blocks writes to .claude/settings.json" {
    _run_protect '{"tool_input":{"file_path":"/home/user/.claude/settings.json"}}'

    [ "$status" -eq 2 ]
    [[ "$output" =~ "Blocked" ]]
}

@test "protect-claude-config allows writes to an unprotected path" {
    _run_protect '{"tool_input":{"file_path":"/home/user/projects/app/src/index.js"}}'

    [ "$status" -eq 0 ]
}

@test "protect-claude-config fails closed on invalid JSON input" {
    _run_protect "not-json"

    [ "$status" -eq 2 ]
    [[ "$output" =~ "Error" || "$output" =~ "error" || "$output" =~ "JSON" ]]
}
