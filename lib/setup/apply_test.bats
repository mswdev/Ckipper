#!/usr/bin/env bats
# Module-level tests for lib/setup/apply.zsh.
# apply.zsh is zsh-only — both functions iterate associative arrays via the
# zsh-only `${(@kP)name}` indirect-keys flag — so every assertion spawns a zsh
# subshell that sources schema.zsh + core/config.zsh + core/registry.zsh +
# setup/apply.zsh, then runs the function under test (matching the pattern in
# prompts_test.bats).
#
# Each assertion is chained inside a single `zsh -c` so the typeset -A array
# declared by the test is visible to the apply function and the post-write
# `_core_config_get` verification — the array would otherwise be discarded
# when the subshell exits.

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

# Helper: source schema + core/config + core/registry + setup/apply in zsh,
# run zsh_cmd, and let stderr/stdout merge into bats $output.
#
# Args: $1 — zsh command to execute.
# Side effect: populates $status / $output / $lines as with bats `run`.
_run_apply() {
    local zsh_cmd="$1"
    run env CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
            HOME="$TMP_HOME" PATH="$PATH" \
        zsh -c "
            source \"$REPO_ROOT/lib/config/schema.zsh\"
            source \"$REPO_ROOT/lib/core/config.zsh\"
            source \"$REPO_ROOT/lib/core/registry.zsh\"
            source \"$REPO_ROOT/lib/setup/apply.zsh\"
            $zsh_cmd
        "
}

@test "_ckipper_setup_apply_global writes each key in the array" {
    _run_apply '
        typeset -A updates=([notify_bell]=false [dep_install_cmd]="pnpm install")
        _ckipper_setup_apply_global updates || exit 1
        echo "bell=$(_core_config_get notify_bell)"
        echo "dep=$(_core_config_get dep_install_cmd)"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"bell=false"* ]]
    [[ "$output" == *"dep=pnpm install"* ]]
}

@test "_ckipper_setup_apply_global returns 0 with empty array" {
    _run_apply '
        typeset -A updates=()
        _ckipper_setup_apply_global updates
    '

    [ "$status" -eq 0 ]
}

@test "_ckipper_setup_apply_global returns 1 on validation failure" {
    # notify_bell is bool — "yes" is rejected by _core_config_validate.
    _run_apply '
        typeset -A updates=([notify_bell]=yes)
        _ckipper_setup_apply_global updates
    '

    [ "$status" -ne 0 ]
}

@test "_ckipper_setup_apply_account writes preferences for the named account" {
    _run_apply '
        typeset -A prefs=([always_docker]=true [ssh_forward]=false)
        _ckipper_setup_apply_account work prefs || exit 1
        echo "docker=$(_core_config_get always_docker work)"
        echo "ssh=$(_core_config_get ssh_forward work)"
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"docker=true"* ]]
    [[ "$output" == *"ssh=false"* ]]
}

@test "_ckipper_setup_apply_account returns 1 on unknown account" {
    _run_apply '
        typeset -A prefs=([always_docker]=true)
        _ckipper_setup_apply_account ghost prefs 2>/dev/null
    '

    [ "$status" -ne 0 ]
}
