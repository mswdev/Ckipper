#!/usr/bin/env zsh
# Argument parsing for the worktree namespace. Two parsers, one per subcommand
# (run, rm); the rest of the worktree subcommands take no args. Mode dispatch
# (--list / --rm / --rebuild-image) is gone — those are subcommands now and
# the dispatcher in lib/worktree/dispatcher.zsh routes them directly.
#
# Validation helpers (`_ckipper_worktree_validate_branch_name`,
# `_ckipper_worktree_validate_project_name`) defend against attacker-controlled
# `$worktree` / `$project` strings being parsed as git/option flags or
# traversing the projects directory. Callers MUST invoke these before passing
# the values into git commands or `$CKIPPER_PROJECTS_DIR/$project` paths.

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

# Validate a branch name before passing it to any git command.
#
# Rejects names that begin with `-` (would parse as a git flag) and names that
# fail `git check-ref-format --branch` (rejects `..`, control chars, trailing
# `.lock`, and other ref-format violations). Always pair this with `--` in the
# eventual git invocation as a defense-in-depth measure.
#
# Args: $1 — proposed branch name.
# Returns: 0 if the name is safe; 1 otherwise.
# Errors (stderr): "Invalid branch name: <name>" — when validation fails.
_ckipper_worktree_validate_branch_name() {
    local branch="$1"
    if [[ -z "$branch" || "$branch" == -* ]]; then
        echo "Invalid branch name: '$branch' (must not be empty or start with '-')" >&2
        return 1
    fi
    if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
        echo "Invalid branch name: '$branch' (rejected by git check-ref-format)" >&2
        return 1
    fi
}

# Validate a project path before using it under $CKIPPER_PROJECTS_DIR.
#
# Rejects empty values, leading `-`, characters outside `[A-Za-z0-9._/-]`, and
# any `..` path component. Uses a case-glob component check rather than a
# substring search so legitimate names like `my..app` are not rejected for
# containing `..` purely as text. The character whitelist makes shell-meta
# injection impossible even if a caller forgets to quote.
#
# Args: $1 — proposed project path (e.g. `myorg/app`).
# Returns: 0 if the path is safe; 1 otherwise.
# Errors (stderr): "Invalid project path: <path>" — when validation fails.
_ckipper_worktree_validate_project_name() {
    local project="$1"
    if [[ -z "$project" || "$project" == -* ]]; then
        echo "Invalid project path: '$project' (must not be empty or start with '-')" >&2
        return 1
    fi
    if [[ ! "$project" =~ ^[A-Za-z0-9._/-]+$ ]]; then
        echo "Invalid project path: '$project' (allowed: letters, digits, '.', '_', '-', '/')" >&2
        return 1
    fi
    case "/$project/" in
        */../*)
            echo "Invalid project path: '$project' ('..' path component not allowed)" >&2
            return 1
            ;;
    esac
}
