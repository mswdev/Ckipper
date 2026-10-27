#!/usr/bin/env bats
# Top-level dispatcher tests for ckipper().
#
# Verifies that namespace routing (account, desktop, doctor) works, that the
# acct short form is equivalent, that bare/help prints overview, that unknown
# commands fuzzy-suggest, that removed commands print a pointer to their
# replacement, and that namespace subcommands are reachable.
#
# ckipper.zsh is zsh-only (uses read "?..." prompt syntax, setopt, etc.).
# Bats runs under bash, so every test spawns a zsh subprocess via run_ckipper().

load "${BATS_TEST_DIRNAME}/tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# ── Top-level routing ────────────────────────────────────────────────

@test "ckipper (bare) prints top-level help" {
    run_ckipper

    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper account <subcommand>" ]]
    [[ "$output" =~ "ckipper desktop <subcommand>" ]]
}

@test "ckipper help prints top-level help" {
    run_ckipper help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Short alias" ]]
}

@test "ckipper unknown-command fuzzy-suggests when close" {
    run_ckipper accont
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Unknown command: 'accont'. Did you mean: 'account'?" ]]
}

@test "ckipper unknown-command shows bare error when no close match" {
    run_ckipper xyzzy
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Unknown command: 'xyzzy'." ]]
    [[ ! "$output" =~ "Did you mean" ]]
}

# ── Account namespace + alias ────────────────────────────────────────

@test "ckipper account help prints account-namespace help" {
    run_ckipper account help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper account" ]]
    [[ "$output" =~ "Short form" ]]
}

@test "ckipper acct help is equivalent to ckipper account help" {
    run_ckipper acct help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper account" ]]
}

@test "ckipper account list prints message when no accounts registered" {
    rm -f "$CKIPPER_REGISTRY"
    run_ckipper account list
    [ "$status" -eq 0 ]
    [[ "$output" =~ "No accounts" || "$output" =~ "no accounts" ]]
}

@test "ckipper acct list works through the short alias" {
    rm -f "$CKIPPER_REGISTRY"
    run_ckipper acct list
    [ "$status" -eq 0 ]
    [[ "$output" =~ "No accounts" || "$output" =~ "no accounts" ]]
}

@test "ckipper account add --help prints add-specific help" {
    run_ckipper account add --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper account add" ]]
    [[ "$output" =~ "--adopt" ]]
}

@test "ckipper account remove rejects unknown name" {
    echo '{"version":3,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
    run_ckipper account remove nobody
    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

# ── Removed commands ─────────────────────────────────────────────────

@test "ckipper worktree points at claude --worktree" {
    run_ckipper worktree run myproj main

    [ "$status" -ne 0 ]
    [[ "$output" =~ "'ckipper worktree' was removed" ]]
    [[ "$output" =~ "--worktree" ]]
}

@test "ckipper run points at claude --worktree" {
    run_ckipper run myproj main

    [ "$status" -ne 0 ]
    [[ "$output" =~ "'ckipper run' was removed" ]]
}

@test "ckipper config and setup print a removed hint" {
    run_ckipper config list
    [ "$status" -ne 0 ]
    [[ "$output" =~ "'ckipper config' was removed" ]]

    run_ckipper setup
    [ "$status" -ne 0 ]
    [[ "$output" =~ "'ckipper setup' was removed" ]]
}

# ── Doctor (top-level command, not a namespace) ──────────────────────

@test "ckipper doctor --help prints doctor-specific help" {
    run_ckipper doctor --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper doctor" ]]
    [[ "$output" =~ "Registry validity" || "$output" =~ "registry" ]]
}

@test "ckipper doctor exits 0 when registry missing (no accounts)" {
    rm -f "$CKIPPER_REGISTRY"
    run_ckipper doctor
    [ "$status" -eq 0 ]
}

@test "ckipper doctor mentions registry in output" {
    echo '{"version":3,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
    run_ckipper doctor
    [[ "$output" =~ [Rr]egistry ]]
}

# ── tab completion version sentinel ──────────────────────────────────

# The completion-file regeneration mechanism relies on the literal
# "# ckipper-completion-version=N" sentinel inside the single-quoted heredoc
# matching the CKIPPER_COMPLETION_VERSION variable referenced in the grep
# check immediately above. If a future bump only updates one side, existing
# installs silently fail to regenerate. This test guards against that drift.
@test "ckipper.zsh: completion version sentinel matches outer variable" {
    local outer inner
    outer=$(grep -E '^CKIPPER_COMPLETION_VERSION=' "$REPO_ROOT/ckipper.zsh" | head -1 | cut -d= -f2)
    inner=$(grep -E '^# ckipper-completion-version=' "$REPO_ROOT/ckipper.zsh" | head -1 | cut -d= -f2)
    [ -n "$outer" ]
    [ -n "$inner" ]
    [ "$outer" = "$inner" ]
}
