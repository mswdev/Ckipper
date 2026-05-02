#!/usr/bin/env zsh
# Sync engine — type-agnostic main loop.
#
# This module implements the source × targets × types loop. It NEVER
# references concrete type semantics (MCP servers, agents, etc.) — instead
# it dispatches to per-type strategy functions following a fixed naming
# convention. Adding a new type does NOT require touching this file.
#
# ── Strategy contract ────────────────────────────────────────────────────
#
# Every type registered in lib/account/sync/registry.zsh MUST implement
# these five functions, named `_ckipper_account_sync_<type>_<verb>`:
#
#   <type>_enumerate <src_dir>
#       List every syncable item the source has, one per line, as
#       "id<TAB>display". `id` is whatever the apply/compare/diff
#       functions need to look the item up; `display` is the picker label.
#       Empty stdout means "nothing to sync" (no items in source).
#
#   <type>_compare <src_dir> <dst_dir> <id>
#       Print one of: "new" | "overwrite" | "unchanged".
#
#   <type>_summary <src_dir> <dst_dir> <id>
#       Print a one-line summary of the change for the preview table
#       (e.g. "+12/-3 lines", "command changed", "false → true").
#
#   <type>_diff <src_dir> <dst_dir> <id>
#       Print a full diff for drill-down view. Files use `diff -u`;
#       JSON values use side-by-side `jq` pretty-print. May be empty for
#       new items (drill-down skips status==new in the preview UI).
#
#   <type>_apply <src_dir> <dst_dir> <id> <backup_dir>
#       Perform the merge. MUST call _core_account_sync_backup_file
#       before any destructive write. Returns 0 on success; non-zero on
#       failure (engine then triggers per-target rollback).
#
# All five functions take their arguments in the same order so the engine
# can call them through _core_account_sync_strategy_fn uniformly.

# Compute the strategy function name for a (type, verb) pair.
#
# Args: $1 — type id (e.g. "mcp", "claude-md"); $2 — verb (enumerate, compare,
#   summary, diff, apply).
# Returns: 0; prints the function name (e.g. "_ckipper_account_sync_mcp_enumerate").
_core_account_sync_strategy_fn() {
    local type="$1" verb="$2"
    echo "_ckipper_account_sync_${type}_${verb}"
}

# Refuse to sync when Claude is running with the destination's config dir.
# Reuses lib/core/keychain.zsh::_core_running_claude_processes and filters by
# whether any line references the destination directory.
#
# Args: $1 — destination dir; $2 — force flag ("true" | "false").
# Returns: 0 if safe to proceed; 1 if Claude is running on dst (unless force).
# Errors (stderr): a multiline message identifying the running process(es)
#   and the suggested launcher command.
_core_account_sync_assert_dst_idle() {
    local dst_dir="$1" force="$2"
    [[ "$force" == "true" ]] && return 0
    local procs; procs=$(_core_running_claude_processes 2>/dev/null)
    [[ -z "$procs" ]] && return 0
    local matching; matching=$(echo "$procs" | grep -F "$dst_dir" || true)
    [[ -z "$matching" ]] && return 0
    {
        echo "Refusing to sync: Claude is running on the destination config dir."
        echo "$matching" | sed 's/^/  /'
        echo ""
        echo "Quit the session, or pass --force to override (risk of file races)."
    } >&2
    return 1
}

# Validate a single (source, target) pair. Identity check only; account
# existence is handled by _core_account_dir from lib/core/registry.zsh
# at the dispatcher layer.
#
# Args: $1 — source name; $2 — target name.
# Returns: 0 if valid; 1 if names match.
# Errors (stderr): "Source and target must differ: <name>"
_core_account_sync_validate_pair() {
    local src="$1" tgt="$2"
    if [[ "$src" == "$tgt" ]]; then
        echo "Source and target must differ: $src" >&2
        return 1
    fi
    return 0
}

# Build the per-(target, type) change set for a single sync slice.
# For each type, runs that strategy's enumerate then compare per item;
# emits one TSV row per item with the resulting status appended.
#
# Args: $1 — src dir; $2 — dst dir; $3 — src account name; $4 — dst account name;
#       $5..$N — type ids to walk (already resolved from --include/--exclude).
# Returns: 0 always; prints "<type>\t<id>\t<display>\t<status>" per line.
_core_account_sync_build_change_set() {
    local src_dir="$1" dst_dir="$2" src_name="$3" dst_name="$4"
    shift 4
    local type
    for type in "$@"; do
        _core_account_sync_walk_type "$type" "$src_dir" "$dst_dir" "$src_name" "$dst_name"
    done
}

