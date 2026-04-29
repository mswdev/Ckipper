#!/usr/bin/env zsh
# Port resolution for w() Docker mode. Finds available host ports for dev servers.

readonly MAX_PORT_FALLBACK_ATTEMPTS=10

# Resolve port mappings for Docker, using fallback host ports when the
# preferred port is already in use. Appends -p flags to the W_DOCKER_ARGS array.
#
# Reads: W_PORTS (array of container ports), W_DOCKER_ARGS (appended to).
# Sets: W_RESOLVED_PORTS (array of ports for display).
_w_resolve_ports() {
    W_RESOLVED_PORTS=("${W_PORTS[@]}")

    for port in "${W_PORTS[@]}"; do
        _w_bind_port "$port"
    done
}

# Attempt to bind a single container port to an available host port.
#
# Args:
#   $1 — container port number to bind
#
# Reads: W_DOCKER_ARGS (appended to).
# Returns: 0 always (logs a warning if no port could be bound).
_w_bind_port() {
    local port="$1"
    local host_port=$port
    local is_bound=0

    for (( i=0; i<MAX_PORT_FALLBACK_ATTEMPTS; i++ )); do
        if ! lsof -i :"$host_port" -P -n &>/dev/null; then
            W_DOCKER_ARGS+=( -p "127.0.0.1:$host_port:$port" )
            is_bound=1
            if (( host_port != port )); then
                echo "  Port $port mapped to host:$host_port (original in use)"
            fi
            break
        fi
        (( host_port++ ))
    done

    if (( !is_bound )); then
        echo "  Port $port: no available host port found ($port-$((port+MAX_PORT_FALLBACK_ATTEMPTS-1)) all in use)"
    fi
}
