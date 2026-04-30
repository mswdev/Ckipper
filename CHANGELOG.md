# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed
- `ckipper migrate` subcommand (legacy `claude-docker-sandbox` migration). The legacy install path is no longer supported; use `ckipper add <name>` for fresh installs.

### Added
- `CKIPPER_PROJECTS_DIR` and `CKIPPER_WORKTREES_DIR` are now user-configurable via `w-config.zsh`. Defaults remain `$HOME/Developer` and `$CKIPPER_PROJECTS_DIR/.worktrees`. Existing tab-completion files regenerate on next shell startup via a version sentinel.

### Changed
- Repository layout: templates moved to `templates/` (`w-config.zsh.example`, `settings-template.json`); manual integration test prompt moved to `docs/test-prompt.md`. Source name `settings-hooks.json` renamed to `settings-template.json` to match the deployed name.

## [0.1.0] — 2026-04-28

### Added
- Initial public release.
- Multi-account Claude Code management (`ckipper add/remove/rename/list/default/sync/doctor/migrate`).
- `w()` worktree-aware launcher with normal and Docker (`--docker --firewall`) modes.
- Auto-generated per-account aliases.
- Safety hooks: `bash-guardrails.sh`, `protect-claude-config.sh`, `docker-context.sh`, `notify-bell.sh`.
- Docker sandbox with egress firewall.
- Modular architecture: `lib/core/` (shared) + `lib/ckipper/` + `lib/w/`.
- Test suite: bats-core (shell) + pytest (Python).
- CI: GitHub Actions on macos-latest.
