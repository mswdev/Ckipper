#!/usr/bin/env bats
# Module-level tests for lib/worktree/run.zsh.
# Verifies the orchestration: bad arg combos, mode selection (docker vs normal).

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: run _ckipper_worktree_run in a zsh subshell with stubs for
# resolve-account, resolve-flags, create-worktree, docker-mode, normal-mode,
# and help. The orchestration tests don't exercise per-account preference
# resolution; that is covered separately further down with the real function
# sourced. Stubbing here keeps these tests focused on dispatch order.
_run_run() {
    run env HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "
            source \"$REPO_ROOT/lib/worktree/args.zsh\"
            source \"$REPO_ROOT/lib/worktree/run.zsh\"
            _ckipper_worktree_resolve_account() { echo 'STUB-RESOLVE'; }
            _ckipper_worktree_resolve_flags() { :; }
            _ckipper_worktree_create_worktree() { echo 'STUB-CREATE' \"\$@\"; }
            _ckipper_worktree_run_docker_mode() { echo 'STUB-DOCKER'; }
            _ckipper_worktree_run_normal_mode() { echo 'STUB-NORMAL'; }
            _ckipper_worktree_help_for() { echo \"STUB-HELP-FOR \$@\"; }
            _ckipper_worktree_run $*
        "
}

@test "run with no args prints help and exits 1" {
    _run_run

    [ "$status" -eq 1 ]
    [[ "$output" =~ "STUB-HELP-FOR run" ]]
}

@test "run with only project prints help and exits 1" {
    _run_run myproj

    [ "$status" -eq 1 ]
    [[ "$output" =~ "STUB-HELP-FOR run" ]]
}

@test "run with --firewall but no --docker exits 1 with error" {
    _run_run myproj feat --firewall

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: --firewall requires --docker" ]]
}

@test "run normal-mode happy path calls resolve, create, normal" {
    _run_run myproj feat

    [ "$status" -eq 0 ]
    [[ "$output" =~ "STUB-RESOLVE" ]]
    [[ "$output" =~ "STUB-CREATE myproj feat" ]]
    [[ "$output" =~ "STUB-NORMAL" ]]
    [[ ! "$output" =~ "STUB-DOCKER" ]]
}

@test "run docker-mode happy path calls resolve, create, docker" {
    _run_run myproj feat --docker

    [ "$status" -eq 0 ]
    [[ "$output" =~ "STUB-RESOLVE" ]]
    [[ "$output" =~ "STUB-CREATE myproj feat" ]]
    [[ "$output" =~ "STUB-DOCKER" ]]
    [[ ! "$output" =~ "STUB-NORMAL" ]]
}

@test "run docker + firewall happy path calls docker mode" {
    _run_run myproj feat --docker --firewall

    [ "$status" -eq 0 ]
    [[ "$output" =~ "STUB-DOCKER" ]]
}

# ── _ckipper_worktree_resolve_flags ──────────────────────────────────
# These tests source the real resolve_flags + config primitives so the
# CLI-vs-account precedence is exercised end-to-end (registry → _core_config_get
# → flag globals).

# Helper: write a v2 accounts.json fixture with a single `work` account whose
# preferences object is exactly $1 (a JSON object literal, e.g. '{"always_docker":true}').
_write_registry() {
    local prefs_json="$1"
    cat >"$CKIPPER_REGISTRY" <<JSON
{"version":2,"default":"work","accounts":{"work":{"config_dir":"/x","keychain_service":null,"registered_at":"t","preferences":${prefs_json}}}}
JSON
}

# Helper: run a parse + resolve_flags scenario in a zsh subshell with the real
# schema and config primitives sourced.
#
# Args:
#   $1 — extra flags to pass to _ckipper_worktree_parse_run_args after `proj
#        branch` (e.g. "--no-docker"; pass empty string for none)
#   $2 — the variable name to print after resolve_flags (e.g.
#        CKIPPER_WT_FLAG_DOCKER)
_run_resolve_flags() {
    local extra_flags="$1" var_name="$2"
    run env HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        zsh -c "
            source \"$REPO_ROOT/lib/config/schema.zsh\"
            source \"$REPO_ROOT/lib/core/config.zsh\"
            source \"$REPO_ROOT/lib/worktree/args.zsh\"
            source \"$REPO_ROOT/lib/worktree/run.zsh\"
            _ckipper_worktree_parse_run_args proj branch ${extra_flags}
            _ckipper_worktree_resolve_flags work
            print -r -- \"\$${var_name}\"
        "
}

@test "_ckipper_worktree_resolve_flags applies always_docker=true when CLI silent" {
    _write_registry '{"always_docker":true}'

    _run_resolve_flags "" CKIPPER_WT_FLAG_DOCKER

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "_ckipper_worktree_resolve_flags --docker overrides always_docker=false" {
    _write_registry '{"always_docker":false}'

    _run_resolve_flags "--docker" CKIPPER_WT_FLAG_DOCKER

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "_ckipper_worktree_resolve_flags --no-docker overrides always_docker=true" {
    _write_registry '{"always_docker":true}'

    _run_resolve_flags "--no-docker" CKIPPER_WT_FLAG_DOCKER

    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "_ckipper_worktree_resolve_flags applies always_firewall=true when CLI silent" {
    _write_registry '{"always_firewall":true}'

    _run_resolve_flags "" CKIPPER_WT_FLAG_FIREWALL

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "_ckipper_worktree_resolve_flags --no-firewall overrides always_firewall=true" {
    _write_registry '{"always_firewall":true}'

    _run_resolve_flags "--no-firewall" CKIPPER_WT_FLAG_FIREWALL

    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "_ckipper_worktree_resolve_flags applies ssh_forward=false when CLI silent" {
    _write_registry '{"ssh_forward":false}'

    _run_resolve_flags "" CKIPPER_WT_FLAG_SSH_FORWARD

    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "_ckipper_worktree_resolve_flags --ssh-forward overrides ssh_forward=false" {
    _write_registry '{"ssh_forward":false}'

    _run_resolve_flags "--ssh-forward" CKIPPER_WT_FLAG_SSH_FORWARD

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "_ckipper_worktree_resolve_flags falls back to schema defaults when account has no prefs" {
    _write_registry '{}'

    _run_resolve_flags "" CKIPPER_WT_FLAG_DOCKER
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]

    _run_resolve_flags "" CKIPPER_WT_FLAG_SSH_FORWARD
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}
