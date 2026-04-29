#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../tests/lib/test-helper.bash"

setup() {
    [ "${BATS_INTEGRATION:-}" = "1" ] || skip "entrypoint tests gated by BATS_INTEGRATION=1"
    setup_isolated_env
}

teardown() {
    [ "${BATS_INTEGRATION:-}" = "1" ] || return 0
    teardown_isolated_env
}

@test "entrypoint writes credentials without trailing newline" {
    skip "Requires container env"
}

@test "entrypoint enforces 1MB credentials bounds check" {
    skip "Requires container env"
}

@test "entrypoint configures git from oauth account name" {
    skip "Requires container env"
}
