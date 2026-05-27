#!/usr/bin/env zsh
# Desktop instance lifecycle subcommands: add, list, remove, rename.
#
# Owns the CRUD surface for ~/.ckipper/desktop.json — registry entries that
# pair a lowercase instance name with its user-data dir (~/.claude-desktop-
# <name>/) and its wrapper .app bundle path (~/Applications/Claude-<Name>.app).
#
# Boundary notes:
#   - Calls _ckipper_desktop_bundle_write (bundle.zsh) for .app generation.
#   - Calls _core_registry_{init,update,check_version}_at on
#     $CKIPPER_DESKTOP_REGISTRY, with $CKIPPER_REGISTRY_VERSION temporarily
#     scoped via the `VAR=val cmd` inline-env idiom (zsh assigns VAR for the
#     duration of cmd's invocation only — no global mutation).
#   - HOME-derived paths are computed at call time inside helpers, NOT stored
#     in module-level "constants", so per-test $HOME overrides take effect.

# Regex for valid instance names — lowercase alphanumeric, underscore, hyphen.
# Mirrors lib/account/account-management.zsh's name regex for consistency.
readonly _CKIPPER_DESKTOP_NAME_REGEX='^[a-z0-9_-]+$'

# Compute the user-data dir for a given instance name. HOME is read at call
# time so per-test overrides work; do NOT cache this in a module-level const.
#
# Args: $1 — instance name.
# Returns: 0 always. Prints the absolute path to stdout.
_ckipper_desktop_data_dir_for() {
    local name="$1"
    print -r -- "$HOME/.claude-desktop-${name}"
}

# Compute the .app bundle path for a given instance name. HOME is read at
# call time. Requires lib/desktop/bundle.zsh to be sourced (provides the
# title-case helper used here).
#
# Args: $1 — instance name (lowercase).
# Returns: 0 always. Prints the absolute path to stdout.
_ckipper_desktop_bundle_path_for() {
    local name="$1"
    local titled
    titled=$(_ckipper_desktop_bundle_title_case "$name")
    print -r -- "$HOME/Applications/Claude-${titled}.app"
}

# Validate a desktop instance name against _CKIPPER_DESKTOP_NAME_REGEX.
# Prints a usage line on empty input and a regex hint on invalid input.
#
# Args: $1 — proposed instance name.
# Returns: 0 if valid; 1 on empty or non-matching input.
#
# Errors (stderr):
#   "Usage: ckipper desktop add <name>" — when name is empty.
#   "Instance name must match ..."      — when name fails the regex.
_ckipper_desktop_validate_name() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "Usage: ckipper desktop add <name>" >&2
        return 1
    fi
    if [[ ! "$name" =~ $_CKIPPER_DESKTOP_NAME_REGEX ]]; then
        echo "Instance name must match ^[a-z0-9_-]+$ (lowercase alphanumeric, underscore, hyphen)." >&2
        return 1
    fi
}

# Assert that /Applications/Claude.app (or the test override) is installed.
# Reads $_CKIPPER_DESKTOP_SYSTEM_APP at call time so tests can override.
#
# Returns: 0 if the system Claude.app is present; 1 otherwise.
# Errors (stderr): "Claude.app not found at <path>. Install from <url>."
_ckipper_desktop_assert_claude_app() {
    [[ -d "$_CKIPPER_DESKTOP_SYSTEM_APP" ]] && return 0
    echo "Claude.app not found at $_CKIPPER_DESKTOP_SYSTEM_APP." >&2
    echo "Install Claude Desktop from https://claude.ai/download, then re-run." >&2
    return 1
}

# Initialize the desktop registry file and verify its version. Scopes
# $CKIPPER_REGISTRY_VERSION to the per-call inline-env so the accounts.json
# version global is not mutated.
#
# Returns: 0 on success; 1 on init failure or unsupported version.
_ckipper_desktop_init_registry() {
    CKIPPER_REGISTRY_VERSION="$CKIPPER_DESKTOP_REGISTRY_VERSION" \
        _core_registry_init_at "$CKIPPER_DESKTOP_REGISTRY" || return 1
    CKIPPER_REGISTRY_VERSION="$CKIPPER_DESKTOP_REGISTRY_VERSION" \
        _core_registry_check_version_at "$CKIPPER_DESKTOP_REGISTRY"
}

# Refuse if an instance with this name is already registered.
#
# Args: $1 — instance name.
# Returns: 0 if name is free; 1 if already present.
# Errors (stderr): "Desktop instance '<name>' is already registered."
_ckipper_desktop_assert_unique() {
    local name="$1"
    if jq -e --arg n "$name" '.instances[$n]' "$CKIPPER_DESKTOP_REGISTRY" >/dev/null 2>&1; then
        echo "Desktop instance '$name' is already registered." >&2
        return 1
    fi
}

