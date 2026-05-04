#!/usr/bin/env zsh
# Docker mode execution for `ckipper worktree run --docker`. Builds docker run args and launches the container.

readonly _CKIPPER_WT_SHASUM_BITS=256

# Container user identity. Must match useradd -u/-g in docker/Dockerfile.
readonly _CKIPPER_WT_CLAUDE_CONTAINER_UID=1000
readonly _CKIPPER_WT_CLAUDE_CONTAINER_GID=1000

# tmpfs for /tmp/claude-creds inside the container.
readonly _CKIPPER_WT_CREDS_TMPFS_MODE=700
readonly _CKIPPER_WT_CREDS_TMPFS_SIZE="1m"

# Host gid 0 (wheel/root) added so the container user can read host-mounted files
# owned by macOS staff/wheel without needing world-readable bits.
readonly _CKIPPER_WT_DOCKER_GROUP_ADD_HOST_ROOT=0

# Run the worktree in a Docker container.
#
# Reads globals: CKIPPER_WT_PATH, CKIPPER_PROJECTS_DIR, CKIPPER_WT_PROJECT, CKIPPER_WT_BRANCH, CKIPPER_WT_COMMAND,
#   CKIPPER_WT_FLAG_FIREWALL, CKIPPER_WT_ACTIVE_ACCOUNT, CKIPPER_WT_ACTIVE_CONFIG_DIR,
#   CKIPPER_WT_ACTIVE_KEYCHAIN_SERVICE, CKIPPER_PORTS, CKIPPER_EXTRA_VOLUMES, CKIPPER_EXTRA_ENV.
# Sets globals: CKIPPER_WT_DOCKER_ARGS — the assembled `docker run` argv,
#   built up by helper calls below. Declared at function scope as a global
#   array (not `local -a`) so the runtime ring is uniform with the other
#   CKIPPER_WT_* runtime variables (the helpers mutate it explicitly, not via
#   dynamic-scope leakage).
# Returns: exit code of the docker run invocation.
_ckipper_worktree_run_docker_mode() {
    _ckipper_worktree_docker_check_prerequisites || return 1

    [[ -f "$CKIPPER_WT_ACTIVE_CONFIG_DIR/.claude.json" ]] || echo '{}' > "$CKIPPER_WT_ACTIVE_CONFIG_DIR/.claude.json"

    _ckipper_worktree_docker_validate_keychain || return 1

    local claude_creds gh_token
    claude_creds=$(_ckipper_worktree_docker_extract_credentials) || return 1
    gh_token=$(_ckipper_worktree_docker_extract_gh_token)

    # Export credentials in this shell scope so `docker run -e VAR` (without =value)
    # inherits them from the parent process env. This keeps the values OUT of argv
    # (and therefore out of `ps`/`/proc/<pid>/cmdline` and `docker inspect`).
    # We always unset before returning — see the trap below.
    export CLAUDE_CREDENTIALS="$claude_creds"
    export GH_TOKEN="$gh_token"
    # shellcheck disable=SC2064 # intentional immediate expansion: unset by exact name.
    trap "unset CLAUDE_CREDENTIALS GH_TOKEN; trap - EXIT INT TERM" EXIT INT TERM

    typeset -ga CKIPPER_WT_DOCKER_ARGS=()
    _ckipper_worktree_docker_build_base_args
    _ckipper_worktree_docker_add_optional_args "$claude_creds" "$gh_token"
    _ckipper_worktree_resolve_ports
    [[ "$CKIPPER_WT_FLAG_FIREWALL" = true ]] && CKIPPER_WT_DOCKER_ARGS+=( --cap-add=NET_ADMIN -e ENABLE_FIREWALL=1 )

    CKIPPER_WT_DOCKER_ARGS+=( ckipper-dev )
    _ckipper_worktree_docker_expand_command

    _ckipper_worktree_docker_print_banner
    _ckipper_worktree_docker_snapshot_and_run
}

# Validate Docker is installed and daemon is running.
#
# Returns: 0 if docker is available and running; 1 otherwise.
# Errors (stderr):
#   "Error: docker is not installed or not in PATH" — when docker binary is missing
#   "Error: Docker daemon is not running. Start Docker Desktop first." — when daemon is down
_ckipper_worktree_docker_check_prerequisites() {
    if ! command -v docker &>/dev/null; then
        echo "Error: docker is not installed or not in PATH" >&2
        return 1
    fi
    if ! docker info &>/dev/null 2>&1; then
        echo "Error: Docker daemon is not running. Start Docker Desktop first." >&2
        return 1
    fi
    if ! docker image inspect ckipper-dev > /dev/null 2>&1; then
        _ckipper_worktree_build_image || return 1
    fi
}

