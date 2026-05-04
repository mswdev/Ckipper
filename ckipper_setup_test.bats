#!/usr/bin/env bats
# Top-level dispatcher tests for the `setup` namespace routing.
#
# Verifies that `ckipper setup --help` reaches the dispatcher, that `setup`
# is listed by `ckipper help`, and that the completion-version sentinel + the
# new source block correctly wire `lib/setup/dispatcher.zsh` into ckipper.zsh.
#
# ckipper.zsh is zsh-only; bats runs under bash, so each test spawns a zsh
# subprocess via run_ckipper().

load "${BATS_TEST_DIRNAME}/tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    mkdir -p "$CKIPPER_DIR/docker"
    : >"$CKIPPER_DIR/docker/ckipper-config.zsh"
    cat >"$CKIPPER_REGISTRY" <<'JSON'
{"version":2,"default":null,"accounts":{}}
JSON
}

teardown() {
    teardown_isolated_env
}

@test "ckipper setup --help prints setup help" {
    run_ckipper setup --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper setup" ]]
    [[ "$output" =~ "interactive wizard" ]]
}

@test "ckipper setup -h is equivalent to --help" {
    run_ckipper setup -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper setup" ]]
}

@test "ckipper help mentions setup as a top-level command" {
    run_ckipper help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper setup" ]]
}

@test "ckipper unknown command does not get routed to setup" {
    # `setp` is close enough to `setup` for the fuzzy-match suggestion to
    # mention setup, but it MUST NOT exit 0 — that would mean the dispatcher
    # silently swallowed an unknown command.
    run_ckipper setp
    [ "$status" -ne 0 ]
}
