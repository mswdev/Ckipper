#!/usr/bin/env zsh
# Strategy module for "structured" sync types (JSON-key merges):
#   - mcp      → <dir>/.claude.json `.mcpServers`
#   - settings → <dir>/settings.json (top-level + nested keys; .hooks excluded)
#   - prefs    → $CKIPPER_REGISTRY `.accounts.<name>.preferences`
#
# Each type implements the strategy contract documented in engine.zsh:
#   _ckipper_account_sync_<type>_{enumerate,compare,summary,diff,apply}
#
# All apply functions go through _ckipper_account_sync_json_atomic_write which:
#   1. Writes the candidate JSON to a tmpfile
#   2. Validates with `jq -e .`
#   3. mv's into place ONLY if validation passes (Safeguard #4)

# Validate a JSON file with jq. No output; exit code is the signal.
#
# Args: $1 — path to a JSON file (must exist).
# Returns: 0 if valid; non-zero if invalid or jq unavailable.
_ckipper_account_sync_json_validate() {
    jq -e . "$1" >/dev/null 2>&1
}

# Write JSON to a target path atomically with validation. Steps:
#   1. mktemp peer of target
#   2. write the candidate JSON pretty-printed via jq
#   3. validate via _ckipper_account_sync_json_validate; abort on failure (no clobber)
#   4. mv into place
#
# Args: $1 — target path; $2 — candidate JSON string.
# Returns: 0 on commit; 1 on jq parse error; 2 on mv failure.
# Errors (stderr): "Refusing to write invalid JSON to <path>"
_ckipper_account_sync_json_atomic_write() {
    local target="$1" json="$2"
    mkdir -p "${target:h}"
    local tmp; tmp=$(mktemp "${target}.XXXXXX")
    echo "$json" | jq '.' > "$tmp" 2>/dev/null
    if ! _ckipper_account_sync_json_validate "$tmp"; then
        echo "Refusing to write invalid JSON to $target" >&2
        rm -f "$tmp"
        return 1
    fi
    mv "$tmp" "$target" || return 2
}

# ── MCP strategy ─────────────────────────────────────────────────────────

# Enumerate every MCP server name in the source's .claude.json. Empty stdout
# when the file is missing or .mcpServers is empty/null.
#
# Args: $1 — source account dir.
# Returns: 0; prints "<name>\t<name>" per line (id and display are the same here).
_ckipper_account_sync_mcp_enumerate() {
    local src="$1"
    local file="$src/.claude.json"
    [[ ! -f "$file" ]] && return 0
    jq -r '.mcpServers // {} | keys[]? | "\(.)\t\(.)"' "$file" 2>/dev/null
}

# Compare a single MCP server between source and destination.
#
# Args: $1 — src; $2 — dst; $3 — server name.
# Returns: 0; prints "new" | "overwrite" | "unchanged".
_ckipper_account_sync_mcp_compare() {
    local src="$1" dst="$2" name="$3"
    local s d
    s=$(jq -c --arg n "$name" '.mcpServers[$n] // null' "$src/.claude.json" 2>/dev/null)
    d=$(jq -c --arg n "$name" '.mcpServers[$n] // null' "$dst/.claude.json" 2>/dev/null)
    # Empty `d` means the destination file is missing entirely (jq exited
    # non-zero); treat the same as "key absent" so the manifest records `op=create`
    # and rollback knows to delete (not restore-overwrite) the new file.
    if [[ -z "$d" || "$d" == "null" ]]; then echo "new"; return 0; fi
    if [[ "$s" == "$d" ]]; then echo "unchanged"; return 0; fi
    echo "overwrite"
}

# One-line summary of the change for the preview table.
#
# Args: $1 — src; $2 — dst; $3 — server name.
# Returns: 0; prints summary text.
_ckipper_account_sync_mcp_summary() {
    local src="$1" dst="$2" name="$3"
    local cmp_status; cmp_status=$(_ckipper_account_sync_mcp_compare "$src" "$dst" "$name")
    case "$cmp_status" in
        new) echo "new" ;;
        overwrite) echo "overwrite — server config changed" ;;
        unchanged) echo "unchanged" ;;
    esac
}

# Full diff for drill-down view: jq pretty-print of source vs destination.
#
# Args: $1 — src; $2 — dst; $3 — server name.
# Returns: 0; prints labeled before/after blocks.
_ckipper_account_sync_mcp_diff() {
    local src="$1" dst="$2" name="$3"
    echo "── source ($src/.claude.json:.mcpServers.$name) ──"
    jq --arg n "$name" '.mcpServers[$n] // null' "$src/.claude.json"
    echo "── destination ($dst/.claude.json:.mcpServers.$name) ──"
    jq --arg n "$name" '.mcpServers[$n] // null' "$dst/.claude.json" 2>/dev/null
}