# Validate the active account's keychain service name if set.
#
# Reads: CKIPPER_WT_ACTIVE_KEYCHAIN_SERVICE, CKIPPER_WT_ACTIVE_ACCOUNT globals.
# Returns: 0 if valid or no keychain service is configured; 1 on invalid service.
# Errors (stderr):
#   "Error: account '<name>' has invalid keychain_service in registry." — on validation failure
_ckipper_worktree_docker_validate_keychain() {
    if [[ -n "$CKIPPER_WT_ACTIVE_KEYCHAIN_SERVICE" ]] && \
       ! _core_keychain_validate "$CKIPPER_WT_ACTIVE_KEYCHAIN_SERVICE"; then
        echo "Error: account '$CKIPPER_WT_ACTIVE_ACCOUNT' has invalid keychain_service in registry." >&2
        echo "Re-register with: ckipper account remove $CKIPPER_WT_ACTIVE_ACCOUNT && ckipper account add $CKIPPER_WT_ACTIVE_ACCOUNT --adopt" >&2
        return 1
    fi
}

# Extract Claude credentials from macOS Keychain and validate they are valid JSON.
#
# Reads: CKIPPER_WT_ACTIVE_KEYCHAIN_SERVICE global.
# Returns: 0 on success (prints credentials to stdout, or empty string if no service).
#   1 if credentials are present but not valid JSON.
# Errors (stderr):
#   "Error: Claude credentials from Keychain are not valid JSON. ..." — on invalid JSON
_ckipper_worktree_docker_extract_credentials() {
    if [[ -z "$CKIPPER_WT_ACTIVE_KEYCHAIN_SERVICE" ]]; then
        echo ""
        return 0
    fi

    local creds
    creds=$(security find-generic-password -s "$CKIPPER_WT_ACTIVE_KEYCHAIN_SERVICE" -w 2>/dev/null) || true

    if [[ -z "$creds" ]]; then
        echo ""
        return 0
    fi

    if ! echo "$creds" | jq empty >/dev/null 2>&1; then
        echo "Error: Claude credentials from Keychain are not valid JSON. Re-run: ckipper account add $CKIPPER_WT_ACTIVE_ACCOUNT --adopt" >&2
        return 1
    fi

    echo "$creds"
}

# Extract GitHub token for gh CLI auth inside container (prints to stdout).
#
# Reads: CKIPPER_WT_ACTIVE_CONFIG_DIR global.
# Returns: 0 always (prints empty string if no token found).
_ckipper_worktree_docker_extract_gh_token() {
    local token
    token=$(jq -r '.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN // empty' \
        "$CKIPPER_WT_ACTIVE_CONFIG_DIR/.claude.json" 2>/dev/null) || true
    if [[ -z "$token" ]] && command -v gh &>/dev/null; then
        token=$(gh auth token 2>/dev/null) || true
    fi
    echo "$token"
}

