#!/usr/bin/env zsh
# Launch / login / process helpers for Claude Desktop instances.
#
# Three public entry points (only assert_not_running is in place after Task 9;
# launch / login land in Tasks 10 + 11):
#   _ckipper_desktop_launch  — open -n -a <bundle> (no quit dance)
#   _ckipper_desktop_login   — quit ALL Claude.app processes, then launch <bundle>
#   _ckipper_desktop_assert_not_running — refuse if a Claude process owns
#                                          this user-data-dir
#
# Why pgrep against --user-data-dir, not the bundle path:
# every wrapper's Contents/MacOS/launcher exec's /Applications/Claude.app
# directly, so the bundle path never appears in process listings. Only the
# system Claude binary path and the --user-data-dir flag do. The per-instance
# probe matches on that flag; the all-Claude probe (login dance) matches on
# the binary path.

# Cmdline substring identifying any running Claude Desktop (Electron) process.
# Every wrapper bundle's launcher exec's /Applications/Claude.app — so the
# bundle path NEVER appears in pgrep output; only this path does.
readonly _CKIPPER_DESKTOP_CLAUDE_PROCESS_PATTERN='/Applications/Claude.app/Contents/MacOS/Claude'

# Login-dance timing. typeset -g (NOT readonly) so tests can shrink the
# numbers for fast feedback without waiting the full 5s timeout. Consumed by
# Task 10's quit-all-Claude polling loop.
typeset -g _CKIPPER_DESKTOP_POLL_INTERVAL_SECONDS="0.2"
typeset -g _CKIPPER_DESKTOP_TERM_TIMEOUT_MAX_POLLS=25

# Refuse the operation if a Claude Desktop instance is currently running
# against this data dir.
#
# Detection: pgrep for the cmdline argument `--user-data-dir=<path>`. Bundle
# path is irrelevant because wrapper bundles never appear in process listings
# (their launcher exec's into /Applications/Claude.app).
#
# Args: $1 — the user-data-dir to check.
# Returns: 0 if no matching process is found; 1 if the instance is running.
#
# Errors (stderr):
#   "Refusing: a Claude Desktop instance is running for <dir> (PID(s): ...)."
#   "Quit it first (Cmd-Q on the instance), then re-run."
_ckipper_desktop_assert_not_running() {
    local data_dir="$1"
    local pids
    pids=$(pgrep -f -- "--user-data-dir=$data_dir" 2>/dev/null) || return 0
    [[ -z "$pids" ]] && return 0
    echo "Refusing: a Claude Desktop instance is running for $data_dir (PID(s): $pids)." >&2
    echo "Quit it first (Cmd-Q on the instance), then re-run." >&2
    return 1
}
