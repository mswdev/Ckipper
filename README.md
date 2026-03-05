# Claude Docker Sandbox

Docker-based isolation for running Claude Code with `--dangerously-skip-permissions` safely. One command to spin up a sandboxed autonomous Claude session on any project.

Inspired by [incident.io's worktree workflow](https://incident.io/blog/shipping-faster-with-claude-code-and-git-worktrees) and [Rory Bain's gist](https://gist.github.com/rorydbain/e20e6ab0c7cc027fc1599bd2e430117d), extended with Docker containerization, egress firewall, safety hooks, and macOS Keychain auth integration.

## The Problem

Claude Code's `--dangerously-skip-permissions` lets Claude work autonomously without clicking Allow for every action. But running it on your actual machine means Claude has full access to your entire filesystem, credentials, and network.

## The Solution

```bash
w Whmoro/orderguard my-feature --auto
```

This creates a git worktree, spins up a Docker container, and runs Claude inside it. Claude thinks it has full permissions, but it can only access the worktree you gave it. Your Documents, other projects, and system files are completely inaccessible.

## What It Does

- **Creates a git worktree** from `origin/develop` (configurable)
- **Installs dependencies** and copies `.env` files from the main project
- **Launches a Docker container** with the worktree mounted at `/workspace`
- **Runs Claude Code** in autonomous mode inside the container
- **Destroys the container** on exit (`--rm`) — the worktree persists for review
- **Warns you** if `.git/config` was modified during the session

## Quick Reference

```bash
w myorg/myapp feature-x --auto              # Docker autonomous mode
w myorg/myapp feature-x --auto --firewall   # + egress firewall
w myorg/myapp feature-x                     # cd to worktree (no Docker)
w myorg/myapp feature-x claude              # run Claude in worktree (no Docker)
w --list                                    # list all worktrees
w --rm myorg/myapp feature-x               # remove worktree + delete branch
w --rebuild-image                           # rebuild Docker image
```

`<project>` is a relative path under `~/Developer/` (e.g. `Whmoro/orderguard`, `Vibma`). Tab completion is included.

## What's In the Container

- Node.js 24, git, gh CLI, ripgrep, curl, jq, python3, tmux
- Chromium headless (Playwright/Puppeteer)
- Claude Code (native installer)
- `uv`/`uvx` for Python-based MCP servers
- `iptables-legacy` for optional egress firewall
- Non-root `claude` user

## Security

### Docker Isolation

Claude **cannot**: access files outside the worktree, reach your Documents/Desktop/other projects, install system packages, persist processes after exit, create other Docker containers, or access your LAN (ports bound to `127.0.0.1` only).

### Safety Hooks (Docker-only, no-op on host)

Three Claude Code hooks activate inside Docker:

1. **Config Protection** (`protect-claude-config.sh`) — Blocks Edit/Write to Claude config files (settings.json, hooks, plugins, etc.) that could execute code on the host
2. **Bash Guardrails** (`bash-guardrails.sh`) — Blocks destructive commands:
   - `rm -rf` (except build artifacts like `node_modules`, `dist`, `.next`)
   - `git push --force` (suggests `--force-with-lease`)
   - `git reset --hard` (suggests `git stash`)
   - Writing to `.git/hooks/` or `.git/config` (these execute on the host)
   - Recursive `chmod`/`chown`
   - Reading SSH keys or credential files directly
   - Modifying Claude config files via shell
3. **Context Injection** (`docker-context.sh`) — Tells Claude the safety rules at startup so it avoids triggering guardrails

### Additional Security

- `core.hooksPath` set globally to `~/.git-hooks` — git ignores `.git/hooks/` so planted hooks can't execute on host
- Post-session `.git/config` tamper detection
- Credentials cleared from environment before `exec claude` (invisible to `env` and `/proc/self/environ`)
- `.claude.json` mounted read-only as staging copy (prevents race condition with host)
- No Docker socket mounted (cannot create sibling containers)

### Optional Egress Firewall

```bash
w myorg/myapp feature-x --auto --firewall
```

Default-deny iptables firewall that only allows outbound traffic to whitelisted domains. Uses `iptables-legacy` (Docker Desktop doesn't support `nf_tables`). DNS auto-detected from `/etc/resolv.conf`. Blocked requests silently drop (~60s timeout).

Default whitelist: Anthropic API, GitHub, npm, PyPI, Sentry, and common MCP services (Atlassian, Clerk, Figma, ClickUp, Context7, Google Fonts). Edit `docker/init-firewall.sh` to customize.

## MCP Support

| MCP Server | Type | Works? |
|---|---|---|
| stdio MCPs (npx-based) | npx | Yes |
| HTTP/SSE MCPs | network | Yes |
| MCPs with local files | node/uvx (mounted ro) | Yes (add mount) |
| Docker-based MCPs | Docker-in-Docker | No (security) |

For MCPs that reference local files, add read-only volume mounts in `w-function.zsh` (search for "MCP dependencies"). Mount at the exact same host path so MCP configs work unchanged.

## Setup

### Prerequisites

- **macOS** with zsh
- **Docker Desktop** installed and running
- **Claude Code** installed and authenticated (`claude` command works)
- **SSH keys** in `~/.ssh/` with GitHub access
- **jq** installed (`brew install jq`)

### Install

```bash
# Clone the repo
git clone https://github.com/whmoro/claude-docker-sandbox.git
cd claude-docker-sandbox

# Run the installer (copies files, sets up git hooks path)
./install.sh

# Add hooks to your ~/.claude/settings.json
# Merge the contents of settings-hooks.json into your existing settings.
# IMPORTANT: Use $HOME/ in all paths, not hardcoded /Users/yourname/

# Append the w() function to your ~/.zshrc
cat w-function.zsh >> ~/.zshrc

# Customize w-function.zsh in your .zshrc:
# 1. Search for "MCP dependencies" — add your MCP mounts or remove the examples
# 2. Search for "ports=" — change to your dev server ports
# 3. Search for "develop" — change if your default branch is different

# Build the Docker image
source ~/.zshrc
w --rebuild-image

# Test it
w <your-project> test-branch --auto
```

### Option 2: Let Claude Do It

Clone the repo, then open Claude Code and paste this prompt:

> Read the README.md and install.sh in this repo. Run the install script, then merge settings-hooks.json into my ~/.claude/settings.json (keep my existing settings, just add the hooks). Append the contents of w-function.zsh to my ~/.zshrc. The MCP mount lines in the w() function should be commented out by default — I'll customize them later. After everything is set up, run `mkdir -p ~/.git-hooks && git config --global core.hooksPath ~/.git-hooks && source ~/.zshrc && w --rebuild-image` and tell me when it's ready to test.

### What Gets Installed Where

| Source | Destination | Purpose |
|---|---|---|
| `docker/Dockerfile` | `~/.claude/docker/Dockerfile` | Docker image definition |
| `docker/entrypoint.sh` | `~/.claude/docker/entrypoint.sh` | Container startup |
| `docker/init-firewall.sh` | `~/.claude/docker/init-firewall.sh` | Egress firewall |
| `hooks/protect-claude-config.sh` | `~/.claude/hooks/protect-claude-config.sh` | Edit/Write guard |
| `hooks/bash-guardrails.sh` | `~/.claude/hooks/bash-guardrails.sh` | Bash command guard |
| `hooks/docker-context.sh` | `~/.claude/hooks/docker-context.sh` | Context injection |
| `settings-hooks.json` | Merge into `~/.claude/settings.json` | Hook registration |
| `w-function.zsh` | Append to `~/.zshrc` | w() function + completion |

### macOS Keychain Authentication

On macOS, Claude Code stores OAuth credentials in the macOS Keychain (service: `Claude Code-credentials`) and actively deletes the on-disk credentials file. The `w()` function extracts credentials from Keychain at launch and passes them to the container as an environment variable. The entrypoint writes them to disk inside the container, then clears the env var before starting Claude.

Tokens are short-lived (~6 hours). If they expire mid-session, exit the container, run any `claude` command on the host (refreshes the token), then restart.

## Customization

### Firewall Domains

Edit `docker/init-firewall.sh` → `ALLOWED_DOMAINS` array, then `w --rebuild-image`.

### Forwarded Ports

Edit the `ports` array in `w-function.zsh` (in your `.zshrc`).

### Base Branch

Worktrees are created from `origin/develop`. Search for `develop` in `w-function.zsh` and change to `main` or your default branch.

### MCP Mounts

Search for "MCP dependencies" in `w-function.zsh` and add read-only volume mounts for any MCP servers that reference local files on your host.

## Troubleshooting

| Problem | Fix |
|---|---|
| Docker not running | Start Docker Desktop |
| Image not found | `w --rebuild-image` |
| "Not logged in" in container | Run `claude` on host to refresh Keychain, restart |
| "Could not extract credentials" | Run `/login` on host |
| Credentials expired mid-session | Exit, run `claude` on host, restart |
| Port conflict | Busy ports auto-skipped |
| Firewall blocking needed domain | Add to `init-firewall.sh`, rebuild |
| Hook not blocking | Check `settings.json` uses `$HOME/` paths |
| GitHub MCP failed | Expected — Docker-in-Docker disabled |
| `gh` commands fail | Check GH_TOKEN extracted from `.claude.json` |

## License

MIT
