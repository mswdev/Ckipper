#!/usr/bin/env zsh
# Shared registry read/write primitives for managing the ckipper accounts registry.

readonly _CORE_REGISTRY_FILE_PERMS=600
readonly _CORE_REGISTRY_LOCK_NOTIFY_THRESHOLD_ATTEMPTS=30
readonly _CORE_REGISTRY_LOCK_MAX_ATTEMPTS=200
readonly _CORE_REGISTRY_STALE_LOCK_AGE_THRESHOLD_SECONDS=30
readonly _CORE_REGISTRY_LOCK_RETRY_INTERVAL_SECONDS=0.05

# Perform an atomic registry update via flock (Linux/GNU systems).
#
# Args:
#   $1 — registry file path (lock + tmpfile derive from this).
#   $2 — jq filter string
#   $@ — remaining args passed to jq
#
# Returns:
#   0 on success; 1 on jq or write failure.
_core_registry_update_with_flock() {
    local registry_file="$1"; shift
    local jq_filter="$1"; shift
    local lock="${registry_file}.lock"
    local rc=1
    : > "$lock"
    {
        flock -x 9
        local registry_tmpfile; registry_tmpfile=$(mktemp "${registry_file:h}/.registry.tmp.XXXXXX")
        if jq "$@" "$jq_filter" "$registry_file" > "$registry_tmpfile" 2>/dev/null; then
            mv "$registry_tmpfile" "$registry_file"
            chmod "$_CORE_REGISTRY_FILE_PERMS" "$registry_file"
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
    (( attempts < _CORE_REGISTRY_LOCK_MAX_ATTEMPTS )) && return 1
    local current_time_epoch modification_time_epoch lock_age_seconds
    current_time_epoch=$(date +%s)
    modification_time_epoch=$(_core_stat_mtime "$lockdir")
    lock_age_seconds=$(( current_time_epoch - ${modification_time_epoch:-$current_time_epoch} ))
    if (( lock_age_seconds > _CORE_REGISTRY_STALE_LOCK_AGE_THRESHOLD_SECONDS )); then
        _core_registry_recover_stale_lock "$lockdir" "$lock_age_seconds"
        return 0
    fi
    echo "Registry lock held by another process for ${lock_age_seconds}s. Try again shortly." >&2
    return 2
}

# Wait for the mkdir lock to become available, with stale-lock recovery.
# The caller is responsible for releasing the lock — DO NOT install an EXIT
# trap here. In zsh, an EXIT trap set inside a function fires when *that*
# function returns, which would remove the lockdir before the caller's
# critical section runs. The trap belongs in the caller (the function whose
# lifetime spans the critical section).
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
        if (( attempts == _CORE_REGISTRY_LOCK_NOTIFY_THRESHOLD_ATTEMPTS )) && [[ "$has_notified" = "false" ]]; then
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
        sleep "$_CORE_REGISTRY_LOCK_RETRY_INTERVAL_SECONDS"
    done
}

# Perform an atomic registry update via mkdir lock (macOS fallback — no flock).
#
# Args:
#   $1 — registry file path (lock + tmpfile derive from this).
#   $2 — jq filter string
#   $@ — remaining args passed to jq
#
# Returns:
#   0 on success; 1 on lock timeout or jq/write failure.
_core_registry_update_mkdir_fallback() {
    local registry_file="$1"; shift
    local jq_filter="$1"; shift
    setopt local_options local_traps
    local lockdir="${registry_file}.lock.d"
    _core_registry_acquire_mkdir_lock "$lockdir" || return 1
    # Trap lives in this function (not in acquire) so it fires when the
    # critical section is done — not when acquire returns mid-critical-section.
    # Use double-quoted trap text so $lockdir is expanded NOW (at trap-set time);
    # by the time the trap actually fires (after this function returns), our
    # local $lockdir is out of scope, so a deferred-expansion form (single quotes)
    # would expand to the empty string and rmdir would silently no-op.
    trap "rmdir '$lockdir' 2>/dev/null" EXIT
    local registry_tmpfile; registry_tmpfile=$(mktemp "${registry_file:h}/.registry.tmp.XXXXXX")
    if jq "$@" "$jq_filter" "$registry_file" > "$registry_tmpfile" 2>/dev/null; then
        mv "$registry_tmpfile" "$registry_file"
        chmod "$_CORE_REGISTRY_FILE_PERMS" "$registry_file"
        return 0
    fi
    rm -f "$registry_tmpfile"
    return 1
}

