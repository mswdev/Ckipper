#!/usr/bin/env zsh
# Account lifecycle subcommands: add, finalize_registration, remove, rename, list, default, bare_alias_safe.

# Module-level context for the in-progress registration.
# Populated by callers before invoking _ckipper_account_finalize_registration.
# Fields: name, dir, service
typeset -gA _CKIPPER_FINALIZE_CTX

# Module-level context for the in-progress rename.
# Populated by _ckipper_account_rename before invoking _ckipper_account_rename_perform.
# Fields: old_dir, new_dir
typeset -gA _CKIPPER_RENAME_CTX

# Validate the account name and --adopt flag from `ckipper account add` arguments.
# Prints error messages to stdout and returns non-zero on failure.
#
# Args:
#   $1 — account name
#   $2 — "--adopt" or empty
#
# Returns:
#   0 if valid; 1 on empty name, invalid name format, or already registered.
_ckipper_account_add_validate_name() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "Usage: ckipper account add <name> [--adopt]"
        return 1
    fi
    if [[ ! "$name" =~ ^[a-z0-9_-]+$ ]]; then
        echo "Account name must match ^[a-z0-9_-]+$ (lowercase alphanumeric, underscore, hyphen)."
        return 1
    fi
    if jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null 2>/dev/null; then
        echo "Account '$name' is already registered."
        return 1
    fi
}

