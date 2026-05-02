# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — CLI + onboarding overhaul

### Sync system overhaul

- **New:** `ckipper account sync` is fully interactive by default. Run with no args to pick source, targets, and types via gum pickers; pass positional args to skip the relevant pickers.
- **New:** 10 syncable types covering every shareable Claude Code config category: MCP servers, settings (top-level + nested keys), CLAUDE.md, agents, commands, output-styles, skills, statusline (with internal/external script detection), user-written hooks (filtered against the install allowlist), and account preferences.
- **New:** Named bundles `all`, `customizations`, `claude-config`, `preferences` for `--include` / `--exclude`.
- **New:** Multi-destination support — sync from one account to many in a single invocation.
- **New:** Summary table preview with `git status`-style status badges (`[+]` / `[~]`) and on-demand drill-down for any per-item diff.
- **New:** Timestamped backups before any destructive write — `<dst>/.ckipper-sync-backups/<ts>-from-<source>/` — with manifest-driven restore via `ckipper account sync undo <account> [--pick | --list]`.
- **New:** Hard refusal when Claude is running with the destination's config dir (override with `--force`).
- **New:** Setup wizard offers initial sync after adding a 2nd-or-later account.
- **Renamed:** `ckipper account sync-hooks` → `ckipper account redeploy-hooks`. The new name reflects that it deploys the ckipper-managed safety hooks from the install dir to every account; it is NOT peer-to-peer sync.
- **Removed:** Old flag surface (`--mcp [names]`, `--settings <keys>`, `--all`). The new `--include` / `--exclude` model with bundles supersedes these.

### Added
- `ckipper setup` — interactive wizard for configuring Ckipper. Re-runnable.
- `ckipper config get / set / unset / list / edit` — view and modify settings.
- `ckipper run <project> <branch>` — top-level shortcut for `ckipper worktree run`.
- Bare `ck` (no args) — interactive launcher menu.
- `ckipper doctor --fix` — gum-driven repairs, including the former `repair-plugins` flow.
- Per-account preferences: `always_docker`, `always_firewall`, `ssh_forward`, populating flag defaults for `ck run`/`ck wt run`.
- New global config keys: `CKIPPER_DEFAULT_BRANCH`, `CKIPPER_DEP_INSTALL_CMD`, `CKIPPER_NOTIFY_BELL`, `CKIPPER_ALIASES_AUTO_SOURCE`.
- New flags: `--no-docker`, `--no-firewall`, `--ssh-forward`, `--no-ssh-forward` (override per-account preferences inline).
- Auto-detection of `origin/HEAD` for the worktree base branch.
- Restyled output across `ck account list`, `ck worktree list`, `ck doctor`, and all `--help` text via shared `lib/core/style.zsh`.
- `ck doctor` validates `accounts.json` v2 preferences shape and `ckipper-config.zsh` keys against the schema.

### Changed
- `accounts.json` schema bumped v1 → v2; auto-migrates on first command after upgrade. Backup written to `accounts.json.v1.bak.<timestamp>`.
- `install.sh` now ends by auto-invoking `ckipper setup` in interactive shells.
- `gum` is a hard prereq (added to `install.sh` prereq check and `make bootstrap`).

### Removed
- `ckipper account repair-plugins` (folded into `ckipper doctor --fix`).
- `ckipper account sync-hooks` from public help (still callable; auto-runs after install/setup).

### Notes
- `lib/account/sync.zsh` is intentionally untouched — full sync overhaul ships in a separate future PR.

## [0.2.0] — 2026-04-30 — Breaking changes: merge `w` into `ckipper`

### Removed
- `w()` shell function (replaced by `ckipper worktree run`).
- `ckipper migrate` subcommand (legacy claude-docker-sandbox migration).
- `~/.ckipper/docker/w-function.zsh` (replaced by `~/.ckipper/docker/ckipper.zsh`; `install.sh` deletes the stale file and rewrites `~/.zshrc`).
- `~/.ckipper/docker/w-config.zsh` (replaced by `~/.ckipper/docker/ckipper-config.zsh`; `install.sh` migrates content automatically).
- `~/.zsh/completions/_w` (replaced by `~/.zsh/completions/_ckipper`).

### Renamed
- `lib/w/` → `lib/worktree/`.
- `lib/ckipper/` → `lib/account/`.
- `_w_*` functions → `_ckipper_worktree_*`.
- `_ckipper_*` (account ops) → `_ckipper_account_*` (`_ckipper_doctor*` and the top-level dispatcher helpers stay un-namespaced).
- `W_PROJECTS_DIR` / `W_WORKTREES_DIR` / `W_PORTS` / `W_EXTRA_VOLUMES` / `W_EXTRA_ENV` / `W_REPO_DIR` / `W_COMPLETION_VERSION` → `CKIPPER_*` (same suffix; user-configurable via `ckipper-config.zsh`).
- Worktree runtime globals (`W_FLAG_*`, `W_PROJECT`, `W_BRANCH`, `W_CLI_ACCOUNT`, `W_COMMAND`, `W_ACTIVE_*`, `W_WT_PATH`, `W_RESOLVED_PORTS`, `W_DOCKER_ARGS`, `W_FIND_MAX_DEPTH`) → `CKIPPER_WT_*`.

### Added
- Namespaced commands: `ckipper account ...`, `ckipper worktree ...`.
- Short namespace forms: `ckipper acct ...`, `ckipper wt ...` (and the existing `ck` as a shorthand for `ckipper`).
- Universal fuzzy-suggest on unknown subcommands (Levenshtein distance ≤ 2).
- Per-subcommand `--help` / `-h` for every command (e.g. `ckipper account add --help`).
- `lib/core/fuzzy.zsh` — `_core_fuzzy_suggest` helper.
- `make lint-merge-guards` — four CI grep guards that catch leftover `_w_*`/`W_*` references and cross-namespace imports.

### Migration
Run `./install.sh`. It rewrites `~/.zshrc`, deletes stale paths (`w-function.zsh`, `_w` completion file), and preserves your existing `w-config.zsh` content as `ckipper-config.zsh` (variable names already match — they were renamed in this release).

## [0.1.0] — 2026-04-28

### Added
- Initial public release.
- Multi-account Claude Code management (`ckipper add/remove/rename/list/default/sync/doctor/migrate`; renamed to `ckipper account *` in 0.2.0).
- `w()` worktree-aware launcher with normal and Docker (`--docker --firewall`) modes.
- Auto-generated per-account aliases.
- Safety hooks: `bash-guardrails.sh`, `protect-claude-config.sh`, `docker-context.sh`, `notify-bell.sh`.
- Docker sandbox with egress firewall.
- Modular architecture: `lib/core/` (shared) + `lib/ckipper/` + `lib/w/`.
- Test suite: bats-core (shell) + pytest (Python).
- CI: GitHub Actions on macos-latest.