# Merge a single server from src into dst's .claude.json. Backs up the
# destination's .claude.json before writing.
#
# Args: $1 — src; $2 — dst; $3 — server name; $4 — backup_dir.
# Returns: 0 on success; non-zero on jq/write failure.
_ckipper_account_sync_mcp_apply() {
    local src="$1" dst="$2" name="$3" backup_dir="$4"
    _ckipper_account_sync_backup_file "$backup_dir" "$dst/.claude.json" ".claude.json" || return 1
    local server_obj
    server_obj=$(jq -c --arg n "$name" '.mcpServers[$n]' "$src/.claude.json")
    [[ -f "$dst/.claude.json" ]] || echo '{}' > "$dst/.claude.json"
    local merged
    merged=$(jq --arg n "$name" --argjson v "$server_obj" \
        '.mcpServers = (.mcpServers // {}) | .mcpServers[$n] = $v' "$dst/.claude.json")
    _ckipper_account_sync_json_atomic_write "$dst/.claude.json" "$merged"
}

# ── Settings strategy ────────────────────────────────────────────────────

# Enumerate jq paths the user can sync. Recursion stops at scalars or
# top-level keys whose value is a primitive; objects are enumerated as
# their leaf paths so the user can sync just `.permissions.allow` without
# touching `.permissions.deny`.
#
# Excludes the `.hooks` block — the user-hooks sync type owns it.
#
# Args: $1 — source account dir.
# Returns: 0; prints "<jq-path-no-leading-dot>\t<display>" per line.
_ckipper_account_sync_settings_enumerate() {
    local src="$1"
    local file="$src/settings.json"
    [[ ! -f "$file" ]] && return 0
    jq -r '
        . as $root
        | [paths]
        | map(select(([.[]] | map(type == "number") | any | not)))
        | map(select(length > 0))
        | .[]
        | . as $p
        | select(($root | getpath($p)) | type != "object")
        | ($p | map(tostring) | join(".")) as $k
        | select($k | startswith("hooks") | not)
        | "\($k)\t\($k)"
    ' "$file" 2>/dev/null
}

# Compare a jq-path between source and destination.
#
# Args: $1 — src; $2 — dst; $3 — jq path (no leading dot).
# Returns: 0; prints "new" | "overwrite" | "unchanged".
_ckipper_account_sync_settings_compare() {
    local src="$1" dst="$2" id="$3"
    local jq_path; jq_path=$(_ckipper_account_sync_settings_jq_path "$id")
    local s d
    s=$(jq -c "$jq_path // null" "$src/settings.json" 2>/dev/null)
    d=$(jq -c "$jq_path // null" "$dst/settings.json" 2>/dev/null)
    # Empty `d` means the destination file is missing entirely; see the
    # equivalent guard in `_ckipper_account_sync_mcp_compare` for rationale.
    if [[ -z "$d" || "$d" == "null" ]]; then echo "new"; return 0; fi
    if [[ "$s" == "$d" ]]; then echo "unchanged"; return 0; fi
    echo "overwrite"
}

# Convert a dotted id like "permissions.allow" into a jq filter ".permissions.allow".
# Bare id goes to the empty filter "." which selects the document root —
# never used in practice because enumerate filters to leaves.
#
# Note: arg variable is `id` (not `path`) — zsh ties lowercase `path` to `$PATH`
# as an array, which corrupts the env if used as a local var.
#
# Args: $1 — dotted id (no leading dot).
# Returns: 0; prints jq filter string.
_ckipper_account_sync_settings_jq_path() {
    local id="$1"
    [[ -z "$id" ]] && { echo "."; return 0; }
    echo ".$id"
}

# One-line summary for the preview table.
#
# Args: $1 — src; $2 — dst; $3 — jq path.
# Returns: 0; prints summary.
_ckipper_account_sync_settings_summary() {
    local src="$1" dst="$2" id="$3"
    local cmp_status; cmp_status=$(_ckipper_account_sync_settings_compare "$src" "$dst" "$id")
    case "$cmp_status" in
        new) echo "new key" ;;
        overwrite) echo "overwrite — value changed" ;;
        unchanged) echo "unchanged" ;;
    esac
}

# Full diff for drill-down.
#
# Args: $1 — src; $2 — dst; $3 — jq path.
# Returns: 0; prints labeled before/after.
_ckipper_account_sync_settings_diff() {
    local src="$1" dst="$2" id="$3"
    local jq_path; jq_path=$(_ckipper_account_sync_settings_jq_path "$id")
    echo "── source ($src/settings.json:$id) ──"
    jq "$jq_path" "$src/settings.json"
    echo "── destination ($dst/settings.json:$id) ──"
    jq "$jq_path" "$dst/settings.json" 2>/dev/null
}

