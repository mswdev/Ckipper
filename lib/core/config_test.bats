#!/usr/bin/env bats
# Module-level tests for lib/core/config.zsh.
# Verifies _core_config_get/set/unset/validate primitives against the schema
# from lib/config/schema.zsh. config.zsh is zsh-only, so each assertion spawns
# a zsh subshell that sources schema then config and runs the function under
# test (matching the pattern in registry_test.bats and schema_test.bats).

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

# Helper: source schema.zsh + config.zsh in zsh and run zsh_cmd.
_run_config() {
    local zsh_cmd="$1"
    run env HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        zsh -c "source \"$REPO_ROOT/lib/config/schema.zsh\"; source \"$REPO_ROOT/lib/core/config.zsh\"; $zsh_cmd"
}

@test "_core_config_get returns schema default when key is unset" {
    _run_config "_core_config_get notify_bell"

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "_core_config_get returns global value when set" {
    echo 'CKIPPER_NOTIFY_BELL="false"' >"$CKIPPER_DIR/docker/ckipper-config.zsh"

    _run_config "_core_config_get notify_bell"

    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "_core_config_get returns account override when set" {
    _run_config "_core_config_set always_docker true work && _core_config_get always_docker work"

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "_core_config_set writes global key idempotently" {
    _run_config "_core_config_set notify_bell false && _core_config_set notify_bell false"

    [ "$status" -eq 0 ]
    local count
    count=$(grep -c '^CKIPPER_NOTIFY_BELL=' "$CKIPPER_DIR/docker/ckipper-config.zsh")
    [ "$count" = "1" ]
}

@test "_core_config_validate accepts valid bool" {
    _run_config "_core_config_validate notify_bell true"
    [ "$status" -eq 0 ]

    _run_config "_core_config_validate notify_bell false"
    [ "$status" -eq 0 ]
}

@test "_core_config_validate rejects invalid bool" {
    _run_config "_core_config_validate notify_bell yes"

    [ "$status" -ne 0 ]
}

@test "_core_config_validate rejects unknown key" {
    _run_config "_core_config_validate not_a_real_key true"

    [ "$status" -ne 0 ]
}

@test "_core_config_unset removes the override and returns default" {
    _run_config "_core_config_set notify_bell false && _core_config_unset notify_bell && _core_config_get notify_bell"

    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "_core_config_get returns false when set false on per-account key with default true" {
    _run_config "_core_config_set ssh_forward false work && _core_config_get ssh_forward work"

    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

@test "_core_config_validate accepts integer-array values like \"3000\" and \"3000,3030,6006\"" {
    _run_config "_core_config_validate ports 3000"
    [ "$status" -eq 0 ]

    _run_config "_core_config_validate ports 3000,3030,6006"
    [ "$status" -eq 0 ]
}

@test "_core_config_validate rejects malformed int_array" {
    _run_config "_core_config_validate ports abc"
    [ "$status" -ne 0 ]

    _run_config "_core_config_validate ports 3000,abc"
    [ "$status" -ne 0 ]

    _run_config '_core_config_validate ports ""'
    [ "$status" -ne 0 ]
}

@test "_core_config_validate accepts string and path values trivially" {
    _run_config '_core_config_validate default_branch "main"'
    [ "$status" -eq 0 ]

    _run_config '_core_config_validate default_branch ""'
    [ "$status" -eq 0 ]

    _run_config '_core_config_validate projects_dir "/some/path"'
    [ "$status" -eq 0 ]
}

@test "_core_config_set rejects account-scoped key with no account argument" {
    _run_config "_core_config_set always_docker true"

    [ "$status" -ne 0 ]
    [[ "$output" == *"requires --account"* ]]
}

@test "_core_config_unset for account scope removes the override and returns default" {
    _run_config "_core_config_set ssh_forward false work && _core_config_get ssh_forward work && _core_config_unset ssh_forward work && _core_config_get ssh_forward work"

    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "false" ]
    [ "${lines[1]}" = "true" ]
}
