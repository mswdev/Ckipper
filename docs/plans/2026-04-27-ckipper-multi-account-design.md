# Ckipper — Multi-Account Claude Code Sandbox

**Date:** 2026-04-27
**Status:** Design (approved)

## Overview

Rename the project formerly called `claude-docker-sandbox` to **Ckipper** (pronounced "skipper") and add support for running multiple Claude Code accounts (personal, work, etc.) concurrently in different terminals or Docker containers without shared auth, MCP config, sessions, or settings.

The design is generic for N ≥ 1 accounts and agnostic to specific account names. Account names like `personal`, `work`, `af` are user choices, never hardcoded.

## Goals

- Run any number of Claude Code accounts concurrently with full isolation: credentials, `.claude.json`, MCP servers, plugins, hooks, projects, settings.
- Make adding the second, third, fourth account a one-command flow that anyone can follow.
- Preserve the existing `w` worktree + Docker workflow; account becomes another dimension alongside project + branch.
- Migrate existing single-account installs without data loss.
- Keep the project name distinct from "Claude" so docs and conversations don't get muddy.

## Non-goals (YAGNI)

- Cross-account project sharing.
- A GUI.
- Auto-detecting the account from cwd or git remote.
- Per-account Docker images.
- Synchronizing credentials across machines.

## Background — what the research established

`CLAUDE_CONFIG_DIR` is an undocumented but functional environment variable. When set, Claude Code reads/writes its credentials, `.claude.json`, settings, plugins, hooks, projects, and MCP config from that directory instead of `~/.claude`. On macOS, credentials still go to the Keychain, but the service name is suffixed with a hash of the config dir path — empirically confirmed by inspecting the host (three `Claude Code-credentials*` entries already exist there). Different config dirs produce different Keychain entries, so isolation is real on macOS, not just on disk.

