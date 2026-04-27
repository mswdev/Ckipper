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

# Source user config (ports, extra volumes, extra env vars)
_w_config="${CKIPPER_DIR:-$HOME/.ckipper}/docker/w-config.zsh"
if [[ -f "$_w_config" ]]; then
    source "$_w_config"
fi
# Defaults if config is missing or incomplete
(( ${#W_PORTS[@]} == 0 )) && W_PORTS=(3000)
(( ${#W_EXTRA_VOLUMES[@]} == 0 )) && W_EXTRA_VOLUMES=()
(( ${#W_EXTRA_ENV[@]} == 0 )) && W_EXTRA_ENV=()

_w_build_image() {
    local docker_dir="${CKIPPER_DIR:-$HOME/.ckipper}/docker"
    if [[ ! -f "$docker_dir/Dockerfile" ]]; then
        echo "Dockerfile not found: $docker_dir/Dockerfile"
        return 1
    fi
    echo "Building ckipper-dev Docker image..."
    docker build --build-arg "CACHEBUST=$(date +%s)" -t ckipper-dev "$docker_dir"
}

_w_resolve_account() {
    local cli_account="$1"
    if [[ -n "$cli_account" ]]; then
        echo "$cli_account"; return 0
    fi
    if [[ -n "$CLAUDE_CONFIG_DIR" && -f "$CKIPPER_REGISTRY" ]]; then
        local matched
        matched=$(jq -r --arg d "$CLAUDE_CONFIG_DIR" \
            '.accounts | to_entries[] | select(.value.config_dir == $d) | .key' \
            "$CKIPPER_REGISTRY" | head -1)
        [[ -n "$matched" ]] && { echo "$matched"; return 0; }
    fi
    if [[ -f "$CKIPPER_REGISTRY" ]]; then
        local default
        default=$(jq -r '.default // ""' "$CKIPPER_REGISTRY")
        [[ -n "$default" ]] && { echo "$default"; return 0; }
    fi
    return 0
}

w() {
    local projects_dir="$HOME/Developer"
    local worktrees_dir="$HOME/Developer/.worktrees"

    # -- List all worktrees --
    if [[ "$1" == "--list" ]]; then
        echo "=== All Worktrees ==="
        if [[ -d "$worktrees_dir" ]]; then
            local current_project=""
            find "$worktrees_dir" -name ".git" -type f -not -path "*/node_modules/*" 2>/dev/null | sort | while IFS= read -r gitfile; do
                local wt_dir="${gitfile:h}"
                local rel="${wt_dir#$worktrees_dir/}"
                # Extract project (first two path segments) and branch (rest)
                local project="${rel%%/*}"
                local after_first="${rel#*/}"
                if [[ "$after_first" == "$rel" ]]; then
                    continue  # malformed path
                fi
                # Check if second segment is a sub-project (e.g. Whmoro/orderguard)
                local second="${after_first%%/*}"
                local rest="${after_first#*/}"
                if [[ -d "$projects_dir/$project/$second/.git" ]]; then
                    project="$project/$second"
                    local branch="$rest"
                else
                    local branch="$after_first"
                fi
                if [[ "$project" != "$current_project" ]]; then
                    current_project="$project"
                    echo "\n[$project]"
                fi
                echo "  • $branch"
            done
        fi
        return 0
    fi

    # -- Rebuild Docker image --
    if [[ "$1" == "--rebuild-image" ]]; then
        _w_build_image
        return $?
    fi

    # -- Remove a worktree --
    if [[ "$1" == "--rm" ]]; then
        shift
        local force_flag=""
        if [[ "$1" == "--force" || "$1" == "-f" ]]; then
            force_flag="--force"
            shift
        fi
        local project="$1"
        local worktree="$2"
        if [[ -z "$project" || -z "$worktree" ]]; then
            echo "Usage: w --rm [--force] <project> <worktree>"
            return 1
        fi
        local wt_path="$worktrees_dir/$project/$worktree"
        if [[ ! -d "$wt_path" ]]; then
            echo "Worktree not found: $wt_path"
            return 1
        fi
        (cd "$projects_dir/$project" && git worktree remove $force_flag "$wt_path" && git branch -D "$worktree" 2>/dev/null) || {
            echo "Failed to remove worktree. Use --force if it has uncommitted changes."
            return 1
        }
        # Clean up Claude Code settings for removed worktree
        WT_PATH="$wt_path" python3 -c "
import json, os
claude_config = os.path.expanduser('~/.claude.json')
wt_path = os.environ['WT_PATH']
with open(claude_config, 'r') as f:
    d = json.load(f)
if wt_path in d.get('projects', {}):
    del d['projects'][wt_path]
    with open(claude_config, 'w') as f:
        json.dump(d, f)
    print(f'Removed worktree project entry from ~/.claude.json')
" 2>/dev/null
        return 0
    fi

    # -- Normal usage: w <project> <worktree> [--docker [--firewall] [cmd...]] [command...] --
    local project="$1"
    local worktree="$2"
    shift 2 2>/dev/null

    # Parse flags
    local docker_mode=0
    local firewall_mode=0
    local cli_account=""
    local command=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --docker)   docker_mode=1; shift ;;
            --firewall) firewall_mode=1; shift ;;
            --account)  cli_account="$2"; shift 2 ;;
            *)          command+=("$1"); shift ;;
        esac
    done

    if [[ -z "$project" || -z "$worktree" ]]; then
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
        return 1
    fi

    # Validate flag combinations
    if [[ $firewall_mode -eq 1 && $docker_mode -eq 0 ]]; then
        echo "Error: --firewall requires --docker"
        return 1
    fi

    # Resolve active Ckipper account (no legacy fallback — error if none).
    local active_account
    active_account=$(_w_resolve_account "$cli_account")
    if [[ -z "$active_account" ]]; then
        echo "Error: no account selected and no default registered."
        echo "Run: ckipper list   (then: ckipper default <name>, or pass --account <name>)"
        return 1
    fi
    local active_config_dir
    active_config_dir=$(jq -r --arg n "$active_account" '.accounts[$n].config_dir // empty' "$CKIPPER_REGISTRY" 2>/dev/null)
    local active_keychain_service
    active_keychain_service=$(jq -r --arg n "$active_account" '.accounts[$n].keychain_service // empty' "$CKIPPER_REGISTRY" 2>/dev/null)
    if [[ -z "$active_config_dir" ]]; then
        echo "Error: account '$active_account' is not registered. Run: ckipper list"
        return 1
    fi

    if [[ ! -d "$projects_dir/$project" ]]; then
        echo "Project not found: $projects_dir/$project"
        return 1
    fi

    # Find existing worktree
    local wt_path=""
    if [[ -d "$worktrees_dir/$project/$worktree" ]]; then
        if [[ ! -f "$worktrees_dir/$project/$worktree/.git" ]]; then
            echo "Error: $worktrees_dir/$project/$worktree exists but is not a valid worktree."
            echo "Remove it manually or use a different branch name."
            return 1
        fi
        wt_path="$worktrees_dir/$project/$worktree"
    fi

    # Create if it doesn't exist
    if [[ -z "$wt_path" ]]; then
        echo "Creating worktree: $worktree"
        mkdir -p "$worktrees_dir/$project"
        wt_path="$worktrees_dir/$project/$worktree"
        # Fetch latest develop + target branch (target may not exist on remote)
        (cd "$projects_dir/$project" && git fetch origin develop) || {
            echo "Failed to fetch from origin. Check your network connection and that 'develop' exists on the remote."
            return 1
        }
        (cd "$projects_dir/$project" && git fetch origin "$worktree" 2>/dev/null) || true
        # Create the worktree
        (cd "$projects_dir/$project" && \
            if git show-ref --verify --quiet "refs/heads/$worktree"; then
                echo "Using existing local branch: $worktree"
                git worktree add "$wt_path" "$worktree"
            elif git show-ref --verify --quiet "refs/remotes/origin/$worktree"; then
                echo "Tracking remote branch: origin/$worktree"
                git worktree add "$wt_path" -b "$worktree" "origin/$worktree"
            else
                echo "Creating new branch from origin/develop"
                git worktree add "$wt_path" -b "$worktree" origin/develop
            fi
        ) || {
            local current_branch
            current_branch=$(cd "$projects_dir/$project" && git branch --show-current 2>/dev/null)
            if [[ "$current_branch" == "$worktree" ]]; then
                echo "Failed: branch '$worktree' is currently checked out in the main repo."
                echo "Switch the main repo to a different branch first:"
                echo "  cd $projects_dir/$project && git checkout develop"
            else
                echo "Failed to create worktree"
            fi
            return 1
        }
        echo "Installing dependencies..."
        (cd "$wt_path" && npm install) || echo "Warning: npm install failed. You may need to run it manually."

        # Copy .env files from main project (includes .env.local, .env.development, etc. but not .env.example)
        for env_file in $(find "$projects_dir/$project" -maxdepth 3 -name ".env*" -not -name "*.example" -not -path "*/node_modules/*" -not -path "*/.git/*"); do
            local rel_path="${env_file#$projects_dir/$project/}"
            local dest_dir="$wt_path/$(dirname "$rel_path")"
            mkdir -p "$dest_dir"
            cp "$env_file" "$dest_dir/"
            echo "Copied $rel_path"
        done

        # Sync Claude Code project settings (disabled MCPs, permissions, etc.)
        local main_project_path="$projects_dir/$project"
        MAIN_PATH="$main_project_path" WT_PATH="$wt_path" python3 -c "
import json, os
claude_config = os.path.expanduser('~/.claude.json')
main_path = os.environ['MAIN_PATH']
wt_path = os.environ['WT_PATH']
with open(claude_config, 'r') as f:
    d = json.load(f)
main = d.get('projects', {}).get(main_path, {})
if main:
    keys = ['disabledMcpServers', 'enabledMcpjsonServers', 'disabledMcpjsonServers',
            'allowedTools', 'hasTrustDialogAccepted', 'hasClaudeMdExternalIncludesApproved',
            'hasClaudeMdExternalIncludesWarningShown', 'hasCompletedProjectOnboarding']
    wt = d.setdefault('projects', {}).setdefault(wt_path, {})
    for k in keys:
        if k in main:
            wt[k] = main[k]
    with open(claude_config, 'w') as f:
        json.dump(d, f)
    print('Synced Claude Code settings')
else:
    print('No Claude settings found for main project')
" 2>/dev/null
    fi

    # -- Docker mode: run in containerized environment --
    if [[ $docker_mode -eq 1 ]]; then
        # Ensure Docker is available
        if ! command -v docker &>/dev/null; then
            echo "Error: docker is not installed or not in PATH"
            return 1
        fi
        if ! docker info &>/dev/null 2>&1; then
            echo "Error: Docker daemon is not running. Start Docker Desktop first."
            return 1
        fi

        # Ensure Docker image exists
        if ! docker image inspect ckipper-dev > /dev/null 2>&1; then
            _w_build_image || return 1
        fi

        # Ensure .claude.json exists (Docker would mount as directory if missing)
        [[ -f "$HOME/.claude.json" ]] || echo '{}' > "$HOME/.claude.json"

        # Extract credentials from macOS Keychain (Claude stores auth there, not on disk)
        local claude_creds
        claude_creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || true

        # Extract GitHub token for gh CLI auth inside container
        # Try .claude.json MCP config first, then fall back to host's gh CLI auth
        local gh_token
        gh_token=$(jq -r '.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN // empty' "$HOME/.claude.json" 2>/dev/null) || true
        if [[ -z "$gh_token" ]] && command -v gh &>/dev/null; then
            gh_token=$(gh auth token 2>/dev/null) || true
        fi

        local docker_args=(
            docker run --rm -it
            -e TERM="${TERM:-xterm-256color}"
            # Mount worktree as workspace
            -v "$wt_path:/workspace:rw"
            # Mount main repo .git at same absolute path (resolves worktree .git file)
            -v "$projects_dir/$project/.git:$projects_dir/$project/.git:rw"
            # Mount Claude auth and config
            -v "$HOME/.claude:/home/claude/.claude:rw"
            -v "$HOME/.claude.json:/home/claude/.claude-host.json:ro"
            # Mount .claude at host path too — plugins store absolute host paths
            # (e.g. /Users/<user>/.claude/plugins/...) that don't resolve at
            # the container's /home/claude/.claude. This dual mount makes both work.
            -v "$HOME/.claude:$HOME/.claude:rw"
            # Mount SSH config as staging copy (sanitized by entrypoint)
            -v "$HOME/.ssh:/home/claude/.ssh-host:ro"
            # Forward host's SSH agent (Docker Desktop for Mac).
            # Lets the container authenticate using the host's SSH keys
            # without copying them. Works with 1Password and macOS Keychain agents.
            -v /run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock
            -e SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock
            --group-add 0  # SSH agent socket is root:root 0660; claude user needs group access
            # ── Credentials tmpfs ──────────────────────────────────
            # Entrypoint writes credentials here instead of the host-mounted
            # ~/.claude, so they only exist in container memory.
            --tmpfs /tmp/claude-creds:mode=700,uid=1000,gid=1000,size=1m
            # ──────────────────────────────────────────────────────────
            # ── uvx/uv cache & tools ───────────────────────────────────
            # Named volumes persist Python packages and pre-installed tool
            # environments across container restarts. The entrypoint pre-installs
            # uvx-based MCP servers into .uv-tools/ so they start instantly.
            -v "claude-uv-cache:/home/claude/.cache/uv"
            -v "claude-uv-tools:/home/claude/.uv-tools"
            -e "UV_TOOL_DIR=/home/claude/.uv-tools/envs"
            -e "UV_TOOL_BIN_DIR=/home/claude/.uv-tools/bin"
            -e "UV_PYTHON_INSTALL_DIR=/home/claude/.uv-tools/python"
            # ──────────────────────────────────────────────────────────
        )

        # Add user-configured extra volumes from w-config.zsh
        for vol in "${W_EXTRA_VOLUMES[@]}"; do
            docker_args+=( -v "$vol" )
        done

        # Pass Keychain credentials to container
        if [[ -n "$claude_creds" ]]; then
            docker_args+=( -e "CLAUDE_CREDENTIALS=$claude_creds" )
        else
            echo "  Warning: Could not extract Claude credentials from Keychain"
        fi

        # Pass GitHub token for gh CLI auth
        if [[ -n "$gh_token" ]]; then
            docker_args+=( -e "GH_TOKEN=$gh_token" )
        else
            echo "  Warning: No GitHub token found (gh commands won't work in container)"
        fi

        # Add user-configured extra env vars from w-config.zsh
        for env_var in "${W_EXTRA_ENV[@]}"; do
            docker_args+=( -e "$env_var" )
        done

        # Port forwarding for dev servers (try fallback host ports if taken)
        local -a ports=("${W_PORTS[@]}")
        local max_fallback=10  # try up to 10 alternative host ports
        for port in "${ports[@]}"; do
            local host_port=$port
            local bound=0
            for (( i=0; i<max_fallback; i++ )); do
                if ! lsof -i :"$host_port" -P -n &>/dev/null; then
                    docker_args+=( -p "127.0.0.1:$host_port:$port" )
                    bound=1
                    if (( host_port != port )); then
                        echo "  Port $port mapped to host:$host_port (original in use)"
                    fi
                    break
                fi
                (( host_port++ ))
            done
            if (( !bound )); then
                echo "  Port $port: no available host port found ($port-$((port+max_fallback-1)) all in use)"
            fi
        done

        # Add firewall capability if requested
        if [[ $firewall_mode -eq 1 ]]; then
            docker_args+=( --cap-add=NET_ADMIN -e ENABLE_FIREWALL=1 )
        fi

        docker_args+=( ckipper-dev )

        # If "claude" is the command, expand it to the full skip-permissions invocation
        # and auto-name the session after the worktree branch
        if [[ ${#command[@]} -gt 0 && "${command[1]}" == "claude" ]]; then
            command=(claude --dangerously-skip-permissions "/rename $worktree")
        fi

        # Pass command to container (if any)
        if [[ ${#command[@]} -gt 0 ]]; then
            docker_args+=( "${command[@]}" )
        fi

        local mode_label="Docker"
        [[ ${#command[@]} -gt 0 ]] && mode_label+=": ${command[1]}"
        [[ $firewall_mode -eq 1 ]] && mode_label+=", firewall"
        echo "Starting $mode_label..."
        echo "  Worktree: $wt_path"
        echo "  Ports: ${ports[*]}"

        # Snapshot .git/config before session (detect tampering after)
        local git_config="$projects_dir/$project/.git/config"
        local git_config_hash=""
        [[ -f "$git_config" ]] && git_config_hash=$(shasum -a 256 "$git_config" | cut -d' ' -f1)

        # Snapshot worktree metadata before session (detect pruning damage)
        local git_worktrees_dir="$projects_dir/$project/.git/worktrees"
        local -a worktrees_before=()
        if [[ -d "$git_worktrees_dir" ]]; then
            worktrees_before=( "$git_worktrees_dir"/*(N/:t) )
        fi

        "${docker_args[@]}"
        local exit_code=$?

        # Post-session: clean up dangling credentials symlink left by tmpfs credential isolation.
        # Only remove when no other ckipper-dev containers are running — parallel sessions
        # share the ~/.claude bind mount, so deleting the symlink would break their credentials.
        if [[ -L "$HOME/.claude/.credentials.json" ]]; then
            if ! docker ps --filter ancestor=ckipper-dev --quiet 2>/dev/null | grep -q .; then
                rm -f "$HOME/.claude/.credentials.json"
            fi
        fi

        # Post-session: warn if .git/config was modified
        if [[ -n "$git_config_hash" && -f "$git_config" ]]; then
            local new_hash=$(shasum -a 256 "$git_config" | cut -d' ' -f1)
            if [[ "$git_config_hash" != "$new_hash" ]]; then
                echo ""
                echo "WARNING: .git/config was modified during the Docker session!"
                echo "Review changes: git -C $projects_dir/$project config --local --list"
            fi
        fi

        # Post-session: check if any worktree metadata was destroyed
        if [[ ${#worktrees_before[@]} -gt 0 ]]; then
            local -a worktrees_after=()
            if [[ -d "$git_worktrees_dir" ]]; then
                worktrees_after=( "$git_worktrees_dir"/*(N/:t) )
            fi
            local -a missing=()
            for wt in "${worktrees_before[@]}"; do
                if [[ ! " ${worktrees_after[*]} " =~ " $wt " ]]; then
                    missing+=("$wt")
                fi
            done
            if [[ ${#missing[@]} -gt 0 ]]; then
                echo ""
                echo "CRITICAL: ${#missing[@]} worktree(s) had metadata destroyed during the Docker session!"
                echo "Missing worktrees: ${missing[*]}"
                echo ""
                echo "The working directories still exist on disk — only the .git/worktrees/ metadata was deleted."
                echo "To recover, re-register each worktree:"
                echo "  cd $projects_dir/$project"
                for wt in "${missing[@]}"; do
                    echo "  git worktree add <path-to-$wt> $wt"
                done
            fi
        fi

        return $exit_code
    fi

    # -- Normal mode: execute command or cd --
    if [[ ${#command[@]} -eq 0 ]]; then
        cd "$wt_path"
    else
        # If command is "claude", auto-name the session after the worktree branch
        if [[ "${command[1]}" == "claude" ]]; then
            command+=("/rename $worktree")
        fi
        local old_pwd="$PWD"
        cd "$wt_path"
        "${command[@]}"
        local exit_code=$?
        cd "$old_pwd"
        return $exit_code
    fi
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

# Source ckipper subcommand dispatcher (if deployed)
[[ -f "${CKIPPER_DIR:-$HOME/.ckipper}/docker/ckipper.zsh" ]] && \
    source "${CKIPPER_DIR:-$HOME/.ckipper}/docker/ckipper.zsh"
