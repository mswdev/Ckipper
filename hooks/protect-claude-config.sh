#!/bin/bash
# Prevents Claude from modifying its own config files inside Docker.
# Closes the container escape vector where a compromised Claude modifies
# settings.json (statusLine.command) to execute arbitrary code on the host.
# Only active in Docker containers — no-op on the host.

# Skip protection when not in Docker (CKIPPER_DOCKERENV overrides path for testing)
[ ! -f "${CKIPPER_DOCKERENV:-/.dockerenv}" ] && exit 0

INPUT="$(cat)"
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty') || {
    echo "Error: hook input is not valid JSON; failing closed" >&2
    exit 2
}

# Resolve symlinks/relative segments before regex matching so attempts like
# /workspace/foo/../.git/config can't slip past the substring check. Fall back
# to the raw path if realpath isn't available (it lives in coreutils inside
# the container, but we keep this defensive for host-side test runs).
if command -v realpath >/dev/null 2>&1; then
    RESOLVED_PATH=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
else
    RESOLVED_PATH="$FILE_PATH"
fi

# Block Claude state subset under ~/.claude or any per-account ~/.claude-<name>.
# Note: ~/.claude-host.json is the read-only staging mount and is intentionally
# excluded — the regex requires a '/' after the optional -<name> suffix, while
# .claude-host.json has '.json' instead.
if [[ $RESOLVED_PATH =~ \.claude(-[a-z0-9_-]+)?/(settings(\.local)?\.json|statusline-command\.sh|CLAUDE\.md|commands/|docker/|hooks/|plugins/) ]]; then
    echo "Blocked: cannot modify $FILE_PATH (protected Claude config file)" >&2
    exit 2
fi

# Block anything under ~/.ckipper (registry, hooks, settings-template, docker tooling).
# Tampering with accounts.json could redirect another account's keychain_service.
if [[ $RESOLVED_PATH =~ /\.ckipper/ ]]; then
    echo "Blocked: cannot modify $FILE_PATH (protected Ckipper file)" >&2
    exit 2
fi

# Block writes inside the host repo's .git/ (mounted RW into the container by
# docker-mode.zsh). Edits to .git/hooks/, .git/config, .git/info/, or
# .git/worktrees/ execute on the host the next time the user runs git, so they
# constitute a container-escape vector. The leading '/' anchor avoids
# over-blocking '.gitignore', '.github/', or directories like '.git-foo/'.
if [[ $RESOLVED_PATH =~ /\.git/(config|info/|hooks/|worktrees/) ]]; then
    echo "Blocked: cannot modify $FILE_PATH (protected host .git file)" >&2
    exit 2
fi

exit 0
