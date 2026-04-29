# Ckipper (pronounced "skipper") — multi-account Claude Code manager
# Sourced by w-function.zsh

CKIPPER_DIR="${CKIPPER_DIR:-$HOME/.ckipper}"
CKIPPER_REGISTRY="$CKIPPER_DIR/accounts.json"
CKIPPER_REGISTRY_VERSION=1

ckipper() {
    local cmd="$1"
    shift 2>/dev/null
    case "$cmd" in
        # --help on any subcommand short-circuits to subcommand help
        add|list|default|remove|rename|sync|sync-hooks|migrate|doctor)
            if [[ "$1" == "--help" || "$1" == "-h" ]]; then
                _ckipper_help_for "$cmd"
                return 0
            fi
            "_ckipper_${cmd//-/_}" "$@"
            ;;
        ""|help|-h|--help) _ckipper_help ;;
        *) echo "Unknown command: $cmd"; _ckipper_help; return 1 ;;
    esac
}

_ckipper_help() {
    cat <<'EOF'
ckipper (pronounced "skipper") — multi-account Claude Code manager

Usage:
  ckipper add <name>          Register a new account (interactive /login)
  ckipper add <name> --adopt  Register an existing populated config dir
  ckipper list                Show registered accounts
  ckipper default <name>      Set the default account
  ckipper remove <name>       Unregister (does not delete the dir)
  ckipper rename <old> <new>  Rename an account (dir + registry + aliases)
  ckipper sync <from> <to>    Copy MCP/settings from one account to another
  ckipper sync-hooks          Copy hooks into all registered accounts
  ckipper migrate             One-time migration from legacy layout
  ckipper doctor              Diagnostic check of registered accounts and tooling

Companion commands (sourced via aliases.zsh):
  claude-<name> [args...]     Auto-generated launcher per registered account
  <name> [args...]            Bare-name shortcut (skipped if it would shadow an
                              existing command, builtin, alias, or reserved word)

Run `ckipper <subcommand> --help` for per-subcommand details.
EOF
}

_ckipper_help_for() {
    case "$1" in
        add)
            cat <<'EOF'
ckipper add <name> [--adopt]

Register a new account. <name> must match ^[a-z0-9_-]+$.

Without --adopt: creates ~/.claude-<name>/ and walks you through /login.
With --adopt:    registers an existing populated ~/.claude-<name>/ directory.
EOF
            ;;
        list)    echo "ckipper list — print registered accounts, default, and last-login email."  ;;
        default) echo "ckipper default <name> — set the default account used when no flag/env is provided." ;;
        remove)  echo "ckipper remove <name> — unregister. Does not delete the dir or Keychain entry." ;;
        rename)
            cat <<'EOF'
ckipper rename <old> <new>

Rename a registered account in place:
  - Renames ~/.claude-<old>/ → ~/.claude-<new>/
  - Updates the registry (key + config_dir)
  - If <old> was the default, makes <new> the default
  - Regenerates aliases.zsh and re-syncs hooks
  - Refuses if any Claude session is running (so the dir isn't held open)

Keychain service name is NOT changed — only the dir + registry mapping.
EOF
            ;;
        sync-hooks) echo "ckipper sync-hooks — copy ~/.ckipper/hooks/* into each account's <dir>/hooks/, rewrite settings.json paths." ;;
        sync)
            cat <<'EOF'
ckipper sync <from> <to> [options]

Copy state from one registered account to another. Useful for sharing MCP
servers, plugin lists, status line, env vars, etc. across accounts without
having to re-configure each.

By default (no flags) syncs a sensible bundle: mcpServers + enabledPlugins +
extraKnownMarketplaces + statusLine + env.

Options:
  --mcp [name1,name2,...]    Sync mcpServers. Without arg: all servers.
                             With arg: only the named servers.
  --settings <key1,key2,...> Sync specific top-level keys from settings.json.
                             Comma-separated. Examples: enabledPlugins,
                             extraKnownMarketplaces, statusLine, env, model.
  --all                      Sync the default bundle (same as no flags).
  --dry-run                  Show what would change without writing.

Examples:
  ckipper sync personal work
  ckipper sync personal work --mcp
  ckipper sync personal work --mcp Vibma,github
  ckipper sync personal work --settings statusLine,env --dry-run
EOF
            ;;
        migrate) echo "ckipper migrate — migrate from legacy ~/.claude/docker/ layout. Idempotent. Refuses if Claude is running." ;;
        doctor) echo "ckipper doctor — run a diagnostic checklist on registered accounts and ckipper tooling." ;;
    esac
}

# Validates a keychain_service name before passing to `security`.
# Accepts "Claude Code-credentials" optionally followed by "-<hex>".
_ckipper_validate_keychain_service() {
    local svc="$1"
    [[ -z "$svc" ]] && return 1
    [[ "$svc" =~ ^Claude\ Code-credentials(-[a-f0-9]+)?$ ]]
}

