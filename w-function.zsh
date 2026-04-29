#!/usr/bin/env zsh
# ── Worktree Manager ──────────────────────────────────────────────
# Usage:
#   w <project> <branch-name>                     cd to worktree (creates if needed)
#   w <project> <branch-name> <cmd>               run command in worktree (e.g. claude)
#   w <project> <branch-name> --docker             shell in Docker container
#   w <project> <branch-name> --docker claude      Claude in Docker (skip-permissions)
#   w <project> <branch-name> --docker --firewall  Docker + egress firewall
#   w --list                                       list all worktrees
#   w --rm <project> <branch-name>                 remove worktree + delete branch
#   w --rebuild-image                              rebuild ckipper-dev Docker image
#
# <project> is a path relative to ~/Developer (e.g. "Whmoro/orderguard", "my-app")
#
# ── CUSTOMIZATION ────────────────────────────────────────────────
# Edit ~/.ckipper/docker/w-config.zsh to customize:
#   - W_PORTS: dev server ports to forward
#   - W_EXTRA_VOLUMES: MCP server mounts and other volume mounts
#   - W_EXTRA_ENV: extra environment variables for the container
#
# BASE BRANCH: Worktrees are created from origin/develop. Change
# "develop" below if your default branch is different (e.g. main).
# ─────────────────────────────────────────────────────────────────

W_REPO_DIR="${0:A:h}"
source "$W_REPO_DIR/ckipper.zsh"
source "$W_REPO_DIR/lib/w/resolve-account.zsh"
source "$W_REPO_DIR/lib/w/build-image.zsh"
source "$W_REPO_DIR/lib/w/args.zsh"
source "$W_REPO_DIR/lib/w/worktree.zsh"
source "$W_REPO_DIR/lib/w/ports.zsh"
source "$W_REPO_DIR/lib/w/docker-mode.zsh"
source "$W_REPO_DIR/lib/w/normal-mode.zsh"

# Source user config (ports, extra volumes, extra env vars)
_w_config="${CKIPPER_DIR:-$HOME/.ckipper}/docker/w-config.zsh"
if [[ -f "$_w_config" ]]; then
    source "$_w_config"
fi
# Defaults if config is missing or incomplete
(( ${#W_PORTS[@]} == 0 )) && W_PORTS=(3000)
(( ${#W_EXTRA_VOLUMES[@]} == 0 )) && W_EXTRA_VOLUMES=()
(( ${#W_EXTRA_ENV[@]} == 0 )) && W_EXTRA_ENV=()

w() {
    _w_parse_args "$@"

    if [[ "$W_FLAG_LIST" = true ]]; then
        _w_list_worktrees
    elif [[ "$W_FLAG_REBUILD_IMAGE" = true ]]; then
        _w_build_image
        return $?
    elif [[ "$W_FLAG_RM" = true ]]; then
        _w_remove_worktree "$W_PROJECT" "$W_BRANCH"
        return $?
    elif [[ -z "$W_PROJECT" || -z "$W_BRANCH" ]]; then
        _w_usage
        return 1
    else
        if [[ "$W_FLAG_FIREWALL" = true && "$W_FLAG_DOCKER" = false ]]; then
            echo "Error: --firewall requires --docker"
            return 1
        fi
        _w_resolve_account || return $?
        _w_create_worktree "$W_PROJECT" "$W_BRANCH" || return $?
        if [[ "$W_FLAG_DOCKER" = true ]]; then
            _w_run_docker_mode
        else
            _w_run_normal_mode
        fi
    fi
}

# Print usage information for the w() command.
#
# Returns: 0 always.
_w_usage() {
    echo "Usage: w <project> <worktree> [--docker [--firewall] [cmd...]]"
    echo "       w <project> <worktree> [command...]"
    echo "       w --list"
    echo "       w --rm <project> <worktree>"
    echo "       w --rebuild-image"
    echo ""
    echo "Flags:"
    echo "  --docker            Run in Docker container (shell by default, or specify command)"
    echo "  --firewall          Add egress firewall (only with --docker)"
    echo "  --account <name>    Use a specific Ckipper account (default: registered default or \$CLAUDE_CONFIG_DIR)"
    echo ""
    echo "Examples:"
    echo "  w myorg/app feature --docker              # shell in container"
    echo "  w myorg/app feature --docker claude        # Claude in container"
    echo "  w myorg/app feature --docker --firewall    # shell + firewall"
}

# -- Tab completion for w --
# Ensure completions directory is in fpath
[[ -d ~/.zsh/completions ]] || mkdir -p ~/.zsh/completions
fpath=(~/.zsh/completions $fpath)

if [[ ! -f ~/.zsh/completions/_w ]]; then
    cat > ~/.zsh/completions/_w << 'COMPEOF'
#compdef w

_w() {
    local projects_dir="$HOME/Developer"
    local worktrees_dir="$HOME/Developer/.worktrees"

    _arguments -C \
        '(--rm)--list[List all worktrees]' \
        '(--list)--rm[Remove a worktree]' \
        '--rebuild-image[Rebuild ckipper-dev Docker image]' \
        '--account[Ckipper account to use]:account name:' \
        '1: :->project' \
        '2: :->worktree' \
        '3: :->command' \
        '*:: :->command_args' \
        && return 0

    case $state in
        project)
            local -a projects
            for dir in $(find "$projects_dir" -maxdepth 3 -name ".git" -type d -not -path "*/.worktrees/*" 2>/dev/null); do
                local repo_dir="${dir:h}"
                local rel="${repo_dir#$projects_dir/}"
                projects+=("$rel")
            done
            _describe -t projects 'project' projects && return 0
            ;;
        worktree)
            local project="${words[2]}"
            [[ -z "$project" ]] && return 0
            local -a worktrees
            if [[ -d "$worktrees_dir/$project" ]]; then
                for wt in $worktrees_dir/$project/*(N/); do
                    worktrees+=(${wt:t})
                done
            fi
            if (( ${#worktrees} > 0 )); then
                _describe -t worktrees 'existing worktree' worktrees
            else
                _message 'new worktree branch name'
            fi
            ;;
        command)
            local -a common_commands
            common_commands=(
                'claude:Start Claude Code session'
                '--docker:Run in Docker container (shell or specify command)'
                '--firewall:Add egress firewall (requires --docker)'
                'code:Open in VS Code'
                'npm:Run npm commands'
            )
            _describe -t commands 'command' common_commands
            _command_names -e
            ;;
        command_args)
            words=(${words[4,-1]})
            CURRENT=$((CURRENT - 3))
            _normal
            ;;
    esac
}

_w "$@"
COMPEOF
fi
