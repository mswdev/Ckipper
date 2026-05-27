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

# Column widths (chars) used when rendering `ckipper desktop list` rows.
# Matched against the header printed by _ckipper_desktop_list_header.
readonly _CKIPPER_DESKTOP_LIST_COL_NAME=14
readonly _CKIPPER_DESKTOP_LIST_COL_DATA_DIR=30
readonly _CKIPPER_DESKTOP_LIST_COL_BUNDLE=36
readonly _CKIPPER_DESKTOP_LIST_COL_REGISTERED=22

# Print the column-header row for `ckipper desktop list`.
#
# Returns: 0 always.
_ckipper_desktop_list_header() {
    printf '%-*s%-*s%-*s%-*s%s\n' \
        "$_CKIPPER_DESKTOP_LIST_COL_NAME" "NAME" \
        "$_CKIPPER_DESKTOP_LIST_COL_DATA_DIR" "DATA-DIR" \
        "$_CKIPPER_DESKTOP_LIST_COL_BUNDLE" "BUNDLE" \
        "$_CKIPPER_DESKTOP_LIST_COL_REGISTERED" "REGISTERED" \
        "STATUS"
}

# Shorten an absolute path under $HOME to a `~/`-prefixed form for display.
# Mirrors lib/account/account-management.zsh::_ckipper_account_list_short_dir;
# extracted again here because the account namespace is off-limits to siblings.
#
# Args: $1 — absolute path.
# Returns: 0 always; prints the (possibly shortened) path.
_ckipper_desktop_list_short_path() {
    local path="$1"
    [[ "$path" == "$HOME"* ]] && printf '~%s' "${path#$HOME}" || printf '%s' "$path"
}

# Decide running status for a desktop instance by checking whether any
# process has the instance's --user-data-dir on its command line. This is
# the same probe used by `desktop remove` / `desktop rename` to refuse
# destructive ops on a live instance.
#
# Args: $1 — user-data dir to probe.
# Returns: 0 always. Prints "running" or "stopped" to stdout.
_ckipper_desktop_list_status() {
    local data_dir="$1"
    if pgrep -f -- "--user-data-dir=$data_dir" >/dev/null 2>&1; then
        echo "running"
    else
        echo "stopped"
    fi
}

# Print a single instance row for `ckipper desktop list`.
#
# Args:
#   $1 — instance name
#   $2 — user-data dir
#   $3 — app bundle path
#
# Reads `_CKIPPER_DESKTOP_LIST_REGISTERED_AT` (set by `_ckipper_desktop_list`
# before invoking) so this helper stays at the 3-parameter cap. The list
# loop pipes name/dir/bundle/registered_at as 4 tab-separated columns; we
# stash the timestamp in a module global to avoid a 4th positional.
_ckipper_desktop_list_row() {
    local name="$1" data_dir="$2" bundle="$3"
    local registered="$_CKIPPER_DESKTOP_LIST_REGISTERED_AT"
    # NB: zsh's $status is a read-only special, so this var is `run_status`.
    local short_data short_bundle run_status
    short_data=$(_ckipper_desktop_list_short_path "$data_dir")
    short_bundle=$(_ckipper_desktop_list_short_path "$bundle")
    run_status=$(_ckipper_desktop_list_status "$data_dir")
    printf '%-*s%-*s%-*s%-*s%s\n' \
        "$_CKIPPER_DESKTOP_LIST_COL_NAME" "$name" \
        "$_CKIPPER_DESKTOP_LIST_COL_DATA_DIR" "$short_data" \
        "$_CKIPPER_DESKTOP_LIST_COL_BUNDLE" "$short_bundle" \
        "$_CKIPPER_DESKTOP_LIST_COL_REGISTERED" "$registered" \
        "$run_status"
}

# Module-level scratchpad for the in-progress list row. See
# _ckipper_desktop_list_row's doc-header for why this is global.
typeset -g _CKIPPER_DESKTOP_LIST_REGISTERED_AT=""

# Print the empty-registry hint message when no instances are registered.
#
# Returns: 0 always.
_ckipper_desktop_list_empty_hint() {
    echo "No Desktop instances registered. Run: ckipper desktop add <name>"
}

