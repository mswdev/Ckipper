#!/usr/bin/env zsh
# Account-namespace dispatcher and help text.
#
# Routes `ckipper account <subcommand>` to the matching _ckipper_account_*
# function, prints overview/per-subcommand help, and suggests the closest
# subcommand on a typo via _core_fuzzy_suggest.

# Known account subcommands. Used both for routing and for fuzzy-suggest.
#
# `repair-plugins` was retired in favour of `ckipper doctor --fix`.
_CKIPPER_ACCOUNT_SUBCOMMANDS=(
    add list default remove rename sync redeploy-hooks help
)

# Dispatch an `account` subcommand.
#
# Args:
#   $1     — subcommand name (add, list, default, remove, rename, sync,
#             sync-hooks [hidden but callable], help, -h, --help, or empty)
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
        add|list|default|remove|rename|redeploy-hooks)
            if [[ "$1" == "--help" || "$1" == "-h" ]]; then
                _ckipper_account_help_for "$cmd"
                return 0
            fi
            "_ckipper_account_${cmd//-/_}" "$@"
            ;;
        sync)
            _ckipper_account_sync_dispatch "$@"
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
    _core_unknown_command "$1" \
        "Run 'ckipper account help' for available commands." \
        "${_CKIPPER_ACCOUNT_SUBCOMMANDS[@]}"
}

# Print the account-namespace usage summary.
#
# Returns: 0 always.
_ckipper_account_help() {
    _core_help_render "ckipper account — manage registered Claude accounts" \
        "" \
        "Usage:" \
        "  ckipper account add <name>           Register a new account (interactive /login)" \
        "  ckipper account add <name> --adopt   Register an existing populated config dir" \
        "  ckipper account list                 Show registered accounts" \
        "  ckipper account default <name>       Set the default account" \
        "  ckipper account remove <name>        Unregister; prompts to delete dir + Keychain" \
        "  ckipper account rename <old> <new>   Rename an account in place" \
        "  ckipper account sync [<from> <to>]   Sync state peer-to-peer between accounts" \
        "  ckipper account redeploy-hooks       Redeploy install safety hooks to all accounts" \
        "" \
        "Short form: \`ckipper acct ...\` is equivalent." \
        "" \
        "Run \`ckipper account <subcommand> --help\` for per-subcommand details."
}

# Per-subcommand help text router. Each arm prints a focused usage block.
#
# Note: the `sync` arm dispatches to the new sync subsystem's help via
# parse_args before reaching this router, so `_ckipper_account_help_text_sync`
# is no longer used here — kept only as a fallback.
#
# Args: $1 — subcommand name.
# Returns: 0 always.
_ckipper_account_help_for() {
    case "$1" in
        add)             _ckipper_account_help_text_add ;;
        list)            _ckipper_account_help_text_list ;;
        default)         _ckipper_account_help_text_default ;;
        remove)          _ckipper_account_help_text_remove ;;
        rename)          _ckipper_account_help_text_rename ;;
        sync)            _ckipper_account_sync_help_text ;;
        redeploy-hooks)  _ckipper_account_help_text_redeploy_hooks ;;
    esac
}

_ckipper_account_help_text_add() {
    _core_help_render "ckipper account add <name> [--adopt]" \
        "" \
        "Register a new account. <name> must match ^[a-z0-9_-]+$." \
        "" \
        "Without --adopt: creates ~/.claude-<name>/ and walks you through /login." \
        "With --adopt:    registers an existing populated ~/.claude-<name>/ directory."
}

_ckipper_account_help_text_list() {
    _core_help_render "ckipper account list" \
        "" \
        "Print registered accounts: name, config dir, keychain service, default flag," \
        "and last-login email (read from each account's .claude.json, if present)."
}

_ckipper_account_help_text_default() {
    _core_help_render "ckipper account default <name>" \
        "" \
        "Set the default account used when no \`--account\` flag and no" \
        "\$CLAUDE_CONFIG_DIR env var are provided."
}

_ckipper_account_help_text_remove() {
    _core_help_render "ckipper account remove <name>" \
        "" \
        "Unregister an account from the registry and aliases, then interactively" \
        "prompt to delete the config dir and the macOS Keychain entry. Decline" \
        "either prompt to keep the file/entry; the manual cleanup command is shown."
}

_ckipper_account_help_text_rename() {
    _core_help_render "ckipper account rename <old> <new>" \
        "" \
        "Rename a registered account in place:" \
        "  - Renames ~/.claude-<old>/ → ~/.claude-<new>/" \
        "  - Updates the registry (key + config_dir)" \
        "  - If <old> was the default, makes <new> the default" \
        "  - Regenerates aliases.zsh and re-syncs hooks" \
        "  - Refuses if any Claude session is running (so the dir isn't held open)" \
        "" \
        "Keychain service name is NOT changed — only the dir + registry mapping."
}

_ckipper_account_help_text_redeploy_hooks() {
    _core_help_render "ckipper account redeploy-hooks" \
        "" \
        "Redeploy ckipper-managed safety hooks from \$CKIPPER_DIR/hooks/ into" \
        "every registered account dir, then rewrite each account's settings.json" \
        "hook paths to absolute paths." \
        "" \
        "These hooks (bash-guardrails, protect-claude-config, docker-context," \
        "notify-bell) are docker safety guardrails — identical across every" \
        "account by construction. Run after editing any hook script under" \
        "\$CKIPPER_DIR/hooks/ so the change propagates to every account." \
        "" \
        "Note: this is NOT peer-to-peer sync. To sync user-written hooks" \
        "(scripts you authored that live outside the install set) between" \
        "accounts, use \`ckipper account sync <from> <to> --include hooks\`."
}
