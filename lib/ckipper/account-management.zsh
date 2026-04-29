#!/usr/bin/env zsh
# Account lifecycle subcommands: add, finalize_registration, remove, rename, list, default, bare_alias_safe.

_ckipper_add() {
    _core_registry_check_version || return 1
    local name="$1" adopt=0
    [[ "$2" == "--adopt" ]] && adopt=1
    if [[ -z "$name" ]]; then
        echo "Usage: ckipper add <name> [--adopt]"
        return 1
    fi
    if [[ ! "$name" =~ ^[a-z0-9_-]+$ ]]; then
        echo "Account name must match ^[a-z0-9_-]+$ (lowercase alphanumeric, underscore, hyphen)."
        return 1
    fi

    _core_registry_init

    if jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null; then
        echo "Account '$name' is already registered."
        return 1
    fi

    local dir="$HOME/.claude-$name"

    if [[ $adopt -eq 1 ]]; then
        if [[ ! -d "$dir" ]]; then
            echo "Cannot adopt: $dir does not exist."
            return 1
        fi
        # In adopt mode, list candidate Keychain entries and let the user pick (or skip).
        local picked=""
        if [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" == darwin* ]]; then
            local candidates
            candidates=$(_core_keychain_snapshot) || return 1
            if [[ -n "$candidates" ]]; then
                echo "Candidate Keychain entries:"
                echo "$candidates" | nl
                read -r "?Pick a number (or empty to skip): " idx
                if [[ -n "$idx" ]]; then
                    picked=$(echo "$candidates" | sed -n "${idx}p")
                    if [[ -n "$picked" ]] && ! _core_keychain_validate "$picked"; then
                        echo "Invalid Keychain service shape: $picked"
                        return 1
                    fi
                fi
            fi
        fi
        _ckipper_finalize_registration "$name" "$dir" "$picked" "adopt"
        return $?
    fi

    # Fresh registration: ckipper LAUNCHES claude itself (in-place, same TTY) so
    # there's no shell-deadlock UX where the user has to Ctrl-Z, run a command,
    # then `fg`. User just /login's and exits Claude (Ctrl-D); ckipper resumes
    # and finalizes registration.
    if [[ -d "$dir" ]]; then
        echo "Directory $dir already exists. Use --adopt to register it."
        return 1
    fi
    mkdir -p "$dir/hooks"
    if [[ -f "$CKIPPER_DIR/settings-template.json" ]]; then
        cp "$CKIPPER_DIR/settings-template.json" "$dir/settings.json"
    fi
    # Deploy hook scripts and rewrite settings.json paths to the per-account
    # dir BEFORE launching claude. The template ships with $HOME/.claude/hooks
    # paths; without this rewrite, the /login session inside claude fires hook
    # errors ("No such file or directory") for paths that don't exist yet.
    _ckipper_sync_hooks_for "$name" "$dir"

    local before_snapshot
    before_snapshot=$(_core_keychain_snapshot) || return 1

    cat <<EOF

A new account directory was created at $dir.

About to launch Claude with this account context. Steps:
  1. Complete the /login flow with the account you want to register as '$name'.
  2. When done, exit Claude with /quit (or Ctrl-D at the prompt).
  3. ckipper will resume here and finalize registration.

Press enter to launch Claude (or type 'skip' to abort and clean up):
EOF
    read -r ack
    if [[ "$ack" == "skip" ]]; then
        rm -rf "$dir"
        echo "Aborted. Cleaned up $dir."
        return 1
    fi

    # Launch claude in-place. The user interacts with it directly in this TTY.
    # Use `command claude` to bypass the bare-claude guard from aliases.zsh.
    CLAUDE_CONFIG_DIR="$dir" command claude
    local rc=$?
    echo ""
    echo "Claude exited (status $rc). Finalizing registration..."

    local after_snapshot
    after_snapshot=$(_core_keychain_snapshot) || return 1

    # Diff using printf (not echo) for comm-friendly input
    local new_service
    new_service=$(comm -13 \
        <(printf '%s\n' "$before_snapshot") \
        <(printf '%s\n' "$after_snapshot") | head -1)

    if [[ -n "$new_service" ]]; then
        if ! _core_keychain_validate "$new_service"; then
            echo "Detected entry has unexpected shape: $new_service"
            echo "Refusing to register. Use --adopt to register manually."
            return 1
        fi
        echo "Detected new Keychain entry: $new_service"
    else
        # No new entry. Could be: (a) login failed, (b) API-key auth (creds on disk), (c) keychain misread.
        if [[ -f "$dir/.credentials.json" ]]; then
            echo "No new Keychain entry, but $dir/.credentials.json exists — proceeding with on-disk credentials."
        else
            echo "Warning: no new Keychain entry detected and no .credentials.json on disk."
            echo "Login may not have completed. Re-run /login or use: ckipper add $name --adopt"
            return 1
        fi
    fi

    _ckipper_finalize_registration "$name" "$dir" "$new_service" "fresh"
}

_ckipper_finalize_registration() {
    local name="$1" dir="$2" service="$3" mode="$4"
    local now; now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    _core_registry_init

    # Atomic insert under lock: jq errors out if the name OR the config_dir is already
    # claimed. Replaces the prior pattern of "pre-check + unguarded write" which had
    # a TOCTOU under concurrent ckipper add invocations.
    if ! _core_registry_update '
        if (.accounts | has($n)) then
            error("ALREADY_REGISTERED")
        elif ([.accounts[].config_dir] | any(. == $d)) then
            error("CONFIG_DIR_IN_USE")
        else
            .accounts[$n] = {config_dir: $d, keychain_service: (if $s == "" then null else $s end), registered_at: $t}
            | (if .default == null then .default = $n else . end)
        end
    ' --arg n "$name" --arg d "$dir" --arg s "$service" --arg t "$now"; then
        # The most likely causes are (a) registry write failure (perms/disk),
        # (b) jq error from one of the assertions above. Distinguish best-effort
        # by re-checking state.
        if jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
            echo "Error: account '$name' already exists in registry (race detected)." >&2
        elif jq -e --arg d "$dir" '[.accounts[].config_dir] | any(. == $d)' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
            echo "Error: config dir '$dir' is already claimed by another registered account." >&2
        else
            echo "Error: failed to write account '$name' to registry $CKIPPER_REGISTRY" >&2
        fi
        return 1
    fi

    _ckipper_regenerate_aliases
    _ckipper_sync_hooks_for "$name"

    echo "Registered '$name' (mode: $mode)."
    if _ckipper_bare_alias_safe "$name"; then
        echo "Use it via: claude-$name   (or just: $name)"
    else
        echo "Use it via: claude-$name"
    fi
}

# Returns 0 if $1 is safe to use as a bare-alias function name (no clash with
# any existing PATH command, shell builtin, alias, or reserved word). Existing
# shell *functions* are not a clash — we expect to redefine those.
_ckipper_bare_alias_safe() {
    local n="$1"
    (( ${+commands[$n]} || ${+builtins[$n]} || ${+aliases[$n]} )) && return 1
    local what; what=$(whence -w "$n" 2>/dev/null | awk '{print $2}')
    [[ "$what" == "reserved" ]] && return 1
    return 0
}

_ckipper_list() {
    if [[ ! -f "$CKIPPER_REGISTRY" ]]; then
        echo "No accounts registered. Run: ckipper add <name>"
        return 0
    fi
    local default
    default=$(jq -r '.default // ""' "$CKIPPER_REGISTRY")
    echo "Registered accounts:"
    jq -r '.accounts | to_entries[] | "\(.key)\t\(.value.config_dir)"' "$CKIPPER_REGISTRY" | \
        while IFS=$'\t' read -r name dir; do
            local marker="  "
            [[ "$name" == "$default" ]] && marker="* "
            local email=""
            if [[ -f "$dir/.claude.json" ]]; then
                email=$(jq -r '.oauthAccount.emailAddress // ""' "$dir/.claude.json" 2>/dev/null)
            fi
            local exists="(missing)"
            [[ -d "$dir" ]] && exists=""
            echo "$marker$name  $dir  ${email:+($email)} $exists"
        done
    echo ""
    echo "* = default. Run: ckipper default <name>"
    echo ""
    echo "Tip: don't run the same account in two terminals at once — Claude's OAuth refresh"
    echo "is single-use, so the second session gets logged out. Use a different account instead."
}

_ckipper_default() {
    _core_registry_check_version || return 1
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: ckipper default <name>"; return 1; }
    if ! jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null; then
        echo "Account '$name' is not registered."
        return 1
    fi
    _core_registry_update '.default = $n' --arg n "$name"
    echo "Default account is now '$name'."
}

_ckipper_remove() {
    _core_registry_check_version || return 1
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: ckipper remove <name>"; return 1; }
    if ! jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null; then
        echo "Account '$name' is not registered."
        return 1
    fi
    local dir; dir=$(jq -r --arg n "$name" '.accounts[$n].config_dir' "$CKIPPER_REGISTRY")
    local service; service=$(jq -r --arg n "$name" '.accounts[$n].keychain_service // ""' "$CKIPPER_REGISTRY")
    _core_registry_update 'del(.accounts[$n]) | (if .default == $n then .default = null else . end)' --arg n "$name"
    # Drop the now-stale launcher functions from the calling shell (regenerate
    # only redefines what's still in the registry; it can't unset removed entries).
    unset -f "claude-$name" 2>/dev/null
    unset -f "$name" 2>/dev/null
    _ckipper_regenerate_aliases
    echo "Unregistered '$name'."
    echo ""
    echo "The directory and Keychain entry were not deleted. To remove them manually:"
    printf "  rm -rf %q\n" "$dir"
    if [[ -n "$service" ]]; then
        printf "  security delete-generic-password -s %q\n" "$service"
    fi
}

_ckipper_rename() {
    _core_registry_check_version || return 1
    local old="$1" new="$2"
    if [[ -z "$old" || -z "$new" ]]; then
        echo "Usage: ckipper rename <old> <new>"
        return 1
    fi
    if [[ ! "$new" =~ ^[a-z0-9_-]+$ ]]; then
        echo "New name must match ^[a-z0-9_-]+$ (lowercase alphanumeric, underscore, hyphen)."
        return 1
    fi
    if [[ "$old" == "$new" ]]; then
        echo "Old and new name are the same. Nothing to do."
        return 1
    fi
    if ! jq -e --arg n "$old" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
        echo "Account '$old' is not registered."
        return 1
    fi
    if jq -e --arg n "$new" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
        echo "Account '$new' is already registered."
        return 1
    fi

    local old_dir new_dir
    old_dir=$(jq -r --arg n "$old" '.accounts[$n].config_dir' "$CKIPPER_REGISTRY")
    new_dir="$HOME/.claude-$new"
    if [[ -e "$new_dir" ]]; then
        echo "Error: $new_dir already exists. Pick a different name or remove it first."
        return 1
    fi
    if [[ ! -d "$old_dir" ]]; then
        echo "Error: source directory $old_dir does not exist."
        return 1
    fi

    # Refuse if any Claude session is running — they'd be writing to old_dir.
    _core_assert_no_running_claude || return 1

    if ! mv "$old_dir" "$new_dir" 2>/dev/null; then
        echo "Error: failed to rename $old_dir → $new_dir." >&2
        return 1
    fi

    if ! _core_registry_update '
        .accounts[$new] = .accounts[$old] |
        .accounts[$new].config_dir = $newdir |
        del(.accounts[$old]) |
        (if .default == $old then .default = $new else . end)
    ' --arg old "$old" --arg new "$new" --arg newdir "$new_dir"; then
        # Rollback: move dir back.
        mv "$new_dir" "$old_dir" 2>/dev/null
        echo "Error: registry write failed; reverted directory rename." >&2
        return 1
    fi

    # Drop old-name launcher functions from the calling shell.
    unset -f "claude-$old" 2>/dev/null
    unset -f "$old" 2>/dev/null
    _ckipper_regenerate_aliases
    _ckipper_sync_hooks_for "$new"   # rewrite per-account settings.json hook paths to the new dir

    echo "Renamed '$old' → '$new'."
    echo "Directory:    $old_dir → $new_dir"
    if _ckipper_bare_alias_safe "$new"; then
        echo "Use:          claude-$new   (or just: $new)"
    else
        echo "Use:          claude-$new"
    fi
}
