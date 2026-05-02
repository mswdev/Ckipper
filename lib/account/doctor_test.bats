#!/usr/bin/env bats
# Unit tests for lib/account/doctor.zsh helpers.
# Sources ckipper.zsh (which wires up all lib/core/ + lib/account/ modules).
#
# Doctor.zsh also owns plugin-metadata path-rewrite logic (formerly in
# lib/account/plugin-repair.zsh). The plugin-repair tests below were merged
# into this file when `ckipper account repair-plugins` was retired in favour
# of `ckipper doctor --fix`.

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

# ── _ckipper_doctor_check ─────────────────────────────────────────────

@test "doctor_check PASS prints PASS label without incrementing counters" {
    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_check PASS "all good"
        echo "fail=$_CKIPPER_DOCTOR_FAIL warn=$_CKIPPER_DOCTOR_WARN"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "PASS" ]]
    [[ "$output" =~ "fail=0" ]]
    [[ "$output" =~ "warn=0" ]]
}

@test "doctor_check WARN prints WARN label and increments warn counter" {
    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_check WARN "something fishy"
        echo "fail=$_CKIPPER_DOCTOR_FAIL warn=$_CKIPPER_DOCTOR_WARN"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "WARN" ]]
    [[ "$output" =~ "warn=1" ]]
}

@test "doctor_check FAIL prints FAIL label and increments fail counter" {
    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_check FAIL "broken"
        echo "fail=$_CKIPPER_DOCTOR_FAIL warn=$_CKIPPER_DOCTOR_WARN"'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "FAIL" ]]
    [[ "$output" =~ "fail=1" ]]
}

# ── _ckipper_doctor_summary ───────────────────────────────────────────

@test "doctor_summary returns 0 when no FAILs or WARNs" {
    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_summary'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "all checks passed" ]]
}

@test "doctor_summary returns 0 when only WARNs (no FAILs)" {
    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=2
        _ckipper_doctor_summary'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "WARN" ]]
}

@test "doctor_summary returns 1 when there are FAILs" {
    run_helper '_CKIPPER_DOCTOR_FAIL=1; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_summary'

    [ "$status" -ne 0 ]
    [[ "$output" =~ "FAIL" ]]
}

# ── _ckipper_doctor_accounts ──────────────────────────────────────────

@test "doctor_accounts emits a WARN when the registry has no accounts" {
    echo '{"version":1,"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"

    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_accounts'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "WARN" ]]
    [[ "$output" =~ "no accounts" ]]
}

@test "doctor_accounts lists each registered account by name" {
    local acc_dir="$TMP_HOME/.claude-work"
    mkdir -p "$acc_dir"
    echo '{"version":1,"default":"work","accounts":{"work":{"config_dir":"'"$acc_dir"'","keychain_service":null}}}' > "$CKIPPER_REGISTRY"

    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_accounts'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "work" ]]
}

# ── _ckipper_doctor_tooling ───────────────────────────────────────────

@test "doctor_tooling emits PASS when ckipper dir exists" {
    # CKIPPER_DIR is already created by setup_isolated_env.
    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_tooling'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "PASS" ]]
    [[ "$output" =~ "exists" ]]
}

# ── plugin-metadata path rewrite (merged from plugin-repair_test.bats) ─

# ── _ckipper_account_detect_stale_plugin_prefix ──────────────────────────────

@test "detect_stale_plugin_prefix finds old prefix in known_marketplaces.json" {
    local acc_dir="$TMP_HOME/.claude-personal"
    mkdir -p "$acc_dir/plugins"
    # Write a marketplace file with a stale ~/.claude/ prefix.
    printf '{"url":"%s/plugins/marketplace.json"}' "$TMP_HOME/.claude/" \
        > "$acc_dir/plugins/known_marketplaces.json"

    run_helper "_ckipper_account_detect_stale_plugin_prefix \"$acc_dir\""

    [ "$status" -eq 0 ]
    [[ "$output" =~ ".claude/" ]]
}

