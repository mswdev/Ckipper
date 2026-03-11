#!/bin/bash
# Bash guardrails for Docker containers with --dangerously-skip-permissions.
# Catches accidental destructive commands. Not adversarial-proof, but
# prevents the most common "oops" scenarios.
# No-op on the host.

[ ! -f /.dockerenv ] && exit 0

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Normalize: collapse whitespace, strip leading sudo
NORMALIZED=$(echo "$CMD" | sed 's/^[[:space:]]*sudo[[:space:]]*//' | tr -s ' ')

# 1. Destructive recursive deletes (allow only build artifacts)
if echo "$NORMALIZED" | grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f|--recursive|-[a-zA-Z]*f[a-zA-Z]*r)\s'; then
    SAFE="node_modules|dist|\.next|build|\.cache|__pycache__|\.turbo|coverage|\.pytest_cache|tmp|\.parcel-cache|out"
    if ! echo "$NORMALIZED" | grep -qE "rm\s+-[^ ]+\s+\.?/?(${SAFE})(/|\s|$)"; then
        echo "Blocked: recursive delete. Only build artifacts (node_modules, dist, .next, etc.) can be rm -rf'd." >&2
        exit 2
    fi
fi

# 2. Git history destruction
if echo "$NORMALIZED" | grep -qE 'git\s+push\s+.*--force\b|git\s+push\s+-f\b'; then
    echo "Blocked: git push --force. Use --force-with-lease instead." >&2
    exit 2
fi
if echo "$NORMALIZED" | grep -qE 'git\s+reset\s+--hard'; then
    echo "Blocked: git reset --hard. Use git stash or git checkout <file>." >&2
    exit 2
fi

# 3. Git worktree destruction (prune sees host paths as missing → nukes all worktrees)
if echo "$NORMALIZED" | grep -qE 'git\s+worktree\s+prune'; then
    echo "Blocked: git worktree prune. Host worktree paths don't exist in the container — prune would destroy ALL worktree metadata." >&2
    exit 2
fi
if echo "$NORMALIZED" | grep -qE 'git\s+worktree\s+(remove|move)'; then
    # Allow removing/moving container-created worktrees under /workspace
    if echo "$NORMALIZED" | grep -qE 'git\s+worktree\s+(remove|move)\s+.*(/workspace/)'; then
        : # allowed
    else
        echo "Blocked: git worktree remove/move outside /workspace. Use the host to manage worktrees." >&2
        exit 2
    fi
fi

# 4. .git/hooks, .git/config, and .git/worktrees modification (execute on host)
if echo "$NORMALIZED" | grep -qE '\.git/(hooks|config|info/attributes|worktrees)'; then
    if echo "$NORMALIZED" | grep -qE '^(cat|less|head|tail|grep|rg|wc|ls|file|stat|git)\s'; then
        exit 0
    fi
    echo "Blocked: modifying .git/hooks, .git/config, .git/worktrees, or .git/info/attributes. These affect the host." >&2
    exit 2
fi

# 5. Broad recursive chmod/chown
if echo "$NORMALIZED" | grep -qE '(chmod|chown)\s+(-R|--recursive)\s'; then
    echo "Blocked: recursive chmod/chown. Apply permissions to specific files instead." >&2
    exit 2
fi

# 6. Direct credential/key file reads
if echo "$NORMALIZED" | grep -qE '(cat|less|head|tail|cp|curl|base64|xxd)\s+.*(\.ssh/(id_|config|authorized)|\.claude/\.credentials)'; then
    echo "Blocked: reading credential/key files. Use git, gh, or npm which handle auth automatically." >&2
    exit 2
fi

# 7. Claude config modification via Bash (closes Edit/Write hook bypass)
if echo "$NORMALIZED" | grep -qE '\.claude/(settings(\.local)?\.json|statusline-command\.sh|docker/|hooks/|plugins/)'; then
    if echo "$NORMALIZED" | grep -qE '^(cat|less|head|tail|grep|rg|wc|ls|file|stat|jq)\s'; then
        exit 0
    fi
    echo "Blocked: modifying Claude config files via Bash. These are protected." >&2
    exit 2
fi

exit 0
