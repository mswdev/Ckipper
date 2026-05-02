#!/usr/bin/env bats
# Unit tests for lib/account/sync/registry.zsh — declarative type registry.

load "${BATS_TEST_DIRNAME}/../../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: source registry.zsh in a zsh subshell and run an expression.
run_in_zsh() {
    run env CKIPPER_DIR="$CKIPPER_DIR" \
        zsh -c "source \"$REPO_ROOT/lib/account/sync/registry.zsh\"; $*"
}

@test "registry declares all 10 sync types" {
    run_in_zsh 'echo ${(k)_CKIPPER_SYNC_TYPE_LABEL} | tr " " "\n" | sort | tr "\n" ","'
    [ "$status" -eq 0 ]
    [[ "$output" == *"agents,claude-md,commands,hooks,mcp,output-styles,prefs,settings,skills,statusline,"* ]]
}

@test "every type has a label" {
    run_in_zsh '
        for t in mcp settings claude-md agents commands output-styles skills statusline hooks prefs; do
            [[ -n "${_CKIPPER_SYNC_TYPE_LABEL[$t]}" ]] || { echo "missing label for $t"; exit 1; }
        done
        echo OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "every type has a kind in {structured, files-flat, files-dir, special}" {
    run_in_zsh '
        for t in mcp settings claude-md agents commands output-styles skills statusline hooks prefs; do
            kind="${_CKIPPER_SYNC_TYPE_KIND[$t]}"
            case "$kind" in
                structured|files-flat|files-dir|special) ;;
                *) echo "bad kind $kind for $t"; exit 1 ;;
            esac
        done
        echo OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "every type has at least one bundle membership" {
    run_in_zsh '
        for t in mcp settings claude-md agents commands output-styles skills statusline hooks prefs; do
            [[ -n "${_CKIPPER_SYNC_TYPE_BUNDLES[$t]}" ]] || { echo "missing bundles for $t"; exit 1; }
        done
        echo OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "_core_account_sync_resolve_bundle expands all to all 10 types" {
    run_in_zsh '_core_account_sync_resolve_bundle all | sort | tr "\n" ","'
    [ "$status" -eq 0 ]
    [[ "$output" == "agents,claude-md,commands,hooks,mcp,output-styles,prefs,settings,skills,statusline," ]]
}

@test "_core_account_sync_resolve_bundle expands customizations" {
    run_in_zsh '_core_account_sync_resolve_bundle customizations | sort | tr "\n" ","'
    [ "$status" -eq 0 ]
    [[ "$output" == "agents,claude-md,commands,hooks,mcp,output-styles,settings,skills,statusline," ]]
}

@test "_core_account_sync_resolve_bundle preferences = prefs" {
    run_in_zsh '_core_account_sync_resolve_bundle preferences | tr "\n" ","'
    [[ "$output" == "prefs," ]]
}

@test "_core_account_sync_resolve_bundle claude-config = mcp,settings,hooks" {
    run_in_zsh '_core_account_sync_resolve_bundle claude-config | sort | tr "\n" ","'
    [[ "$output" == "hooks,mcp,settings," ]]
}

@test "_core_account_sync_resolve_bundle returns input unchanged for non-bundle token" {
    run_in_zsh '_core_account_sync_resolve_bundle mcp | tr "\n" ","'
    [[ "$output" == "mcp," ]]
}

@test "_core_account_sync_resolve_includes mixes types and bundles, dedups" {
    run_in_zsh '_core_account_sync_resolve_includes "preferences,mcp" "" | sort | tr "\n" ","'
    [[ "$output" == "mcp,prefs," ]]
}

@test "_core_account_sync_resolve_includes subtracts excludes" {
    run_in_zsh '_core_account_sync_resolve_includes "all" "prefs,hooks" | sort | tr "\n" ","'
    [[ "$output" == "agents,claude-md,commands,mcp,output-styles,settings,skills,statusline," ]]
}

@test "_core_account_sync_is_known_type returns 0 for known type" {
    run_in_zsh '_core_account_sync_is_known_type mcp && echo ok'
    [[ "$output" == "ok" ]]
}

@test "_core_account_sync_is_known_type returns 1 for unknown" {
    run_in_zsh '_core_account_sync_is_known_type bogus && echo wrongly_ok || true'
    [ "$status" -eq 0 ]
    [[ "$output" != *"wrongly_ok"* ]]
}

@test "bundle names never collide with type ids" {
    run_in_zsh '
        for b in all customizations claude-config preferences; do
            if (( ${+_CKIPPER_SYNC_TYPE_LABEL[$b]} )); then
                echo "bundle $b collides with type id"
                exit 1
            fi
        done
        echo OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}