# Atomic registry write under flock (or mkdir-fallback for macOS) on the
# default registry ($CKIPPER_REGISTRY). See _core_registry_update_at for the
# parametrized form.
#
# Args:
#   $1 — jq filter string; jq error() calls propagate as non-zero exit.
#   $@ — remaining args passed through to jq (e.g. --arg n "$name")
#
# Returns:
#   0 on successful jq+write; 1 on jq error or write failure.
_core_registry_update() {
    _core_registry_update_at "$CKIPPER_REGISTRY" "$@"
}

# Atomic registry write on an arbitrary registry file. Lock paths and
# tmpfiles derive from the file path so multiple registries (accounts.json,
# desktop.json) do not contend on a shared lock.
#
# Args:
#   $1 — registry file path.
#   $2 — jq filter string; jq error() calls propagate as non-zero exit.
#   $@ — remaining args passed through to jq (e.g. --arg n "$name")
#
# Returns:
#   0 on successful jq+write; 1 on jq error or write failure.
_core_registry_update_at() {
    local registry_file="$1"; shift
    mkdir -p "${registry_file:h}"
    if command -v flock >/dev/null 2>&1; then
        _core_registry_update_with_flock "$registry_file" "$@"
    else
        _core_registry_update_mkdir_fallback "$registry_file" "$@"
    fi
}

# Initialize an empty default registry ($CKIPPER_REGISTRY) with version field.
# See _core_registry_init_at for the parametrized form.
#
# Returns:
#   0 always.
#
# Errors (stderr):
#   "Error: CKIPPER_REGISTRY_VERSION is not a positive integer" — when version var is invalid.
_core_registry_init() {
    _core_registry_init_at "$CKIPPER_REGISTRY"
}

# Initialize an empty registry file with version field. Idempotent under
# concurrency via atomic create (mv -n) — two concurrent ckipper init's won't
# clobber each other.
#
# Args:
#   $1 — registry file path.
#
# Returns:
#   0 always (or 1 on invalid version env var).
#
# Errors (stderr):
#   "Error: CKIPPER_REGISTRY_VERSION is not a positive integer" — when version var is invalid.
_core_registry_init_at() {
    local registry_file="$1"
    [[ -f "$registry_file" ]] && return 0
    if [[ ! "$CKIPPER_REGISTRY_VERSION" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: CKIPPER_REGISTRY_VERSION is not a positive integer: '$CKIPPER_REGISTRY_VERSION'" >&2
        return 1
    fi
    mkdir -p "${registry_file:h}"
    local registry_tmpfile; registry_tmpfile=$(mktemp "${registry_file:h}/.registry.init.XXXXXX")
    jq -n --argjson v "$CKIPPER_REGISTRY_VERSION" \
        '{"version": $v, "default": null, "accounts": {}}' > "$registry_tmpfile"
    # mv -n (no-clobber): if another writer beat us, leave their file alone.
    mv -n "$registry_tmpfile" "$registry_file" 2>/dev/null || rm -f "$registry_tmpfile"
    [[ -f "$registry_file" ]] && chmod "$_CORE_REGISTRY_FILE_PERMS" "$registry_file"
}

# Build a JSON object of every account-scope schema key with its default
# value, suitable for embedding in a jq filter via `--argjson p "$(...)"`.
# Used by both the v1→v2 migration and the account-add finalize step so the
# two callers cannot drift from the schema.
#
# Reads: _CKIPPER_SCHEMA_TYPE, _CKIPPER_SCHEMA_DEFAULT, _CKIPPER_SCHEMA_SCOPE
#   (lib/core/schema.zsh — must be sourced before this is called).
#
# Limitations: only handles bool, int, string, and path types. The current
# schema has no account-scope `int_array` keys; if one is added, extend the
# case below to render the comma-separated default as a JSON array.
#
# Returns: 0; emits a valid JSON object string to stdout (e.g.
#   `{"always_docker":false,"always_firewall":false,"ssh_forward":true}`).
_core_registry_account_defaults_json() {
    local key entries=""
    for key in "${(@ko)_CKIPPER_SCHEMA_TYPE}"; do
        [[ "${_CKIPPER_SCHEMA_SCOPE[$key]}" == "account" ]] || continue
        local val="${_CKIPPER_SCHEMA_DEFAULT[$key]}"
        local type="${_CKIPPER_SCHEMA_TYPE[$key]}"
        case "$type" in
            bool | int) entries+="\"$key\":$val," ;;
            *) entries+="\"$key\":\"$val\"," ;;
        esac
    done
    echo "{${entries%,}}"
}

# Auto-migrate the default v1 registry ($CKIPPER_REGISTRY) to v2 in place.
# See _core_registry_migrate_v1_to_v2_at for the parametrized form.
#
# Returns:
#   0 on successful migration; 1 if backup write or jq update failed.
#
# Errors (stderr):
#   "Error: failed to write migration backup..." — when cp to the .v1.bak path fails.
_core_registry_migrate_v1_to_v2() {
    _core_registry_migrate_v1_to_v2_at "$CKIPPER_REGISTRY"
}

