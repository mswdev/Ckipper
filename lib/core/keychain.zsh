#!/usr/bin/env zsh
# Shared macOS Keychain and Claude process utilities.

readonly KEYCHAIN_TIMEOUT_SECONDS=10

# Validate a keychain_service name before passing to `security`.
# Accepts "Claude Code-credentials" optionally followed by "-<hex>".
#
# Args:
#   $1 — service name to validate
#
# Returns:
#   0 if valid; non-zero if empty or wrong shape.
_core_keychain_validate() {
    local svc="$1"
    [[ -z "$svc" ]] && return 1
    [[ "$svc" =~ ^Claude\ Code-credentials(-[a-f0-9]+)?$ ]]
}

# Detect the best available timeout command for wrapping keychain access.
#
# Returns:
#   0 always; prints the timeout command prefix to stdout (empty if none found).
_core_keychain_detect_timeout_cmd() {
    if command -v timeout >/dev/null 2>&1; then
        printf 'timeout %s' "$KEYCHAIN_TIMEOUT_SECONDS"
    elif command -v gtimeout >/dev/null 2>&1; then
        printf 'gtimeout %s' "$KEYCHAIN_TIMEOUT_SECONDS"
    fi
}

# Dump the macOS Keychain using a timeout wrapper, then filter for Claude entries.
#
# Args:
#   $1 — timeout command prefix (e.g. "timeout 10"), or empty for no timeout
#
# Returns:
#   0 on success with Claude service names printed to stdout; 1 on keychain error.
_core_keychain_snapshot_with_timeout() {
    local timeout_cmd="$1"
    local out
    if ! out=$($timeout_cmd security dump-keychain 2>/dev/null); then
        echo "Warning: Keychain may be locked or slow. Unlock it (Keychain Access > File > Unlock) and retry." >&2
        return 1
    fi
    printf '%s\n' "$out" | \
        awk -F'"' '/"svce"<blob>="Claude Code-credentials/ {print $4}' | \
        sort -u
}

# Dump the macOS Keychain without a timeout wrapper, then filter for Claude entries.
#
# Returns:
#   0 on success with Claude service names printed to stdout; 1 on keychain error.
#
# Errors (stderr):
#   "Warning: 'security dump-keychain' failed..." — when keychain dump exits non-zero.
_core_keychain_snapshot_fallback() {
    local out
    # No timeout available — run without. If keychain is locked the GUI
    # password prompt will block this, which is a fine failure mode.
    if ! out=$(security dump-keychain 2>/dev/null); then
        echo "Warning: 'security dump-keychain' failed. Keychain may be locked." >&2
        return 1
    fi
    printf '%s\n' "$out" | \
        awk -F'"' '/"svce"<blob>="Claude Code-credentials/ {print $4}' | \
        sort -u
}

# Return service names of all "Claude Code-credentials*" Keychain entries, sorted.
# macOS only — returns 0 immediately on other platforms.
#
# Returns:
#   0 on success; 1 if keychain is locked or unavailable.
#
# Errors (stderr):
#   Warning messages when the keychain is slow, locked, or dump fails.
_core_keychain_snapshot() {
    [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" != darwin* ]] && return 0

    # Pick a timeout binary if available (macOS doesn't ship one; gtimeout from
    # coreutils is the typical brew install). Fall through to no timeout if neither
    # is present — better than failing with a misleading "keychain locked" error.
    local timeout_cmd
    timeout_cmd=$(_core_keychain_detect_timeout_cmd)

    if [[ -n "$timeout_cmd" ]]; then
        _core_keychain_snapshot_with_timeout "$timeout_cmd"
    else
        _core_keychain_snapshot_fallback
    fi
}

# Detect running Claude processes that would conflict with destructive operations.
# Matches: 'claude' CLI (basename), 'Claude' (Claude.app main process). Avoids matching
# vim files named 'claude-*', tmux sessions, or Claude Helper subprocesses (the parent
# Claude.app being killed will cascade to those).
#
# Returns:
#   0 always; matching processes printed to stdout.
_core_running_claude_processes() {
    pgrep -lx claude 2>/dev/null
    pgrep -lx Claude 2>/dev/null
}

# Refuse with a clear message if any Claude process is running.
#
# Returns:
#   0 if no Claude processes found (or CKIPPER_FORCE=1 is set); 1 otherwise.
#
# Errors (stderr):
#   "Error: Claude process(es) detected..." — when running processes found.
_core_assert_no_running_claude() {
    local found
    found=$(_core_running_claude_processes)
    [[ -z "$found" ]] && return 0

    echo "Error: Claude process(es) detected. Quit them first:" >&2
    echo "$found" | sed 's/^/  /' >&2
    echo "(Set CKIPPER_FORCE=1 to bypass this check, but expect inconsistent state.)" >&2
    if [[ "$CKIPPER_FORCE" == "1" ]]; then
        echo "CKIPPER_FORCE=1 set — proceeding despite running Claude." >&2
        return 0
    fi
    return 1
}
