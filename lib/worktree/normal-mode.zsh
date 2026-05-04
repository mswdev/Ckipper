#!/usr/bin/env zsh
# Normal (non-Docker) mode execution for `ckipper worktree run`.

# Run the worktree in normal mode: cd to it or run a command inside it.
#
# Reads globals: CKIPPER_WT_PATH, CKIPPER_WT_BRANCH, CKIPPER_WT_COMMAND.
# Returns: 0 on cd; exit code of command if one was given.
_ckipper_worktree_run_normal_mode() {
    if [[ ! -d "$CKIPPER_WT_PATH" ]]; then
        echo "Error: worktree path missing: $CKIPPER_WT_PATH" >&2
        return 1
    fi
    if [[ ${#CKIPPER_WT_COMMAND[@]} -eq 0 ]]; then
        cd "$CKIPPER_WT_PATH" || return 1
        return 0
    fi

    if [[ "${CKIPPER_WT_COMMAND[1]}" == "claude" ]]; then
        CKIPPER_WT_COMMAND+=("/rename $CKIPPER_WT_BRANCH")
    fi

    local old_pwd="$PWD"
    cd "$CKIPPER_WT_PATH" || return 1
    "${CKIPPER_WT_COMMAND[@]}"
    local exit_code=$?
    cd "$old_pwd" || true
    return $exit_code
}
