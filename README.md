# Ckipper (pronounced "skipper")

> _This project is vibe-engineered. I use it personally for my own setup and it works well; use it at your own risk. Works on my machine ;) See [Contributing](#contributing)._

> **Platform:** macOS only — uses macOS Keychain, Docker Desktop, and host SSH agent forwarding.

A lightweight CLI for managing Claude Code accounts, worktrees, and Docker sandboxes.

Inspired by [incident.io's worktree workflow](https://incident.io/blog/shipping-faster-with-claude-code-and-git-worktrees) and [Rory Bain's gist](https://gist.github.com/rorydbain/e20e6ab0c7cc027fc1599bd2e430117d), extended with Docker containerization, an egress firewall, safety hooks, macOS Keychain auth, and per-account isolation across credentials, settings, MCP, plugins, and projects.

## The Problem

`--dangerously-skip-permissions` lets Claude work autonomously without clicking Allow for every action — but on your actual machine it has full access to your filesystem, credentials, and network. Running it inside a container is the whole point.

## The Solution

```bash
ck run myorg/myapp my-feature
```

Creates a git worktree, optionally spins up a Docker container, and runs Claude inside it. Claude thinks it has full permissions but can only see the worktree. Your other projects, system files, and credentials are inaccessible.

## Quick start

```bash
git clone https://github.com/mswdev/Ckipper.git
cd Ckipper
./install.sh        # auto-launches `ckipper setup` at the end
```

`install.sh` deploys files under `~/.ckipper/`, adds the source line to your `.zshrc`, and ends by running the interactive setup wizard. The wizard registers your first Claude account, sets your projects directory, and configures default behaviors. Re-runnable any time via `ckipper setup`.

### Prerequisites

- **macOS** with zsh
- **Docker Desktop** installed and running
- **Claude Code** installed and authenticated (`claude` command works)
- **GitHub auth**: SSH keys added to your SSH agent, or `gh auth login` on host
- **jq** and **gum** installed (`brew install jq gum`)

## Core commands

| Command | Purpose |
| --- | --- |
| `ck setup` | Interactive wizard for configuring Ckipper |
| `ck run <project> <branch>` | Create-or-cd to a worktree, optionally Docker |
| `ck config get/set/unset/list/edit` | View and modify settings |
| `ck account add/list/default/remove/rename/sync/redeploy-hooks` | Manage Claude accounts (see [Sync state between accounts](#sync-state-between-accounts)) |
| `ck worktree run/list/rm/rebuild-image` | Manage git worktrees |
| `ck doctor [--fix]` | Diagnose registry, hooks, schema; optionally repair |
| `ck` (no args) | Interactive launcher menu |

`ck` is a short alias for `ckipper`. `<project>` is a relative path under `$CKIPPER_PROJECTS_DIR` (default `~/Developer/`, e.g. `myorg/myapp`). Tab completion is included.

## Configuration

Ckipper has a single source of truth for user-configurable settings ([`lib/core/schema.zsh`](lib/core/schema.zsh)). Use `ck config` to view and modify settings, or `ck setup` to walk the wizard.

### Global keys

These live in `~/.ckipper/docker/ckipper-config.zsh`.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `CKIPPER_PROJECTS_DIR` | path | `~/Developer` | Base directory containing your git projects |
| `CKIPPER_WORKTREES_DIR` | path | `$projects_dir/.worktrees` | Where worktrees are created |
| `CKIPPER_PORTS` | int array | `(3000)` | Ports to forward from container to host |
| `CKIPPER_DEFAULT_BRANCH` | string | _(empty)_ | Fallback base branch when `origin/HEAD` is unset |
| `CKIPPER_DEP_INSTALL_CMD` | string | `npm install` | Command run after worktree creation; empty = skip |
| `CKIPPER_NOTIFY_BELL` | bool | `true` | Install notify-bell hook into account dirs |
| `CKIPPER_ALIASES_AUTO_SOURCE` | bool | `true` | `install.sh` auto-adds aliases.zsh source line to `.zshrc` |

`CKIPPER_EXTRA_VOLUMES` and `CKIPPER_EXTRA_ENV` are also defined in the same file (raw zsh arrays, not schema-managed). See "MCP support" below.

### Per-account preferences

These live in `~/.ckipper/accounts.json` under each account's `preferences` block.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `always_docker` | bool | `false` | Default `--docker` on for this account |
| `always_firewall` | bool | `false` | Default `--firewall` on for this account |
| `ssh_forward` | bool | `true` | Forward host `~/.ssh` into containers run with this account |

### Flag override semantics

Per-account preferences populate flag defaults; pass `--no-docker` / `--no-firewall` / `--no-ssh-forward` to override per invocation. Conversely, pass `--docker` / `--firewall` / `--ssh-forward` to opt in for a single invocation when the preference is off.

## Multiple accounts

Run a personal account in one terminal and a work account in another, fully isolated. Each gets its own credentials, MCP servers, plugins, projects, and session history.

### Add an account

```bash
ckipper account add work
```

`ckipper` walks you through `/login` and registers the account. Repeat for every account you want.

### Use an account

```bash
claude-work                                  # auto-generated launcher
work                                         # bare-name shortcut (skipped if it would shadow an existing command)
CLAUDE_CONFIG_DIR=~/.claude-work claude      # raw form
```

`ckipper account add` re-sources `aliases.zsh` in your current shell, so new launchers are usable immediately — no `exec zsh`.

### Inside Docker

```bash
ck run myorg/app feature --account work --docker
```

If you're already in a terminal where `CLAUDE_CONFIG_DIR` is set (e.g., via `claude-work`), `ckipper run` picks up the account automatically — no flag needed.

### List, default, remove

```bash
ckipper account list
ckipper account default personal
ckipper account remove old-account
```

### How accounts are stored

- Per-account state lives in `~/.claude-<name>/` (analogous to the legacy `~/.claude/`).
- The registry mapping accounts to dirs and Keychain services lives at `~/.ckipper/accounts.json` (chmod 600, atomic writes via `flock`). The file is on `accounts.json` schema v2 — preferences (`always_docker`, `always_firewall`, `ssh_forward`) are stored per account.
- Auto-generated `~/.ckipper/aliases.zsh` defines `claude-<name>` (and a bare `<name>` shortcut, when it doesn't shadow an existing command) per registered account.
- Hooks under `~/.ckipper/hooks/` are the canonical source — they're synced into each registered account dir automatically after install/setup.

### Don't run the same account in two sessions

Two terminals running the **same** account simultaneously will hit a known OAuth refresh-token race ([upstream issue #24317](https://github.com/anthropics/claude-code/issues/24317)) — symptoms: frequent re-login prompts, lost sessions.

- **Safe:** `claude-personal` in one terminal, `claude-work` in another. Different accounts, different refresh tokens, no race.
- **Bad:** `claude-personal` in two terminals at once.

If you want concurrent runs of the *same* account, register it twice under two names (`personal-a`, `personal-b`) — though this means re-`/login` for each.

## Sync state between accounts

`ckipper account sync` copies state between registered accounts — MCP servers, settings, agents, commands, skills, user hooks, etc. — interactively by default, with one source and one or more destinations.

### Syncable types

| Type | What it covers |
|---|---|
| `mcp` | `.claude.json` `.mcpServers` (per server) |
| `settings` | `settings.json` top-level + nested keys (excludes `.hooks`) |
| `claude-md` | `CLAUDE.md` (user memory) |
| `agents` | `agents/*.md` |
| `commands` | `commands/*.md` |
| `output-styles` | `output_styles/*.md` |
| `skills` | `skills/<name>/` (per-directory; symlinks preserved) |
| `statusline` | `settings.json` `.statusLine` + referenced script (if internal to the account dir) |
| `hooks` | User-written hooks under `<account>/hooks/` (filtered against the install allowlist) + paired `settings.json` `.hooks` entries |
| `prefs` | Account preferences in `accounts.json` (`always_docker`, `always_firewall`, `ssh_forward`) |

Plugins are not a separate type — sync `enabledPlugins` + `extraKnownMarketplaces` (both in the `settings` type) and Claude Code re-fetches the plugins on the destination's next launch.

### Common commands

```sh
# Full interactive wizard — picks source, targets, and types
ckipper account sync

# One-shot single type
ckipper account sync personal work --include mcp

# Bundle: every user-customization (no prefs)
ckipper account sync personal work --include customizations

# Multi-destination
ckipper account sync personal work client1 client2 --include all

# Dry run (summary only, no writes)
ckipper account sync personal work --include all --dry-run

# Apply without confirm prompt (for scripting)
ckipper account sync personal work --include all --yes
```

### Named bundles

| Bundle | Resolves to |
|---|---|
| `all` | every type |
| `customizations` | mcp, settings, claude-md, agents, commands, output-styles, skills, statusline, hooks |
| `claude-config` | mcp, settings, hooks |
| `preferences` | prefs |

### Safeguards & undo

Every destructive write is preceded by a copy to `<dst>/.ckipper-sync-backups/<UTC-ISO-ts>-from-<source>/`. The summary table prints the backup directory path before applying. To restore:

```sh
ckipper account sync undo work          # restore most recent backup
ckipper account sync undo work --pick   # gum-pick from backup ledger
ckipper account sync undo work --list   # print backup directory paths
```

Sync refuses to write when Claude is running with the destination's config dir (override with `--force` if you understand the risk).

### Sync vs. redeploy-hooks

These two commands sound similar but do different things:

- **`ckipper account sync ... --include hooks`** — peer-to-peer copy of *user-written* hooks (any hook file in `<account>/hooks/` whose filename does NOT match a ckipper-managed install hook). Includes the paired `settings.json` `.hooks` entry.
- **`ckipper account redeploy-hooks`** — pushes the ckipper safety hooks (`bash-guardrails`, `protect-claude-config`, `docker-context`, `notify-bell`) from `~/.ckipper/hooks/` to every registered account. Run after editing a script in the install dir.

## Security

### Docker isolation

Claude **cannot**: access files outside the worktree, reach your Documents/Desktop/other projects, install system packages, persist processes after exit, create other Docker containers, or access your LAN (ports bound to `127.0.0.1` only).

**What Claude *can* do inside the container:**

- Full read/write on the worktree (`/workspace`).
- Read/write on the parent repo's `.git/` directory (so commits, fetches, and branch ops work).
- Read/write on the active per-account dir (`~/.claude-<name>/`).
- Read a copy of your `~/.ssh` contents — staged read-only at `~/.ssh-host` and copied into the container's tmpfs at `~/.ssh` on startup, **only when `ssh_forward` is enabled** for the account. The `ssh_forward` per-account preference toggles whether `~/.ssh` is mounted into containers; set it to `false` for accounts that don't need git push over SSH. The copy lives only in container RAM and disappears when the container exits.
- Use the host's SSH agent (forwarded via `/run/host-services/ssh-auth.sock`, also gated by `ssh_forward`) and a `gh`-authenticated session for HTTPS pushes.
- Outbound network — unrestricted by default; default-deny with a domain whitelist when `--firewall` is set.

### Prompt injection: the agent inside is still a target

Container isolation contains accidents and outright host-level escalation; it does not stop a successful prompt-injection attack from doing damage *with* Claude's legitimate access. An attacker-controlled input — a poisoned README in a dependency, a hostile MCP server, a fetched URL, a GitHub issue body that Claude reads, a malicious commit message — can try to convince Claude to act against you using the access it already has. That includes writing files anywhere in the worktree, committing and pushing to your remote (the SSH agent is forwarded and `gh` is authenticated), reading the in-container copy of `~/.ssh` and the per-account `.claude.json`, and sending data outbound to any whitelisted domain. Treat untrusted inputs accordingly: be cautious about what repos you point Claude at, what MCP servers you install, and what URLs you ask it to fetch. The `--firewall` mode meaningfully shrinks the exfiltration surface but does not eliminate it (GitHub itself is whitelisted).

### Safety hooks (Docker-only, no-op on host)

These hooks are UX guardrails, not a security boundary — the container, the optional egress firewall, and the absence of host write access are the actual isolation. Four Claude Code hooks activate inside Docker:

1. **Config Protection** (`protect-claude-config.sh`) — Blocks Edit/Write to Claude config files (settings.json, hooks, plugins, etc.) that could execute code on the host
2. **Bash Guardrails** (`bash-guardrails.sh`) — Blocks destructive commands run via the Bash tool (the Read tool is not hooked, so this is not a defense against direct file reads):
   - `rm -rf` (except build artifacts like `node_modules`, `dist`, `.next`)
   - `git push --force` (suggests `--force-with-lease`)
   - `git reset --hard` (suggests `git stash`)
   - Writing to `.git/hooks/` or `.git/config` (these execute on the host)
   - Recursive `chmod`/`chown`
   - Reading SSH keys or credential files via shell commands like `cat`/`cp`/`base64` (Bash-tool only — the Read tool is not hooked, so this catches scripted exfiltration, not direct reads)
   - Modifying Claude config files via shell
3. **Context Injection** (`docker-context.sh`) — Tells Claude the safety rules at startup so it avoids triggering guardrails
4. **Notification Bell** (`notify-bell.sh`) — Sends a terminal bell character (`\a`) on Claude Code notification events. Triggers native notifications (dock bounce, sound) in Ghostty, iTerm2, Warp, and other terminals that support terminal bell. Toggle install via `CKIPPER_NOTIFY_BELL`.

### Additional security

- `core.hooksPath` set globally to `~/.git-hooks` — git ignores `.git/hooks/` so planted hooks can't execute on host. `install.sh` only sets this if you don't already have a different value (so husky/pre-commit/etc. are preserved); the global setting is overridable by per-repo config, so it isn't an absolute backstop.
- GPG signing disabled via `GIT_CONFIG_COUNT` env vars — no file modification, overrides both local and global config, disappears when container exits
- Post-session `.git/config` tamper detection
- Credentials cleared from environment before launching the command (invisible to `env` and `/proc/self/environ`)
- Per-account `.claude.json` is bind-mounted RW; container mutations propagate to the host file (intentional, gated by the same-account-twice advisory)
- SSH config mounted read-only as staging copy (`.ssh-host`), copied and sanitized by entrypoint — macOS-specific `UseKeychain` stripped. Gated by the per-account `ssh_forward` preference.
- Per-account `~/.claude-<name>` mounted at the same host path inside the container so plugins with hardcoded absolute paths resolve correctly
- No Docker socket mounted (cannot create sibling containers)

### Optional egress firewall

```bash
ck run myorg/myapp feature-x --docker --firewall
```

Default-deny iptables firewall that only allows outbound traffic to whitelisted domains. Uses `iptables-legacy` (Docker Desktop doesn't support `nf_tables`). DNS auto-detected from `/etc/resolv.conf`. Blocked requests silently drop (~60s timeout).

Default whitelist: Anthropic API, GitHub, npm, PyPI, Sentry, and common MCP services (Atlassian, Clerk, Figma, ClickUp, Context7, Google Fonts). Edit `docker/init-firewall.sh` to customize.

Default-deny applies to IPv4. Container IPv6 is off by default in Docker Desktop; if you've enabled it, keep it disabled when running with `--firewall` until IPv6 default-deny is in place.

### macOS Keychain authentication

On macOS, Claude Code stores OAuth credentials in the macOS Keychain (service: `Claude Code-credentials`) and actively deletes the on-disk credentials file. `ckipper run` extracts credentials from Keychain at launch and passes them to the container via environment variable. The entrypoint writes them to disk, authenticates `gh` CLI, then clears the env vars before starting Claude.

Tokens are short-lived (~6 hours). If they expire mid-session, exit the container, run any `claude` command on the host (refreshes the token), then restart.

## MCP support

| MCP Server | Type | Works? |
|---|---|---|
| stdio MCPs (npx-based) | npx | Yes |
| HTTP/SSE MCPs | network | Yes |
| MCPs with local files | node/uvx (mounted ro) | Yes (add mount) |
| Docker-based MCPs | Docker-in-Docker | No (security) |

> **Supply-chain note:** an MCP server is third-party code that runs inside the container with the same access Claude has — full RW on the worktree, the per-account `.claude.json`, and outbound network. Pin versions where the registry supports it, audit servers before adding them, and remove servers you no longer use.

For MCPs that reference local files, add entries to `CKIPPER_EXTRA_VOLUMES` in `~/.ckipper/docker/ckipper-config.zsh`. Mount at the exact same host path so MCP configs work unchanged.

Two named Docker volumes support uvx-based MCP servers:
- **`claude-uv-cache`** — persists the uv package cache (downloaded wheels, git clones) across container restarts
- **`claude-uv-tools`** — persists pre-installed tool environments and the uv-managed Python interpreter

The entrypoint pre-installs uvx-based MCP servers before Claude starts and rewrites the container's `.claude.json` to invoke the installed binary directly. This eliminates the network freshness check and ephemeral venv creation that cause intermittent MCP startup timeouts.

## Customization

All schema-managed settings are reachable via `ck config get/set/unset/list/edit` or the `ck setup` wizard. Non-schema items in `~/.ckipper/docker/ckipper-config.zsh` (`CKIPPER_EXTRA_VOLUMES`, `CKIPPER_EXTRA_ENV`) and the firewall whitelist (`docker/init-firewall.sh`) are still edited by hand.

## Updating

### Update the host-side install (Ckipper itself)

```bash
cd /path/to/Ckipper
git pull
./install.sh           # or: make install
source ~/.zshrc
```

`install.sh` is idempotent. It re-deploys `~/.ckipper/docker/` (entry scripts, Dockerfile, entrypoint, `lib/` tree) and `~/.ckipper/hooks/`. Your `accounts.json`, `aliases.zsh`, and `ckipper-config.zsh` are preserved. **After updating, run `ckipper setup` to pick up new schema keys.**

### Update the container

```bash
ck wt rebuild-image
```

Updates everything in the container — system packages, Claude Code, uv/uvx, bun, gh CLI, and Chromium. The build cache-busts all layers so nothing goes stale. Only the base image (`node:24-slim`) is cached; pull it manually with `docker pull node:24-slim` if needed.

To clear stale uv/MCP caches (e.g., after permission errors or broken tool installs):

```bash
docker volume rm claude-uv-cache claude-uv-tools
```

The volumes are recreated automatically on the next container start.

## Known limitations (Docker mode only)

These apply only when you launch Claude Code inside the Ckipper Docker container (`ck run ... --docker`). On the host, these features work normally. They cannot be fully resolved without upstream changes.

### OAuth token expiry across host and container

Claude Code stores OAuth credentials in the macOS Keychain. When the container's Claude refreshes an expired token (~6 hours), the host's token is invalidated server-side. The refreshed token lives in container RAM (tmpfs) and cannot be written back to Keychain from Linux. If you run long container sessions, the host Claude will be logged out. Workaround: run `claude` on the host to re-authenticate.

### Clipboard / image paste

Ctrl+V image paste does not work inside the container. Claude Code uses `pbpaste` (macOS-only) to access the system clipboard, which doesn't exist in the Linux container. There is no standard mechanism for forwarding the macOS clipboard into a Docker container. OSC 52 terminal escape sequences can forward text clipboard but not images.

### Voice mode (`/voice`)

Voice mode requires microphone access, which is unavailable inside the container. Docker Desktop for Mac does not expose the host's microphone to containers. There is no equivalent of the SSH agent forwarding pattern for audio devices on macOS.

### Claude in Chrome MCP

The [Claude in Chrome](https://www.anthropic.com/news/claude-for-chrome) browser extension cannot connect to Claude Code inside the container. The extension's discovery mechanism doesn't bridge the host/container boundary, so the extension reports "Browser extension is not connected." Reference: [#25506](https://github.com/anthropics/claude-code/issues/25506). Workaround: run Claude Code on the host (without `--docker`) when you need the Chrome extension.

### Custom system-sound hooks

User-written hooks that shell out to macOS audio/AppleScript binaries (`afplay`, `say`, `osascript`) won't work inside the container — the binaries don't exist on Linux and there's no host audio device. Ckipper's built-in `notify-bell.sh` sidesteps this by emitting the terminal bell character (`\a`), which most modern terminals translate into a system notification. If you author a hook that needs richer host-only notifications, gate it on `[ ! -f /.dockerenv ]` (the same idiom every built-in safety hook uses) so it no-ops in the container.

## Multi-account caveats (host and Docker)

These apply to the multi-account model in general — they're upstream Claude Code behavior, not Ckipper bugs, and they apply equally on the host and inside Docker. Ckipper papers over some of them; others you should know about.

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

`mcpServers` lives in each account's `.claude.json`. When you `ckipper account add <new>`, the new account starts with **zero** user-scoped MCP servers. Use `ckipper account sync <from> <new> --include mcp` (or run the wizard with no args) to copy them — see [Sync state between accounts](#sync-state-between-accounts).

### Plugins and marketplaces are per-account

`enabledPlugins` and `extraKnownMarketplaces` (in `settings.json`) are per-account. The `~/.ckipper/plugins/known_marketplaces.json` cache is independent per account dir.

### Diagnose anytime

`ckipper doctor` runs a full health check: registry validity, account dir presence, `.claude.json`/`settings.json`/`hooks/` per-account, Keychain entries, `~/.zshrc` source lines, schema validation against `ckipper-config.zsh`, and `accounts.json` v2 preferences shape. Run it whenever something looks off; pass `--fix` for guided in-place repair.

## Troubleshooting

| Problem | Fix |
|---|---|
| Docker not running | Start Docker Desktop |
| Image not found | `ck wt rebuild-image` |
| "Not logged in" in container | Run `claude` on host to refresh Keychain, restart |
| "Could not extract credentials" | Run `/login` on host |
| Credentials expired mid-session | Exit, run `claude` on host, restart |
| Port conflict | Busy ports auto-skipped |
| Firewall blocking needed domain | Add to `init-firewall.sh`, rebuild |
| Hook not blocking | Run `ckipper doctor --fix` |
| GitHub MCP failed | Expected — Docker-in-Docker disabled |
| `gh` commands fail | Check GH_TOKEN extracted from `.claude.json` |
| `git commit` fails (no identity) | Entrypoint should set this automatically; check `.claude.json` has `oauthAccount` |
| Native binary errors (Exec format) | Run `ck wt rebuild-image` — entrypoint runs `npm install` to fix platform binaries |
| Branch already checked out | Switch main repo to different branch: `cd $CKIPPER_PROJECTS_DIR/<project> && git checkout develop` |
| Stale worktree directory | `ck wt rm <project> <branch>` |
| `git push` fails (SSH permission denied) | Ensure SSH keys are added to your agent (`ssh-add -l` to check) and `ssh_forward` is enabled for the active account |
| GPG signing issues in container | Handled automatically via `GIT_CONFIG_COUNT` env vars; host config is not modified |
| `.env.local` not copied to worktree | Worktree creation copies all `.env*` files except `.env.example` |
| uvx MCP server fails to start | Run `ck wt rebuild-image`; if still broken, delete stale volumes: `docker volume rm claude-uv-cache claude-uv-tools` |
| Claude Code version outdated | Run `ck wt rebuild-image` — Claude and uv are always re-fetched |

## Contributing

PRs welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the workflow, code style, and how to run the test suite (`make bootstrap && make test`).

## Security disclosure

Found a vulnerability? See [`SECURITY.md`](SECURITY.md) for private reporting. Please do not open a public issue.

## License

MIT — see [`LICENSE`](LICENSE).
