#!/usr/bin/env zsh
# Backup primitives for the sync engine.
# Every destructive write goes through _ckipper_account_sync_backup_file
# (called by strategy apply functions BEFORE the merge) so any failure can
# be rolled back from the backup dir.
#
# Layout:
#   <dst-dir>/.ckipper-sync-backups/<UTC-ISO-ts>-from-<source>/
#       <relative-paths-from-dst>
#       .ckipper-sync-manifest.json
#
# 0700 perms on every backup dir; 0600 on every backed-up file (mirrors
# the registry permission discipline in lib/core/registry.zsh).

readonly _CKIPPER_SYNC_BACKUP_SUBDIR=".ckipper-sync-backups"
readonly _CKIPPER_SYNC_BACKUP_DIR_PERMS=700
readonly _CKIPPER_SYNC_BACKUP_FILE_PERMS=600
readonly _CKIPPER_SYNC_MANIFEST_FILE=".ckipper-sync-manifest.json"
readonly _CKIPPER_SYNC_MANIFEST_VERSION=1

# Compute the backup-dir path (does NOT create it). Pure function; no IO.
#
# Args: $1 — destination account dir; $2 — source account name.
# Returns: 0; prints absolute path of the to-be-created backup dir.
_ckipper_account_sync_backup_dir_path() {
    local dst_dir="$1" source_name="$2"
    local ts; ts=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
    echo "$dst_dir/$_CKIPPER_SYNC_BACKUP_SUBDIR/$ts-from-$source_name"
}

# Create the backup root dir for one sync invocation. Idempotent: a
# concurrent caller picking the same timestamp will see the existing dir.
#
# Args: $1 — destination account dir; $2 — source account name.
# Returns: 0; prints the created path on stdout.
_ckipper_account_sync_backup_create() {
    local dst_dir="$1" source_name="$2"
    local backup_dir
    backup_dir=$(_ckipper_account_sync_backup_dir_path "$dst_dir" "$source_name")
    mkdir -p "$backup_dir"
    chmod "$_CKIPPER_SYNC_BACKUP_DIR_PERMS" "$backup_dir"
    echo "$backup_dir"
}

# Copy a single file or directory from the destination into the backup
# dir at the given relative path. No-op when the source path does not
# exist (i.e. operation is "create" — there's nothing to back up).
# Idempotent: a second call for the same rel within one invocation is a
# no-op so the original-state snapshot is preserved when two strategies
# (e.g. settings + statusline) write to the same destination file.
#
# Args: $1 — backup_dir; $2 — absolute source path; $3 — relative destination path.
# Returns: 0 on success or no-op; 1 if cp fails.
_ckipper_account_sync_backup_file() {
    local backup_dir="$1" src="$2" rel="$3"
    [[ ! -e "$src" ]] && return 0
    local dst="$backup_dir/$rel"
    [[ -e "$dst" ]] && return 0
    mkdir -p "${dst:h}"
    cp -a "$src" "$dst" || return 1
    [[ -f "$dst" ]] && chmod "$_CKIPPER_SYNC_BACKUP_FILE_PERMS" "$dst"
    return 0
}

# Initialize the per-invocation manifest with an empty `files` array.
#
# Args: $1 — backup_dir; $2 — source name; $3 — target name.
# Returns: 0; writes manifest JSON to <backup_dir>/<manifest_file>.
_ckipper_account_sync_manifest_init() {
    local backup_dir="$1" source_name="$2" target_name="$3"
    local manifest="$backup_dir/$_CKIPPER_SYNC_MANIFEST_FILE"
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq -n --argjson v "$_CKIPPER_SYNC_MANIFEST_VERSION" \
        --arg s "$source_name" --arg t "$target_name" --arg ts "$ts" \
        '{version: $v, source: $s, target: $t, timestamp: $ts, files: []}' \
        > "$manifest"
    chmod "$_CKIPPER_SYNC_BACKUP_FILE_PERMS" "$manifest"
}

