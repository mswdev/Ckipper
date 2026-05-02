#!/usr/bin/env bats
# Module-level tests for lib/config/dispatcher.zsh.
# Verifies routing of `ckipper config <subcommand>` to the per-subcommand
# handlers, plus the unknown-subcommand path. The dispatcher and handlers are
# zsh-only, so each test spawns a zsh subshell that sources schema.zsh +
# core/config.zsh + core/fuzzy.zsh + core/registry.zsh + every config handler +
# dispatcher (matching the pattern in lib/core/config_test.bats).
#
# core/registry.zsh is sourced because handlers call _core_account_dir to
# validate that --account names refer to registered accounts (rejects typos
# that would otherwise silently create phantom registry records).

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    mkdir -p "$CKIPPER_DIR/docker"
    : >"$CKIPPER_DIR/docker/ckipper-config.zsh"
    # v2 accounts.json fixture with one `work` account having empty preferences.
    cat >"$CKIPPER_REGISTRY" <<'JSON'
{"version":2,"default":"work","accounts":{"work":{"config_dir":"/x","keychain_service":null,"registered_at":"t","preferences":{}}}}
JSON
}

teardown() {
    teardown_isolated_env
}

# Helper: source schema + every config module in zsh and run zsh_cmd.
_run_config_dispatch() {
    local zsh_cmd="$1"
    run env HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        CKIPPER_REGISTRY_VERSION="${CKIPPER_REGISTRY_VERSION:-2}" \
        PATH="$PATH" \
        zsh -c "
            source \"$REPO_ROOT/lib/config/schema.zsh\"
            source \"$REPO_ROOT/lib/core/config.zsh\"
            source \"$REPO_ROOT/lib/core/registry.zsh\"
            source \"$REPO_ROOT/lib/core/fuzzy.zsh\"
            source \"$REPO_ROOT/lib/core/style.zsh\"
            source \"$REPO_ROOT/lib/core/help.zsh\"
            source \"$REPO_ROOT/lib/config/get.zsh\"
            source \"$REPO_ROOT/lib/config/set.zsh\"
            source \"$REPO_ROOT/lib/config/unset.zsh\"
            source \"$REPO_ROOT/lib/config/list.zsh\"
            source \"$REPO_ROOT/lib/config/edit.zsh\"
            source \"$REPO_ROOT/lib/config/dispatcher.zsh\"
            $zsh_cmd
        "
}

@test "dispatcher routes set with explicit value to global key" {
    _run_config_dispatch "_ckipper_config_dispatch set notify_bell false && _ckipper_config_dispatch get notify_bell"

    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "dispatcher routes set --account to account-scoped key" {
    _run_config_dispatch "_ckipper_config_dispatch set --account work always_docker true && _ckipper_config_dispatch get --account work always_docker"

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "dispatcher routes unset and reverts to schema default" {
    _run_config_dispatch "_ckipper_config_dispatch set notify_bell false && _ckipper_config_dispatch unset notify_bell && _ckipper_config_dispatch get notify_bell"

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "dispatcher rejects unknown key on set" {
    _run_config_dispatch "_ckipper_config_dispatch set not_a_key value"

    [ "$status" -ne 0 ]
}

@test "dispatcher unknown subcommand suggests help pointer" {
    _run_config_dispatch "_ckipper_config_dispatch nope"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "config help" ]]
}
