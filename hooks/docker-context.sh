#!/bin/bash
# Inject safety context at session start inside Docker.
# Reminds Claude of constraints so it doesn't accidentally trigger guardrails.
# No-op on the host.

[ ! -f /.dockerenv ] && exit 0

cat <<'CONTEXT'
You are running inside a Docker container with --dangerously-skip-permissions.
Safety hooks are active and will block:
- Recursive rm -rf (except build artifacts like node_modules, dist, .next)
- git push --force (use --force-with-lease instead)
- git reset --hard (use git stash or targeted checkout)
- Modifications to .git/hooks/ or .git/config (these execute on the host)
- Recursive chmod/chown
- Reading SSH keys or credential files directly
- Modifying Claude config files (.claude/settings.json, hooks/, plugins/)

If a hook blocks something you genuinely need, explain what you need
and the user can run it manually on the host.
CONTEXT

exit 0