# Iterate the registry's .instances object and print one row per instance.
# Extracted from `_ckipper_desktop_list` so the orchestrator stays under
# the 25-line cap.
#
# Returns: 0 always.
_ckipper_desktop_list_print_rows() {
    jq -r '.instances // {} | to_entries[] | "\(.key)\t\(.value.user_data_dir)\t\(.value.app_bundle_path)\t\(.value.registered_at // "-")"' \
        "$CKIPPER_DESKTOP_REGISTRY" | \
        while IFS=$'\t' read -r name data_dir bundle registered; do
            _CKIPPER_DESKTOP_LIST_REGISTERED_AT="$registered"
            _ckipper_desktop_list_row "$name" "$data_dir" "$bundle"
        done
}

# Refuse if a Claude Desktop process is currently running against the given
# user-data dir. Used by `desktop remove` and `desktop rename` to block
# destructive ops on a live instance.
#
# TODO(Task 9): replace with _ckipper_desktop_assert_not_running once that
# helper lands. Inlined here because remove/rename need the check before
# the launcher module exists.
#
# Args: $1 — user-data dir to probe.
# Returns: 0 if no matching process; 1 otherwise.
# Errors (stderr): "Refusing: ..." when a matching process is found.
_ckipper_desktop_assert_not_running() {
    local data_dir="$1"
    pgrep -f -- "--user-data-dir=$data_dir" >/dev/null 2>&1 || return 0
    echo "Refusing: a Claude Desktop instance is running for $data_dir." >&2
    echo "Quit it first, then re-run." >&2
    return 1
}

# Look up the user-data dir for a registered instance.
#
# Args: $1 — instance name.
# Returns: 0 if registered; 1 if not.
# Errors (stderr): "Desktop instance '<name>' is not registered."
_ckipper_desktop_data_dir_of() {
    local name="$1"
    if ! jq -e --arg n "$name" '.instances[$n]' "$CKIPPER_DESKTOP_REGISTRY" >/dev/null 2>&1; then
        echo "Desktop instance '$name' is not registered." >&2
        return 1
    fi
    jq -r --arg n "$name" '.instances[$n].user_data_dir' "$CKIPPER_DESKTOP_REGISTRY"
}

# Look up the app bundle path for a registered instance. Assumes the caller
# has already verified registration via _ckipper_desktop_data_dir_of.
#
# Args: $1 — instance name.
# Returns: 0 always. Prints the bundle path to stdout.
_ckipper_desktop_bundle_of() {
    local name="$1"
    jq -r --arg n "$name" '.instances[$n].app_bundle_path' "$CKIPPER_DESKTOP_REGISTRY"
}

# Prompt the user to delete the user-data dir for a removed instance.
# Default is N — preserves user data (chats, settings, OAuth tokens).
#
# Args: $1 — instance name (label only); $2 — user-data dir path.
# Returns: 0 always.
_ckipper_desktop_remove_prompt_data_dir() {
    local name="$1" data_dir="$2"
    [[ -d "$data_dir" ]] || return 0
    if _core_prompt_confirm "Delete data dir $data_dir? (chats, settings, OAuth tokens)"; then
        rm -rf "$data_dir"
        echo "Deleted $data_dir."
        return 0
    fi
    echo "Kept $data_dir. To delete later: rm -rf '$data_dir'"
}

# Prompt the user to delete the .app bundle for a removed instance.
# Default is N (gum confirm defaults to no) — but the bundle is regeneratable
# via `ckipper desktop add <same-name>`, so the prompt text steers toward yes.
#
# Args: $1 — instance name (label only); $2 — bundle path.
# Returns: 0 always.
_ckipper_desktop_remove_prompt_bundle() {
    local name="$1" bundle="$2"
    [[ -d "$bundle" ]] || return 0
    if _core_prompt_confirm "Delete app bundle $bundle? (regeneratable via desktop add)"; then
        rm -rf "$bundle"
        echo "Deleted $bundle."
        return 0
    fi
    echo "Kept $bundle. To delete later: rm -rf '$bundle'"
}

