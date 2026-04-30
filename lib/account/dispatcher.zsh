#!/usr/bin/env zsh
# Account-namespace dispatcher and help text.
#
# Routes `ckipper account <subcommand>` to the matching _ckipper_account_*
# function, prints overview/per-subcommand help, and suggests the closest
# subcommand on a typo via _core_fuzzy_suggest.

# Known account subcommands. Used both for routing and for fuzzy-suggest.
_CKIPPER_ACCOUNT_SUBCOMMANDS=(
    add list default remove rename sync sync-hooks repair-plugins help
)

# Dispatch an `account` subcommand.
#
# Args:
#   $1     — subcommand name (add, list, default, remove, rename, sync,
#             sync-hooks, repair-plugins, help, -h, --help, or empty)
#   $2..$N — arguments forwarded to the subcommand handler
#
# Returns: 0 on success; 1 on unknown subcommand.
#
# Errors (stderr):
#   "Unknown command: '<cmd>'. Did you mean: '<match>'? ..."
_ckipper_account_dispatch() {
    local cmd="$1"
    shift 2>/dev/null
    case "$cmd" in
        add|list|default|remove|rename|sync|sync-hooks|repair-plugins)
            if [[ "$1" == "--help" || "$1" == "-h" ]]; then
                _ckipper_account_help_for "$cmd"
                return 0
            fi
            "_ckipper_account_${cmd//-/_}" "$@"
            ;;
        ""|help|-h|--help) _ckipper_account_help ;;
        *) _ckipper_account_unknown "$cmd"; return 1 ;;
    esac
}

# Print the closest-match suggestion (or a bare unknown-command line) and
# point the user at help. Always writes to stderr.
#
# Args: $1 — the unknown subcommand the user typed.
# Returns: 0 always.
_ckipper_account_unknown() {
    local cmd="$1" suggestion
    suggestion=$(_core_fuzzy_suggest "$cmd" "${_CKIPPER_ACCOUNT_SUBCOMMANDS[@]}")
    if [[ -n "$suggestion" ]]; then
        echo "Unknown command: '$cmd'. Did you mean: '$suggestion'?" >&2
    else
        echo "Unknown command: '$cmd'." >&2
    fi
    echo "Run 'ckipper account help' for available commands." >&2
}

# Print the account-namespace usage summary.
#
# Returns: 0 always.
_ckipper_account_help() {
    cat <<'EOF'
ckipper account — manage registered Claude accounts

Usage:
  ckipper account add <name>         Register a new account (interactive /login)
  ckipper account add <name> --adopt Register an existing populated config dir
  ckipper account list               Show registered accounts
  ckipper account default <name>     Set the default account
  ckipper account remove <name>      Unregister (does not delete the dir)
  ckipper account rename <old> <new> Rename an account in place
  ckipper account sync <from> <to>   Copy MCP/settings between accounts
  ckipper account sync-hooks         Re-deploy hooks into every account dir
  ckipper account repair-plugins <n> Rewrite stale plugin paths

Short form: `ckipper acct ...` is equivalent.

Run `ckipper account <subcommand> --help` for per-subcommand details.
EOF
}

# Per-subcommand help text router. Each arm prints a focused usage block.
#
# Args: $1 — subcommand name.
# Returns: 0 always.
_ckipper_account_help_for() {
    case "$1" in
        add)            _ckipper_account_help_text_add ;;
        list)           _ckipper_account_help_text_list ;;
        default)        _ckipper_account_help_text_default ;;
        remove)         _ckipper_account_help_text_remove ;;
        rename)         _ckipper_account_help_text_rename ;;
        sync)           _ckipper_account_help_text_sync ;;
        sync-hooks)     _ckipper_account_help_text_sync_hooks ;;
        repair-plugins) _ckipper_account_help_text_repair_plugins ;;
    esac
}

_ckipper_account_help_text_add() {
    cat <<'EOF'
ckipper account add <name> [--adopt]

Register a new account. <name> must match ^[a-z0-9_-]+$.

Without --adopt: creates ~/.claude-<name>/ and walks you through /login.
With --adopt:    registers an existing populated ~/.claude-<name>/ directory.
EOF
}

_ckipper_account_help_text_list() {
    cat <<'EOF'
ckipper account list

Print registered accounts: name, config dir, keychain service, default flag,
and last-login email (read from each account's .claude.json, if present).
EOF
}

_ckipper_account_help_text_default() {
    cat <<'EOF'
ckipper account default <name>

Set the default account used when no `--account` flag and no
$CLAUDE_CONFIG_DIR env var are provided.
EOF
}

_ckipper_account_help_text_remove() {
    cat <<'EOF'
ckipper account remove <name>

Unregister an account from the registry and aliases. Does NOT delete the
config dir or the macOS Keychain entry — those stay for safety.
EOF
}

_ckipper_account_help_text_rename() {
    cat <<'EOF'
ckipper account rename <old> <new>

Rename a registered account in place:
  - Renames ~/.claude-<old>/ → ~/.claude-<new>/
  - Updates the registry (key + config_dir)
  - If <old> was the default, makes <new> the default
  - Regenerates aliases.zsh and re-syncs hooks
  - Refuses if any Claude session is running (so the dir isn't held open)

Keychain service name is NOT changed — only the dir + registry mapping.
EOF
}

_ckipper_account_help_text_sync() {
    cat <<'EOF'
ckipper account sync <from> <to> [options]

Copy state from one registered account to another. Useful for sharing MCP
servers, plugin lists, status line, env vars, etc. across accounts.

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
  ckipper account sync personal work
  ckipper account sync personal work --mcp
  ckipper account sync personal work --mcp Vibma,github
  ckipper account sync personal work --settings statusLine,env --dry-run
EOF
}

_ckipper_account_help_text_sync_hooks() {
    cat <<'EOF'
ckipper account sync-hooks

Copy ~/.ckipper/hooks/* into each registered account's <dir>/hooks/ and
rewrite the per-account settings.json to point at those copies.

Run after editing any hook script under ~/.ckipper/hooks/ so the change
propagates to every account.
EOF
}

_ckipper_account_help_text_repair_plugins() {
    cat <<'EOF'
ckipper account repair-plugins <name>

Rewrite stale absolute paths in <account_dir>/plugins/{known_marketplaces,
installed_plugins}.json from $HOME/.claude/... to the account's actual dir.

Use this when Claude Code shows "Plugin not found in marketplace ..." for
plugins that were installed before the account directory was renamed.
Backups are written alongside each rewritten file.
EOF
}
