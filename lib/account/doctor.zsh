#!/usr/bin/env zsh
# Diagnostic check subcommand: doctor (with --fix to apply repairs).
#
# Also owns plugin-metadata path-rewrite logic (formerly lib/account/plugin-repair.zsh):
# in --fix mode, doctor calls _ckipper_account_repair_plugins for any account whose
# plugin metadata has stale ~/.claude/ paths. The repair functions kept their
# original names so their existing tests work unchanged.

readonly MIN_HOOK_FILES=4

# Module-level counters shared across all doctor helpers.
typeset -g _CKIPPER_DOCTOR_FAIL=0
typeset -g _CKIPPER_DOCTOR_WARN=0
# Module-level fix-mode flag set by `_ckipper_doctor --fix` and consumed by
# per-account checks (e.g. plugin metadata) to decide warn-only vs. repair.
typeset -g _CKIPPER_DOCTOR_FIX_MODE="false"

# Print a single check result and increment the appropriate counter.
#
# Uses _core_style_badge so badge color follows the project-wide style policy
# (NO_COLOR / TTY detection / CKIPPER_FORCE_COLOR override) instead of
# emitting raw ANSI codes that ignore the user's preferences.
#
# Args:
#   $1 — symbol: PASS, WARN, FAIL, or INFO
#   $2 — message text
#
# Returns:
#   0 always.
_ckipper_doctor_check() {
    local sym="$1" msg="$2"
    local badge
    case "$sym" in
        PASS) badge=$(_core_style_badge PASS green) ;;
        WARN) badge=$(_core_style_badge WARN yellow); (( _CKIPPER_DOCTOR_WARN += 1 )) ;;
        FAIL) badge=$(_core_style_badge FAIL red); (( _CKIPPER_DOCTOR_FAIL += 1 )) ;;
        INFO) badge="[INFO]" ;;
    esac
    printf '  %s %s\n' "$badge" "$msg"
}

# Check that all required ckipper tool files and hook files are deployed.
#
# Returns:
#   0 always (results printed via _ckipper_doctor_check).
_ckipper_doctor_tooling() {
    _core_style_header "Tooling"
    if [[ -d "$CKIPPER_DIR" ]]; then _ckipper_doctor_check PASS "$CKIPPER_DIR exists"; else _ckipper_doctor_check FAIL "$CKIPPER_DIR is missing — run install.sh"; fi
    if [[ -f "$CKIPPER_DIR/docker/ckipper.zsh" ]]; then _ckipper_doctor_check PASS "ckipper.zsh deployed"; else _ckipper_doctor_check FAIL "ckipper.zsh missing in $CKIPPER_DIR/docker/"; fi
    if [[ -f "$CKIPPER_DIR/docker/cleanup-projects.py" ]]; then _ckipper_doctor_check PASS "cleanup-projects.py deployed"; else _ckipper_doctor_check WARN "cleanup-projects.py missing — ckipper worktree rm cleanup will silently skip"; fi
    if [[ -f "$CKIPPER_DIR/settings-template.json" ]]; then _ckipper_doctor_check PASS "settings-template.json deployed"; else _ckipper_doctor_check WARN "settings-template.json missing — ckipper account add will skip seeding settings.json"; fi
    if [[ -d "$CKIPPER_DIR/hooks" ]] && (( $(ls -1 "$CKIPPER_DIR/hooks" 2>/dev/null | wc -l) >= MIN_HOOK_FILES )); then
        _ckipper_doctor_check PASS "hooks/ has ${MIN_HOOK_FILES}+ files"
    else
        _ckipper_doctor_check WARN "hooks/ is missing or has fewer than $MIN_HOOK_FILES hook files"
    fi
    _ckipper_doctor_check_stale_w_vars
}

