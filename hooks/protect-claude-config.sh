#!/bin/bash
# Prevents Claude from modifying its own config files inside Docker.
# Closes the container escape vector where a compromised Claude modifies
# settings.json (statusLine.command) to execute arbitrary code on the host.
# Only active in Docker containers — no-op on the host.

# Skip protection when not in Docker
[ ! -f /.dockerenv ] && exit 0

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Block Claude state subset under ~/.claude or any per-account ~/.claude-<name>.
# Note: ~/.claude-host.json is the read-only staging mount and is intentionally
# excluded — the regex requires a '/' after the optional -<name> suffix, while
# .claude-host.json has '.json' instead.
if [[ $FILE_PATH =~ \.claude(-[a-z0-9_-]+)?/(settings(\.local)?\.json|statusline-command\.sh|CLAUDE\.md|commands/|docker/|hooks/|plugins/) ]]; then
    echo "Blocked: cannot modify $FILE_PATH (protected Claude config file)" >&2
    exit 2
fi

# Block anything under ~/.ckipper (registry, hooks, settings-template, docker tooling).
# Tampering with accounts.json could redirect another account's keychain_service.
if [[ $FILE_PATH =~ /\.ckipper/ ]]; then
    echo "Blocked: cannot modify $FILE_PATH (protected Ckipper file)" >&2
    exit 2
fi

exit 0
