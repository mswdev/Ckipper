# Docker Container Environment Test

Copy this prompt into a Claude Code session running inside the Docker container
(`w <project> <branch> --auto`) to verify everything works.

---

Run a comprehensive environment test to verify this Docker container has everything needed to develop on this project. Go through each check below, report pass/fail for each, and note any issues.

**1. Entrypoint verification**
- Run `echo $TURBO_CACHE_DIR` — should be `/workspace/.turbo/cache`
- Run `env | grep -i cred` and `env | grep GH_TOKEN` — both should return empty (credentials were consumed and cleared by entrypoint)
- Read `~/.claude.json` and verify `claudeInChromeDefaultEnabled` is `false`
- Run `git config user.name` and `git config user.email` — should be set (pulled from .claude.json account info by entrypoint)

**2. File system access**
- Read package.json and list the workspace packages
- Read the project's CLAUDE.md and any files in .claude/rules/
- Create a test file at /workspace/test-write.txt, verify it exists, then delete it

**3. Code modification round-trip**
- Find a source file in the project, make a small change using Edit (add a comment), verify with Read, then revert it. This tests that Edit works on mounted volume files with correct permissions.

**4. Git operations**
- Run git status and git log --oneline -5
- Create a test branch, make an empty commit, then delete the branch (this also verifies git identity is configured)
- Run `ssh -T git@github.com` — likely FAIL if SSH keys are managed by an agent (1Password, macOS Keychain) rather than on-disk files. This is expected; use `gh` CLI for git operations instead.
- Run `gh auth status` to verify GitHub CLI is authenticated

**5. Dependencies and build tools**
- Run npm ls --depth=0 to verify node_modules
- Run `npx biome --version` — if this fails with "Exec format error", the entrypoint's npm install didn't fix native binaries
- Run `npx turbo --version`
- Run node --version, npm --version, python3 --version, git --version
- Run `tmux new-session -d -s test 'sleep 2' && sleep 1 && tmux list-sessions && tmux kill-session -t test`

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

## Expected Results

| Check | Expected |
|-------|----------|
| 1a-1d | All PASS |
| 2a-2c | All PASS |
| 3 | PASS |
| 4a | PASS |
| 4b | PASS (git identity + GPG signing disabled by entrypoint) |
| 4c | FAIL expected if using SSH agent (1Password, etc.) — no on-disk keys to mount |
| 4d | PASS (gh authenticated via entrypoint; also configured as git credential helper for HTTPS push) |
| 5a-5e | All PASS |
| 6 | PASS (all packages build) |
| 7 | PARTIAL expected — servers start but may 500 without full .env |
| 8a-8b | PASS |
| 9a | PASS |
| 9b | PASS |
| 9c | PASS if --firewall, NOT ACTIVE if not |
| 10a-10d | All BLOCKED |

After all checks, give me a summary table of what works and what doesn't, and flag anything that would prevent you from doing normal development work (writing code, running tests, building, committing, pushing).
