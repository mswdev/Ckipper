#!/usr/bin/env zsh
# Shared registry read/write primitives for managing the ckipper accounts registry.

readonly REGISTRY_FILE_PERMS=600
readonly LOCK_NOTIFY_THRESHOLD_ATTEMPTS=30
readonly LOCK_MAX_ATTEMPTS=200
readonly STALE_LOCK_AGE_THRESHOLD_SECONDS=30
readonly LOCK_RETRY_INTERVAL_SECONDS=0.05

# Perform an atomic registry update via flock (Linux/GNU systems).
#
# Args:
#   $1 — jq filter string
#   $@ — remaining args passed to jq
#
# Returns:
#   0 on success; 1 on jq or write failure.
_core_registry_update_with_flock() {
    local jq_filter="$1"; shift
    local lock="$CKIPPER_DIR/.registry.lock"
    local rc=1
    : > "$lock"
    {
        flock -x 9
        local registry_tmpfile; registry_tmpfile=$(mktemp "$CKIPPER_DIR/.registry.tmp.XXXXXX")
        if jq "$@" "$jq_filter" "$CKIPPER_REGISTRY" > "$registry_tmpfile" 2>/dev/null; then
            mv "$registry_tmpfile" "$CKIPPER_REGISTRY"
            chmod "$REGISTRY_FILE_PERMS" "$CKIPPER_REGISTRY"
            rc=0
        else
            rm -f "$registry_tmpfile"
        fi
    } 9>"$lock"
    return $rc
}

# Recover a stale mkdir-based lock directory and reset the attempt counter.
# Prints a warning to stderr, tries rmdir first, then falls back to rm -rf with warning.
#
# Args:
#   $1 — lockdir path
#   $2 — age in seconds (for the message)
#
# Returns:
#   0 after recovery attempt.
#
# Errors (stderr):
#   "Cleaning up old lock..." — always printed when called.
#   "Warning: rmdir failed..." — when rmdir fails and rm -rf fallback is used.
_core_registry_recover_stale_lock() {
    local lockdir="$1" lock_age_seconds="$2"
    echo "Cleaning up old lock from a previous session (age ${lock_age_seconds}s)..." >&2
    if ! rmdir "$lockdir" 2>/dev/null; then
        echo "Warning: rmdir failed on lock dir (unexpected contents); using rm -rf as fallback." >&2
        rm -rf "$lockdir"
    fi
}

# Check if the mkdir lock is stale and recover if so.
#
# Args:
#   $1 — lockdir path
#   $2 — current attempts count
#
# Returns:
#   0 if stale lock was recovered (caller should reset attempts);
#   1 if not stale or lock age could not be determined;
#   2 if the lock is live but held too long (caller should abort).
_core_registry_check_stale_lock() {
    local lockdir="$1" attempts="$2"
    (( attempts < LOCK_MAX_ATTEMPTS )) && return 1
    local current_time_epoch modification_time_epoch lock_age_seconds
    current_time_epoch=$(date +%s)
    modification_time_epoch=$(_core_stat_mtime "$lockdir")
    lock_age_seconds=$(( current_time_epoch - ${modification_time_epoch:-$current_time_epoch} ))
    if (( lock_age_seconds > STALE_LOCK_AGE_THRESHOLD_SECONDS )); then
        _core_registry_recover_stale_lock "$lockdir" "$lock_age_seconds"
        return 0
    fi
    echo "Registry lock held by another process for ${lock_age_seconds}s. Try again shortly." >&2
    return 2
}

# Wait for the mkdir lock to become available, with stale-lock recovery.
# Sets up the EXIT trap to release the lock on success.
#
# Args:
#   $1 — lockdir path
#
# Returns:
#   0 when lock is acquired; 1 on timeout.
_core_registry_acquire_mkdir_lock() {
    local lockdir="$1"
    local attempts=0 has_notified="false"
    while ! mkdir "$lockdir" 2>/dev/null; do
        (( attempts++ ))
        if (( attempts == LOCK_NOTIFY_THRESHOLD_ATTEMPTS )) && [[ "$has_notified" = "false" ]]; then
            echo "Waiting on registry lock..." >&2
            has_notified="true"
        fi
        local stale_rc
        _core_registry_check_stale_lock "$lockdir" "$attempts"; stale_rc=$?
        if (( stale_rc == 0 )); then
            attempts=0
            continue
        fi
        (( stale_rc == 2 )) && return 1
        sleep "$LOCK_RETRY_INTERVAL_SECONDS"
    done
    trap 'rmdir "$lockdir" 2>/dev/null' EXIT
}

