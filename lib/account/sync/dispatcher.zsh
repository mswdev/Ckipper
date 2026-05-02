#!/usr/bin/env zsh
# Dispatcher for `ckipper account sync` and `ckipper account sync undo`.
# Routes top-level args to either the sync flow or the undo flow.
# Owns argument parsing; delegates execution to engine.zsh / interactive.zsh.

# Module-level parsed-arg holders. Populated by _ckipper_account_sync_parse_args
# before any handler reads them.
typeset -g _SYNC_FROM=""
typeset -ga _SYNC_TARGETS=()
typeset -g _SYNC_INCLUDE=""
typeset -g _SYNC_EXCLUDE=""
typeset -g _SYNC_DRY_RUN="false"
typeset -g _SYNC_YES="false"
typeset -g _SYNC_FORCE="false"

# Reset all module-level _SYNC_* holders. Called at the top of every
# parse_args invocation so re-running the dispatcher in the same shell
# doesn't see stale state from the previous call.
#
# Returns: 0 always.
_ckipper_account_sync_reset_args() {
    _SYNC_FROM=""
    _SYNC_TARGETS=()
    _SYNC_INCLUDE=""
    _SYNC_EXCLUDE=""
    _SYNC_DRY_RUN="false"
    _SYNC_YES="false"
    _SYNC_FORCE="false"
}

# Parse `ckipper account sync` arguments into the module-level _SYNC_* vars.
# Positional args: <from> [<to>...]. Flags: --include <list>, --exclude <list>,
# --dry-run, --yes, --force.
#
# Args: $@ — raw argv after `ckipper account sync` is stripped.
# Returns: 0 on success; 1 on unknown flag.
# Errors (stderr): "Unknown flag: <flag>" — when an unrecognized --foo appears.
_ckipper_account_sync_parse_args() {
    _ckipper_account_sync_reset_args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --include) _SYNC_INCLUDE="$2"; shift 2 ;;
            --exclude) _SYNC_EXCLUDE="$2"; shift 2 ;;
            --dry-run) _SYNC_DRY_RUN="true"; shift ;;
            --yes)     _SYNC_YES="true";     shift ;;
            --force)   _SYNC_FORCE="true";   shift ;;
            -h|--help) _ckipper_account_sync_help_text; return 0 ;;
            --*) echo "Unknown flag: $1" >&2; return 1 ;;
            *)
                if [[ -z "$_SYNC_FROM" ]]; then
                    _SYNC_FROM="$1"
                else
                    _SYNC_TARGETS+=("$1")
                fi
                shift
                ;;
        esac
    done
    return 0
}

# Print --help body for `ckipper account sync`. Filled in fully in Phase 9.
#
# Returns: 0 always.
_ckipper_account_sync_help_text() {
    echo "ckipper account sync [<from>] [<to>...] [options]"
    echo ""
    echo "  See docs/plans/2026-05-02-sync-overhaul-design.md §5 for the"
    echo "  complete flag and bundle catalog. Wired up in Phase 9."
}