# ── _ckipper_account_rewrite_plugin_paths ─────────────────────────────────────

@test "rewrite_plugin_paths replaces old prefix with new prefix in plugin files" {
    local old_dir="$TMP_HOME/.claude/"
    local new_dir="$TMP_HOME/.claude-personal/"
    mkdir -p "${new_dir}plugins"
    # Seed a marketplace file using the old prefix path.
    printf '{"url":"%s/plugins/marketplace.json"}' "$old_dir" \
        > "${new_dir}plugins/known_marketplaces.json"

    # Use darwin ostype so the code picks `sed -i ''` (macOS compatible form).
    run env \
        HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        _CKIPPER_TEST_OSTYPE="darwin" \
        CKIPPER_FORCE=1 \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; _ckipper_account_rewrite_plugin_paths \"$old_dir\" \"$new_dir\""

    [ "$status" -eq 0 ]
    grep -q "$new_dir" "${new_dir}plugins/known_marketplaces.json"
    ! grep -q "$old_dir" "${new_dir}plugins/known_marketplaces.json"
}

@test "rewrite_plugin_paths is idempotent — running twice produces the same result" {
    local old_dir="$TMP_HOME/.claude/"
    local new_dir="$TMP_HOME/.claude-personal/"
    mkdir -p "${new_dir}plugins"
    printf '{"url":"%s/plugins/marketplace.json"}' "$old_dir" \
        > "${new_dir}plugins/known_marketplaces.json"

    # First run — replaces old prefix with new prefix.
    run env \
        HOME="$TMP_HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" _CKIPPER_TEST_OSTYPE="darwin" CKIPPER_FORCE=1 \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; _ckipper_account_rewrite_plugin_paths \"$old_dir\" \"$new_dir\""
    local content_after_first; content_after_first=$(cat "${new_dir}plugins/known_marketplaces.json")

    # Second run — old prefix is gone so this is a no-op; output must be identical.
    run env \
        HOME="$TMP_HOME" CKIPPER_DIR="$CKIPPER_DIR" CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" _CKIPPER_TEST_OSTYPE="darwin" CKIPPER_FORCE=1 \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; _ckipper_account_rewrite_plugin_paths \"$old_dir\" \"$new_dir\""
    local content_after_second; content_after_second=$(cat "${new_dir}plugins/known_marketplaces.json")

    [ "$content_after_first" = "$content_after_second" ]
}

# ── doctor --fix integration ──────────────────────────────────────────

# Helper: seed registry + account dir + stale plugin metadata for --fix tests.
# Uses darwin ostype so the rewrite picks the macOS-compatible `sed -i ''` form,
# matching the host running these tests.
_seed_account_with_stale_plugins() {
    local name="$1"
    local acc_dir="$TMP_HOME/.claude-$name"
    mkdir -p "$acc_dir/plugins"
    # The fixture must use a prefix that differs from the new dir AND ends with `/`.
    # Using $TMP_HOME/.claude/ guarantees both conditions in the isolated env.
    printf '{"url":"%s/plugins/marketplace.json"}' "$TMP_HOME/.claude/" \
        > "$acc_dir/plugins/known_marketplaces.json"
    printf '{"version":2,"default":"%s","accounts":{"%s":{"config_dir":"%s","keychain_service":null}}}' \
        "$name" "$name" "$acc_dir" > "$CKIPPER_REGISTRY"
}

@test "doctor (no --fix) just WARNs on stale plugin paths and leaves the file unchanged" {
    _seed_account_with_stale_plugins personal
    local pm_file="$TMP_HOME/.claude-personal/plugins/known_marketplaces.json"
    local before; before=$(cat "$pm_file")

    run_helper '_ckipper_doctor'

    [[ "$output" =~ "WARN" ]]
    [[ "$output" =~ "stale" ]]
    # File was NOT rewritten.
    local after; after=$(cat "$pm_file")
    [ "$before" = "$after" ]
}

