#!/usr/bin/env bats
# Module-level tests for lib/worktree/build-image.zsh.
# Verifies _ckipper_worktree_build_image invokes docker build when Dockerfile exists.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export DOCKER_STUB_LOG="$TMP_HOME/docker.log"
    : > "$DOCKER_STUB_LOG"
}

teardown() {
    teardown_isolated_env
}

@test "_ckipper_worktree_build_image invokes docker build when Dockerfile is present" {
    mkdir -p "$CKIPPER_DIR/docker"
    touch "$CKIPPER_DIR/docker/Dockerfile"

    run env HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        DOCKER_STUB_LOG="$DOCKER_STUB_LOG" \
        PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/worktree/build-image.zsh\"; _ckipper_worktree_build_image"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Building" ]]
    grep -q "build" "$DOCKER_STUB_LOG"
}
