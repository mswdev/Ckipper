#!/usr/bin/env zsh
# Diagnostic check subcommand: doctor.

_ckipper_doctor() {
    local fail=0 warn=0
    local check() {
        local sym="$1" msg="$2"
        case "$sym" in
            PASS) printf "  \033[32m[PASS]\033[0m %s\n" "$msg" ;;
            WARN) printf "  \033[33m[WARN]\033[0m %s\n" "$msg"; (( warn++ )) ;;
            FAIL) printf "  \033[31m[FAIL]\033[0m %s\n" "$msg"; (( fail++ )) ;;
            INFO) printf "  [INFO] %s\n" "$msg" ;;
        esac
    }
    # Locally-scoped function for color output. zsh function nesting works at runtime.

    echo "── Tooling ───────────────────────────────────────────"
    if [[ -d "$CKIPPER_DIR" ]]; then check PASS "$CKIPPER_DIR exists"; else check FAIL "$CKIPPER_DIR is missing — run install.sh"; fi
    if [[ -f "$CKIPPER_DIR/docker/w-function.zsh" ]]; then check PASS "w-function.zsh deployed"; else check FAIL "w-function.zsh missing in $CKIPPER_DIR/docker/"; fi
    if [[ -f "$CKIPPER_DIR/docker/ckipper.zsh" ]]; then check PASS "ckipper.zsh deployed"; else check FAIL "ckipper.zsh missing in $CKIPPER_DIR/docker/"; fi
    if [[ -f "$CKIPPER_DIR/docker/cleanup-projects.py" ]]; then check PASS "cleanup-projects.py deployed"; else check WARN "cleanup-projects.py missing — w --rm cleanup will silently skip"; fi
    if [[ -f "$CKIPPER_DIR/settings-template.json" ]]; then check PASS "settings-template.json deployed"; else check WARN "settings-template.json missing — ckipper add will skip seeding settings.json"; fi
    if [[ -d "$CKIPPER_DIR/hooks" ]] && (( $(ls -1 "$CKIPPER_DIR/hooks" 2>/dev/null | wc -l) >= 4 )); then
        check PASS "hooks/ has 4+ files"
    else
        check WARN "hooks/ is missing or has fewer than 4 hook files"
    fi

    echo ""
    echo "── Registry ──────────────────────────────────────────"
    if [[ ! -f "$CKIPPER_REGISTRY" ]]; then
        check INFO "No registry yet — no accounts registered. Run: ckipper migrate (or ckipper add <name>)"
        return 0
    fi
    local v; v=$(jq -r '.version // 0' "$CKIPPER_REGISTRY" 2>/dev/null)
    if [[ "$v" == "$CKIPPER_REGISTRY_VERSION" ]]; then check PASS "registry version $v matches expected"
    else check FAIL "registry version $v != expected $CKIPPER_REGISTRY_VERSION"; fi
    local perms; perms=$(_core_stat_perms "$CKIPPER_REGISTRY")
    if [[ "$perms" == "600" ]]; then check PASS "registry permissions 600"
    else check WARN "registry permissions $perms (expected 600)"; fi

    local default_acc; default_acc=$(jq -r '.default // ""' "$CKIPPER_REGISTRY")
    if [[ -z "$default_acc" ]]; then
        check WARN "no default account set — w/ckipper-add will require --account"
    elif jq -e --arg n "$default_acc" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
        check INFO "default account: $default_acc"
    else
        check FAIL "default account '$default_acc' is NOT in registry — fix with: ckipper default <existing-account>"
    fi

    echo ""
    echo "── Per-account state ────────────────────────────────"
    local names; names=$(jq -r '.accounts | keys[]?' "$CKIPPER_REGISTRY")
    if [[ -z "$names" ]]; then
        check WARN "registry has no accounts"
    else
        while IFS= read -r name; do
            echo ""
            echo "  Account: $name"
            # Combined declare+assign: zsh 5.9 leaks "var=''" to stdout when the
            # `local x; x=$(...)` form runs inside a `while` loop body.
            local dir=$(jq -r --arg n "$name" '.accounts[$n].config_dir' "$CKIPPER_REGISTRY")
            local svc=$(jq -r --arg n "$name" '.accounts[$n].keychain_service // ""' "$CKIPPER_REGISTRY")
            if [[ -d "$dir" ]]; then check PASS "    dir exists: $dir"
            else check FAIL "    dir missing: $dir"; fi
            if [[ -f "$dir/.claude.json" ]]; then
                local email=$(jq -r '.oauthAccount.emailAddress // "(none)"' "$dir/.claude.json" 2>/dev/null)
                local proj_count=$(jq '.projects | length // 0' "$dir/.claude.json" 2>/dev/null)
                local mcp_count=$(jq '.mcpServers | length // 0' "$dir/.claude.json" 2>/dev/null)
                check PASS "    .claude.json: oauth=$email, projects=$proj_count, mcps=$mcp_count"
            else
                check WARN "    .claude.json missing in $dir"
            fi
            if [[ -f "$dir/settings.json" ]]; then check PASS "    settings.json present"; else check WARN "    settings.json missing"; fi
            if [[ -d "$dir/hooks" ]]; then check PASS "    hooks/ deployed"; else check WARN "    hooks/ missing — run: ckipper sync-hooks"; fi
            # Stale plugin-metadata paths: a sign that ckipper migrate moved
            # the account dir without rewriting absolute paths inside
            # plugins/{known_marketplaces,installed_plugins}.json. Symptom is
            # "Plugin not found in marketplace ..." in the Claude Code UI.
            local stale_pm=0
            for pm in known_marketplaces.json installed_plugins.json; do
                [[ -f "$dir/plugins/$pm" ]] || continue
                if grep -q -- "$HOME/.claude/" "$dir/plugins/$pm" 2>/dev/null; then
                    stale_pm=1
                fi
            done
            if (( stale_pm )); then
                check WARN "    plugins/*.json has stale ~/.claude/ paths — plugins will fail to load. Repair: ckipper repair-plugins $name"
            fi
            # Keychain check (macOS only)
            if [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" == darwin* ]]; then
                if [[ -z "$svc" ]]; then
                    check INFO "    keychain_service: null (account uses on-disk credentials)"
                elif ! _core_keychain_validate "$svc"; then
                    check FAIL "    keychain_service has invalid shape: $svc"
                elif security find-generic-password -s "$svc" >/dev/null 2>&1; then
                    check PASS "    keychain entry present: $svc"
                else
                    check WARN "    keychain entry NOT FOUND: $svc — re-run /login with: claude-$name"
                fi
            fi
        done <<< "$names"
    fi

    echo ""
    echo "── Aliases & shell integration ──────────────────────"
    if [[ -f "$CKIPPER_DIR/aliases.zsh" ]]; then check PASS "aliases.zsh exists at $CKIPPER_DIR/aliases.zsh"
    else check WARN "aliases.zsh missing — will be regenerated on next add/remove"; fi
    if grep -q 'ckipper/aliases.zsh' "$HOME/.zshrc" 2>/dev/null; then check PASS "~/.zshrc sources aliases.zsh"
    else check WARN "~/.zshrc does NOT source aliases.zsh — add: [[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh"; fi
    if grep -q 'ckipper/docker/w-function\.zsh' "$HOME/.zshrc" 2>/dev/null; then check PASS "~/.zshrc sources w-function.zsh"
    else check FAIL "~/.zshrc does NOT source w-function.zsh — re-run install.sh"; fi

    echo ""
    echo "── Stub files (cosmetic) ────────────────────────────"
    if [[ -d "$HOME/.claude" ]]; then
        local stub_count; stub_count=$(ls -1A "$HOME/.claude" 2>/dev/null | wc -l | tr -d ' ')
        check WARN "~/.claude exists ($stub_count files) — Claude Code may have recreated it. Safe to: rm -rf ~/.claude"
    else
        check PASS "~/.claude (stub dir) is absent"
    fi
    if [[ -f "$HOME/.claude.json" ]]; then check WARN "~/.claude.json exists at home root — should have been migrated. If you ran migrate, this is leftover."
    else check PASS "~/.claude.json (home root) is absent"; fi

    echo ""
    echo "──────────────────────────────────────────────────────"
    if (( fail > 0 )); then
        printf "Result: \033[31m%d FAIL\033[0m, \033[33m%d WARN\033[0m\n" "$fail" "$warn"
        return 1
    elif (( warn > 0 )); then
        printf "Result: \033[33m%d WARN\033[0m\n" "$warn"
        return 0
    else
        printf "Result: \033[32mall checks passed\033[0m\n"
        return 0
    fi
}
