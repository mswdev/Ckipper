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

# Helper: source schema.zsh + registry.zsh + config.zsh in zsh and run zsh_cmd.
# registry.zsh is sourced because account-scoped writes in config.zsh now route
# through _core_registry_update for lock-protected, atomic updates (I-1 fix).
_run_config() {
    local zsh_cmd="$1"
    run env HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        zsh -c "
            source \"$REPO_ROOT/lib/config/schema.zsh\"
            source \"$REPO_ROOT/lib/core/registry.zsh\"
            source \"$REPO_ROOT/lib/core/config.zsh\"
            $zsh_cmd
        "
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

@test "_core_config_validate allows variable-style \$ in path values" {
    # Users routinely set projects_dir to e.g. \$HOME/Developer; the global file
    # is sourced as zsh, so the expansion happens at shell-startup time.
    # The escaped \$ ensures the validator sees the literal "$HOME/..." string
    # (not pre-expanded by the zsh -c host) — the whole point of this test.
    _run_config '_core_config_validate projects_dir "\$HOME/Developer"'
    [ "$status" -eq 0 ]

    _run_config '_core_config_validate projects_dir "\${HOME}/code"'
    [ "$status" -eq 0 ]
}

@test "_core_config_validate rejects shell-breakout chars in string/path values" {
    # The global config file is sourced by zsh, so these would otherwise execute
    # arbitrary code on every shell start. Each character class is a distinct
    # breakout vector; assert each is rejected.
    _run_config '_core_config_validate projects_dir "evil\"; rm -rf /; echo \""'
    [ "$status" -ne 0 ]

    _run_config '_core_config_validate projects_dir "\`whoami\`"'
    [ "$status" -ne 0 ]

    _run_config '_core_config_validate projects_dir "\$(whoami)"'
    [ "$status" -ne 0 ]

    _run_config '_core_config_validate projects_dir "back\\\\slash"'
    [ "$status" -ne 0 ]

    _run_config '_core_config_validate dep_install_cmd "npm install \$(echo bad)"'
    [ "$status" -ne 0 ]
}

@test "_core_config_set persists no shell injection through the global file" {
    # End-to-end: a quote-breakout value passed to _core_config_set must NOT
    # land in the sourced config file. Verifies the validator gates the writer.
    _run_config '_core_config_set projects_dir "evil\"; export INJECTED=1; echo \""'

    [ "$status" -ne 0 ]
    run grep -F 'INJECTED=1' "$CKIPPER_DIR/docker/ckipper-config.zsh"
    [ "$status" -ne 0 ]
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

# I-1 regression: account-scoped registry writes must go through the locked
# update primitive (_core_registry_update). Stubbing _core_registry_update to
# leave a marker file proves the routing — if a writer bypasses the lock and
# does its own `mktemp + mv`, the stub never runs and the marker is missing.

@test "_core_config_set account-scoped routes through _core_registry_update" {
    local marker="$CKIPPER_DIR/_registry_update_called"

    _run_config "
        _core_registry_update() { : > '$marker'; return 0; }
        _core_config_set always_docker true work
    "

    [ "$status" -eq 0 ]
    [ -f "$marker" ]
}

@test "_core_config_unset account-scoped routes through _core_registry_update" {
    local marker="$CKIPPER_DIR/_registry_update_called"

    _run_config "
        _core_registry_update() { : > '$marker'; return 0; }
        _core_config_unset always_docker work
    "

    [ "$status" -eq 0 ]
    [ -f "$marker" ]
}
