#!/usr/bin/env zsh
# Shared cross-platform stat utilities used by registry and other modules.

# Cross-platform stat for permissions: BSD (macOS) uses -f, GNU/Linux uses -c.
_core_stat_perms() {
    if [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" == darwin* ]]; then
        stat -f '%Lp' "$1" 2>/dev/null
    else
        stat -c '%a' "$1" 2>/dev/null
    fi
}

# Cross-platform stat for mtime in seconds since epoch.
_core_stat_mtime() {
    if [[ "${_CKIPPER_TEST_OSTYPE:-$OSTYPE}" == darwin* ]]; then
        stat -f '%m' "$1" 2>/dev/null
    else
        stat -c '%Y' "$1" 2>/dev/null
    fi
}
