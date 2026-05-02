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
#   <type>_apply <src_dir> <dst_dir> <id>
#       Perform the merge. MUST call _ckipper_account_sync_backup_file
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
