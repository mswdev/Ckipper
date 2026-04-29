#!/usr/bin/env zsh
# Docker mode execution for w(). Builds docker run args and launches the container.

readonly SHASUM_BITS=256

# Run the worktree in a Docker container.
#
# Reads globals: W_WT_PATH, W_PROJECTS_DIR, W_PROJECT, W_BRANCH, W_COMMAND,
#   W_FLAG_FIREWALL, W_ACTIVE_ACCOUNT, W_ACTIVE_CONFIG_DIR,
#   W_ACTIVE_KEYCHAIN_SERVICE, W_PORTS, W_EXTRA_VOLUMES, W_EXTRA_ENV.
# Returns: exit code of the docker run invocation.
_w_run_docker_mode() {
    _w_docker_check_prerequisites || return 1

    [[ -f "$W_ACTIVE_CONFIG_DIR/.claude.json" ]] || echo '{}' > "$W_ACTIVE_CONFIG_DIR/.claude.json"

    _w_docker_validate_keychain || return 1

    local claude_creds gh_token
    claude_creds=$(_w_docker_extract_credentials) || return 1
    gh_token=$(_w_docker_extract_gh_token)

    local -a W_DOCKER_ARGS
    _w_docker_build_base_args
    _w_docker_add_optional_args "$claude_creds" "$gh_token"
    _w_resolve_ports
    [[ "$W_FLAG_FIREWALL" = true ]] && W_DOCKER_ARGS+=( --cap-add=NET_ADMIN -e ENABLE_FIREWALL=1 )

    W_DOCKER_ARGS+=( ckipper-dev )
    _w_docker_expand_command

    _w_docker_print_banner
    _w_docker_snapshot_and_run
}

# Validate Docker is installed and daemon is running.
#
# Returns: 0 if docker is available and running; 1 otherwise.
# Errors (stderr):
#   "Error: docker is not installed or not in PATH" — when docker binary is missing
#   "Error: Docker daemon is not running. Start Docker Desktop first." — when daemon is down
_w_docker_check_prerequisites() {
    if ! command -v docker &>/dev/null; then
        echo "Error: docker is not installed or not in PATH"
        return 1
    fi
    if ! docker info &>/dev/null 2>&1; then
        echo "Error: Docker daemon is not running. Start Docker Desktop first."
        return 1
    fi
    if ! docker image inspect ckipper-dev > /dev/null 2>&1; then
        _w_build_image || return 1
    fi
}

# Validate the active account's keychain service name if set.
#
# Reads: W_ACTIVE_KEYCHAIN_SERVICE, W_ACTIVE_ACCOUNT globals.
# Returns: 0 if valid or no keychain service is configured; 1 on invalid service.
# Errors (stderr):
#   "Error: account '<name>' has invalid keychain_service in registry." — on validation failure
_w_docker_validate_keychain() {
    if [[ -n "$W_ACTIVE_KEYCHAIN_SERVICE" ]] && \
       ! _core_keychain_validate "$W_ACTIVE_KEYCHAIN_SERVICE"; then
        echo "Error: account '$W_ACTIVE_ACCOUNT' has invalid keychain_service in registry."
        echo "Re-register with: ckipper remove $W_ACTIVE_ACCOUNT && ckipper add $W_ACTIVE_ACCOUNT --adopt"
        return 1
    fi
}

# Extract Claude credentials from macOS Keychain and validate they are valid JSON.
#
# Reads: W_ACTIVE_KEYCHAIN_SERVICE global.
# Returns: 0 on success (prints credentials to stdout, or empty string if no service).
#   1 if credentials are present but not valid JSON.
# Errors (stderr):
#   "Error: Claude credentials from Keychain are not valid JSON. ..." — on invalid JSON
_w_docker_extract_credentials() {
    if [[ -z "$W_ACTIVE_KEYCHAIN_SERVICE" ]]; then
        echo ""
        return 0
    fi

    local creds
    creds=$(security find-generic-password -s "$W_ACTIVE_KEYCHAIN_SERVICE" -w 2>/dev/null) || true

    if [[ -z "$creds" ]]; then
        echo ""
        return 0
    fi

    if ! echo "$creds" | jq empty >/dev/null 2>&1; then
        echo "Error: Claude credentials from Keychain are not valid JSON. Re-run: ckipper add $W_ACTIVE_ACCOUNT --adopt" >&2
        return 1
    fi

    echo "$creds"
}

