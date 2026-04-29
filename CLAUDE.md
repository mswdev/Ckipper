# CLAUDE.md

**Ckipper** (pronounced "skipper") — Docker-based sandbox for running Claude Code with `--dangerously-skip-permissions` safely. The `w()` shell function creates a git worktree, launches a Docker container, and runs Claude autonomously inside it. One command to spin up an isolated session on any project.

## Architecture

- **`w-function.zsh`** — zsh function that manages worktrees (`git worktree add`), builds/runs Docker containers, extracts macOS Keychain credentials, forwards ports, and detects `.git/config` tampering post-session. Resolves the active Ckipper account from `--account`, env, or registered default. Sources `ckipper.zsh` at the bottom. Includes tab completion.
- **`ckipper.zsh`** — multi-account manager. Subcommands: `add`, `list`, `default`, `remove`, `sync-hooks`, `migrate`. Owns the registry at `~/.ckipper/accounts.json` and the auto-generated `~/.ckipper/aliases.zsh`. Sourced by `w-function.zsh` after deployment.
- **`w-config.zsh.example`** — Template for user-specific Docker config (ports, volume mounts, env vars). Copied to `~/.ckipper/docker/w-config.zsh` on first install, never overwritten on updates.
- **`docker/Dockerfile`** — `node:24-slim` image with dev tools (git, gh, ripgrep, tmux, Chromium, uv/uvx, bun, Claude Code native installer). Runs as non-root `claude` user.
- **`docker/entrypoint.sh`** — Container startup: errors out if `CLAUDE_CONFIG_DIR` is unset; mutates `.claude.json` (chrome flags, MCP rewrites) in the bind-mounted account dir, writes credentials to tmpfs, sets git identity, disables GPG signing via `GIT_CONFIG_COUNT`, authenticates `gh` CLI, optionally enables firewall, creates `bunx` wrapper, runs `npm install` for Linux binaries, clears credential env vars, then runs the provided command.
- **`docker/cleanup-projects.py`** — Registry-driven helper invoked by `w` for `--rm` cleanup (removes a worktree entry from every account's `.claude.json`) and worktree creation (copies main project settings into the new worktree entry under the active account).
- **`hooks/`** — Four Claude Code hooks (template at `settings-hooks.json` → deployed to `~/.ckipper/settings-template.json`):
  - `protect-claude-config.sh` — PreToolUse on Edit/Write: blocks modifications to `~/.claude*/...settings|hooks|plugins/...` and anything under `~/.ckipper/`. `~/.claude-host.json` is intentionally allowed (read-only staging mount).
  - `bash-guardrails.sh` — PreToolUse on Bash: blocks `rm -rf`, `git push --force`, `git reset --hard`, `.git/hooks` writes, recursive `chmod`/`chown`, credential file reads, Claude/Ckipper config modification via shell.
  - `docker-context.sh` — SessionStart: injects safety rules so Claude avoids triggering guardrails
  - `notify-bell.sh` — Notification: sends terminal bell (`\a`) so host terminal fires native notifications (dock bounce, sound)
  - All four are no-op on the host (exit early if `/.dockerenv` doesn't exist)
- **`docker/init-firewall.sh`** — Optional `iptables-legacy` egress whitelist (default-deny). Uses `--cap-add=NET_ADMIN`.

## Multi-account model

Each Claude account is a `CLAUDE_CONFIG_DIR=~/.claude-<name>/` directory — analogous to the legacy `~/.claude/`, but namespaced. The registry at `~/.ckipper/accounts.json` (chmod 600, schema version 1) maps account name → `{config_dir, keychain_service, registered_at}`. Atomic writes via `flock` (with `mkdir`-based fallback for systems without `flock`).

`w` resolves the active account in priority order: `--account <name>` > `CLAUDE_CONFIG_DIR` env (matched against registry) > registered default. **No legacy fallback** — if no account resolves, `w` errors out and tells you to register one. Inside the container, the entrypoint requires `CLAUDE_CONFIG_DIR` and exits 1 if unset (no silent fallback).

Companion shell layer: `~/.ckipper/aliases.zsh` is auto-regenerated on every `ckipper add` / `remove` / `rename`, then re-sourced into the calling shell so new launchers work immediately. It contains a `claude-<name>` function per registered account, plus a bare `<name>` shortcut when that name doesn't shadow a PATH binary, builtin, alias, or reserved word (see `_ckipper_bare_alias_safe`). The file is self-contained — sourcing only `aliases.zsh` (without `ckipper.zsh` or `w-function.zsh`) yields a working setup.

`settings-template.json` is **seed-only**. After an account is registered, its `settings.json` diverges (per-account hooks, paths). Re-running `ckipper sync-hooks` refreshes hook paths and copies the canonical `~/.ckipper/hooks/*` into each account; it does not re-apply the template wholesale.

## Critical Safety Rules

**Never modify the host's `.git/config` from inside the container.** The container mounts the host's `.git` directory read-write (required for worktree refs to resolve). Any `git config --local` command modifies the host's actual git config. Use `GIT_CONFIG_COUNT` environment variables instead — they take highest priority in git's config precedence and disappear when the container exits.

**Clear credentials from the environment before `exec claude`.** The entrypoint receives `CLAUDE_CREDENTIALS` and `GH_TOKEN` as env vars, writes them to disk, then `unset`s them before `exec`. The `exec` replaces the process, so `/proc/self/environ` is clean. If you add new credential env vars, follow this same pattern.

**Don't run the same Ckipper account in two sessions.** Per-account `.claude.json` is bind-mounted RW into the container — entrypoint mutations (chrome flags, MCP rewrites) propagate back to the host file. With the multi-account model, the previous read-only staging mount was dropped (macOS Docker Desktop virtiofs cannot create a nested mountpoint under another bind-mount). Race protection now relies on the user advisory: if you need concurrent containers, use different accounts. See README issue #24317 reference.

**Hooks prevent accidents, not adversarial bypass.** Absolute paths (`/bin/rm`), language-level file access (`python3 -c "open(...).read()"`), and symlink indirection can bypass the bash guardrails. This is accepted. Don't over-engineer the regex matching.

**Validate `keychain_service` shape before any `security` call.** The registry stores a per-account Keychain service name (`Claude Code-credentials` optionally followed by `-<hex>`). Both `ckipper add` and `w` validate the shape via `_ckipper_validate_keychain_service` before passing it to `security find-generic-password`. Without this, a tampered registry could feed arbitrary arguments into `security` (command injection vector). Hooks also block writes to `~/.ckipper/accounts.json` so a compromised in-container Claude can't redirect another account's keychain service.

## Development Workflow

| Change | Action Required |
|--------|----------------|
| `Dockerfile` | `w --rebuild-image` |
| `entrypoint.sh` | `w --rebuild-image` (it's `COPY`'d into the image) |
| `init-firewall.sh` | `w --rebuild-image` (it's `COPY`'d into the image) |
| `w-function.zsh` | `./install.sh` (copies to `~/.ckipper/docker/`; user config in `w-config.zsh` is preserved) |
| `ckipper.zsh` | `./install.sh` (copies to `~/.ckipper/docker/`; sourced by `w-function.zsh`) |
| `cleanup-projects.py` | `./install.sh` (copies to `~/.ckipper/docker/`; invoked by `w` for `--rm` and worktree-create sync) |
| `w-config.zsh.example` | Template only — user's `~/.ckipper/docker/w-config.zsh` is never overwritten |
| `hooks/*` | `./install.sh` deploys to `~/.ckipper/hooks/`; per-account copies are written by `ckipper sync-hooks` |
| `settings-hooks.json` | `./install.sh` deploys to `~/.ckipper/settings-template.json` (consumed by `ckipper add` and `ckipper sync-hooks` for per-account `settings.json`) |

Two copies of the code exist: this repo (development) and deployed files on the host (`~/.ckipper/docker/`, `~/.ckipper/hooks/`). Run `./install.sh` to sync all core files. User customizations live in `~/.ckipper/docker/w-config.zsh` and are never overwritten.

## Testing

`test-prompt.md` is the validation suite. It has 12 sections covering entrypoint verification, filesystem access, git operations, build tools, safety hooks (including bypass attempts), container isolation, and **multi-account isolation**. Run it by starting a Docker session (`w <project> <branch> --docker claude`) and pasting the prompt contents. Section 12 must be run in two concurrent containers under different accounts.

## Key Implementation Details

- **npm install in entrypoint**: Replaces macOS native binaries (rollup, biome, esbuild, swc) with Linux ones. This is intentional — the worktree's `node_modules` were installed on macOS.
- **`TURBO_CACHE_DIR`**: Set to `/workspace/.turbo/cache` because worktree git roots resolve to the host's main repo path, which isn't writable in the container.
- **`gh auth`**: Must `unset GH_TOKEN` before `gh auth login --with-token` because gh refuses to store credentials while the env var is set. Then `gh auth setup-git` configures gh as the git credential helper for HTTPS push.
- **`core.hooksPath`**: Set globally to `~/.git-hooks` on the host so git ignores `.git/hooks/` — prevents planted hooks from executing on the host after the container exits.
- **Port forwarding**: Ports that are already in use on the host are silently skipped.
- **Worktree removal** (`w --rm`): Removes the project entry from every registered account's `.claude.json` via `cleanup-projects.py`.
- **Account-aware mounts**: `w` mounts `$active_config_dir:$active_config_dir:rw` (no `/home/claude/.claude` dual mount). Plugins' absolute-path references resolve because the account dir is at the same host path. Credentials still live in container-only tmpfs (`/tmp/claude-creds`) — the host-side symlink target points to a path that doesn't exist outside the container.
