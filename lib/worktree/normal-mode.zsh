#!/usr/bin/env zsh
# Normal (non-Docker) mode execution for w().

# Run the worktree in normal mode: cd to it or run a command inside it.
#
# Reads globals: W_WT_PATH, W_BRANCH, W_COMMAND.
# Returns: 0 on cd; exit code of command if one was given.
_ckipper_worktree_run_normal_mode() {
    if [[ ${#W_COMMAND[@]} -eq 0 ]]; then
        cd "$W_WT_PATH"
        return 0
    fi

    if [[ "${W_COMMAND[1]}" == "claude" ]]; then
        W_COMMAND+=("/rename $W_BRANCH")
    fi

    local old_pwd="$PWD"
    cd "$W_WT_PATH"
    "${W_COMMAND[@]}"
    local exit_code=$?
    cd "$old_pwd"
    return $exit_code
}