# Extract GitHub token for gh CLI auth inside container (prints to stdout).
#
# Reads: W_ACTIVE_CONFIG_DIR global.
# Returns: 0 always (prints empty string if no token found).
_w_docker_extract_gh_token() {
    local token
    token=$(jq -r '.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN // empty' \
        "$W_ACTIVE_CONFIG_DIR/.claude.json" 2>/dev/null) || true
    if [[ -z "$token" ]] && command -v gh &>/dev/null; then
        token=$(gh auth token 2>/dev/null) || true
    fi
    echo "$token"
}

# Build the base docker run argument array into W_DOCKER_ARGS.
#
# Reads: W_WT_PATH, W_PROJECTS_DIR, W_PROJECT, W_ACTIVE_CONFIG_DIR,
#   W_EXTRA_VOLUMES globals.
# Sets: W_DOCKER_ARGS (initialised from scratch).
# Returns: 0 always.
_w_docker_build_base_args() {
    W_DOCKER_ARGS=(
        docker run --rm -it
        -e TERM="${TERM:-xterm-256color}"
        -v "$W_WT_PATH:/workspace:rw"
        -v "$W_PROJECTS_DIR/$W_PROJECT/.git:$W_PROJECTS_DIR/$W_PROJECT/.git:rw"
        -v "$W_ACTIVE_CONFIG_DIR:$W_ACTIVE_CONFIG_DIR:rw"
        -e "CLAUDE_CONFIG_DIR=$W_ACTIVE_CONFIG_DIR"
        -v "$HOME/.ssh:/home/claude/.ssh-host:ro"
        -v /run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock
        -e SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock
        --group-add 0
        --tmpfs /tmp/claude-creds:mode=700,uid=1000,gid=1000,size=1m
        -v "claude-uv-cache:/home/claude/.cache/uv"
        -v "claude-uv-tools:/home/claude/.uv-tools"
        -e "UV_TOOL_DIR=/home/claude/.uv-tools/envs"
        -e "UV_TOOL_BIN_DIR=/home/claude/.uv-tools/bin"
        -e "UV_PYTHON_INSTALL_DIR=/home/claude/.uv-tools/python"
    )
    for vol in "${W_EXTRA_VOLUMES[@]}"; do
        W_DOCKER_ARGS+=( -v "$vol" )
    done
}

# Add credentials, gh token, and extra env vars to W_DOCKER_ARGS.
#
# Args:
#   $1 — claude_creds: Claude credentials string (may be empty)
#   $2 — gh_token: GitHub personal access token (may be empty)
#
# Reads: W_EXTRA_ENV global. Appends to W_DOCKER_ARGS.
# Returns: 0 always.
_w_docker_add_optional_args() {
    local claude_creds="$1"
    local gh_token="$2"

    if [[ -n "$claude_creds" ]]; then
        W_DOCKER_ARGS+=( -e "CLAUDE_CREDENTIALS=$claude_creds" )
    else
        echo "  Warning: Could not extract Claude credentials from Keychain"
    fi

    if [[ -n "$gh_token" ]]; then
        W_DOCKER_ARGS+=( -e "GH_TOKEN=$gh_token" )
    else
        echo "  Warning: No GitHub token found (gh commands won't work in container)"
    fi

    for env_var in "${W_EXTRA_ENV[@]}"; do
        W_DOCKER_ARGS+=( -e "$env_var" )
    done
}

