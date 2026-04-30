#!/usr/bin/env zsh
# Ckipper main dispatcher.
# Sources shared primitives from lib/core/ and account-management subcommands from lib/account/.
# Public functions exposed: ckipper, ck.

# Ckipper (pronounced "skipper") — multi-account Claude Code manager
# Sourced by w-function.zsh

CKIPPER_DIR="${CKIPPER_DIR:-$HOME/.ckipper}"
CKIPPER_REGISTRY="$CKIPPER_DIR/accounts.json"
CKIPPER_REGISTRY_VERSION=1

CKIPPER_REPO_DIR="${0:A:h}"

source "$CKIPPER_REPO_DIR/lib/core/utils.zsh"
source "$CKIPPER_REPO_DIR/lib/core/registry.zsh"
source "$CKIPPER_REPO_DIR/lib/core/keychain.zsh"
source "$CKIPPER_REPO_DIR/lib/account/account-management.zsh"
source "$CKIPPER_REPO_DIR/lib/account/aliases.zsh"
source "$CKIPPER_REPO_DIR/lib/account/plugin-repair.zsh"
source "$CKIPPER_REPO_DIR/lib/account/sync.zsh"
source "$CKIPPER_REPO_DIR/lib/account/doctor.zsh"

# Dispatch a ckipper subcommand or print top-level help.
#
# Args:
#   $1 — subcommand name (add, list, default, remove, rename, sync, sync-hooks,
#         doctor, repair-plugins, help, -h, --help, or empty)
#   $@ — arguments forwarded to the subcommand handler
#
# Returns:
#   0 on success; 1 on unknown subcommand.
#
# Errors (stderr):
#   "Unknown command: <cmd>" — when the subcommand is not recognised.
ckipper() {
    local cmd="$1"
    shift 2>/dev/null
    case "$cmd" in
        # --help on any subcommand short-circuits to subcommand help
        add|list|default|remove|rename|sync|sync-hooks|doctor|repair-plugins)
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

# Print the top-level ckipper usage summary to stdout.
#
# Returns:
#   0 always.
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
  ckipper doctor              Diagnostic check of registered accounts and tooling
  ckipper repair-plugins <n>  Rewrite stale ~/.claude/ paths in plugin metadata

Companion commands (sourced via aliases.zsh):
  claude-<name> [args...]     Auto-generated launcher per registered account
  <name> [args...]            Bare-name shortcut (skipped if it would shadow an
                              existing command, builtin, alias, or reserved word)

Run `ckipper <subcommand> --help` for per-subcommand details.
EOF
}

# Print help text for the 'add' subcommand.
_help_text_add() {
    cat <<'EOF'
ckipper add <name> [--adopt]

Register a new account. <name> must match ^[a-z0-9_-]+$.

Without --adopt: creates ~/.claude-<name>/ and walks you through /login.
With --adopt:    registers an existing populated ~/.claude-<name>/ directory.
EOF
}

# Print help text for the 'rename' subcommand.
_help_text_rename() {
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
}

# Print help text for the 'repair-plugins' subcommand.
_help_text_repair_plugins() {
    cat <<'EOF'
ckipper repair-plugins <name>

Rewrite stale absolute paths in <account_dir>/plugins/{known_marketplaces,
installed_plugins}.json from $HOME/.claude/... to the account's actual dir.

Use this when Claude Code shows "Plugin not found in marketplace ..." for
plugins that were installed before the account directory was renamed.
Backups are written alongside each rewritten file.
EOF
}

# Print help text for the 'sync' subcommand.
_help_text_sync() {
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
}

# Dispatch to the per-subcommand help text printer.
#
# Args:
#   $1 — subcommand name
#
# Returns:
#   0 always.
_ckipper_help_for() {
    case "$1" in
        add)            _help_text_add ;;
        list)           echo "ckipper list — print registered accounts, default, and last-login email." ;;
        default)        echo "ckipper default <name> — set the default account used when no flag/env is provided." ;;
        remove)         echo "ckipper remove <name> — unregister. Does not delete the dir or Keychain entry." ;;
        rename)         _help_text_rename ;;
        sync-hooks)     echo "ckipper sync-hooks — copy ~/.ckipper/hooks/* into each account's <dir>/hooks/, rewrite settings.json paths." ;;
        repair-plugins) _help_text_repair_plugins ;;
        sync)           _help_text_sync ;;
        doctor)         echo "ckipper doctor — run a diagnostic checklist on registered accounts and ckipper tooling." ;;
    esac
}

# Short alias: 'ck' for 'ckipper'.
ck() { ckipper "$@"; }
