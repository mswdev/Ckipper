#!/usr/bin/env zsh
# Port resolution for `ckipper worktree run --docker`. Finds available host ports for dev servers.

readonly _CKIPPER_WT_MAX_PORT_FALLBACK_ATTEMPTS=10

# Resolve port mappings for Docker, using fallback host ports when the
# preferred port is already in use. Appends -p flags to the CKIPPER_WT_DOCKER_ARGS array.
#
# Reads: CKIPPER_PORTS (array of container ports), CKIPPER_WT_DOCKER_ARGS (appended to).
# Sets: CKIPPER_WT_RESOLVED_PORTS (array of ports for display).
_ckipper_worktree_resolve_ports() {
    CKIPPER_WT_RESOLVED_PORTS=("${CKIPPER_PORTS[@]}")

    for port in "${CKIPPER_PORTS[@]}"; do
        _ckipper_worktree_bind_port "$port"
    done
}

# Attempt to bind a single container port to an available host port.
#
# Args:
#   $1 — container port number to bind
#
# Reads: CKIPPER_WT_DOCKER_ARGS (appended to).
# Returns: 0 always (logs a warning if no port could be bound).
_ckipper_worktree_bind_port() {
    local port="$1"
    local host_port=$port
    local is_bound="false"

    for (( i=0; i<_CKIPPER_WT_MAX_PORT_FALLBACK_ATTEMPTS; i++ )); do
        if ! lsof -i :"$host_port" -P -n &>/dev/null; then
            _ckipper_worktree_record_bound_port "$port" "$host_port"
            is_bound="true"
            break
        fi
        (( host_port++ ))
    done

    if [[ "$is_bound" != "true" ]]; then
        echo "  Port $port: no available host port found ($port-$((port+_CKIPPER_WT_MAX_PORT_FALLBACK_ATTEMPTS-1)) all in use)"
    fi
}

# Append the resolved -p flag to CKIPPER_WT_DOCKER_ARGS and log if the host port differs.
#
# Args:
#   $1 — original container port
#   $2 — host port that was bound (may equal $1 or be a fallback)
#
# Reads: CKIPPER_WT_DOCKER_ARGS (appended to).
# Returns: 0 always.
_ckipper_worktree_record_bound_port() {
    local port="$1"
    local host_port="$2"
    CKIPPER_WT_DOCKER_ARGS+=( -p "127.0.0.1:$host_port:$port" )
    (( host_port != port )) && echo "  Port $port mapped to host:$host_port (original in use)"
    return 0
}
