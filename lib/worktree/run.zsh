#!/usr/bin/env zsh
# `ckipper worktree run` orchestrator. The body of the old w() function,
# minus the mode dispatch that's now in lib/worktree/dispatcher.zsh.

# Create-or-cd to a worktree and either drop into the host shell, run a host
# command, launch a Docker container, or run a command inside the container.
#
# Args:
#   $@ — exactly the args passed to `ckipper worktree run`:
#         <project> <branch> [flags...] [cmd...]
#         (See _ckipper_worktree_parse_run_args for the supported flags.)
#
# Returns:
#   0 on success; 1 on usage error or launch failure.
#
# Errors (stderr):
#   "Error: --firewall requires --docker" — when the resolved firewall flag is
#     true but the resolved docker flag is false. This catches both the obvious
#     CLI typo (--firewall --no-docker) and the subtler account-misconfig case
#     (always_firewall=true with always_docker=false).
_ckipper_worktree_run() {
    _ckipper_worktree_parse_run_args "$@"

    if [[ -z "$CKIPPER_WT_PROJECT" || -z "$CKIPPER_WT_BRANCH" ]]; then
        _ckipper_worktree_help_for run >&2
        return 1
    fi

    _core_registry_check_version || return 1
    _ckipper_worktree_resolve_account || return $?
    _ckipper_worktree_resolve_flags "$CKIPPER_WT_ACTIVE_ACCOUNT"

    if [[ "$CKIPPER_WT_FLAG_FIREWALL" = "true" && "$CKIPPER_WT_FLAG_DOCKER" = "false" ]]; then
        echo "Error: --firewall requires --docker" >&2
        return 1
    fi

    _ckipper_worktree_create_worktree "$CKIPPER_WT_PROJECT" "$CKIPPER_WT_BRANCH" || return $?

    if [[ "$CKIPPER_WT_FLAG_DOCKER" = "true" ]]; then
        _ckipper_worktree_run_docker_mode
    else
        _ckipper_worktree_run_normal_mode
    fi
}

# Apply per-account preferences to the docker/firewall/ssh-forward flags.
# Explicit CLI overrides (CKIPPER_WT_FLAG_*_EXPLICIT=true) win; otherwise the
# corresponding account preference is read from the registry via
# _core_config_get, which falls back to the schema default when no preference
# is set.
#
# Must be called after _ckipper_worktree_resolve_account so that
# CKIPPER_WT_ACTIVE_ACCOUNT and the account preferences are available.
#
# Args: $1 — account name (may be empty; _core_config_get falls back to the
#   global value, then the schema default).
# Returns: 0 always. Mutates CKIPPER_WT_FLAG_DOCKER / _FIREWALL / _SSH_FORWARD
#   in place when the corresponding *_EXPLICIT tracker is "false".
_ckipper_worktree_resolve_flags() {
    local account="$1"
    if [[ "$CKIPPER_WT_FLAG_DOCKER_EXPLICIT" = "false" ]]; then
        CKIPPER_WT_FLAG_DOCKER=$(_core_config_get always_docker "$account")
    fi
    if [[ "$CKIPPER_WT_FLAG_FIREWALL_EXPLICIT" = "false" ]]; then
        CKIPPER_WT_FLAG_FIREWALL=$(_core_config_get always_firewall "$account")
    fi
    if [[ "$CKIPPER_WT_FLAG_SSH_FORWARD_EXPLICIT" = "false" ]]; then
        CKIPPER_WT_FLAG_SSH_FORWARD=$(_core_config_get ssh_forward "$account")
    fi
}
