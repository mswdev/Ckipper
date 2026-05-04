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

# Regression: the rm-recursive guard required BOTH `r` AND `f` flags
# (regex `r[a-zA-Z]*f` or `f[a-zA-Z]*r`), so `rm -r /home/user/important`
# bypassed the check. With --dangerously-skip-permissions this could wipe
# arbitrary user state. Now the guard requires *either* recursive flag.
@test "bash-guardrails blocks rm -r without -f on a user path" {
    _run_guardrails "rm -r /home/user/important-files"

    [ "$status" -eq 2 ]
    [[ "$output" =~ "Blocked" ]]
}

@test "bash-guardrails blocks rm -R (capital recursive flag)" {
    _run_guardrails "rm -R /home/user/important-files"

    [ "$status" -eq 2 ]
    [[ "$output" =~ "Blocked" ]]
}

@test "bash-guardrails blocks rm --recursive on a user path" {
    _run_guardrails "rm --recursive /home/user/important-files"

    [ "$status" -eq 2 ]
    [[ "$output" =~ "Blocked" ]]
}

@test "bash-guardrails still allows rm -rf on a build-artifact dir" {
    _run_guardrails "rm -rf node_modules"

    [ "$status" -eq 0 ]
}

# Regression: `\b` is a word/non-word boundary. In `--force-with-lease`,
# `force` is followed by `-` (non-word), so `\b` fired and the previous
# regex `git\s+push\s+.*--force\b` matched `--force-with-lease` — the
# very replacement the error message tells the user to switch to. Now
# the right side is anchored against whitespace or end-of-string, so
# `--force-with-lease` passes through.
@test "bash-guardrails allows git push --force-with-lease (the recommended replacement)" {
    _run_guardrails "git push origin main --force-with-lease"

    [ "$status" -eq 0 ]
}

@test "bash-guardrails still blocks git push --force" {
    _run_guardrails "git push origin main --force"

    [ "$status" -eq 2 ]
    [[ "$output" =~ "force" ]]
}

@test "bash-guardrails still blocks git push -f" {
    _run_guardrails "git push -f origin main"

    [ "$status" -eq 2 ]
    [[ "$output" =~ "force" ]]
}
