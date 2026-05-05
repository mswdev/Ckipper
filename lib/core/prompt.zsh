#!/usr/bin/env zsh
# Interactive prompt helpers for ckipper. Wraps gum (charmbracelet/gum) when
# available, otherwise falls back to pure-zsh `read` prompts.
#
# All public helpers honor CKIPPER_NO_GUM: setting it to "1" forces the
# pure-zsh fallback path so non-TTY callers and tests can pin behavior
# regardless of whether gum is installed on the host.
#
# Prompt labels are written to stderr (via `read "?prompt"`); the chosen value
# is written to stdout. Callers must capture stdout via command substitution
# and let stderr flow to the terminal.

# Sentinel value for CKIPPER_NO_GUM that disables gum even when installed.
readonly _CORE_PROMPT_NO_GUM_SENTINEL="1"

# Decide whether to use gum for the next prompt.
#
# Returns: 0 when gum should be used (CKIPPER_NO_GUM != "1" AND `gum` is on
#   PATH); 1 otherwise.
_core_prompt_use_gum() {
    [[ "$CKIPPER_NO_GUM" == "$_CORE_PROMPT_NO_GUM_SENTINEL" ]] && return 1
    command -v gum >/dev/null 2>&1
}

# Prompt for a free-form string. Returns the entered value, or the supplied
# default when input is empty.
#
# Distinguishes "user submitted empty" (rc=0, value=default) from "user
# cancelled" (rc != 0, no stdout). `gum input` exits non-zero on Esc/Ctrl-C,
# and we propagate that so callers can distinguish cancellation. Previously
# we collapsed both into "echo default", which meant a cancelled launcher
# branch prompt silently created a worktree on the default branch name.
#
# Args: $1 — label shown to the user; $2 — default value used on empty input.
# Returns: 0 on submit (including empty submit); non-zero on cancellation.
#   Prints the resolved value to stdout on success; nothing on cancel.
_core_prompt_input() {
    local label="$1" default="$2"
    if _core_prompt_use_gum; then
        local out rc
        out=$(gum input --placeholder "$default" --prompt "$label > ")
        rc=$?
        (( rc != 0 )) && return $rc
        echo "${out:-$default}"
        return 0
    fi
    local val=""
    read -r "val?$label [$default]: " || return $?
    echo "${val:-$default}"
}

# Prompt for a yes/no confirmation. Default is no — empty input is treated as
# rejection so unattended runs fail closed.
#
# Args: $1 — label shown to the user.
# Returns: 0 on yes (input begins with y or Y); 1 otherwise.
_core_prompt_confirm() {
    local label="$1"
    if _core_prompt_use_gum; then
        gum confirm "$label"
        return $?
    fi
    local ans=""
    read -r "ans?$label [y/N]: "
    [[ "$ans" =~ ^[yY] ]]
}

# Render a numbered list of items to stderr — helper for _core_prompt_choose's
# fallback path. Kept separate to keep _core_prompt_choose under the 25-line
# cap (matches the _core_style_table_print_row precedent in style.zsh).
#
# Args: $@ — items to render, one per line, prefixed with their 1-based index.
# Returns: 0 always; output goes to stderr so the chosen value (stdout) stays
#   pipeable.
_core_prompt_choose_render_list() {
    local index=1 item
    for item in "$@"; do
        printf '  %d) %s\n' "$index" "$item" >&2
        ((index++))
    done
}

# Prompt the user to pick one of the supplied items. Echoes the chosen item
# to stdout.
#
# Args: $1 — label shown to the user; $2..$N — items to choose from.
# Returns: 0 on a valid pick; 1 if the input is non-numeric, less than 1, or
#   greater than the number of items.
_core_prompt_choose() {
    local label="$1"
    shift
    if _core_prompt_use_gum; then
        printf '%s\n' "$@" | gum choose --header "$label"
        return $?
    fi
    echo "$label" >&2
    _core_prompt_choose_render_list "$@"
    local choice=""
    read -r "choice?Selection: "
    [[ "$choice" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= $# )) || return 1
    echo "${@[choice]}"
}
