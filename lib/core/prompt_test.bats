#!/usr/bin/env bats
# Module-level tests for lib/core/prompt.zsh.
# prompt.zsh is zsh-only (uses `read -r "?prompt"` and zsh array indexing), so
# every assertion spawns a zsh subshell that sources prompt.zsh and runs the
# function under test (matching the pattern in style_test.bats and
# help_test.bats).
#
# CKIPPER_NO_GUM=1 forces the pure-zsh fallback path so tests are deterministic
# regardless of whether `gum` is installed on the runner. Stderr is redirected
# to /dev/null inside the zsh -c command so the read-prompt label (printed to
# stderr by `read "?..."`) doesn't leak into bats `run`'s captured $output —
# without that, the default-value test is unable to distinguish "echoed
# default" from "default appears in the prompt label `[default]:`".

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: source prompt.zsh in zsh, feed stdin, run zsh_cmd with stderr muted.
#
# Args: $1 — stdin payload to pipe to the prompt; $2 — zsh command to execute.
# Side effect: populates $status / $output / $lines as with bats `run`.
_run_prompt() {
    local stdin="$1" zsh_cmd="$2"
    run env CKIPPER_NO_GUM=1 PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/core/prompt.zsh\"; $zsh_cmd 2>/dev/null" <<<"$stdin"
}

@test "_core_prompt_input echoes the user's input" {
    _run_prompt "hello" '_core_prompt_input "Q" "thedefault"'

    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "_core_prompt_input returns default on empty input" {
    _run_prompt "" '_core_prompt_input "Q" "thedefault"'

    [ "$status" -eq 0 ]
    [ "$output" = "thedefault" ]
}

# Regression: previously cancellation (EOF / Ctrl-C / Esc on the gum form)
# was indistinguishable from "user submitted empty" because both echoed
# the default. The launcher's branch prompt then created a worktree on
# `feature/dev` even when the user pressed Ctrl-X to back out. The fix
# propagates rc from gum / read so callers can distinguish cancel via rc.
@test "_core_prompt_input returns non-zero with no stdout when read sees EOF" {
    run env CKIPPER_NO_GUM=1 PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/core/prompt.zsh\"; \
                _core_prompt_input \"Q\" \"thedefault\" 2>/dev/null" </dev/null

    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "_core_prompt_confirm returns 0 on y" {
    _run_prompt "y" '_core_prompt_confirm "Proceed?"'

    [ "$status" -eq 0 ]
}

@test "_core_prompt_confirm returns 0 on uppercase Y" {
    _run_prompt "Y" '_core_prompt_confirm "Proceed?"'

    [ "$status" -eq 0 ]
}

@test "_core_prompt_confirm returns 1 on n" {
    _run_prompt "n" '_core_prompt_confirm "Proceed?"'

    [ "$status" -eq 1 ]
}

@test "_core_prompt_confirm returns 1 on empty input" {
    _run_prompt "" '_core_prompt_confirm "Proceed?"'

    [ "$status" -eq 1 ]
}

@test "_core_prompt_choose returns the picked item by index" {
    _run_prompt "1" '_core_prompt_choose "Pick" alpha beta gamma'

    [ "$status" -eq 0 ]
    [ "$output" = "alpha" ]
}

@test "_core_prompt_choose returns last item when last index is selected" {
    _run_prompt "3" '_core_prompt_choose "Pick" alpha beta gamma'

    [ "$status" -eq 0 ]
    [ "$output" = "gamma" ]
}

@test "_core_prompt_choose returns 1 on out-of-range index" {
    _run_prompt "99" '_core_prompt_choose "Pick" alpha beta gamma'

    [ "$status" -eq 1 ]
}

@test "_core_prompt_choose returns 1 on non-numeric input" {
    _run_prompt "abc" '_core_prompt_choose "Pick" alpha beta gamma'

    [ "$status" -eq 1 ]
}

@test "_core_prompt_choose returns 1 on zero index" {
    _run_prompt "0" '_core_prompt_choose "Pick" alpha beta gamma'

    [ "$status" -eq 1 ]
}

@test "_core_prompt_use_gum returns 1 when CKIPPER_NO_GUM=1" {
    _run_prompt "" '_core_prompt_use_gum'

    [ "$status" -eq 1 ]
}

@test "_core_prompt_spin runs the command and forwards exit status 0" {
    _run_prompt "" '_core_prompt_spin "Working" true'

    [ "$status" -eq 0 ]
}

@test "_core_prompt_spin forwards non-zero exit status" {
    _run_prompt "" '_core_prompt_spin "Working" false'

    [ "$status" -eq 1 ]
}
