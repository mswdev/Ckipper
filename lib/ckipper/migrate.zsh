#!/usr/bin/env zsh
# One-time migration from legacy ~/.claude/docker/ layout.

# Module globals tracking destructive migration steps for rollback.
typeset -g _CKIPPER_MIGRATE_STEP=0
typeset -g _CKIPPER_MIGRATE_BACKUP=""

# Module-level context for the in-progress migration.
# Populated by _ckipper_migrate before any helper reads it.
# Fields: name, target_dir, legacy_claude, legacy_homejson, probed_service
typeset -gA _CKIPPER_MIGRATE_CTX

# Check preconditions for migration: no running Claude, no symlinks at key paths.
#
# Args:
#   $1 — legacy_claude path (e.g. "$HOME/.claude")
#   $2 — legacy home json path (e.g. "$HOME/.claude.json")
#
# Returns:
#   0 if all preconditions pass; 1 on failure.
#
# Errors (stderr):
#   "Error: ... is a symlink..." — when either path is a symlink.
_ckipper_migrate_preflight() {
    local legacy_claude="$1" legacy_homejson_check="$2"
    _core_assert_no_running_claude || return 1
    if [[ -L "$legacy_claude" ]]; then
        local target; target=$(readlink "$legacy_claude")
        echo "Error: $legacy_claude is a symlink (→ $target). Refusing to migrate." >&2
        echo "Resolve manually: replace the symlink with the actual directory contents," >&2
        echo "or migrate the target directly." >&2
        return 1
    fi
    if [[ -L "$legacy_homejson_check" ]]; then
        local target; target=$(readlink "$legacy_homejson_check")
        echo "Error: $legacy_homejson_check is a symlink (→ $target). Refusing to migrate." >&2
        echo "Resolve manually: replace the symlink with the actual file contents," >&2
        echo "or migrate the target directly." >&2
        return 1
    fi
}


# Print the appropriate no-op message for migrate when nothing needs to be done.
#
# Args:
#   $1 — legacy_claude path
#   $2 — legacy home json path
#
# Returns:
#   0 always.
_ckipper_migrate_print_no_op() {
    local legacy_claude="$1" legacy_homejson="$2"
    local has_registry=0
    [[ -f "$CKIPPER_REGISTRY" ]] && \
        jq -e '.accounts | length > 0' "$CKIPPER_REGISTRY" >/dev/null 2>&1 && has_registry=1
    if (( has_registry )); then
        echo "Nothing to migrate: no $legacy_claude state and no $legacy_homejson at home root."
        echo "($CKIPPER_REGISTRY already has registered accounts — you're likely already migrated.)"
        echo "Run: ckipper list"
    else
        echo "Nothing to migrate: no $legacy_claude/.claude.json, no $legacy_claude/settings.json, no $legacy_homejson."
        echo "If this is a fresh setup, register an account directly: ckipper add <name>"
    fi
}

# Prompt the user for a migration account name with validation.
# Prints the chosen name to stdout.
#
# Returns:
#   0 with the name on stdout; 1 if the name cannot be determined.
_ckipper_migrate_prompt_account_name() {
    local default_name="personal" name=""
    while [[ -z "$name" ]]; do
        read -r "?What name do you want for this migrated account? [$default_name] " name
        [[ -z "$name" ]] && name="$default_name"
        if [[ ! "$name" =~ ^[a-z0-9_-]+$ ]]; then
            echo "Account name must match ^[a-z0-9_-]+$ (lowercase alphanumeric, underscore, hyphen). Try again."
            name=""
            continue
        fi
        if [[ -e "$HOME/.claude-$name" ]]; then
            echo "$HOME/.claude-$name already exists. Pick a different name."
            name=""
        fi
    done
    printf '%s' "$name"
}