_ckipper_keychain_snapshot() {
    # macOS only. Returns service names of all "Claude Code-credentials*" entries, sorted.
    [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" != darwin* ]] && return 0

    # Pick a timeout binary if available (macOS doesn't ship one; gtimeout from
    # coreutils is the typical brew install). Fall through to no timeout if neither
    # is present — better than failing with a misleading "keychain locked" error.
    local timeout_cmd=""
    if command -v timeout >/dev/null 2>&1; then
        timeout_cmd="timeout 10"
    elif command -v gtimeout >/dev/null 2>&1; then
        timeout_cmd="gtimeout 10"
    fi

    local out
    if [[ -n "$timeout_cmd" ]]; then
        if ! out=$($timeout_cmd security dump-keychain 2>/dev/null); then
            echo "Warning: Keychain may be locked or slow. Unlock it (Keychain Access > File > Unlock) and retry." >&2
            return 1
        fi
    else
        # No timeout available — run without. If keychain is locked the GUI
        # password prompt will block this, which is a fine failure mode.
        if ! out=$(security dump-keychain 2>/dev/null); then
            echo "Warning: 'security dump-keychain' failed. Keychain may be locked." >&2
            return 1
        fi
    fi

    printf '%s\n' "$out" | \
        awk -F'"' '/"svce"<blob>="Claude Code-credentials/ {print $4}' | \
        sort -u
}

# Cross-platform stat for permissions: BSD (macOS) uses -f, GNU/Linux uses -c.
_ckipper_stat_perms() {
    if [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" == darwin* ]]; then
        stat -f '%Lp' "$1" 2>/dev/null
    else
        stat -c '%a' "$1" 2>/dev/null
    fi
}

# Cross-platform stat for mtime in seconds since epoch.
_ckipper_stat_mtime() {
    if [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" == darwin* ]]; then
        stat -f '%m' "$1" 2>/dev/null
    else
        stat -c '%Y' "$1" 2>/dev/null
    fi
}

# Detect running Claude processes that would conflict with destructive operations.
# Matches: 'claude' CLI (basename), 'Claude' (Claude.app main process). Avoids matching
# vim files named 'claude-*', tmux sessions, or Claude Helper subprocesses (the parent
# Claude.app being killed will cascade to those).
_ckipper_running_claude_processes() {
    pgrep -lx claude 2>/dev/null
    pgrep -lx Claude 2>/dev/null
}

# Refuse with a clear message if any Claude process is running.
_ckipper_assert_no_running_claude() {
    local found
    found=$(_ckipper_running_claude_processes)
    if [[ -n "$found" ]]; then
        echo "Error: Claude process(es) detected. Quit them first:" >&2
        echo "$found" | sed 's/^/  /' >&2
        echo "(Set CKIPPER_FORCE=1 to bypass this check, but expect inconsistent state.)" >&2
        if [[ "$CKIPPER_FORCE" == "1" ]]; then
            echo "CKIPPER_FORCE=1 set — proceeding despite running Claude." >&2
            return 0
        fi
        return 1
    fi
    return 0
}

# Atomic registry write under flock (or mkdir-fallback). $1 = jq filter.
# Returns 0 on successful jq+write, 1 on jq error or write failure.
# A jq error() call inside the filter (used for atomic-collision-checks like
# _ckipper_finalize_registration) propagates as a non-zero exit here.
_ckipper_registry_update() {
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
        while ! mkdir "$lockdir" 2>/dev/null; do
            (( attempts++ ))
            if (( attempts >= 200 )); then  # 10s
                local lockdir_age now
                now=$(date +%s)
                local mtime; mtime=$(_ckipper_stat_mtime "$lockdir")
                lockdir_age=$(( now - ${mtime:-$now} ))
                if (( lockdir_age > 30 )); then
                    echo "Recovering stale registry lock (age ${lockdir_age}s)" >&2
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
_ckipper_init_registry() {
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
_ckipper_check_registry_version() {
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

_ckipper_add() {
    _ckipper_check_registry_version || return 1
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

    _ckipper_init_registry

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
            candidates=$(_ckipper_keychain_snapshot) || return 1
            if [[ -n "$candidates" ]]; then
                echo "Candidate Keychain entries:"
                echo "$candidates" | nl
                read -r "?Pick a number (or empty to skip): " idx
                if [[ -n "$idx" ]]; then
                    picked=$(echo "$candidates" | sed -n "${idx}p")
                    if [[ -n "$picked" ]] && ! _ckipper_validate_keychain_service "$picked"; then
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

    local before_snapshot
    before_snapshot=$(_ckipper_keychain_snapshot) || return 1

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
    after_snapshot=$(_ckipper_keychain_snapshot) || return 1

    # Diff using printf (not echo) for comm-friendly input
    local new_service
    new_service=$(comm -13 \
        <(printf '%s\n' "$before_snapshot") \
        <(printf '%s\n' "$after_snapshot") | head -1)

    if [[ -n "$new_service" ]]; then
        if ! _ckipper_validate_keychain_service "$new_service"; then
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

    _ckipper_init_registry

    # Atomic insert under lock: jq errors out if the name OR the config_dir is already
    # claimed. Replaces the prior pattern of "pre-check + unguarded write" which had
    # a TOCTOU under concurrent ckipper add invocations.
    if ! _ckipper_registry_update '
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

_ckipper_regenerate_aliases() {
    local out="$CKIPPER_DIR/aliases.zsh"
    local _name _dir
    {
        echo "# Auto-generated by ckipper. Do not edit by hand."
        echo "# Self-contained: does not depend on ckipper.zsh or w-function.zsh being sourced."
        echo "# Regenerated whenever an account is added or removed."
        echo ""
        echo "_CKIPPER_REGISTRY=\"\${CKIPPER_DIR:-\$HOME/.ckipper}/accounts.json\""
        echo ""
        # Guard: bare 'claude' would default to ~/.claude/ and write to the unsuffixed
        # 'Claude Code-credentials' Keychain entry — which is the SAME entry the
        # default account uses. A fresh /login here silently overwrites those creds.
        # Block bare 'claude' when accounts are registered; users bypass via 'command claude'.
        echo "claude() {"
        echo "    if [[ -f \"\$_CKIPPER_REGISTRY\" ]] && jq -e '.accounts | length > 0' \"\$_CKIPPER_REGISTRY\" >/dev/null 2>&1; then"
        echo "        local default"
        echo "        default=\$(jq -r '.default // \"\"' \"\$_CKIPPER_REGISTRY\" 2>/dev/null)"
        echo "        echo \"Refusing to launch bare 'claude' — Ckipper has registered accounts.\" >&2"
        echo "        echo \"\" >&2"
        echo "        echo \"Bare 'claude' uses ~/.claude/ and writes to the Keychain entry your\" >&2"
        echo "        echo \"default account ('\${default:-personal}') is registered against. A fresh\" >&2"
        echo "        echo \"/login here would silently overwrite those credentials.\" >&2"
        echo "        echo \"\" >&2"
        echo "        if [[ -n \"\$default\" ]]; then"
        echo "            echo \"Use:  claude-\$default\" >&2"
        echo "        else"
        echo "            echo \"Set a default first: ckipper default <name>, then use claude-<name>.\" >&2"
        echo "        fi"
        echo "        echo \"\" >&2"
        echo "        echo \"To bypass (fresh login on purpose):  command claude \\\$@\" >&2"
        echo "        return 1"
        echo "    fi"
        echo "    command claude \"\$@\""
        echo "}"
        echo ""
        if [[ -f "$CKIPPER_REGISTRY" ]]; then
            jq -r '.accounts | to_entries[] | "\(.key)\t\(.value.config_dir)"' "$CKIPPER_REGISTRY" | \
                while IFS=$'\t' read -r _name _dir; do
                    echo "claude-$_name() { CLAUDE_CONFIG_DIR=\"$_dir\" command claude \"\$@\"; }"
                    # Bare-name shortcut: also generate `<name>` so users can
                    # type the account name directly. Skip if it would shadow
                    # a real binary, builtin, alias, or reserved word.
                    if _ckipper_bare_alias_safe "$_name"; then
                        echo "$_name() { CLAUDE_CONFIG_DIR=\"$_dir\" command claude \"\$@\"; }"
                    else
                        echo "# Bare-name alias '$_name' skipped (would shadow existing command)."
                    fi
                done
        fi
    } > "$out.tmp"
    # Atomic install — readers in other shells never see a partial file.
    mv "$out.tmp" "$out"
    chmod 644 "$out"

    # Re-source in the calling shell so newly-registered accounts are usable
    # immediately without the user having to `exec zsh`. Function definitions
    # from a sourced file are global by default in zsh, so this works even
    # though we're sourcing inside a function.
    source "$out"
}

_ckipper_sync_hooks_for() {
    local name="$1"
    _ckipper_check_registry_version || return 1
    local dir; dir=$(jq -r --arg n "$name" '.accounts[$n].config_dir' "$CKIPPER_REGISTRY")
    [[ -z "$dir" || "$dir" == "null" ]] && return 1
    mkdir -p "$dir/hooks"
    cp -a "$CKIPPER_DIR/hooks/." "$dir/hooks/" 2>/dev/null || true

    # Rewrite settings.json hook paths to absolute paths under this account dir.
    # Consumes the entire prefix (`$HOME/.claude/`, `$HOME/.claude-<name>/`, or `$HOME/.ckipper/`)
    # plus `hooks/` so we don't end up with `$HOME<dir>/hooks/...` after substitution.
    if [[ -f "$dir/settings.json" ]] && command -v jq &>/dev/null; then
        local tmp; tmp=$(mktemp "$dir/.settings.tmp.XXXXXX")
        jq --arg d "$dir" '
            (.hooks // {}) as $h |
            .hooks = ($h | walk(
                if type == "string" and test("\\$HOME/(\\.claude(-[a-z0-9_-]+)?|\\.ckipper)/hooks/")
                then sub("\\$HOME/(\\.claude(-[a-z0-9_-]+)?|\\.ckipper)/hooks/"; "\($d)/hooks/")
                else . end
            ))
        ' "$dir/settings.json" > "$tmp" && mv "$tmp" "$dir/settings.json"
    fi
}

_ckipper_sync_hooks() {
    if [[ ! -f "$CKIPPER_REGISTRY" ]]; then
        echo "No accounts registered."
        return 0
    fi
    _ckipper_check_registry_version || return 1
    local names; names=$(jq -r '.accounts | keys[]' "$CKIPPER_REGISTRY")
    while IFS= read -r name; do
        echo "Syncing hooks → $name"
        _ckipper_sync_hooks_for "$name"
    done <<< "$names"
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
    _ckipper_check_registry_version || return 1
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: ckipper default <name>"; return 1; }
    if ! jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null; then
        echo "Account '$name' is not registered."
        return 1
    fi
    _ckipper_registry_update '.default = $n' --arg n "$name"
    echo "Default account is now '$name'."
}

_ckipper_remove() {
    _ckipper_check_registry_version || return 1
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: ckipper remove <name>"; return 1; }
    if ! jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null; then
        echo "Account '$name' is not registered."
        return 1
    fi
    local dir; dir=$(jq -r --arg n "$name" '.accounts[$n].config_dir' "$CKIPPER_REGISTRY")
    local service; service=$(jq -r --arg n "$name" '.accounts[$n].keychain_service // ""' "$CKIPPER_REGISTRY")
    _ckipper_registry_update 'del(.accounts[$n]) | (if .default == $n then .default = null else . end)' --arg n "$name"
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
    _ckipper_check_registry_version || return 1
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
    _ckipper_assert_no_running_claude || return 1

    if ! mv "$old_dir" "$new_dir" 2>/dev/null; then
        echo "Error: failed to rename $old_dir → $new_dir." >&2
        return 1
    fi

    if ! _ckipper_registry_update '
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

# Validates that an account exists in the registry. Echoes its config_dir on success.
_ckipper_account_dir() {
    local name="$1"
    if ! jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
        echo "Account '$name' is not registered." >&2
        return 1
    fi
    jq -r --arg n "$name" '.accounts[$n].config_dir' "$CKIPPER_REGISTRY"
}

_ckipper_sync() {
    _ckipper_check_registry_version || return 1
    local from="$1" to="$2"
    shift 2 2>/dev/null
    if [[ -z "$from" || -z "$to" ]]; then
        echo "Usage: ckipper sync <from> <to> [--mcp [names]] [--settings keys] [--all] [--dry-run]"
        return 1
    fi
    if [[ "$from" == "$to" ]]; then
        echo "<from> and <to> must differ."
        return 1
    fi

    local from_dir to_dir
    from_dir=$(_ckipper_account_dir "$from") || return 1
    to_dir=$(_ckipper_account_dir "$to") || return 1
    if [[ ! -f "$from_dir/.claude.json" ]]; then
        echo "Source has no .claude.json: $from_dir"; return 1
    fi
    if [[ ! -f "$to_dir/.claude.json" ]]; then
        echo "Destination has no .claude.json: $to_dir"; return 1
    fi

    # Parse flags. The argparse here is intentionally minimal — order matters,
    # but each flag is well-formed and easy to read.
    local mode_mcp=0 mcp_names="" mode_settings=0 settings_keys="" dry_run=0 mode_all=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mcp)
                mode_mcp=1
                if [[ -n "$2" && "$2" != --* ]]; then mcp_names="$2"; shift; fi
                shift ;;
            --settings)
                mode_settings=1
                if [[ -n "$2" && "$2" != --* ]]; then settings_keys="$2"; shift; fi
                shift ;;
            --all)        mode_all=1; shift ;;
            --dry-run)    dry_run=1; shift ;;
            *) echo "Unknown flag: $1"; return 1 ;;
        esac
    done

    # Default bundle when no specific flags were passed: mcpServers + a useful
    # selection of settings.json keys.
    if (( mode_mcp == 0 && mode_settings == 0 )); then
        mode_all=1
    fi
    if (( mode_all )); then
        mode_mcp=1
        mode_settings=1
        [[ -z "$settings_keys" ]] && \
            settings_keys="enabledPlugins,extraKnownMarketplaces,statusLine,env,model"
    fi

    # If a Claude session is running, sync's writes can race with its writes
    # to the same .claude.json. Warn (but don't refuse) unless --dry-run.
    if (( ! dry_run )); then
        local running_procs
        running_procs=$(_ckipper_running_claude_processes)
        if [[ -n "$running_procs" ]]; then
            echo "Warning: Claude is currently running. If a session uses '$to' or '$from'," >&2
            echo "sync may race with its writes (Claude doesn't lock these files)." >&2
            echo "$running_procs" | sed 's/^/  /' >&2
            read -r "?Continue anyway? [y/N] " ans
            [[ "$ans" != "y" && "$ans" != "Y" ]] && { echo "Aborted."; return 1; }
        fi
    fi

    local pending_msgs=()

    # ── MCP sync ─────────────────────────────────────────────────
    if (( mode_mcp )); then
        local mcp_filter
        if [[ -z "$mcp_names" ]]; then
            mcp_filter='.mcpServers // {}'
        else
            # Build a jq object containing only the named servers, e.g. {Vibma: ..., github: ...}
            local jq_array
            jq_array=$(echo "$mcp_names" | jq -R 'split(",") | map(. | gsub("^\\s+|\\s+$"; ""))')
            mcp_filter='.mcpServers // {} | with_entries(select(.key as $k | '"$jq_array"' | index($k)))'
        fi
        local servers
        servers=$(jq "$mcp_filter" "$from_dir/.claude.json")
        local server_keys
        server_keys=$(echo "$servers" | jq -r 'keys[]?' | tr '\n' ' ')
        if [[ -z "$server_keys" || "$server_keys" == " " ]]; then
            pending_msgs+=("MCP: nothing to sync (no matching servers in $from)")
        else
            pending_msgs+=("MCP servers → $to: $server_keys")
            if (( ! dry_run )); then
                local tmp; tmp=$(mktemp "$to_dir/.claude.json.tmp.XXXXXX")
                jq --argjson new "$servers" '.mcpServers = (.mcpServers // {}) + $new' \
                    "$to_dir/.claude.json" > "$tmp" && mv "$tmp" "$to_dir/.claude.json"
            fi
        fi
    fi

    # ── settings.json key sync ───────────────────────────────────
    if (( mode_settings )) && [[ -n "$settings_keys" ]]; then
        if [[ ! -f "$from_dir/settings.json" ]]; then
            pending_msgs+=("Settings: $from has no settings.json (skipping)")
        else
            # Build a jq subset object with only the requested keys (skipping missing ones).
            local jq_keys
            jq_keys=$(echo "$settings_keys" | jq -R 'split(",") | map(. | gsub("^\\s+|\\s+$"; ""))')
            local subset
            subset=$(jq --argjson keys "$jq_keys" \
                'with_entries(select(.key as $k | $keys | index($k)))' \
                "$from_dir/settings.json")
            local copied_keys
            copied_keys=$(echo "$subset" | jq -r 'keys[]?' | tr '\n' ' ')
            if [[ -z "$copied_keys" || "$copied_keys" == " " ]]; then
                pending_msgs+=("Settings: no matching keys in $from/settings.json")
            else
                pending_msgs+=("Settings keys → $to: $copied_keys")
                if (( ! dry_run )); then
                    if [[ ! -f "$to_dir/settings.json" ]]; then
                        echo '{}' > "$to_dir/settings.json"
                    fi
                    local tmp; tmp=$(mktemp "$to_dir/settings.json.tmp.XXXXXX")
                    jq --argjson new "$subset" '. + $new' \
                        "$to_dir/settings.json" > "$tmp" && mv "$tmp" "$to_dir/settings.json"
                fi
            fi
        fi
    fi

    if (( dry_run )); then
        echo "Dry run — would apply:"
    else
        echo "Synced:"
    fi
    for m in "${pending_msgs[@]}"; do
        echo "  - $m"
    done

    if (( ! dry_run )); then
        echo ""
        echo "Restart any running '$to' Claude session for changes to take effect."
    fi
}

_ckipper_doctor() {
    local fail=0 warn=0
    local check() {
        local sym="$1" msg="$2"
        case "$sym" in
            PASS) printf "  \033[32m[PASS]\033[0m %s\n" "$msg" ;;
            WARN) printf "  \033[33m[WARN]\033[0m %s\n" "$msg"; (( warn++ )) ;;
            FAIL) printf "  \033[31m[FAIL]\033[0m %s\n" "$msg"; (( fail++ )) ;;
            INFO) printf "  [INFO] %s\n" "$msg" ;;
        esac
    }
    # Locally-scoped function for color output. zsh function nesting works at runtime.

    echo "── Tooling ───────────────────────────────────────────"
    if [[ -d "$CKIPPER_DIR" ]]; then check PASS "$CKIPPER_DIR exists"; else check FAIL "$CKIPPER_DIR is missing — run install.sh"; fi
    if [[ -f "$CKIPPER_DIR/docker/w-function.zsh" ]]; then check PASS "w-function.zsh deployed"; else check FAIL "w-function.zsh missing in $CKIPPER_DIR/docker/"; fi
    if [[ -f "$CKIPPER_DIR/docker/ckipper.zsh" ]]; then check PASS "ckipper.zsh deployed"; else check FAIL "ckipper.zsh missing in $CKIPPER_DIR/docker/"; fi
    if [[ -f "$CKIPPER_DIR/docker/cleanup-projects.py" ]]; then check PASS "cleanup-projects.py deployed"; else check WARN "cleanup-projects.py missing — w --rm cleanup will silently skip"; fi
    if [[ -f "$CKIPPER_DIR/settings-template.json" ]]; then check PASS "settings-template.json deployed"; else check WARN "settings-template.json missing — ckipper add will skip seeding settings.json"; fi
    if [[ -d "$CKIPPER_DIR/hooks" ]] && (( $(ls -1 "$CKIPPER_DIR/hooks" 2>/dev/null | wc -l) >= 4 )); then
        check PASS "hooks/ has 4+ files"
    else
        check WARN "hooks/ is missing or has fewer than 4 hook files"
    fi

    echo ""
    echo "── Registry ──────────────────────────────────────────"
    if [[ ! -f "$CKIPPER_REGISTRY" ]]; then
        check INFO "No registry yet — no accounts registered. Run: ckipper migrate (or ckipper add <name>)"
        return 0
    fi
    local v; v=$(jq -r '.version // 0' "$CKIPPER_REGISTRY" 2>/dev/null)
    if [[ "$v" == "$CKIPPER_REGISTRY_VERSION" ]]; then check PASS "registry version $v matches expected"
    else check FAIL "registry version $v != expected $CKIPPER_REGISTRY_VERSION"; fi
    local perms; perms=$(_ckipper_stat_perms "$CKIPPER_REGISTRY")
    if [[ "$perms" == "600" ]]; then check PASS "registry permissions 600"
    else check WARN "registry permissions $perms (expected 600)"; fi

    local default_acc; default_acc=$(jq -r '.default // ""' "$CKIPPER_REGISTRY")
    if [[ -z "$default_acc" ]]; then
        check WARN "no default account set — w/ckipper-add will require --account"
    elif jq -e --arg n "$default_acc" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
        check INFO "default account: $default_acc"
    else
        check FAIL "default account '$default_acc' is NOT in registry — fix with: ckipper default <existing-account>"
    fi

    echo ""
    echo "── Per-account state ────────────────────────────────"
    local names; names=$(jq -r '.accounts | keys[]?' "$CKIPPER_REGISTRY")
    if [[ -z "$names" ]]; then
        check WARN "registry has no accounts"
    else
        while IFS= read -r name; do
            echo ""
            echo "  Account: $name"
            local dir; dir=$(jq -r --arg n "$name" '.accounts[$n].config_dir' "$CKIPPER_REGISTRY")
            local svc; svc=$(jq -r --arg n "$name" '.accounts[$n].keychain_service // ""' "$CKIPPER_REGISTRY")
            if [[ -d "$dir" ]]; then check PASS "    dir exists: $dir"
            else check FAIL "    dir missing: $dir"; fi
            if [[ -f "$dir/.claude.json" ]]; then
                local email proj_count mcp_count
                email=$(jq -r '.oauthAccount.emailAddress // "(none)"' "$dir/.claude.json" 2>/dev/null)
                proj_count=$(jq '.projects | length // 0' "$dir/.claude.json" 2>/dev/null)
                mcp_count=$(jq '.mcpServers | length // 0' "$dir/.claude.json" 2>/dev/null)
                check PASS "    .claude.json: oauth=$email, projects=$proj_count, mcps=$mcp_count"
            else
                check WARN "    .claude.json missing in $dir"
            fi
            if [[ -f "$dir/settings.json" ]]; then check PASS "    settings.json present"; else check WARN "    settings.json missing"; fi
            if [[ -d "$dir/hooks" ]]; then check PASS "    hooks/ deployed"; else check WARN "    hooks/ missing — run: ckipper sync-hooks"; fi
            # Keychain check (macOS only)
            if [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" == darwin* ]]; then
                if [[ -z "$svc" ]]; then
                    check INFO "    keychain_service: null (account uses on-disk credentials)"
                elif ! _ckipper_validate_keychain_service "$svc"; then
                    check FAIL "    keychain_service has invalid shape: $svc"
                elif security find-generic-password -s "$svc" >/dev/null 2>&1; then
                    check PASS "    keychain entry present: $svc"
                else
                    check WARN "    keychain entry NOT FOUND: $svc — re-run /login with: claude-$name"
                fi
            fi
        done <<< "$names"
    fi

    echo ""
    echo "── Aliases & shell integration ──────────────────────"
    if [[ -f "$CKIPPER_DIR/aliases.zsh" ]]; then check PASS "aliases.zsh exists at $CKIPPER_DIR/aliases.zsh"
    else check WARN "aliases.zsh missing — will be regenerated on next add/remove"; fi
    if grep -q 'ckipper/aliases.zsh' "$HOME/.zshrc" 2>/dev/null; then check PASS "~/.zshrc sources aliases.zsh"
    else check WARN "~/.zshrc does NOT source aliases.zsh — add: [[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh"; fi
    if grep -q 'ckipper/docker/w-function\.zsh' "$HOME/.zshrc" 2>/dev/null; then check PASS "~/.zshrc sources w-function.zsh"
    else check FAIL "~/.zshrc does NOT source w-function.zsh — re-run install.sh"; fi

    echo ""
    echo "── Stub files (cosmetic) ────────────────────────────"
    if [[ -d "$HOME/.claude" ]]; then
        local stub_count; stub_count=$(ls -1A "$HOME/.claude" 2>/dev/null | wc -l | tr -d ' ')
        check WARN "~/.claude exists ($stub_count files) — Claude Code may have recreated it. Safe to: rm -rf ~/.claude"
    else
        check PASS "~/.claude (stub dir) is absent"
    fi
    if [[ -f "$HOME/.claude.json" ]]; then check WARN "~/.claude.json exists at home root — should have been migrated. If you ran migrate, this is leftover."
    else check PASS "~/.claude.json (home root) is absent"; fi

    echo ""
    echo "──────────────────────────────────────────────────────"
    if (( fail > 0 )); then
        printf "Result: \033[31m%d FAIL\033[0m, \033[33m%d WARN\033[0m\n" "$fail" "$warn"
        return 1
    elif (( warn > 0 )); then
        printf "Result: \033[33m%d WARN\033[0m\n" "$warn"
        return 0
    else
        printf "Result: \033[32mall checks passed\033[0m\n"
        return 0
    fi
}

_ckipper_migrate() {
    _ckipper_check_registry_version || return 1
    local legacy_docker="$HOME/.claude/docker"
    local legacy_claude="$HOME/.claude"

    # ── Precondition 1: no Claude process running ─────────────────
    _ckipper_assert_no_running_claude || return 1

    # ── Precondition 2: ~/.claude must NOT be a symlink ──────────
    # Some users symlink ~/.claude to a synced location. Renaming a symlink
    # moves the link, not the target — confusing and probably not what they want.
    if [[ -L "$legacy_claude" ]]; then
        local target; target=$(readlink "$legacy_claude")
        echo "Error: $legacy_claude is a symlink (→ $target). Refusing to migrate." >&2
        echo "Resolve manually: replace the symlink with the actual directory contents," >&2
        echo "or migrate the target directly." >&2
        return 1
    fi

    # ── Precondition 3: ~/.claude.json must NOT be a symlink ──────
    # Same reasoning — Dropbox/iCloud users symlink this for cross-machine sync.
    # mv on a symlink moves the link itself, breaking the sync target.
    local legacy_homejson_check="$HOME/.claude.json"
    if [[ -L "$legacy_homejson_check" ]]; then
        local target; target=$(readlink "$legacy_homejson_check")
        echo "Error: $legacy_homejson_check is a symlink (→ $target). Refusing to migrate." >&2
        echo "Resolve manually: replace the symlink with the actual file contents," >&2
        echo "or migrate the target directly." >&2
        return 1
    fi

    # ── 1. Move ~/.claude/docker → ~/.ckipper/docker if not done ──
    if [[ -d "$legacy_docker" && ! -d "$CKIPPER_DIR/docker" ]]; then
        mkdir -p "$CKIPPER_DIR"
        cp -a "$legacy_docker/." "$CKIPPER_DIR/docker/"
        echo "Copied $legacy_docker → $CKIPPER_DIR/docker (legacy left intact for one release cycle)"
    fi

    # ── 2. Adopt ~/.claude as a registered account ────────────────
    # Eligible if either ~/.claude/.claude.json or ~/.claude/settings.json exists,
    # OR ~/.claude.json exists at home root (Claude Code's canonical big-config location).
    local legacy_homejson="$HOME/.claude.json"
    local has_inner_state=0 has_homejson=0
    [[ -f "$legacy_claude/.claude.json" || -f "$legacy_claude/settings.json" ]] && has_inner_state=1
    [[ -f "$legacy_homejson" ]] && has_homejson=1

    if (( has_inner_state == 0 && has_homejson == 0 )); then
        local has_registry=0
        [[ -f "$CKIPPER_REGISTRY" ]] && jq -e '.accounts | length > 0' "$CKIPPER_REGISTRY" >/dev/null 2>&1 && has_registry=1
        if (( has_registry )); then
            echo "Nothing to migrate: no $legacy_claude state and no $legacy_homejson at home root."
            echo "($CKIPPER_REGISTRY already has registered accounts — you're likely already migrated.)"
            echo "Run: ckipper list"
        else
            echo "Nothing to migrate: no $legacy_claude/.claude.json, no $legacy_claude/settings.json, no $legacy_homejson."
            echo "If this is a fresh setup, register an account directly: ckipper add <name>"
        fi
        return 0
    fi

    if [[ -f "$legacy_claude/.claude.json" || -f "$legacy_claude/settings.json" || -f "$legacy_homejson" ]]; then
        if [[ ! -f "$CKIPPER_REGISTRY" ]] || \
           ! jq -e '.accounts | length > 0' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then

            # ── Prompt for the account name ──────────────────────
            local default_name="personal"
            local name=""
            while [[ -z "$name" ]]; do
                read -r "?What name do you want for this migrated account? [$default_name] " name
                [[ -z "$name" ]] && name="$default_name"
                if [[ ! "$name" =~ ^[a-z0-9_-]+$ ]]; then
                    echo "Account name must match ^[a-z0-9_-]+$ (lowercase alphanumeric, underscore, hyphen). Try again."
                    name=""
                fi
                if [[ -n "$name" && -e "$HOME/.claude-$name" ]]; then
                    echo "$HOME/.claude-$name already exists. Pick a different name."
                    name=""
                fi
            done
            local target_dir="$HOME/.claude-$name"

            # Show the user what we're about to do.
            cat <<EOF

Detected existing $legacy_claude with login credentials.
EOF
            [[ -f "$legacy_homejson" ]] && \
                echo "Also detected $legacy_homejson (Claude's main config — projects, MCPs, trust state)."

            cat <<EOF

This migration will:
  1. Rename $legacy_claude → $target_dir.
EOF
            [[ -f "$legacy_homejson" ]] && \
                echo "  2. Move $legacy_homejson → $target_dir/.claude.json (preserving any existing inner one as a backup)."
            cat <<EOF
  3. Register '$name' in $CKIPPER_REGISTRY.
  4. Probe macOS Keychain for the matching 'Claude Code-credentials' entry.

NOT a symlink — bare 'claude' will no longer use this account; use 'claude-$name' instead.
If anything fails, the rename is automatically reverted.

EOF
            read -r "?Proceed? [y/N] " ans
            if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
                echo "Aborted."
                return 1
            fi

            # ── Precondition: probe Keychain entry exists ───────
            local probed_service="Claude Code-credentials"
            if [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" == darwin* ]]; then
                if ! security find-generic-password -s "$probed_service" -w >/dev/null 2>&1; then
                    echo "Warning: '$probed_service' not found in Keychain."
                    echo "Listing available Claude Keychain entries:"
                    _ckipper_keychain_snapshot || return 1
                    read -r "?Enter the Keychain service for the '$name' account (or empty to skip): " probed_service
                    if [[ -n "$probed_service" ]] && ! _ckipper_validate_keychain_service "$probed_service"; then
                        echo "Invalid Keychain service shape. Aborting."
                        return 1
                    fi
                fi
            else
                probed_service=""
            fi

            # ── Destructive operation with explicit rollback ─────
            # Tracks every step performed so rollback can undo precisely:
            #   1 = ~/.claude renamed; 2 = ~/.claude.json moved (inner backed up)
            local migrate_step=0
            local moved_homejson_backup=""
            _ckipper_migrate_rollback() {
                local why="${1:-rollback}"
                # Step 2 reverse: restore ~/.claude.json at home root, restore the
                # inner backup if we made one.
                if (( migrate_step >= 2 )) && [[ -f "$target_dir/.claude.json" && ! -e "$legacy_homejson" ]]; then
                    mv "$target_dir/.claude.json" "$legacy_homejson" 2>/dev/null
                    if [[ -n "$moved_homejson_backup" && -f "$moved_homejson_backup" ]]; then
                        mv "$moved_homejson_backup" "$target_dir/.claude.json" 2>/dev/null
                    fi
                fi
                # Step 1 reverse: rename target_dir back to legacy_claude.
                if (( migrate_step >= 1 )) && [[ -d "$target_dir" && ! -e "$legacy_claude" ]]; then
                    mv "$target_dir" "$legacy_claude" 2>/dev/null
                    echo "Migration $why — restored $legacy_claude." >&2
                fi
                # Clean partial registry entry so a re-run isn't blocked.
                if [[ -f "$CKIPPER_REGISTRY" ]] && \
                   jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then
                    _ckipper_registry_update \
                        'del(.accounts[$n]) | (if .default == $n then .default = null else . end)' \
                        --arg n "$name"
                    echo "Cleaned partial '$name' entry from $CKIPPER_REGISTRY." >&2
                fi
                # Regenerate aliases.zsh so it reflects the post-rollback registry
                # (otherwise it would still define claude-<name>() pointing into a
                # dir that no longer exists).
                _ckipper_regenerate_aliases 2>/dev/null || true
            }
            # HUP catches Terminal.app window-close mid-migrate; QUIT catches Ctrl-\.
            trap '_ckipper_migrate_rollback interrupted; trap - INT TERM HUP QUIT ERR; return 130' INT TERM HUP QUIT

            # Step 1: rename ~/.claude → ~/.claude-<name>
            if ! mv "$legacy_claude" "$target_dir" 2>/dev/null; then
                trap - INT TERM HUP QUIT
                echo "Error: failed to rename $legacy_claude → $target_dir" >&2
                echo "(Check permissions on $HOME and that no process holds the directory open.)" >&2
                return 1
            fi
            migrate_step=1

            # Step 2: move ~/.claude.json → $target_dir/.claude.json.
            # If $target_dir already has a .claude.json (Claude wrote one when
            # CLAUDE_CONFIG_DIR was set in some prior run), back it up — the
            # home-root file is canonical.
            if [[ -f "$legacy_homejson" ]]; then
                if [[ -f "$target_dir/.claude.json" ]]; then
                    moved_homejson_backup="$target_dir/.claude.json.pre-migrate-backup"
                    mv "$target_dir/.claude.json" "$moved_homejson_backup"
                fi
                if ! mv "$legacy_homejson" "$target_dir/.claude.json" 2>/dev/null; then
                    _ckipper_migrate_rollback failed
                    trap - INT TERM HUP QUIT
                    echo "Error: failed to move $legacy_homejson → $target_dir/.claude.json" >&2
                    return 1
                fi
                migrate_step=2
            fi

            if ! _ckipper_finalize_registration "$name" "$target_dir" "$probed_service" "migrate"; then
                _ckipper_migrate_rollback failed
                trap - INT TERM HUP QUIT
                return 1
            fi
            trap - INT TERM HUP QUIT
            unset -f _ckipper_migrate_rollback
        fi
    fi

    # ── 3. Best-effort cleanup of old Docker image ────────────────
    if command -v docker >/dev/null 2>&1; then
        docker rmi claude-dev 2>/dev/null && echo "Removed old claude-dev Docker image."
    fi

    # Reload `name` from registry for the success-message context (in case migrate
    # was run for a no-op state and `name` was never set in this scope).
    local registered_name=""
    if [[ -f "$CKIPPER_REGISTRY" ]]; then
        registered_name=$(jq -r '.default // (.accounts | keys[0] // "")' "$CKIPPER_REGISTRY")
    fi

    cat <<EOF

Migration complete.

Next steps:
  1. Confirm your ~/.zshrc sources the new path:
       source ~/.ckipper/docker/w-function.zsh
     (install.sh updates this automatically; if you used a manual install, edit it yourself.)
  2. Add to ~/.zshrc to enable per-account aliases AND the bare-claude guard:
       [[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh
  3. Restart your shell:  exec zsh
  4. Run:  ckipper add <other-account-name>   to add additional accounts.

EOF
    if [[ -n "$registered_name" ]]; then
        cat <<EOF
To launch Claude with your migrated account, use:  claude-$registered_name
(Bare 'claude' no longer resolves to it — the guard in aliases.zsh refuses bare invocation once accounts are registered.)

EOF
    fi
}

# Short alias: 'ck' for 'ckipper'.
ck() { ckipper "$@"; }
