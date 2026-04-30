# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — Breaking changes: merge `w` into `ckipper`

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
