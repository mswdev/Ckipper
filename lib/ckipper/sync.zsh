#!/usr/bin/env zsh
# Account settings sync subcommand: sync MCP servers and settings.json keys between accounts.

_ckipper_sync() {
    _core_registry_check_version || return 1
    local from="$1" to="$2"
    shift 2 2>/dev/null
    if [[ -z "$from" || -z "$to" ]]; then
        echo "Usage: ckipper sync <from> <to> [--mcp [names]] [--settings keys] [--all] [--dry-run]"
        return 1
    fi
    if [[ "$from" == "$to" ]]; then
        echo "<from> and <to> must differ."
        return 1
    fi

    local from_dir to_dir
    from_dir=$(_core_account_dir "$from") || return 1
    to_dir=$(_core_account_dir "$to") || return 1
    if [[ ! -f "$from_dir/.claude.json" ]]; then
        echo "Source has no .claude.json: $from_dir"; return 1
    fi
    if [[ ! -f "$to_dir/.claude.json" ]]; then
        echo "Destination has no .claude.json: $to_dir"; return 1
    fi

    # Parse flags. The argparse here is intentionally minimal — order matters,
    # but each flag is well-formed and easy to read.
    local mode_mcp=0 mcp_names="" mode_settings=0 settings_keys="" dry_run=0 mode_all=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mcp)
                mode_mcp=1
                if [[ -n "$2" && "$2" != --* ]]; then mcp_names="$2"; shift; fi
                shift ;;
            --settings)
                mode_settings=1
                if [[ -n "$2" && "$2" != --* ]]; then settings_keys="$2"; shift; fi
                shift ;;
            --all)        mode_all=1; shift ;;
            --dry-run)    dry_run=1; shift ;;
            *) echo "Unknown flag: $1"; return 1 ;;
        esac
    done

    # Default bundle when no specific flags were passed: mcpServers + a useful
    # selection of settings.json keys.
    if (( mode_mcp == 0 && mode_settings == 0 )); then
        mode_all=1
    fi
    if (( mode_all )); then
        mode_mcp=1
        mode_settings=1
        [[ -z "$settings_keys" ]] && \
            settings_keys="enabledPlugins,extraKnownMarketplaces,statusLine,env,model"
    fi

    # If a Claude session is running, sync's writes can race with its writes
    # to the same .claude.json. Warn (but don't refuse) unless --dry-run.
    if (( ! dry_run )); then
        local running_procs
        running_procs=$(_core_running_claude_processes)
        if [[ -n "$running_procs" ]]; then
            echo "Warning: Claude is currently running. If a session uses '$to' or '$from'," >&2
            echo "sync may race with its writes (Claude doesn't lock these files)." >&2
            echo "$running_procs" | sed 's/^/  /' >&2
            read -r "?Continue anyway? [y/N] " ans
            [[ "$ans" != "y" && "$ans" != "Y" ]] && { echo "Aborted."; return 1; }
        fi
    fi

    local pending_msgs=()

    # ── MCP sync ─────────────────────────────────────────────────
    if (( mode_mcp )); then
        local mcp_filter
        if [[ -z "$mcp_names" ]]; then
            mcp_filter='.mcpServers // {}'
        else
            # Build a jq object containing only the named servers, e.g. {Vibma: ..., github: ...}
            local jq_array
            jq_array=$(echo "$mcp_names" | jq -R 'split(",") | map(. | gsub("^\\s+|\\s+$"; ""))')
            mcp_filter='.mcpServers // {} | with_entries(select(.key as $k | '"$jq_array"' | index($k)))'
        fi
        local servers
        servers=$(jq "$mcp_filter" "$from_dir/.claude.json")
        local server_keys
        server_keys=$(echo "$servers" | jq -r 'keys[]?' | tr '\n' ' ')
        if [[ -z "$server_keys" || "$server_keys" == " " ]]; then
            pending_msgs+=("MCP: nothing to sync (no matching servers in $from)")
        else
            pending_msgs+=("MCP servers → $to: $server_keys")
            if (( ! dry_run )); then
                local tmp; tmp=$(mktemp "$to_dir/.claude.json.tmp.XXXXXX")
                jq --argjson new "$servers" '.mcpServers = (.mcpServers // {}) + $new' \
                    "$to_dir/.claude.json" > "$tmp" && mv "$tmp" "$to_dir/.claude.json"
            fi
        fi
    fi

    # ── settings.json key sync ───────────────────────────────────
    if (( mode_settings )) && [[ -n "$settings_keys" ]]; then
        if [[ ! -f "$from_dir/settings.json" ]]; then
            pending_msgs+=("Settings: $from has no settings.json (skipping)")
        else
            # Build a jq subset object with only the requested keys (skipping missing ones).
            local jq_keys
            jq_keys=$(echo "$settings_keys" | jq -R 'split(",") | map(. | gsub("^\\s+|\\s+$"; ""))')
            local subset
            subset=$(jq --argjson keys "$jq_keys" \
                'with_entries(select(.key as $k | $keys | index($k)))' \
                "$from_dir/settings.json")
            local copied_keys
            copied_keys=$(echo "$subset" | jq -r 'keys[]?' | tr '\n' ' ')
            if [[ -z "$copied_keys" || "$copied_keys" == " " ]]; then
                pending_msgs+=("Settings: no matching keys in $from/settings.json")
            else
                pending_msgs+=("Settings keys → $to: $copied_keys")
                if (( ! dry_run )); then
                    if [[ ! -f "$to_dir/settings.json" ]]; then
                        echo '{}' > "$to_dir/settings.json"
                    fi
                    local tmp; tmp=$(mktemp "$to_dir/settings.json.tmp.XXXXXX")
                    jq --argjson new "$subset" '. + $new' \
                        "$to_dir/settings.json" > "$tmp" && mv "$tmp" "$to_dir/settings.json"
                fi
            fi
        fi
    fi

    if (( dry_run )); then
        echo "Dry run — would apply:"
    else
        echo "Synced:"
    fi
    for m in "${pending_msgs[@]}"; do
        echo "  - $m"
    done

    if (( ! dry_run )); then
        echo ""
        echo "Restart any running '$to' Claude session for changes to take effect."
    fi
}
