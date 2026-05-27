#!/usr/bin/env zsh
# Desktop-namespace help text.
#
# Owns ALL `ckipper desktop` help output — both the top-level overview
# (`ckipper desktop` / `ckipper desktop help`) and the focused per-
# subcommand help (`ckipper desktop <sub> --help`). Kept in a dedicated
# file because the desktop namespace has substantially longer help blocks
# (deep-link gotcha, bundle/data-dir layout) than account/worktree.
#
# Rendering goes through `_core_help_render` (lib/core/help.zsh) so chrome
# stays uniform across every ckipper subcommand.

# Print the desktop-namespace usage summary.
#
# Returns: 0 always.
_ckipper_desktop_help() {
    _core_help_render "ckipper desktop — manage Claude Desktop instances (macOS)" \
        "" \
        "Usage:" \
        "  ckipper desktop add <name>           Register a new desktop instance" \
        "  ckipper desktop list                 Show registered instances" \
        "  ckipper desktop remove <name>        Unregister; prompts to delete dir + bundle" \
        "  ckipper desktop rename <old> <new>   Rename an instance in place" \
        "  ckipper desktop login <name>         Quit ALL Claude apps then launch only <name>" \
        "  ckipper desktop launch <name>        Launch <name> alongside any others" \
        "" \
        "Short form: \`ckipper dt ...\` is equivalent." \
        "" \
        "Run \`ckipper desktop <subcommand> --help\` for per-subcommand details." \
        "" \
        "Note: macOS routes \`claude://\` deep-link auth callbacks to whichever Claude" \
        "instance registered the URL scheme most recently. Use \`ckipper desktop login\`" \
        "to avoid auth landing in the wrong window."
}

# Per-subcommand help text router. Each arm prints a focused usage block.
#
# Args: $1 — subcommand name (add, list, remove, rename, login, launch).
# Returns: 0 always.
_ckipper_desktop_help_for() {
    case "$1" in
        add)    _ckipper_desktop_help_text_add ;;
        list)   _ckipper_desktop_help_text_list ;;
        remove) _ckipper_desktop_help_text_remove ;;
        rename) _ckipper_desktop_help_text_rename ;;
        login)  _ckipper_desktop_help_text_login ;;
        launch) _ckipper_desktop_help_text_launch ;;
    esac
}

# Print help for `ckipper desktop add`.
#
# Returns: 0 always.
_ckipper_desktop_help_text_add() {
    _core_help_render "ckipper desktop add <name>" \
        "" \
        "Register a new Claude Desktop instance. <name> must match ^[a-z0-9_-]+$." \
        "" \
        "Creates:" \
        "  ~/.claude-desktop-<name>/             Isolated user-data dir for this instance" \
        "  ~/Applications/Claude-<Name>.app/     Wrapper bundle that launches Claude with" \
        "                                        --user-data-dir pointed at the dir above" \
        "" \
        "Prerequisite: /Applications/Claude.app must be installed (download from" \
        "https://claude.ai/download). The wrapper bundle exec's \`open -n -a\` on it."
}

# Print help for `ckipper desktop list`.
#
# Returns: 0 always.
_ckipper_desktop_help_text_list() {
    _core_help_render "ckipper desktop list" \
        "" \
        "Print registered desktop instances. Columns:" \
        "  name              The instance name" \
        "  user-data-dir     Path to ~/.claude-desktop-<name>/" \
        "  bundle            Path to the generated .app wrapper bundle" \
        "  registered_at     ISO-8601 timestamp from the registry" \
        "  status            running / stopped (from pgrep against the data dir)"
}

# Print help for `ckipper desktop remove`.
#
# Returns: 0 always.
_ckipper_desktop_help_text_remove() {
    _core_help_render "ckipper desktop remove <name>" \
        "" \
        "Unregister a desktop instance from the registry, then interactively prompt" \
        "to delete:" \
        "  - the user-data dir (~/.claude-desktop-<name>/)" \
        "  - the wrapper bundle (~/Applications/Claude-<Name>.app)" \
        "" \
        "Decline either prompt to keep the file/dir; the manual cleanup command is" \
        "shown so you can finish later." \
        "" \
        "Refuses if the instance is currently running — quit it first."
}

# Print help for `ckipper desktop rename`.
#
# Returns: 0 always.
_ckipper_desktop_help_text_rename() {
    _core_help_render "ckipper desktop rename <old> <new>" \
        "" \
        "Rename a desktop instance in place:" \
        "  - Moves ~/.claude-desktop-<old>/ → ~/.claude-desktop-<new>/" \
        "  - Regenerates the wrapper bundle as ~/Applications/Claude-<New>.app" \
        "  - Updates the registry (key + paths)" \
        "" \
        "Refuses if:" \
        "  - the instance is currently running (so files aren't held open), or" \
        "  - <new> already exists in the registry (name collision)."
}

# Print help for `ckipper desktop login`.
#
# Returns: 0 always.
_ckipper_desktop_help_text_login() {
    _core_help_render "ckipper desktop login <name>" \
        "" \
        "Quit ALL running Claude Desktop processes, then launch only <name>." \
        "" \
        "Why this exists: macOS routes \`claude://\` deep-link auth callbacks to" \
        "whichever Claude instance registered the URL scheme most recently. If" \
        "you start \`/login\` while two instances are running, the OAuth callback" \
        "can land in the wrong window. This is unfixable in user space." \
        "" \
        "The workaround is to quit other instances before logging in. This command" \
        "automates that dance: pgrep-and-kill every running Claude process, wait" \
        "for them to exit, then \`open -n -a\` only the target wrapper bundle." \
        "Complete \`/login\` in the lone running instance; the deep-link callback" \
        "has only one place to land." \
        "" \
        "See also: \`ckipper desktop launch <name>\` to start an instance without" \
        "quitting the others."
}

# Print help for `ckipper desktop launch`.
#
# Returns: 0 always.
_ckipper_desktop_help_text_launch() {
    _core_help_render "ckipper desktop launch <name>" \
        "" \
        "Launch a desktop instance via \`open -n -a\` on its wrapper bundle." \
        "Does NOT quit other running Claude instances — use \`ckipper desktop" \
        "login <name>\` for that (needed before /login flows; see its --help)."
}
