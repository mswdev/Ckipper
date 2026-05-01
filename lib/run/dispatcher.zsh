#!/usr/bin/env zsh
# Top-level `ckipper run` — shortcut for `ckipper worktree run`.
#
# Most users spend nearly all their time on the `worktree run` path; promoting
# it to a top-level verb keeps the muscle-memory short (`ck run …`) without
# duplicating any orchestration: this module is a thin pre-dispatch that
# forwards everything to `_ckipper_worktree_run`. The only logic here is the
# `--help` short-circuit so `ck run --help` shows shortcut-specific guidance
# rather than the namespaced `worktree run` text.

# Delegate to the worktree run handler, preserving all args.
#
# Args: $@ — forwarded to _ckipper_worktree_run unchanged. The first arg is
#   intercepted only when it is `--help` or `-h`; in that case the shortcut's
#   own help text is printed and `_ckipper_worktree_run` is not invoked.
# Returns: same as _ckipper_worktree_run; 0 when `--help`/`-h` short-circuits.
_ckipper_run() {
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        _ckipper_run_help
        return 0
    fi
    _ckipper_worktree_run "$@"
}

# Print help for `ckipper run`.
#
# Returns: 0 always.
_ckipper_run_help() {
    cat <<'EOF'
ckipper run <project> <branch> [flags] [cmd...]

Shortcut for `ckipper worktree run`. Per-account preferences
(always_docker, always_firewall, ssh_forward) populate flag
defaults; pass --no-docker / --no-firewall / --no-ssh-forward
to override per invocation.
EOF
}