# Detect pre-merge W_* variable assignments in ckipper-config.zsh.
#
# Pre-merge installs used W_PROJECTS_DIR / W_PORTS / W_EXTRA_VOLUMES /
# W_EXTRA_ENV / W_WORKTREES_DIR. Post-merge ckipper.zsh only reads the
# CKIPPER_* names, so any leftover W_* assignment is silently ignored — and
# the user's customizations are lost. Surface this loudly.
#
# Returns: 0 always (results printed via _ckipper_doctor_check).
_ckipper_doctor_check_stale_w_vars() {
    local cfg="$CKIPPER_DIR/docker/ckipper-config.zsh"
    [[ -f "$cfg" ]] || return 0
    if grep -qE '^[[:space:]]*W_(PROJECTS_DIR|WORKTREES_DIR|PORTS|EXTRA_VOLUMES|EXTRA_ENV)[[:space:]]*=' "$cfg"; then
        _ckipper_doctor_check FAIL "ckipper-config.zsh has stale W_* assignments — they're being ignored. Rename to CKIPPER_* (e.g. W_PORTS → CKIPPER_PORTS)."
    fi
}

# Check registry version, permissions, and default account validity.
#
# Returns:
#   0 if registry exists and checks run; 1 if registry file is missing.
_ckipper_doctor_registry() {
    echo ""
    _core_style_header "Registry"
    if [[ ! -f "$CKIPPER_REGISTRY" ]]; then
        _ckipper_doctor_check INFO "No registry yet — no accounts registered. Run: ckipper account add <name>"
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
        _ckipper_doctor_check WARN "no default account set — ckipper worktree run will require --account"
    elif jq -e --arg n "$default_acc" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
        _ckipper_doctor_check INFO "default account: $default_acc"
    else
        _ckipper_doctor_check FAIL "default account '$default_acc' is NOT in registry — fix with: ckipper account default <existing-account>"
    fi
}

# Detect whether an account's plugin metadata files contain stale ~/.claude/ paths.
#
# Args:
#   $1 — account config directory
#
# Returns:
#   0 if stale paths found; 1 otherwise.
_ckipper_doctor_has_stale_plugin_metadata() {
    local dir="$1" pm
    for pm in known_marketplaces.json installed_plugins.json; do
        [[ -f "$dir/plugins/$pm" ]] || continue
        grep -q -- "$HOME/.claude/" "$dir/plugins/$pm" 2>/dev/null && return 0
    done
    return 1
}

# Apply repair and report PASS/FAIL based on the post-repair state.
#
# Args:
#   $1 — account name
#   $2 — account config directory
#
# Returns:
#   0 always (results printed via _ckipper_doctor_check).
_ckipper_doctor_apply_plugin_repair() {
    local name="$1" dir="$2"
    _ckipper_account_repair_plugins "$name" >/dev/null 2>&1
    if _ckipper_doctor_has_stale_plugin_metadata "$dir"; then
        _ckipper_doctor_check FAIL "    plugins/*.json still has stale ~/.claude/ paths after repair attempt"
        return 0
    fi
    _ckipper_doctor_check PASS "    plugin metadata repaired (stale ~/.claude/ paths rewritten)"
}

# Check plugin metadata files for a single account for stale paths.
#
# In fix-mode (when _CKIPPER_DOCTOR_FIX_MODE is "true"), runs the in-place
# rewrite via _ckipper_account_repair_plugins and re-checks; emits PASS on
# successful repair. Otherwise emits WARN with a hint to run `doctor --fix`.
#
# Args:
#   $1 — account name
#   $2 — account config directory
#
# Returns:
#   0 always.
_ckipper_doctor_account_plugins() {
    local name="$1" dir="$2"
    _ckipper_doctor_has_stale_plugin_metadata "$dir" || return 0
    if [[ "$_CKIPPER_DOCTOR_FIX_MODE" = "true" ]]; then
        _ckipper_doctor_apply_plugin_repair "$name" "$dir"
        return 0
    fi
    _ckipper_doctor_check WARN "    plugins/*.json has stale ~/.claude/ paths — plugins will fail to load. Repair: ckipper doctor --fix"
}

# Rewrite stale absolute paths embedded in Claude Code's plugin metadata files
# (known_marketplaces.json, installed_plugins.json). After moving an account
# directory (legacy ~/.claude → ~/.claude-<name>), the plugin cache files on
# disk have moved with the rename, but the JSON metadata still has the old
# absolute paths baked in — Claude Code then fails to resolve plugins with
# "Plugin not found in marketplace ..." errors.
#
# Args:
#   $1 — old prefix (must end with `/`), e.g. "$HOME/.claude/"
#   $2 — new prefix (must end with `/`), e.g. "$HOME/.claude-personal/"
#
# Returns:
#   0 always (idempotent: if neither file contains old prefix, this is a no-op);
#   1 if arguments are invalid.
_ckipper_account_rewrite_plugin_paths() {
    local old="$1" new="$2"
    [[ -z "$old" || -z "$new" || "$old" != */ || "$new" != */ ]] && return 1
    [[ "$old" == "$new" ]] && return 0
    local f
    for f in plugins/known_marketplaces.json plugins/installed_plugins.json; do
        _ckipper_account_rewrite_single_plugin_file "$old" "$new" "$f"
    done
    return 0
}

