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
    echo '{"version":4,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_add_validate_name "myaccount"'

    [ "$status" -eq 0 ]
}

@test "validate_name accepts names with hyphens and underscores" {
    echo '{"version":4,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_add_validate_name "my-account_1"'

    [ "$status" -eq 0 ]
}

@test "validate_name rejects an empty name" {
    echo '{"version":4,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_add_validate_name ""'

    [ "$status" -ne 0 ]
    [[ "$output" =~ [Uu]sage ]]
}

@test "validate_name rejects names with uppercase letters" {
    echo '{"version":4,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_add_validate_name "MyAccount"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "must match" ]]
}

@test "validate_name rejects names with spaces" {
    echo '{"version":4,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_add_validate_name "my account"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "must match" ]]
}

@test "validate_name rejects a name already registered" {
    echo '{"version":4,"default":"work","accounts":{"work":{"config_dir":"/tmp/.claude-work"}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_add_validate_name "work"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "already registered" ]]
}

# ── _ckipper_account_finalize_registration ───────────────────────────────────

@test "finalize_registration writes only config_dir and registered_at" {
    echo '{"version":4,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_finalize_registration work /tmp/.claude-work adopt'

    [ "$status" -eq 0 ]
    [ "$(jq -r '.accounts.work.config_dir' "$CKIPPER_REGISTRY")" = "/tmp/.claude-work" ]
    [ "$(jq -r '.accounts.work | keys | join(",")' "$CKIPPER_REGISTRY")" = "config_dir,registered_at" ]
    [ "$(jq -r '.default' "$CKIPPER_REGISTRY")" = "work" ]
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
    echo '{"version":4,"default":"work","accounts":{"work":{"config_dir":"/tmp/.claude-work"}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_list'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "work" ]]
}

@test "list marks the default account with an asterisk" {
    echo '{"version":4,"default":"work","accounts":{"work":{"config_dir":"/tmp/.claude-work"}}}' > "$CKIPPER_REGISTRY"

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
    echo '{"version":4,"default":null,"accounts":{"work":{"config_dir":"/tmp/.claude-work"}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_default "work"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "work" ]]
    local val; val=$(jq -r '.default' "$CKIPPER_REGISTRY")
    [ "$val" = "work" ]
}

@test "default fails when account is not registered" {
    echo '{"version":4,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_default "nobody"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

# ── _ckipper_account_remove ───────────────────────────────────────────────────

@test "remove unregisters a known account and exits 0" {
    # Use $TMP_HOME-relative dir so the cleanup helpers find no directory and
    # don't prompt — this test only asserts the unregistration outcome.
    printf '{"version":4,"default":null,"accounts":{"tmp":{"config_dir":"%s/.claude-tmp"}}}\n' \
        "$TMP_HOME" > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_remove "tmp"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Unregistered" ]]
}

@test "remove fails for an account that is not registered" {
    echo '{"version":4,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_remove "nobody"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

# ── _ckipper_account_rename_validate ──────────────────────────────────────────

@test "rename_validate rejects an empty old name" {
    echo '{"version":4,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_rename_validate "" "newname"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ [Uu]sage ]]
}

@test "rename_validate rejects a new name with uppercase letters" {
    echo '{"version":4,"default":null,"accounts":{"old":{"config_dir":"/tmp/.claude-old"}}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_rename_validate "old" "NewName"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "must match" ]]
}

@test "rename_validate rejects rename when old name is not registered" {
    echo '{"version":4,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_rename_validate "ghost" "newname"'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "not registered" ]]
}

# ── _ckipper_account_add_check_credentials ───────────────────────────────────

@test "check_credentials passes when the derived Keychain entry exists" {
    local dir="$TMP_HOME/.claude-work"
    local service; service="Claude Code-credentials-$(printf '%s' "$dir" | shasum -a 256 | cut -c1-8)"

    run env HOME="$TMP_HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" _CKIPPER_TEST_OSTYPE="darwin19.0" SECURITY_STUB_SERVICES="$service" \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; _ckipper_account_add_check_credentials work '$dir'"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Found Keychain entry: $service" ]]
}

@test "check_credentials falls back to on-disk .credentials.json" {
    local dir="$TMP_HOME/.claude-work"
    mkdir -p "$dir"
    echo '{}' > "$dir/.credentials.json"

    run_helper "_ckipper_account_add_check_credentials work '$dir'"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "on-disk credentials" ]]
}

@test "check_credentials fails when neither store has the login" {
    local dir="$TMP_HOME/.claude-work"
    mkdir -p "$dir"

    run_helper "_ckipper_account_add_check_credentials work '$dir'"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Login may not have completed" ]]
}

# ── _ckipper_account_rename ──────────────────────────────────────────────────

