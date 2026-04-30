#!/usr/bin/env zsh
# `ckipper worktree run` orchestrator. The body of the old w() function,
# minus the mode dispatch that's now in lib/worktree/dispatcher.zsh.

# Create-or-cd to a worktree and either drop into the host shell, run a host
# command, launch a Docker container, or run a command inside the container.
#
# Args:
#   $@ — exactly the args passed to `ckipper worktree run`:
#         <project> <branch> [--docker] [--firewall] [--account <name>] [cmd...]
#
# Returns:
#   0 on success; 1 on usage error or launch failure.
#
# Errors (stderr):
#   "Error: --firewall requires --docker" — when --firewall is passed without --docker.
_ckipper_worktree_run() {
    _ckipper_worktree_parse_run_args "$@"

    if [[ -z "$CKIPPER_WT_PROJECT" || -z "$CKIPPER_WT_BRANCH" ]]; then
        _ckipper_worktree_help_for run >&2
        return 1
    fi

    if [[ "$CKIPPER_WT_FLAG_FIREWALL" = true && "$CKIPPER_WT_FLAG_DOCKER" = false ]]; then
        echo "Error: --firewall requires --docker" >&2
        return 1
    fi

    _ckipper_worktree_resolve_account || return $?
    _ckipper_worktree_create_worktree "$CKIPPER_WT_PROJECT" "$CKIPPER_WT_BRANCH" || return $?

    if [[ "$CKIPPER_WT_FLAG_DOCKER" = true ]]; then
        _ckipper_worktree_run_docker_mode
    else
        _ckipper_worktree_run_normal_mode
    fi
}
