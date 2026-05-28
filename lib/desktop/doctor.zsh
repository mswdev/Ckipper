#!/usr/bin/env zsh
# Diagnostic checks for Claude Desktop instances.
#
# Read-only (no --fix paths). Called by the top-level `doctor)` case in
# ckipper.zsh after _ckipper_doctor (the account/tooling doctor). Returns 0
# on all-pass-or-warns; 1 on any FAIL — the top-level dispatcher composes
# the rc via `|| rc=1`.
#
# Feature-dir isolation: this module calls ONLY lib/core/* helpers (notably
# _core_style_badge and _core_style_header). It does NOT reach into the
# account-namespace doctor helpers; counters are tracked locally.

# Module-level counters consumed by the orchestrator's exit-code decision.
# Kept local to the desktop namespace — no shared state with lib/account.
typeset -g _CKIPPER_DESKTOP_DOCTOR_FAIL=0
typeset -g _CKIPPER_DESKTOP_DOCTOR_WARN=0

# Print a doctor result line and update local counters.
#
# Mirrors the account-side doctor's check helper shape but tracks its own
# counters so the two doctor modules never collide. PASS and INFO are
# non-incrementing; WARN and FAIL bump the matching local counter.
#
# Args: $1 — PASS|WARN|FAIL|INFO; $2 — message.
# Returns: 0 always.
_ckipper_desktop_doctor_render() {
    local sym="$1" msg="$2" badge
    case "$sym" in
        PASS) badge=$(_core_style_badge PASS green) ;;
        WARN) badge=$(_core_style_badge WARN yellow); (( _CKIPPER_DESKTOP_DOCTOR_WARN += 1 )) ;;
        FAIL) badge=$(_core_style_badge FAIL red);    (( _CKIPPER_DESKTOP_DOCTOR_FAIL += 1 )) ;;
        INFO) badge="[INFO]" ;;
    esac
    printf '  %s %s\n' "$badge" "$msg"
}

# Check that the system Claude.app exists at $_CKIPPER_DESKTOP_SYSTEM_APP.
#
# On a CLI-only host with no registered instances the missing .app is
# expected — emit INFO and move on. With one or more instances registered,
# the .app is required (it's the open-target of every wrapper launcher), so
# its absence is a FAIL.
#
# Returns: 0 always (results printed via _ckipper_desktop_doctor_render).
_ckipper_desktop_doctor_claude_app_check() {
    if [[ -d "$_CKIPPER_DESKTOP_SYSTEM_APP" ]]; then
        _ckipper_desktop_doctor_render PASS "Claude.app present: $_CKIPPER_DESKTOP_SYSTEM_APP"
        return 0
    fi
    local count
    count=$(_ckipper_desktop_instance_count)
    if (( count >= 1 )); then
        _ckipper_desktop_doctor_render FAIL \
            "Claude.app missing at $_CKIPPER_DESKTOP_SYSTEM_APP — $count instance(s) registered but wrapper launchers cannot open it."
        return 0
    fi
    _ckipper_desktop_doctor_render INFO \
        "Claude.app not installed and no instances registered — skipping (CLI-only host)."
}

# Check that desktop.json (if present) parses and matches the expected
# schema version. Reads CKIPPER_DESKTOP_REGISTRY_VERSION via the inline-env
# scoping idiom so the accounts.json version global stays untouched.
#
# Returns: 0 always (results printed via _ckipper_desktop_doctor_render).
_ckipper_desktop_doctor_registry_check() {
    if [[ ! -f "$CKIPPER_DESKTOP_REGISTRY" ]]; then
        _ckipper_desktop_doctor_render INFO \
            "desktop.json not present (0 instances registered)."
        return 0
    fi
    if CKIPPER_REGISTRY_VERSION="$CKIPPER_DESKTOP_REGISTRY_VERSION" \
        _core_registry_check_version_at "$CKIPPER_DESKTOP_REGISTRY" >/dev/null 2>&1; then
        _ckipper_desktop_doctor_render PASS \
            "desktop.json version $CKIPPER_DESKTOP_REGISTRY_VERSION matches expected"
    else
        _ckipper_desktop_doctor_render FAIL \
            "desktop.json has unsupported version or is corrupt — restore from backup or remove."
    fi
}

# Check that one instance's user_data_dir exists on disk.
#
# Args: $1 — instance name; $2 — user_data_dir path.
# Returns: 0 always.
_ckipper_desktop_doctor_check_data_dir() {
    local name="$1" data_dir="$2"
    if [[ -d "$data_dir" ]]; then
        _ckipper_desktop_doctor_render PASS "    [$name] data dir present: $data_dir"
    else
        _ckipper_desktop_doctor_render FAIL "    [$name] data dir missing: $data_dir"
    fi
}

