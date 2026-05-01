#!/usr/bin/env zsh
# Wizard prerequisite checks for `ckipper setup`.
#
# Verifies the external tools the rest of Ckipper relies on are installed
# (gum for prompts, jq for JSON registry edits, docker for sandboxed worktrees)
# and offers to brew-install any that are missing.
#
# Depends on lib/core/prompt.zsh (`_core_prompt_confirm`); the orchestrator
# `_ckipper_setup_prereqs` is the entry point invoked by the setup wizard.

# Tools that must be on PATH before the setup wizard can proceed.
readonly _CKIPPER_SETUP_REQUIRED_TOOLS=(gum jq docker)

# Test whether a single command is on PATH.
#
# Args: $1 — name of the executable to probe.
# Returns: 0 if the executable is found; 1 if missing.
_ckipper_setup_prereq_check_one() {
    command -v "$1" >/dev/null 2>&1
}

# Print the subset of the supplied tool names that are not on PATH, one per
# line. Used by the orchestrator to decide whether installation is needed.
#
# Args: $@ — tool names to probe.
# Returns: 0 always; missing names are echoed to stdout.
_ckipper_setup_prereq_list_missing() {
    local tool
    for tool in "$@"; do
        _ckipper_setup_prereq_check_one "$tool" || echo "$tool"
    done
    return 0
}

# Prompt the user to brew-install the supplied missing tools. The "Missing
# tools:" notice is printed to stderr so callers piping stdout still see a
# clean tool list. Returns success without prompting when no tools are passed.
#
# Args: $@ — missing tool names. Empty input is treated as a no-op success.
# Returns: 0 if the user accepted and brew install succeeded (or no tools
#   passed); 1 if the user declined or brew install failed.
# Errors (stderr): "Missing tools: <space-separated list>" — when at least one
#   tool is supplied.
_ckipper_setup_prereq_install_missing() {
    (( $# == 0 )) && return 0
    echo "Missing tools: $*" >&2
    _core_prompt_confirm "Install with brew?" || return 1
    brew install "$@"
}

# Setup-wizard entry point: ensure every tool in
# `_CKIPPER_SETUP_REQUIRED_TOOLS` is on PATH, offering a brew install for any
# that are missing and re-checking afterwards. Stdout is reserved for the
# (rare) tool list; status messages flow through the helpers above.
#
# Returns: 0 if every required tool is present (either initially or after a
#   successful install); 1 if the user declined the install, brew install
#   failed, or some tools remain missing after the install attempt.
_ckipper_setup_prereqs() {
    local missing_blob
    missing_blob=$(_ckipper_setup_prereq_list_missing "${_CKIPPER_SETUP_REQUIRED_TOOLS[@]}")
    [[ -z "$missing_blob" ]] && return 0
    local -a missing=("${(@f)missing_blob}")
    _ckipper_setup_prereq_install_missing "${missing[@]}" || return 1
    missing_blob=$(_ckipper_setup_prereq_list_missing "${_CKIPPER_SETUP_REQUIRED_TOOLS[@]}")
    [[ -z "$missing_blob" ]]
}
