#!/usr/bin/env zsh
# Strategy module for "hooks" sync type — USER-WRITTEN HOOKS ONLY.
#
# A hook script <src>/hooks/<file> is a sync candidate iff the filename
# does NOT match a ckipper-managed install hook in $CKIPPER_DIR/hooks/.
# This filter is computed at runtime so adding a new ckipper safety hook
# automatically excludes it from sync.
#
# Each enumerated item is (script-file, paired-settings-entry). The apply
# function does both:
#   1. Copy the script to the destination (with backup).
#   2. Rewrite the .hooks block in <dst>/settings.json to include the
#      paired entry from <src>/settings.json, with command paths rewritten
#      to point at the destination's hooks dir.

# Build the install-managed allowlist as a newline-separated set of basenames.
#
# Returns: 0; prints one filename per line. Empty if install hooks dir
#   doesn't exist.
_core_sync_hooks_install_allowlist() {
    local install_dir="$CKIPPER_DIR/hooks"
    [[ ! -d "$install_dir" ]] && return 0
    local f
    for f in "$install_dir"/*(N); do
        [[ -f "$f" ]] || continue
        echo "${f:t}"
    done
}

# Enumerate user-written hooks in <src>/hooks/ — files NOT in the install
# allowlist.
#
# Args: $1 — source account dir.
# Returns: 0; prints "<relpath>\t<basename>" per item.
_ckipper_account_sync_hooks_enumerate() {
    local src="$1"
    local hooks_dir="$src/hooks"
    [[ ! -d "$hooks_dir" ]] && return 0
    local allowlist; allowlist=$(_core_sync_hooks_install_allowlist)
    local f base
    for f in "$hooks_dir"/*(N); do
        [[ -f "$f" ]] || continue
        base="${f:t}"
        if [[ -n "$allowlist" ]] && echo "$allowlist" | grep -qx "$base"; then
            continue
        fi
        echo "hooks/$base\t$base"
    done
}

# Compare: file content hash for the script. Settings entry coupling is
# transparent — if the script differs, the whole pair is treated as
# overwrite even if the .hooks entry is identical.
#
# Args: $1 — src; $2 — dst; $3 — relpath (hooks/<basename>).
# Returns: 0; prints "new" | "overwrite" | "unchanged".
_ckipper_account_sync_hooks_compare() {
    local src="$1" dst="$2" rel="$3"
    [[ ! -f "$dst/$rel" ]] && { echo "new"; return 0; }
    local sh dh
    sh=$(_core_sync_file_hash "$src/$rel" 2>/dev/null)
    dh=$(_core_sync_file_hash "$dst/$rel" 2>/dev/null)
    [[ "$sh" == "$dh" ]] && { echo "unchanged"; return 0; }
    echo "overwrite"
}

# Summary: line-count delta + " (paired settings entry)" annotation.
#
# Args: $1 — src; $2 — dst; $3 — relpath.
# Returns: 0; prints summary.
_ckipper_account_sync_hooks_summary() {
    local src="$1" dst="$2" rel="$3"
    local cmp_status; cmp_status=$(_ckipper_account_sync_hooks_compare "$src" "$dst" "$rel")
    case "$cmp_status" in
        new) echo "new — paired with settings.hooks entry" ;;
        overwrite)
            local stats; stats=$(diff "$dst/$rel" "$src/$rel" 2>/dev/null \
                | awk 'BEGIN{a=0;d=0} /^>/{a++} /^</{d++} END{printf "+%d/-%d", a, d}')
            echo "overwrite — $stats lines (+ settings entry)"
            ;;
        unchanged) echo "unchanged" ;;
    esac
}

# Diff: file diff plus a note about the settings entry.
_ckipper_account_sync_hooks_diff() {
    local src="$1" dst="$2" rel="$3"
    diff -u "$dst/$rel" "$src/$rel" 2>/dev/null
    echo "── paired settings.json entry: rewritten for destination dir on apply ──"
    return 0
}

# Apply: copy script + write paired settings.hooks entry with rewritten paths.
#
# Args: $1 — src; $2 — dst; $3 — relpath; $4 — backup_dir.
# Returns: 0 on success; non-zero on cp/jq/write failure.
_ckipper_account_sync_hooks_apply() {
    local src="$1" dst="$2" rel="$3" backup_dir="$4"
    _core_account_sync_backup_file "$backup_dir" "$dst/$rel" "$rel" || return 1
    _core_account_sync_backup_file "$backup_dir" "$dst/settings.json" "settings.json" || return 1
    mkdir -p "$dst/${rel:h}"
    cp -a "$src/$rel" "$dst/$rel" || return 1
    chmod +x "$dst/$rel" 2>/dev/null
    _core_sync_hooks_merge_settings "$src" "$dst" "$rel"
}

# Merge a single user-hook's paired settings.json entries from src into dst,
# rewriting absolute paths from src dir → dst dir. Operates by:
#   1. Filtering src settings.hooks entries to those whose .command
#      references "/<script_basename>" (the user hook being synced).
#   2. Rewriting each .command path's src prefix → dst prefix.
#   3. Appending the filtered+rewritten entries to dst's per-event arrays
#      (creating events that didn't exist on dst).
#
# Args: $1 — src; $2 — dst; $3 — script relpath (hooks/<basename>).
# Returns: 0 on success; non-zero on jq/write failure.
_core_sync_hooks_merge_settings() {
    local src="$1" dst="$2" rel="$3"
    local src_settings="$src/settings.json"
    local dst_settings="$dst/settings.json"
    [[ ! -f "$src_settings" ]] && return 0
    [[ ! -f "$dst_settings" ]] && echo '{}' > "$dst_settings"
    local script_basename="${rel:t}"
    local filtered_src_hooks
    filtered_src_hooks=$(_core_sync_hooks_filter_src "$src_settings" "$script_basename" "$src" "$dst")
    local merged
    merged=$(jq --argjson src_hooks "$filtered_src_hooks" '
        .hooks //= {} |
        reduce ($src_hooks | to_entries[]) as $event (
            .;
            .hooks[$event.key] //= [] |
            .hooks[$event.key] += $event.value
        )
    ' "$dst_settings")
    _core_sync_json_atomic_write "$dst_settings" "$merged"
}

# Helper: filter src settings.hooks to only those entries that reference
# the given script basename, with the src→dst path rewrite applied.
#
# Args: $1 — src settings.json path; $2 — script basename;
#       $3 — src dir; $4 — dst dir.
# Returns: 0; prints filtered hooks JSON object (may be empty {}).
_core_sync_hooks_filter_src() {
    local src_settings="$1" script_basename="$2" src="$3" dst="$4"
    jq --arg sb "$script_basename" --arg src "$src" --arg dst "$dst" '
        (.hooks // {})
        | to_entries
        | map({
            key: .key,
            value: (
                .value
                | map(.hooks |= map(select(.command | tostring | contains("/" + $sb))))
                | map(select(.hooks | length > 0))
                | map(.hooks |= map(.command |= gsub($src; $dst)))
            )
          })
        | map(select(.value | length > 0))
        | from_entries
    ' "$src_settings"
}
