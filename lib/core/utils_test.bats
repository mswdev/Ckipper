#!/usr/bin/env bats
# Module-level tests for lib/core/utils.zsh.
# Tests _core_stat_perms and _core_stat_mtime observable behaviour.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    # Use darwin ostype so the BSD stat flags are used on macOS host.
    export _CKIPPER_TEST_OSTYPE="darwin19.0"
}

teardown() {
    teardown_isolated_env
}

# Helper: source utils.zsh and run a command in a zsh subshell.
_run_utils() {
    local zsh_cmd="$1"
    run env HOME="$TMP_HOME" _CKIPPER_TEST_OSTYPE="$_CKIPPER_TEST_OSTYPE" PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/core/utils.zsh\"; $zsh_cmd"
}

@test "_core_stat_perms returns the octal mode of a file" {
    local target="$TMP_HOME/perm-test.txt"
    touch "$target"
    chmod 644 "$target"

    _run_utils "_core_stat_perms \"$target\""

    [ "$status" -eq 0 ]
    [ "$output" = "644" ]
}

@test "_core_stat_mtime returns epoch seconds for a touched file" {
    local target="$TMP_HOME/mtime-test.txt"
    touch -t 202001010000 "$target"

    _run_utils "_core_stat_mtime \"$target\""

    [ "$status" -eq 0 ]
    # 2020-01-01 00:00 UTC → 1577836800.  Accept any 10-digit epoch.
    [[ "$output" =~ ^[0-9]{10}$ ]]
}
