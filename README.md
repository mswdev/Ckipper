# Claude Docker Sandbox

Docker-based isolation for running Claude Code with `--dangerously-skip-permissions` safely. One command to spin up a sandboxed autonomous Claude session on any project.

Inspired by [incident.io's worktree workflow](https://incident.io/blog/shipping-faster-with-claude-code-and-git-worktrees) and [Rory Bain's gist](https://gist.github.com/rorydbain/e20e6ab0c7cc027fc1599bd2e430117d), extended with Docker containerization, egress firewall, safety hooks, and macOS Keychain auth integration.

## The Problem

Claude Code's `--dangerously-skip-permissions` lets Claude work autonomously without clicking Allow for every action. But running it on your actual machine means Claude has full access to your entire filesystem, credentials, and network.

## The Solution

```bash
w Whmoro/orderguard my-feature --docker claude
```

This creates a git worktree, spins up a Docker container, and runs Claude inside it. Claude thinks it has full permissions, but it can only access the worktree you gave it. Your Documents, other projects, and system files are completely inaccessible.

## What It Does

- **Creates a git worktree** from `origin/develop` (or uses an existing branch)
- **Installs dependencies** and copies `.env` files from the main project
- **Launches a Docker container** with the worktree mounted at `/workspace`
- **Entrypoint sets up the environment**: installs Linux-native binaries, configures git identity, authenticates `gh` CLI, sets Turbo cache path, optionally enables firewall
- **Runs Claude Code** in autonomous mode inside the container (when `claude` is specified)
- **Destroys the container** on exit (`--rm`) — the worktree persists for review
- **Warns you** if `.git/config` was modified during the session

## Quick Reference

```bash
w myorg/myapp feature-x --docker claude        # Claude in Docker (skip-permissions)
w myorg/myapp feature-x --docker               # shell in Docker container
w myorg/myapp feature-x --docker --firewall    # Docker + egress firewall
w myorg/myapp feature-x                        # cd to worktree (no Docker)
w myorg/myapp feature-x claude                 # run Claude in worktree (no Docker)
w --list                                       # list all worktrees
w --rm myorg/myapp feature-x                   # remove worktree + delete branch
w --rebuild-image                              # rebuild Docker image
```

`<project>` is a relative path under `~/Developer/` (e.g. `Whmoro/orderguard`, `Vibma`). Tab completion is included.

## What's In the Container

- Node.js 24, git, gh CLI, ripgrep, curl, jq, python3, tmux
- Chromium headless (Playwright/Puppeteer) with `--no-sandbox`
- Claude Code (native installer)
- `uv`/`uvx` for Python-based MCP servers
- `bun`/`bunx` for fast JS runtime and statusline commands
- `iptables-legacy` for optional egress firewall
- Non-root `claude` user

## What the Entrypoint Does

On every container start, `entrypoint.sh` automatically:

1. **Copies `.claude.json`** from read-only staging mount to writable location (prevents race condition with host)
2. **Copies and sanitizes SSH config** from read-only `.ssh-host` staging mount — strips macOS-specific `UseKeychain` option that breaks Linux OpenSSH
3. **Disables Chrome extension checks** via jq (no browser in container)
4. **Writes OAuth credentials** from `CLAUDE_CREDENTIALS` env var to `.credentials.json`
5. **Sets git identity** (`user.name` / `user.email`) from `.claude.json` account info
6. **Disables GPG signing** via `GIT_CONFIG_COUNT` environment variables (no GPG key in container). Uses env vars instead of `git config` so the host's `.git/config` is never modified — the overrides disappear when the container exits
7. **Authenticates `gh` CLI** — unsets `GH_TOKEN`, runs `gh auth login --with-token`, then `gh auth setup-git` (enables `git push` over HTTPS)
8. **Enables egress firewall** if `ENABLE_FIREWALL=1`
9. **Sets `TURBO_CACHE_DIR`** to `/workspace/.turbo/cache` (worktree git root points to unwritable host path)
10. **Forces truecolor statusline** — creates a `bunx` wrapper that injects `FORCE_COLOR=3` (Claude Code doesn't pass it to subprocesses)
11. **Reinstalls native binaries** — `npm install --prefer-offline` replaces macOS binaries (rollup, biome, esbuild, swc) with Linux versions
12. **Clears credential env vars** (`unset CLAUDE_CREDENTIALS GH_TOKEN`) before launching the command
13. **Runs the specified command** — `claude --dangerously-skip-permissions` if `claude` was passed, otherwise drops to an interactive bash shell

## Security

### Docker Isolation

Claude **cannot**: access files outside the worktree, reach your Documents/Desktop/other projects, install system packages, persist processes after exit, create other Docker containers, or access your LAN (ports bound to `127.0.0.1` only).

### Safety Hooks (Docker-only, no-op on host)

Four Claude Code hooks activate inside Docker:

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
4. **Notification Bell** (`notify-bell.sh`) — Sends a terminal bell character (`\a`) on Claude Code notification events, which passes through Docker's TTY to the host terminal. Triggers native notifications (dock bounce, sound) in Ghostty, iTerm2, Warp, and other terminals that support terminal bell

### Additional Security

- `core.hooksPath` set globally to `~/.git-hooks` — git ignores `.git/hooks/` so planted hooks can't execute on host
- GPG signing disabled via `GIT_CONFIG_COUNT` env vars — no file modification, overrides both local and global config, disappears when container exits
- Post-session `.git/config` tamper detection
- Credentials cleared from environment before launching the command (invisible to `env` and `/proc/self/environ`)
- `.claude.json` mounted read-only as staging copy (prevents race condition with host)
- SSH config mounted read-only as staging copy (`.ssh-host`), copied and sanitized by entrypoint — macOS-specific `UseKeychain` stripped
- SSH agent forwarded from host via Docker Desktop socket (`/run/host-services/ssh-auth.sock`) — no private keys copied into container
- `~/.claude` dual-mounted at both `/home/claude/.claude` and the host path (e.g. `/Users/<user>/.claude`) so plugins with hardcoded absolute paths resolve correctly
- No Docker socket mounted (cannot create sibling containers)

### Optional Egress Firewall

```bash
w myorg/myapp feature-x --docker --firewall claude
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

For MCPs that reference local files, add entries to `W_EXTRA_VOLUMES` in `~/.claude/docker/w-config.zsh`. Mount at the exact same host path so MCP configs work unchanged.

A named Docker volume (`claude-uv-cache`) persists the uv/uvx package cache across container restarts. Without it, uvx-based MCP servers cold-start every launch (download Python + clone + install), often exceeding Claude Code's MCP startup timeout.

## Setup

### Prerequisites

- **macOS** with zsh
- **Docker Desktop** installed and running
- **Claude Code** installed and authenticated (`claude` command works)
- **GitHub auth**: SSH keys added to your SSH agent, or `gh auth login` on host
- **jq** installed (`brew install jq`)

### Option 1: Manual Install

```bash
# Clone the repo
git clone https://github.com/whmoro/claude-docker-sandbox.git
cd claude-docker-sandbox

# Run the installer (copies all files, merges hooks, adds source line)
./install.sh

# Customize your config
# Edit ~/.claude/docker/w-config.zsh with your MCP mounts, ports, etc.

# Build the Docker image (takes a few minutes first time)
source ~/.zshrc
w --rebuild-image

# Test it
w <your-project> test-branch --docker claude
```

### Option 2: Let Claude Do It

Clone the repo, then open Claude Code and paste this prompt:

> Read the README.md in this repo and run `./install.sh`. Then run `source ~/.zshrc && w --rebuild-image` and tell me when it's ready to test. Show me what's in `~/.claude/docker/w-config.zsh` so I can customize it.

### What Gets Installed Where

| Source | Destination | Purpose |
|---|---|---|
| `docker/Dockerfile` | `~/.claude/docker/Dockerfile` | Docker image definition |
| `docker/entrypoint.sh` | `~/.claude/docker/entrypoint.sh` | Container startup + environment setup |
| `docker/init-firewall.sh` | `~/.claude/docker/init-firewall.sh` | Egress firewall |
| `hooks/protect-claude-config.sh` | `~/.claude/hooks/protect-claude-config.sh` | Edit/Write guard |
| `hooks/bash-guardrails.sh` | `~/.claude/hooks/bash-guardrails.sh` | Bash command guard |
| `hooks/docker-context.sh` | `~/.claude/hooks/docker-context.sh` | Context injection |
| `hooks/notify-bell.sh` | `~/.claude/hooks/notify-bell.sh` | Notification bell |
| `w-function.zsh` | `~/.claude/docker/w-function.zsh` | w() function (sourced by .zshrc) |
| `w-config.zsh.example` | `~/.claude/docker/w-config.zsh` | User config (ports, mounts, env vars) |
| `settings-hooks.json` | Auto-merged into `~/.claude/settings.json` | Hook registration |

### macOS Keychain Authentication

On macOS, Claude Code stores OAuth credentials in the macOS Keychain (service: `Claude Code-credentials`) and actively deletes the on-disk credentials file. The `w()` function extracts credentials from Keychain at launch and passes them to the container via environment variable. The entrypoint writes them to disk, authenticates `gh` CLI, then clears the env vars before starting Claude.

Tokens are short-lived (~6 hours). If they expire mid-session, exit the container, run any `claude` command on the host (refreshes the token), then restart.

## Testing

After setup, run the comprehensive environment test to verify everything works:

```bash
w <your-project> test-branch --docker claude
```

Then paste the contents of [`test-prompt.md`](test-prompt.md) into the Docker Claude session. It covers 11 sections:

- Entrypoint verification (env vars, git identity, Chrome disabled, Turbo cache, credential clearing from `/proc/self/environ`)
- File system access (read, write, delete, ownership, SSH staging mount, config sanitization)
- Code modification round-trip (Edit tool on mounted files)
- Git operations (status, log, branch, commit, SSH agent forwarding, gh CLI, HTTPS push via credential helper)
- Build tools (npm, biome, turbo, tmux, Chromium headless, uv/uvx, Python)
- Full project build
- Dev servers
- Tests and linting
- MCP and network access
- Safety hooks (4 blocked actions + guardrail bypass testing)
- Container isolation (non-root user, sudo restrictions, no Docker socket, setuid audit)

See `test-prompt.md` for the full prompt and expected results table.

## Customization

### Firewall Domains

Edit `docker/init-firewall.sh` → `ALLOWED_DOMAINS` array, then `w --rebuild-image`.

### Forwarded Ports

Edit `W_PORTS` in `~/.claude/docker/w-config.zsh`.

### Base Branch

Worktrees are created from `origin/develop`. Search for `develop` in `w-function.zsh` (or `~/.claude/docker/w-function.zsh` if deployed) and change to `main` or your default branch.

### MCP Mounts

Add entries to `W_EXTRA_VOLUMES` in `~/.claude/docker/w-config.zsh`. Format: `"host_path:container_path:mode"`.

### Statusline

If you use a custom statusline (like [ccstatusline](https://github.com/sirmalloc/ccstatusline)), add the config and cache mounts to `W_EXTRA_VOLUMES` in `~/.claude/docker/w-config.zsh`:
- **Config mount** (`~/.config/ccstatusline`, read-only) — theme, widget layout, powerline settings
- **Cache mount** (`~/.cache/ccstatusline`, read-write) — shares usage API cache with host to avoid 429 rate limits

The `bun` runtime is included in the container image. The entrypoint creates a `bunx` wrapper that injects `FORCE_COLOR=3` for truecolor statusline output (Claude Code doesn't pass this to subprocesses).

## Updating

Run `w --rebuild-image` to get the latest versions of Claude Code and uv/uvx. The build uses a cache-bust argument so these tools are always re-fetched, while heavier layers (system packages, bun, Chromium) stay cached for fast rebuilds.

If you need to update everything (system packages, bun, gh CLI, Node.js base image), do a full rebuild:

```bash
docker build --no-cache -t claude-dev ~/.claude/docker
```

To clear stale uv/MCP caches (e.g., after permission errors or broken tool installs):

```bash
docker volume rm claude-uv-cache claude-uv-tools
```

The volumes are recreated automatically on the next container start.

## Known Limitations

These are inherent to running Claude Code inside a Docker container on macOS and cannot be fully resolved without upstream changes.

### OAuth Token Expiry Across Host and Container

Claude Code stores OAuth credentials in the macOS Keychain. When the container's Claude refreshes an expired token (~6 hours), the host's token is invalidated server-side. The refreshed token lives in container RAM (tmpfs) and cannot be written back to Keychain from Linux. If you run long container sessions, the host Claude will be logged out. Workaround: run `claude` on the host to re-authenticate.

### Clipboard / Image Paste

Ctrl+V image paste does not work inside the container. Claude Code uses `pbpaste` (macOS-only) to access the system clipboard, which doesn't exist in the Linux container. There is no standard mechanism for forwarding the macOS clipboard into a Docker container. OSC 52 terminal escape sequences can forward text clipboard but not images.

### Voice Mode (`/voice`)

Voice mode requires microphone access, which is unavailable inside the container. Docker Desktop for Mac does not expose the host's microphone to containers. There is no equivalent of the SSH agent forwarding pattern for audio devices on macOS.

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
| `git commit` fails (no identity) | Entrypoint should set this automatically; check `.claude.json` has `oauthAccount` |
| Native binary errors (Exec format) | Run `w --rebuild-image` — entrypoint runs `npm install` to fix platform binaries |
| Turbo cache permission denied | Entrypoint sets `TURBO_CACHE_DIR`; run `w --rebuild-image` if missing |
| Branch already checked out | Switch main repo to different branch: `cd ~/Developer/<project> && git checkout develop` |
| Stale worktree directory | Remove manually: `rm -rf ~/Developer/.worktrees/<project>/<branch>` |
| Statusline not rendering correctly | Add ccstatusline mounts to `W_EXTRA_VOLUMES` in `~/.claude/docker/w-config.zsh`; ensure `bun` is in the image (`w --rebuild-image`) |
| `git push` fails (SSH permission denied) | Ensure SSH keys are added to your agent (`ssh-add -l` to check); Docker Desktop forwards the host's SSH agent automatically |
| GPG signing issues in container | Handled automatically via `GIT_CONFIG_COUNT` env vars; host config is not modified |
| `.env.local` not copied to worktree | Fixed: worktree creation now copies all `.env*` files except `.env.example` |
| uvx MCP server fails to start | Run `w --rebuild-image`; if still broken, delete stale volumes: `docker volume rm claude-uv-cache claude-uv-tools` |
| Claude Code version outdated | Run `w --rebuild-image` — Claude and uv are always re-fetched |