# Build the base docker run argument array into CKIPPER_WT_DOCKER_ARGS.
#
# Reads: CKIPPER_WT_PATH, CKIPPER_PROJECTS_DIR, CKIPPER_WT_PROJECT, CKIPPER_WT_ACTIVE_CONFIG_DIR,
#   CKIPPER_EXTRA_VOLUMES, CKIPPER_WT_FLAG_SSH_FORWARD globals.
# Sets: CKIPPER_WT_DOCKER_ARGS (initialised from scratch).
# Returns: 0 always.
#
# Hardening notes:
# - --cap-drop=ALL drops the default Linux caps (NET_RAW, FOWNER, SETUID, etc.).
#   The conditional --cap-add=NET_ADMIN appended later when --firewall is set
#   re-grants what init-firewall.sh needs (iptables-legacy). Side effect: the
#   `chown` in fix-volume-perms.sh becomes a silent no-op (loses CAP_CHOWN); the
#   script already wraps it in `|| true`, and new installs get the right UID
#   from initial volume creation, so this only affects upgrade paths with stale
#   named-volume UIDs — accepted trade-off.
# - We deliberately do NOT add --security-opt=no-new-privileges. It would block
#   sudo's setuid bit at exec time, breaking `sudo init-firewall.sh` and the
#   unconditional `sudo fix-volume-perms.sh` in entrypoint.sh. Refactoring the
#   sudo path is out of scope for this script.
# - SSH agent forwarding (the macOS Docker Desktop magic socket plus the host
#   ~/.ssh mount) is gated by CKIPPER_WT_FLAG_SSH_FORWARD via
#   `_ckipper_worktree_docker_add_ssh_mounts` so users with ssh_forward=false
#   in their account preferences get a tighter container.
_ckipper_worktree_docker_build_base_args() {
    CKIPPER_WT_DOCKER_ARGS=(
        docker run --rm -it
        --cap-drop=ALL
        -e TERM="${TERM:-xterm-256color}"
        -v "$CKIPPER_WT_PATH:/workspace:rw"
        -v "$CKIPPER_PROJECTS_DIR/$CKIPPER_WT_PROJECT/.git:$CKIPPER_PROJECTS_DIR/$CKIPPER_WT_PROJECT/.git:rw"
        -v "$CKIPPER_WT_ACTIVE_CONFIG_DIR:$CKIPPER_WT_ACTIVE_CONFIG_DIR:rw"
        -e "CLAUDE_CONFIG_DIR=$CKIPPER_WT_ACTIVE_CONFIG_DIR"
        --group-add "$_CKIPPER_WT_DOCKER_GROUP_ADD_HOST_ROOT"
        --tmpfs "/tmp/claude-creds:mode=$_CKIPPER_WT_CREDS_TMPFS_MODE,uid=$_CKIPPER_WT_CLAUDE_CONTAINER_UID,gid=$_CKIPPER_WT_CLAUDE_CONTAINER_GID,size=$_CKIPPER_WT_CREDS_TMPFS_SIZE"
        -v "claude-uv-cache:/home/claude/.cache/uv"
        -v "claude-uv-tools:/home/claude/.uv-tools"
        -e "UV_TOOL_DIR=/home/claude/.uv-tools/envs"
        -e "UV_TOOL_BIN_DIR=/home/claude/.uv-tools/bin"
        -e "UV_PYTHON_INSTALL_DIR=/home/claude/.uv-tools/python"
    )
    _ckipper_worktree_docker_add_ssh_mounts
    for vol in "${CKIPPER_EXTRA_VOLUMES[@]}"; do
        CKIPPER_WT_DOCKER_ARGS+=( -v "$vol" )
    done
}

# Append SSH agent forwarding mounts when CKIPPER_WT_FLAG_SSH_FORWARD is set.
# No-op otherwise.
#
# Reads: CKIPPER_WT_FLAG_SSH_FORWARD, HOME globals.
# Sets: appends to CKIPPER_WT_DOCKER_ARGS.
# Returns: 0 always.
_ckipper_worktree_docker_add_ssh_mounts() {
    [[ "$CKIPPER_WT_FLAG_SSH_FORWARD" == "true" ]] || return 0
    CKIPPER_WT_DOCKER_ARGS+=(
        -v "$HOME/.ssh:/home/claude/.ssh-host:ro"
        -v /run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock
        -e SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock
    )
}

# Add credentials, gh token, and extra env vars to CKIPPER_WT_DOCKER_ARGS.
#
# Args:
#   $1 — claude_creds: Claude credentials string (may be empty). Used only for
#        the empty/non-empty branch decision; the actual value is passed to the
#        container via the parent shell's exported CLAUDE_CREDENTIALS env var
#        (set by the caller) — `docker run -e VAR` (no `=value`) inherits it.
#        This keeps the secret out of argv (`ps`, `/proc/*/cmdline`, `docker inspect`).
#   $2 — gh_token: GitHub personal access token (may be empty). Same handling
#        as $1: passed via inherited GH_TOKEN env var, not via argv.
#
# Reads: CKIPPER_EXTRA_ENV global. Appends to CKIPPER_WT_DOCKER_ARGS.
# Returns: 0 always.
_ckipper_worktree_docker_add_optional_args() {
    local claude_creds="$1"
    local gh_token="$2"

    if [[ -n "$claude_creds" ]]; then
        CKIPPER_WT_DOCKER_ARGS+=( -e CLAUDE_CREDENTIALS )
    else
        echo "  Warning: Could not extract Claude credentials from Keychain"
    fi

    if [[ -n "$gh_token" ]]; then
        CKIPPER_WT_DOCKER_ARGS+=( -e GH_TOKEN )
    else
        echo "  Warning: No GitHub token found (gh commands won't work in container)"
    fi

    for env_var in "${CKIPPER_EXTRA_ENV[@]}"; do
        CKIPPER_WT_DOCKER_ARGS+=( -e "$env_var" )
    done
}