# Auto-migrate a v1 registry file to v2 in place. Backs up the v1 file
# (refuses to migrate without a backup), then rewrites it with .version=2 and
# a per-account .preferences block. Existing preferences win over defaults so
# partial-v2 fixtures keep their values.
#
# Args:
#   $1 — registry file path.
#
# Returns:
#   0 on successful migration; 1 if backup write or jq update failed.
#
# Errors (stderr):
#   "Error: failed to write migration backup..." — when cp to the .v1.bak path fails.
_core_registry_migrate_v1_to_v2_at() {
    local registry_file="$1"
    local backup="${registry_file}.v1.bak.$(date -u +%Y%m%dT%H%M%SZ)"
    if ! cp "$registry_file" "$backup" 2>/dev/null; then
        echo "Error: failed to write migration backup $backup" >&2
        return 1
    fi
    local defaults
    defaults=$(_core_registry_account_defaults_json)
    _core_registry_update_at "$registry_file" '
        .version = 2
        | .accounts = (
            .accounts | with_entries(
                .value.preferences = ($defaults + (.value.preferences // {}))
            )
        )
    ' --argjson defaults "$defaults"
}

# Refuse to operate on the default registry ($CKIPPER_REGISTRY) when its
# version is unsupported or its schema is corrupt. Wraps the parametrized
# version check with the accounts.json-specific schema assertion (.accounts
# must be a JSON object). See _core_registry_check_version_at for a
# version-only check that does not enforce the accounts schema (used for
# alternate registries with different shapes).
#
# Returns:
#   0 if registry is absent or valid; 1 on version mismatch, migration failure,
#   or corrupt schema.
#
# Errors (stderr):
#   "Migrating <basename> v1 → v2..." — informational notice during auto-migration.
#   "Error: registry version..." — on version mismatch.
#   "Error: ... is corrupt..." — on bad schema.
_core_registry_check_version() {
    _core_registry_check_version_at "$CKIPPER_REGISTRY" || return 1
    [[ ! -f "$CKIPPER_REGISTRY" ]] && return 0
    _core_registry_assert_accounts_object || return 1
}

# Refuse to operate on a registry file whose version we don't understand.
# Auto-migrates a v1 registry to v2 (with backup) before checking the version.
# Does NOT enforce the accounts.json-specific schema shape — alternate
# registries (e.g. desktop.json) have different top-level keys. The default
# registry wrapper _core_registry_check_version layers that assertion on top.
#
# Args:
#   $1 — registry file path.
#
# Returns:
#   0 if registry is absent or valid; 1 on version mismatch or migration failure.
#
# Errors (stderr):
#   "Migrating <basename> v1 → v2..." — informational notice during auto-migration.
#   "Error: registry version..." — on version mismatch.
_core_registry_check_version_at() {
    local registry_file="$1"
    [[ ! -f "$registry_file" ]] && return 0
    local cur
    cur=$(jq -r '.version // 0' "$registry_file" 2>/dev/null)
    if [[ "$cur" == "1" ]] && (( CKIPPER_REGISTRY_VERSION >= 2 )); then
        echo "Migrating ${registry_file:t} v1 → v2..." >&2
        _core_registry_migrate_v1_to_v2_at "$registry_file" || return 1
    fi
    local v
    v=$(jq -r '.version // 0' "$registry_file" 2>/dev/null)
    if (( v != CKIPPER_REGISTRY_VERSION )); then
        echo "Error: registry version $v not supported (this ckipper expects $CKIPPER_REGISTRY_VERSION). Update ckipper or restore from backup." >&2
        return 1
    fi
    return 0
}

# Verify that .accounts in the default registry ($CKIPPER_REGISTRY) is a
# JSON object (not an array or other type). Surface a clear error with
# manual-recovery instructions when it isn't. This is accounts.json-specific
# and intentionally not parametrized.
#
# Returns:
#   0 if the schema looks valid; 1 if .accounts is corrupt.
#
# Errors (stderr):
#   "Error: ... is corrupt..." — when .accounts is not an object.
_core_registry_assert_accounts_object() {
    if jq -e '.accounts | type == "object"' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
        return 0
    fi
    echo "Error: $CKIPPER_REGISTRY is corrupt (.accounts is not an object)." >&2
    echo "Backup and re-init manually:" >&2
    echo "  mv $CKIPPER_REGISTRY $CKIPPER_REGISTRY.corrupt-\$(date +%s)" >&2
    return 1
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
