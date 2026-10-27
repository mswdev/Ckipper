#!/usr/bin/env zsh
# Account groups: sets of accounts that share one setup (e.g. "personal" vs
# "work"), each with a master account the others are copied from.
#
# Registry shape (accounts.json):
#   .groups.<group>.master   — name of the group's master account (or null)
#   .accounts.<name>.group   — the group an account belongs to (absent = none)
#
# Sync only runs between accounts in the same group, so a personal → work
# sync can never carry personal-only settings (memory dir, plugins,
# marketplaces) into a work account or overwrite work-only ones.

# Plugin files and dirs copied from a group's master into a new account.
# plugins/data (per-plugin state) and plugins/synced (managed per account by
# claude.ai) are deliberately left out; caches are re-fetched by Claude Code.
readonly -a _CKIPPER_ACCOUNT_SEED_PLUGIN_JSON=(installed_plugins.json known_marketplaces.json)
readonly -a _CKIPPER_ACCOUNT_SEED_PLUGIN_DIRS=(cache marketplaces)

# Print the group an account belongs to (empty when it has none).
#
# Args: $1 — account name.
# Returns: 0 always.
_ckipper_account_group_of() {
    jq -r --arg n "$1" '.accounts[$n].group // ""' "$CKIPPER_REGISTRY" 2>/dev/null
}

# Print a group's master account (empty when the group has none).
#
# Args: $1 — group name.
# Returns: 0 always.
_ckipper_account_group_master() {
    jq -r --arg g "$1" '.groups[$g].master // ""' "$CKIPPER_REGISTRY" 2>/dev/null
}

# Print the members of a group, one per line, sorted.
#
# Args: $1 — group name.
# Returns: 0 always.
_ckipper_account_group_members() {
    jq -r --arg g "$1" '.accounts | to_entries[] | select(.value.group == $g) | .key' \
        "$CKIPPER_REGISTRY" 2>/dev/null | sort
}

# Validate a group name (same rules as account names).
#
# Args: $1 — proposed group name.
# Returns: 0 if valid; 1 otherwise.
# Errors (stderr): "Group name must match ^[a-z0-9_-]+$ …"
_ckipper_account_group_validate_name() {
    [[ "$1" =~ ^[a-z0-9_-]+$ ]] && return 0
    echo "Group name must match ^[a-z0-9_-]+$ (lowercase alphanumeric, underscore, hyphen)." >&2
    return 1
}

