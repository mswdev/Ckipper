#!/usr/bin/env bats
# Module-level tests for lib/w/args.zsh.
# Verifies that _w_parse_args sets the correct W_* globals.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: source args.zsh, call _w_parse_args with provided args, then print
# the value of $1 (variable name) to stdout.
_parse_and_print() {
    local var_name="$1"; shift
    run env HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/w/args.zsh\"; _w_parse_args $*; print -r -- \"\$$var_name\""
}

@test "_w_parse_args sets W_PROJECT and W_BRANCH for bare project/branch args" {
    _parse_and_print "W_PROJECT" myapp feature-x

    [ "$status" -eq 0 ]
    [ "$output" = "myapp" ]
}

@test "_w_parse_args sets W_FLAG_RM to true for --rm flag" {
    _parse_and_print "W_FLAG_RM" --rm myapp branch

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "_w_parse_args sets W_FLAG_DOCKER to true for --docker flag" {
    _parse_and_print "W_FLAG_DOCKER" myapp feature-x --docker

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "_w_parse_args sets W_FLAG_LIST to true for --list flag" {
    _parse_and_print "W_FLAG_LIST" --list

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}
