#!/usr/bin/env zsh
# Account resolution for `ckipper worktree run`. Populates CKIPPER_WT_ACTIVE_* globals.

# Resolve which ckipper account to use, then populate:
#   CKIPPER_WT_ACTIVE_ACCOUNT          — resolved account name
#   CKIPPER_WT_ACTIVE_CONFIG_DIR       — account's claude config directory
#   CKIPPER_WT_ACTIVE_KEYCHAIN_SERVICE — account's keychain service name (may be empty)
#
# Resolution order:
#   1. CKIPPER_WT_CLI_ACCOUNT (from --account flag)
#   2. Account whose config_dir matches $CLAUDE_CONFIG_DIR (if set)
#   3. Registry default
#
# Returns: 0 on success; 1 if no account found or account not in registry.
# Errors (stderr):
#   "Error: no account selected and no default registered." — when no account can be resolved
#   "Error: account '<name>' is not registered. Run: ckipper account list" — when account missing from registry
_ckipper_worktree_resolve_account() {
    local candidate
    candidate=$(_ckipper_worktree_find_account_name)

    if [[ -z "$candidate" ]]; then
        echo "Error: no account selected and no default registered." >&2
        echo "Run: ckipper account list   (then: ckipper account default <name>, or pass --account <name>)" >&2
        return 1
    fi

    local config_dir keychain_service
    if [[ -f "$CKIPPER_REGISTRY" ]]; then
        config_dir=$(_core_registry_read | jq -r --arg n "$candidate" '.accounts[$n].config_dir // empty' 2>/dev/null)
        keychain_service=$(_core_registry_read | jq -r --arg n "$candidate" '.accounts[$n].keychain_service // empty' 2>/dev/null)
    fi

    if [[ -z "$config_dir" ]]; then
        echo "Error: account '$candidate' is not registered. Run: ckipper account list" >&2
        return 1
    fi

    CKIPPER_WT_ACTIVE_ACCOUNT="$candidate"
    CKIPPER_WT_ACTIVE_CONFIG_DIR="$config_dir"
    CKIPPER_WT_ACTIVE_KEYCHAIN_SERVICE="$keychain_service"
}

# Return the account name to use, without side effects.
#
# Resolution order: CLI flag → env match → registry default.
#
# Returns: 0 always (prints account name to stdout, or empty string if none found).
_ckipper_worktree_find_account_name() {
    if [[ -n "$CKIPPER_WT_CLI_ACCOUNT" ]]; then
        echo "$CKIPPER_WT_CLI_ACCOUNT"
        return 0
    fi

    if [[ -n "$CLAUDE_CONFIG_DIR" && -f "$CKIPPER_REGISTRY" ]]; then
        local matched
        matched=$(_core_registry_read | jq -r --arg d "$CLAUDE_CONFIG_DIR" \
            '.accounts | to_entries[] | select(.value.config_dir == $d) | .key' \
            | head -1)
        [[ -n "$matched" ]] && { echo "$matched"; return 0; }
    fi

    if [[ -f "$CKIPPER_REGISTRY" ]]; then
        local default
        default=$(_core_registry_read | jq -r '.default // ""')
        [[ -n "$default" ]] && { echo "$default"; return 0; }
    fi

    return 0
}
