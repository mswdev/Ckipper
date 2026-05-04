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
#       Perform the merge. MUST call _ckipper_account_sync_backup_file
#       before any destructive write. Returns 0 on success; non-zero on
#       failure (engine then triggers per-target rollback).
#
# All five functions take their arguments in the same order so the engine
# can call them through _ckipper_account_sync_strategy_fn uniformly.

# Per-target context shared by apply_target → apply_one and the preview/
# finalize helpers in dispatcher.zsh. Declared here too because engine.zsh
# is sourced before dispatcher.zsh, and engine_test.bats sources only the
# engine. Re-declaration without `=()` is a no-op so dispatcher.zsh's
# matching declaration doesn't reset state. Keys: src_dir, dst_dir,
# src_name, dst_name, backup_dir (and from dispatcher: changeset, summaries,
# items).
typeset -gA _CKIPPER_SYNC_CTX

# Compute the strategy function name for a (type, verb) pair.
#
# Args: $1 — type id (e.g. "mcp", "claude-md"); $2 — verb (enumerate, compare,
#   summary, diff, apply).
# Returns: 0; prints the function name (e.g. "_ckipper_account_sync_mcp_enumerate").
_ckipper_account_sync_strategy_fn() {
    local type="$1" verb="$2"
    echo "_ckipper_account_sync_${type}_${verb}"
}

