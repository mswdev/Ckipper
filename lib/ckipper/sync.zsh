#!/usr/bin/env zsh
# Account settings sync subcommand: sync MCP servers and settings.json keys between accounts.

# Parse sync subcommand flags into named variables in the caller's scope.
# Populates: mode_mcp, mcp_names, mode_settings, settings_keys, dry_run, mode_all.
#
# Args:
#   $@ — remaining args after <from> and <to> have been shifted
#
# Returns:
#   0 on success; 1 on unknown flag.
_ckipper_sync_parse_flags() {
    mode_mcp=0; mcp_names=""; mode_settings=0; settings_keys=""; dry_run=0; mode_all=0
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
            --all)     mode_all=1; shift ;;
            --dry-run) dry_run=1; shift ;;
            *) echo "Unknown flag: $1"; return 1 ;;
        esac
    done
    if (( mode_mcp == 0 && mode_settings == 0 )); then
        mode_all=1
    fi
    if (( mode_all )); then
        mode_mcp=1
        mode_settings=1
        [[ -z "$settings_keys" ]] && \
            settings_keys="enabledPlugins,extraKnownMarketplaces,statusLine,env,model"
    fi
}

# Warn if Claude is running and the sync would race with its writes.
# Prompts the user to confirm continuation.
#
# Args:
#   $1 — from account name
#   $2 — to account name
#
# Returns:
#   0 to proceed; 1 if user aborts.
_ckipper_sync_warn_running_claude() {
    local from="$1" to="$2"
    local running_procs
    running_procs=$(_core_running_claude_processes)
    [[ -z "$running_procs" ]] && return 0
    echo "Warning: Claude is currently running. If a session uses '$to' or '$from'," >&2
    echo "sync may race with its writes (Claude doesn't lock these files)." >&2
    echo "$running_procs" | sed 's/^/  /' >&2
    local user_choice
    read -r "?Continue anyway? [y/N] " user_choice
    [[ "$user_choice" != "y" && "$user_choice" != "Y" ]] && { echo "Aborted."; return 1; }
}

# Sync MCP servers from one account to another. Appends a summary line to pending_msgs.
#
# Args:
#   $1 — from account config directory
#   $2 — to account name (for message)
#   $3 — to account config directory
#   $4 — comma-separated MCP server names to sync (empty = all)
#   $5 — dry_run flag (1 = dry run, 0 = write)
#
# Returns:
#   0 always.
_ckipper_sync_mcp_servers() {
    local from_dir="$1" to="$2" to_dir="$3" mcp_names="$4" dry_run="$5"
    local mcp_filter
    if [[ -z "$mcp_names" ]]; then
        mcp_filter='.mcpServers // {}'
    else
        local jq_array
        jq_array=$(printf '%s' "$mcp_names" | jq -R 'split(",") | map(. | gsub("^\\s+|\\s+$"; ""))')
        mcp_filter='.mcpServers // {} | with_entries(select(.key as $k | '"$jq_array"' | index($k)))'
    fi
    local servers; servers=$(jq "$mcp_filter" "$from_dir/.claude.json")
    local server_keys; server_keys=$(printf '%s' "$servers" | jq -r 'keys[]?' | tr '\n' ' ')
    if [[ -z "$server_keys" || "$server_keys" == " " ]]; then
        pending_msgs+=("MCP: nothing to sync (no matching servers in source)")
        return 0
    fi
    pending_msgs+=("MCP servers → $to: $server_keys")
    (( dry_run )) && return 0
    local sync_tmpfile; sync_tmpfile=$(mktemp "$to_dir/.claude.json.tmp.XXXXXX")
    jq --argjson new "$servers" '.mcpServers = (.mcpServers // {}) + $new' \
        "$to_dir/.claude.json" > "$sync_tmpfile" && mv "$sync_tmpfile" "$to_dir/.claude.json"
}

