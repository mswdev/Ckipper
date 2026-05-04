#!/usr/bin/env bats
# Unit tests for lib/account/account-management.zsh helpers.
# Sources ckipper.zsh (which wires up all lib/core/ + lib/account/ modules).

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

# ── _ckipper_account_add_validate_name ───────────────────────────────────────

@test "validate_name accepts valid lowercase-alphanumeric names" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_add_validate_name "myaccount"'

    [ "$status" -eq 0 ]
}

@test "validate_name accepts names with hyphens and underscores" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_add_validate_name "my-account_1"'

    [ "$status" -eq 0 ]
}

@test "validate_name rejects an empty name" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_add_validate_name ""'

    [ "$status" -ne 0 ]
    [[ "$output" =~ [Uu]sage ]]
}

@test "validate_name rejects names with uppercase letters" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_add_validate_name "MyAccount"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "must match" ]]
}

@test "validate_name rejects names with spaces" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_add_validate_name "my account"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "must match" ]]
}

@test "validate_name rejects a name already registered" {
    echo '{"version":1,"default":"work","accounts":{"work":{"config_dir":"/tmp/.claude-work","keychain_service":null}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_add_validate_name "work"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "already registered" ]]
}

# ── _ckipper_account_finalize_registration ───────────────────────────────────

@test "account add stores preferences with safe defaults" {
    echo '{"version":2,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_CKIPPER_FINALIZE_CTX[name]="work"; _CKIPPER_FINALIZE_CTX[dir]="/tmp/.claude-work"; _CKIPPER_FINALIZE_CTX[service]=""; _ckipper_account_finalize_registration "adopt"'

    [ "$status" -eq 0 ]
    local always_docker always_firewall ssh_forward
    always_docker=$(jq -r '.accounts.work.preferences.always_docker' "$CKIPPER_REGISTRY")
    always_firewall=$(jq -r '.accounts.work.preferences.always_firewall' "$CKIPPER_REGISTRY")
    ssh_forward=$(jq -r '.accounts.work.preferences.ssh_forward' "$CKIPPER_REGISTRY")
    [ "$always_docker" = "false" ]
    [ "$always_firewall" = "false" ]
    [ "$ssh_forward" = "true" ]
}

# ── _ckipper_account_bare_alias_safe ─────────────────────────────────────────

@test "bare_alias_safe returns 1 for shell builtin 'cd'" {
    # 'cd' is a zsh builtin — using it as a bare alias would shadow it.
    run_helper '_ckipper_account_bare_alias_safe "cd" && echo SAFE || echo UNSAFE'

    [[ "$output" =~ "UNSAFE" ]]
}

@test "bare_alias_safe returns 0 for an invented name that cannot shadow anything" {
    # A random name with no PATH binary, no builtin, no alias.
    run_helper '_ckipper_account_bare_alias_safe "xyzzy_no_clash_9q7" && echo SAFE || echo UNSAFE'

    [[ "$output" =~ "SAFE" ]]
}

# ── _ckipper_account_list ────────────────────────────────────────────────────

@test "list shows 'No accounts' message when registry is missing" {
    rm -f "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_list'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "No accounts" ]]
}

@test "list shows registered account name" {
    echo '{"version":1,"default":"work","accounts":{"work":{"config_dir":"/tmp/.claude-work","keychain_service":null}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_list'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "work" ]]
}

@test "list marks the default account with an asterisk" {
    echo '{"version":1,"default":"work","accounts":{"work":{"config_dir":"/tmp/.claude-work","keychain_service":null}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_list'

    [ "$status" -eq 0 ]
    # Default marker is rendered in the trailing DEFAULT column (post-restyle).
    # Require `work` then non-newline padding then `*` on the SAME line.
    # [[:blank:]] is space/tab only (no \n) and [^[:cntrl:]] excludes \n, so
    # the legend line `* = default ...` cannot satisfy this regex via
    # cross-line matching.
    [[ "$output" =~ work[[:blank:]]+[^[:cntrl:]]*\* ]]
    [[ "$output" =~ "* = default" ]]
}

# ── _ckipper_account_default ──────────────────────────────────────────────────

@test "default sets the default account in the registry" {
    echo '{"version":1,"default":null,"accounts":{"work":{"config_dir":"/tmp/.claude-work","keychain_service":null}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_default "work"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "work" ]]
    local val; val=$(jq -r '.default' "$CKIPPER_REGISTRY")
    [ "$val" = "work" ]
}

@test "default fails when account is not registered" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_default "nobody"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

# ── _ckipper_account_remove ───────────────────────────────────────────────────

@test "remove unregisters a known account and exits 0" {
    # Use $TMP_HOME-relative dir so the cleanup helpers find no directory and
    # don't prompt — this test only asserts the unregistration outcome.
    printf '{"version":1,"default":null,"accounts":{"tmp":{"config_dir":"%s/.claude-tmp","keychain_service":null}}}\n' \
        "$TMP_HOME" > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_remove "tmp"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Unregistered" ]]
}

@test "remove fails for an account that is not registered" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_remove "nobody"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

# ── _ckipper_account_rename_validate ──────────────────────────────────────────

@test "rename_validate rejects an empty old name" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_rename_validate "" "newname"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ [Uu]sage ]]
}

@test "rename_validate rejects a new name with uppercase letters" {
    echo '{"version":1,"default":null,"accounts":{"old":{"config_dir":"/tmp/.claude-old","keychain_service":null}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_rename_validate "old" "NewName"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "must match" ]]
}

@test "rename_validate rejects rename when old name is not registered" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_rename_validate "ghost" "newname"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

# ── _ckipper_account_add_pick_keychain_entry ─────────────────────────────────
# Regression: zsh has no working `local -n` / `typeset -n`, so the previous
# nameref-style implementation silently leaked the picked value to a global
# named `_picked_ref` and the caller's variable stayed empty. The contract is
# now stdout-capture: the function echoes the picked service to stdout (or
# nothing on skip / no candidates).

@test "pick_keychain_entry echoes the picked service to stdout" {
    run_helper '
        _core_keychain_snapshot() { printf "Claude Code-credentials\nClaude Code-credentials-personal\n"; }
        _core_prompt_choose() { echo "Claude Code-credentials-personal"; }
        _core_keychain_validate() { return 0; }
        _ckipper_account_add_pick_keychain_entry myaccount
    '

    [ "$status" -eq 0 ]
    [ "$output" = "Claude Code-credentials-personal" ]
}

@test "pick_keychain_entry emits nothing on skip selection" {
    run_helper '
        _core_keychain_snapshot() { printf "Claude Code-credentials\n"; }
        _core_prompt_choose() { echo "$_CKIPPER_ACCOUNT_KEYCHAIN_SKIP_LABEL"; }
        _ckipper_account_add_pick_keychain_entry myaccount
    '

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "pick_keychain_entry emits nothing when keychain_snapshot returns no candidates" {
    run_helper '
        _core_keychain_snapshot() { :; }
        _ckipper_account_add_pick_keychain_entry myaccount
    '

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "pick_keychain_entry returns 1 with stderr error when picked service has bad shape" {
    run_helper '
        _core_keychain_snapshot() { echo "bogus-service"; }
        _core_prompt_choose() { echo "bogus-service"; }
        _core_keychain_validate() { return 1; }
        _ckipper_account_add_pick_keychain_entry myaccount
    '

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Invalid Keychain service shape" ]]
}
