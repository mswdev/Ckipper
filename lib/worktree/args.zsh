#!/usr/bin/env zsh
# Argument parsing for the worktree namespace. Two parsers, one per subcommand
# (run, rm); the rest of the worktree subcommands take no args. Mode dispatch
# (--list / --rm / --rebuild-image) is gone — those are subcommands now and
# the dispatcher in lib/worktree/dispatcher.zsh routes them directly.

# Reset per-call CKIPPER_WT_* arg globals (flags + positionals) to defaults.
# Config globals (CKIPPER_PROJECTS_DIR, CKIPPER_WORKTREES_DIR, CKIPPER_PORTS,
# etc.) are owned by ckipper.zsh and intentionally not touched here.
#
# Returns: 0 always.
_ckipper_worktree_reset_globals() {
    CKIPPER_WT_FLAG_FORCE=false
    CKIPPER_WT_FLAG_DOCKER=false
    CKIPPER_WT_FLAG_FIREWALL=false
    CKIPPER_WT_PROJECT=""
    CKIPPER_WT_BRANCH=""
    CKIPPER_WT_CLI_ACCOUNT=""
    CKIPPER_WT_COMMAND=()
}

# Parse `worktree run <project> <branch> [--docker] [--firewall] [--account <name>] [cmd...]`.
#
# Globals set:
#   CKIPPER_WT_PROJECT       — first positional arg (project path)
#   CKIPPER_WT_BRANCH        — second positional arg (worktree/branch name)
#   CKIPPER_WT_FLAG_DOCKER   — true if --docker
#   CKIPPER_WT_FLAG_FIREWALL — true if --firewall
#   CKIPPER_WT_CLI_ACCOUNT   — value of --account <name>, or empty
#   CKIPPER_WT_COMMAND       — array of remaining positional args (the command to run)
#
# Returns: 0 always (validation is the caller's responsibility).
_ckipper_worktree_parse_run_args() {
    _ckipper_worktree_reset_globals
    CKIPPER_WT_PROJECT="$1"
    CKIPPER_WT_BRANCH="$2"
    shift 2 2>/dev/null

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --docker)   CKIPPER_WT_FLAG_DOCKER=true; shift ;;
            --firewall) CKIPPER_WT_FLAG_FIREWALL=true; shift ;;
            --account)  CKIPPER_WT_CLI_ACCOUNT="$2"; shift 2 ;;
            *)          CKIPPER_WT_COMMAND+=("$1"); shift ;;
        esac
    done
}

# Parse `worktree rm [--force] <project> <branch>`.
#
# Globals set:
#   CKIPPER_WT_FLAG_FORCE  — true if --force / -f was passed
#   CKIPPER_WT_PROJECT     — project path
#   CKIPPER_WT_BRANCH      — branch name
#
# Returns: 0 always.
_ckipper_worktree_parse_rm_args() {
    _ckipper_worktree_reset_globals
    if [[ "$1" == "--force" || "$1" == "-f" ]]; then
        CKIPPER_WT_FLAG_FORCE=true
        shift
    fi
    CKIPPER_WT_PROJECT="$1"
    CKIPPER_WT_BRANCH="$2"
}
