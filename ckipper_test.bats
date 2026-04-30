#!/usr/bin/env bats
# Characterization tests for ckipper subcommands.
#
# Purpose: regression net for Phases 2-4 (modularization + refactoring).
# These tests document ACTUAL current behavior — assertions were adjusted to
# match observed output rather than idealized behavior.
#
# Important: ckipper.zsh is zsh-only (uses read "?..." prompt syntax, setopt,
# local-function nesting). Bats runs under bash, so every test spawns a zsh
# subprocess via run_ckipper() in test-helper.bash.

load "${BATS_TEST_DIRNAME}/tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# ── _ckipper_doctor ─────────────────────────────────────────────────

@test "ckipper doctor prints diagnostic output and mentions registry" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
    run_ckipper doctor
    # doctor always exits 0 or 1 depending on FAIL count; with an empty registry
    # and no deployed tooling it returns some WARNs/FAILs but does not crash.
    [[ "$output" =~ [Rr]egistry ]]
}

@test "ckipper doctor prints INFO about missing registry when none exists" {
    rm -f "$CKIPPER_REGISTRY"
    run_ckipper doctor
    # With no registry, doctor prints an INFO line and returns 0.
    [ "$status" -eq 0 ]
    [[ "$output" =~ [Rr]egistry ]]
}

@test "ckipper doctor exits 0 when registry missing (no accounts registered)" {
    rm -f "$CKIPPER_REGISTRY"
    run_ckipper doctor
    [ "$status" -eq 0 ]
}

# ── _ckipper_sync ────────────────────────────────────────────────────

@test "ckipper sync --help prints usage and exits 0" {
    run_ckipper sync --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "sync" ]]
}

@test "ckipper sync errors when source account is not registered" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
    run_ckipper sync nonexistent target
    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

@test "ckipper sync errors when from and to are the same" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
    run_ckipper sync same same
    [ "$status" -ne 0 ]
    [[ "$output" =~ "differ" ]]
}

# ── _ckipper_add ────────────────────────────────────────────────────

@test "ckipper add rejects names containing spaces (invalid regex)" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
    run_ckipper add "Invalid Name With Spaces"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "must match" || "$output" =~ [Ii]nvalid ]]
}

@test "ckipper add rejects uppercase names" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
    run_ckipper add "MyAccount"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "must match" || "$output" =~ [Ii]nvalid ]]
}

@test "ckipper add with builtin name 'cd' fails after prompt due to missing claude binary" {
    # Note: 'cd' passes the name-regex check (^[a-z0-9_-]+$). It does NOT get
    # rejected at validation time. Instead, ckipper proceeds to launch 'claude'
    # which is not available in the test env. Feeding "skip" at the
    # "Press enter to launch" prompt causes a clean abort.
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
    local stdin_file="$TMP_HOME/stdin.txt"
    printf 'skip\n' > "$stdin_file"
    run env \
        HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        _CKIPPER_TEST_OSTYPE="linux" \
        CKIPPER_FORCE=1 \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; ckipper add cd" < "$stdin_file"
    # After "skip" input, ckipper aborts with exit 1.
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Aborted" || "$output" =~ "abort" ]]
}

@test "ckipper add with no name prints usage and exits 1" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
    run_ckipper add
    [ "$status" -ne 0 ]
    [[ "$output" =~ [Uu]sage ]]
}

# ── _ckipper_list ────────────────────────────────────────────────────

@test "ckipper list shows registered accounts" {
    echo '{"version":1,"default":"work","accounts":{"work":{"config_dir":"/tmp/.claude-work","keychain_service":"Claude Code-credentials-work"}}}' > "$CKIPPER_REGISTRY"
    run_ckipper list
    [ "$status" -eq 0 ]
    [[ "$output" =~ "work" ]]
}

@test "ckipper list prints a message when no accounts registered" {
    rm -f "$CKIPPER_REGISTRY"
    run_ckipper list
    [ "$status" -eq 0 ]
    [[ "$output" =~ "No accounts" || "$output" =~ "no accounts" ]]
}

# ── _ckipper_remove ──────────────────────────────────────────────────

@test "ckipper remove unregisters a known account and exits 0" {
    echo '{"version":1,"default":null,"accounts":{"tmp":{"config_dir":"/tmp/.claude-tmp","keychain_service":"Claude Code-credentials-tmp"}}}' > "$CKIPPER_REGISTRY"
    # Note: ckipper remove has no --yes flag; it removes without prompting.
    run_ckipper remove tmp
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Unregistered" ]]
}

@test "ckipper remove errors on unknown account name" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
    run_ckipper remove nobody
    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

@test "ckipper remove with no name prints usage and exits 1" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
    run_ckipper remove
    [ "$status" -ne 0 ]
    [[ "$output" =~ [Uu]sage ]]
}
