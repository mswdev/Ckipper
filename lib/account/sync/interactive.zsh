#!/usr/bin/env zsh
# Interactive wizard for `ckipper account sync` — gum-driven pickers for
# source account, target accounts (multi-select), and types (multi-select).
#
# All pickers honor CKIPPER_NO_GUM via lib/core/prompt.zsh helpers
# (_core_prompt_choose etc.) so non-TTY callers and tests have a fallback.

# List every registered account name (sorted by registry insertion order).
#
# Returns: 0; prints account names, one per line.
_ckipper_account_sync_list_accounts() {
    [[ ! -f "$CKIPPER_REGISTRY" ]] && return 0
    jq -r '.accounts | keys[]?' "$CKIPPER_REGISTRY" 2>/dev/null
}

# List every registered account name EXCEPT the given one.
#
# Args: $1 — account name to exclude.
# Returns: 0; prints filtered list.
_ckipper_account_sync_list_accounts_except() {
    local exclude="$1"
    _ckipper_account_sync_list_accounts | grep -vxF "$exclude" 2>/dev/null
}

# Prompt the user to pick the source account.
#
# Returns: 0 with chosen name on stdout; 1 if user cancels or no accounts
#   are registered.
_ckipper_account_sync_pick_source() {
    local -a accounts
    accounts=( ${(f)"$(_ckipper_account_sync_list_accounts)"} )
    if (( ${#accounts} == 0 )); then
        echo "No accounts registered. Run: ckipper account add <name>" >&2
        return 1
    fi
    _core_prompt_choose "Sync FROM which account?" "${accounts[@]}"
}

# Prompt to multi-select target accounts. With gum, uses --no-limit.
# Without gum, falls back to a comma-separated input prompt.
#
# Args: $1 — source account name (excluded from candidates).
# Returns: 0 with chosen names (one per line) on stdout; 1 if user cancels.
_ckipper_account_sync_pick_targets() {
    local source="$1"
    local -a candidates
    candidates=( ${(f)"$(_ckipper_account_sync_list_accounts_except "$source")"} )
    if (( ${#candidates} == 0 )); then
        echo "No other accounts to sync to." >&2
        return 1
    fi
    if _core_prompt_use_gum; then
        printf '%s\n' "${candidates[@]}" | gum choose --no-limit --header "Sync TO which accounts? (space to multi-select)"
        return $?
    fi
    _ckipper_account_sync_pick_targets_fallback "${candidates[@]}"
}

# Pure-zsh fallback: comma-separated input, validated against candidates.
#
# Args: $@ — candidate account names.
# Returns: 0; prints chosen names.
_ckipper_account_sync_pick_targets_fallback() {
    echo "Available targets: $*" >&2
    local input
    input=$(_core_prompt_input "Enter comma-separated targets" "")
    local name
    for name in ${(s:,:)input}; do
        echo "$name"
    done
}

# Prompt to multi-select sync types from the registry.
#
# Returns: 0; prints chosen type ids.
_ckipper_account_sync_pick_types() {
    local -a labels
    local t
    for t in "${(@k)_CKIPPER_SYNC_TYPE_LABEL}"; do
        labels+=("$t — ${_CKIPPER_SYNC_TYPE_LABEL[$t]}")
    done
    if _core_prompt_use_gum; then
        printf '%s\n' "${labels[@]}" \
            | gum choose --no-limit --header "Pick types to sync (space to multi-select)" \
            | awk '{print $1}'
        return $?
    fi
    echo "Type tokens: ${(@k)_CKIPPER_SYNC_TYPE_LABEL}" >&2
    local input
    input=$(_core_prompt_input "Enter comma-separated types" "")
    local name
    for name in ${(s:,:)input}; do
        echo "$name"
    done
}
