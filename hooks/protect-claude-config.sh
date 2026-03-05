#!/bin/bash
# Prevents Claude from modifying its own config files inside Docker.
# Closes the container escape vector where a compromised Claude modifies
# settings.json (statusLine.command) to execute arbitrary code on the host.
# Only active in Docker containers — no-op on the host.

# Skip protection when not in Docker
[ ! -f /.dockerenv ] && exit 0

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ "$FILE_PATH" =~ \.claude/(settings(\.local)?\.json|statusline-command\.sh|docker/|hooks/|plugins/) ]]; then
    echo "Blocked: cannot modify $FILE_PATH (protected Claude config file)" >&2
    exit 2
fi

exit 0