# Append one entry to the manifest. Items field is a comma-separated list
# (the strategy decides what counts as an item — JSON keys, file paths, etc.).
#
# Args: $1 — backup_dir; $2 — relative path; $3 — operation (create|overwrite);
#       $4 — type id; $5 — items (comma-separated, optional).
# Returns: 0 on success; 1 on jq failure (tmp file is cleaned up on every path).
_ckipper_account_sync_manifest_append() {
    local backup_dir="$1" rel="$2" op="$3" type="$4" items="${5:-}"
    local manifest="$backup_dir/$_CKIPPER_SYNC_MANIFEST_FILE"
    local tmp; tmp=$(mktemp "$manifest.XXXXXX")
    if jq --arg p "$rel" --arg o "$op" --arg t "$type" --arg i "$items" \
        '.files += [{path: $p, operation: $o, type: $t, items: ($i | split(",") | map(select(length > 0)))}]' \
        "$manifest" > "$tmp"; then
        mv "$tmp" "$manifest" && chmod "$_CKIPPER_SYNC_BACKUP_FILE_PERMS" "$manifest"
        return $?
    fi
    rm -f "$tmp"
    return 1
}

# List backup directories under <dst>, newest first. Returns absolute paths.
# Sort key is the directory basename — the ts prefix sorts lexicographically
# by design so plain `sort -r` gives newest-first ordering.
#
# Args: $1 — destination account dir.
# Returns: 0 always; prints absolute backup-dir paths, one per line.
_ckipper_account_sync_manifest_list_backups() {
    local dst_dir="$1"
    local root="$dst_dir/$_CKIPPER_SYNC_BACKUP_SUBDIR"
    [[ ! -d "$root" ]] && return 0
    local d
    for d in "$root"/*(N/); do
        echo "$d"
    done | sort -r
}

# Roll back a single target by reversing every entry in its manifest:
# - operation=create  → delete the file at <dst>/<rel> (the sync put it there)
# - operation=overwrite → restore from <backup_dir>/<rel> via atomic rename
#
# Best-effort per-entry: a missing backup or a permission error is logged
# (stderr) but does not stop subsequent entries from rolling back.
#
# Args: $1 — backup_dir for this target; $2 — destination account dir.
# Returns: 0 on full success; 1 if any per-entry rollback failed.
# Errors (stderr): "rollback failed: <relpath> — <reason>" — per-entry failures.
_ckipper_account_sync_rollback_target() {
    local backup_dir="$1" dst_dir="$2"
    local manifest="$backup_dir/$_CKIPPER_SYNC_MANIFEST_FILE"
    [[ ! -f "$manifest" ]] && return 0
    local rc=0
    while IFS=$'\t' read -r op rel; do
        _ckipper_account_sync_rollback_one "$backup_dir" "$dst_dir" "$op" "$rel" || rc=1
    done < <(jq -r '.files[] | "\(.operation)\t\(.path)"' "$manifest")
    return $rc
}

# Per-entry rollback helper. Kept separate so _rollback_target stays under
# the 25-line cap and the per-entry logic is independently unit-testable.
#
# Args: $1 — backup_dir; $2 — dst_dir; $3 — operation; $4 — relative path.
# Returns: 0 on success; 1 on rm/mv failure.
# Errors (stderr): "rollback failed: <rel> — <reason>"
_ckipper_account_sync_rollback_one() {
    local backup_dir="$1" dst_dir="$2" op="$3" rel="$4"
    local live="$dst_dir/$rel"
    if [[ "$op" == "create" ]]; then
        rm -rf "$live" 2>/dev/null || {
            echo "rollback failed: $rel — could not remove created file" >&2
            return 1
        }
        return 0
    fi
    local backup_path="$backup_dir/$rel"
    [[ ! -e "$backup_path" ]] && return 0
    rm -rf "$live" 2>/dev/null
    mkdir -p "${live:h}"
    cp -a "$backup_path" "$live" || {
        echo "rollback failed: $rel — could not restore from backup" >&2
        return 1
    }
}

# Public undo entry — restore from a specific backup dir, then delete it.
# Caller is responsible for refusing if Claude is running on the destination
# (engine.zsh handles that gate).
#
# Args: $1 — backup_dir; $2 — destination account dir.
# Returns: 0 on full restore + cleanup; 1 if restore had failures
#   (backup dir is preserved on partial failure for inspection).
_ckipper_account_sync_undo_from_backup() {
    local backup_dir="$1" dst_dir="$2"
    if ! _ckipper_account_sync_rollback_target "$backup_dir" "$dst_dir"; then
        return 1
    fi
    rm -rf "$backup_dir"
    return 0
}
