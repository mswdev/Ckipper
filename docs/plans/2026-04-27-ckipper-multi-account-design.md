# Ckipper — Multi-Account Claude Code Sandbox

**Date:** 2026-04-27
**Status:** Design (revised after panel review — 6 reviewers + Team Lead, all GO-WITH-FIXES)

## Overview

Rename the project formerly called `claude-docker-sandbox` to **Ckipper** (pronounced "skipper") and add support for running multiple Claude Code accounts (personal, work, etc.) concurrently in different terminals or Docker containers without shared auth, MCP config, sessions, or settings.

The design is generic for N ≥ 1 accounts and agnostic to specific account names. Account names like `personal`, `work`, or any other lowercase-alphanumeric string are user choices, never hardcoded.

## Revisions from panel review (post-initial-draft)

Six reviewers (Senior SWE, Senior Architect, Security, DevOps, DX, QA) plus a Team Lead synthesized the following changes into the design before execution:

- **Drop the `~/.claude → ~/.claude-personal` symlink.** Originally proposed as backward-compat for bare `claude`, the symlink created four failure modes (dangling on `remove personal`, interaction with upstream issue #3833 workspace writes, hook realpath drift across versions, target-swap attack vector) for one minor convenience. After migrate, the user uses `claude-personal` (or whatever name they registered). Bare `claude` with no `CLAUDE_CONFIG_DIR` falls back to whatever Claude Code's default is, which after migration is an empty `~/.claude` (Claude will prompt to log in fresh). The README warns about this.
- **Hooks must protect `~/.ckipper/` and per-account dirs.** `bash-guardrails.sh` and `protect-claude-config.sh` get an explicit anchored regex covering `$HOME/.claude(-[a-z0-9_-]+)?/` and `$HOME/.ckipper/`. Without this, a Claude session in account A can edit `~/.ckipper/accounts.json` to repoint A's name at B's keychain service — a credential cross-contamination vector.
- **Validate `keychain_service` shape before passing to `security`.** Empty strings or shell metacharacters from a corrupted registry would otherwise reach `security find-generic-password -s …`. Required regex: `^Claude Code-credentials(-[a-f0-9]+)?$`.
- **Fix the Keychain snapshot.** Use `printf '%s\n'` (not `echo`) to feed `comm`; capture a real `security dump-keychain` sample as a test fixture; detect a locked keychain (timeout + error rather than silent empty diff).
- **`cca` self-containment.** The dispatcher must define its own dependencies so sourcing `aliases.zsh` alone works without `ckipper.zsh`.
- **Migration safety.** Refuse migration if any `claude` process is running. Wrap destructive `mv` in a `trap` that restores on failure. Probe the legacy Keychain entry before trusting it.
- **`accounts.json` schema versioning + `chmod 600`.** Add `"version": 1`. Lock perms.
- **Phase 6.5 Docker smoke test** before live deploy on the user's host. The current plan's Phase 7 was the first time anything ran in Docker.
- **Default `CLAUDE_CONFIG_DIR` in entrypoint should be an error, not a silent fallback to `~/.claude`.**

Reviewer disagreements resolved by Team Lead:
- Symlink fate (drop vs. clarify vs. protect) → **drop**.
- Default `CLAUDE_CONFIG_DIR` (document vs. error) → **error**.
- `.zshrc` auto-edit (do nothing vs. auto-append) → **auto-append the source line for `~/.ckipper/docker/w-function.zsh`** (consistent with existing `install.sh` behavior); print instructions for the optional `aliases.zsh` source line.

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
    ckipper.zsh              # umbrella CLI subcommand dispatcher
    cleanup-projects.py      # extracted helper, called from w --rm
  hooks/                     # canonical hook source
    bash-guardrails.sh
    protect-claude-config.sh
    docker-context.sh
    notify-bell.sh
  aliases.zsh                # auto-generated `cca` + `claude-<name>` (sourced by .zshrc; self-contained)
  accounts.json              # the registry, chmod 600
  settings-template.json     # canonical settings used to seed new account dirs
```

(Test fixtures like `tests/keychain-dump.sample` live in the *repo*, not in the deployed `~/.ckipper/` — they are dev-time only.)

The shell sources two lines from `.zshrc` (the first is auto-appended by `install.sh`; the second is suggested if the user wants per-account aliases):

```zsh
[[ -f ~/.ckipper/docker/w-function.zsh ]] && source ~/.ckipper/docker/w-function.zsh
[[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh
```

`aliases.zsh` is fully self-contained — it does not depend on `w-function.zsh` or `ckipper.zsh` being sourced. The generated file defines its own `CKIPPER_REGISTRY` path before defining `cca`.

After migration, **bare `claude`** (no env var, no alias) does whatever Claude Code's default behavior is — which after migration is "no `~/.claude` exists, prompt for fresh login". This is intentional. To use the personal account, the user runs `claude-personal` (or whichever name they registered).

### Registry — `~/.ckipper/accounts.json`

```json
{
  "version": 1,
  "default": "personal",
  "accounts": {
    "personal": {
      "config_dir": "$HOME/.claude-personal",
      "keychain_service": "Claude Code-credentials",
      "registered_at": "2026-04-27T18:00:00Z"
    },
    "<name>": {
      "config_dir": "$HOME/.claude-<name>",
      "keychain_service": "Claude Code-credentials-<8hex>",
      "registered_at": "..."
    }
  }
}
```

(In the actual file, `$HOME` is expanded — shown above as a placeholder so the example reads correctly for any user.)

The schema:
- `version: 1` — bumped when fields are added or semantics change. CLI refuses to operate on a registry whose version it doesn't understand.
- `keychain_service` shape is enforced: `^Claude Code-credentials(-[a-f0-9]+)?$`. CLI rejects values that don't match before passing to the macOS `security` command.
- `keychain_service: null` is valid — used when the account authenticates via API key (`.credentials.json` on disk) or on Linux/Windows where there is no Keychain.
- File permissions are `0600` (set on creation and on every write).
- Atomic writes use `flock` on the registry file to serialize concurrent `ckipper add` invocations.

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
- Drops the dual-mount of `~/.claude` at both `/home/claude/.claude` and `$HOME/.claude`, replaced by a single mount at the per-account host path. **Before this change ships, the implementation phase grep-audits every `/home/claude/.claude` reference under `docker/` and migrates each one to `$CLAUDE_CONFIG_DIR`.** The plan has an explicit task for this audit — silent removal of the dual mount would break uvx pre-install, gh auth setup, and any plugin path that referenced the dropped mount.
- Cross-account `--rm` cleanup walks the registry (not a glob of `~/.claude-*`), so backup or archived dirs aren't picked up by accident.

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

Detects pre-Ckipper layouts and runs a guided migration. Idempotent. Safety-checked.

**Preconditions enforced before any destructive operation:**

1. No `claude` process is currently running (`pgrep -f "claude " >/dev/null` must return non-zero, else abort with a clear message).
2. `~/.claude-personal` does not already exist (else abort — `mv` would nest, not overwrite).
3. The legacy `Claude Code-credentials` Keychain entry actually returns credentials (`security find-generic-password -s "Claude Code-credentials" -w` succeeds). If not, the user is shown a list of `Claude Code-credentials*` entries and asked to pick.

**The destructive sequence is wrapped in a `trap` that restores on failure** — if `mv` succeeds but the registry write fails, the trap reverses the move so the user is never left with a missing `~/.claude`.

| Detected state | Action |
|---|---|
| `~/.claude/docker/` exists | Copy tooling files to `~/.ckipper/`. Preserve `w-config.zsh` (user customization). Old dir kept for one release cycle (prints recovery instructions). |
| `~/.claude/.claude.json` exists with an `oauthAccount` | After preconditions pass: offer to register it as `personal`. If accepted: rename `~/.claude` → `~/.claude-personal` (no symlink — see "Revisions from panel review"), write the registry entry. Probe the matched Keychain entry first. |
| Old `~/.zshrc` source line points at `~/.claude/docker/w-function.zsh` | Print a one-line update for the user to apply (`install.sh` may auto-edit; `migrate` does not). |
| Existing hooks in `~/.claude/hooks/` | After the rename, settings.json now lives at `~/.claude-personal/settings.json` and references `~/.claude-personal/hooks/*` (rewritten by `sync-hooks`). |
| Old `claude-dev` Docker image | `docker rmi claude-dev 2>/dev/null` — best-effort cleanup of the renamed image. |

After migrate completes successfully, the user runs `ckipper add <name>` for each additional account, and uses `claude-personal` (not bare `claude`) to launch Claude Code.

## Issues from research — and how the design handles them

1. **Plain `claude` after rename** — *not preserved* (decision reversed in panel review). After migration, `~/.claude` no longer exists. Bare `claude` invocations create a fresh empty `~/.claude` and prompt for login. The README and `ckipper migrate` output state this explicitly: "after migrate, use `claude-personal` to launch Claude Code with your personal account."
2. **Keychain hash discovery** — `ckipper add` snapshots Keychain entries before/after the user runs `/login`, then diffs to find the new entry. The snapshot uses `printf '%s\n'` (not `echo`) for `comm`-friendly input, detects a locked keychain via timeout, and is regression-tested against a captured `security dump-keychain` fixture under `~/.ckipper/tests/`.
3. **`w` Docker integration** — fully parameterized via the registry: per-account Keychain service, per-account mount path, per-account `CLAUDE_CONFIG_DIR` in container. `keychain_service` shape is validated before passing to the `security` command. No more hardcoded `Claude Code-credentials`.
4. **Hooks duplication across accounts** — `ckipper sync-hooks` is a one-command refresh. Each account's `settings.json` references its own absolute paths, so isolation is real. Both `bash-guardrails.sh` and `protect-claude-config.sh` extend their protected-path regex to cover `$HOME/.claude(-[a-z0-9_-]+)?/` and `$HOME/.ckipper/` (so a session in account A can't tamper with the registry to redirect account B's credentials).
5. **OAuth race (#24317)** — different accounts have different refresh tokens; only same-account concurrent use can race. README warns prominently. Two terminals using `claude-personal` simultaneously is the bad case; one `claude-personal` and one `claude-work` is fine.
6. **`#3833` workspace-local `.claude/`** — out of our control. If it appears, we document and report upstream.
7. **Registry tampering** — `~/.ckipper/accounts.json` lives in user-writable space. Defenses: hooks block Edit/Write to it from inside Claude sessions; `chmod 600` reduces accidental exposure; `keychain_service` shape validation rejects corrupt values before `security` is invoked.
8. **Migration data loss** — `ckipper migrate` enforces three preconditions before any `mv` and wraps the destructive sequence in an error-trap that restores the previous state on any failure.

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

## Implementation phases (preview — full plan in `2026-04-27-ckipper-multi-account-implementation.md`)

1. Rename project metadata (CLAUDE.md, README.md, install.sh paths, Docker image tag). No behavior change.
2. Move tooling location: `~/.claude/docker/` → `~/.ckipper/`. Update install.sh + auto-append `.zshrc` source line.
3. Add `ckipper` CLI with `add`, `list`, `default`, `remove`, `sync-hooks`, `migrate`. Includes registry schema versioning, file locking, fixture-based Keychain regression test.
4. Make `w` and `entrypoint.sh` account-aware. Audit `/home/claude/.claude` references first; remove only after each one is migrated to `$CLAUDE_CONFIG_DIR`. Validate `keychain_service` shape before passing to `security`.
5. Extend hooks (`bash-guardrails.sh`, `protect-claude-config.sh`) to cover `~/.ckipper/` and per-account dirs. Re-run existing `test-prompt.md` Section 10 hook-bypass tests after the change.
6. README, CLAUDE.md, and test-prompt.md updates with multi-account walkthrough, concurrent-use warning, migration preamble, and concrete Section 12 isolation assertions.
6.5. Build the renamed `ckipper-dev` image and run a Docker smoke test against a registered test account before deploying anywhere real.
7. Run `ckipper migrate` on the implementer's host. Add additional accounts with generic placeholder names (`<work>`, `<your-second-account>`). End-to-end validation against both accounts in concurrent Docker sessions.

Each phase is independently testable. Phase 7 is the only phase that touches the implementer's actual host.
