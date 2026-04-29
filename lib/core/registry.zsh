#!/usr/bin/env zsh
# Shared registry read/write primitives for managing the ckipper accounts registry.

# Atomic registry write under flock (or mkdir-fallback). $1 = jq filter.
# Returns 0 on successful jq+write, 1 on jq error or write failure.
# A jq error() call inside the filter (used for atomic-collision-checks like
# _ckipper_finalize_registration) propagates as a non-zero exit here.
_core_registry_update() {
    local jq_filter="$1"; shift
    local lock="$CKIPPER_DIR/.registry.lock"
    mkdir -p "$CKIPPER_DIR"
    : > "$lock"
    local rc=1
    if command -v flock >/dev/null 2>&1; then
        {
            flock -x 9
            local tmp; tmp=$(mktemp "$CKIPPER_DIR/.registry.tmp.XXXXXX")
            if jq "$@" "$jq_filter" "$CKIPPER_REGISTRY" > "$tmp" 2>/dev/null; then
                mv "$tmp" "$CKIPPER_REGISTRY"
                chmod 600 "$CKIPPER_REGISTRY"
                rc=0
            else
                rm -f "$tmp"
            fi
        } 9>"$lock"
    else
        # Fallback for systems without flock (the default on macOS): mkdir-based lock,
        # with stale-lock recovery so a SIGKILL'd ckipper doesn't permanently brick
        # subsequent invocations.
        setopt local_options local_traps
        local lockdir="$CKIPPER_DIR/.registry.lock.d"
        local attempts=0
        local notified=0
        while ! mkdir "$lockdir" 2>/dev/null; do
            (( attempts++ ))
            # Reassure the user something is happening — silent multi-second
            # pauses look like a freeze. Print once at ~1.5s in, then again
            # only if we recover a stale lock below.
            if (( attempts == 30 && notified == 0 )); then
                echo "Waiting on registry lock..." >&2
                notified=1
            fi
            if (( attempts >= 200 )); then  # 10s
                local lockdir_age now
                now=$(date +%s)
                local mtime; mtime=$(_core_stat_mtime "$lockdir")
                lockdir_age=$(( now - ${mtime:-$now} ))
                if (( lockdir_age > 30 )); then
                    echo "Cleaning up old lock from a previous session (age ${lockdir_age}s)..." >&2
                    rmdir "$lockdir" 2>/dev/null || rm -rf "$lockdir"
                    attempts=0
                    continue
                fi
                echo "Registry lock held by another process for ${lockdir_age}s. Try again shortly." >&2
                return 1
            fi
            sleep 0.05
        done
        trap 'rmdir "$lockdir" 2>/dev/null' EXIT
        local tmp; tmp=$(mktemp "$CKIPPER_DIR/.registry.tmp.XXXXXX")
        if jq "$@" "$jq_filter" "$CKIPPER_REGISTRY" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$CKIPPER_REGISTRY"
            chmod 600 "$CKIPPER_REGISTRY"
            rc=0
        else
            rm -f "$tmp"
        fi
    fi
    return $rc
}

# Initialize an empty registry with version field. Idempotent under concurrency
# via atomic create (mv -n) — two concurrent ckipper init's won't clobber each other.
_core_registry_init() {
    if [[ ! -f "$CKIPPER_REGISTRY" ]]; then
        mkdir -p "$CKIPPER_DIR"
        local tmp; tmp=$(mktemp "$CKIPPER_DIR/.registry.init.XXXXXX")
        cat > "$tmp" <<EOF
{"version": $CKIPPER_REGISTRY_VERSION, "default": null, "accounts": {}}
EOF
        # mv -n (no-clobber): if another writer beat us, leave their file alone.
        mv -n "$tmp" "$CKIPPER_REGISTRY" 2>/dev/null || rm -f "$tmp"
        [[ -f "$CKIPPER_REGISTRY" ]] && chmod 600 "$CKIPPER_REGISTRY"
    fi
}

# Refuse to operate on a registry whose version we don't understand OR whose schema
# is corrupt (e.g. user manually edited and turned .accounts into an array).
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

# Validates that an account exists in the registry. Echoes its config_dir on success.
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
# Returns: 0 on success; non-zero if registry file is missing.
_core_registry_read() {
    cat "$CKIPPER_REGISTRY"
}