# Rewrite stale paths in a single plugin metadata file using sed (in-place).
# Creates a timestamped backup before modifying the file.
#
# Args:
#   $1 — old prefix (must end with `/`)
#   $2 — new prefix (must end with `/`)
#   $3 — relative plugin file path (e.g. plugins/known_marketplaces.json)
#
# Returns:
#   0 always (no-op if file absent or old prefix not found).
_ckipper_account_rewrite_single_plugin_file() {
    local old="$1" new="$2" rel_path="$3"
    local fp="$new$rel_path"
    [[ -f "$fp" ]] || return 0
    grep -q -- "$old" "$fp" 2>/dev/null || return 0
    cp "$fp" "$fp.pre-rewrite-backup-$(date +%s)"
    if [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" == darwin* ]]; then
        sed -i '' "s|$old|$new|g" "$fp"
    else
        sed -i "s|$old|$new|g" "$fp"
    fi
}

# Detect the stale prefix in the plugin metadata files for the given account.
#
# Args:
#   $1 — account config directory path
#
# Returns:
#   0 always; prints stale prefix to stdout (empty if none found).
_ckipper_account_detect_stale_plugin_prefix() {
    local dir="$1"
    local f
    for f in plugins/known_marketplaces.json plugins/installed_plugins.json; do
        [[ -f "$dir/$f" ]] || continue
        local hit
        hit=$(grep -oE "$HOME/\.claude(-[a-z0-9_-]+)?/" "$dir/$f" 2>/dev/null \
            | sort -u | grep -v "^$dir/$" | head -1)
        if [[ -n "$hit" ]]; then
            printf '%s' "$hit"
            return 0
        fi
    done
}

# Rewrite stale absolute paths in plugin metadata for a single registered account.
#
# This is internal to doctor's --fix path; the public `ckipper account
# repair-plugins` subcommand was retired in favour of `ckipper doctor --fix`.
#
# Args:
#   $1 — registered account name
#
# Returns:
#   0 on success or when no repair is needed; 1 on error.
#
# Errors (stderr):
#   "Usage: ckipper doctor --fix (account: <name> required)" — when name is empty.
#   "Account '...' is not registered." — when account not found.
#   "Account dir does not exist: ..." — when directory is missing.
_ckipper_account_repair_plugins() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "Usage: _ckipper_account_repair_plugins <name> (called from ckipper doctor --fix)" >&2
        return 1
    fi
    _core_registry_check_version || return 1
    local dir
    dir=$(jq -r --arg n "$name" '.accounts[$n].config_dir // empty' "$CKIPPER_REGISTRY")
    if [[ -z "$dir" ]]; then
        echo "Account '$name' is not registered. Run: ckipper account list" >&2
        return 1
    fi
    if [[ ! -d "$dir" ]]; then
        echo "Account dir does not exist: $dir" >&2
        return 1
    fi
    _ckipper_account_repair_plugins_apply "$name" "$dir"
}

# Apply stale-prefix repair to an account directory once validation has passed.
#
# Args:
#   $1 — account name (for messages)
#   $2 — account config directory
#
# Returns:
#   0 on success or when no repair is needed.
_ckipper_account_repair_plugins_apply() {
    local name="$1" dir="$2"
    local stale_prefix
    stale_prefix=$(_ckipper_account_detect_stale_plugin_prefix "$dir")
    if [[ -z "$stale_prefix" ]]; then
        echo "No stale paths found in $dir/plugins/. Nothing to repair."
        return 0
    fi
    echo "Rewriting plugin metadata for '$name':"
    echo "  $stale_prefix → $dir/"
    _ckipper_account_rewrite_plugin_paths "$stale_prefix" "$dir/"
    echo "Done. Backups saved alongside each rewritten file (.pre-rewrite-backup-<ts>)."
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
    if [[ -d "$dir/hooks" ]]; then _ckipper_doctor_check PASS "    hooks/ deployed"; else _ckipper_doctor_check WARN "    hooks/ missing — run: ckipper account sync-hooks"; fi
    _ckipper_doctor_account_plugins "$name" "$dir"
    _ckipper_doctor_account_keychain "$svc" "$name"
}

