#!/usr/bin/env zsh
# Strategy module for "files-flat" sync types — flat .md file collections
# under the account dir:
#   - claude-md     → <dir>/CLAUDE.md (single file, not a directory)
#   - agents        → <dir>/agents/*.md
#   - commands      → <dir>/commands/*.md
#   - output-styles → <dir>/output_styles/*.md
#
# All four types share the contract implementations; the only thing that
# varies is the subpath, declared in _CKIPPER_SYNC_FILES_FLAT_PATH.
#
# Items are identified by their relative path from the account dir
# (e.g. "agents/foo.md"). claude-md's single item id is "CLAUDE.md".

# Per-type relative path under the account dir.
typeset -gA _CKIPPER_SYNC_FILES_FLAT_PATH=(
    [claude-md]="CLAUDE.md"
    [agents]="agents"
    [commands]="commands"
    [output-styles]="output_styles"
)

# Compute sha256 of a file. Uses shasum (macOS-friendly) which is available
# in both macOS and Linux containers. Empty stdout if file missing.
#
# Args: $1 — file path.
# Returns: 0; prints hex hash or empty string.
_core_sync_file_hash() {
    local f="$1"
    [[ ! -f "$f" ]] && { echo ""; return 0; }
    shasum -a 256 "$f" | cut -d' ' -f1
}

# Generic enumerator. Lists items as "<relpath>\t<basename>".
# - For claude-md: a single line iff CLAUDE.md exists.
# - For others: every *.md file under the subdir.
#
# Args: $1 — type id; $2 — source account dir.
# Returns: 0; prints items one per line.
_core_sync_files_flat_enumerate() {
    local type="$1" src="$2"
    local sub="${_CKIPPER_SYNC_FILES_FLAT_PATH[$type]}"
    local target="$src/$sub"
    if [[ "$type" == "claude-md" ]]; then
        [[ ! -f "$target" ]] && return 0
        echo "$sub\t$sub"
        return 0
    fi
    [[ ! -d "$target" ]] && return 0
    local f
    for f in "$target"/*.md(N); do
        echo "${f#$src/}\t${f:t}"
    done
}

# Generic compare via content hash.
#
# Args: $1 — type id; $2 — src; $3 — dst; $4 — relpath (the item id).
# Returns: 0; prints "new" | "overwrite" | "unchanged".
_core_sync_files_flat_compare() {
    local type="$1" src="$2" dst="$3" rel="$4"
    [[ ! -f "$dst/$rel" ]] && { echo "new"; return 0; }
    local sh dh
    sh=$(_core_sync_file_hash "$src/$rel")
    dh=$(_core_sync_file_hash "$dst/$rel")
    [[ "$sh" == "$dh" ]] && { echo "unchanged"; return 0; }
    echo "overwrite"
}

# Generic summary: line-count diff via diff --stat-equivalent.
#
# Args: $1 — type id; $2 — src; $3 — dst; $4 — relpath.
# Returns: 0; prints "new" | "overwrite — +A/-D lines" | "unchanged".
_core_sync_files_flat_summary() {
    local type="$1" src="$2" dst="$3" rel="$4"
    local cmp_status; cmp_status=$(_core_sync_files_flat_compare "$type" "$src" "$dst" "$rel")
    [[ "$cmp_status" != "overwrite" ]] && { echo "$cmp_status"; return 0; }
    local stats; stats=$(diff "$dst/$rel" "$src/$rel" 2>/dev/null \
        | awk 'BEGIN{a=0;d=0} /^>/{a++} /^</{d++} END{printf "+%d/-%d", a, d}')
    echo "overwrite — $stats lines"
}

# Generic diff: unified diff against destination.
#
# Args: $1 — type id; $2 — src; $3 — dst; $4 — relpath.
# Returns: 0 always (diff exit code 1 means "files differ", which is expected).
_core_sync_files_flat_diff() {
    local type="$1" src="$2" dst="$3" rel="$4"
    diff -u "$dst/$rel" "$src/$rel" 2>/dev/null
    return 0
}

# Generic apply: backup destination if present, then cp.
#
# Args: $1 — type id; $2 — src; $3 — dst; $4 — relpath; $5 — backup_dir.
# Returns: 0 on success; 1 on cp failure.
_core_sync_files_flat_apply() {
    local type="$1" src="$2" dst="$3" rel="$4" backup_dir="$5"
    _core_account_sync_backup_file "$backup_dir" "$dst/$rel" "$rel" || return 1
    mkdir -p "$dst/${rel:h}"
    cp -a "$src/$rel" "$dst/$rel"
}

# Per-type contract bindings — one-line wrappers over the generic helpers
# so each type satisfies the strategy naming convention.

# claude-md wrappers
_ckipper_account_sync_claude-md_enumerate() { _core_sync_files_flat_enumerate claude-md "$@"; }
_ckipper_account_sync_claude-md_compare()   { _core_sync_files_flat_compare   claude-md "$@"; }
_ckipper_account_sync_claude-md_summary()   { _core_sync_files_flat_summary   claude-md "$@"; }
_ckipper_account_sync_claude-md_diff()      { _core_sync_files_flat_diff      claude-md "$@"; }
_ckipper_account_sync_claude-md_apply()     { _core_sync_files_flat_apply     claude-md "$@"; }

# agents wrappers
_ckipper_account_sync_agents_enumerate() { _core_sync_files_flat_enumerate agents "$@"; }
_ckipper_account_sync_agents_compare()   { _core_sync_files_flat_compare   agents "$@"; }
_ckipper_account_sync_agents_summary()   { _core_sync_files_flat_summary   agents "$@"; }
_ckipper_account_sync_agents_diff()      { _core_sync_files_flat_diff      agents "$@"; }
_ckipper_account_sync_agents_apply()     { _core_sync_files_flat_apply     agents "$@"; }

# commands wrappers
_ckipper_account_sync_commands_enumerate() { _core_sync_files_flat_enumerate commands "$@"; }
_ckipper_account_sync_commands_compare()   { _core_sync_files_flat_compare   commands "$@"; }
_ckipper_account_sync_commands_summary()   { _core_sync_files_flat_summary   commands "$@"; }
_ckipper_account_sync_commands_diff()      { _core_sync_files_flat_diff      commands "$@"; }
_ckipper_account_sync_commands_apply()     { _core_sync_files_flat_apply     commands "$@"; }

# output-styles wrappers
_ckipper_account_sync_output-styles_enumerate() { _core_sync_files_flat_enumerate output-styles "$@"; }
_ckipper_account_sync_output-styles_compare()   { _core_sync_files_flat_compare   output-styles "$@"; }
_ckipper_account_sync_output-styles_summary()   { _core_sync_files_flat_summary   output-styles "$@"; }
_ckipper_account_sync_output-styles_diff()      { _core_sync_files_flat_diff      output-styles "$@"; }
_ckipper_account_sync_output-styles_apply()     { _core_sync_files_flat_apply     output-styles "$@"; }