# Apply: write the source value at jq-path into the destination's settings.json
# using jq's `setpath`, preserving all sibling content. Uses atomic write +
# JSON validation gate.
#
# Args: $1 — src; $2 — dst; $3 — jq path; $4 — backup_dir.
# Returns: 0 on success; non-zero on jq/write failure.
_ckipper_account_sync_settings_apply() {
    local src="$1" dst="$2" id="$3" backup_dir="$4"
    _ckipper_account_sync_backup_file "$backup_dir" "$dst/settings.json" "settings.json" || return 1
    [[ -f "$dst/settings.json" ]] || echo '{}' > "$dst/settings.json"
    local jq_path; jq_path=$(_ckipper_account_sync_settings_jq_path "$id")
    local val_json
    val_json=$(jq -c "$jq_path" "$src/settings.json")
    local id_array
    id_array=$(jq -c -n --arg p "$id" '$p | split(".")')
    local merged
    merged=$(jq --argjson p "$id_array" --argjson v "$val_json" \
        'setpath($p; $v)' "$dst/settings.json")
    _ckipper_account_sync_json_atomic_write "$dst/settings.json" "$merged"
}

# ── Prefs strategy ───────────────────────────────────────────────────────
#
# Operates on the registry (accounts.json), not per-account dirs. The engine
# passes account NAMES through the dir args. This is the only strategy that
# uses CKIPPER_REGISTRY rather than the dir paths.
#
# Depends on lib/config/schema.zsh (account-scope key list) and
# lib/core/config.zsh (_core_config_get/_core_config_set).

# Enumerate every account-scope schema key.
#
# Args: $1 — source account name (unused; kept for contract uniformity).
# Returns: 0; prints "<key>\t<key>" per line.
_ckipper_account_sync_prefs_enumerate() {
    local key
    for key in "${(@k)_CKIPPER_SCHEMA_TYPE}"; do
        [[ "${_CKIPPER_SCHEMA_SCOPE[$key]}" == "account" ]] || continue
        echo "$key\t$key"
    done
}

# Compare one preference key.
#
# Args: $1 — source account name; $2 — dst account name; $3 — schema key.
# Returns: 0; prints "new" | "overwrite" | "unchanged".
_ckipper_account_sync_prefs_compare() {
    local src="$1" dst="$2" key="$3"
    local s d
    s=$(_core_config_get "$key" "$src")
    d=$(_core_config_get "$key" "$dst")
    [[ "$s" == "$d" ]] && { echo "unchanged"; return 0; }
    # `new` is rare for prefs — the v2 migration ensures every account has
    # all keys with defaults. We still distinguish: if the destination has
    # no override (raw read empty), call it new.
    local raw; raw=$(_core_config_read_account "$key" "$dst")
    [[ -z "$raw" ]] && { echo "new"; return 0; }
    echo "overwrite"
}

# Summary: for prefs the value is short, render inline.
#
# Args: $1 — src name; $2 — dst name; $3 — key.
# Returns: 0; prints e.g. "false → true" or "(default) → true".
_ckipper_account_sync_prefs_summary() {
    local src="$1" dst="$2" key="$3"
    local s d_raw d_eff
    s=$(_core_config_get "$key" "$src")
    d_raw=$(_core_config_read_account "$key" "$dst")
    d_eff=$(_core_config_get "$key" "$dst")
    if [[ -z "$d_raw" ]]; then
        echo "(default $d_eff) → $s"
    else
        echo "$d_eff → $s"
    fi
}

# Diff: prefs are scalar — diff is the same as summary.
#
# Args: $1 — src name; $2 — dst name; $3 — key.
# Returns: 0; prints summary.
_ckipper_account_sync_prefs_diff() {
    _ckipper_account_sync_prefs_summary "$@"
}

# Apply via _core_config_set (uses registry locking). The registry write
# itself is its own atomic operation, so we do NOT need the JSON validation
# gate here. The backup is the file copy of CKIPPER_REGISTRY into the
# backup dir — recorded in the manifest as path "accounts.json".
#
# Args: $1 — src name; $2 — dst name; $3 — key; $4 — backup_dir.
# Returns: 0 on success; non-zero on read/write failure.
_ckipper_account_sync_prefs_apply() {
    local src="$1" dst="$2" key="$3" backup_dir="$4"
    _ckipper_account_sync_backup_file "$backup_dir" "$CKIPPER_REGISTRY" "accounts.json" || return 1
    local val; val=$(_core_config_get "$key" "$src")
    _core_config_set "$key" "$val" "$dst"
}
