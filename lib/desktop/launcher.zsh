#!/usr/bin/env zsh
# Launch / login / process helpers for Claude Desktop instances.
#
# Three public entry points:
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

# Look up an instance's bundle path. Fails if the instance is not registered.
# Mirrors the registry-existence check pattern at
# instance-management.zsh::_ckipper_desktop_data_dir_of — kept local to the
# launcher namespace because feature dirs MUST NOT call into each other
# beyond public, namespaced entry points; instance-management.zsh's
# _ckipper_desktop_data_dir_of returns a different field (data_dir, not
# bundle) so we don't reuse it.
#
# Args: $1 — instance name.
# Returns: 0 with bundle path on stdout; 1 with error on stderr.
# Errors (stderr): "Desktop instance '<name>' is not registered."
_ckipper_desktop_lookup_bundle() {
    local name="$1"
    if [[ ! -f "$CKIPPER_DESKTOP_REGISTRY" ]] \
        || ! jq -e --arg n "$name" '.instances[$n]' \
            "$CKIPPER_DESKTOP_REGISTRY" >/dev/null 2>&1; then
        echo "Desktop instance '$name' is not registered." >&2
        return 1
    fi
    jq -r --arg n "$name" '.instances[$n].app_bundle_path' "$CKIPPER_DESKTOP_REGISTRY"
}

# Poll until every PID in $1 (newline-separated) has exited, escalating to
# SIGKILL once _TERM_TIMEOUT_MAX_POLLS polls have elapsed. Uses an integer
# poll count + a literal-string sleep interval to avoid floating-point
# arithmetic in zsh.
#
# Args: $1 — newline-separated PIDs (output of pgrep).
# Returns: 0 always.
_ckipper_desktop_wait_for_exit() {
    local pids="$1"
    local polls=0 pid still
    while (( polls < _CKIPPER_DESKTOP_TERM_TIMEOUT_MAX_POLLS )); do
        still=0
        for pid in ${(f)pids}; do
            kill -0 "$pid" 2>/dev/null && still=1
        done
        (( still == 0 )) && return 0
        sleep "$_CKIPPER_DESKTOP_POLL_INTERVAL_SECONDS"
        (( polls += 1 ))
    done
    for pid in ${(f)pids}; do
        kill -KILL "$pid" 2>/dev/null
    done
}

# Quit ALL running Claude Desktop processes (the bare app + every wrapper).
# SIGTERM first, then poll up to the configured timeout, then SIGKILL any
# stragglers via _ckipper_desktop_wait_for_exit.
#
# Returns: 0 once all processes have exited (or none were running).
_ckipper_desktop_quit_all_claude_processes() {
    local pids
    pids=$(pgrep -f "$_CKIPPER_DESKTOP_CLAUDE_PROCESS_PATTERN" 2>/dev/null) || return 0
    [[ -z "$pids" ]] && return 0
    local pid
    for pid in ${(f)pids}; do
        kill -TERM "$pid" 2>/dev/null
    done
    _ckipper_desktop_wait_for_exit "$pids"
}

# Quit all running Claude Desktop processes, then launch only <name>.
#
# Use this command to safely complete a /login flow: macOS routes
# claude:// deep-link callbacks to the most-recently-active Claude app,
# so with multiple instances running the callback can land in the wrong
# window. By quitting everything first and launching just <name>, the
# deep-link callback has only one place to land.
#
# Args: $1 — instance name.
# Returns: 0 on success; 1 if the instance is not registered.
_ckipper_desktop_login() {
    local name="$1"
    local bundle
    bundle=$(_ckipper_desktop_lookup_bundle "$name") || return 1
    _ckipper_desktop_quit_all_claude_processes
    open -n -a "$bundle"
}

# Open a registered Desktop instance without disturbing others.
# This is the simple, non-auth path — use `ckipper desktop login <name>`
# instead when completing a /login flow that involves deep-link callbacks.
#
# Args: $1 — instance name.
# Returns: 0 on success; 1 if the instance is not registered.
_ckipper_desktop_launch() {
    local name="$1"
    local bundle
    bundle=$(_ckipper_desktop_lookup_bundle "$name") || return 1
    open -n -a "$bundle"
}