# Walk a single type's items. prefs uses account names instead of dirs.
#
# Args: $1 — type; $2 — src_dir; $3 — dst_dir; $4 — src_name; $5 — dst_name.
# Returns: 0 always; prints rows.
_core_account_sync_walk_type() {
    local type="$1" src_dir="$2" dst_dir="$3" src_name="$4" dst_name="$5"
    local enumerate_fn compare_fn
    enumerate_fn=$(_core_account_sync_strategy_fn "$type" enumerate)
    compare_fn=$(_core_account_sync_strategy_fn "$type" compare)
    local arg_a="$src_dir" arg_b="$dst_dir"
    [[ "$type" == "prefs" ]] && { arg_a="$src_name"; arg_b="$dst_name"; }
    local id display change_status
    while IFS=$'\t' read -r id display; do
        [[ -z "$id" ]] && continue
        change_status=$("$compare_fn" "$arg_a" "$arg_b" "$id")
        echo "$type"$'\t'"$id"$'\t'"$display"$'\t'"$change_status"
    done < <("$enumerate_fn" "$arg_a")
}

# Apply a change set to a single target. Steps:
#   1. Create backup dir + manifest.
#   2. For each change, call the strategy's apply (which itself calls
#      _core_account_sync_backup_file before writing).
#   3. On any failure: roll back via _core_account_sync_rollback_target,
#      print the partial manifest's path, and return non-zero.
#
# Reads the change set on stdin: TSV rows of "<type>\t<id>\t<display>\t<status>"
# where status is one of "new" | "overwrite" (unchanged rows are filtered upstream).
#
# Args: $1 — src dir; $2 — dst dir; $3 — src name; $4 — dst name.
# Returns: 0 on success; 1 if any apply failed (after rollback completed).
_core_account_sync_apply_target() {
    local src_dir="$1" dst_dir="$2" src_name="$3" dst_name="$4"
    local backup_dir
    backup_dir=$(_core_account_sync_backup_create "$dst_dir" "$src_name")
    _core_account_sync_manifest_init "$backup_dir" "$src_name" "$dst_name"
    local rc=0 type id display change_status
    while IFS=$'\t' read -r type id display change_status; do
        [[ -z "$type" || "$change_status" == "unchanged" ]] && continue
        if ! _core_account_sync_apply_one "$type" "$src_dir" "$dst_dir" \
                                          "$src_name" "$dst_name" "$id" \
                                          "$change_status" "$backup_dir"; then
            rc=1
            break
        fi
    done
    if (( rc != 0 )); then
        _core_account_sync_rollback_target "$backup_dir" "$dst_dir" >&2
        echo "Rolled back. Backup preserved at: $backup_dir" >&2
    fi
    return $rc
}

# Apply one change set entry. Bridges between the strategy contract and
# the manifest schema. prefs uses names; everything else uses dirs.
#
# Args: $1 — type; $2 — src_dir; $3 — dst_dir; $4 — src_name; $5 — dst_name;
#       $6 — id; $7 — change status; $8 — backup_dir.
# Returns: 0 on success; non-zero on apply failure.
_core_account_sync_apply_one() {
    local type="$1" src_dir="$2" dst_dir="$3" src_name="$4" dst_name="$5"
    local id="$6" change_status="$7" backup_dir="$8"
    local apply_fn; apply_fn=$(_core_account_sync_strategy_fn "$type" apply)
    local arg_a="$src_dir" arg_b="$dst_dir"
    [[ "$type" == "prefs" ]] && { arg_a="$src_name"; arg_b="$dst_name"; }
    local op="overwrite"; [[ "$change_status" == "new" ]] && op="create"
    local rel; rel=$(_core_account_sync_manifest_rel "$type" "$id")
    "$apply_fn" "$arg_a" "$arg_b" "$id" "$backup_dir" || return 1
    _core_account_sync_manifest_append "$backup_dir" "$rel" "$op" "$type" "$id"
}

# Compute the manifest's path field for a given (type, id). The relpath
# is what _core_account_sync_rollback_one operates on.
#
# Args: $1 — type; $2 — id.
# Returns: 0; prints relpath.
_core_account_sync_manifest_rel() {
    local type="$1" id="$2"
    case "$type" in
        mcp) echo ".claude.json" ;;
        settings|statusline) echo "settings.json" ;;
        prefs) echo "accounts.json" ;;
        *) echo "$id" ;;
    esac
}