# Put an account in a group. The first account in a group becomes its
# master; pass "true" as $3 to make the account master of an existing group.
# Leaving a group the account was master of clears that group's master.
#
# Args: $1 — account name; $2 — group name; $3 — "true" to make it master.
# Returns: 0 on success; 1 on unknown account, bad group name, or write failure.
_ckipper_account_group_assign() {
    local name="$1" group="$2" make_master="${3:-false}"
    _core_account_dir "$name" >/dev/null || return 1
    _ckipper_account_group_validate_name "$group" || return 1
    _core_registry_update '
        (.accounts[$n].group // null) as $old
        | .groups //= {}
        | (if $old != null and $old != $g and .groups[$old].master == $n
           then .groups[$old].master = null else . end)
        | .accounts[$n].group = $g
        | (if (.groups[$g].master // null) == null or $m == "true"
           then .groups[$g].master = $n else . end)
    ' --arg n "$name" --arg g "$group" --arg m "$make_master"
}

# `ckipper account group <name> <group> [--master]`.
#
# Args: $1 — account name; $2 — group name; $3 — optional "--master".
# Returns: 0 on success; 1 on usage error or assignment failure.
# Errors (stderr): "Usage: ckipper account group <name> <group> [--master]"
_ckipper_account_group() {
    _core_registry_check_version || return 1
    local name="$1" group="$2" make_master="false"
    [[ "$3" == "--master" ]] && make_master="true"
    if [[ -z "$name" || -z "$group" || ( -n "$3" && "$make_master" != "true" ) ]]; then
        echo "Usage: ckipper account group <name> <group> [--master]" >&2
        return 1
    fi
    _ckipper_account_group_assign "$name" "$group" "$make_master" || return 1
    echo "'$name' is in group '$group' (master: $(_ckipper_account_group_master "$group"))."
}

# Refuse a sync between accounts that are not in the same group.
#
# Args: $1 — source account; $2 — target account.
# Returns: 0 if both are in the same group; 1 otherwise.
# Errors (stderr): "Refusing to sync <src> → <dst>: …"
_ckipper_account_assert_same_group() {
    local src="$1" dst="$2"
    local src_group dst_group
    src_group=$(_ckipper_account_group_of "$src")
    dst_group=$(_ckipper_account_group_of "$dst")
    if [[ -z "$src_group" || -z "$dst_group" ]]; then
        local ungrouped="$src"; [[ -n "$src_group" ]] && ungrouped="$dst"
        echo "Refusing to sync $src → $dst: '$ungrouped' is not in a group. Assign one: ckipper account group $ungrouped <group>" >&2
        return 1
    fi
    [[ "$src_group" == "$dst_group" ]] && return 0
    echo "Refusing to sync $src → $dst: they are in different groups ($src_group vs $dst_group). Sync only copies within a group." >&2
    return 1
}

# Copy a group master's setup into a freshly registered account: every sync
# type (MCP servers, settings, CLAUDE.md, skills, …) plus installed plugins.
# --force skips the running-Claude refusal: nothing is using the new dir yet.
#
# Args: $1 — new account name; $2 — master account name.
# Returns: 0 on success; 1 if the sync failed.
_ckipper_account_seed_from_master() {
    local name="$1" master="$2"
    echo ""
    echo "Copying '$master' (the group master) into '$name'..."
    _ckipper_account_sync_dispatch "$master" "$name" --include all --yes --force || return 1
    _ckipper_account_seed_plugins "$(_core_account_dir "$master")" "$(_core_account_dir "$name")"
}

# Copy the master's installed plugins into a new account. Merges the two
# metadata files (entries the new account already has win), copies cache
# and marketplace dirs without overwriting, then rewrites the master's
# absolute paths to the new dir.
#
# Args: $1 — master config dir; $2 — new account config dir.
# Returns: 0 always.
_ckipper_account_seed_plugins() {
    local master_dir="$1" dir="$2"
    [[ -d "$master_dir/plugins" ]] || return 0
    mkdir -p "$dir/plugins"
    local rel
    for rel in "${_CKIPPER_ACCOUNT_SEED_PLUGIN_DIRS[@]}"; do
        [[ -d "$master_dir/plugins/$rel" ]] || continue
        mkdir -p "$dir/plugins/$rel"
        cp -an "$master_dir/plugins/$rel/." "$dir/plugins/$rel/" 2>/dev/null
    done
    for rel in "${_CKIPPER_ACCOUNT_SEED_PLUGIN_JSON[@]}"; do
        _ckipper_account_seed_merge_plugin_json "$master_dir/plugins/$rel" "$dir/plugins/$rel"
    done
    _ckipper_account_rewrite_plugin_paths "$master_dir/" "$dir/"
}

# Merge one plugin metadata file from the master into the new account.
# installed_plugins.json nests its entries under .plugins; known_marketplaces
# .json is a flat map. Entries already in the destination win.
#
# Args: $1 — master file; $2 — destination file.
# Returns: 0 always (no-op when the master file is missing or invalid).
_ckipper_account_seed_merge_plugin_json() {
    local master_file="$1" dst_file="$2"
    jq -e . "$master_file" >/dev/null 2>&1 || return 0
    if [[ ! -f "$dst_file" ]] || ! jq -e . "$dst_file" >/dev/null 2>&1; then
        cp "$master_file" "$dst_file"
        return 0
    fi
    local merged
    merged=$(jq -s '
        .[0] as $m | .[1] as $d
        | if ($m | has("plugins")) then $m + $d + {plugins: (($m.plugins // {}) + ($d.plugins // {}))}
          else $m + $d end
    ' "$master_file" "$dst_file") || return 0
    _ckipper_account_sync_json_atomic_write "$dst_file" "$merged"
}
