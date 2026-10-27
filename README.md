# Ckipper (pronounced "skipper")

> _This project is vibe-engineered. I use it personally for my own setup and it works well; use it at your own risk. Works on my machine ;) See [Contributing](#contributing)._

> **Platform:** macOS only — uses the macOS Keychain and Claude Desktop's `.app` bundle format.

A lightweight CLI for running several Claude Code accounts and several Claude Desktop instances side by side on one Mac.

For developers who want clean separation between personal and work Claude — in the terminal, in the Desktop app, or both — with one registry, one `doctor`, and the same `ck` short alias driving everything.

The Claude Desktop multi-instance approach (generated `.app` wrappers + Electron `--user-data-dir`) was inspired by [Philipp Stracker's gist](https://gist.github.com/stracker-phil/9f84927a556632c7f9cc06663b534f14).

## The Problem

Claude Code keeps everything for one login in one config folder (`~/.claude/` by default). Switching between a personal and a work account means logging out and back in, and the two accounts' settings, MCP servers, plugins, and history bleed into each other.

Claude Desktop is single-instance by default — sign in with one account, lose the other.

## The Solution

```bash
ck account add work      # creates ~/.claude-work/ and walks you through /login
claude-work              # launches Claude Code against ~/.claude-work/
```

Each account gets its own config folder, selected with `CLAUDE_CONFIG_DIR`. Claude Code stores each folder's login under its own macOS Keychain entry, so accounts never overwrite each other's credentials.

```bash
ck desktop add work
```

Generates `~/Applications/Claude-Work.app` — a wrapper bundle that launches the system Claude Desktop against an isolated user-data dir. Spotlight, Dock, and Cmd-Tab treat it like any other app.

For worktrees and sandboxing, use Claude Code's own features: `claude-work --worktree <name>` creates and cleans up a git worktree, and auto mode gates risky actions without a container.

## Quick start

```bash
git clone https://github.com/mswdev/Ckipper.git
cd Ckipper
./install.sh
source ~/.zshrc
ckipper account add personal
```

`install.sh` copies `ckipper.zsh` and `lib/` into `~/.ckipper/`, regenerates `~/.ckipper/aliases.zsh` from your registry, and adds `source "$HOME/.ckipper/ckipper.zsh"` to your `.zshrc`. Re-run it after every `git pull`.

To get the per-account launchers, also add this line to `.zshrc` (the installer prints it if it's missing):

```bash
[[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh
```

### Prerequisites

- **macOS** with zsh
- **Claude Code** installed (`claude` command works)
- **Claude Desktop** (`/Applications/Claude.app`) — *only if you'll use `ck desktop` instances*
- **jq** and **gum** installed (`brew install jq gum`)

## Core commands

| Command | Purpose |
| --- | --- |
| `ck account add/list/default/remove/rename/group/sync` | Manage Claude Code accounts (alias `acct`; see [Multiple accounts](#multiple-accounts)) |
| `ck desktop add/list/remove/rename/launch/login` | Manage Claude Desktop instances (alias `dt`; see [Claude Desktop instances](#claude-desktop-instances)) |
| `ck doctor [--fix]` | Diagnose the registry, account dirs, Keychain entries and shell setup; optionally repair |
| `ck help` (or bare `ck`) | Show the command overview |

`ck` is a short alias for `ckipper`. Tab completion is included.

## Multiple accounts

Run a personal account in one terminal and a work account in another, fully isolated. Each gets its own credentials, MCP servers, plugins, projects, and session history.

### Add an account

```bash
ckipper account add work                      # fresh: creates ~/.claude-work/, launches /login
ckipper account add work-2 --group work       # …and copies the work group's master into it
ckipper account add work --adopt              # register an existing ~/.claude-work/
```

Account names may not start with `desktop-` (that prefix is a Desktop instance's data dir).

### Groups

Accounts that should share one setup form a **group** with one **master**: for example `personal` (master) with `personal-2`, `personal-3`, and `aff` (master) with `aff-2`, `aff-3`.

```bash
ckipper account group personal personal       # first account in a group becomes its master
ckipper account group personal-2 personal
ckipper account group aff aff
ckipper account group aff-3 aff --master      # hand the master role to another member
```

- **Sync stays inside a group.** `ckipper account sync personal aff` is refused, so a personal-only memory dir, plugin or marketplace never lands in a work account, and work-only settings (like an `autoMode` block) are never overwritten from personal. The interactive target picker only offers the source's group.
- **New members start as a copy of the master.** `ckipper account add <name> --group <group>` runs `/login`, then copies everything sync covers from the master (MCP servers, settings, CLAUDE.md, agents, commands, output styles, skills except `skills/synced`, statusline, hooks) plus its installed plugins (`plugins/installed_plugins.json`, `known_marketplaces.json`, `cache/`, `marketplaces/`, with paths rewritten). `plugins/data` and `plugins/synced` are left out.
- **One memory dir per group.** If you share memory across a group with `env.CLAUDE_CODE_REMOTE_MEMORY_DIR` in `settings.json`, `ckipper doctor` checks that every member uses its master's value and fails if two groups point at the same dir.

### Use an account

```bash
claude-work                                  # auto-generated launcher
work                                         # bare-name shortcut (skipped if it would shadow an existing command)
CLAUDE_CONFIG_DIR=~/.claude-work claude      # raw form
```

`ckipper account add` re-sources `aliases.zsh` in your current shell, so new launchers are usable immediately — no `exec zsh`.

### The bare-`claude` guard

Once any account is registered, `aliases.zsh` replaces plain `claude` with a guard that refuses to start and points you at `claude-<default>`. Plain `claude` uses `~/.claude/`, which no registered account owns, so a `/login` there would create a stray, unmanaged login. The guard steps aside when `CLAUDE_CONFIG_DIR` is already set (for example inside a `claude-<name>` session), since `claude` then can't touch `~/.claude/`. To bypass it on purpose: `command claude`.

### List, default, remove, rename

```bash
ckipper account list
ckipper account default personal
ckipper account remove old-account     # prompts before deleting the dir and the Keychain login
ckipper account rename work client     # then: claude-client, /login
```

`rename` moves the config dir, and Claude Code names the Keychain entry after the dir, so the renamed account starts logged out — run `/login` once. Ckipper rewrites the plugin paths for you and prints the command to delete the old entry.

### How accounts are stored

- Per-account state lives in `~/.claude-<name>/`.
- The registry mapping account names to dirs lives at `~/.ckipper/accounts.json` (chmod 600, atomic writes, schema v4). Older registries are upgraded in place on first use, with a backup next to the file.
- Logins live in the macOS Keychain, one entry per config dir. Claude Code names the entry `Claude Code-credentials-<first 8 hex of sha256(config dir path)>` (plain `~/.claude` uses `Claude Code-credentials`), so Ckipper derives it rather than storing it.
- Auto-generated `~/.ckipper/aliases.zsh` defines `claude-<name>` (and a bare `<name>` shortcut, when it doesn't shadow an existing command) per registered account, plus the bare-`claude` guard.

### Don't run the same account in two sessions

Two terminals running the **same** account simultaneously will hit a known OAuth refresh-token race ([upstream issue #24317](https://github.com/anthropics/claude-code/issues/24317)) — symptoms: frequent re-login prompts, lost sessions.

- **Safe:** `claude-personal` in one terminal, `claude-work` in another.
- **Bad:** `claude-personal` in two terminals at once.

If you want concurrent runs of the *same* account, register it twice under two names (`personal`, `personal-2`) and `/login` in each.

## Sync state between accounts

`ckipper account sync` copies state between registered accounts in the same [group](#groups) — MCP servers, settings, agents, commands, skills, user hooks, etc. — interactively by default, with one source and one or more destinations.

### Syncable types

| Type | What it covers |
|---|---|
| `mcp` | `.claude.json` `.mcpServers` (per server) |
| `settings` | `settings.json` top-level + nested keys (excludes `.hooks` and `.statusLine`) |
| `claude-md` | `CLAUDE.md` (user memory) |
| `agents` | `agents/*.md` |
| `commands` | `commands/*.md` |
| `output-styles` | `output-styles/*.md` |
| `skills` | `skills/<name>/` (per-directory; symlinks preserved; `skills/synced/` is skipped — claude.ai manages it per account) |
| `statusline` | `settings.json` `.statusLine` + referenced script (if internal to the account dir) |
| `hooks` | Hook scripts under `<account>/hooks/` + their paired `settings.json` `.hooks` entries |

### Common commands

```bash
# Full interactive wizard — picks source, targets, and types
ckipper account sync

# One-shot single type
ckipper account sync personal work --include mcp

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

### Safeguards & undo

Every destructive write is preceded by a copy to `<dst>/.ckipper-sync-backups/<UTC-ISO-ts>-from-<source>/`. The summary table prints the backup directory path before applying. To restore:

```bash
ckipper account sync undo work          # restore most recent backup
ckipper account sync undo work --pick   # gum-pick from backup ledger
ckipper account sync undo work --list   # print backup directory paths
```

Sync refuses to write while any Claude CLI is running (override with `--force` if you understand the risk). `--dry-run` is always allowed. A sync with nothing to change writes nothing and leaves no backup. A destination file that is a symlink is replaced by a regular file; its target is never written through.

Settings sync copies each value as-is: arrays such as `permissions.allow` are replaced, not merged. Check the drill-down (`View changes`) before applying.

## Claude Desktop instances

Run a personal Claude Desktop in one window and a work Claude Desktop in another, fully isolated. Each shows up in Spotlight and the Dock as its own `Claude-<Name>.app`, signs in with its own account, and keeps its own MCP servers, projects, and conversation history. Under the hood: a generated `.app` wrapper that launches the system `Claude.app` with Electron's `--user-data-dir` pointed at an isolated sandbox.

### Accounts vs. Desktop instances

Two independent isolation models, configured separately:

| | CLI accounts (`ckipper account`) | Desktop instances (`ckipper desktop`) |
| --- | --- | --- |
| Scope | The `claude` CLI in a terminal | The `Claude.app` Electron app |
| Data dir | `~/.claude-<name>/` | `~/.claude-desktop-<name>/` |
| Registry | `~/.ckipper/accounts.json` | `~/.ckipper/desktop.json` |
| Auth | macOS Keychain (one entry per config dir) | Electron-managed (per user-data dir) |
| Sync command | `ckipper account sync` | _not available — each instance signs in independently_ |
| Default selector | `ckipper account default <name>` | _not available — pick from Spotlight/Dock_ |

An account named `work` and a Desktop instance named `work` share nothing but the name. `ckipper account sync` does not touch Desktop instances; `ckipper desktop` does not touch CLI accounts.

### Add an instance

```bash
ckipper desktop add work
```

Creates `~/.claude-desktop-work/` (user-data dir) and `~/Applications/Claude-Work.app` (wrapper bundle whose launcher exec's `open -n -a /Applications/Claude.app --args --user-data-dir=…`). Requires `/Applications/Claude.app` to be installed.

### Use an instance

```bash
ckipper desktop launch work         # open the instance (also works from Spotlight / Dock)
```

### List, rename, remove

```bash
ckipper desktop list                # see registered instances + running status
ckipper desktop rename work prod    # rename in place
ckipper desktop remove work         # interactively prompt to delete user-data dir + bundle
```

### Don't run `/login` with two instances open

macOS routes `claude://` URLs (the OAuth callback used by `/login`) to whichever Claude app was most recently active. With two or more Desktop instances running, the callback can land in the wrong window. `ckipper desktop login <name>` works around this by quitting *every* running Claude process and launching only the target — complete `/login` there, then re-open the others as needed.

```bash
ckipper desktop login work          # quit all, launch only 'work' — safe for /login flows
```

### How instances are stored

- Per-instance data lives in `~/.claude-desktop-<name>/` (Electron `userData` dir).
- Generated `.app` wrappers live in `~/Applications/Claude-<Name>.app` (per-user, no admin required). The launcher script bakes `--user-data-dir` in at generation time — no runtime path-walking.
- The registry mapping instance names to dirs and bundles lives at `~/.ckipper/desktop.json` (separate file from `accounts.json`, separate schema version).

## Diagnose

`ckipper doctor` checks the install (`~/.ckipper/ckipper.zsh`, leftovers from the old Docker-based layout, `gum`), the registry, each account (config dir, `.claude.json`, `settings.json`, stale plugin paths, Keychain entry), the groups (every account grouped, every group with a master, one memory dir per group), the `~/.zshrc` source lines, and every Desktop instance. Pass `--fix` to rewrite stale plugin metadata paths in place.

## Multi-account caveats

These are upstream Claude Code behavior, not Ckipper bugs.

### OAuth refresh token races (upstream)

Two concurrent Claude Code sessions on the same account share a single-use OAuth refresh token. The first to refresh wins; the second loses authentication. References: [#24317](https://github.com/anthropics/claude-code/issues/24317), [#27933](https://github.com/anthropics/claude-code/issues/27933). **Workaround:** different accounts in different terminals.

### Credentials silently wiped on failed refresh (upstream)

If a token refresh fails mid-flight, Claude Code may overwrite the stored credentials with an empty value. Reference: [#29896](https://github.com/anthropics/claude-code/issues/29896). **Recovery:** `claude-<name>`, then `/login` again.

### Keychain permission glitches after macOS updates (upstream)

After macOS or Claude Code updates, the Keychain entry can become inaccessible to Claude Code, forcing a re-`/login`. Reference: [#19456](https://github.com/anthropics/claude-code/issues/19456).

### Project-level files are SHARED across accounts (by design)

Files inside a project repo are *not* governed by `CLAUDE_CONFIG_DIR`: `<repo>/.claude/settings.json`, `<repo>/.claude/settings.local.json`, `<repo>/.mcp.json`, and `<repo>/CLAUDE.md`. Your `personal` and `work` accounts working in the same repo see the same project rules and project MCPs.

### MCP servers, plugins and marketplaces are per-account

`mcpServers` lives in each account's `.claude.json`; installed plugins live in each account's `plugins/` dir. `ckipper account add <name> --group <group>` copies both from the group's master; afterwards, `ckipper account sync <master> <name> --include mcp,settings` keeps MCP servers and the `enabledPlugins` / `extraKnownMarketplaces` settings in step.

## Troubleshooting

| Problem | Fix |
|---|---|
| `claude` refuses to start | That's the bare-`claude` guard. Use `claude-<account>` (or `command claude` to bypass on purpose). |
| `claude-<name>: command not found` | Add the `aliases.zsh` source line to `~/.zshrc`, then `source ~/.zshrc`. |
| `ckipper doctor` says ~/.zshrc doesn't source ckipper.zsh | Re-run `./install.sh`. |
| Plugins fail to load after a rename | `ckipper doctor --fix` rewrites stale plugin paths. |
| Sync refuses to run | A Claude CLI is running (quit it, use `--dry-run`, or pass `--force`), or the accounts are in different groups or none (`ckipper account group <name> <group>`). |

## Contributing

PRs welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the workflow, code style, and how to run the test suite (`make bootstrap && make test`).

## Security disclosure

Found a vulnerability? See [`SECURITY.md`](SECURITY.md) for private reporting. Please do not open a public issue.

## License

MIT — see [`LICENSE`](LICENSE).
