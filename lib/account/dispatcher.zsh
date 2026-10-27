#!/usr/bin/env zsh
# Account-namespace dispatcher and help text.
#
# Routes `ckipper account <subcommand>` to the matching _ckipper_account_*
# function, prints overview/per-subcommand help, and suggests the closest
# subcommand on a typo via _core_fuzzy_suggest.

# Known account subcommands. Used both for routing and for fuzzy-suggest.
_CKIPPER_ACCOUNT_SUBCOMMANDS=(
    add list default remove rename group sync help
)

# Dispatch an `account` subcommand.
#
# Args:
#   $1     — subcommand name (add, list, default, remove, rename, group,
#             sync, help, -h, --help, or empty)
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
        add|list|default|remove|rename|group)
            if [[ "$1" == "--help" || "$1" == "-h" ]]; then
                _ckipper_account_help_for "$cmd"
                return 0
            fi
            "_ckipper_account_${cmd}" "$@"
            ;;
        sync)
            _ckipper_account_sync_dispatch "$@"
            ;;
        ""|help|-h|--help) _ckipper_account_help ;;
        *) _ckipper_account_unknown "$cmd"; return 1 ;;
    esac
}

# Print the unknown-subcommand line with a fuzzy suggestion. Always writes
# to stderr.
#
# Args: $1 — the unknown subcommand the user typed.
# Returns: 0 always.
_ckipper_account_unknown() {
    local cmd="$1"
    _core_unknown_command "$cmd" \
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
        "      [--group <group>]                  …and join a group, copying its master's setup" \
        "  ckipper account add <name> --adopt   Register an existing populated config dir" \
        "  ckipper account list                 Show registered accounts" \
        "  ckipper account default <name>       Set the default account" \
        "  ckipper account remove <name>        Unregister; prompts to delete dir + Keychain" \
        "  ckipper account rename <old> <new>   Rename an account in place" \
        "  ckipper account group <name> <group> Put an account in a group (--master to lead it)" \
        "  ckipper account sync [<from> <to>]   Sync state between accounts in the same group" \
        "" \
        "Short form: \`ckipper acct ...\` is equivalent." \
        "" \
        "Run \`ckipper account <subcommand> --help\` for per-subcommand details."
}

# Per-subcommand help text router. Each arm prints a focused usage block.
# The `sync` arm forwards to the sync subsystem's own help text since that
# module owns its CLI surface.
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
        group)           _ckipper_account_help_text_group ;;
        sync)            _ckipper_account_sync_help_text ;;
    esac
}

_ckipper_account_help_text_add() {
    _core_help_render "ckipper account add <name> [--group <group>] [--adopt]" \
        "" \
        "Register a new account. <name> must match ^[a-z0-9_-]+$ and may not start" \
        "with 'desktop-'." \
        "" \
        "Without --adopt: creates ~/.claude-<name>/ and walks you through /login." \
        "With --adopt:    registers an existing populated ~/.claude-<name>/ directory." \
        "" \
        "With --group, the account joins <group>. A fresh account joining a group" \
        "that has a master gets the master's setup copied in after /login: every" \
        "sync type (MCP servers, settings, CLAUDE.md, skills, …) plus its installed" \
        "plugins. The first account in a new group becomes its master."
}

_ckipper_account_help_text_list() {
    _core_help_render "ckipper account list" \
        "" \
        "Print registered accounts: name, config dir, last-login email (from each" \
        "account's .claude.json), whether its Keychain login exists, and the default flag."
}

_ckipper_account_help_text_default() {
    _core_help_render "ckipper account default <name>" \
        "" \
        "Set the default account. The bare-claude guard points you at" \
        "claude-<default> when you type plain \`claude\`."
}

_ckipper_account_help_text_remove() {
    _core_help_render "ckipper account remove <name>" \
        "" \
        "Unregister an account from the registry and aliases, then interactively" \
        "prompt to delete the config dir and the account's macOS Keychain login" \
        "(the entry Claude Code derives from the dir path; the default" \
        "'Claude Code-credentials' entry is never touched). Decline either prompt" \
        "to keep the file/entry; the manual cleanup command is shown."
}

_ckipper_account_help_text_rename() {
    _core_help_render "ckipper account rename <old> <new>" \
        "" \
        "Rename a registered account in place:" \
        "  - Renames ~/.claude-<old>/ → ~/.claude-<new>/" \
        "  - Updates the registry (key + config_dir)" \
        "  - If <old> was the default, makes <new> the default" \
        "  - Rewrites absolute paths in plugins/*.json to the new dir" \
        "  - Regenerates aliases.zsh" \
        "  - Refuses if any Claude session is running (so the dir isn't held open)" \
        "" \
        "You must /login again afterwards: Claude Code names the Keychain entry" \
        "after the config dir, so the moved dir starts logged out. The old entry" \
        "is left in place and the command to delete it is printed."
}

_ckipper_account_help_text_group() {
    _core_help_render "ckipper account group <name> <group> [--master]" \
        "" \
        "Put an account in a group. Sync only runs between accounts in the same" \
        "group, so a personal account's settings, memory dir and plugins never" \
        "leak into a work account (or the reverse)." \
        "" \
        "The first account in a group becomes its master — the account new" \
        "members are copied from (see \`ckipper account add --group\`). Pass" \
        "--master to make <name> the master of an existing group." \
        "" \
        "\`ckipper doctor\` checks that each group's accounts share one" \
        "env.CLAUDE_CODE_REMOTE_MEMORY_DIR and that no two groups share one."
}
