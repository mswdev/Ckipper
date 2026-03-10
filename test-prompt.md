# Docker Container Environment Test

Copy this prompt into a Claude Code session running inside the Docker container
(`w <project> <branch> --docker claude`) to verify everything works.

---

Run a comprehensive environment test to verify this Docker container has everything needed to develop on this project. Go through each check below, report pass/fail for each, and note any issues.

**1. Entrypoint verification**
- Run `echo $TURBO_CACHE_DIR` — should be `/workspace/.turbo/cache`
- Run `env | grep -i cred` and `env | grep GH_TOKEN` — both should return empty (credentials were consumed and cleared by entrypoint)
- Read `~/.claude.json` and verify `claudeInChromeDefaultEnabled` is `false`
- Run `git config user.name` and `git config user.email` — should be set (pulled from .claude.json account info by entrypoint)
- Run `strings /proc/self/environ | grep -iE 'cred|token|secret'` — should return empty (credentials cleared from process environment before exec)

**2. File system access**
- Read package.json and list the workspace packages
- Read the project's CLAUDE.md and any files in .claude/rules/
- Create a test file at /workspace/test-write.txt, verify it exists, then delete it
- Create a file and check ownership: `touch /workspace/test-owner.txt && ls -la /workspace/test-owner.txt` — should be owned by `claude:claude`. Delete after.
- Verify SSH staging mount is read-only: `echo test >> ~/.ssh-host/known_hosts 2>&1` — should fail with "Read-only file system"
- Verify SSH config was sanitized: `grep -i UseKeychain ~/.ssh/config 2>&1` — should return no matches (or no config file)

**3. Code modification round-trip**
- Find a source file in the project, make a small change using Edit (add a comment), verify with Read, then revert it. This tests that Edit works on mounted volume files with correct permissions.

**4. Git operations**
- Run git status and git log --oneline -5
- Create a test branch, make an empty commit, then delete the branch (this also verifies git identity is configured)
- Run `ssh -T git@github.com` — should succeed with "Hi <user>! You've successfully authenticated" (SSH agent is forwarded from host via Docker Desktop)
- Run `gh auth status` to verify GitHub CLI is authenticated
- Verify worktree git references resolve: run `git log --oneline origin/develop -1` and `git diff --stat origin/develop HEAD | tail -5` — both should work (verifies the worktree .git file resolves through the mounted main repo .git directory)
- Test git push over HTTPS (full credential chain test): create a test branch, push it with `git push -u origin <branch>`, verify it appears with `git ls-remote --heads origin <branch>`, then clean up: `git push origin --delete <branch>`, switch back to original branch, and delete the local branch

**5. Dependencies and build tools**
- Run npm ls --depth=0 to verify node_modules
- Run `npx biome --version` — if this fails with "Exec format error", the entrypoint's npm install didn't fix native binaries
- Run `npx turbo --version`
- Run node --version, npm --version, python3 --version, git --version
- Run `tmux new-session -d -s test 'sleep 2' && sleep 1 && tmux list-sessions && tmux kill-session -t test`
- Run `chromium --headless --disable-gpu --dump-dom https://example.com 2>&1 | head -5` — should output HTML (verifies headless Chromium works with --no-sandbox)
- Run `uv --version && uvx --version` — both should return version numbers (needed for Python-based MCP servers)
- Run `python3 -c "import json, sys; print(f'Python {sys.version} works')"` — should print version (verifies Python can import stdlib and execute scripts)

**6. Build the project**
- Run the full build: npm run build
- If it fails, identify which workspace package failed and why
- Note: first build may be slow; subsequent builds use turbo cache

**7. Run dev servers**
- Start the dev servers in the background
- Wait 15 seconds for them to start
- Use curl to check if localhost:3000 and localhost:3030 respond
- Kill the dev servers after testing
- Note: dev servers may return errors if .env files have missing secrets (expected in Docker without full env setup)

**8. Run tests and linting**
- Run the test suite: npm test or npx vitest run
- Run the linter: npm run lint
- Note: these should work even without .env files

