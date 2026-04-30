# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
