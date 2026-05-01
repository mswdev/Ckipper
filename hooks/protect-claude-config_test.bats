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

# .git/ blocking — closes the docker-mode RW bind-mount escape vector where
# Edit/Write tool calls plant hooks or git config overrides that execute on
# the host. Mirrors the bash-side coverage in bash-guardrails.sh.

@test "protect-claude-config blocks writes to /workspace/.git/config" {
    _run_protect '{"tool_input":{"file_path":"/workspace/.git/config"}}'

    [ "$status" -eq 2 ]
    [[ "$output" =~ "Blocked" ]]
    [[ "$output" =~ ".git" ]]
}

@test "protect-claude-config blocks writes to /workspace/.git/hooks/post-commit" {
    _run_protect '{"tool_input":{"file_path":"/workspace/.git/hooks/post-commit"}}'

    [ "$status" -eq 2 ]
    [[ "$output" =~ "Blocked" ]]
}

@test "protect-claude-config blocks writes to /Users/x/.git/info/attributes" {
    _run_protect '{"tool_input":{"file_path":"/Users/x/.git/info/attributes"}}'

    [ "$status" -eq 2 ]
    [[ "$output" =~ "Blocked" ]]
}

@test "protect-claude-config blocks writes to /workspace/.git/worktrees/foo/HEAD" {
    _run_protect '{"tool_input":{"file_path":"/workspace/.git/worktrees/foo/HEAD"}}'

    [ "$status" -eq 2 ]
    [[ "$output" =~ "Blocked" ]]
}

@test "protect-claude-config allows writes to /workspace/.gitignore" {
    _run_protect '{"tool_input":{"file_path":"/workspace/.gitignore"}}'

    [ "$status" -eq 0 ]
}

@test "protect-claude-config allows writes to /workspace/.github/workflows/ci.yml" {
    _run_protect '{"tool_input":{"file_path":"/workspace/.github/workflows/ci.yml"}}'

    [ "$status" -eq 0 ]
}

@test "protect-claude-config allows writes to differently named .git-hooks-config dir" {
    _run_protect '{"tool_input":{"file_path":"/workspace/some/.git-hooks-config/x"}}'

    [ "$status" -eq 0 ]
}

@test "protect-claude-config allows writes to a path with 'git' as a path segment" {
    _run_protect '{"tool_input":{"file_path":"/workspace/file/with/git/in/path/file.txt"}}'

    [ "$status" -eq 0 ]
}