**9. MCP and network access**
- Try using WebFetch on a URL to verify network access
- Run `gh pr list --limit 5` to verify GitHub CLI works
- If `--firewall` was used: verify `curl -s --max-time 5 https://api.anthropic.com` succeeds (whitelisted) and `curl -s --max-time 5 https://example.com` times out (blocked)

**10. Safety hooks verification**
- Try to Edit `~/.claude/settings.json` — should be BLOCKED by config protection hook
- Try to run `echo test > .git/hooks/pre-commit` — should be BLOCKED by bash guardrails
- Try to run `rm -rf /workspace` — should be BLOCKED by bash guardrails
- Try to run `cat ~/.ssh/id_ed25519` — should be BLOCKED by bash guardrails
- Report the exact error message from each blocked action

Now test guardrail bypass attempts (report which are caught and which pass through):
- Try `echo "safe" && rm -rf /workspace` — should be BLOCKED (multi-command with dangerous second half)
- Try `/bin/rm -rf /workspace` — note whether BLOCKED or passes (absolute path bypasses `rm` regex)
- Try `cat /etc/passwd; cat ~/.ssh/id_ed25519` — should be BLOCKED (semicolon-chained credential read)
- Try `python3 -c "open('/home/claude/.ssh/id_ed25519').read()"` — note whether BLOCKED or passes (language-level file access)
- Try `ln -s /home/claude/.ssh /workspace/ssh-link && cat /workspace/ssh-link/id_ed25519` — note whether BLOCKED or passes (symlink to change the path pattern). Clean up: `rm -f /workspace/ssh-link`

**11. Container isolation**
- Run `whoami` — should be `claude` (non-root user)
- Run `sudo -l 2>&1` — should only list `/usr/local/bin/init-firewall.sh` as allowed
- Run `sudo bash 2>&1` — should be denied
- Run `docker ps 2>&1` — should fail (no Docker socket mounted)
- Run `cat /proc/1/cmdline 2>&1 | tr '\0' ' '` — should show entrypoint or claude process (PID 1 is the container's entrypoint, not a host process)
- Run `mount | grep workspace` — verify /workspace is mounted rw (not ro)
- Run `find /usr -perm -4000 -type f 2>/dev/null` — list setuid binaries (should be minimal in slim image)

## Expected Results

| Check | Expected |
|-------|----------|
| 1a-1d | All PASS |
| 1e | PASS (no credentials in /proc/self/environ) |
| 2a-2c | All PASS |
| 2d | PASS (owned by claude:claude) |
| 2e | PASS (read-only file system error on .ssh-host; UseKeychain stripped from config) |
| 3 | PASS |
| 4a | PASS |
| 4b | PASS (git identity + GPG signing disabled by entrypoint) |
| 4c | PASS (SSH agent forwarded from host via Docker Desktop socket) |
| 4d | PASS (gh authenticated via entrypoint; also configured as git credential helper for HTTPS push) |
| 4e | PASS (worktree references resolve through mounted .git) |
| 4f | PASS (push + delete over HTTPS using gh credential helper) |
| 5a-5e | All PASS |
| 5f | PASS (Chromium outputs HTML) |
| 5g | PASS (uv and uvx installed) |
| 5h | PASS (Python runs scripts) |
| 6 | PASS (all packages build) |
| 7 | PARTIAL expected — servers start but may 500 without full .env |
| 8a-8b | PASS |
| 9a | PASS |
| 9b | PASS |
| 9c | PASS if --firewall, NOT ACTIVE if not |
| 10a-10d | All BLOCKED |
| 10e (bypasses) | Multi-command + semicolon BLOCKED; absolute path + python + symlink may pass (guardrails prevent accidents, not adversarial bypass) |
| 11a | PASS (claude user) |
| 11b | PASS (only init-firewall.sh) |
| 11c | DENIED (sudo restricted) |
| 11d | FAIL expected (no Docker socket) |
| 11e | PASS (shows entrypoint/claude) |
| 11f | PASS (workspace mounted rw) |
| 11g | Minimal setuid list (passwd, su, sudo expected) |

After all checks, give me a summary table of what works and what doesn't, and flag anything that would prevent you from doing normal development work (writing code, running tests, building, committing, pushing). For any guardrail bypass attempts that succeeded, note them as potential hardening opportunities.
