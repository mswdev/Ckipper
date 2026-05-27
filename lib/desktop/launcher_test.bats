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

# ── desktop login (Task 10) ────────────────────────────────────────────────
#
# Login tests use zsh function overrides INSIDE the spawned subshell (not via
# PATH stubs) because the dance has multiple phases — initial pgrep, then
# wait_for_exit's kill -0 polls, then optional SIGKILL — and each phase needs
# a different mock response. PATH stubs can't carry that state.

@test "login looks up bundle from registry and opens it" {
    _install_fake_claude_app
    run_ckipper desktop add work

    local mock_log="$TMP_HOME/mock.log"
    : >"$mock_log"
    run env HOME="$TMP_HOME" CKIPPER_DIR="$CKIPPER_DIR" \
        _CKIPPER_TEST_OSTYPE="darwin19.0" \
        _CKIPPER_DESKTOP_SYSTEM_APP="$_CKIPPER_DESKTOP_SYSTEM_APP" \
        PATH="$PATH" MOCK_LOG="$mock_log" \
        zsh -c '
            source "'"$REPO_ROOT"'/ckipper.zsh"
            pgrep() { return 1; }
            open()  { echo "open $*" >> "$MOCK_LOG"; }
            ckipper desktop login work
        '

    [ "$status" -eq 0 ]
    grep -q "open -n -a $HOME/Applications/Claude-Work.app" "$mock_log"
}

@test "login quits running Claude processes via TERM before launching target" {
    _install_fake_claude_app
    run_ckipper desktop add work

    local mock_log="$TMP_HOME/mock.log"
    : >"$mock_log"
    run env HOME="$TMP_HOME" CKIPPER_DIR="$CKIPPER_DIR" \
        _CKIPPER_TEST_OSTYPE="darwin19.0" \
        _CKIPPER_DESKTOP_SYSTEM_APP="$_CKIPPER_DESKTOP_SYSTEM_APP" \
        PATH="$PATH" MOCK_LOG="$mock_log" \
        zsh -c '
            source "'"$REPO_ROOT"'/ckipper.zsh"
            # Shrink timeout so the test does not idle for 5s if mocks misbehave.
            _CKIPPER_DESKTOP_TERM_TIMEOUT_MAX_POLLS=2
            _CKIPPER_DESKTOP_POLL_INTERVAL_SECONDS="0.05"
            pgrep() { echo 1001; echo 1002; }
            # kill -0 (alive-check) returns non-zero so wait_for_exit exits
            # the polling loop immediately ("all dead"). kill -TERM is logged.
            kill() {
                echo "kill $*" >> "$MOCK_LOG"
                [[ "$1" == "-0" ]] && return 1
                return 0
            }
            open() { echo "open $*" >> "$MOCK_LOG"; }
            ckipper desktop login work
        '

    [ "$status" -eq 0 ]
    grep -q "kill -TERM 1001" "$mock_log"
    grep -q "kill -TERM 1002" "$mock_log"
    grep -q "open -n -a" "$mock_log"
}

@test "login escalates SIGTERM to SIGKILL after timeout" {
    _install_fake_claude_app
    run_ckipper desktop add work

    local mock_log="$TMP_HOME/mock.log"
    : >"$mock_log"
    run env HOME="$TMP_HOME" CKIPPER_DIR="$CKIPPER_DIR" \
        _CKIPPER_TEST_OSTYPE="darwin19.0" \
        _CKIPPER_DESKTOP_SYSTEM_APP="$_CKIPPER_DESKTOP_SYSTEM_APP" \
        PATH="$PATH" MOCK_LOG="$mock_log" \
        zsh -c '
            source "'"$REPO_ROOT"'/ckipper.zsh"
            # Two polls at 50ms each = 0.1s before SIGKILL fires.
            _CKIPPER_DESKTOP_TERM_TIMEOUT_MAX_POLLS=2
            _CKIPPER_DESKTOP_POLL_INTERVAL_SECONDS="0.05"
            pgrep() { echo 1001; }
            # kill -0 ALWAYS reports alive — forces escalation to SIGKILL.
            kill() {
                echo "kill $*" >> "$MOCK_LOG"
                [[ "$1" == "-0" ]] && return 0
                return 0
            }
            open() { echo "open $*" >> "$MOCK_LOG"; }
            ckipper desktop login work
        '

    grep -q "kill -KILL 1001" "$mock_log"
}

@test "login fails when instance is not registered" {
    _install_fake_claude_app

    run_ckipper desktop login ghost

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

@test "login succeeds when no Claude processes are running" {
    _install_fake_claude_app
    run_ckipper desktop add work

    local mock_log="$TMP_HOME/mock.log"
    : >"$mock_log"
    run env HOME="$TMP_HOME" CKIPPER_DIR="$CKIPPER_DIR" \
        _CKIPPER_TEST_OSTYPE="darwin19.0" \
        _CKIPPER_DESKTOP_SYSTEM_APP="$_CKIPPER_DESKTOP_SYSTEM_APP" \
        PATH="$PATH" MOCK_LOG="$mock_log" \
        zsh -c '
            source "'"$REPO_ROOT"'/ckipper.zsh"
            pgrep() { return 1; }
            open()  { echo "open $*" >> "$MOCK_LOG"; }
            ckipper desktop login work
        '

    [ "$status" -eq 0 ]
    grep -q "open -n -a" "$mock_log"
}
