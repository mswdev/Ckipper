#!/usr/bin/env bats
# Top-level dispatcher tests for ckipper().
#
# Verifies that namespace routing (account, worktree, doctor) works, that the
# acct/wt short forms are equivalent, that bare/help prints overview, that
# unknown commands fuzzy-suggest, and that namespace subcommands are reachable
# through the new dispatcher.
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

@test "ckipper (bare) prints top-level help and exits 0" {
    run_ckipper
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper account" ]]
    [[ "$output" =~ "ckipper worktree" ]]
    [[ "$output" =~ "ckipper doctor" ]]
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
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
    run_ckipper account remove nobody
    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

# ── Worktree namespace + alias ───────────────────────────────────────

@test "ckipper worktree help prints worktree-namespace help" {
    run_ckipper worktree help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper worktree" ]]
    [[ "$output" =~ "Short form" ]]
}

@test "ckipper wt help is equivalent to ckipper worktree help" {
    run_ckipper wt help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper worktree" ]]
}

@test "ckipper worktree run --help prints run-specific help" {
    run_ckipper worktree run --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ckipper worktree run" ]]
    [[ "$output" =~ "--docker" ]]
}

@test "ckipper wt run with no args prints help and exits 1" {
    run_ckipper wt run
    [ "$status" -ne 0 ]
    [[ "$output" =~ "ckipper worktree run" ]]
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
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
    run_ckipper doctor
    [[ "$output" =~ [Rr]egistry ]]
}
