#!/usr/bin/env zsh
# Bare-`ckipper` interactive launcher menu.
#
# When a user types `ck` or `ckipper` with no arguments, this module renders
# a banner + numbered menu and dispatches the chosen entry to the matching
# handler. Each menu entry is a thin wrapper around an existing top-level
# command (so the launcher is purely a discoverability surface, never the
# canonical implementation of any action).
#
# Depends on:
#   - lib/core/style.zsh   (`_core_style_header`)
#   - lib/core/prompt.zsh  (`_core_prompt_choose`, `_core_prompt_input`)
#   - lib/run/dispatcher.zsh           (`_ckipper_run`, for the run option)
#   - lib/worktree/dispatcher.zsh      (`_ckipper_worktree_dispatch`)
#   - lib/account/dispatcher.zsh       (`_ckipper_account_dispatch`)
#   - lib/config/dispatcher.zsh        (`_ckipper_config_dispatch`)
#   - lib/setup/dispatcher.zsh         (`_ckipper_setup`)
#   - lib/account/doctor.zsh           (`_ckipper_doctor`)

# Menu options shown by `_ckipper_launcher_menu`. The order is load-bearing:
# `_ckipper_launcher_route` matches on the human-readable label, and tests
# rely on "Quit" being the 8th (and last) entry.
typeset -gra _CKIPPER_LAUNCHER_OPTIONS=(
    "Run Claude on a worktree"
    "List worktrees"
    "List accounts"
    "Add an account"
    "Run setup wizard"
    "Edit config"
    "Run doctor"
    "Quit"
)

# `find -maxdepth` value for project discovery. Three levels covers the common
# layouts (`~/Developer/<repo>`, `~/Developer/<org>/<repo>`,
# `~/Developer/<group>/<org>/<repo>`) without scanning entire user homedirs.
readonly _CKIPPER_LAUNCHER_PROJECTS_MAXDEPTH=3

# Print the launcher banner: a styled "Ckipper" header, the product tagline,
# and a trailing blank line that separates the banner from whatever prompt or
# table the active menu entry renders next.
#
# Returns: 0 always.
_ckipper_launcher_banner() {
    _core_style_header "Ckipper"
    echo "Multi-account Claude Code manager"
    echo ""
}

# Render the launcher: banner, then a numbered choice prompt over
# `_CKIPPER_LAUNCHER_OPTIONS`. The user's pick is forwarded to the route
# dispatcher, which is the single function responsible for mapping menu
# labels to handlers.
#
# Returns: the route handler's exit status; 1 when the user cancels the
#   choose prompt (EOF, non-numeric input, or out-of-range index).
_ckipper_launcher_menu() {
    _ckipper_launcher_banner
    local choice
    choice=$(_core_prompt_choose "What would you like to do?" \
        "${_CKIPPER_LAUNCHER_OPTIONS[@]}")
    [[ -z "$choice" ]] && return 1
    _ckipper_launcher_route "$choice"
}

# Map a menu label to its handler. Each arm delegates to a top-level command
# (or a launcher-local helper for the multi-step "Run Claude on a worktree"
# flow); the launcher itself owns no orchestration logic beyond this case.
#
# Args: $1 — menu label (must match an entry in `_CKIPPER_LAUNCHER_OPTIONS`).
# Returns: the dispatched handler's exit status; 1 on an unknown label.
_ckipper_launcher_route() {
    local choice="$1"
    case "$choice" in
        "Run Claude on a worktree") _ckipper_launcher_route_run ;;
        "List worktrees")           _ckipper_worktree_dispatch list ;;
        "List accounts")            _ckipper_account_dispatch list ;;
        "Add an account")           _ckipper_account_dispatch add ;;
        "Run setup wizard")         _ckipper_setup ;;
        "Edit config")              _ckipper_config_dispatch edit ;;
        "Run doctor")               _ckipper_doctor ;;
        "Quit")                     return 0 ;;
        *)                          return 1 ;;
    esac
}

# Discover git repositories under `$CKIPPER_PROJECTS_DIR`, returning their
# paths relative to that root, one per line. Skips the `.worktrees/` subtree
# so transient worktree clones don't mask the canonical repo path.
#
# Returns: 0 always; prints relative project paths to stdout.
_ckipper_launcher_discover_projects() {
    local projects_dir="${CKIPPER_PROJECTS_DIR:-$HOME/Developer}"
    [[ -d "$projects_dir" ]] || return 0
    local dir repo_dir rel
    while IFS= read -r -d '' dir; do
        repo_dir="${dir:h}"
        rel="${repo_dir#$projects_dir/}"
        print -- "$rel"
    done < <(find "$projects_dir" -maxdepth "$_CKIPPER_LAUNCHER_PROJECTS_MAXDEPTH" \
        -name ".git" -type d -not -path "*/.worktrees/*" -print0 2>/dev/null)
}

# Run-Claude flow: enumerate projects under `$CKIPPER_PROJECTS_DIR`, prompt
# the user to pick one, prompt for a branch name, then forward to
# `_ckipper_run`. When no projects exist, abort with a stderr error rather
# than dumping into an empty-choice prompt.
#
# Returns: 0 on success; 1 when no projects are found or the user cancels
#   either prompt; otherwise the `_ckipper_run` exit status.
_ckipper_launcher_route_run() {
    local -a projects
    projects=( ${(f)"$(_ckipper_launcher_discover_projects)"} )
    if (( ${#projects} == 0 )); then
        echo "No projects found under \${CKIPPER_PROJECTS_DIR:-\$HOME/Developer}." >&2
        return 1
    fi
    local project branch
    project=$(_core_prompt_choose "Pick a project" "${projects[@]}")
    [[ -z "$project" ]] && return 1
    branch=$(_core_prompt_input "Branch name" "feature/dev")
    [[ -z "$branch" ]] && return 1
    _ckipper_run "$project" "$branch"
}
