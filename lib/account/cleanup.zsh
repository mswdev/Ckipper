#!/usr/bin/env zsh
# Interactive cleanup helpers for `ckipper account remove`.
#
# After unregistering an account, prompts the user to delete the config dir
# and the macOS Keychain entry. Both prompts honor CKIPPER_NO_GUM via the
# shared _core_prompt_confirm helper.
#
# Depends on lib/core/prompt.zsh (`_core_prompt_confirm`).

# Prompt the user to delete the account's config directory, and remove it on
# confirmation. No-op when the directory does not exist.
#
# Args:
#   $1 — account name (used in the friendly log line on success)
#   $2 — absolute path to the config directory
#
# Returns: 0 always; non-zero only if the underlying `rm -rf` failed.
_ckipper_account_cleanup_dir() {
    local name="$1" dir="$2"
    [[ ! -d "$dir" ]] && return 0
    if _core_prompt_confirm "Delete config dir $dir?"; then
        rm -rf "$dir" || return 1
        echo "Deleted config dir for '$name' ($dir)."
        return 0
    fi
    echo "Kept config dir for '$name'. To remove it manually:"
    printf "  rm -rf %q\n" "$dir"
}

# Prompt the user to delete the macOS Keychain entry Claude Code keeps for
# the account's config dir, and delete it on confirmation. The entry name is
# derived from the dir path (see lib/core/keychain.zsh), so it always belongs
# to this account. Never touches the default "Claude Code-credentials" entry,
# which belongs to bare `claude` (~/.claude), not to a registered account.
# No-op off macOS or when the entry does not exist.
#
# Args:
#   $1 — account name (used in the friendly log line on success)
#   $2 — absolute path to the account's config directory
#
# Returns: 0 always.
_ckipper_account_cleanup_keychain() {
    local name="$1" dir="$2"
    local service; service=$(_core_keychain_service_for_dir "$dir")
    [[ "$service" == "$_CORE_KEYCHAIN_SERVICE_PREFIX" ]] && return 0
    _core_keychain_entry_exists "$service" || return 0
    if ! _core_prompt_confirm "Delete Keychain entry '$service' (the login for '$name')?"; then
        echo "Kept Keychain entry for '$name'. To remove it manually:"
        printf "  security delete-generic-password -s %q\n" "$service"
        return 0
    fi
    if security delete-generic-password -s "$service" >/dev/null 2>&1; then
        echo "Deleted Keychain entry '$service' for '$name'."
        return 0
    fi
    echo "Failed to delete Keychain entry '$service' for '$name'. To retry manually:"
    printf "  security delete-generic-password -s %q\n" "$service"
}
