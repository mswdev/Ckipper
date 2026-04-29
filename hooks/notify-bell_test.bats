#!/usr/bin/env bats
# Module-level tests for hooks/notify-bell.sh.
# Verifies that the hook emits the bell character when in Docker.

load "${BATS_TEST_DIRNAME}/../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export CKIPPER_DOCKERENV="$TMP_HOME/fake-dockerenv"
    touch "$CKIPPER_DOCKERENV"
}

teardown() {
    teardown_isolated_env
}

@test "notify-bell emits a bell character (\\a) when inside Docker" {
    run env CKIPPER_DOCKERENV="$CKIPPER_DOCKERENV" \
        bash "$REPO_ROOT/hooks/notify-bell.sh"

    [ "$status" -eq 0 ]
    # The bell character is \x07.
    [[ "$output" == $'\a' ]]
}