# Refuse if the .app bundle path is already occupied by some other directory.
# Catches the case where a previous ckipper run left a partial bundle behind
# or where the user manually placed an app at that path.
#
# Args: $1 — bundle path.
# Returns: 0 if free; 1 if a file or directory already exists at that path.
# Errors (stderr): "Bundle path <path> already exists."
_ckipper_desktop_assert_no_bundle_collision() {
    local bundle="$1"
    if [[ -e "$bundle" ]]; then
        echo "Bundle path $bundle already exists. Remove it manually or pick a different name." >&2
        return 1
    fi
}

# Write the registry entry for a newly-registered instance. The entry shape
# mirrors what `desktop list` reads back: user_data_dir, app_bundle_path,
# registered_at (ISO 8601 UTC). Scopes $CKIPPER_REGISTRY_VERSION to the
# per-call inline-env.
#
# Args: $1 — instance name; $2 — user-data dir; $3 — bundle path.
# Returns: 0 on success; 1 on registry write failure.
_ckipper_desktop_register() {
    local name="$1" data_dir="$2" bundle="$3"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    CKIPPER_REGISTRY_VERSION="$CKIPPER_DESKTOP_REGISTRY_VERSION" \
        _core_registry_update_at "$CKIPPER_DESKTOP_REGISTRY" '
            .instances[$n] = {
                user_data_dir: $d,
                app_bundle_path: $b,
                registered_at: $t
            }
        ' --arg n "$name" --arg d "$data_dir" --arg b "$bundle" --arg t "$now"
}

# Count registered desktop instances. Used by the announce helper to decide
# whether the deep-link tip should fire (>= 2 means the user now has multiple
# instances and is at risk of OAuth callbacks landing in the wrong window).
#
# Returns: 0 always. Prints the count to stdout (0 if registry is missing).
_ckipper_desktop_instance_count() {
    [[ -f "$CKIPPER_DESKTOP_REGISTRY" ]] || { echo 0; return 0; }
    jq -r '.instances // {} | length' "$CKIPPER_DESKTOP_REGISTRY" 2>/dev/null || echo 0
}

# Print the post-add summary. When this brings the total instance count to
# two or more, also nudge the user toward `ckipper desktop login` to avoid
# the deep-link auth-routing pitfall (see lib/desktop/help.zsh::login text).
#
# Args: $1 — instance name; $2 — bundle path.
# Returns: 0 always.
_ckipper_desktop_add_announce() {
    local name="$1" bundle="$2"
    echo "Registered Desktop instance '$name'."
    echo "Bundle:    $bundle"
    echo "Data dir:  $(_ckipper_desktop_data_dir_for "$name")"
    local count
    count=$(_ckipper_desktop_instance_count)
    if (( count >= 2 )); then
        echo ""
        echo "Tip: with two or more Desktop instances installed, use \`ckipper desktop login <name>\`"
        echo "before running /login so the OAuth deep-link lands in the right window."
    fi
}

# Register a new Claude Desktop instance: create the user-data dir, generate
# its wrapper .app bundle, and record the entry in the desktop registry.
# Rolls back the data dir + bundle if the registry write fails.
#
# Args: $1 — instance name (must match _CKIPPER_DESKTOP_NAME_REGEX).
# Returns: 0 on success; 1 on validation, generation, or registry failure.
_ckipper_desktop_add() {
    local name="$1"
    _ckipper_desktop_validate_name "$name" || return 1
    _ckipper_desktop_assert_claude_app || return 1
    _ckipper_desktop_init_registry || return 1
    _ckipper_desktop_assert_unique "$name" || return 1
    local data_dir bundle
    data_dir=$(_ckipper_desktop_data_dir_for "$name")
    bundle=$(_ckipper_desktop_bundle_path_for "$name")
    _ckipper_desktop_assert_no_bundle_collision "$bundle" || return 1
    mkdir -p "$data_dir" "$HOME/Applications"
    if ! _ckipper_desktop_bundle_write "$name" "$bundle" "$data_dir"; then
        rm -rf "$data_dir" "$bundle"
        echo "Failed to write .app bundle; rolled back $data_dir and $bundle." >&2
        return 1
    fi
    if ! _ckipper_desktop_register "$name" "$data_dir" "$bundle"; then
        rm -rf "$data_dir" "$bundle"
        echo "Failed to write desktop registry; rolled back $data_dir and $bundle." >&2
        return 1
    fi
    _ckipper_desktop_add_announce "$name" "$bundle"
}