# Check that one instance's .app bundle and Info.plist exist; if plutil is
# on PATH, also lint the plist. plutil-missing emits INFO so CI containers
# without macOS tooling don't FAIL on what's a host-tooling gap.
#
# Args: $1 — instance name; $2 — app_bundle_path.
# Returns: 0 always.
_ckipper_desktop_doctor_check_bundle() {
    local name="$1" bundle="$2"
    local plist="$bundle/Contents/Info.plist"
    if [[ ! -d "$bundle" ]]; then
        _ckipper_desktop_doctor_render FAIL "    [$name] .app bundle missing: $bundle"
        return 0
    fi
    _ckipper_desktop_doctor_render PASS "    [$name] .app bundle present: $bundle"
    if [[ ! -f "$plist" ]]; then
        _ckipper_desktop_doctor_render FAIL "    [$name] Info.plist missing: $plist"
        return 0
    fi
    _ckipper_desktop_doctor_render PASS "    [$name] Info.plist present"
    _ckipper_desktop_doctor_check_plist_parse "$name" "$plist"
}

# Lint Info.plist via plutil when available. Skip with an INFO line otherwise.
#
# Args: $1 — instance name; $2 — plist path.
# Returns: 0 always.
_ckipper_desktop_doctor_check_plist_parse() {
    local name="$1" plist="$2"
    if ! command -v plutil >/dev/null 2>&1; then
        _ckipper_desktop_doctor_render INFO "    [$name] plutil missing, skipping plist parse"
        return 0
    fi
    if plutil -lint "$plist" >/dev/null 2>&1; then
        _ckipper_desktop_doctor_render PASS "    [$name] Info.plist parses cleanly"
    else
        _ckipper_desktop_doctor_render FAIL "    [$name] Info.plist failed plutil -lint"
    fi
}

# Iterate every registered instance and run the per-instance check trio.
# Silent (no header) when desktop.json is absent or empty — the registry
# check already surfaced the empty state.
#
# Returns: 0 always (results printed via _ckipper_desktop_doctor_render).
_ckipper_desktop_doctor_per_instance_check() {
    [[ -f "$CKIPPER_DESKTOP_REGISTRY" ]] || return 0
    local count
    count=$(_ckipper_desktop_instance_count)
    (( count == 0 )) && return 0
    local rows
    rows=$(jq -r '.instances // {} | to_entries[] | "\(.key)\t\(.value.user_data_dir)\t\(.value.app_bundle_path)"' \
        "$CKIPPER_DESKTOP_REGISTRY" 2>/dev/null)
    [[ -z "$rows" ]] && return 0
    local name data_dir bundle
    while IFS=$'\t' read -r name data_dir bundle; do
        _ckipper_desktop_doctor_check_data_dir "$name" "$data_dir"
        _ckipper_desktop_doctor_check_bundle "$name" "$bundle"
    done <<< "$rows"
}

# Print the deep-link routing reminder when 2+ instances are registered.
# Below the threshold this is silent — no PASS line, because this is a
# contextual nudge, not a pass/fail check.
#
# Returns: 0 always.
_ckipper_desktop_doctor_deep_link_warn() {
    local count
    count=$(_ckipper_desktop_instance_count)
    (( count < _CKIPPER_DESKTOP_DEEP_LINK_TIP_THRESHOLD )) && return 0
    _ckipper_desktop_doctor_render WARN \
        "2+ desktop instances registered — run 'ckipper desktop login <name>' before completing /login flows (claude:// deep-links route to the most-recently-active app)."
}

# Run the desktop-instance diagnostic section.
#
# Skipped entirely (one INFO line, rc 0) on non-macOS hosts. On macOS,
# resets local counters, prints a section header, and runs the four
# sub-checks (Claude.app, registry shape, per-instance, deep-link warn).
#
# Returns: 0 on all-pass-or-warns; 1 if any sub-check incremented the
#          local FAIL counter. The top-level doctor dispatcher composes
#          this rc with the account doctor's rc via `|| rc=1`.
_ckipper_desktop_doctor() {
    [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" == darwin* ]] || {
        _ckipper_desktop_doctor_render INFO "desktop: skipped (non-macOS)"
        return 0
    }
    _CKIPPER_DESKTOP_DOCTOR_FAIL=0
    _CKIPPER_DESKTOP_DOCTOR_WARN=0
    echo ""
    _core_style_header "Desktop instances"
    _ckipper_desktop_doctor_claude_app_check
    _ckipper_desktop_doctor_registry_check
    _ckipper_desktop_doctor_per_instance_check
    _ckipper_desktop_doctor_deep_link_warn
    (( _CKIPPER_DESKTOP_DOCTOR_FAIL > 0 )) && return 1
    return 0
}
