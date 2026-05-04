#!/bin/bash
# Send terminal bell on Claude Code notifications inside Docker.
# The bell character passes through Docker's TTY to the host terminal,
# triggering native notifications (dock bounce, sound, etc.).
# No-op on the host (host Claude handles notifications natively).

# Skip bell when not in Docker (CKIPPER_DOCKERENV overrides path for testing)
[ ! -f "${CKIPPER_DOCKERENV:-/.dockerenv}" ] && exit 0

printf '\a'
exit 0
