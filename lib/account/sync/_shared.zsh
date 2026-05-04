#!/usr/bin/env zsh
# Strategy-shared helpers — content hashing, diff stats, JSON status compare.
#
# Sourced from ckipper.zsh BEFORE any strategy module so every strategy can
# call these without a sibling import. Keep this file dependency-free
# (no calls into other sync modules) so the load order stays trivial.

# Per-target context shared across the engine, dispatcher, and preview
# modules. Single canonical declaration here — those three modules must NOT
# redeclare it (any `=()` in a redeclaration would silently reset state set
# by an earlier module). Module test files source this file before the
# module under test for the same reason.
#
# Keys: src_dir, dst_dir, src_name, dst_name, backup_dir, changeset,
# summaries, items.
typeset -gA _CKIPPER_SYNC_CTX

# Compute sha256 of a file. Uses shasum (macOS- and Linux-friendly).
#
# Args: $1 — file path.
# Returns: 0; prints hex hash, or empty string if path is missing.
_ckipper_account_sync_hash_file() {
    local f="$1"
    [[ ! -f "$f" ]] && { echo ""; return 0; }
    shasum -a 256 "$f" | cut -d' ' -f1
}

# Compute a content hash for a directory or symlink. For symlinks: the
# target path. For regular dirs: concatenated sha256 of every file in
# lexical order, hashed once more.
#
# Note: arg variable is `target` (not `path`) — zsh ties lowercase `path` to
# `$PATH` as an array, which corrupts the env if used as a local var.
#
# Args: $1 — path to directory or symlink.
# Returns: 0; prints hex hash, or empty string if path is missing.
_ckipper_account_sync_hash_dir() {
    local target="$1"
    [[ ! -e "$target" ]] && { echo ""; return 0; }
    if [[ -L "$target" ]]; then
        readlink "$target" | shasum -a 256 | cut -d' ' -f1
        return 0
    fi
    [[ ! -d "$target" ]] && { echo ""; return 0; }
    (cd "$target" && find . -type f -print0 2>/dev/null \
        | sort -z \
        | xargs -0 shasum -a 256 2>/dev/null) \
        | shasum -a 256 | cut -d' ' -f1
}

# Run a unified `diff` on two files and emit a "+A/-D" line-stat string.
# Used by file-shaped strategies (files-flat, hooks) for the preview summary.
#
# Args: $1 — destination file (left side); $2 — source file (right side).
# Returns: 0 always (diff exit 1 means "files differ", expected); prints "+A/-D".
_ckipper_account_sync_diff_line_stats() {
    diff "$1" "$2" 2>/dev/null \
        | awk 'BEGIN{a=0;d=0} /^>/{a++} /^</{d++} END{printf "+%d/-%d", a, d}'
}

# Compare two pre-extracted JSON-string operands and emit the standard
# strategy status word. Used by structured-style strategies (mcp, settings,
# statusline) where both sides are jq-formatted to a comparable string.
#
# Empty `d` means the destination file was missing entirely (jq exited
# non-zero); treat the same as "key absent" so apply records `op=create`.
#
# Args: $1 — source JSON string; $2 — destination JSON string ("" or "null"
#   if absent).
# Returns: 0; prints "new" | "unchanged" | "overwrite".
_ckipper_account_sync_json_status() {
    local s="$1" d="$2"
    [[ -z "$d" || "$d" == "null" ]] && { echo "new"; return 0; }
    [[ "$s" == "$d" ]] && { echo "unchanged"; return 0; }
    echo "overwrite"
}