@test "doctor --fix repairs stale plugin paths and re-emits PASS for plugin metadata" {
    _seed_account_with_stale_plugins personal
    local pm_file="$TMP_HOME/.claude-personal/plugins/known_marketplaces.json"

    run env \
        HOME="$TMP_HOME" \
        CKIPPER_DIR="$CKIPPER_DIR" \
        CKIPPER_REGISTRY="$CKIPPER_REGISTRY" \
        PATH="$PATH" \
        _CKIPPER_TEST_OSTYPE="darwin" \
        CKIPPER_FORCE=1 \
        zsh -c "source \"$REPO_ROOT/ckipper.zsh\"; _ckipper_doctor --fix"

    [[ "$output" =~ "PASS" ]]
    [[ "$output" =~ "plugin metadata repaired" ]]
    # File now references the new prefix and the seeded stale prefix
    # ($TMP_HOME/.claude/) is gone. The rewrite produces a `.claude-<name>/`
    # substring (with a trailing slash from the new prefix), so we assert on
    # the substring `.claude-personal` rather than a specific concatenation.
    grep -q ".claude-personal" "$pm_file"
    ! grep -q "$TMP_HOME/.claude/" "$pm_file"
}

# ── _ckipper_doctor_check_preferences ─────────────────────────────────

@test "doctor flags account missing preferences block" {
    local acc_dir="$TMP_HOME/.claude-work"
    mkdir -p "$acc_dir"
    cat >"$CKIPPER_REGISTRY" <<JSON
{"version":2,"default":"work","accounts":{"work":{"config_dir":"$acc_dir","keychain_service":null,"registered_at":"t"}}}
JSON

    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_check_preferences'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "WARN" ]]
    [[ "$output" =~ "preferences" ]]
    [[ "$output" =~ "work" ]]
}

@test "doctor passes when accounts have valid preferences blocks" {
    local acc_dir="$TMP_HOME/.claude-work"
    mkdir -p "$acc_dir"
    cat >"$CKIPPER_REGISTRY" <<JSON
{"version":2,"default":"work","accounts":{"work":{"config_dir":"$acc_dir","keychain_service":null,"registered_at":"t","preferences":{"always_docker":false,"always_firewall":false,"ssh_forward":true}}}}
JSON

    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_check_preferences'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "PASS" ]]
    [[ "$output" =~ "preferences blocks valid" ]]
}

# ── _ckipper_doctor_check_config_keys ─────────────────────────────────

@test "doctor warns on unknown CKIPPER_ keys in ckipper-config.zsh" {
    mkdir -p "$CKIPPER_DIR/docker"
    cat >"$CKIPPER_DIR/docker/ckipper-config.zsh" <<'CFG'
CKIPPER_NOTIFY_BELL=true
CKIPPER_TYPO_KEY=foo
CFG

    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_check_config_keys'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "WARN" ]]
    [[ "$output" =~ "CKIPPER_TYPO_KEY" ]]
}

@test "doctor passes when every CKIPPER_ key in config file is in the schema" {
    mkdir -p "$CKIPPER_DIR/docker"
    cat >"$CKIPPER_DIR/docker/ckipper-config.zsh" <<'CFG'
CKIPPER_NOTIFY_BELL=true
CKIPPER_DEP_INSTALL_CMD="pnpm install"
CFG

    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_check_config_keys'

    [ "$status" -eq 0 ]
    [[ "$output" =~ "PASS" ]]
    [[ "$output" =~ "all known" ]]
}

@test "doctor accepts EXTRA_VOLUMES and EXTRA_ENV as power-user keys" {
    mkdir -p "$CKIPPER_DIR/docker"
    cat >"$CKIPPER_DIR/docker/ckipper-config.zsh" <<'CFG'
CKIPPER_EXTRA_VOLUMES=("foo:/foo")
CKIPPER_EXTRA_ENV=("BAR=baz")
CFG

    run_helper '_CKIPPER_DOCTOR_FAIL=0; _CKIPPER_DOCTOR_WARN=0
        _ckipper_doctor_check_config_keys'

    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "unknown keys" ]]
    [[ ! "$output" =~ "WARN" ]]
}
