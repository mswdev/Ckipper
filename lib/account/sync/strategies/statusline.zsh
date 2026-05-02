#!/usr/bin/env zsh
# Strategy module for "statusline" sync type.
#
# Statusline lives at <dir>/settings.json `.statusLine` and may reference
# an executable script via .statusLine.command. Sync semantics:
#
#   - settings reference (.statusLine.*): always copied
#   - referenced script: copied IFF the path resolves to inside <src>/.
#     Otherwise (system path, shared script, etc.) the reference is copied
#     verbatim without touching any file on the destination.
#
# Implementation depends on lib/account/sync/strategies/structured.zsh
# for _ckipper_account_sync_json_atomic_write and on lib/account/sync/backup.zsh
# for _ckipper_account_sync_backup_file.

# Single item id constant — statusline is not enumerable per-element.
readonly _CKIPPER_SYNC_STATUSLINE_ID="statusLine"

# Enumerate: emit a single "statusLine" entry iff source has one.
#
# Args: $1 — source account dir.
# Returns: 0; prints one line on hit, empty on miss.
_ckipper_account_sync_statusline_enumerate() {
    local src="$1"
    local file="$src/settings.json"
    [[ ! -f "$file" ]] && return 0
    local has; has=$(jq -r '.statusLine // null' "$file" 2>/dev/null)
    [[ "$has" == "null" ]] && return 0
    echo "$_CKIPPER_SYNC_STATUSLINE_ID\tStatus line"
}

# Compare: shape varies. We treat the .statusLine subtree as one structured
# value (same approach as settings, but always at the .statusLine path).
#
# Args: $1 — src; $2 — dst; $3 — id (always "statusLine").
# Returns: 0; prints "new" | "overwrite" | "unchanged".
_ckipper_account_sync_statusline_compare() {
    local src="$1" dst="$2"
    local s d
    s=$(jq -c '.statusLine // null' "$src/settings.json" 2>/dev/null)
    d=$(jq -c '.statusLine // null' "$dst/settings.json" 2>/dev/null)
    if [[ "$d" == "null" ]]; then echo "new"; return 0; fi
    if [[ "$s" == "$d" ]]; then echo "unchanged"; return 0; fi
    echo "overwrite"
}

# Resolve and detect whether the referenced script lives under <src>/.
# Empty stdout = external (or no command); non-empty = absolute path
# inside src.
#
# Walks every whitespace-delimited token because real-world commands often
# use an interpreter prefix (e.g. "bash /path/to/script.sh", "node x.js",
# "python3 statusline.py"). Returns the first token that resolves to a path
# under the source dir.
#
# Args: $1 — src dir.
# Returns: 0; prints internal-script path or empty.
_ckipper_account_sync_statusline_internal_path() {
    local src="$1"
    local file="$src/settings.json"
    [[ ! -f "$file" ]] && return 0
    local cmd; cmd=$(jq -r '.statusLine.command // empty' "$file" 2>/dev/null)
    [[ -z "$cmd" ]] && return 0
    local token
    for token in ${(z)cmd}; do
        case "$token" in
            "$src"/*) echo "$token"; return 0 ;;
        esac
    done
}

# Summary: combines internal/external indicator with overwrite-or-new.
#
# Args: $1 — src; $2 — dst; $3 — id.
# Returns: 0; prints summary text.
_ckipper_account_sync_statusline_summary() {
    local src="$1" dst="$2"
    local cmp_status; cmp_status=$(_ckipper_account_sync_statusline_compare "$src" "$dst" "$_CKIPPER_SYNC_STATUSLINE_ID")
    local internal; internal=$(_ckipper_account_sync_statusline_internal_path "$src")
    local kind="external"
    [[ -n "$internal" ]] && kind="internal (will copy script)"
    case "$cmp_status" in
        new) echo "new — $kind" ;;
        overwrite) echo "overwrite — $kind" ;;
        unchanged) echo "unchanged" ;;
    esac
}

# Diff: jq before/after of .statusLine.
_ckipper_account_sync_statusline_diff() {
    local src="$1" dst="$2"
    echo "── source ($src/settings.json:.statusLine) ──"
    jq '.statusLine // null' "$src/settings.json"
    echo "── destination ($dst/settings.json:.statusLine) ──"
    jq '.statusLine // null' "$dst/settings.json" 2>/dev/null
}

# Apply: settings.statusLine subtree is written via setpath (same approach
# as the settings strategy). If the referenced script is internal, copy
# it under the destination dir AND rewrite the .command path to the
# destination's location.
#
# Args: $1 — src; $2 — dst; $3 — id; $4 — backup_dir.
# Returns: 0 on success; non-zero on jq/cp/write failure.
_ckipper_account_sync_statusline_apply() {
    local src="$1" dst="$2" id="$3" backup_dir="$4"
    _ckipper_account_sync_backup_file "$backup_dir" "$dst/settings.json" "settings.json" || return 1
    [[ -f "$dst/settings.json" ]] || echo '{}' > "$dst/settings.json"
    local internal; internal=$(_ckipper_account_sync_statusline_internal_path "$src")
    local statusline_obj; statusline_obj=$(jq -c '.statusLine' "$src/settings.json")
    if [[ -n "$internal" ]]; then
        statusline_obj=$(_ckipper_account_sync_statusline_copy_and_rewrite \
            "$src" "$dst" "$internal" "$backup_dir" "$statusline_obj") || return 1
    fi
    local merged
    merged=$(jq --argjson v "$statusline_obj" '.statusLine = $v' "$dst/settings.json")
    _ckipper_account_sync_json_atomic_write "$dst/settings.json" "$merged"
}

# Internal-script branch: copies the script then rewrites .command in the
# given JSON to point at the destination's path.
#
# Args: $1 — src dir; $2 — dst dir; $3 — internal script abs path;
#       $4 — backup_dir; $5 — statusline JSON object.
# Returns: 0 on success (prints rewritten JSON); 1 on cp failure.
_ckipper_account_sync_statusline_copy_and_rewrite() {
    local src="$1" dst="$2" internal="$3" backup_dir="$4" obj="$5"
    local rel="${internal#$src/}"
    _ckipper_account_sync_backup_file "$backup_dir" "$dst/$rel" "$rel" || return 1
    mkdir -p "$dst/${rel:h}"
    cp -a "$internal" "$dst/$rel" || return 1
    # Literal split+join (NOT sub/gsub) — paths often contain regex
    # metacharacters (`.`, `-`) and the interpreter-prefix form means
    # the `$src` substring is not necessarily at position 0.
    echo "$obj" | jq --arg src "$src" --arg dst "$dst" \
        '.command = (.command | split($src) | join($dst))'
}
