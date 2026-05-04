#!/usr/bin/env bats
# Module-level tests for hooks/docker-context.sh.
# Verifies that the hook is a no-op on the host (no /.dockerenv).

load "${BATS_TEST_DIRNAME}/../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

@test "docker-context exits 0 and produces no output when not in Docker" {
    # No CKIPPER_DOCKERENV set, so the file-not-found guard exits 0 early.
    run env bash "$REPO_ROOT/hooks/docker-context.sh"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