# Refuse to sync when any Claude CLI is running.
#
# We previously tried to filter by "Claude running on this destination dir,"
# but that requires reading another process's CLAUDE_CONFIG_DIR env var —
# macOS does not expose that to non-privileged callers (`ps -E` is a no-op
# for foreign processes; `pgrep -lx` only shows PID + basename). The only
# reliable signal we have is "is any claude CLI running at all," so we
# refuse on that. Coarser than designed, but the original sync.zsh on
# develop did the same; --force is the documented escape hatch.
#
# Args: $1 — destination dir (kept in the signature for forward
#   compatibility once we have a dst-specific signal); $2 — force flag
#   ("true" | "false").
# Returns: 0 if safe to proceed; 1 if any Claude CLI is running (unless force).
# Errors (stderr): multiline message identifying the running process(es).
_ckipper_account_sync_assert_dst_idle() {
    local dst_dir="$1" force="$2"
    [[ "$force" == "true" ]] && return 0
    local procs; procs=$(_core_running_claude_processes 2>/dev/null)
    [[ -z "$procs" ]] && return 0
    {
        echo "Refusing to sync: a Claude CLI process is running."
        echo "$procs" | sed 's/^/  /'
        echo ""
        echo "Quit running Claude (or pass --force to override; risk of file races)."
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
_ckipper_account_sync_validate_pair() {
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
_ckipper_account_sync_build_change_set() {
    local src_dir="$1" dst_dir="$2" src_name="$3" dst_name="$4"
    shift 4
    local type
    for type in "$@"; do
        _ckipper_account_sync_walk_type "$type" "$src_dir" "$dst_dir" "$src_name" "$dst_name"
    done
}

# Walk a single type's items. Types in _CKIPPER_SYNC_TYPE_USES_NAMES use
# account names instead of dirs.
#
# Args: $1 — type; $2 — src_dir; $3 — dst_dir; $4 — src_name; $5 — dst_name.
# Returns: 0 always; prints rows.
_ckipper_account_sync_walk_type() {
    local type="$1" src_dir="$2" dst_dir="$3" src_name="$4" dst_name="$5"
    local enumerate_fn compare_fn
    enumerate_fn=$(_ckipper_account_sync_strategy_fn "$type" enumerate)
    compare_fn=$(_ckipper_account_sync_strategy_fn "$type" compare)
    local arg_a="$src_dir" arg_b="$dst_dir"
    (( ${+_CKIPPER_SYNC_TYPE_USES_NAMES[$type]} )) && { arg_a="$src_name"; arg_b="$dst_name"; }
    local id display change_status
    while IFS=$'\t' read -r id display; do
        [[ -z "$id" ]] && continue
        change_status=$("$compare_fn" "$arg_a" "$arg_b" "$id")
        echo "$type"$'\t'"$id"$'\t'"$display"$'\t'"$change_status"
    done < <("$enumerate_fn" "$arg_a")
}

# Apply a change set to a single target. Steps:
#   1. Create backup dir + manifest, populate _CKIPPER_SYNC_CTX[backup_dir].
#   2. For each change, call the strategy's apply (which itself calls
#      _ckipper_account_sync_backup_file before writing).
#   3. On any failure: roll back via _ckipper_account_sync_rollback_target,
#      print the partial manifest's path, and return non-zero.
#
# Also (re)populates _CKIPPER_SYNC_CTX with the four name/dir args so the function
# is callable on its own (engine_test.bats invokes it directly without
# going through run_one_target).
#
# Reads the change set on stdin: TSV rows of "<type>\t<id>\t<display>\t<status>"
# where status is one of "new" | "overwrite" (unchanged rows are filtered upstream).
#
# Args: $1 — src dir; $2 — dst dir; $3 — src name; $4 — dst name.
# Returns: 0 on success; 1 if any apply failed (after rollback completed).
_ckipper_account_sync_apply_target() {
    local src_dir="$1" dst_dir="$2" src_name="$3" dst_name="$4"
    local backup_dir
    backup_dir=$(_ckipper_account_sync_backup_create "$dst_dir" "$src_name")
    _ckipper_account_sync_manifest_init "$backup_dir" "$src_name" "$dst_name"
    _CKIPPER_SYNC_CTX[src_dir]="$src_dir"; _CKIPPER_SYNC_CTX[dst_dir]="$dst_dir"
    _CKIPPER_SYNC_CTX[src_name]="$src_name"; _CKIPPER_SYNC_CTX[dst_name]="$dst_name"
    _CKIPPER_SYNC_CTX[backup_dir]="$backup_dir"
    local rc=0 type id display change_status
    while IFS=$'\t' read -r type id display change_status; do
        [[ -z "$type" || "$change_status" == "unchanged" ]] && continue
        _ckipper_account_sync_apply_one "$type" "$id" || { rc=1; break; }
    done
    if (( rc != 0 )); then
        _ckipper_account_sync_rollback_target "$backup_dir" "$dst_dir" >&2
        echo "Rolled back. Backup preserved at: $backup_dir" >&2
    fi
    return $rc
}

# Apply one change set entry. Bridges between the strategy contract and
# the manifest schema. Types in _CKIPPER_SYNC_TYPE_USES_NAMES use names;
# everything else uses dirs.
#
# Reads src_dir/dst_dir/src_name/dst_name/backup_dir from _CKIPPER_SYNC_CTX (set
# by apply_target). Keeping these in context drops the parameter count
# from 8 to 3, satisfying the .claude/rules/code-style.md cap.
#
# Manifest is appended BEFORE the apply call, not after. If the apply
# crashes mid-write (backed-up the file, started writing, errored), the
# manifest still contains the entry so rollback can restore from the
# backup dir. Without this, mid-write failures leave the destination
# half-written with no manifest record (rollback would skip the file).
#
# `op` is derived from whether the live file exists at apply time, NOT
# from change_status. change_status="new" can fire when a sub-key is
# absent from a file that already exists (e.g. adding one MCP server to a
# .claude.json that already has others); recording op=create there would
# make rollback rm-rf the whole file, destroying unrelated data.
#
# Args: $1 — type; $2 — id.
# Returns: 0 on success; non-zero on apply failure.
_ckipper_account_sync_apply_one() {
    local type="$1" id="$2"
    local apply_fn; apply_fn=$(_ckipper_account_sync_strategy_fn "$type" apply)
    local arg_a="${_CKIPPER_SYNC_CTX[src_dir]}" arg_b="${_CKIPPER_SYNC_CTX[dst_dir]}"
    (( ${+_CKIPPER_SYNC_TYPE_USES_NAMES[$type]} )) && { arg_a="${_CKIPPER_SYNC_CTX[src_name]}"; arg_b="${_CKIPPER_SYNC_CTX[dst_name]}"; }
    local rel; rel=$(_ckipper_account_sync_manifest_rel "$type" "$id")
    local live; live=$(_ckipper_account_sync_live_path "$type" "${_CKIPPER_SYNC_CTX[dst_dir]}" "$rel")
    local op="overwrite"; [[ ! -e "$live" ]] && op="create"
    _ckipper_account_sync_manifest_append "${_CKIPPER_SYNC_CTX[backup_dir]}" "$rel" "$op" "$type" "$id"
    "$apply_fn" "$arg_a" "$arg_b" "$id" "${_CKIPPER_SYNC_CTX[backup_dir]}"
}

# Compute the manifest's path field for a given (type, id). The relpath
# is what _ckipper_account_sync_rollback_one operates on.
#
# Args: $1 — type; $2 — id.
# Returns: 0; prints relpath.
_ckipper_account_sync_manifest_rel() {
    local type="$1" id="$2"
    case "$type" in
        mcp) echo ".claude.json" ;;
        settings|statusline) echo "settings.json" ;;
        prefs) echo "accounts.json" ;;
        *) echo "$id" ;;
    esac
}

# Build a TSV of (type, id, summary) by calling each strategy's _summary
# function for every changeset row. Reads the changeset on stdin; writes
# to stdout. Skips unchanged rows so the picker only sees actionable items.
#
# Args: $1 — src_dir; $2 — dst_dir; $3 — src_name; $4 — dst_name.
# Returns: 0 always.
_ckipper_account_sync_build_summaries() {
    local src_dir="$1" dst_dir="$2" src_name="$3" dst_name="$4"
    local type id display change_status summary_fn arg_a arg_b summary
    while IFS=$'\t' read -r type id display change_status; do
        [[ -z "$type" || "$change_status" == "unchanged" ]] && continue
        summary_fn=$(_ckipper_account_sync_strategy_fn "$type" summary)
        arg_a="$src_dir"; arg_b="$dst_dir"
        (( ${+_CKIPPER_SYNC_TYPE_USES_NAMES[$type]} )) && { arg_a="$src_name"; arg_b="$dst_name"; }
        summary=$("$summary_fn" "$arg_a" "$arg_b" "$id")
        echo "$type"$'\t'"$id"$'\t'"$summary"
    done
}
