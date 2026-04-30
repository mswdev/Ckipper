#!/usr/bin/env zsh
# Argument parsing for w(). Populates W_* globals used by all other lib/w modules.

# Parse all arguments passed to w() into W_* globals.
#
# Globals set:
#   CKIPPER_WT_FLAG_LIST           — true if --list
#   CKIPPER_WT_FLAG_REBUILD_IMAGE  — true if --rebuild-image
#   CKIPPER_WT_FLAG_RM             — true if --rm
#   CKIPPER_WT_FLAG_FORCE          — true if --force (with --rm)
#   CKIPPER_WT_FLAG_DOCKER         — true if --docker
#   CKIPPER_WT_FLAG_FIREWALL       — true if --firewall
#   CKIPPER_WT_PROJECT             — first positional arg (project path)
#   CKIPPER_WT_BRANCH              — second positional arg (worktree/branch name)
#   CKIPPER_WT_CLI_ACCOUNT         — value of --account <name>, or empty
#   CKIPPER_WT_COMMAND             — array: remaining positional args after project+branch
#
# CKIPPER_PROJECTS_DIR / CKIPPER_WORKTREES_DIR are config values, not args — they are
# initialized once when w-function.zsh is sourced and never reset here.
#
# Returns: 0 always (validation is done by the dispatcher).
_ckipper_worktree_parse_args() {
    _ckipper_worktree_reset_globals

    if [[ "$1" == "--list" ]]; then
        CKIPPER_WT_FLAG_LIST=true
        return 0
    fi

    if [[ "$1" == "--rebuild-image" ]]; then
        CKIPPER_WT_FLAG_REBUILD_IMAGE=true
        return 0
    fi

    if [[ "$1" == "--rm" ]]; then
        _ckipper_worktree_parse_rm_args "$@"
        return 0
    fi

    _ckipper_worktree_parse_run_args "$@"
}

# Reset per-call W_* arg globals (flags + positionals) to their default values.
# Config globals (CKIPPER_PROJECTS_DIR, CKIPPER_WORKTREES_DIR, CKIPPER_PORTS, etc.) are owned
# by w-function.zsh and intentionally not touched here.
#
# Returns: 0 always.
_ckipper_worktree_reset_globals() {
    CKIPPER_WT_FLAG_LIST=false
    CKIPPER_WT_FLAG_REBUILD_IMAGE=false
    CKIPPER_WT_FLAG_RM=false
    CKIPPER_WT_FLAG_FORCE=false
    CKIPPER_WT_FLAG_DOCKER=false
    CKIPPER_WT_FLAG_FIREWALL=false
    CKIPPER_WT_PROJECT=""
    CKIPPER_WT_BRANCH=""
    CKIPPER_WT_CLI_ACCOUNT=""
    CKIPPER_WT_COMMAND=()
}

# Parse --rm [--force] <project> <branch> args.
#
# Args:
#   $@ — original args starting with --rm
#
# Returns: 0 always.
_ckipper_worktree_parse_rm_args() {
    CKIPPER_WT_FLAG_RM=true
    shift
    if [[ "$1" == "--force" || "$1" == "-f" ]]; then
        CKIPPER_WT_FLAG_FORCE=true
        shift
    fi
    CKIPPER_WT_PROJECT="$1"
    CKIPPER_WT_BRANCH="$2"
}

# Parse the normal run args: project branch [flags...] [command...].
#
# Args:
#   $@ — original args (project is $1, branch is $2)
#
# Returns: 0 always.
_ckipper_worktree_parse_run_args() {
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