Known caveats (from upstream issues):
- [#3833](https://github.com/anthropics/claude-code/issues/3833) — Claude Code may still create workspace-local `.claude/` dirs in some cases. Hybrid behavior, undocumented.
- [#24317](https://github.com/anthropics/claude-code/issues/24317) — OAuth refresh-token race when **the same** account runs in two sessions. Different accounts have different refresh tokens, so cross-account concurrent use is not affected. Same-account concurrency is — README will warn.

The Keychain hash algorithm is undocumented. We do not reverse engineer it; instead, registration snapshots Keychain entries before/after `/login` and records the diff.

## Architecture

### Per-account isolation primitive

Each account is a directory pointed to by `CLAUDE_CONFIG_DIR=$HOME/.claude-<name>`. Every piece of Claude state lives inside it. Accounts are siblings under `$HOME/`:

```
~/.claude-personal/
~/.claude-work/
~/.claude-<name>/
```

This naming follows Claude Code's own convention (each is literally a Claude config dir) and keeps account dirs visually grouped.

### Tool layout — Ckipper lives in `~/.ckipper/`

The sandbox tooling moves out of `~/.claude/docker/` to its own root:

```
~/.ckipper/
  docker/
    Dockerfile
    entrypoint.sh
    init-firewall.sh
    fix-volume-perms.sh
    w-function.zsh
    w-config.zsh             # user's port/volume customizations (preserved across updates)
  hooks/                     # canonical hook source
    bash-guardrails.sh
    protect-claude-config.sh
    docker-context.sh
    notify-bell.sh
  ckipper                    # umbrella CLI (zsh function or shell script)
  aliases.zsh                # auto-generated `claude-<name>` aliases (sourced by .zshrc)
  accounts.json              # the registry
  settings-template.json     # canonical settings used to seed new account dirs
```

The shell needs one source line in `.zshrc`:

```zsh
[[ -f ~/.ckipper/docker/w-function.zsh ]] && source ~/.ckipper/docker/w-function.zsh
[[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh
```

### Registry — `~/.ckipper/accounts.json`

```json
{
  "default": "personal",
  "accounts": {
    "personal": {
      "config_dir": "/Users/matt/.claude-personal",
      "keychain_service": "Claude Code-credentials",
      "registered_at": "2026-04-27T18:00:00Z"
    },
    "<name>": {
      "config_dir": "/Users/matt/.claude-<name>",
      "keychain_service": "Claude Code-credentials-<8hex>",
      "registered_at": "..."
    }
  }
}
```

`keychain_service: null` is valid — used when the account authenticates via API key (`.credentials.json` on disk) or on Linux/Windows where there is no Keychain.

## Components

### 1. `ckipper` umbrella CLI

A zsh function shipped in `~/.ckipper/docker/w-function.zsh` (kept together for one-shot install).

| Subcommand | Behavior |
|---|---|
| `ckipper add <name>` | Register a new account. Creates `~/.claude-<name>/`, copies `settings-template.json` and hooks into it, snapshots `Claude Code-credentials*` Keychain entries, prints "Run `claude /login` in this shell with `CLAUDE_CONFIG_DIR=~/.claude-<name>` set, then press enter." After enter: re-snapshots Keychain, finds the new entry, writes it to the registry, regenerates `aliases.zsh`. |
| `ckipper add <name> --adopt` | Register an existing populated account dir without re-login. Lists existing `Claude Code-credentials*` Keychain entries; prompts user to pick the one belonging to this account (or selects automatically if only one is unclaimed by the registry). |
| `ckipper list` | Print accounts, current default, dir presence, and last-login email per account (read from each `<dir>/.claude.json`'s `oauthAccount.emailAddress`). |
| `ckipper default <name>` | Update `accounts.json.default`. |
| `ckipper remove <name>` | Unregister. Does NOT delete the dir or Keychain entry — prints the commands to do so manually. |
| `ckipper sync-hooks` | Copy `~/.ckipper/hooks/*` into each `<account>/hooks/` and rewrite each `<account>/settings.json` to reference its own absolute hook paths. |
| `ckipper migrate` | Detect a pre-Ckipper layout (`~/.claude/docker/` exists) and run the one-time migration described below. |

Implementation language: zsh + `jq` for JSON manipulation. Same dependencies the existing tooling already uses.

### 2. `cca` dispatcher

`cca <name> [args...]` — short for "claude-config-as". Resolves `<name>` → config dir from the registry, exports `CLAUDE_CONFIG_DIR`, exec's `command claude "$@"`. Used for one-offs without an alias. Errors if `<name>` is not registered.

### 3. Auto-generated per-account aliases

`~/.ckipper/aliases.zsh` is regenerated on every `ckipper add` / `ckipper remove`:

```zsh
# Auto-generated by ckipper. Do not edit by hand.
claude-personal() { CLAUDE_CONFIG_DIR=$HOME/.claude-personal command claude "$@"; }
claude-work()     { CLAUDE_CONFIG_DIR=$HOME/.claude-work     command claude "$@"; }
```

User adds one line to `.zshrc` (handled by `install.sh`). After registration, the new alias is available in any new shell or after `source ~/.ckipper/aliases.zsh`.

### 4. `w` script — account-aware Docker integration

`w` gains an `--account <name>` flag. Active-account resolution order (Option C, env-by-default with flag override):

1. `--account <name>` flag if passed.
2. `CLAUDE_CONFIG_DIR` env var if it matches a registered account's `config_dir`.
3. `accounts.json.default` if set.
4. Otherwise: error with a helpful message ("No account selected. Run `ckipper list`.").

Once resolved, `w` reads `config_dir` and `keychain_service` from the registry and:

- Extracts credentials from the **right** Keychain entry — `security find-generic-password -s "<keychain_service>" -w` instead of the hardcoded `"Claude Code-credentials"`.
- Mounts the per-account config dir into Docker at the same host absolute path (so plugin paths inside `.claude.json` resolve): `-v "$config_dir:$config_dir:rw"`.
- Sets `-e CLAUDE_CONFIG_DIR=$config_dir` inside the container.
- Reads/writes `<config_dir>/.claude.json` instead of `~/.claude.json` for the project-settings sync that runs at worktree creation.
- Drops the dual-mount of `~/.claude` at both `/home/claude/.claude` and `$HOME/.claude` — replaced by a single mount at the per-account host path. The container only needs the per-account dir; there is no shared `~/.claude` anymore.

### 5. Entrypoint changes

`~/.ckipper/docker/entrypoint.sh`:

- Replace `~/.claude.json` and `~/.claude-host.json` references with `$CLAUDE_CONFIG_DIR/.claude.json` and `$CLAUDE_CONFIG_DIR/.claude-host.json`. The "copy from read-only staging" trick stays the same; only the path changes.
- Credentials tmpfs symlink: `ln -sf /tmp/claude-creds/.credentials.json "$CLAUDE_CONFIG_DIR/.credentials.json"` (was `$HOME/.claude/.credentials.json`).
- Pre-install uvx-based MCP servers from `$CLAUDE_CONFIG_DIR/.claude.json`.
- Git identity continues to read from `oauthAccount` in `$CLAUDE_CONFIG_DIR/.claude.json`. Each account's `displayName` / `emailAddress` is now per-account, so commits made in a "work" container use the work email automatically. This is a feature.

### 6. Hooks installation

`install.sh`:

- Deploys this repo's `docker/`, `hooks/`, `settings-hooks.json`, and the new `ckipper` CLI to `~/.ckipper/`.
- Adds the source line(s) to `.zshrc` if missing.
- If accounts are registered: runs `ckipper sync-hooks` to push hooks into each account's dir.
- If no accounts are registered: leaves a `settings-template.json` alongside the canonical hooks for `ckipper add` to use when initializing new account dirs.

Each account's `settings.json` references absolute paths to **its own** hooks (`~/.claude-<name>/hooks/<hook>.sh`), so the right hooks fire under the right account.

### 7. Migration for existing users — `ckipper migrate`

Detects pre-Ckipper layouts and runs a guided migration. Idempotent.

| Detected state | Action |
|---|---|
| `~/.claude/docker/` exists | Move tooling files to `~/.ckipper/`. Preserve `w-config.zsh` (user customization). |
| `~/.claude/.claude.json` exists with an `oauthAccount` | Offer to register it as `personal`. If accepted: rename `~/.claude` → `~/.claude-personal`, create `~/.claude` symlink back to it (for legacy bare-`claude` invocations), write the registry entry. Match the existing `Claude Code-credentials` (no suffix) Keychain entry to it. |
| Old `~/.zshrc` source line points at `~/.claude/docker/w-function.zsh` | Update to `~/.ckipper/docker/w-function.zsh`. |
| Existing hooks in `~/.claude/hooks/` referenced from `~/.claude/settings.json` | After the rename, settings.json now lives at `~/.claude-personal/settings.json` and references `~/.claude-personal/hooks/*` (rewritten by `sync-hooks`). |

Then the user runs `ckipper add <name>` for each additional account.

## Issues from research — and how the design handles them

1. **Plain `claude` after rename** — `~/.claude → ~/.claude-personal` symlink preserves it. Bare `claude` keeps working with the personal account.
2. **Keychain hash discovery** — `ckipper add` snapshots Keychain entries before/after the user runs `/login`, then diffs to find the new entry. No reverse engineering.
3. **`w` Docker integration** — fully parameterized via the registry: per-account Keychain service, per-account mount path, per-account `CLAUDE_CONFIG_DIR` in container. No more hardcoded `Claude Code-credentials`.
4. **Hooks duplication across accounts** — `ckipper sync-hooks` is a one-command refresh. Each account's `settings.json` references its own absolute paths, so isolation is real.
5. **OAuth race (#24317)** — different accounts have different refresh tokens; only same-account concurrent use can race. README warns. Two terminals using `claude-personal` simultaneously is the bad case; one `claude-personal` and one `claude-work` is fine.
6. **`#3833` workspace-local `.claude/`** — out of our control. If it appears, we document and report upstream.

## Data flow — typical session

```
User opens Ghostty terminal A:
  $ claude-work               # alias exports CLAUDE_CONFIG_DIR=~/.claude-work
                              # claude reads creds from Keychain entry "Claude Code-credentials-<hash>"
                              # session lives in ~/.claude-work/projects/<...>

User opens Ghostty terminal B:
  $ claude-personal           # alias exports CLAUDE_CONFIG_DIR=~/.claude-personal
                              # claude reads creds from Keychain entry "Claude Code-credentials"
                              # session lives in ~/.claude-personal/projects/<...>

User opens Ghostty terminal C:
  $ w myorg/app feature --account work --docker claude
                              # w reads accounts.json → "work" config_dir + keychain_service
                              # security find-generic-password -s "Claude Code-credentials-<hash>"
                              # docker run with:
                              #   -v ~/.claude-work:~/.claude-work:rw
                              #   -e CLAUDE_CONFIG_DIR=~/.claude-work
                              # entrypoint copies .claude-host.json → .claude.json inside container
                              # writes credentials to tmpfs, symlinks to ~/.claude-work/.credentials.json
                              # exec claude --dangerously-skip-permissions
```

All three sessions are independent. Different accounts, different credentials, different project state, different MCP config.

## README updates

The README gets a new "Multiple accounts" section with:

- One-paragraph explanation of why anyone would want this.
- Quickstart: `ckipper add work`, follow prompts, start using `claude-work`.
- Concurrent-use warning: don't run the same account in two sessions; do run different accounts in two sessions.
- Migration steps for existing users (`ckipper migrate`).
- Reference table of files/dirs Ckipper creates and what each is for.

Old "claude-docker-sandbox" naming gets replaced wholesale with "Ckipper".

## Open questions

- Should `cca` and the auto-generated aliases live in the **same** `aliases.zsh`, or split? **Decision:** same file. Simpler.
- Should `ckipper sync-hooks` run automatically on `ckipper add`? **Decision:** yes, on first add for that account. Manual otherwise.
- Should `ckipper add --adopt` also work for the brand-new `~/.claude` dir at first install? **Decision:** yes — `ckipper migrate` is just `ckipper add personal --adopt` with extra layout-cleanup.

## Implementation phases (preview — full plan in writing-plans next)

1. Rename project metadata (CLAUDE.md, README.md, install.sh paths). No behavior change.
2. Move tooling location: `~/.claude/docker/` → `~/.ckipper/`. Update install.sh + source lines.
3. Add `ckipper` CLI with `add`, `list`, `default`, `remove`, `sync-hooks`, `migrate`.
4. Make `w` and `entrypoint.sh` account-aware.
5. README rewrite with multi-account walkthrough.
6. Run `ckipper migrate` on the user's host to do the personal → personal+af split. Test end-to-end with both accounts.

Each phase is independently testable.
