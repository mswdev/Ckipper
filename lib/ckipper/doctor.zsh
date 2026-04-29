#!/usr/bin/env zsh
# Diagnostic check subcommand: doctor.

readonly MIN_HOOK_FILES=4

# Module-level counters shared across all doctor helpers.
typeset -g _CKIPPER_DOCTOR_FAIL=0
typeset -g _CKIPPER_DOCTOR_WARN=0

# Print a single check result and increment the appropriate counter.
#
# Args:
#   $1 — symbol: PASS, WARN, FAIL, or INFO
#   $2 — message text
#
# Returns:
#   0 always.
_ckipper_doctor_check() {
    local sym="$1" msg="$2"
    case "$sym" in
        PASS) printf "  \033[32m[PASS]\033[0m %s\n" "$msg" ;;
        WARN) printf "  \033[33m[WARN]\033[0m %s\n" "$msg"; (( _CKIPPER_DOCTOR_WARN += 1 )) ;;
        FAIL) printf "  \033[31m[FAIL]\033[0m %s\n" "$msg"; (( _CKIPPER_DOCTOR_FAIL += 1 )) ;;
        INFO) printf "  [INFO] %s\n" "$msg" ;;
    esac
}

# Check that all required ckipper tool files and hook files are deployed.
#
# Returns:
#   0 always (results printed via _ckipper_doctor_check).
_ckipper_doctor_tooling() {
    echo "── Tooling ───────────────────────────────────────────"
    if [[ -d "$CKIPPER_DIR" ]]; then _ckipper_doctor_check PASS "$CKIPPER_DIR exists"; else _ckipper_doctor_check FAIL "$CKIPPER_DIR is missing — run install.sh"; fi
    if [[ -f "$CKIPPER_DIR/docker/w-function.zsh" ]]; then _ckipper_doctor_check PASS "w-function.zsh deployed"; else _ckipper_doctor_check FAIL "w-function.zsh missing in $CKIPPER_DIR/docker/"; fi
    if [[ -f "$CKIPPER_DIR/docker/ckipper.zsh" ]]; then _ckipper_doctor_check PASS "ckipper.zsh deployed"; else _ckipper_doctor_check FAIL "ckipper.zsh missing in $CKIPPER_DIR/docker/"; fi
    if [[ -f "$CKIPPER_DIR/docker/cleanup-projects.py" ]]; then _ckipper_doctor_check PASS "cleanup-projects.py deployed"; else _ckipper_doctor_check WARN "cleanup-projects.py missing — w --rm cleanup will silently skip"; fi
    if [[ -f "$CKIPPER_DIR/settings-template.json" ]]; then _ckipper_doctor_check PASS "settings-template.json deployed"; else _ckipper_doctor_check WARN "settings-template.json missing — ckipper add will skip seeding settings.json"; fi
    if [[ -d "$CKIPPER_DIR/hooks" ]] && (( $(ls -1 "$CKIPPER_DIR/hooks" 2>/dev/null | wc -l) >= MIN_HOOK_FILES )); then
        _ckipper_doctor_check PASS "hooks/ has ${MIN_HOOK_FILES}+ files"
    else
        _ckipper_doctor_check WARN "hooks/ is missing or has fewer than $MIN_HOOK_FILES hook files"
    fi
}

# Check registry version, permissions, and default account validity.
#
# Returns:
#   0 if registry exists and checks run; 1 if registry file is missing.
_ckipper_doctor_registry() {
    echo ""
    echo "── Registry ──────────────────────────────────────────"
    if [[ ! -f "$CKIPPER_REGISTRY" ]]; then
        _ckipper_doctor_check INFO "No registry yet — no accounts registered. Run: ckipper migrate (or ckipper add <name>)"
        return 1
    fi
    local v; v=$(jq -r '.version // 0' "$CKIPPER_REGISTRY" 2>/dev/null)
    if [[ "$v" == "$CKIPPER_REGISTRY_VERSION" ]]; then _ckipper_doctor_check PASS "registry version $v matches expected"
    else _ckipper_doctor_check FAIL "registry version $v != expected $CKIPPER_REGISTRY_VERSION"; fi
    local perms; perms=$(_core_stat_perms "$CKIPPER_REGISTRY")
    if [[ "$perms" == "600" ]]; then _ckipper_doctor_check PASS "registry permissions 600"
    else _ckipper_doctor_check WARN "registry permissions $perms (expected 600)"; fi
    local default_acc; default_acc=$(jq -r '.default // ""' "$CKIPPER_REGISTRY")
    if [[ -z "$default_acc" ]]; then
        _ckipper_doctor_check WARN "no default account set — w/ckipper-add will require --account"
    elif jq -e --arg n "$default_acc" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
        _ckipper_doctor_check INFO "default account: $default_acc"
    else
        _ckipper_doctor_check FAIL "default account '$default_acc' is NOT in registry — fix with: ckipper default <existing-account>"
    fi
}