# Display the migration plan and prompt for user confirmation.
# Reads legacy_claude, legacy_homejson, target_dir, and name from _CKIPPER_MIGRATE_CTX.
#
# Returns:
#   0 if user confirms; 1 if user aborts.
_ckipper_migrate_confirm_plan() {
    local legacy_claude="${_CKIPPER_MIGRATE_CTX[legacy_claude]}"
    local legacy_homejson="${_CKIPPER_MIGRATE_CTX[legacy_homejson]}"
    local target_dir="${_CKIPPER_MIGRATE_CTX[target_dir]}"
    local name="${_CKIPPER_MIGRATE_CTX[name]}"
    cat <<EOF

Detected existing $legacy_claude with login credentials.
EOF
    [[ -f "$legacy_homejson" ]] && \
        echo "Also detected $legacy_homejson (Claude's main config — projects, MCPs, trust state)."
    cat <<EOF

This migration will:
  1. Rename $legacy_claude → $target_dir.
EOF
    [[ -f "$legacy_homejson" ]] && \
        echo "  2. Move $legacy_homejson → $target_dir/.claude.json (preserving any existing inner one as a backup)."
    cat <<EOF
  3. Register '$name' in $CKIPPER_REGISTRY.
  4. Probe macOS Keychain for the matching 'Claude Code-credentials' entry.

NOT a symlink — bare 'claude' will no longer use this account; use 'claude-$name' instead.
If anything fails, the rename is automatically reverted.

EOF
    local user_choice
    read -r "?Proceed? [y/N] " user_choice
    if [[ "$user_choice" != "y" && "$user_choice" != "Y" ]]; then
        echo "Aborted."
        return 1
    fi
}

