#!/usr/bin/env zsh
# Worktree-namespace dispatcher and help text.
#
# Routes `ckipper worktree <subcommand>` to the matching helper, prints
# overview/per-subcommand help, and suggests the closest subcommand on a
# typo via _core_fuzzy_suggest.

# Known worktree subcommands. Used both for routing and for fuzzy-suggest.
_CKIPPER_WORKTREE_SUBCOMMANDS=(run list rm rebuild-image help)

# Dispatch a `worktree` subcommand.
#
# Args:
#   $1     — subcommand name (run, list, rm, rebuild-image, help, -h, --help, or empty)
#   $2..$N — arguments forwarded to the subcommand handler
#
# Returns: subcommand exit status; 1 on unknown subcommand.
_ckipper_worktree_dispatch() {
    local cmd="$1"
    shift 2>/dev/null
    case "$cmd" in
        run|list|rm|rebuild-image)
            if [[ "$1" == "--help" || "$1" == "-h" ]]; then
                _ckipper_worktree_help_for "$cmd"
                return 0
            fi
            _ckipper_worktree_route "$cmd" "$@"
            ;;
        ""|help|-h|--help) _ckipper_worktree_help ;;
        *) _ckipper_worktree_unknown "$cmd"; return 1 ;;
    esac
}

# Route a known subcommand to its handler.
#
# Args:
#   $1     — subcommand name (run, list, rm, or rebuild-image)
#   $2..$N — arguments forwarded to the handler
#
# Returns: handler exit status.
_ckipper_worktree_route() {
    local cmd="$1"
    shift
    case "$cmd" in
        run)           _ckipper_worktree_run "$@" ;;
        list)          _ckipper_worktree_list_worktrees "$@" ;;
        rm)            _ckipper_worktree_route_rm "$@" ;;
        rebuild-image) _ckipper_worktree_build_image "$@" ;;
    esac
}

# Parse `rm` flags and dispatch to the remove helper.
#
# Args: $1..$N — `rm` arguments (flags + project + worktree).
#
# Returns: 0 on success; 1 if project or worktree is empty after parsing.
_ckipper_worktree_route_rm() {
    _ckipper_worktree_parse_rm_args "$@"
    if [[ -z "$CKIPPER_WT_PROJECT" || -z "$CKIPPER_WT_BRANCH" ]]; then
        _ckipper_worktree_help_for rm >&2
        return 1
    fi
    _ckipper_worktree_remove_worktree "$CKIPPER_WT_PROJECT" "$CKIPPER_WT_BRANCH"
}

# Print the closest-match suggestion (or a bare unknown-command line) and
# point the user at help. Always writes to stderr.
#
# Args: $1 — the unknown subcommand the user typed.
# Returns: 0 always.
_ckipper_worktree_unknown() {
    _core_unknown_command "$1" \
        "Run 'ckipper worktree help' for available commands." \
        "${_CKIPPER_WORKTREE_SUBCOMMANDS[@]}"
}

# Print the worktree-namespace usage summary.
#
# Returns: 0 always.
_ckipper_worktree_help() {
    _core_help_render "ckipper worktree — manage git worktrees and run Claude in them" \
        "" \
        "Usage:" \
        "  ckipper worktree run <project> <branch> [--docker [--firewall]] [--account <name>] [cmd...]" \
        "                                       Create-or-cd worktree, optionally launch in Docker" \
        "  ckipper worktree list                List all worktrees under CKIPPER_WORKTREES_DIR" \
        "  ckipper worktree rm [--force] <project> <branch>" \
        "                                       Remove worktree directory + delete branch" \
        "  ckipper worktree rebuild-image       Rebuild the ckipper-dev Docker image" \
        "" \
        "Short form: \`ckipper wt ...\` is equivalent." \
        "" \
        "Run \`ckipper worktree <subcommand> --help\` for per-subcommand details."
}

# Per-subcommand help text router.
#
# Args: $1 — subcommand name.
# Returns: 0 always.
_ckipper_worktree_help_for() {
    case "$1" in
        run)           _ckipper_worktree_help_text_run ;;
        list)          _ckipper_worktree_help_text_list ;;
        rm)            _ckipper_worktree_help_text_rm ;;
        rebuild-image) _ckipper_worktree_help_text_rebuild_image ;;
    esac
}

_ckipper_worktree_help_text_run() {
    _core_help_render "ckipper worktree run <project> <branch> [flags] [cmd...]" \
        "" \
        "Create-or-cd to a git worktree under CKIPPER_WORKTREES_DIR, then either drop" \
        "you in a shell or run a command. Without --docker, runs on the host." \
        "" \
        "Args:" \
        "  <project>           Path relative to CKIPPER_PROJECTS_DIR (e.g. myorg/app)" \
        "  <branch>            Worktree/branch name (creates from origin/HEAD if new)" \
        "  [cmd...]            Optional command to run in the worktree (e.g. \`claude\`)" \
        "" \
        "Flags:" \
        "  --docker            Run inside the ckipper-dev container (shell by default)" \
        "  --firewall          Add the egress firewall (requires --docker)" \
        "  --account <name>    Use a specific Ckipper account (default: registered" \
        "                      default, or value of \$CLAUDE_CONFIG_DIR if set)" \
        "" \
        "Examples:" \
        "  ckipper wt run myorg/app feature                       # cd to worktree" \
        "  ckipper wt run myorg/app feature claude                # claude on host" \
        "  ckipper wt run myorg/app feature --docker              # shell in container" \
        "  ckipper wt run myorg/app feature --docker claude       # claude in container" \
        "  ckipper wt run myorg/app feature --docker --firewall   # + egress firewall"
}

_ckipper_worktree_help_text_list() {
    _core_help_render "ckipper worktree list" \
        "" \
        "Print every worktree under CKIPPER_WORKTREES_DIR, grouped by project. Useful" \
        "for finding stale worktrees you forgot to remove."
}

_ckipper_worktree_help_text_rm() {
    _core_help_render "ckipper worktree rm [--force] <project> <branch>" \
        "" \
        "Remove a worktree directory and delete the matching branch. Refuses if the" \
        "worktree has uncommitted changes; pass --force (or -f) to override." \
        "" \
        "Args:" \
        "  <project>   Path relative to CKIPPER_PROJECTS_DIR" \
        "  <branch>    Worktree name to remove" \
        "" \
        "Flags:" \
        "  --force, -f Remove even if the worktree has uncommitted changes"
}

_ckipper_worktree_help_text_rebuild_image() {
    _core_help_render "ckipper worktree rebuild-image" \
        "" \
        "Rebuild the ckipper-dev Docker image (the one used by \`worktree run --docker\`)." \
        "Run this after editing the Dockerfile or pulling Ckipper updates that change" \
        "the entrypoint."
}
