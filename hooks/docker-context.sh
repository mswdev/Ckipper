#!/bin/bash
# Inject safety context at session start inside Docker.
# Reminds Claude of constraints so it doesn't accidentally trigger guardrails.
# No-op on the host.

# Skip context injection when not in Docker (CKIPPER_DOCKERENV overrides path for testing)
[ ! -f "${CKIPPER_DOCKERENV:-/.dockerenv}" ] && exit 0

cat <<'CONTEXT'
You are running inside a Docker container with --dangerously-skip-permissions.
Safety hooks are active and will block:
- Recursive rm -rf (except build artifacts like node_modules, dist, .next)
- git push --force (use --force-with-lease instead)
- git reset --hard (use git stash or targeted checkout)
- git worktree prune (host worktree paths don't exist here — prune would destroy ALL worktrees)
- git worktree remove/move outside /workspace
- git config --local/--worktree (modifies host .git/config; use GIT_CONFIG_COUNT env vars instead)
- Modifications to .git/hooks/, .git/config, .git/worktrees, .git/info/ (these affect the host)
- Recursive chmod/chown
- Reading SSH keys or credential files directly
- gh gist create, npm publish (data exfiltration channels)
- Modifying Claude config files (.claude/settings.json, CLAUDE.md, hooks/, commands/, plugins/)

CRITICAL: This container runs inside a host git worktree. The .git directory is
mounted from the host and contains metadata for OTHER active worktrees. Never run
git worktree prune — it will destroy metadata for all host worktrees since their
paths don't exist inside this container. To clean up worktrees you created inside
the container, use "git worktree remove /workspace/.claude/worktrees/<name>".

If a hook blocks something you genuinely need, explain what you need
and the user can run it manually on the host.
CONTEXT

exit 0
