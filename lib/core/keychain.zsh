#!/usr/bin/env zsh
# macOS Keychain naming and Claude process utilities.
#
# Claude Code stores each config dir's login in its own Keychain entry and
# derives the entry's service name from the dir path, so Ckipper never has
# to record or discover it:
#   ~/.claude (no CLAUDE_CONFIG_DIR)  → "Claude Code-credentials"
#   any other CLAUDE_CONFIG_DIR       → "Claude Code-credentials-<hash>"
# where <hash> is the first 8 hex chars of sha256(<config dir path>).

readonly _CORE_KEYCHAIN_SERVICE_PREFIX="Claude Code-credentials"
readonly _CORE_KEYCHAIN_HASH_LENGTH=8

# Print the Keychain service name Claude Code uses for a config dir.
#
# Args: $1 — absolute config dir path, exactly as passed in CLAUDE_CONFIG_DIR.
# Returns: 0; prints the service name.
#
# Example:
#   _core_keychain_service_for_dir "$HOME/.claude-work"
#   # → Claude Code-credentials-1a2b3c4d
_core_keychain_service_for_dir() {
    local dir="$1"
    if [[ "$dir" == "$HOME/.claude" ]]; then
        print -r -- "$_CORE_KEYCHAIN_SERVICE_PREFIX"
        return 0
    fi
    local digest
    digest=$(print -rn -- "$dir" | shasum -a 256 | cut -c "1-$_CORE_KEYCHAIN_HASH_LENGTH")
    print -r -- "$_CORE_KEYCHAIN_SERVICE_PREFIX-$digest"
}

# Return 0 if the macOS Keychain has an entry for the given service. Reads
# attributes only (no -w), so it never prompts and never touches the secret.
# Always returns 1 off macOS.
#
# Args: $1 — Keychain service name.
# Returns: 0 if the entry exists; 1 otherwise.
_core_keychain_entry_exists() {
    local service="$1"
    [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" != darwin* ]] && return 1
    security find-generic-password -s "$service" >/dev/null 2>&1
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
