#!/usr/bin/env zsh
# Strategy module for "structured" sync types (JSON-key merges):
#   - mcp      → <dir>/.claude.json `.mcpServers`
#   - settings → <dir>/settings.json (top-level + nested keys; .hooks excluded)
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
    # print -r, not echo: zsh's echo expands backslash escapes, which turned
    # every "\n" inside a JSON string into a raw newline and broke the file.
    print -r -- "$json" | jq '.' > "$tmp" 2>/dev/null
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
    _ckipper_account_sync_json_status "$s" "$d"
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
# Excludes the `.hooks` block (the user-hooks sync type owns it) and the
# `.statusLine` subtree (the statusline sync type owns it — the dedicated
# strategy handles internal-script copy + path rewrite, which `settings`
# cannot do, so enumerating it here would silently plant broken absolute
# paths on the destination when sync runs without `statusline` included).
#
# The id column is the JSON-encoded path array (e.g. `["permissions","allow"]`
# or `["cleanup-period-days"]`). compare/diff/apply parse it back via
# `--argjson p` and use `getpath`/`setpath` — never `.foo.bar` filter strings,
# which jq would mis-parse for keys containing `-`, `.`, or other operator
# characters. The display column is the dotted string for the preview UI.
#
# Args: $1 — source account dir.
# Returns: 0; prints "<json-path-array>\t<display>" per line.
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
        | ($p | map(tostring) | join(".")) as $display
        | select($display | startswith("hooks") | not)
        | select($display | startswith("statusLine") | not)
        | "\($p | tojson)\t\($display)"
    ' "$file" 2>/dev/null
}

# Compare a jq-path between source and destination.
#
# Uses a bare `getpath` (no `// null` fallback): jq's `//` treats `false` as
# missing, which made every `false` setting look "new" on every sync.
# getpath already yields null for an absent path.
#
# Args: $1 — src; $2 — dst; $3 — JSON path array (e.g. '["model"]').
# Returns: 0; prints "new" | "overwrite" | "unchanged".
_ckipper_account_sync_settings_compare() {
    local src="$1" dst="$2" id="$3"
    local s d
    s=$(jq -c --argjson p "$id" 'getpath($p)' "$src/settings.json" 2>/dev/null)
    d=$(jq -c --argjson p "$id" 'getpath($p)' "$dst/settings.json" 2>/dev/null)
    _ckipper_account_sync_json_status "$s" "$d"
}

# One-line summary for the preview table.
#
# Args: $1 — src; $2 — dst; $3 — JSON path array.
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
# Args: $1 — src; $2 — dst; $3 — JSON path array.
# Returns: 0; prints labeled before/after.
_ckipper_account_sync_settings_diff() {
    local src="$1" dst="$2" id="$3"
    local display; display=$(jq -r -n --argjson p "$id" '$p | map(tostring) | join(".")')
    echo "── source ($src/settings.json:$display) ──"
    jq --argjson p "$id" 'getpath($p)' "$src/settings.json"
    echo "── destination ($dst/settings.json:$display) ──"
    jq --argjson p "$id" 'getpath($p)' "$dst/settings.json" 2>/dev/null
}

# Apply: write the source value at the given path into the destination's
# settings.json using jq's `setpath`, preserving all sibling content. Uses
# atomic write + JSON validation gate.
#
# Args: $1 — src; $2 — dst; $3 — JSON path array; $4 — backup_dir.
# Returns: 0 on success; non-zero on jq/write failure.
_ckipper_account_sync_settings_apply() {
    local src="$1" dst="$2" id="$3" backup_dir="$4"
    _ckipper_account_sync_backup_file "$backup_dir" "$dst/settings.json" "settings.json" || return 1
    [[ -f "$dst/settings.json" ]] || echo '{}' > "$dst/settings.json"
    local val_json
    val_json=$(jq -c --argjson p "$id" 'getpath($p)' "$src/settings.json")
    local merged
    merged=$(jq --argjson p "$id" --argjson v "$val_json" \
        'setpath($p; $v)' "$dst/settings.json")
    _ckipper_account_sync_json_atomic_write "$dst/settings.json" "$merged"
}