# If the command is "claude", expand to full skip-permissions invocation.
#
# Reads and appends to W_COMMAND and W_DOCKER_ARGS.
# Returns: 0 always.
_w_docker_expand_command() {
    if [[ ${#W_COMMAND[@]} -gt 0 && "${W_COMMAND[1]}" == "claude" ]]; then
        W_COMMAND=(claude --dangerously-skip-permissions "/rename $W_BRANCH")
    fi
    if [[ ${#W_COMMAND[@]} -gt 0 ]]; then
        W_DOCKER_ARGS+=( "${W_COMMAND[@]}" )
    fi
}

# Print the startup banner.
#
# Reads: W_COMMAND, W_FLAG_FIREWALL, W_WT_PATH, W_RESOLVED_PORTS globals.
# Returns: 0 always.
_w_docker_print_banner() {
    local mode_label="Docker"
    [[ ${#W_COMMAND[@]} -gt 0 ]] && mode_label+=": ${W_COMMAND[1]}"
    [[ "$W_FLAG_FIREWALL" = true ]] && mode_label+=", firewall"
    echo "Starting $mode_label..."
    echo "  Worktree: $W_WT_PATH"
    echo "  Ports: ${W_RESOLVED_PORTS[*]}"
}

# Snapshot git state, run docker, then check for post-session tampering.
#
# Reads: W_DOCKER_ARGS, W_PROJECTS_DIR, W_PROJECT globals.
# Returns: exit code of the docker run invocation.
_w_docker_snapshot_and_run() {
    local git_config="$W_PROJECTS_DIR/$W_PROJECT/.git/config"
    local git_config_hash=""
    [[ -f "$git_config" ]] && git_config_hash=$(shasum -a "$SHASUM_BITS" "$git_config" | cut -d' ' -f1)

    local git_worktrees_dir="$W_PROJECTS_DIR/$W_PROJECT/.git/worktrees"
    local -a worktrees_before=()
    if [[ -d "$git_worktrees_dir" ]]; then
        worktrees_before=( "$git_worktrees_dir"/*(N/:t) )
    fi

    "${W_DOCKER_ARGS[@]}"
    local exit_code=$?

    _w_docker_check_git_config_tampering "$git_config" "$git_config_hash"
    _w_docker_check_worktree_destruction "$git_worktrees_dir" "${worktrees_before[@]}"

    return $exit_code
}

# Warn if .git/config was modified during the session.
#
# Args:
#   $1 — path to .git/config
#   $2 — sha256 hash of config before session (may be empty)
#
# Returns: 0 always.
_w_docker_check_git_config_tampering() {
    local git_config="$1"
    local original_hash="$2"
    if [[ -n "$original_hash" && -f "$git_config" ]]; then
        local new_hash
        new_hash=$(shasum -a "$SHASUM_BITS" "$git_config" | cut -d' ' -f1)
        if [[ "$original_hash" != "$new_hash" ]]; then
            echo ""
            echo "WARNING: .git/config was modified during the Docker session!"
            echo "Review changes: git -C $W_PROJECTS_DIR/$W_PROJECT config --local --list"
        fi
    fi
}

# Warn if any worktree metadata was destroyed during the session.
#
# Args:
#   $1 — path to .git/worktrees directory
#   $@ — worktree names present before the session
#
# Returns: 0 always.
_w_docker_check_worktree_destruction() {
    local git_worktrees_dir="$1"
    shift
    local -a worktrees_before=("$@")
    [[ ${#worktrees_before[@]} -eq 0 ]] && return 0

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

    [[ ${#missing[@]} -eq 0 ]] && return 0

    echo ""
    echo "CRITICAL: ${#missing[@]} worktree(s) had metadata destroyed during the Docker session!"
    echo "Missing worktrees: ${missing[*]}"
    echo ""
    echo "The working directories still exist on disk — only the .git/worktrees/ metadata was deleted."
    echo "To recover, re-register each worktree:"
    echo "  cd $W_PROJECTS_DIR/$W_PROJECT"
    for wt in "${missing[@]}"; do
        echo "  git worktree add <path-to-$wt> $wt"
    done
}