# Run the adopt flow: pick a Keychain entry and finalize registration for an existing dir.
#
# Args:
#   $1 — account name
#   $2 — account config directory
#
# Returns:
#   0 on success; 1 on validation or registration failure.
_ckipper_account_add_adopt_flow() {
    local name="$1" dir="$2"
    if [[ ! -d "$dir" ]]; then
        echo "Cannot adopt: $dir does not exist."
        return 1
    fi
    local picked=""
    if [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" == darwin* ]]; then
        _ckipper_account_add_pick_keychain_entry "$name" picked || return 1
    fi
    _CKIPPER_FINALIZE_CTX[name]="$name"
    _CKIPPER_FINALIZE_CTX[dir]="$dir"
    _CKIPPER_FINALIZE_CTX[service]="$picked"
    _ckipper_account_finalize_registration "adopt"
}

# Prompt the user to pick a Keychain entry from the available candidates.
# On return, the nameref variable (arg $2) holds the chosen service (may be empty).
#
# Args:
#   $1 — account name (for error messages)
#   $2 — nameref variable to receive the chosen service name
#
# Returns:
#   0 on success; 1 on keychain error or invalid service shape.
_ckipper_account_add_pick_keychain_entry() {
    local name="$1"
    local -n _picked_ref="$2"
    local candidates
    candidates=$(_core_keychain_snapshot) || return 1
    [[ -z "$candidates" ]] && return 0
    echo "Candidate Keychain entries:"
    echo "$candidates" | nl
    local keychain_index
    read -r "?Pick a number (or empty to skip): " keychain_index
    [[ -z "$keychain_index" ]] && return 0
    _picked_ref=$(printf '%s\n' "$candidates" | sed -n "${keychain_index}p")
    if [[ -n "$_picked_ref" ]] && ! _core_keychain_validate "$_picked_ref"; then
        echo "Invalid Keychain service shape: $_picked_ref"
        return 1
    fi
}

# Run the fresh registration flow: create the dir, deploy hooks, launch Claude, detect new keychain.
#
# Args:
#   $1 — account name
#   $2 — account config directory
#
# Returns:
#   0 on success; 1 on abort or credential detection failure.
_ckipper_account_add_fresh_flow() {
    local name="$1" dir="$2"
    if [[ -d "$dir" ]]; then
        echo "Directory $dir already exists. Use --adopt to register it."
        return 1
    fi
    mkdir -p "$dir/hooks"
    if [[ -f "$CKIPPER_DIR/settings-template.json" ]]; then
        cp "$CKIPPER_DIR/settings-template.json" "$dir/settings.json"
    fi
    _ckipper_account_sync_hooks_for "$name" "$dir"
    local before_snapshot
    before_snapshot=$(_core_keychain_snapshot) || return 1
    _ckipper_account_add_launch_claude "$name" "$dir" || return 1
    local after_snapshot
    after_snapshot=$(_core_keychain_snapshot) || return 1
    local new_service
    new_service=$(comm -13 \
        <(printf '%s\n' "$before_snapshot") \
        <(printf '%s\n' "$after_snapshot") | head -1)
    _ckipper_account_add_check_credentials "$name" "$dir" "$new_service" || return 1
    _CKIPPER_FINALIZE_CTX[name]="$name"
    _CKIPPER_FINALIZE_CTX[dir]="$dir"
    _CKIPPER_FINALIZE_CTX[service]="$new_service"
    _ckipper_account_finalize_registration "fresh"
}

# Display the fresh-add instructions, prompt for confirmation, and launch Claude.
#
# Args:
#   $1 — account name
#   $2 — account config directory
#
# Returns:
#   0 after Claude exits; 1 if user chose to skip.
_ckipper_account_add_launch_claude() {
    local name="$1" dir="$2"
    cat <<EOF

A new account directory was created at $dir.

About to launch Claude with this account context. Steps:
  1. Complete the /login flow with the account you want to register as '$name'.
  2. When done, exit Claude with /quit (or Ctrl-D at the prompt).
  3. ckipper will resume here and finalize registration.

Press enter to launch Claude (or type 'skip' to abort and clean up):
EOF
    local ack
    read -r ack
    if [[ "$ack" == "skip" ]]; then
        rm -rf "$dir"
        echo "Aborted. Cleaned up $dir."
        return 1
    fi
    # Use `command claude` to bypass the bare-claude guard from aliases.zsh.
    CLAUDE_CONFIG_DIR="$dir" command claude
    local rc=$?
    echo ""
    echo "Claude exited (status $rc). Finalizing registration..."
}

# Validate that credentials were captured after a fresh login attempt.
#
# Args:
#   $1 — account name
#   $2 — account config directory
#   $3 — detected new keychain service (may be empty)
#
# Returns:
#   0 if credentials are present; 1 otherwise with error message.
_ckipper_account_add_check_credentials() {
    local name="$1" dir="$2" new_service="$3"
    if [[ -n "$new_service" ]]; then
        if ! _core_keychain_validate "$new_service"; then
            echo "Detected entry has unexpected shape: $new_service"
            echo "Refusing to register. Use --adopt to register manually."
            return 1
        fi
        echo "Detected new Keychain entry: $new_service"
        return 0
    fi
    if [[ -f "$dir/.credentials.json" ]]; then
        echo "No new Keychain entry, but $dir/.credentials.json exists — proceeding with on-disk credentials."
        return 0
    fi
    echo "Warning: no new Keychain entry detected and no .credentials.json on disk."
    echo "Login may not have completed. Re-run /login or use: ckipper account add $name --adopt"
    return 1
}

# Register a new account interactively (fresh login) or by adopting an existing directory.
#
# Args:
#   $1 — account name (must match ^[a-z0-9_-]+$)
#   $2 — "--adopt" to register an existing directory; omit for fresh login flow
#
# Returns:
#   0 on success; 1 on validation or registration failure.
_ckipper_account_add() {
    _core_registry_check_version || return 1
    local name="$1" should_adopt="false"
    [[ "$2" == "--adopt" ]] && should_adopt="true"
    _core_registry_init
    _ckipper_account_add_validate_name "$name" || return 1
    local dir="$HOME/.claude-$name"
    if [[ "$should_adopt" = "true" ]]; then
        _ckipper_account_add_adopt_flow "$name" "$dir"
        return $?
    fi
    _ckipper_account_add_fresh_flow "$name" "$dir"
}

# Write the account entry to the registry and regenerate aliases atomically.
# On collision, diagnoses the cause and prints an appropriate error.
# Reads name, dir, and service from _CKIPPER_FINALIZE_CTX module global.
#
# Args:
#   $1 — registration mode: "fresh" or "adopt"
#
# Returns:
#   0 on success; 1 on registry collision or write failure.
_ckipper_account_finalize_registration() {
    local mode="$1"
    local name="${_CKIPPER_FINALIZE_CTX[name]}"
    local dir="${_CKIPPER_FINALIZE_CTX[dir]}"
    local service="${_CKIPPER_FINALIZE_CTX[service]}"
    local now; now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    _core_registry_init
    if ! _core_registry_update '
        if (.accounts | has($n)) then
            error("ALREADY_REGISTERED")
        elif ([.accounts[].config_dir] | any(. == $d)) then
            error("CONFIG_DIR_IN_USE")
        else
            .accounts[$n] = {config_dir: $d, keychain_service: (if $s == "" then null else $s end), registered_at: $t}
            | (if .default == null then .default = $n else . end)
        end
    ' --arg n "$name" --arg d "$dir" --arg s "$service" --arg t "$now"; then
        _ckipper_account_finalize_diagnose_error "$name" "$dir"
        return 1
    fi
    _ckipper_account_finalize_announce "$name" "$mode"
}

# Regenerate aliases, sync hooks, and print the post-registration usage hint.
#
# Args:
#   $1 — account name
#   $2 — registration mode label (e.g. "fresh", "adopt")
#
# Returns: 0 always.
_ckipper_account_finalize_announce() {
    local name="$1" mode="$2"
    _ckipper_account_regenerate_aliases
    _ckipper_account_sync_hooks_for "$name"
    echo "Registered '$name' (mode: $mode)."
    if _ckipper_account_bare_alias_safe "$name"; then
        echo "Use it via: claude-$name   (or just: $name)"
    else
        echo "Use it via: claude-$name"
    fi
}

# Diagnose why _ckipper_account_finalize_registration failed and print the appropriate error.
#
# Args:
#   $1 — account name
#   $2 — account config directory
#
# Returns:
#   0 always (error message already printed to stderr).
_ckipper_account_finalize_diagnose_error() {
    local name="$1" dir="$2"
    if jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
        echo "Error: account '$name' already exists in registry (race detected)." >&2
    elif jq -e --arg d "$dir" '[.accounts[].config_dir] | any(. == $d)' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
        echo "Error: config dir '$dir' is already claimed by another registered account." >&2
    else
        echo "Error: failed to write account '$name' to registry $CKIPPER_REGISTRY" >&2
    fi
}

# Return 0 if $1 is safe to use as a bare-alias function name (no clash with
# any existing PATH command, shell builtin, alias, or reserved word). Existing
# shell functions are not a clash — we expect to redefine those.
#
# Args:
#   $1 — proposed alias name
#
# Returns:
#   0 if safe to use; 1 if it would shadow an existing command/builtin/alias/reserved word.
_ckipper_account_bare_alias_safe() {
    local n="$1"
    (( ${+commands[$n]} || ${+builtins[$n]} || ${+aliases[$n]} )) && return 1
    local what; what=$(whence -w "$n" 2>/dev/null | awk '{print $2}')
    [[ "$what" == "reserved" ]] && return 1
    return 0
}

# Print all registered accounts with their directories and email addresses.
#
# Returns:
#   0 always.
_ckipper_account_list() {
    if [[ ! -f "$CKIPPER_REGISTRY" ]]; then
        echo "No accounts registered. Run: ckipper account add <name>"
        return 0
    fi
    local default
    default=$(jq -r '.default // ""' "$CKIPPER_REGISTRY")
    echo "Registered accounts:"
    jq -r '.accounts | to_entries[] | "\(.key)\t\(.value.config_dir)"' "$CKIPPER_REGISTRY" | \
        while IFS=$'\t' read -r name dir; do
            _ckipper_account_list_account_line "$name" "$dir" "$default"
        done
    echo ""
    echo "* = default. Run: ckipper account default <name>"
    echo ""
    echo "Tip: don't run the same account in two terminals at once — Claude's OAuth refresh"
    echo "is single-use, so the second session gets logged out. Use a different account instead."
}

# Print a single account line for `ckipper account list`.
#
# Args:
#   $1 — account name
#   $2 — config directory
#   $3 — default account name
#
# Returns:
#   0 always.
_ckipper_account_list_account_line() {
    local name="$1" dir="$2" default="$3"
    local marker="  "
    [[ "$name" == "$default" ]] && marker="* "
    local email=""
    if [[ -f "$dir/.claude.json" ]]; then
        email=$(jq -r '.oauthAccount.emailAddress // ""' "$dir/.claude.json" 2>/dev/null)
    fi
    local exists="(missing)"
    [[ -d "$dir" ]] && exists=""
    echo "$marker$name  $dir  ${email:+($email)} $exists"
}

# Set the default account in the registry.
#
# Args:
#   $1 — account name to set as default
#
# Returns:
#   0 on success; 1 if account is not registered.
_ckipper_account_default() {
    _core_registry_check_version || return 1
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: ckipper account default <name>"; return 1; }
    if ! jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null; then
        echo "Account '$name' is not registered."
        return 1
    fi
    _core_registry_update '.default = $n' --arg n "$name"
    echo "Default account is now '$name'."
}

# Unregister an account from the registry without deleting its files.
#
# Args:
#   $1 — account name to remove
#
# Returns:
#   0 on success; 1 if account is not registered.
_ckipper_account_remove() {
    _core_registry_check_version || return 1
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: ckipper account remove <name>"; return 1; }
    if ! jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null; then
        echo "Account '$name' is not registered."
        return 1
    fi
    local dir; dir=$(jq -r --arg n "$name" '.accounts[$n].config_dir' "$CKIPPER_REGISTRY")
    local service; service=$(jq -r --arg n "$name" '.accounts[$n].keychain_service // ""' "$CKIPPER_REGISTRY")
    _core_registry_update 'del(.accounts[$n]) | (if .default == $n then .default = null else . end)' --arg n "$name"
    # Drop the now-stale launcher functions from the calling shell.
    unset -f "claude-$name" 2>/dev/null
    unset -f "$name" 2>/dev/null
    _ckipper_account_regenerate_aliases
    echo "Unregistered '$name'."
    echo ""
    echo "The directory and Keychain entry were not deleted. To remove them manually:"
    printf "  rm -rf %q\n" "$dir"
    if [[ -n "$service" ]]; then
        printf "  security delete-generic-password -s %q\n" "$service"
    fi
}

# Validate arguments for `ckipper account rename` before performing the rename.
#
# Args:
#   $1 — old account name
#   $2 — new account name
#
# Returns:
#   0 if valid; 1 on any validation failure.
_ckipper_account_rename_validate() {
    local old="$1" new="$2"
    if [[ -z "$old" || -z "$new" ]]; then
        echo "Usage: ckipper account rename <old> <new>"
        return 1
    fi
    if [[ ! "$new" =~ ^[a-z0-9_-]+$ ]]; then
        echo "New name must match ^[a-z0-9_-]+$ (lowercase alphanumeric, underscore, hyphen)."
        return 1
    fi
    if [[ "$old" == "$new" ]]; then
        echo "Old and new name are the same. Nothing to do."
        return 1
    fi
    if ! jq -e --arg n "$old" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
        echo "Account '$old' is not registered."
        return 1
    fi
    if jq -e --arg n "$new" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
        echo "Account '$new' is already registered."
        return 1
    fi
}

# Perform the directory move and registry update for `ckipper account rename`.
# Rolls back the directory rename if the registry write fails.
# Reads old_dir and new_dir from _CKIPPER_RENAME_CTX module global.
#
# Args:
#   $1 — old account name
#   $2 — new account name
#
# Returns:
#   0 on success; 1 on directory move or registry write failure.
# Verify the rename is safe before performing destructive actions.
#
# Args:
#   $1 — new directory path (must not exist)
#   $2 — old directory path (must be a directory)
#
# Returns: 0 if preconditions pass; 1 if any check fails.
_ckipper_account_rename_check_preconditions() {
    local new_dir="$1" old_dir="$2"
    if [[ -e "$new_dir" ]]; then
        echo "Error: $new_dir already exists. Pick a different name or remove it first."
        return 1
    fi
    if [[ ! -d "$old_dir" ]]; then
        echo "Error: source directory $old_dir does not exist."
        return 1
    fi
    _core_assert_no_running_claude || return 1
}

_ckipper_account_rename_perform() {
    local old="$1" new="$2"
    local old_dir="${_CKIPPER_RENAME_CTX[old_dir]}"
    local new_dir="${_CKIPPER_RENAME_CTX[new_dir]}"
    _ckipper_account_rename_check_preconditions "$new_dir" "$old_dir" || return 1
    if ! mv "$old_dir" "$new_dir" 2>/dev/null; then
        echo "Error: failed to rename $old_dir → $new_dir." >&2
        return 1
    fi
    if ! _core_registry_update '
        .accounts[$new] = .accounts[$old] |
        .accounts[$new].config_dir = $newdir |
        del(.accounts[$old]) |
        (if .default == $old then .default = $new else . end)
    ' --arg old "$old" --arg new "$new" --arg newdir "$new_dir"; then
        mv "$new_dir" "$old_dir" 2>/dev/null
        echo "Error: registry write failed; reverted directory rename." >&2
        return 1
    fi
}

# Rename a registered account: moves its directory and updates the registry.
#
# Args:
#   $1 — old account name
#   $2 — new account name
#
# Returns:
#   0 on success; 1 on validation or rename failure.
_ckipper_account_rename() {
    _core_registry_check_version || return 1
    local old="$1" new="$2"
    _ckipper_account_rename_validate "$old" "$new" || return 1
    local old_dir new_dir
    old_dir=$(jq -r --arg n "$old" '.accounts[$n].config_dir' "$CKIPPER_REGISTRY")
    new_dir="$HOME/.claude-$new"
    _CKIPPER_RENAME_CTX[old_dir]="$old_dir"
    _CKIPPER_RENAME_CTX[new_dir]="$new_dir"
    _ckipper_account_rename_perform "$old" "$new" || return 1
    # Drop old-name launcher functions from the calling shell.
    unset -f "claude-$old" 2>/dev/null
    unset -f "$old" 2>/dev/null
    _ckipper_account_regenerate_aliases
    _ckipper_account_sync_hooks_for "$new"   # rewrite per-account settings.json hook paths to new dir
    echo "Renamed '$old' → '$new'."
    echo "Directory:    $old_dir → $new_dir"
    if _ckipper_account_bare_alias_safe "$new"; then
        echo "Use:          claude-$new   (or just: $new)"
    else
        echo "Use:          claude-$new"
    fi
}
