#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

@test "install.sh fresh install creates ~/.ckipper/docker/ tree with lib/" {
    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" \
        run "$REPO_ROOT/install.sh"

    [ "$status" -eq 0 ]
    [ -d "$TMP_HOME/.ckipper/docker/lib/core" ]
    [ -d "$TMP_HOME/.ckipper/docker/lib/account" ]
    [ -d "$TMP_HOME/.ckipper/docker/lib/w" ]
    [ -f "$TMP_HOME/.ckipper/docker/ckipper.zsh" ]
    [ -f "$TMP_HOME/.ckipper/docker/w-function.zsh" ]
}

@test "install.sh excludes test files from deployed lib/" {
    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" \
        run "$REPO_ROOT/install.sh"

    [ "$status" -eq 0 ]
    run find "$TMP_HOME/.ckipper/docker/lib" \( -name '*_test.*' -o -name '__pycache__' \)
    [ -z "$output" ]
}

@test "install.sh re-run preserves existing w-config.zsh" {
    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" run "$REPO_ROOT/install.sh"
    [ "$status" -eq 0 ]
    echo 'CUSTOM_VALUE="preserve_me"' >> "$TMP_HOME/.ckipper/docker/w-config.zsh"

    HOME="$TMP_HOME" CKIPPER_DIR="$TMP_HOME/.ckipper" \
        run "$REPO_ROOT/install.sh"

    [ "$status" -eq 0 ]
    grep -q 'CUSTOM_VALUE="preserve_me"' "$TMP_HOME/.ckipper/docker/w-config.zsh"
}
