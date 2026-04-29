#!/usr/bin/env zsh
# Port resolution for w() Docker mode. Finds available host ports for dev servers.

# Resolve port mappings for Docker, using fallback host ports when the
# preferred port is already in use. Appends -p flags to the W_DOCKER_ARGS array.
#
# Reads: W_PORTS (array of container ports), W_DOCKER_ARGS (appended to).
# Sets: W_RESOLVED_PORTS (array of ports for display).
_w_resolve_ports() {
    local max_fallback=10
    W_RESOLVED_PORTS=("${W_PORTS[@]}")

    for port in "${W_PORTS[@]}"; do
        local host_port=$port
        local bound=0
        for (( i=0; i<max_fallback; i++ )); do
            if ! lsof -i :"$host_port" -P -n &>/dev/null; then
                W_DOCKER_ARGS+=( -p "127.0.0.1:$host_port:$port" )
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
}