# Validate `ckipper desktop rename <old> <new>` arguments before any I/O.
#
# Args: $1 — old name; $2 — new name.
# Returns: 0 on valid input; 1 on any check failure.
# Errors (stderr): usage hint, regex hint, collision message, etc.
_ckipper_desktop_rename_validate() {
    local old="$1" new="$2"
    if [[ -z "$old" || -z "$new" ]]; then
        echo "Usage: ckipper desktop rename <old> <new>" >&2
        return 1
    fi
    if [[ ! "$new" =~ $_CKIPPER_DESKTOP_NAME_REGEX ]]; then
        echo "New name must match ^[a-z0-9_-]+$ (lowercase alphanumeric, underscore, hyphen)." >&2
        return 1
    fi
    if [[ "$old" == "$new" ]]; then
        echo "Old and new name are the same. Nothing to do." >&2
        return 1
    fi
    if ! jq -e --arg n "$old" '.instances[$n]' "$CKIPPER_DESKTOP_REGISTRY" >/dev/null 2>&1; then
        echo "Desktop instance '$old' is not registered." >&2
        return 1
    fi
    if jq -e --arg n "$new" '.instances[$n]' "$CKIPPER_DESKTOP_REGISTRY" >/dev/null 2>&1; then
        echo "Desktop instance '$new' is already registered." >&2
        return 1
    fi
}

# Atomically update the registry: insert the new entry (copied from the old
# but with refreshed user_data_dir + app_bundle_path) and delete the old
# entry — all in a single jq filter so a concurrent reader can never observe
# both or neither.
#
# Args: $1 — old name; $2 — new name.
# Returns: 0 on success; 1 on registry write failure.
_ckipper_desktop_rename_swap_registry() {
    local old="$1" new="$2"
    local new_data_dir new_bundle
    new_data_dir=$(_ckipper_desktop_data_dir_for "$new")
    new_bundle=$(_ckipper_desktop_bundle_path_for "$new")
    CKIPPER_REGISTRY_VERSION="$CKIPPER_DESKTOP_REGISTRY_VERSION" \
        _core_registry_update_at "$CKIPPER_DESKTOP_REGISTRY" '
            .instances[$new] = (
                .instances[$old]
                | .user_data_dir = $newdir
                | .app_bundle_path = $newbundle
            )
            | del(.instances[$old])
        ' --arg old "$old" --arg new "$new" \
          --arg newdir "$new_data_dir" --arg newbundle "$new_bundle"
}

# Perform the on-disk side of a rename: move the user-data dir to its new
# path, then regenerate the .app bundle under the new name. Rolls back the
# dir move + new bundle if any step fails. Old bundle is removed only after
# the new bundle is written so a mid-rename crash always leaves at least
# one bundle usable.
#
# Args: $1 — old name; $2 — new name.
# Returns: 0 on success; 1 on any filesystem step failure.
_ckipper_desktop_rename_perform_fs() {
    local old="$1" new="$2"
    local old_dir new_dir old_bundle new_bundle
    old_dir=$(_ckipper_desktop_data_dir_for "$old")
    new_dir=$(_ckipper_desktop_data_dir_for "$new")
    old_bundle=$(_ckipper_desktop_bundle_of "$old")
    new_bundle=$(_ckipper_desktop_bundle_path_for "$new")
    if [[ -e "$new_dir" || -e "$new_bundle" ]]; then
        echo "Error: destination path already exists ($new_dir or $new_bundle)." >&2
        return 1
    fi
    [[ -d "$old_dir" ]] && { mv "$old_dir" "$new_dir" || return 1; }
    if ! _ckipper_desktop_bundle_write "$new" "$new_bundle" "$new_dir"; then
        [[ -d "$new_dir" ]] && mv "$new_dir" "$old_dir" 2>/dev/null
        return 1
    fi
    [[ -d "$old_bundle" ]] && rm -rf "$old_bundle"
}

# Roll back a partial rename when the registry write fails after the
# filesystem moves succeeded. Restores both the data dir and the original
# bundle (regenerated from the old name) so the registry/disk pair stays
# in sync.
#
# Args: $1 — old name; $2 — new name.
# Returns: 0 always (best-effort rollback).
_ckipper_desktop_rename_rollback_fs() {
    local old="$1" new="$2"
    local old_dir new_dir old_bundle new_bundle
    old_dir=$(_ckipper_desktop_data_dir_for "$old")
    new_dir=$(_ckipper_desktop_data_dir_for "$new")
    old_bundle=$(_ckipper_desktop_bundle_path_for "$old")
    new_bundle=$(_ckipper_desktop_bundle_path_for "$new")
    [[ -d "$new_dir" ]] && mv "$new_dir" "$old_dir" 2>/dev/null
    [[ -d "$new_bundle" ]] && rm -rf "$new_bundle"
    _ckipper_desktop_bundle_write "$old" "$old_bundle" "$old_dir" 2>/dev/null
    return 0
}