# Detect the Keychain service for the migrating account.
# Prompts the user if the default service is not found.
#
# Returns:
#   0 and prints the service name to stdout (may be empty); 1 on invalid input.
_ckipper_migrate_detect_keychain() {
    local probed_service="Claude Code-credentials"
    [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" != darwin* ]] && printf '' && return 0
    if security find-generic-password -s "$probed_service" -w >/dev/null 2>&1; then
        printf '%s' "$probed_service"
        return 0
    fi
    echo "Warning: '$probed_service' not found in Keychain."
    echo "Listing available Claude Keychain entries:"
    _core_keychain_snapshot || return 1
    local user_input
    read -r "?Enter the Keychain service for the account (or empty to skip): " user_input
    if [[ -n "$user_input" ]] && ! _core_keychain_validate "$user_input"; then
        echo "Invalid Keychain service shape. Aborting."
        return 1
    fi
    printf '%s' "$user_input"
}

# Execute the rename of ~/.claude to the target dir, then move ~/.claude.json if present.
# Updates _CKIPPER_MIGRATE_STEP and _CKIPPER_MIGRATE_BACKUP module globals to track progress.
#
# Args:
#   $1 — legacy_claude path
#   $2 — legacy home json path
#   $3 — target directory
#
# Returns:
#   0 on success; 1 on failure (rollback should be called by the caller).
#
# Errors (stderr):
#   "Error: failed to rename ..." — when mv of the directory fails.
#   "Error: failed to move ..." — when mv of .claude.json fails.
_ckipper_migrate_rename_dirs() {
    local legacy_claude="$1" legacy_homejson="$2" target_dir="$3"
    if ! mv "$legacy_claude" "$target_dir" 2>/dev/null; then
        echo "Error: failed to rename $legacy_claude → $target_dir" >&2
        echo "(Check permissions on $HOME and that no process holds the directory open.)" >&2
        return 1
    fi
    _CKIPPER_MIGRATE_STEP=1
    [[ ! -f "$legacy_homejson" ]] && return 0
    if [[ -f "$target_dir/.claude.json" ]]; then
        _CKIPPER_MIGRATE_BACKUP="$target_dir/.claude.json.pre-migrate-backup"
        mv "$target_dir/.claude.json" "$_CKIPPER_MIGRATE_BACKUP"
    fi
    if ! mv "$legacy_homejson" "$target_dir/.claude.json" 2>/dev/null; then
        echo "Error: failed to move $legacy_homejson → $target_dir/.claude.json" >&2
        return 1
    fi
    _CKIPPER_MIGRATE_STEP=2
}

# Print the migration success message with next steps.
#
# Args:
#   $1 — registered account name (may be empty)
#
# Returns:
#   0 always.
_ckipper_migrate_print_success() {
    local registered_name="$1"
    cat <<EOF

Migration complete.

Next steps:
  1. Confirm your ~/.zshrc sources the new path:
       source ~/.ckipper/docker/w-function.zsh
     (install.sh updates this automatically; if you used a manual install, edit it yourself.)
  2. Add to ~/.zshrc to enable per-account aliases AND the bare-claude guard:
       [[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh
  3. Restart your shell:  exec zsh
  4. Run:  ckipper add <other-account-name>   to add additional accounts.

EOF
    [[ -z "$registered_name" ]] && return 0
    cat <<EOF
To launch Claude with your migrated account, use:  claude-$registered_name
(Bare 'claude' no longer resolves to it — the guard in aliases.zsh refuses bare invocation once accounts are registered.)

EOF
}

# Copy the legacy docker directory to ckipper if not already done.
#
# Args:
#   $1 — legacy docker path ($HOME/.claude/docker)
#
# Returns:
#   0 always.
_ckipper_migrate_copy_docker() {
    local legacy_docker="$1"
    [[ -d "$legacy_docker" && ! -d "$CKIPPER_DIR/docker" ]] || return 0
    mkdir -p "$CKIPPER_DIR"
    cp -a "$legacy_docker/." "$CKIPPER_DIR/docker/"
    echo "Copied $legacy_docker → $CKIPPER_DIR/docker (legacy left intact for one release cycle)"
}

# Check whether there is legacy state that needs migration.
# Returns 0 (state found, proceed), 1 (no state), 2 (already migrated).
#
# Args:
#   $1 — legacy_claude path
#   $2 — legacy home json path
#
# Returns:
#   0 if migration is needed; 1 if no state; 2 if already migrated.
_ckipper_migrate_check_state() {
    local legacy_claude="$1" legacy_homejson="$2"
    local has_inner_state=0 has_homejson=0
    [[ -f "$legacy_claude/.claude.json" || -f "$legacy_claude/settings.json" ]] && has_inner_state=1
    [[ -f "$legacy_homejson" ]] && has_homejson=1
    (( has_inner_state == 0 && has_homejson == 0 )) && return 1
    [[ -f "$CKIPPER_REGISTRY" ]] && \
        jq -e '.accounts | length > 0' "$CKIPPER_REGISTRY" >/dev/null 2>&1 && return 2
    return 0
}

# Perform a one-time migration from legacy ~/.claude/docker/ layout to ckipper.
# Idempotent. Refuses if Claude is running.
#
# Returns:
#   0 on success or no-op; 1 on failure or user abort.
#
# Errors (stderr):
#   Various error messages for symlink, rename, and registry failures.
_ckipper_migrate() {
    _core_registry_check_version || return 1
    local legacy_docker="$HOME/.claude/docker"
    local legacy_claude="$HOME/.claude"
    local legacy_homejson="$HOME/.claude.json"
    _ckipper_migrate_preflight "$legacy_claude" "$legacy_homejson" || return 1
    _ckipper_migrate_copy_docker "$legacy_docker"
    local state_rc
    _ckipper_migrate_check_state "$legacy_claude" "$legacy_homejson"; state_rc=$?
    if (( state_rc == 1 )); then
        _ckipper_migrate_print_no_op "$legacy_claude" "$legacy_homejson"; return 0
    fi
    (( state_rc == 2 )) && { _ckipper_migrate_finalize; return 0; }
    local name; name=$(_ckipper_migrate_prompt_account_name)
    local target_dir="$HOME/.claude-$name"
    _CKIPPER_MIGRATE_CTX[name]="$name"
    _CKIPPER_MIGRATE_CTX[target_dir]="$target_dir"
    _CKIPPER_MIGRATE_CTX[legacy_claude]="$legacy_claude"
    _CKIPPER_MIGRATE_CTX[legacy_homejson]="$legacy_homejson"
    _ckipper_migrate_confirm_plan || return 1
    local probed_service
    probed_service=$(_ckipper_migrate_detect_keychain) || return 1
    _CKIPPER_MIGRATE_CTX[probed_service]="$probed_service"
    _ckipper_migrate_run
}

# Undo destructive migration steps on failure or interruption.
# Reads _CKIPPER_MIGRATE_STEP, _CKIPPER_MIGRATE_BACKUP, and _CKIPPER_MIGRATE_CTX module globals.
#
# Args:
#   $1 — reason label (e.g. "failed", "interrupted"); defaults to "rollback"
#
# Returns:
#   0 always.
_ckipper_migrate_rollback() {
    local why="${1:-rollback}"
    local name="${_CKIPPER_MIGRATE_CTX[name]}"
    local target_dir="${_CKIPPER_MIGRATE_CTX[target_dir]}"
    local legacy_claude="${_CKIPPER_MIGRATE_CTX[legacy_claude]}"
    local legacy_homejson="${_CKIPPER_MIGRATE_CTX[legacy_homejson]}"
    if (( _CKIPPER_MIGRATE_STEP >= 2 )) && [[ -f "$target_dir/.claude.json" && ! -e "$legacy_homejson" ]]; then
        mv "$target_dir/.claude.json" "$legacy_homejson" 2>/dev/null
        [[ -n "$_CKIPPER_MIGRATE_BACKUP" && -f "$_CKIPPER_MIGRATE_BACKUP" ]] && \
            mv "$_CKIPPER_MIGRATE_BACKUP" "$target_dir/.claude.json" 2>/dev/null
    fi
    if (( _CKIPPER_MIGRATE_STEP >= 1 )) && [[ -d "$target_dir" && ! -e "$legacy_claude" ]]; then
        mv "$target_dir" "$legacy_claude" 2>/dev/null
        echo "Migration $why — restored $legacy_claude." >&2
    fi
    if [[ -f "$CKIPPER_REGISTRY" ]] && \
       jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
        _core_registry_update \
            'del(.accounts[$n]) | (if .default == $n then .default = null else . end)' \
            --arg n "$name"
        echo "Cleaned partial '$name' entry from $CKIPPER_REGISTRY." >&2
    fi
    _ckipper_regenerate_aliases 2>/dev/null || true
}

# Run the destructive migration steps with rollback on failure or interruption.
# Reads all context from _CKIPPER_MIGRATE_CTX module global.
#
# Returns:
#   0 on success; 1 on failure (rollback applied).
_ckipper_migrate_run() {
    _CKIPPER_MIGRATE_STEP=0
    _CKIPPER_MIGRATE_BACKUP=""
    trap '_ckipper_migrate_rollback interrupted; trap - INT TERM HUP QUIT; return 130' INT TERM HUP QUIT
    _ckipper_migrate_run_steps
    local run_rc=$?
    trap - INT TERM HUP QUIT
    (( run_rc == 0 )) && _ckipper_migrate_finalize
    return $run_rc
}

# Execute the actual migration rename and register steps (called from _ckipper_migrate_run).
# Reads all context from _CKIPPER_MIGRATE_CTX module global.
#
# Returns:
#   0 on success; 1 on failure (_ckipper_migrate_rollback should be called by caller).
_ckipper_migrate_run_steps() {
    local name="${_CKIPPER_MIGRATE_CTX[name]}"
    local target_dir="${_CKIPPER_MIGRATE_CTX[target_dir]}"
    local legacy_claude="${_CKIPPER_MIGRATE_CTX[legacy_claude]}"
    local legacy_homejson="${_CKIPPER_MIGRATE_CTX[legacy_homejson]}"
    local probed_service="${_CKIPPER_MIGRATE_CTX[probed_service]}"
    _ckipper_migrate_rename_dirs "$legacy_claude" "$legacy_homejson" "$target_dir" || {
        _ckipper_migrate_rollback failed
        return 1
    }
    _ckipper_rewrite_plugin_paths "$legacy_claude/" "$target_dir/"
    _CKIPPER_FINALIZE_CTX[name]="$name"
    _CKIPPER_FINALIZE_CTX[dir]="$target_dir"
    _CKIPPER_FINALIZE_CTX[service]="$probed_service"
    if ! _ckipper_finalize_registration "migrate"; then
        _ckipper_migrate_rollback failed
        return 1
    fi
}

# Perform post-migration steps: clean up old Docker image and print success.
#
# Returns:
#   0 always.
_ckipper_migrate_finalize() {
    if command -v docker >/dev/null 2>&1; then
        docker rmi claude-dev 2>/dev/null && echo "Removed old claude-dev Docker image."
    fi
    local registered_name=""
    if [[ -f "$CKIPPER_REGISTRY" ]]; then
        registered_name=$(jq -r '.default // (.accounts | keys[0] // "")' "$CKIPPER_REGISTRY")
    fi
    _ckipper_migrate_print_success "$registered_name"
}

