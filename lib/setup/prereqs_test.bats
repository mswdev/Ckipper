#!/usr/bin/env bats
# Module-level tests for lib/setup/prereqs.zsh.
# prereqs.zsh is zsh-only (uses typeset -ga / readonly arrays), so every
# assertion spawns a zsh subshell that sources prompt.zsh + prereqs.zsh and
# runs the function under test (matching the pattern in prompt_test.bats and
# style_test.bats).
#
# CKIPPER_NO_GUM=1 forces the pure-zsh fallback path inside _core_prompt_*
# helpers so tests are deterministic regardless of whether `gum` is installed
# on the runner. The decline test pipes stdin to the zsh subshell so the
# embedded `_core_prompt_confirm` read receives "n".

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: source prompt.zsh + prereqs.zsh in zsh, optionally feed stdin, run zsh_cmd.
#
# Args: $1 — zsh command to execute; $2 — optional stdin payload.
# Side effect: populates $status / $output / $lines as with bats `run`.
_run_prereqs() {
    local zsh_cmd="$1" stdin="${2:-}"
    run env CKIPPER_NO_GUM=1 PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/core/prompt.zsh\"; source \"$REPO_ROOT/lib/setup/prereqs.zsh\"; $zsh_cmd" <<<"$stdin"
}

@test "_ckipper_setup_prereq_check_one returns 0 when tool exists" {
    _run_prereqs "_ckipper_setup_prereq_check_one ls"

    [ "$status" -eq 0 ]
}

@test "_ckipper_setup_prereq_check_one returns 1 when tool is missing" {
    _run_prereqs "_ckipper_setup_prereq_check_one fake_xyz_999"

    [ "$status" -eq 1 ]
}

@test "_ckipper_setup_prereq_list_missing prints only the missing tools" {
    _run_prereqs "_ckipper_setup_prereq_list_missing ls fake_xyz_999"

    [ "$status" -eq 0 ]
    [[ "$output" == *"fake_xyz_999"* ]]
    [[ "$output" != *"ls"* ]]
}

@test "_ckipper_setup_prereq_list_missing prints nothing when all present" {
    _run_prereqs "_ckipper_setup_prereq_list_missing ls cat sh"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "_ckipper_setup_prereq_list_missing returns 0 with no args" {
    _run_prereqs "_ckipper_setup_prereq_list_missing"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "_ckipper_setup_prereq_install_missing returns 0 with no args" {
    _run_prereqs "_ckipper_setup_prereq_install_missing"

    [ "$status" -eq 0 ]
}

@test "_ckipper_setup_prereq_install_missing returns 1 when user declines" {
    _run_prereqs "_ckipper_setup_prereq_install_missing fake_xyz_999 2>&1" "n"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing tools:"* ]]
    [[ "$output" == *"fake_xyz_999"* ]]
}

@test "_ckipper_setup_prereq_install_missing fails clearly when brew is not on PATH" {
    # Sandbox PATH so brew is not visible. /usr/bin:/bin holds zsh, command, and
    # the rest of the function's dependencies; brew lives in /opt/homebrew/bin
    # or /usr/local/bin and so is filtered out. This proves the precheck fires
    # before any brew invocation.
    run env CKIPPER_NO_GUM=1 PATH="/usr/bin:/bin" \
        zsh -c "source \"$REPO_ROOT/lib/core/prompt.zsh\"; source \"$REPO_ROOT/lib/setup/prereqs.zsh\"; _ckipper_setup_prereq_install_missing fake_xyz_999 2>&1"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Homebrew is not installed"* ]]
    [[ "$output" == *"fake_xyz_999"* ]]
}
