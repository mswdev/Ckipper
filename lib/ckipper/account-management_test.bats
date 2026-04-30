#!/usr/bin/env bats
# Unit tests for lib/ckipper/account-management.zsh helpers.
# Sources ckipper.zsh (which wires up all lib/core/ + lib/ckipper/ modules).

load "${BATS_TEST_DIRNAME}/../../tests/lib/test-helper.bash"

setup() {
    setup_isolated_env
}

teardown() {
    teardown_isolated_env
}

# Helper: run a zsh expression with the full ckipper environment sourced.
run_helper() {
    run env \
        HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        _CKIPPER_TEST_OSTYPE="linux" \
        CKIPPER_FORCE=1 \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; $*"
}

# ── _ckipper_add_validate_name ───────────────────────────────────────

@test "validate_name accepts valid lowercase-alphanumeric names" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_add_validate_name "myaccount"'

    [ "$status" -eq 0 ]
}

@test "validate_name accepts names with hyphens and underscores" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_add_validate_name "my-account_1"'

    [ "$status" -eq 0 ]
}

@test "validate_name rejects an empty name" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_add_validate_name ""'

    [ "$status" -ne 0 ]
    [[ "$output" =~ [Uu]sage ]]
}

@test "validate_name rejects names with uppercase letters" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_add_validate_name "MyAccount"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "must match" ]]
}

@test "validate_name rejects names with spaces" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_add_validate_name "my account"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "must match" ]]
}

@test "validate_name rejects a name already registered" {
    echo '{"version":1,"default":"work","accounts":{"work":{"config_dir":"/tmp/.claude-work","keychain_service":null}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_add_validate_name "work"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "already registered" ]]
}

# ── _ckipper_bare_alias_safe ─────────────────────────────────────────

@test "bare_alias_safe returns 1 for shell builtin 'cd'" {
    # 'cd' is a zsh builtin — using it as a bare alias would shadow it.
    run_helper '_ckipper_bare_alias_safe "cd" && echo SAFE || echo UNSAFE'

    [[ "$output" =~ "UNSAFE" ]]
}

@test "bare_alias_safe returns 0 for an invented name that cannot shadow anything" {
    # A random name with no PATH binary, no builtin, no alias.
    run_helper '_ckipper_bare_alias_safe "xyzzy_no_clash_9q7" && echo SAFE || echo UNSAFE'

    [[ "$output" =~ "SAFE" ]]
}

# ── _ckipper_list ────────────────────────────────────────────────────

@test "list shows 'No accounts' message when registry is missing" {
    rm -f "$CKIPPER_REGISTRY"

    run_helper '_ckipper_list'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "No accounts" ]]
}

@test "list shows registered account name" {
    echo '{"version":1,"default":"work","accounts":{"work":{"config_dir":"/tmp/.claude-work","keychain_service":null}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_list'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "work" ]]
}

@test "list marks the default account with an asterisk" {
    echo '{"version":1,"default":"work","accounts":{"work":{"config_dir":"/tmp/.claude-work","keychain_service":null}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_list'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "* work" ]]
}

# ── _ckipper_default ──────────────────────────────────────────────────

@test "default sets the default account in the registry" {
    echo '{"version":1,"default":null,"accounts":{"work":{"config_dir":"/tmp/.claude-work","keychain_service":null}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_default "work"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "work" ]]
    local val; val=$(jq -r '.default' "$CKIPPER_REGISTRY")
    [ "$val" = "work" ]
}

@test "default fails when account is not registered" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_default "nobody"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

# ── _ckipper_remove ───────────────────────────────────────────────────

@test "remove unregisters a known account and exits 0" {
    echo '{"version":1,"default":null,"accounts":{"tmp":{"config_dir":"/tmp/.claude-tmp","keychain_service":null}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_remove "tmp"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Unregistered" ]]
}

@test "remove fails for an account that is not registered" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_remove "nobody"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

# ── _ckipper_rename_validate ──────────────────────────────────────────

@test "rename_validate rejects an empty old name" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_rename_validate "" "newname"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ [Uu]sage ]]
}

@test "rename_validate rejects a new name with uppercase letters" {
    echo '{"version":1,"default":null,"accounts":{"old":{"config_dir":"/tmp/.claude-old","keychain_service":null}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_rename_validate "old" "NewName"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "must match" ]]
}

@test "rename_validate rejects rename when old name is not registered" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_rename_validate "ghost" "newname"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}
