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
        add|list|default|remove|sync-hooks|migrate)
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
  ckipper sync-hooks          Copy hooks into all registered accounts
  ckipper migrate             One-time migration from legacy layout

Companion commands (sourced via aliases.zsh):
  cca <name> [args...]        Run claude with account <name> (one-off)
  claude-<name> [args...]     Auto-generated alias per registered account

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
        sync-hooks) echo "ckipper sync-hooks — copy ~/.ckipper/hooks/* into each account's <dir>/hooks/, rewrite settings.json paths." ;;
        migrate) echo "ckipper migrate — migrate from legacy ~/.claude/docker/ layout. Idempotent. Refuses if Claude is running." ;;
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
    [[ "$OSTYPE" != darwin* ]] && return 0

    # Fail loudly if keychain is locked (timeout protects against GUI prompt blocking).
    local out
    if ! out=$(timeout 10 security dump-keychain 2>/dev/null); then
        echo "Warning: Keychain may be locked or slow. Unlock it (Keychain Access > File > Unlock) and retry." >&2
        return 1
    fi

    printf '%s\n' "$out" | \
        awk -F'"' '/"svce"<blob>="Claude Code-credentials/ {print $4}' | \
        sort -u
}

# Atomic registry write under flock. $1 = jq filter; remaining args are jq args (e.g. --arg).
_ckipper_registry_update() {
    local jq_filter="$1"; shift
    local lock="$CKIPPER_DIR/.registry.lock"
    mkdir -p "$CKIPPER_DIR"
    : > "$lock"
    if command -v flock >/dev/null 2>&1; then
        {
            flock -x 9
            local tmp; tmp=$(mktemp)
            jq "$@" "$jq_filter" "$CKIPPER_REGISTRY" > "$tmp" && mv "$tmp" "$CKIPPER_REGISTRY"
            chmod 600 "$CKIPPER_REGISTRY"
        } 9>"$lock"
    else
        # Fallback for systems without flock (older macOS): mkdir-based lock.
        local lockdir="$CKIPPER_DIR/.registry.lock.d"
        until mkdir "$lockdir" 2>/dev/null; do sleep 0.05; done
        trap 'rmdir "$lockdir" 2>/dev/null' EXIT INT TERM
        local tmp; tmp=$(mktemp)
        jq "$@" "$jq_filter" "$CKIPPER_REGISTRY" > "$tmp" && mv "$tmp" "$CKIPPER_REGISTRY"
        chmod 600 "$CKIPPER_REGISTRY"
        rmdir "$lockdir" 2>/dev/null
        trap - EXIT INT TERM
    fi
}

# Initialize an empty registry with version field.
_ckipper_init_registry() {
    if [[ ! -f "$CKIPPER_REGISTRY" ]]; then
        mkdir -p "$CKIPPER_DIR"
        cat > "$CKIPPER_REGISTRY" <<EOF
{"version": $CKIPPER_REGISTRY_VERSION, "default": null, "accounts": {}}
EOF
        chmod 600 "$CKIPPER_REGISTRY"
    fi
}

# Refuse to operate on a registry whose version we don't understand.
_ckipper_check_registry_version() {
    [[ ! -f "$CKIPPER_REGISTRY" ]] && return 0
    local v
    v=$(jq -r '.version // 0' "$CKIPPER_REGISTRY")
    if (( v != CKIPPER_REGISTRY_VERSION )); then
        echo "Error: registry version $v not supported (this ckipper expects $CKIPPER_REGISTRY_VERSION). Update ckipper or restore from backup." >&2
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
        if [[ "$OSTYPE" == darwin* ]]; then
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

    # Fresh registration
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

In this same shell, run:

    CLAUDE_CONFIG_DIR=$dir claude

Complete the /login flow with the account you want to register as '$name'.
When done, exit Claude (Ctrl-D) and press enter here to finish registration.
If you closed the terminal by mistake, recover with: ckipper add $name --adopt

EOF
    read -r "?Press enter when /login is complete (or type 'skip' to abort): " ack
    if [[ "$ack" == "skip" ]]; then
        echo "Aborted. The directory $dir was created but not registered."
        echo "To complete registration later: ckipper add $name --adopt"
        return 1
    fi

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

    _ckipper_registry_update '
        .accounts[$n] = {config_dir: $d, keychain_service: (if $s == "" then null else $s end), registered_at: $t}
        | (if .default == null then .default = $n else . end)
    ' --arg n "$name" --arg d "$dir" --arg s "$service" --arg t "$now"

    _ckipper_regenerate_aliases
    _ckipper_sync_hooks_for "$name"

    echo "Registered '$name' (mode: $mode)."
    echo "Use it via: claude-$name   or   cca $name"
}

# Stubs — implemented in subsequent tasks (12, 13)
_ckipper_regenerate_aliases() { :; }
_ckipper_sync_hooks_for() { :; }

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
    echo "Reminder: do not run the same account in two sessions concurrently — see #24317."
}
_ckipper_default()    { echo "ckipper default: not yet implemented"; return 1; }
_ckipper_remove()     { echo "ckipper remove: not yet implemented"; return 1; }
_ckipper_sync_hooks() { echo "ckipper sync-hooks: not yet implemented"; return 1; }
_ckipper_migrate()    { echo "ckipper migrate: not yet implemented"; return 1; }