@test "rename rewrites plugin metadata paths to the new dir" {
    local old_dir="$TMP_HOME/.claude-old"
    mkdir -p "$old_dir/plugins"
    printf '{"m":{"installLocation":"%s/plugins/marketplaces/m"}}' "$old_dir" > "$old_dir/plugins/known_marketplaces.json"
    printf '{"version":4,"default":"old","accounts":{"old":{"config_dir":"%s"}}}' "$old_dir" > "$CKIPPER_REGISTRY"

    run_helper 'ckipper account rename old new'

    [ "$status" -eq 0 ]
    local pm="$TMP_HOME/.claude-new/plugins/known_marketplaces.json"
    grep -q "$TMP_HOME/.claude-new/plugins/marketplaces/m" "$pm"
    ! grep -q "$TMP_HOME/.claude-old/" "$pm"
}

@test "rename tells the user to log in again and names the old Keychain entry" {
    local old_dir="$TMP_HOME/.claude-old"
    mkdir -p "$old_dir"
    printf '{"version":4,"default":"old","accounts":{"old":{"config_dir":"%s"}}}' "$old_dir" > "$CKIPPER_REGISTRY"
    local old_service; old_service="Claude Code-credentials-$(printf '%s' "$old_dir" | shasum -a 256 | cut -c1-8)"

    run env HOME="$TMP_HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" _CKIPPER_TEST_OSTYPE="darwin19.0" CKIPPER_FORCE=1 \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; ckipper account rename old new"

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Log in again" ]]
    [[ "$output" =~ "$old_service" ]]
}

# ── _ckipper_account_remove ──────────────────────────────────────────────────
# Regression: `account remove` performed `rm -rf` on the account's config dir
# (via _ckipper_account_cleanup_dir) without first asserting that no Claude
# process was running. A user with Claude open in another terminal could lose
# their live session's config dir. `account rename` already had the guard;
# `remove` is strictly more destructive and now mirrors it.

@test "account remove refuses to act when a Claude process is running" {
    local dir="$TMP_HOME/.claude-work"
    mkdir -p "$dir"
    cat > "$CKIPPER_REGISTRY" <<JSON
{"version":4,"default":"work","accounts":{"work":{"config_dir":"$dir","registered_at":"t","preferences":{}}}}
JSON

    # CKIPPER_FORCE=0 → the assert is enforced (not bypassed); PGREP_STUB_MATCH=1
    # → the pgrep stub reports a fake live Claude process.
    run env \
        HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        _CKIPPER_TEST_OSTYPE="darwin19.0" \
        CKIPPER_FORCE=0 \
        PGREP_STUB_MATCH=1 \
        CKIPPER_NO_GUM=1 \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; _ckipper_account_remove work"

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Claude process" ]]
    # Registry entry is still present (no destructive write happened).
    local accts
    accts=$(jq -r '.accounts | keys | length' "$CKIPPER_REGISTRY")
    [ "$accts" = "1" ]
    # Config dir is still present (no rm -rf happened).
    [[ -d "$dir" ]]
}

# ── _ckipper_account_default / remove registry-write error surfacing ─────────
# Regression: both functions called _core_registry_update without checking $?,
# then printed success ("Default account is now …" / "Unregistered …") even
# when the registry write silently failed. account_remove additionally
# proceeded to delete the config dir and keychain entry based on a registry
# state that didn't change.

@test "account default surfaces registry-update failure and does not print success" {
    cat > "$CKIPPER_REGISTRY" <<'JSON'
{"version":4,"default":null,"accounts":{"work":{"config_dir":"/tmp/.claude-work","registered_at":"t","preferences":{}}}}
JSON

    run_helper '
        _core_registry_update() { return 1; }
        _ckipper_account_default work
    '

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Error" ]]
    [[ ! "$output" =~ "Default account is now" ]]
}

@test "account remove surfaces registry-update failure and skips destructive cleanup" {
    local dir="$TMP_HOME/.claude-work"
    mkdir -p "$dir"
    cat > "$CKIPPER_REGISTRY" <<JSON
{"version":4,"default":"work","accounts":{"work":{"config_dir":"$dir","registered_at":"t","preferences":{}}}}
JSON

    run_helper '
        _core_registry_update() { return 1; }
        _ckipper_account_remove work
    '

    [ "$status" -ne 0 ]
    [[ "$output" =~ "Error" ]]
    [[ ! "$output" =~ "Unregistered" ]]
    # Config dir must NOT have been rm -rf'd because the registry write failed.
    [[ -d "$dir" ]]
    # Registry entry must still be present.
    local accts
    accts=$(jq -r '.accounts | keys | length' "$CKIPPER_REGISTRY")
    [ "$accts" = "1" ]
}

@test "validate_name rejects the desktop- prefix reserved for Desktop data dirs" {
    echo '{"version":4,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_ckipper_account_add_validate_name desktop-work'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "reserved" ]]
}
