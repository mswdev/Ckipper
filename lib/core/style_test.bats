#!/usr/bin/env bats
# Module-level tests for lib/core/style.zsh.
# style.zsh uses zsh-only constructs (typeset -gA, readonly with value), so
# every assertion spawns a zsh subshell that sources style.zsh and runs the
# function under test (matching the pattern in config_test.bats and
# registry_test.bats).

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: source style.zsh in zsh and run zsh_cmd.
# Forwards CKIPPER_FORCE_COLOR / NO_COLOR explicitly so tests can pin the
# decision deterministically — bats captures stdout, so the TTY check ([[ -t 1 ]])
# is always false inside `run`.
_run_style() {
    local zsh_cmd="$1"
    run env CKIPPER_FORCE_COLOR="${CKIPPER_FORCE_COLOR:-}" \
        NO_COLOR="${NO_COLOR:-}" \
        PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/core/style.zsh\"; $zsh_cmd"
}

@test "_core_style_color emits ANSI escape when CKIPPER_FORCE_COLOR=1" {
    export CKIPPER_FORCE_COLOR=1

    _run_style "_core_style_color red hello"

    [ "$status" -eq 0 ]
    [[ "$output" == $'\x1b[31m'*$'\x1b[0m' ]]
    [[ "$output" == *"hello"* ]]
}

@test "_core_style_color is bypassed when NO_COLOR is set" {
    unset CKIPPER_FORCE_COLOR
    export NO_COLOR=1

    _run_style "_core_style_color red hello"

    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "_core_style_color: CKIPPER_FORCE_COLOR overrides NO_COLOR" {
    export CKIPPER_FORCE_COLOR=1
    export NO_COLOR=1

    _run_style "_core_style_color red hello"

    [ "$status" -eq 0 ]
    [[ "$output" == $'\x1b[31m'*$'\x1b[0m' ]]
}

@test "_core_style_badge in green emits PASS label and color code 32" {
    export CKIPPER_FORCE_COLOR=1

    _run_style "_core_style_badge PASS green"

    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *$'\x1b[32m'* ]]
}

@test "_core_style_badge plain when color disabled" {
    unset CKIPPER_FORCE_COLOR
    export NO_COLOR=1

    _run_style "_core_style_badge PASS green"

    [ "$status" -eq 0 ]
    [ "$output" = "[PASS]" ]
}

@test "_core_style_divider emits a non-empty line containing the box-draw character" {
    _run_style "_core_style_divider"

    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [[ "$output" == *"─"* ]]
}

@test "_core_style_header outputs the title between two dividers" {
    _run_style '_core_style_header "Setup"'

    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 3 ]
    [[ "${lines[0]}" == *"─"* ]]
    [[ "${lines[1]}" == *"Setup"* ]]
    [[ "${lines[2]}" == *"─"* ]]
}

@test "_core_style_table renders headers and rows with both columns present" {
    _run_style "printf 'a|b\nc|d\n' | _core_style_table HEADER1 HEADER2"

    [ "$status" -eq 0 ]
    [[ "$output" == *"HEADER1"* ]]
    [[ "$output" == *"HEADER2"* ]]
    [[ "$output" == *"a"* ]]
    [[ "$output" == *"b"* ]]
    [[ "$output" == *"c"* ]]
    [[ "$output" == *"d"* ]]
}
