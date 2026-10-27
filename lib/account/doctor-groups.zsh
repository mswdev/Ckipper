#!/usr/bin/env zsh
# Doctor checks for account groups (see lib/account/groups.zsh):
#   - every account is in a group (sync is disabled for ungrouped accounts)
#   - every group has a master that is one of its members
#   - a group's accounts all use their master's shared-memory dir
#     (env.CLAUDE_CODE_REMOTE_MEMORY_DIR in settings.json)
#   - no two groups share a memory dir, which would mix their memories

readonly _CKIPPER_DOCTOR_MEMORY_ENV_KEY="CLAUDE_CODE_REMOTE_MEMORY_DIR"

# Print an account's shared-memory dir setting (empty when unset).
#
# Args: $1 — account name.
# Returns: 0 always.
_ckipper_doctor_memory_dir_of() {
    local dir; dir=$(jq -r --arg n "$1" '.accounts[$n].config_dir' "$CKIPPER_REGISTRY")
    jq -r --arg k "$_CKIPPER_DOCTOR_MEMORY_ENV_KEY" '.env[$k] // ""' "$dir/settings.json" 2>/dev/null
}

# Run every group check and print the "Sync groups" section.
#
# Returns: 0 always (results printed via _ckipper_doctor_check).
_ckipper_doctor_groups() {
    echo ""
    _core_style_header "Sync groups"
    _ckipper_doctor_groups_ungrouped
    local groups; groups=$(jq -r '[.accounts[].group // empty] | unique[]' "$CKIPPER_REGISTRY" 2>/dev/null)
    [[ -z "$groups" ]] && return 0
    local group
    while IFS= read -r group; do
        _ckipper_doctor_group "$group"
    done <<< "$groups"
    _ckipper_doctor_groups_shared_memory "$groups"
}

# Warn about accounts that are not in any group.
#
# Returns: 0 always.
_ckipper_doctor_groups_ungrouped() {
    local ungrouped
    ungrouped=$(jq -r '.accounts | to_entries[] | select(.value.group == null) | .key' \
        "$CKIPPER_REGISTRY" 2>/dev/null | paste -sd, -)
    [[ -z "$ungrouped" ]] && return 0
    _ckipper_doctor_check WARN "not in a group, so sync is disabled for: $ungrouped — assign with: ckipper account group <name> <group>"
}

# Check one group: it has a master, and every member uses the master's
# shared-memory dir.
#
# Args: $1 — group name.
# Returns: 0 always.
_ckipper_doctor_group() {
    local group="$1"
    local master; master=$(_ckipper_account_group_master "$group")
    if [[ -z "$master" || "$(_ckipper_account_group_of "$master")" != "$group" ]]; then
        _ckipper_doctor_check WARN "group $group has no master — set one: ckipper account group <name> $group --master"
        return 0
    fi
    local expected; expected=$(_ckipper_doctor_memory_dir_of "$master")
    local member mismatched=""
    for member in ${(f)"$(_ckipper_account_group_members "$group")"}; do
        [[ "$(_ckipper_doctor_memory_dir_of "$member")" == "$expected" ]] || mismatched+="${mismatched:+, }$member"
    done
    if [[ -n "$mismatched" ]]; then
        _ckipper_doctor_check WARN "group $group: $mismatched use a different $_CKIPPER_DOCTOR_MEMORY_ENV_KEY than master $master (${expected:-unset}) — fix with: ckipper account sync $master <name> --include settings"
        return 0
    fi
    _ckipper_doctor_check PASS "group $group: master $master, memory dir ${expected:-unset (each account keeps its own)}"
}

# Fail when two groups' masters point at the same shared-memory dir.
#
# Args: $1 — newline-separated group names.
# Returns: 0 always.
_ckipper_doctor_groups_shared_memory() {
    local groups="$1"
    local -A owner_of_dir
    local group master memory_dir
    while IFS= read -r group; do
        master=$(_ckipper_account_group_master "$group")
        memory_dir=$(_ckipper_doctor_memory_dir_of "$master")
        [[ -z "$master" || -z "$memory_dir" ]] && continue
        if [[ -n "${owner_of_dir[$memory_dir]}" ]]; then
            _ckipper_doctor_check FAIL "groups ${owner_of_dir[$memory_dir]} and $group share memory dir $memory_dir — give each group its own"
            continue
        fi
        owner_of_dir[$memory_dir]="$group"
    done <<< "$groups"
}