# Rename a registered Desktop instance: move the user-data dir, regenerate
# the .app bundle under the new name, and update the registry. Refuses if
# the instance is running or if the destination name is taken. Rolls back
# the filesystem changes if the registry write fails.
#
# Args: $1 — old name; $2 — new name.
# Returns: 0 on success; 1 on any failure.
_ckipper_desktop_rename() {
    local old="$1" new="$2"
    [[ -f "$CKIPPER_DESKTOP_REGISTRY" ]] || {
        echo "Desktop instance '$old' is not registered." >&2; return 1
    }
    _ckipper_desktop_rename_validate "$old" "$new" || return 1
    local old_dir
    old_dir=$(_ckipper_desktop_data_dir_for "$old")
    _ckipper_desktop_assert_not_running "$old_dir" || return 1
    _ckipper_desktop_rename_perform_fs "$old" "$new" || {
        echo "Error: filesystem rename failed; left in place." >&2; return 1
    }
    if ! _ckipper_desktop_rename_swap_registry "$old" "$new"; then
        _ckipper_desktop_rename_rollback_fs "$old" "$new"
        echo "Error: registry update failed; reverted filesystem rename." >&2
        return 1
    fi
    echo "Renamed Desktop instance '$old' → '$new'."
    echo "Data dir: $old_dir → $(_ckipper_desktop_data_dir_for "$new")"
    echo "Bundle:   $(_ckipper_desktop_bundle_path_for "$new")"
}

# Unregister a Desktop instance from the registry, then interactively prompt
# to delete the user-data dir (default N — preserves user data) and the
# .app bundle (regeneratable). Refuses if the instance is currently running.
#
# Args: $1 — instance name.
# Returns: 0 on success; 1 if not registered, running, or registry write fails.
_ckipper_desktop_remove() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "Usage: ckipper desktop remove <name>" >&2
        return 1
    fi
    [[ -f "$CKIPPER_DESKTOP_REGISTRY" ]] || { echo "Desktop instance '$name' is not registered." >&2; return 1; }
    local data_dir bundle
    data_dir=$(_ckipper_desktop_data_dir_of "$name") || return 1
    bundle=$(_ckipper_desktop_bundle_of "$name")
    _ckipper_desktop_assert_not_running "$data_dir" || return 1
    if ! CKIPPER_REGISTRY_VERSION="$CKIPPER_DESKTOP_REGISTRY_VERSION" \
        _core_registry_update_at "$CKIPPER_DESKTOP_REGISTRY" \
        'del(.instances[$n])' --arg n "$name"; then
        echo "Error: failed to unregister '$name' from the desktop registry." >&2
        return 1
    fi
    echo "Unregistered Desktop instance '$name'."
    _ckipper_desktop_remove_prompt_data_dir "$name" "$data_dir"
    _ckipper_desktop_remove_prompt_bundle "$name" "$bundle"
}

# Print registered Desktop instances in a column layout: name, data dir,
# bundle path, registered_at, running/stopped status. Running detection is
# best-effort and uses pgrep against the cmdline --user-data-dir argument.
#
# Returns: 0 always.
_ckipper_desktop_list() {
    if [[ ! -f "$CKIPPER_DESKTOP_REGISTRY" ]]; then
        _ckipper_desktop_list_empty_hint
        return 0
    fi
    CKIPPER_REGISTRY_VERSION="$CKIPPER_DESKTOP_REGISTRY_VERSION" \
        _core_registry_check_version_at "$CKIPPER_DESKTOP_REGISTRY" || return 1
    local count
    count=$(_ckipper_desktop_instance_count)
    if (( count == 0 )); then
        _ckipper_desktop_list_empty_hint
        return 0
    fi
    _core_style_header "Registered Desktop instances"
    _ckipper_desktop_list_header
    _core_style_divider
    _ckipper_desktop_list_print_rows
}