# If the command is "claude", expand to full skip-permissions invocation.
#
# Reads and appends to CKIPPER_WT_COMMAND and CKIPPER_WT_DOCKER_ARGS.
# Returns: 0 always.
_ckipper_worktree_docker_expand_command() {
    if [[ ${#CKIPPER_WT_COMMAND[@]} -gt 0 && "${CKIPPER_WT_COMMAND[1]}" == "claude" ]]; then
        CKIPPER_WT_COMMAND=(claude --dangerously-skip-permissions "/rename $CKIPPER_WT_BRANCH")
    fi
    if [[ ${#CKIPPER_WT_COMMAND[@]} -gt 0 ]]; then
        CKIPPER_WT_DOCKER_ARGS+=( "${CKIPPER_WT_COMMAND[@]}" )
    fi
}

# Print the startup banner.
#
# Reads: CKIPPER_WT_COMMAND, CKIPPER_WT_FLAG_FIREWALL, CKIPPER_WT_PATH, CKIPPER_WT_RESOLVED_PORTS globals.
# Returns: 0 always.
_ckipper_worktree_docker_print_banner() {
    local mode_label="Docker"
    [[ ${#CKIPPER_WT_COMMAND[@]} -gt 0 ]] && mode_label+=": ${CKIPPER_WT_COMMAND[1]}"
    [[ "$CKIPPER_WT_FLAG_FIREWALL" = true ]] && mode_label+=", firewall"
    echo "Starting $mode_label..."
    echo "  Worktree: $CKIPPER_WT_PATH"
    echo "  Ports: ${CKIPPER_WT_RESOLVED_PORTS[*]}"
}

# Snapshot git state, run docker, then check for post-session tampering.
#
# Reads: CKIPPER_WT_DOCKER_ARGS, CKIPPER_PROJECTS_DIR, CKIPPER_WT_PROJECT globals.
# Returns: exit code of the docker run invocation.
_ckipper_worktree_docker_snapshot_and_run() {
    local git_config="$CKIPPER_PROJECTS_DIR/$CKIPPER_WT_PROJECT/.git/config"
    local git_config_hash=""
    [[ -f "$git_config" ]] && git_config_hash=$(shasum -a "$_CKIPPER_WT_SHASUM_BITS" "$git_config" | cut -d' ' -f1)

    local git_worktrees_dir="$CKIPPER_PROJECTS_DIR/$CKIPPER_WT_PROJECT/.git/worktrees"
    local -a worktrees_before=()
    if [[ -d "$git_worktrees_dir" ]]; then
        worktrees_before=( "$git_worktrees_dir"/*(N/:t) )
    fi

    "${CKIPPER_WT_DOCKER_ARGS[@]}"
    local exit_code=$?

    _ckipper_worktree_docker_check_git_config_tampering "$git_config" "$git_config_hash"
    _ckipper_worktree_docker_check_worktree_destruction "$git_worktrees_dir" "${worktrees_before[@]}"

    return $exit_code
}

# Warn if .git/config was modified during the session.
#
# Args:
#   $1 — path to .git/config
#   $2 — sha256 hash of config before session (may be empty)
#
# Returns: 0 always.
_ckipper_worktree_docker_check_git_config_tampering() {
    local git_config="$1"
    local original_hash="$2"
    if [[ -n "$original_hash" && -f "$git_config" ]]; then
        local new_hash
        new_hash=$(shasum -a "$_CKIPPER_WT_SHASUM_BITS" "$git_config" | cut -d' ' -f1)
        if [[ "$original_hash" != "$new_hash" ]]; then
            echo ""
            echo "WARNING: .git/config was modified during the Docker session!"
            echo "Review changes: git -C $CKIPPER_PROJECTS_DIR/$CKIPPER_WT_PROJECT config --local --list"
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
_ckipper_worktree_docker_check_worktree_destruction() {
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
    echo "  cd $CKIPPER_PROJECTS_DIR/$CKIPPER_WT_PROJECT"
    for wt in "${missing[@]}"; do
        echo "  git worktree add <path-to-$wt> $wt"
    done
}
