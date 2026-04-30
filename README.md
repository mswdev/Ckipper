# Ckipper (pronounced "skipper")

Docker-based isolation for running Claude Code with `--dangerously-skip-permissions` safely, plus multi-account support: run a personal account in one terminal and a work account in another, fully isolated.

Inspired by [incident.io's worktree workflow](https://incident.io/blog/shipping-faster-with-claude-code-and-git-worktrees) and [Rory Bain's gist](https://gist.github.com/rorydbain/e20e6ab0c7cc027fc1599bd2e430117d), extended with Docker containerization, an egress firewall, safety hooks, macOS Keychain auth, and per-account isolation across credentials, settings, MCP, plugins, and projects.

## The Problem

`--dangerously-skip-permissions` lets Claude work autonomously without clicking Allow for every action — but on your actual machine it has full access to your filesystem, credentials, and network.

## The Solution

```bash
w myorg/myapp my-feature --docker claude
```

Creates a git worktree, spins up a Docker container, and runs Claude inside it. Claude thinks it has full permissions but can only see the worktree. Your other projects, system files, and credentials are inaccessible.

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
w myorg/myapp feature-x --docker claude              # Claude in Docker (skip-permissions)
w myorg/myapp feature-x --docker --account work     # use a specific Ckipper account
w myorg/myapp feature-x --docker                     # shell in Docker container
w myorg/myapp feature-x --docker --firewall         # Docker + egress firewall
w myorg/myapp feature-x                              # cd to worktree (no Docker)
w myorg/myapp feature-x claude                       # run Claude in worktree (no Docker)
w --list                                             # list all worktrees
w --rm myorg/myapp feature-x                         # remove worktree + delete branch
w --rebuild-image                                    # rebuild Docker image

ckipper add <name>                                   # register a Claude account (interactive /login)
ckipper list                                         # show registered accounts
ckipper default <name>                               # set the default account
ckipper rename <old> <new>                           # rename an account in place
ckipper remove <name>                                # unregister (does not delete the dir)
ckipper sync <from> <to>                             # copy MCP/settings/plugins between accounts
ckipper sync-hooks                                   # re-deploy hooks into every account dir
ckipper repair-plugins <name>                        # fix stale ~/.claude/ paths in plugin metadata
ckipper doctor                                       # diagnostic checklist
ckipper migrate                                      # one-time migration from claude-docker-sandbox
```

`ck` is a short alias for `ckipper`. `<project>` is a relative path under `$W_PROJECTS_DIR` (default `~/Developer/`, e.g. `myorg/myapp`). Tab completion is included. See [Projects Directory](#projects-directory) to change the base path.

## Multiple accounts

Run a personal account in one terminal and a work account in another, fully isolated. Each gets its own credentials, MCP servers, plugins, projects, and session history.

### Add an account

```bash
ckipper add work
```

`ckipper` walks you through `/login` and registers the account. Repeat for every account you want.

### Use an account

```bash
claude-work                                  # auto-generated launcher
work                                         # bare-name shortcut (skipped if it would shadow an existing command)
CLAUDE_CONFIG_DIR=~/.claude-work claude      # raw form
```

`ckipper add` re-sources `aliases.zsh` in your current shell, so new launchers are usable immediately — no `exec zsh`.

### Inside Docker

```bash
w myorg/app feature --account work --docker claude
```

If you're already in a terminal where `CLAUDE_CONFIG_DIR` is set (e.g., via `claude-work`), `w` picks up the account automatically — no flag needed.

### List, default, remove

```bash
ckipper list
ckipper default personal
ckipper remove old-account
```

### How accounts are stored

- Per-account state lives in `~/.claude-<name>/` (analogous to the legacy `~/.claude/`).
- The registry mapping accounts to dirs and Keychain services lives at `~/.ckipper/accounts.json` (chmod 600, atomic writes via `flock`).
- Auto-generated `~/.ckipper/aliases.zsh` defines `claude-<name>` (and a bare `<name>` shortcut, when it doesn't shadow an existing command) per registered account.
- Hooks under `~/.ckipper/hooks/` are the canonical source — `ckipper sync-hooks` copies them per-account and rewrites `settings.json` paths.

## ⚠️ Don't run the same account in two sessions

Two terminals running the **same** account simultaneously will hit a known OAuth refresh-token race ([upstream issue #24317](https://github.com/anthropics/claude-code/issues/24317)) — symptoms: frequent re-login prompts, lost sessions.

- **Safe:** `claude-personal` in one terminal, `claude-work` in another. Different accounts, different refresh tokens, no race.
- **Bad:** `claude-personal` in two terminals at once.

If you want concurrent runs of the *same* account, register it twice under two names (`personal-a`, `personal-b`) — though this means re-`/login` for each.

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

1. **Reads `.claude.json`** from the bind-mounted per-account dir (`$CLAUDE_CONFIG_DIR/.claude.json`) and mutates chrome flags + MCP rewrites in place. Race protection is via the documented "don't run the same account in two sessions" rule.
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
12. **Fixes volume permissions** — runs `chown` on named volumes that may retain stale UIDs from older image builds
13. **Pre-installs uvx-based MCP servers** — parses `.claude.json` for MCP servers that use `uvx`, pre-installs them with `uv tool install`, and rewrites the config to invoke the installed binary directly (avoids Claude's MCP startup timeout)
14. **Clears credential env vars** (`unset CLAUDE_CREDENTIALS GH_TOKEN`) before launching the command
15. **Runs the specified command** — `claude --dangerously-skip-permissions` if `claude` was passed, otherwise drops to an interactive bash shell

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
- Per-account `.claude.json` is bind-mounted RW; container mutations propagate to the host file (intentional, gated by the same-account-twice advisory)
- SSH config mounted read-only as staging copy (`.ssh-host`), copied and sanitized by entrypoint — macOS-specific `UseKeychain` stripped
- SSH agent forwarded from host via Docker Desktop socket (`/run/host-services/ssh-auth.sock`) — no private keys copied into container
- Per-account `~/.claude-<name>` mounted at the same host path inside the container so plugins with hardcoded absolute paths resolve correctly
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

For MCPs that reference local files, add entries to `W_EXTRA_VOLUMES` in `~/.ckipper/docker/w-config.zsh`. Mount at the exact same host path so MCP configs work unchanged.

Two named Docker volumes support uvx-based MCP servers:
- **`claude-uv-cache`** — persists the uv package cache (downloaded wheels, git clones) across container restarts
- **`claude-uv-tools`** — persists pre-installed tool environments and the uv-managed Python interpreter

The entrypoint pre-installs uvx-based MCP servers before Claude starts and rewrites the container's `.claude.json` to invoke the installed binary directly. This eliminates the network freshness check and ephemeral venv creation that cause intermittent MCP startup timeouts.

## Migrating from claude-docker-sandbox

If you've been running this project under its previous name with a single `~/.claude/docker/` install, run:

```bash
ckipper migrate
```

This will:

1. Refuse to run if any `claude` process is currently active (quit them first).
2. Copy `~/.claude/docker/` → `~/.ckipper/`.
3. Offer to register your existing `~/.claude` as the `personal` account. If you accept: rename `~/.claude` → `~/.claude-personal`, probe Keychain for the matching credential entry, and write the registry. **No symlink is created** — after migration, you launch Claude with `claude-personal` (bare `claude` will start a fresh login).
4. If anything fails, the rename automatically reverses (rollback).

Then add additional accounts:

```bash
ckipper add work
```

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
git clone https://github.com/mswdev/Ckipper.git
cd Ckipper

# Run the installer (copies all files, merges hooks, adds source line)
./install.sh

# Customize your config
# Edit ~/.ckipper/docker/w-config.zsh with your MCP mounts, ports, etc.

# Build the Docker image (takes a few minutes first time)
source ~/.zshrc
w --rebuild-image

# Test it
w <your-project> test-branch --docker claude
```

### Option 2: Let Claude Do It

Clone the repo, then open Claude Code and paste this prompt:

> Read the README.md in this repo and run `./install.sh`. Then run `source ~/.zshrc && w --rebuild-image` and tell me when it's ready to test. Show me what's in `~/.ckipper/docker/w-config.zsh` so I can customize it.

### What Gets Installed Where

| Source | Destination | Purpose |
|---|---|---|
| `docker/Dockerfile` | `~/.ckipper/docker/Dockerfile` | Docker image definition |
| `docker/entrypoint.sh` | `~/.ckipper/docker/entrypoint.sh` | Container startup + environment setup |
| `docker/init-firewall.sh` | `~/.ckipper/docker/init-firewall.sh` | Egress firewall |
| `hooks/protect-claude-config.sh` | `~/.ckipper/hooks/protect-claude-config.sh` | Edit/Write guard |
| `hooks/bash-guardrails.sh` | `~/.ckipper/hooks/bash-guardrails.sh` | Bash command guard |
| `hooks/docker-context.sh` | `~/.ckipper/hooks/docker-context.sh` | Context injection |
| `hooks/notify-bell.sh` | `~/.ckipper/hooks/notify-bell.sh` | Notification bell |
| `w-function.zsh` | `~/.ckipper/docker/w-function.zsh` | w() launcher entry (sourced by .zshrc) |
| `ckipper.zsh` | `~/.ckipper/docker/ckipper.zsh` | ckipper CLI entry (account management) |
| `lib/core/`, `lib/ckipper/`, `lib/w/` | `~/.ckipper/docker/lib/` | Shell module tree (sourced by entry scripts; test files excluded) |
| `templates/w-config.zsh.example` | `~/.ckipper/docker/w-config.zsh` | User config (ports, mounts, env vars) |
| `templates/settings-template.json` | `~/.ckipper/settings-template.json` | Hook settings template (applied per-account by `ckipper sync-hooks`) |

### macOS Keychain Authentication

On macOS, Claude Code stores OAuth credentials in the macOS Keychain (service: `Claude Code-credentials`) and actively deletes the on-disk credentials file. The `w()` function extracts credentials from Keychain at launch and passes them to the container via environment variable. The entrypoint writes them to disk, authenticates `gh` CLI, then clears the env vars before starting Claude.

Tokens are short-lived (~6 hours). If they expire mid-session, exit the container, run any `claude` command on the host (refreshes the token), then restart.

## Testing

After setup, run the comprehensive environment test to verify everything works:

```bash
w <your-project> test-branch --docker claude
```

Then paste the contents of [`docs/test-prompt.md`](docs/test-prompt.md) into the Docker Claude session. It covers 12 sections:

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

See `docs/test-prompt.md` for the full prompt and expected results table.

## Customization

### Projects Directory

`w()` resolves project paths under `$W_PROJECTS_DIR` (default `$HOME/Developer`). To use a different location (e.g. `~/code`), set `W_PROJECTS_DIR` in `~/.ckipper/docker/w-config.zsh`. Worktrees default to `$W_PROJECTS_DIR/.worktrees`; override with `W_WORKTREES_DIR` if you want them elsewhere.

### Firewall Domains

Edit `docker/init-firewall.sh` → `ALLOWED_DOMAINS` array, then `w --rebuild-image`.

### Forwarded Ports

Edit `W_PORTS` in `~/.ckipper/docker/w-config.zsh`.

### Base Branch

Worktrees are created from `origin/develop`. Search for `develop` in `w-function.zsh` (or `~/.ckipper/docker/w-function.zsh` if deployed) and change to `main` or your default branch.

### MCP Mounts

Add entries to `W_EXTRA_VOLUMES` in `~/.ckipper/docker/w-config.zsh`. Format: `"host_path:container_path:mode"`.

### Statusline

If you use a custom statusline (like [ccstatusline](https://github.com/sirmalloc/ccstatusline)), add the config and cache mounts to `W_EXTRA_VOLUMES` in `~/.ckipper/docker/w-config.zsh`:
- **Config mount** (`~/.config/ccstatusline`, read-only) — theme, widget layout, powerline settings
- **Cache mount** (`~/.cache/ccstatusline`, read-write) — shares usage API cache with host to avoid 429 rate limits

The `bun` runtime is included in the container image. The entrypoint creates a `bunx` wrapper that injects `FORCE_COLOR=3` for truecolor statusline output (Claude Code doesn't pass this to subprocesses).

## Updating

### Update the host-side install (Ckipper itself)

```bash
cd /path/to/Ckipper
git pull
./install.sh           # or: make install
source ~/.zshrc
```

`install.sh` is idempotent. It re-deploys `~/.ckipper/docker/` (entry scripts, Dockerfile, entrypoint, `lib/` tree) and `~/.ckipper/hooks/`. Your `accounts.json`, `aliases.zsh`, and `w-config.zsh` are preserved. If hooks changed in the update, run `ckipper sync-hooks` to push the new versions into each registered account dir.

### Update the container

```bash
w --rebuild-image
```

Updates everything in the container — system packages, Claude Code, uv/uvx, bun, gh CLI, and Chromium. The build cache-busts all layers so nothing goes stale. Only the base image (`node:24-slim`) is cached; pull it manually with `docker pull node:24-slim` if needed.

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

## Multi-account Caveats

These apply to the multi-account model in general — they're upstream Claude Code behavior, not Ckipper bugs. Ckipper papers over some of them; others you should know about.

### OAuth refresh token races (upstream)

Two concurrent Claude Code sessions on the same account share a single-use OAuth refresh token. The first to refresh wins; the second gets a 404 and loses authentication. Symptoms: frequent `/login` prompts, lost sessions. References: [#24317](https://github.com/anthropics/claude-code/issues/24317), [#27933](https://github.com/anthropics/claude-code/issues/27933). **Workaround:** different accounts in different terminals (the model Ckipper is built around).

### Credentials silently wiped on failed refresh (upstream)

If a token refresh fails mid-flight (network blip, server error), Claude Code may overwrite the stored credentials with an empty value rather than preserving the old one. Reference: [#29896](https://github.com/anthropics/claude-code/issues/29896). **Recovery:** `claude-<name> /login` again.

### Keychain permission glitches after macOS updates (upstream)

After macOS or Claude Code updates, the Keychain entry can become inaccessible to Claude Code, forcing manual re-`/login` 1–N times per day. Reference: [#19456](https://github.com/anthropics/claude-code/issues/19456). Independent of Ckipper.

### Project-level files are SHARED across accounts (by design)

Files inside a project repo are *not* governed by `CLAUDE_CONFIG_DIR`:

- `<repo>/.claude/settings.json` (committed)
- `<repo>/.claude/settings.local.json` (gitignored)
- `<repo>/.mcp.json` (committed, project-scoped MCP servers)
- `<repo>/CLAUDE.md`

This is usually a feature — your `personal` and `work` accounts working in the same repo see the same project rules and project MCPs. If you don't want that, accounts must work in separate worktrees or separate clones.

### MCP servers are per-account (user-scoped only)

`mcpServers` lives in each account's `.claude.json`. When you `ckipper add <new>`, the new account starts with **zero** user-scoped MCP servers. Two ways to populate:

```bash
ckipper sync personal work                  # default bundle: mcpServers + plugins + statusLine + env
ckipper sync personal work --mcp Vibma,github   # only specific MCPs
ckipper sync personal work --dry-run         # preview before writing
```

### Plugins and marketplaces are per-account

`enabledPlugins` and `extraKnownMarketplaces` (in `settings.json`) are per-account. The `ckipper sync` default bundle includes them; the `~/.ckipper/plugins/known_marketplaces.json` cache is independent per account dir.

### `~/.claude/settings.local.json` may recreate after migration

Despite docs saying every `~/.claude/...` path redirects under `CLAUDE_CONFIG_DIR`, some users observe a stub `~/.claude/settings.local.json` recreating itself (single key: `outputStyle`). It's harmless — `rm -rf ~/.claude` is safe and idempotent. The hook regex blocks writes to `~/.claude/` from inside containers, but the host has no such guard.

### Diagnose anytime

`ckipper doctor` runs a full health check: registry validity, account dir presence, `.claude.json`/`settings.json`/`hooks/` per-account, Keychain entries, `~/.zshrc` source lines, and stub-file presence. Use it after `ckipper migrate` or whenever something looks off.

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
| Branch already checked out | Switch main repo to different branch: `cd $W_PROJECTS_DIR/<project> && git checkout develop` |
| Stale worktree directory | Remove manually: `rm -rf $W_WORKTREES_DIR/<project>/<branch>` |
| Statusline not rendering correctly | Add ccstatusline mounts to `W_EXTRA_VOLUMES` in `~/.ckipper/docker/w-config.zsh`; ensure `bun` is in the image (`w --rebuild-image`) |
| `git push` fails (SSH permission denied) | Ensure SSH keys are added to your agent (`ssh-add -l` to check); Docker Desktop forwards the host's SSH agent automatically |
| GPG signing issues in container | Handled automatically via `GIT_CONFIG_COUNT` env vars; host config is not modified |
| `.env.local` not copied to worktree | Fixed: worktree creation now copies all `.env*` files except `.env.example` |
| uvx MCP server fails to start | Run `w --rebuild-image`; if still broken, delete stale volumes: `docker volume rm claude-uv-cache claude-uv-tools` |
| Claude Code version outdated | Run `w --rebuild-image` — Claude and uv are always re-fetched |

## Contributing

PRs welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the workflow, code style, and how to run the test suite (`make bootstrap && make test`).

## Security

Found a vulnerability? See [`SECURITY.md`](SECURITY.md) for private reporting. Please do not open a public issue.

## License

MIT — see [`LICENSE`](LICENSE).
