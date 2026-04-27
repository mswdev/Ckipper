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

# Stubs — implemented in subsequent tasks
_ckipper_add()        { echo "ckipper add: not yet implemented"; return 1; }
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
