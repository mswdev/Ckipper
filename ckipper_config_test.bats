#!/usr/bin/env bats
# Top-level dispatcher tests for the `config` namespace routing.
#
# Verifies that `ckipper config <subcommand>` reaches the namespace dispatcher
# and that the schema + core config + handlers are sourced into ckipper.zsh.
#
# ckipper.zsh is zsh-only; bats runs under bash, so each test spawns a zsh
# subprocess via run_ckipper().

load "${BATS_TEST_DIRNAME}/tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    mkdir -p "$CKIPPER_DIR/docker"
    : >"$CKIPPER_DIR/docker/ckipper-config.zsh"
    cat >"$CKIPPER_REGISTRY" <<'JSON'
{"version":2,"default":"work","accounts":{"work":{"config_dir":"/x","keychain_service":null,"registered_at":"t","preferences":{}}}}
JSON
}

teardown() {
    teardown_isolated_env
}

@test "ckipper config help prints config-namespace help" {
    run_ckipper config help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper config" ]]
}

@test "ckipper config list runs and prints something" {
    run_ckipper config list
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "ckipper config get notify_bell returns schema default" {
    run_ckipper config get notify_bell
    [ "$status" -eq 0 ]
    [[ "$output" =~ "true" ]]
}

@test "ckipper config set + get round-trips through dispatcher" {
    run_ckipper config set notify_bell false
    [ "$status" -eq 0 ]

    run_ckipper config get notify_bell
    [ "$status" -eq 0 ]
    [[ "$output" =~ "false" ]]
}

@test "ckipper config unknown subcommand suggests help pointer" {
    run_ckipper config nope
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Unknown command:" ]]
    [[ "$output" =~ "config help" ]]
}

@test "ckipper config (no subcommand) prints overview help" {
    run_ckipper config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper config" ]]
}
