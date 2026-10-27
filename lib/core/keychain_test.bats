#!/usr/bin/env bats
# Module-level tests for lib/core/keychain.zsh.
# Covers service_for_dir, entry_exists, running_claude_processes, and
# assert_no_running_claude.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    export _CKIPPER_TEST_OSTYPE="darwin19.0"
}

teardown() {
    teardown_isolated_env
}

# Helper: source keychain.zsh and run zsh_cmd.
_run_keychain() {
    local zsh_cmd="$1"
    run env HOME="$TMP_HOME" \
        _CKIPPER_TEST_OSTYPE="${_CKIPPER_TEST_OSTYPE:-darwin19.0}" \
        CKIPPER_FORCE="${CKIPPER_FORCE:-0}" \
        PGREP_STUB_MATCH="${PGREP_STUB_MATCH:-0}" \
        SECURITY_STUB_SERVICES="${SECURITY_STUB_SERVICES:-}" \
        PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/core/keychain.zsh\"; $zsh_cmd"
}

@test "service_for_dir hashes the config dir path like Claude Code does" {
    local dir="/Users/someone/.claude-work"
    local expected
    expected="Claude Code-credentials-$(printf '%s' "$dir" | shasum -a 256 | cut -c1-8)"

    _run_keychain "_core_keychain_service_for_dir '$dir'"

    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
}

@test "service_for_dir returns the unsuffixed name for the default ~/.claude" {
    _run_keychain '_core_keychain_service_for_dir "$HOME/.claude"'

    [ "$status" -eq 0 ]
    [ "$output" = "Claude Code-credentials" ]
}

@test "service_for_dir gives different accounts different entries" {
    _run_keychain '_core_keychain_service_for_dir "$HOME/.claude-a"; _core_keychain_service_for_dir "$HOME/.claude-b"'

    [ "$status" -eq 0 ]
    [ "${lines[0]}" != "${lines[1]}" ]
}

@test "entry_exists is true only for services the Keychain has" {
    export SECURITY_STUB_SERVICES="Claude Code-credentials-aaaa1111"

    _run_keychain '_core_keychain_entry_exists "Claude Code-credentials-aaaa1111" && echo HIT; _core_keychain_entry_exists "Claude Code-credentials-bbbb2222" || echo MISS'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "HIT" ]]
    [[ "$output" =~ "MISS" ]]
}

@test "entry_exists is always false off macOS" {
    export _CKIPPER_TEST_OSTYPE="linux"

    _run_keychain '_core_keychain_entry_exists "Claude Code-credentials" || echo MISS'

    [[ "$output" =~ "MISS" ]]
}

@test "_core_assert_no_running_claude passes when no Claude processes are running" {
    export PGREP_STUB_MATCH=0

    _run_keychain "_core_assert_no_running_claude"

    [ "$status" -eq 0 ]
}
