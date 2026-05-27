#!/usr/bin/env bats
# Tests for lib/desktop/launcher.zsh — process checks (Task 9),
# desktop login (Task 10), and desktop launch (Task 11).

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# ── _ckipper_desktop_assert_not_running ────────────────────────────────────

@test "assert_not_running returns 0 when pgrep finds nothing" {
    run env HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/desktop/launcher.zsh\"; _ckipper_desktop_assert_not_running \"$HOME/.claude-desktop-work\""

    [ "$status" -eq 0 ]
}

@test "assert_not_running returns 1 and prints PID when pgrep finds a match" {
    run env HOME="$TMP_HOME" PATH="$PATH" PGREP_STUB_MATCH=1 \
        zsh -c "source \"$REPO_ROOT/lib/desktop/launcher.zsh\"; _ckipper_desktop_assert_not_running \"$HOME/.claude-desktop-work\""

    [ "$status" -ne 0 ]
    [[ "$output" =~ "99999" ]] || [[ "$output" =~ "running" ]]
}
