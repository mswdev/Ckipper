# CLAUDE.md

Docker-based sandbox for running Claude Code with `--dangerously-skip-permissions` safely. The `w()` shell function creates a git worktree, launches a Docker container, and runs Claude autonomously inside it. One command to spin up an isolated session on any project.

## Architecture

- **`w-function.zsh`** — zsh function that manages worktrees (`git worktree add`), builds/runs Docker containers, extracts macOS Keychain credentials, forwards ports, and detects `.git/config` tampering post-session. Includes tab completion.
- **`w-config.zsh.example`** — Template for user-specific Docker config (ports, volume mounts, env vars). Copied to `~/.claude/docker/w-config.zsh` on first install, never overwritten on updates.
- **`docker/Dockerfile`** — `node:24-slim` image with dev tools (git, gh, ripgrep, tmux, Chromium, uv/uvx, bun, Claude Code native installer). Runs as non-root `claude` user.
- **`docker/entrypoint.sh`** — Container startup: copies `.claude.json` from read-only staging mount, writes credentials to disk, sets git identity, disables GPG signing via `GIT_CONFIG_COUNT`, authenticates `gh` CLI, optionally enables firewall, creates `bunx` wrapper for statusline colors, runs `npm install` for Linux binaries, clears credential env vars, then runs the provided command (or drops to bash shell if none).
- **`hooks/`** — Three Claude Code hooks (registered in `settings-hooks.json`):
  - `protect-claude-config.sh` — PreToolUse on Edit/Write: blocks modifications to `.claude/settings.json`, hooks, plugins
  - `bash-guardrails.sh` — PreToolUse on Bash: blocks `rm -rf`, `git push --force`, `git reset --hard`, `.git/hooks` writes, recursive `chmod`/`chown`, credential file reads, Claude config modification via shell
  - `docker-context.sh` — SessionStart: injects safety rules so Claude avoids triggering guardrails
  - All three are no-op on the host (exit early if `/.dockerenv` doesn't exist)
- **`docker/init-firewall.sh`** — Optional `iptables-legacy` egress whitelist (default-deny). Uses `--cap-add=NET_ADMIN`.

## Critical Safety Rules

**Never modify the host's `.git/config` from inside the container.** The container mounts the host's `.git` directory read-write (required for worktree refs to resolve). Any `git config --local` command modifies the host's actual git config. Use `GIT_CONFIG_COUNT` environment variables instead — they take highest priority in git's config precedence and disappear when the container exits.

**Clear credentials from the environment before `exec claude`.** The entrypoint receives `CLAUDE_CREDENTIALS` and `GH_TOKEN` as env vars, writes them to disk, then `unset`s them before `exec`. The `exec` replaces the process, so `/proc/self/environ` is clean. If you add new credential env vars, follow this same pattern.

**`.claude.json` is mounted read-only as `.claude-host.json`.** The entrypoint copies it to a writable location. This prevents the container from racing with the host's Claude process on the same file. If you need data from `.claude.json`, read from the copy, not the mount.

**Hooks prevent accidents, not adversarial bypass.** Absolute paths (`/bin/rm`), language-level file access (`python3 -c "open(...).read()"`), and symlink indirection can bypass the bash guardrails. This is accepted. Don't over-engineer the regex matching.

## Development Workflow

| Change | Action Required |
|--------|----------------|
| `Dockerfile` | `w --rebuild-image` |
| `entrypoint.sh` | `w --rebuild-image` (it's `COPY`'d into the image) |
| `init-firewall.sh` | `w --rebuild-image` (it's `COPY`'d into the image) |
| `w-function.zsh` | `./install.sh` (copies to `~/.claude/docker/`; user config in `w-config.zsh` is preserved) |
| `w-config.zsh.example` | Template only — user's `~/.claude/docker/w-config.zsh` is never overwritten |
| `hooks/*` | Sync to `~/.claude/hooks/` |
| `settings-hooks.json` | `./install.sh` (auto-merged into `~/.claude/settings.json`) |

Two copies of the code exist: this repo (development) and deployed files on the host (`~/.claude/docker/`, `~/.claude/hooks/`). Run `./install.sh` to sync all core files. User customizations live in `~/.claude/docker/w-config.zsh` and are never overwritten.

## Testing

`test-prompt.md` is the validation suite. It has 11 sections covering entrypoint verification, filesystem access, git operations, build tools, safety hooks (including bypass attempts), and container isolation. Run it by starting a Docker session (`w <project> <branch> --docker claude`) and pasting the prompt contents.

## Key Implementation Details

- **npm install in entrypoint**: Replaces macOS native binaries (rollup, biome, esbuild, swc) with Linux ones. This is intentional — the worktree's `node_modules` were installed on macOS.
- **`TURBO_CACHE_DIR`**: Set to `/workspace/.turbo/cache` because worktree git roots resolve to the host's main repo path, which isn't writable in the container.
- **`gh auth`**: Must `unset GH_TOKEN` before `gh auth login --with-token` because gh refuses to store credentials while the env var is set. Then `gh auth setup-git` configures gh as the git credential helper for HTTPS push.
- **`core.hooksPath`**: Set globally to `~/.git-hooks` on the host so git ignores `.git/hooks/` — prevents planted hooks from executing on the host after the container exits.
- **Port forwarding**: Ports that are already in use on the host are silently skipped.
- **Worktree removal** (`w --rm`): Also cleans up the project entry from `~/.claude.json`.