# Perform an atomic registry update via mkdir lock (macOS fallback — no flock).
#
# Args:
#   $1 — jq filter string
#   $@ — remaining args passed to jq
#
# Returns:
#   0 on success; 1 on lock timeout or jq/write failure.
_core_registry_update_mkdir_fallback() {
    local jq_filter="$1"; shift
    setopt local_options local_traps
    local lockdir="$CKIPPER_DIR/.registry.lock.d"
    _core_registry_acquire_mkdir_lock "$lockdir" || return 1
    local registry_tmpfile; registry_tmpfile=$(mktemp "$CKIPPER_DIR/.registry.tmp.XXXXXX")
    if jq "$@" "$jq_filter" "$CKIPPER_REGISTRY" > "$registry_tmpfile" 2>/dev/null; then
        mv "$registry_tmpfile" "$CKIPPER_REGISTRY"
        chmod "$REGISTRY_FILE_PERMS" "$CKIPPER_REGISTRY"
        return 0
    fi
    rm -f "$registry_tmpfile"
    return 1
}

# Atomic registry write under flock (or mkdir-fallback for macOS).
#
# Args:
#   $1 — jq filter string; jq error() calls propagate as non-zero exit.
#   $@ — remaining args passed through to jq (e.g. --arg n "$name")
#
# Returns:
#   0 on successful jq+write; 1 on jq error or write failure.
_core_registry_update() {
    mkdir -p "$CKIPPER_DIR"
    if command -v flock >/dev/null 2>&1; then
        _core_registry_update_with_flock "$@"
    else
        _core_registry_update_mkdir_fallback "$@"
    fi
}

# Initialize an empty registry with version field. Idempotent under concurrency
# via atomic create (mv -n) — two concurrent ckipper init's won't clobber each other.
#
# Returns:
#   0 always.
#
# Errors (stderr):
#   "Error: CKIPPER_REGISTRY_VERSION is not a positive integer" — when version var is invalid.
_core_registry_init() {
    [[ -f "$CKIPPER_REGISTRY" ]] && return 0
    if [[ ! "$CKIPPER_REGISTRY_VERSION" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: CKIPPER_REGISTRY_VERSION is not a positive integer: '$CKIPPER_REGISTRY_VERSION'" >&2
        return 1
    fi
    mkdir -p "$CKIPPER_DIR"
    local registry_tmpfile; registry_tmpfile=$(mktemp "$CKIPPER_DIR/.registry.init.XXXXXX")
    jq -n --argjson v "$CKIPPER_REGISTRY_VERSION" \
        '{"version": $v, "default": null, "accounts": {}}' > "$registry_tmpfile"
    # mv -n (no-clobber): if another writer beat us, leave their file alone.
    mv -n "$registry_tmpfile" "$CKIPPER_REGISTRY" 2>/dev/null || rm -f "$registry_tmpfile"
    [[ -f "$CKIPPER_REGISTRY" ]] && chmod "$REGISTRY_FILE_PERMS" "$CKIPPER_REGISTRY"
}

# Refuse to operate on a registry whose version we don't understand OR whose schema
# is corrupt (e.g. user manually edited and turned .accounts into an array).
#
# Returns:
#   0 if registry is absent or valid; 1 on version mismatch or corrupt schema.
#
# Errors (stderr):
#   "Error: registry version..." — on version mismatch.
#   "Error: ... is corrupt..." — on bad schema.
_core_registry_check_version() {
    [[ ! -f "$CKIPPER_REGISTRY" ]] && return 0
    local v
    v=$(jq -r '.version // 0' "$CKIPPER_REGISTRY" 2>/dev/null)
    if (( v != CKIPPER_REGISTRY_VERSION )); then
        echo "Error: registry version $v not supported (this ckipper expects $CKIPPER_REGISTRY_VERSION). Update ckipper or restore from backup." >&2
        return 1
    fi
    if ! jq -e '.accounts | type == "object"' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
        echo "Error: $CKIPPER_REGISTRY is corrupt (.accounts is not an object)." >&2
        echo "Backup and re-init manually:" >&2
        echo "  mv $CKIPPER_REGISTRY $CKIPPER_REGISTRY.corrupt-\$(date +%s)" >&2
        return 1
    fi
}

# Validate that an account exists in the registry. Echoes its config_dir on success.
#
# Args:
#   $1 — account name
#
# Returns:
#   0 with config_dir on stdout; 1 if account not found.
#
# Errors (stderr):
#   "Account '...' is not registered." — when account absent.
_core_account_dir() {
    local name="$1"
    if ! jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
        echo "Account '$name' is not registered." >&2
        return 1
    fi
    jq -r --arg n "$name" '.accounts[$n].config_dir' "$CKIPPER_REGISTRY"
}

# Read the entire registry JSON to stdout. Used by both ckipper subcommands
# and (later) by lib/w/ to satisfy the no-sibling-cross-imports rule.
#
# Returns:
#   0 on success; non-zero if registry file is missing.
_core_registry_read() {
    cat "$CKIPPER_REGISTRY"
}
