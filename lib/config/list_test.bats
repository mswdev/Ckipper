#!/usr/bin/env bats
# Module-level tests for lib/config/list.zsh.
# Verifies the three output formats (table, json, env) and account-scope
# filtering. The handler is zsh-only and depends on Phase-2 style helpers
# (_core_style_header / _core_style_divider) — those are stubbed in the
# zsh -c payload before sourcing list.zsh.

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
    mkdir -p "$CKIPPER_DIR/docker"
    : >"$CKIPPER_DIR/docker/ckipper-config.zsh"
    cat >"$CKIPPER_REGISTRY" <<'JSON'
{"version":2,"default":"work","accounts":{"work":{"config_dir":"/x","keychain_service":null,"registered_at":"t","preferences":{}}}}
JSON
}

teardown() {
    teardown_isolated_env
}

# Helper: source schema + core/config + Phase-2 style stubs + list, then run cmd.
_run_config_list() {
    local zsh_cmd="$1"
    run env HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        zsh -c "
            source \"$REPO_ROOT/lib/config/schema.zsh\"
            source \"$REPO_ROOT/lib/core/config.zsh\"
            source \"$REPO_ROOT/lib/core/registry.zsh\"
            _core_style_header() { print -- \"## \$1\"; }
            _core_style_divider() { print -- \"---\"; }
            source \"$REPO_ROOT/lib/config/list.zsh\"
            $zsh_cmd
        "
}

@test "list table includes every global key" {
    _run_config_list "_ckipper_config_list"

    [ "$status" -eq 0 ]
    [[ "$output" == *"notify_bell"* ]]
    [[ "$output" == *"default_branch"* ]]
    [[ "$output" == *"dep_install_cmd"* ]]
}

@test "list json is valid JSON" {
    _run_config_list "_ckipper_config_list --format=json"

    [ "$status" -eq 0 ]
    echo "$output" | jq empty
}

@test "list env emits CKIPPER_<UPPER> lines" {
    _run_config_list "_ckipper_config_list --format=env"

    [ "$status" -eq 0 ]
    [[ "$output" == *"CKIPPER_NOTIFY_BELL="* ]]
}

@test "list --account adds account-scoped keys" {
    _run_config_list "_ckipper_config_list --account work"

    [ "$status" -eq 0 ]
    [[ "$output" == *"always_docker"* ]]
    [[ "$output" == *"ssh_forward"* ]]
}