# Check plugin metadata files for a single account for stale paths.
#
# Args:
#   $1 — account name
#   $2 — account config directory
#
# Returns:
#   0 always.
_ckipper_doctor_account_plugins() {
    local name="$1" dir="$2"
    local stale_pm=0
    local pm
    for pm in known_marketplaces.json installed_plugins.json; do
        [[ -f "$dir/plugins/$pm" ]] || continue
        if grep -q -- "$HOME/.claude/" "$dir/plugins/$pm" 2>/dev/null; then
            stale_pm=1
        fi
    done
    if (( stale_pm )); then
        _ckipper_doctor_check WARN "    plugins/*.json has stale ~/.claude/ paths — plugins will fail to load. Repair: ckipper repair-plugins $name"
    fi
}

# Check macOS Keychain entry presence for a single account.
#
# Args:
#   $1 — keychain service string (may be empty)
#   $2 — account name
#
# Returns:
#   0 always (skips on non-darwin).
_ckipper_doctor_account_keychain() {
    local svc="$1" name="$2"
    [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" != darwin* ]] && return 0
    if [[ -z "$svc" ]]; then
        _ckipper_doctor_check INFO "    keychain_service: null (account uses on-disk credentials)"
    elif ! _core_keychain_validate "$svc"; then
        _ckipper_doctor_check FAIL "    keychain_service has invalid shape: $svc"
    elif security find-generic-password -s "$svc" >/dev/null 2>&1; then
        _ckipper_doctor_check PASS "    keychain entry present: $svc"
    else
        _ckipper_doctor_check WARN "    keychain entry NOT FOUND: $svc — re-run /login with: claude-$name"
    fi
}

# Check config directory, .claude.json, settings.json, hooks, and plugins for one account.
#
# Args:
#   $1 — account name
#
# Returns:
#   0 always.
_ckipper_doctor_account() {
    local name="$1"
    echo ""
    echo "  Account: $name"
    local dir; dir=$(jq -r --arg n "$name" '.accounts[$n].config_dir' "$CKIPPER_REGISTRY")
    local svc; svc=$(jq -r --arg n "$name" '.accounts[$n].keychain_service // ""' "$CKIPPER_REGISTRY")
    if [[ -d "$dir" ]]; then _ckipper_doctor_check PASS "    dir exists: $dir"
    else _ckipper_doctor_check FAIL "    dir missing: $dir"; fi
    if [[ -f "$dir/.claude.json" ]]; then
        local email; email=$(jq -r '.oauthAccount.emailAddress // "(none)"' "$dir/.claude.json" 2>/dev/null)
        local proj_count; proj_count=$(jq '.projects | length // 0' "$dir/.claude.json" 2>/dev/null)
        local mcp_count; mcp_count=$(jq '.mcpServers | length // 0' "$dir/.claude.json" 2>/dev/null)
        _ckipper_doctor_check PASS "    .claude.json: oauth=$email, projects=$proj_count, mcps=$mcp_count"
    else
        _ckipper_doctor_check WARN "    .claude.json missing in $dir"
    fi
    if [[ -f "$dir/settings.json" ]]; then _ckipper_doctor_check PASS "    settings.json present"; else _ckipper_doctor_check WARN "    settings.json missing"; fi
    if [[ -d "$dir/hooks" ]]; then _ckipper_doctor_check PASS "    hooks/ deployed"; else _ckipper_doctor_check WARN "    hooks/ missing — run: ckipper sync-hooks"; fi
    _ckipper_doctor_account_plugins "$name" "$dir"
    _ckipper_doctor_account_keychain "$svc" "$name"
}

# Iterate registry accounts and run per-account checks.
#
# Returns:
#   0 always.
_ckipper_doctor_accounts() {
    echo ""
    echo "── Per-account state ────────────────────────────────"
    local names; names=$(jq -r '.accounts | keys[]?' "$CKIPPER_REGISTRY")
    if [[ -z "$names" ]]; then
        _ckipper_doctor_check WARN "registry has no accounts"
        return 0
    fi
    local name
    while IFS= read -r name; do
        _ckipper_doctor_account "$name"
    done <<< "$names"
}

# Check aliases.zsh and .zshrc integration lines, plus stub dir/file presence.
#
# Returns:
#   0 always.
_ckipper_doctor_shell() {
    echo ""
    echo "── Aliases & shell integration ──────────────────────"
    if [[ -f "$CKIPPER_DIR/aliases.zsh" ]]; then _ckipper_doctor_check PASS "aliases.zsh exists at $CKIPPER_DIR/aliases.zsh"
    else _ckipper_doctor_check WARN "aliases.zsh missing — will be regenerated on next add/remove"; fi
    if grep -q 'ckipper/aliases.zsh' "$HOME/.zshrc" 2>/dev/null; then _ckipper_doctor_check PASS "~/.zshrc sources aliases.zsh"
    else _ckipper_doctor_check WARN "~/.zshrc does NOT source aliases.zsh — add: [[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh"; fi
    if grep -q 'ckipper/docker/w-function\.zsh' "$HOME/.zshrc" 2>/dev/null; then _ckipper_doctor_check PASS "~/.zshrc sources w-function.zsh"
    else _ckipper_doctor_check FAIL "~/.zshrc does NOT source w-function.zsh — re-run install.sh"; fi
    echo ""
    echo "── Stub files (cosmetic) ────────────────────────────"
    if [[ -d "$HOME/.claude" ]]; then
        local stub_count; stub_count=$(ls -1A "$HOME/.claude" 2>/dev/null | wc -l | tr -d ' ')
        _ckipper_doctor_check WARN "~/.claude exists ($stub_count files) — Claude Code may have recreated it. Safe to: rm -rf ~/.claude"
    else
        _ckipper_doctor_check PASS "~/.claude (stub dir) is absent"
    fi
    if [[ -f "$HOME/.claude.json" ]]; then _ckipper_doctor_check WARN "~/.claude.json exists at home root — should have been migrated. If you ran migrate, this is leftover."
    else _ckipper_doctor_check PASS "~/.claude.json (home root) is absent"; fi
}

# Print the three-state summary line (FAIL / WARN-only / all-passed).
#
# Returns:
#   0 if no FAILs; 1 if any FAILs.
_ckipper_doctor_summary() {
    echo ""
    echo "──────────────────────────────────────────────────────"
    if (( _CKIPPER_DOCTOR_FAIL > 0 )); then
        printf "Result: \033[31m%d FAIL\033[0m, \033[33m%d WARN\033[0m\n" "$_CKIPPER_DOCTOR_FAIL" "$_CKIPPER_DOCTOR_WARN"
        return 1
    elif (( _CKIPPER_DOCTOR_WARN > 0 )); then
        printf "Result: \033[33m%d WARN\033[0m\n" "$_CKIPPER_DOCTOR_WARN"
        return 0
    else
        printf "Result: \033[32mall checks passed\033[0m\n"
        return 0
    fi
}

# Run all diagnostic checks and print results to stdout.
#
# Returns:
#   0 if all checks pass (warnings are non-fatal); 1 if any FAIL checks are found.
_ckipper_doctor() {
    _CKIPPER_DOCTOR_FAIL=0
    _CKIPPER_DOCTOR_WARN=0
    _ckipper_doctor_tooling
    if ! _ckipper_doctor_registry; then
        return 0
    fi
    _ckipper_doctor_accounts
    _ckipper_doctor_shell
    _ckipper_doctor_summary
}
