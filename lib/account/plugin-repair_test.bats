#!/usr/bin/env bats
# Unit tests for lib/account/plugin-repair.zsh helpers.
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
