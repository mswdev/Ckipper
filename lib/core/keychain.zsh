#!/usr/bin/env zsh
# Shared macOS Keychain and Claude process utilities.

# Validates a keychain_service name before passing to `security`.
# Accepts "Claude Code-credentials" optionally followed by "-<hex>".
_core_keychain_validate() {
    local svc="$1"
    [[ -z "$svc" ]] && return 1
    [[ "$svc" =~ ^Claude\ Code-credentials(-[a-f0-9]+)?$ ]]
}

_core_keychain_snapshot() {
    # macOS only. Returns service names of all "Claude Code-credentials*" entries, sorted.
    [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" != darwin* ]] && return 0

    # Pick a timeout binary if available (macOS doesn't ship one; gtimeout from
    # coreutils is the typical brew install). Fall through to no timeout if neither
    # is present — better than failing with a misleading "keychain locked" error.
    local timeout_cmd=""
    if command -v timeout >/dev/null 2>&1; then
        timeout_cmd="timeout 10"
    elif command -v gtimeout >/dev/null 2>&1; then
        timeout_cmd="gtimeout 10"
    fi

    local out
    if [[ -n "$timeout_cmd" ]]; then
        if ! out=$($timeout_cmd security dump-keychain 2>/dev/null); then
            echo "Warning: Keychain may be locked or slow. Unlock it (Keychain Access > File > Unlock) and retry." >&2
            return 1
        fi
    else
        # No timeout available — run without. If keychain is locked the GUI
        # password prompt will block this, which is a fine failure mode.
        if ! out=$(security dump-keychain 2>/dev/null); then
            echo "Warning: 'security dump-keychain' failed. Keychain may be locked." >&2
            return 1
        fi
    fi

    printf '%s\n' "$out" | \
        awk -F'"' '/"svce"<blob>="Claude Code-credentials/ {print $4}' | \
        sort -u
}

# Detect running Claude processes that would conflict with destructive operations.
# Matches: 'claude' CLI (basename), 'Claude' (Claude.app main process). Avoids matching
# vim files named 'claude-*', tmux sessions, or Claude Helper subprocesses (the parent
# Claude.app being killed will cascade to those).
_core_running_claude_processes() {
    pgrep -lx claude 2>/dev/null
    pgrep -lx Claude 2>/dev/null
}

# Refuse with a clear message if any Claude process is running.
_core_assert_no_running_claude() {
    local found
    found=$(_core_running_claude_processes)
    if [[ -n "$found" ]]; then
        echo "Error: Claude process(es) detected. Quit them first:" >&2
        echo "$found" | sed 's/^/  /' >&2
        echo "(Set CKIPPER_FORCE=1 to bypass this check, but expect inconsistent state.)" >&2
        if [[ "$CKIPPER_FORCE" == "1" ]]; then
            echo "CKIPPER_FORCE=1 set — proceeding despite running Claude." >&2
            return 0
        fi
        return 1
    fi
    return 0
}
