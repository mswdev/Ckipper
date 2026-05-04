#!/usr/bin/env bats
# Module-level tests for lib/core/fuzzy.zsh.
# Tests _core_fuzzy_suggest observable behaviour.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: source fuzzy.zsh and run a command in a zsh subshell.
_run_fuzzy() {
    local zsh_cmd="$1"
    run env HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/core/fuzzy.zsh\"; $zsh_cmd"
}

@test "_core_fuzzy_suggest returns exact match unchanged" {
    _run_fuzzy "_core_fuzzy_suggest list list add remove"
    [ "$status" -eq 0 ]
    [ "$output" = "list" ]
}

@test "_core_fuzzy_suggest returns close single-letter typo" {
    _run_fuzzy "_core_fuzzy_suggest lst list add remove"
    [ "$status" -eq 0 ]
    [ "$output" = "list" ]
}

@test "_core_fuzzy_suggest returns transposition" {
    _run_fuzzy "_core_fuzzy_suggest lsit list add remove"
    [ "$status" -eq 0 ]
    [ "$output" = "list" ]
}

@test "_core_fuzzy_suggest returns nothing for far-off input" {
    _run_fuzzy "_core_fuzzy_suggest xyzabc list add remove"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "_core_fuzzy_suggest picks the closest of multiple candidates" {
    _run_fuzzy "_core_fuzzy_suggest ad add default doctor"
    [ "$status" -eq 0 ]
    [ "$output" = "add" ]
}

@test "_core_fuzzy_suggest handles empty candidate list" {
    _run_fuzzy "_core_fuzzy_suggest anything"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
