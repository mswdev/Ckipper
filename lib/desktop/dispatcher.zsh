#!/usr/bin/env zsh
# Desktop-namespace dispatcher. Routes `ckipper desktop <subcommand>`
# to the matching _ckipper_desktop_* function, prints overview/per-
# subcommand help, and suggests the closest subcommand on a typo via
# _core_fuzzy_suggest.
#
# Refuses to operate on non-macOS hosts at the dispatcher entry —
# Desktop multi-instance relies on macOS-specific facilities (`open -n -a`,
# `lsregister`, `.app` bundle format).

# Known desktop subcommands. Used both for routing and for fuzzy-suggest.
_CKIPPER_DESKTOP_SUBCOMMANDS=(
    add list remove rename login launch help
)

# Dispatch a `desktop` subcommand.
#
# Args:
#   $1     — subcommand name (add, list, remove, rename, login, launch,
#             help, -h, --help, or empty)
#   $2..$N — arguments forwarded to the subcommand handler
#
# Returns: 0 on success; 1 on unknown subcommand or non-macOS host.
#
# Errors (stderr):
#   "ckipper desktop is macOS-only ..."           — when OSTYPE != darwin*
#   "Unknown command: '<cmd>'. Did you mean ..."  — on a typo
_ckipper_desktop_dispatch() {
    _ckipper_desktop_assert_macos || return 1
    local cmd="$1"
    shift 2>/dev/null
    case "$cmd" in
        add|list|remove|rename|login|launch)
            if [[ "$1" == "--help" || "$1" == "-h" ]]; then
                _ckipper_desktop_help_for "$cmd"
                return 0
            fi
            "_ckipper_desktop_${cmd}" "$@"
            ;;
        ""|help|-h|--help) _ckipper_desktop_help ;;
        *) _ckipper_desktop_unknown "$cmd"; return 1 ;;
    esac
}

# Refuse to run on non-macOS hosts. Uses the _CKIPPER_TEST_OSTYPE override
# for tests (same pattern as lib/core/keychain.zsh and lib/account/doctor.zsh).
#
# Returns: 0 if running on macOS; 1 otherwise.
# Errors (stderr): "ckipper desktop is macOS-only ..." when refusing.
_ckipper_desktop_assert_macos() {
    [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" == darwin* ]] && return 0
    echo "ckipper desktop is macOS-only (Claude Desktop runs on macOS / Windows; only macOS is supported here)." >&2
    return 1
}

# Print an unknown-subcommand line with fuzzy suggestion and help pointer.
# All output goes to stderr via _core_unknown_command.
#
# Args: $1 — the unknown subcommand the user typed.
# Returns: 0 always.
_ckipper_desktop_unknown() {
    local cmd="$1"
    _core_unknown_command "$cmd" \
        "Run 'ckipper desktop help' for available commands." \
        "${_CKIPPER_DESKTOP_SUBCOMMANDS[@]}"
}

# --- TEMPORARY STUBS (deleted as Tasks 5..11 land the real implementations) ---
# Each stub returns 1 so users typing them get a "not yet implemented" signal.
# The task number is embedded in each message for grep-ability when wiring up
# the real handlers.
_ckipper_desktop_add()    { echo "ckipper desktop add: not yet implemented (Task 5)"    >&2; return 1; }
_ckipper_desktop_list()   { echo "ckipper desktop list: not yet implemented (Task 6)"   >&2; return 1; }
_ckipper_desktop_remove() { echo "ckipper desktop remove: not yet implemented (Task 7)" >&2; return 1; }
_ckipper_desktop_rename() { echo "ckipper desktop rename: not yet implemented (Task 8)" >&2; return 1; }
_ckipper_desktop_login()  { echo "ckipper desktop login: not yet implemented (Task 10)" >&2; return 1; }
_ckipper_desktop_launch() { echo "ckipper desktop launch: not yet implemented (Task 11)" >&2; return 1; }