# Sync settings.json keys from one account to another. Appends summary line to pending_msgs.
#
# Args:
#   $1 — from account name (for message)
#   $2 — from account config directory
#   $3 — to account name (for message)
#   $4 — to account config directory
#   $5 — comma-separated settings keys to sync
#   $6 — dry_run flag (1 = dry run, 0 = write)
#
# Returns:
#   0 always.
_ckipper_sync_settings_keys() {
    local from="$1" from_dir="$2" to="$3" to_dir="$4" settings_keys="$5" dry_run="$6"
    if [[ ! -f "$from_dir/settings.json" ]]; then
        pending_msgs+=("Settings: $from has no settings.json (skipping)")
        return 0
    fi
    local jq_keys; jq_keys=$(printf '%s' "$settings_keys" | jq -R 'split(",") | map(. | gsub("^\\s+|\\s+$"; ""))')
    local subset; subset=$(jq --argjson keys "$jq_keys" \
        'with_entries(select(.key as $k | $keys | index($k)))' "$from_dir/settings.json")
    local copied_keys; copied_keys=$(printf '%s' "$subset" | jq -r 'keys[]?' | tr '\n' ' ')
    if [[ -z "$copied_keys" || "$copied_keys" == " " ]]; then
        pending_msgs+=("Settings: no matching keys in $from/settings.json")
        return 0
    fi
    pending_msgs+=("Settings keys → $to: $copied_keys")
    (( dry_run )) && return 0
    [[ ! -f "$to_dir/settings.json" ]] && echo '{}' > "$to_dir/settings.json"
    local sync_tmpfile; sync_tmpfile=$(mktemp "$to_dir/settings.json.tmp.XXXXXX")
    jq --argjson new "$subset" '. + $new' \
        "$to_dir/settings.json" > "$sync_tmpfile" && mv "$sync_tmpfile" "$to_dir/settings.json"
}

# Print the sync summary lines and restart reminder.
#
# Args:
#   $1 — to account name
#   $2 — dry_run flag (1 = dry run, 0 = write)
#
# Returns:
#   0 always.
_ckipper_sync_print_summary() {
    local to="$1" dry_run="$2"
    if (( dry_run )); then
        echo "Dry run — would apply:"
    else
        echo "Synced:"
    fi
    local m
    for m in "${pending_msgs[@]}"; do
        echo "  - $m"
    done
    if (( ! dry_run )); then
        echo ""
        echo "Restart any running '$to' Claude session for changes to take effect."
    fi
}

# Resolve and validate sync source and destination account directories.
# Prints from_dir and to_dir as tab-separated values to stdout on success.
#
# Args:
#   $1 — from account name
#   $2 — to account name
#
# Returns:
#   0 with "from_dir\tto_dir" on stdout; 1 on validation failure.
_ckipper_sync_resolve_dirs() {
    local from="$1" to="$2"
    local from_dir to_dir
    from_dir=$(_core_account_dir "$from") || return 1
    to_dir=$(_core_account_dir "$to") || return 1
    if [[ ! -f "$from_dir/.claude.json" ]]; then
        echo "Source has no .claude.json: $from_dir"; return 1
    fi
    if [[ ! -f "$to_dir/.claude.json" ]]; then
        echo "Destination has no .claude.json: $to_dir"; return 1
    fi
    printf '%s\t%s' "$from_dir" "$to_dir"
}

# Copy MCP servers and/or settings.json keys from one registered account to another.
#
# Args:
#   $1 — from account name
#   $2 — to account name
#   $@ — options: [--mcp [names]] [--settings keys] [--all] [--dry-run]
#
# Returns:
#   0 on success; 1 on validation failure or user abort.
#
# Errors (stderr):
#   "Usage: ckipper sync <from> <to> ..." — when arguments are missing.
#   "<from> and <to> must differ." — when both accounts are the same.
_ckipper_sync() {
    _core_registry_check_version || return 1
    local from="$1" to="$2"
    shift 2 2>/dev/null
    if [[ -z "$from" || -z "$to" ]]; then
        echo "Usage: ckipper sync <from> <to> [--mcp [names]] [--settings keys] [--all] [--dry-run]"
        return 1
    fi
    [[ "$from" == "$to" ]] && { echo "<from> and <to> must differ."; return 1; }
    local dirs_line; dirs_line=$(_ckipper_sync_resolve_dirs "$from" "$to") || return 1
    local from_dir="${dirs_line%%	*}" to_dir="${dirs_line##*	}"
    local mode_mcp mcp_names mode_settings settings_keys dry_run mode_all
    _ckipper_sync_parse_flags "$@" || return 1
    if (( ! dry_run )); then
        _ckipper_sync_warn_running_claude "$from" "$to" || return 1
    fi
    local pending_msgs=()
    (( mode_mcp )) && \
        _ckipper_sync_mcp_servers "$from_dir" "$to" "$to_dir" "$mcp_names" "$dry_run"
    (( mode_settings && ${#settings_keys} > 0 )) && \
        _ckipper_sync_settings_keys "$from" "$from_dir" "$to" "$to_dir" "$settings_keys" "$dry_run"
    _ckipper_sync_print_summary "$to" "$dry_run"
}
