#!/usr/bin/env bats
# Module-level tests for lib/core/help.zsh.
# help.zsh wraps _core_style_header (from style.zsh) and prints body lines.
# Like style.zsh, it relies on zsh-only constructs upstream, so every assertion
# spawns a zsh subshell that sources both files (matching style_test.bats).

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: source style.zsh + help.zsh in zsh and run zsh_cmd.
# Forwards CKIPPER_FORCE_COLOR / NO_COLOR explicitly so the upstream color
# decision in style.zsh stays deterministic under bats `run` (non-TTY).
_run_help() {
    local zsh_cmd="$1"
    run env CKIPPER_FORCE_COLOR="${CKIPPER_FORCE_COLOR:-}" \
        NO_COLOR="${NO_COLOR:-}" \
        PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/core/style.zsh\"; source \"$REPO_ROOT/lib/core/help.zsh\"; $zsh_cmd"
}

@test "_core_help_render emits Synopsis / Description / Args sections plus title" {
    _run_help '_core_help_render "ckipper foo bar" "Synopsis: ck foo" "Description: does the foo." "Args:" "  <baz>  the baz"'

    [ "$status" -eq 0 ]
    [[ "$output" == *"ckipper foo bar"* ]]
    [[ "$output" == *"Synopsis"* ]]
    [[ "$output" == *"Description"* ]]
    [[ "$output" == *"Args"* ]]
}

@test "_core_help_render handles empty body gracefully" {
    _run_help '_core_help_render "ckipper foo"'

    [ "$status" -eq 0 ]
    [[ "$output" == *"ckipper foo"* ]]
}

@test "_core_help_render preserves leading whitespace in body lines" {
    _run_help '_core_help_render "ckipper foo" "  --flag  description"'

    [ "$status" -eq 0 ]
    [[ "$output" == *"  --flag  description"* ]]
}

@test "_core_help_render under NO_COLOR strips ANSI escape sequences" {
    unset CKIPPER_FORCE_COLOR
    export NO_COLOR=1

    _run_help '_core_help_render "ckipper foo" "body line"'

    [ "$status" -eq 0 ]
    [[ "$output" == *"ckipper foo"* ]]
    [[ "$output" == *"body line"* ]]
    [[ "$output" != *$'\x1b['* ]]
}
