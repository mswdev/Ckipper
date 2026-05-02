#!/usr/bin/env zsh
# Strategy module for "files-dir" sync types — per-directory items:
#   - skills → <dir>/skills/<name>/
#
# Each item is a top-level entry under the type's subdir (regular dir OR
# symlink). cp -a preserves symlink semantics, so a destination's symlink
# resolves to the same target as the source's.
#
# Comparison is a recursive content hash (concatenation of per-file hashes
# in lexical order, then hashed). Symlinks are compared by their target
# path, NOT by the contents of the target (so two symlinks pointing at
# the same dir compare equal even if the shared target diverges later).

# Per-type relative subdir under the account dir.
typeset -gA _CKIPPER_SYNC_FILES_DIR_PATH=(
    [skills]="skills"
)

# Compute a content hash for a directory or symlink. For symlinks: the
# target path. For regular dirs: concatenated sha256 of every file in
# lexical order, hashed once more.
#
# Note: arg variable is `target` (not `path`) — zsh ties lowercase `path` to
# `$PATH` as an array, which corrupts the env if used as a local var.
#
# Args: $1 — path to directory or symlink.
# Returns: 0; prints hex hash or empty if path is missing.
_core_sync_dir_hash() {
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

# Enumerate top-level items under the type's subdir. Picks up dirs AND
# symlinks. We use a manual loop so broken symlinks also enumerate, with
# apply later catching the failure.
#
# Args: $1 — type id; $2 — source account dir.
# Returns: 0; prints "<relpath>\t<basename>" per item.
_core_sync_files_dir_enumerate() {
    local type="$1" src="$2"
    local sub="${_CKIPPER_SYNC_FILES_DIR_PATH[$type]}"
    local root="$src/$sub"
    [[ ! -d "$root" ]] && return 0
    local entry
    for entry in "$root"/*(NDoN); do
        [[ -d "$entry" || -L "$entry" ]] || continue
        echo "$sub/${entry:t}\t${entry:t}"
    done
}

# Compare item by directory hash.
#
# Args: $1 — type id; $2 — src; $3 — dst; $4 — relpath.
# Returns: 0; prints "new" | "overwrite" | "unchanged".
_core_sync_files_dir_compare() {
    local type="$1" src="$2" dst="$3" rel="$4"
    [[ ! -e "$dst/$rel" ]] && { echo "new"; return 0; }
    local sh dh
    sh=$(_core_sync_dir_hash "$src/$rel")
    dh=$(_core_sync_dir_hash "$dst/$rel")
    [[ "$sh" == "$dh" ]] && { echo "unchanged"; return 0; }
    echo "overwrite"
}

# Summary: file count delta if both sides exist, else status word.
#
# Args: $1 — type id; $2 — src; $3 — dst; $4 — relpath.
# Returns: 0; prints summary.
_core_sync_files_dir_summary() {
    local type="$1" src="$2" dst="$3" rel="$4"
    local cmp_status; cmp_status=$(_core_sync_files_dir_compare "$type" "$src" "$dst" "$rel")
    case "$cmp_status" in
        new) echo "new directory" ;;
        overwrite)
            local sn dn
            sn=$(find "$src/$rel" -type f 2>/dev/null | wc -l | tr -d ' ')
            dn=$(find "$dst/$rel" -type f 2>/dev/null | wc -l | tr -d ' ')
            echo "overwrite — $dn → $sn files"
            ;;
        unchanged) echo "unchanged" ;;
    esac
}

# Diff: list of file changes via diff -rq between trees. For symlinks,
# print the target paths.
#
# Args: $1 — type id; $2 — src; $3 — dst; $4 — relpath.
# Returns: 0 always.
_core_sync_files_dir_diff() {
    local type="$1" src="$2" dst="$3" rel="$4"
    if [[ -L "$src/$rel" || -L "$dst/$rel" ]]; then
        echo "── source symlink ──"
        [[ -L "$src/$rel" ]] && readlink "$src/$rel"
        echo "── destination symlink ──"
        [[ -L "$dst/$rel" ]] && readlink "$dst/$rel"
        return 0
    fi
    diff -ruN "$dst/$rel" "$src/$rel" 2>/dev/null
    return 0
}

# Apply: backup the destination dir (if present), remove it, then cp -a.
# `rm -rf` is safe because the prior copy is in the backup dir; rollback
# restores it.
#
# Args: $1 — type id; $2 — src; $3 — dst; $4 — relpath; $5 — backup_dir.
# Returns: 0 on success; 1 on cp failure.
_core_sync_files_dir_apply() {
    local type="$1" src="$2" dst="$3" rel="$4" backup_dir="$5"
    _core_account_sync_backup_file "$backup_dir" "$dst/$rel" "$rel" || return 1
    rm -rf "$dst/$rel"
    mkdir -p "$dst/${rel:h}"
    cp -a "$src/$rel" "$dst/$rel"
}

# Per-type wrappers for the strategy contract.
_ckipper_account_sync_skills_enumerate() { _core_sync_files_dir_enumerate skills "$@"; }
_ckipper_account_sync_skills_compare()   { _core_sync_files_dir_compare   skills "$@"; }
_ckipper_account_sync_skills_summary()   { _core_sync_files_dir_summary   skills "$@"; }
_ckipper_account_sync_skills_diff()      { _core_sync_files_dir_diff      skills "$@"; }
_ckipper_account_sync_skills_apply()     { _core_sync_files_dir_apply     skills "$@"; }
