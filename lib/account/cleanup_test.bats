#!/usr/bin/env bats
# Module-level tests for lib/account/cleanup.zsh.
# cleanup.zsh is zsh-only (uses _core_prompt_confirm), so every assertion
# spawns a zsh subshell that sources prompt.zsh + cleanup.zsh and runs the
# function under test (matching the pattern in prereqs_test.bats).
#
# CKIPPER_NO_GUM=1 forces the pure-zsh fallback path inside _core_prompt_*
# helpers so tests are deterministic regardless of whether `gum` is installed
# on the runner. Tests pipe stdin to the zsh subshell so the embedded
# `_core_prompt_confirm` read receives "y" or "n".

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: source prompt.zsh + cleanup.zsh in zsh, feed stdin, run zsh_cmd.
#
# Args: $1 — stdin payload; $2 — zsh command to execute.
# Side effect: populates $status / $output / $lines as with bats `run`.
_run_cleanup() {
    local stdin="$1" zsh_cmd="$2"
    run env CKIPPER_NO_GUM=1 \
        HOME="$TMP_HOME" PATH="$PATH" \
        _CKIPPER_TEST_OSTYPE="${_CKIPPER_TEST_OSTYPE:-linux}" \
        zsh -c "
            source \"$REPO_ROOT/lib/core/prompt.zsh\"
            source \"$REPO_ROOT/lib/account/cleanup.zsh\"
            $zsh_cmd
        " <<<"$stdin"
}

# ── _ckipper_account_cleanup_dir ─────────────────────────────────────────────

@test "cleanup_dir deletes when user confirms" {
    mkdir -p "$TMP_HOME/.claude-foo"

    _run_cleanup "y" "_ckipper_account_cleanup_dir foo \"$TMP_HOME/.claude-foo\""

    [ "$status" -eq 0 ]
    [ ! -d "$TMP_HOME/.claude-foo" ]
}

@test "cleanup_dir keeps dir when user declines" {
    mkdir -p "$TMP_HOME/.claude-foo"

    _run_cleanup "n" "_ckipper_account_cleanup_dir foo \"$TMP_HOME/.claude-foo\""

    [ "$status" -eq 0 ]
    [ -d "$TMP_HOME/.claude-foo" ]
    [[ "$output" =~ "rm -rf" ]]
}

@test "cleanup_dir is a no-op when dir does not exist" {
    _run_cleanup "" "_ckipper_account_cleanup_dir foo \"$TMP_HOME/.claude-missing\""

    [ "$status" -eq 0 ]
    [[ "$output" != *"Delete config dir"* ]]
}

# ── _ckipper_account_cleanup_keychain ────────────────────────────────────────

@test "cleanup_keychain is a no-op on non-darwin" {
    _CKIPPER_TEST_OSTYPE=linux \
        _run_cleanup "y" "_ckipper_account_cleanup_keychain foo 'Claude Code-credentials'"

    [ "$status" -eq 0 ]
    [[ "$output" != *"Deleted"* ]]
    [[ "$output" != *"Delete Keychain"* ]]
}

@test "cleanup_keychain is a no-op when service is empty" {
    _CKIPPER_TEST_OSTYPE=darwin19.0 \
        _run_cleanup "y" "_ckipper_account_cleanup_keychain foo ''"

    [ "$status" -eq 0 ]
    [[ "$output" != *"Deleted"* ]]
    [[ "$output" != *"Delete Keychain"* ]]
}

@test "cleanup_keychain calls security on darwin when user confirms" {
    _CKIPPER_TEST_OSTYPE=darwin19.0 \
        _run_cleanup "y" "_ckipper_account_cleanup_keychain foo 'Claude Code-credentials'"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Deleted" ]]
}

@test "cleanup_keychain leaves entry when user declines on darwin" {
    _CKIPPER_TEST_OSTYPE=darwin19.0 \
        _run_cleanup "n" "_ckipper_account_cleanup_keychain foo 'Claude Code-credentials'"

    [ "$status" -eq 0 ]
    [[ "$output" != *"Deleted"* ]]
    [[ "$output" =~ "security delete-generic-password" ]]
}
