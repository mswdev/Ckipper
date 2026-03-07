# ── Worktree Manager ──────────────────────────────────────────────
# Usage:
#   w <project> <branch-name>                   cd to worktree (creates if needed)
#   w <project> <branch-name> <cmd>             run command in worktree (e.g. claude)
#   w <project> <branch-name> --auto            run Claude in Docker (skip-permissions)
#   w <project> <branch-name> --auto --firewall same as above + egress firewall
#   w --list                                    list all worktrees
#   w --rm <project> <branch-name>              remove worktree + delete branch
#   w --rebuild-image                           rebuild claude-dev Docker image
#
# <project> is a path relative to ~/Developer (e.g. "Whmoro/orderguard", "my-app")
#
# ── CUSTOMIZATION ────────────────────────────────────────────────
# 1. MCP MOUNTS: Search for "MCP dependencies" below and add/remove/change
#    volume mounts based on your own MCP servers that reference local files.
#    Mount at the exact same host path so MCP configs work without modification.
#
# 2. PORTS: Change the "ports" array to match your dev server ports.
#
# 3. BASE BRANCH: Worktrees are created from origin/develop. Change "develop"
#    if your default branch is different (e.g. main).
# ─────────────────────────────────────────────────────────────────

_w_build_image() {
    local docker_dir="$HOME/.claude/docker"
    if [[ ! -f "$docker_dir/Dockerfile" ]]; then
        echo "Dockerfile not found: $docker_dir/Dockerfile"
        return 1
    fi
    echo "Building claude-dev Docker image..."
    docker build -t claude-dev "$docker_dir"
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
                local branch="${rel##*/}"
                local project="${rel%/*}"
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
        (cd "$projects_dir/$project" && git worktree remove $force_flag "$wt_path" && git branch -D "$worktree" 2>/dev/null)
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
        return $?
    fi

    # -- Normal usage: w <project> <worktree> [--auto [--firewall]] [command...] --
    local project="$1"
    local worktree="$2"
    shift 2 2>/dev/null

    # Parse flags
    local auto_mode=0
    local firewall_mode=0
    local command=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auto) auto_mode=1; shift ;;
            --firewall) firewall_mode=1; shift ;;
            *) command+=("$1"); shift ;;
        esac
    done

    if [[ -z "$project" || -z "$worktree" ]]; then
        echo "Usage: w <project> <worktree> [--auto [--firewall]] [command...]"
        echo "       w --list"
        echo "       w --rm <project> <worktree>"
        echo "       w --rebuild-image"
        echo ""
        echo "Flags:"
        echo "  --auto       Run Claude in Docker with --dangerously-skip-permissions"
        echo "  --firewall   Add egress firewall (only with --auto)"
        return 1
    fi

    # Validate flag combinations
    if [[ $firewall_mode -eq 1 && $auto_mode -eq 0 ]]; then
        echo "Error: --firewall requires --auto"
        return 1
    fi

    if [[ ! -d "$projects_dir/$project" ]]; then
        echo "Project not found: $projects_dir/$project"
        return 1
    fi

    # Find existing worktree
    local wt_path=""
    if [[ -d "$worktrees_dir/$project/$worktree" ]]; then
        wt_path="$worktrees_dir/$project/$worktree"
    fi

    # Create if it doesn't exist
    if [[ -z "$wt_path" ]]; then
        echo "Creating worktree: $worktree (from develop)"
        mkdir -p "$worktrees_dir/$project"
        wt_path="$worktrees_dir/$project/$worktree"
        (cd "$projects_dir/$project" && git fetch origin develop && \
            if git show-ref --verify --quiet "refs/heads/$worktree"; then
                echo "Using existing branch: $worktree"
                git worktree add "$wt_path" "$worktree"
            else
                git worktree add "$wt_path" -b "$worktree" origin/develop
            fi
        ) || {
            # Check if branch is already checked out in main repo
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
        (cd "$wt_path" && npm install)

        # Copy .env files from main project
        for env_file in $(find "$projects_dir/$project" -maxdepth 2 -name ".env" -not -path "*/node_modules/*"); do
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

    # -- Auto mode: run Claude in Docker --
    if [[ $auto_mode -eq 1 ]]; then
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
        if ! docker image inspect claude-dev > /dev/null 2>&1; then
            _w_build_image || return 1
        fi

        # Ensure .claude.json exists (Docker would mount as directory if missing)
        [[ -f "$HOME/.claude.json" ]] || echo '{}' > "$HOME/.claude.json"

        # Extract credentials from macOS Keychain (Claude stores auth there, not on disk)
        local claude_creds
        claude_creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || true

        # Extract GitHub token from .claude.json for gh CLI auth
        local gh_token
        gh_token=$(jq -r '.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN // empty' "$HOME/.claude.json" 2>/dev/null) || true

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
            # Mount SSH keys for git/plugin access (read-only)
            -v "$HOME/.ssh:/home/claude/.ssh:ro"
            # ── MCP dependencies ──────────────────────────────────────
            # Add read-only mounts for any MCP servers that reference local files.
            # Mount at the exact same host path so MCP configs work unchanged.
            # Remove or change these lines based on YOUR MCP setup:
            # -v "$HOME/Developer/Vibma:$HOME/Developer/Vibma:ro"
            # -v "$HOME/Developer/tailwindplus-data.json:$HOME/Developer/tailwindplus-data.json:ro"
            # ──────────────────────────────────────────────────────────
        )

        # Pass Keychain credentials to container
        if [[ -n "$claude_creds" ]]; then
            docker_args+=( -e "CLAUDE_CREDENTIALS=$claude_creds" )
        else
            echo "  Warning: Could not extract Claude credentials from Keychain"
        fi

        # Pass GitHub token for gh CLI auth
        if [[ -n "$gh_token" ]]; then
            docker_args+=( -e "GH_TOKEN=$gh_token" )
        fi

        # Port forwarding for dev servers (skip ports already in use)
        # ── CUSTOMIZE: change these ports to match your dev servers ──
        local -a ports=(3000 3030 6006)
        for port in "${ports[@]}"; do
            if ! lsof -i :"$port" -P -n &>/dev/null; then
                docker_args+=( -p "127.0.0.1:$port:$port" )
            else
                echo "  Port $port in use, skipping"
            fi
        done

        # Add firewall capability if requested
        if [[ $firewall_mode -eq 1 ]]; then
            docker_args+=( --cap-add=NET_ADMIN -e ENABLE_FIREWALL=1 )
        fi

        docker_args+=( claude-dev )
        local mode_label="auto mode"
        [[ $firewall_mode -eq 1 ]] && mode_label+=", firewall enabled"
        echo "Starting Claude in Docker ($mode_label)..."
        echo "  Worktree: $wt_path"
        echo "  Ports: ${ports[*]}"

        # Snapshot .git/config before session (detect tampering after)
        local git_config="$projects_dir/$project/.git/config"
        local git_config_hash=""
        [[ -f "$git_config" ]] && git_config_hash=$(shasum -a 256 "$git_config" | cut -d' ' -f1)

        "${docker_args[@]}"
        local exit_code=$?

        # Post-session: warn if .git/config was modified
        if [[ -n "$git_config_hash" && -f "$git_config" ]]; then
            local new_hash=$(shasum -a 256 "$git_config" | cut -d' ' -f1)
            if [[ "$git_config_hash" != "$new_hash" ]]; then
                echo ""
                echo "WARNING: .git/config was modified during the Docker session!"
                echo "Review changes: git -C $projects_dir/$project config --local --list"
            fi
        fi

        return $exit_code
    fi

    # -- Normal mode: execute command or cd --
    if [[ ${#command[@]} -eq 0 ]]; then
        cd "$wt_path"
    else
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

if [[ ! -f ~/.zsh/completions/_w ]] || true; then
    cat > ~/.zsh/completions/_w << 'COMPEOF'
#compdef w

_w() {
    local projects_dir="$HOME/Developer"
    local worktrees_dir="$HOME/Developer/.worktrees"

    _arguments -C \
        '(--rm)--list[List all worktrees]' \
        '(--list)--rm[Remove a worktree]' \
        '--rebuild-image[Rebuild claude-dev Docker image]' \
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
                '--auto:Run Claude in Docker (skip-permissions)'
                '--firewall:Add egress firewall (requires --auto)'
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
