#!/usr/bin/env zsh
# Account resolution for w(). Populates W_ACTIVE_* globals.

# Resolve which ckipper account to use, then populate:
#   W_ACTIVE_ACCOUNT          — resolved account name
#   W_ACTIVE_CONFIG_DIR       — account's claude config directory
#   W_ACTIVE_KEYCHAIN_SERVICE — account's keychain service name (may be empty)
#
# Resolution order:
#   1. W_CLI_ACCOUNT (from --account flag)
#   2. Account whose config_dir matches $CLAUDE_CONFIG_DIR (if set)
#   3. Registry default
#
# Returns: 0 on success; 1 if no account found or account not in registry.
# Errors (stderr):
#   "Error: no account selected and no default registered." — when no account can be resolved
#   "Error: account '<name>' is not registered. Run: ckipper list" — when account missing from registry
_ckipper_worktree_resolve_account() {
    local candidate
    candidate=$(_ckipper_worktree_find_account_name)

    if [[ -z "$candidate" ]]; then
        echo "Error: no account selected and no default registered."
        echo "Run: ckipper list   (then: ckipper default <name>, or pass --account <name>)"
        return 1
    fi

    local config_dir keychain_service
    if [[ -f "$CKIPPER_REGISTRY" ]]; then
        config_dir=$(_core_registry_read | jq -r --arg n "$candidate" '.accounts[$n].config_dir // empty' 2>/dev/null)
        keychain_service=$(_core_registry_read | jq -r --arg n "$candidate" '.accounts[$n].keychain_service // empty' 2>/dev/null)
    fi

    if [[ -z "$config_dir" ]]; then
        echo "Error: account '$candidate' is not registered. Run: ckipper list"
        return 1
    fi

    W_ACTIVE_ACCOUNT="$candidate"
    W_ACTIVE_CONFIG_DIR="$config_dir"
    W_ACTIVE_KEYCHAIN_SERVICE="$keychain_service"
}

# Return the account name to use, without side effects.
#
# Resolution order: CLI flag → env match → registry default.
#
# Returns: 0 always (prints account name to stdout, or empty string if none found).
_ckipper_worktree_find_account_name() {
    if [[ -n "$W_CLI_ACCOUNT" ]]; then
        echo "$W_CLI_ACCOUNT"
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
