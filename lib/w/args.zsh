#!/usr/bin/env zsh
# Argument parsing for w(). Populates W_* globals used by all other lib/w modules.

# Parse all arguments passed to w() into W_* globals.
#
# Globals set:
#   W_FLAG_LIST           — true if --list
#   W_FLAG_REBUILD_IMAGE  — true if --rebuild-image
#   W_FLAG_RM             — true if --rm
#   W_FLAG_FORCE          — --force flag for --rm
#   W_FLAG_DOCKER         — true if --docker
#   W_FLAG_FIREWALL       — true if --firewall
#   W_PROJECT             — first positional arg (project path)
#   W_BRANCH              — second positional arg (worktree/branch name)
#   W_CLI_ACCOUNT         — value of --account <name>, or empty
#   W_COMMAND             — array: remaining positional args after project+branch
#   W_PROJECTS_DIR        — base directory for projects ($HOME/Developer)
#   W_WORKTREES_DIR       — base directory for worktrees ($HOME/Developer/.worktrees)
#
# Returns: 0 always (validation is done by the dispatcher).
_w_parse_args() {
    W_FLAG_LIST=false
    W_FLAG_REBUILD_IMAGE=false
    W_FLAG_RM=false
    W_FLAG_FORCE=false
    W_FLAG_DOCKER=false
    W_FLAG_FIREWALL=false
    W_PROJECT=""
    W_BRANCH=""
    W_CLI_ACCOUNT=""
    W_COMMAND=()
    W_PROJECTS_DIR="$HOME/Developer"
    W_WORKTREES_DIR="$HOME/Developer/.worktrees"

    if [[ "$1" == "--list" ]]; then
        W_FLAG_LIST=true
        return 0
    fi

    if [[ "$1" == "--rebuild-image" ]]; then
        W_FLAG_REBUILD_IMAGE=true
        return 0
    fi

    if [[ "$1" == "--rm" ]]; then
        W_FLAG_RM=true
        shift
        if [[ "$1" == "--force" || "$1" == "-f" ]]; then
            W_FLAG_FORCE=true
            shift
        fi
        W_PROJECT="$1"
        W_BRANCH="$2"
        return 0
    fi

    W_PROJECT="$1"
    W_BRANCH="$2"
    shift 2 2>/dev/null

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --docker)   W_FLAG_DOCKER=true; shift ;;
            --firewall) W_FLAG_FIREWALL=true; shift ;;
            --account)  W_CLI_ACCOUNT="$2"; shift 2 ;;
            *)          W_COMMAND+=("$1"); shift ;;
        esac
    done
}