# Iterate registry accounts and run per-account checks.
#
# Returns:
#   0 always.
_ckipper_doctor_accounts() {
    echo ""
    _core_style_header "Per-account state"
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
    _core_style_header "Aliases & shell integration"
    if [[ -f "$CKIPPER_DIR/aliases.zsh" ]]; then _ckipper_doctor_check PASS "aliases.zsh exists at $CKIPPER_DIR/aliases.zsh"
    else _ckipper_doctor_check WARN "aliases.zsh missing — will be regenerated on next add/remove"; fi
    if grep -q 'ckipper/aliases.zsh' "$HOME/.zshrc" 2>/dev/null; then _ckipper_doctor_check PASS "~/.zshrc sources aliases.zsh"
    else _ckipper_doctor_check WARN "~/.zshrc does NOT source aliases.zsh — add: [[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh"; fi
    if grep -q 'ckipper/docker/ckipper\.zsh' "$HOME/.zshrc" 2>/dev/null; then _ckipper_doctor_check PASS "~/.zshrc sources ckipper.zsh"
    else _ckipper_doctor_check FAIL "~/.zshrc does NOT source ckipper.zsh — re-run install.sh"; fi
    echo ""
    _core_style_header "Stub files (cosmetic)"
    if [[ -d "$HOME/.claude" ]]; then
        local stub_count; stub_count=$(ls -1A "$HOME/.claude" 2>/dev/null | wc -l | tr -d ' ')
        _ckipper_doctor_check WARN "~/.claude exists ($stub_count files) — Claude Code may have recreated it. Safe to: rm -rf ~/.claude"
    else
        _ckipper_doctor_check PASS "~/.claude (stub dir) is absent"
    fi
    if [[ -f "$HOME/.claude.json" ]]; then _ckipper_doctor_check WARN "~/.claude.json exists at home root — leftover from a pre-ckipper claude install."
    else _ckipper_doctor_check PASS "~/.claude.json (home root) is absent"; fi
}

# Print the three-state summary line (FAIL / WARN-only / all-passed).
#
# Returns:
#   0 if no FAILs; 1 if any FAILs.
_ckipper_doctor_summary() {
    echo ""
    _core_style_divider
    if (( _CKIPPER_DOCTOR_FAIL > 0 )); then
        local fail_part warn_part
        fail_part=$(_core_style_color red "$_CKIPPER_DOCTOR_FAIL FAIL")
        warn_part=$(_core_style_color yellow "$_CKIPPER_DOCTOR_WARN WARN")
        printf 'Result: %s, %s\n' "$fail_part" "$warn_part"
        return 1
    fi
    if (( _CKIPPER_DOCTOR_WARN > 0 )); then
        printf 'Result: %s\n' "$(_core_style_color yellow "$_CKIPPER_DOCTOR_WARN WARN")"
        return 0
    fi
    printf 'Result: %s\n' "$(_core_style_color green "all checks passed")"
}

# Run all diagnostic checks and print results to stdout.
#
# Args:
#   $1 — optional `--fix` flag; when set, doctor applies in-place repairs for
#        check categories that support it (currently: stale plugin metadata
#        paths). Without --fix, the same checks emit WARN with a hint.
#
# Returns:
#   0 if all checks pass (warnings are non-fatal); 1 if any FAIL checks are found.
_ckipper_doctor() {
    local should_fix="false"
    [[ "$1" == "--fix" ]] && { should_fix="true"; shift; }
    _CKIPPER_DOCTOR_FAIL=0
    _CKIPPER_DOCTOR_WARN=0
    _CKIPPER_DOCTOR_FIX_MODE="$should_fix"
    _ckipper_doctor_tooling
    if ! _ckipper_doctor_registry; then
        return 0
    fi
    _ckipper_doctor_accounts
    _ckipper_doctor_shell
    _ckipper_doctor_summary
}
