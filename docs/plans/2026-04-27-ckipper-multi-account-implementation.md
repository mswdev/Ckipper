# Ckipper Multi-Account Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rename `claude-docker-sandbox` to **Ckipper** (pronounced "skipper") and add support for running N concurrent Claude Code accounts with full isolation across credentials, settings, MCP, plugins, hooks, projects, and Docker sessions.

**Architecture:** Each account is a `CLAUDE_CONFIG_DIR=~/.claude-<name>/` directory. A registry at `~/.ckipper/accounts.json` maps account names to dirs and macOS Keychain service names. The new `ckipper` CLI registers/lists/removes accounts and auto-generates `claude-<name>` shell aliases. The `w` script and Docker entrypoint become account-aware via an `--account` flag, falling back to `CLAUDE_CONFIG_DIR` env var, then a registered default. Sandbox tooling moves out of `~/.claude/docker/` to its own root `~/.ckipper/` so tooling and account state are decoupled.

**Tech Stack:** zsh (functions, completions), bash (entrypoint, hooks, install), `jq` for JSON, `flock` for atomic registry writes, `security` (macOS Keychain), Docker, git worktrees.

**Reference:** `docs/plans/2026-04-27-ckipper-multi-account-design.md`

**Status:** Revised after panel review (6 reviewers + Team Lead, all GO-WITH-FIXES). Revisions are folded into individual tasks below — they are not a separate phase.

---

## Prerequisites — read this before Task 1

**Starting repository state (verify before beginning):**

```bash
git rev-parse --abbrev-ref HEAD     # → feature/ckipper-multi-account
git status                           # working tree clean
ls docs/plans/                       # contains the design + this implementation file
```

If you are not on `feature/ckipper-multi-account`, stop and ask the user. If the working tree has uncommitted changes, stop and ask. The first two commits on this branch should already be the design doc and the (now-revised) implementation plan — do not re-create them.

**Required tools on the implementer's machine:**

- `zsh` (the project's primary shell)
- `bash` (entrypoint, hooks)
- `jq` (1.6 or newer — `jq walk` is used in `sync-hooks`)
- `flock` (registry locking — bundled on Linux; `util-linux` on macOS via Homebrew, BUT macOS ships with a different tool: see fallback note below)
- `shellcheck`
- Docker (for Phase 6.5 onwards)
- `git` (with whatever signing config the user already has — see GPG note below)
- `python3` (for `docker/cleanup-projects.py`)

**macOS `flock` fallback:** if `flock` is not in PATH, the registry-update helper should fall back to a `mkdir`-based lock: `until mkdir "$CKIPPER_DIR/.registry.lock.d" 2>/dev/null; do sleep 0.05; done; trap 'rmdir "$CKIPPER_DIR/.registry.lock.d"' EXIT INT TERM`. Add this to `_ckipper_registry_update` as a runtime check during Task 9 if `flock` is unavailable.

**GPG signing under sandboxed Bash:** the implementer's git config has commit signing enabled. Inside Claude Code's default sandbox, `gpg-agent` access fails with "Operation not permitted" — every commit will fail. Each `git commit` in this plan must be invoked with `dangerouslyDisableSandbox: true` (Bash tool parameter). This is environmental, not a code issue. Do not amend commits to skip signing without the user's explicit consent.

**Two deployments to keep in sync** (already noted in `CLAUDE.md`): this repo (development) and the user's live install (`~/.ckipper/` post-migration). Phases 1–6.5 only touch the repo. Phase 7 deploys to the host.

**Memory and CLAUDE.md persist across context clears.** Verify by checking that `~/.claude/projects/-Users-matt-Developer-Whmoro-claude-docker-sandbox/memory/MEMORY.md` mentions the Ckipper rename. If it does, the high-level project context is intact even after a fresh start.

---

## Working Conventions

- **Branch:** `feature/ckipper-multi-account` (off `develop`).
- **Commits:** small and frequent — one per task. PR target: `develop`.
- **Verification per task:** `shellcheck` on bash files, `zsh -n` on zsh files (shellcheck doesn't lint zsh well), then a smoke test that sources the function and exercises it. Fixture tests live in `tests/`. Heavyweight Docker testing happens at Phase 6.5 (smoke) and Phase 7 (full).
- **Local deployment:** the implementer's host has a live install at `~/.claude/docker/` (old) → `~/.ckipper/` (new). Do not run `install.sh` on the host until Phase 7. Phases 1–6 happen on the feature branch only.
- **Naming:** generic placeholders in repo only (`<name>`, `personal`, `work`, `<your-second-account>`). Never hardcode any specific user's account name or email.
- **Fixture cleanup:** every `/tmp/ckipper-test-*` fixture has a `trap 'rm -rf …' EXIT` to prevent state leak between tasks.
- **Scope guard:** if a task tempts you to "also clean up X", stop. Add it to the follow-ups list. The plan is the plan.

---

## Phase 1 — Rename to Ckipper (text-only, no behavior change)

### Task 1: Rename in CLAUDE.md

**Files:** Modify `CLAUDE.md`.

**Step 1: Replace project name in description.** Change the first paragraph from:
> Docker-based sandbox for running Claude Code with `--dangerously-skip-permissions` safely.

To:
> **Ckipper** (pronounced "skipper") — Docker-based sandbox for running Claude Code with `--dangerously-skip-permissions` safely.

**Step 2:** Update the `Architecture` and `Development Workflow` sections to reference `~/.ckipper/` instead of `~/.claude/docker/` and `~/.claude/hooks/`. This is documentation forward-looking; actual file moves happen in Phase 2.

**Step 3: Verify**

```bash
grep -n "claude-docker-sandbox\|~/.claude/docker\|~/.claude/hooks" CLAUDE.md
```

Expected: empty (or only intentional historical references).

**Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "Rename project to Ckipper in CLAUDE.md"
```

### Task 2: Rename in README.md

**Files:** Modify `README.md`.

**Step 1:** Replace all occurrences of "claude-docker-sandbox" with "Ckipper". Add the pronunciation note ("pronounced 'skipper'") to the heading.

**Step 2:** Update install/source instructions to reference `~/.ckipper/docker/w-function.zsh`. Leave a "migrating from previous versions" placeholder filled in by Task 19 (full README rewrite).

**Step 3: Verify**

```bash
grep -n "claude-docker-sandbox" README.md
```

Expected: empty.

**Step 4: Commit**

```bash
git add README.md
git commit -m "Rename project to Ckipper in README"
```

### Task 3: Rename Docker image tag

**Files:** Modify `w-function.zsh`, `CLAUDE.md`, `README.md`, `docker/Dockerfile` (LABEL/comments).

**Step 1:** Rename the Docker image tag from `claude-dev` to `ckipper-dev` in:
- `_w_build_image` (currently line ~41)
- The existence check (currently line ~269)
- The parallel-container detection (currently line ~417, the `ancestor=claude-dev` filter)
- Any LABEL or comment in `docker/Dockerfile`
- Any documentation references in `CLAUDE.md` and `README.md`

**Step 2: Verify**

```bash
grep -rn "claude-dev" w-function.zsh CLAUDE.md README.md docker/
```

Expected: empty.

**Step 3: Commit**

```bash
git add w-function.zsh CLAUDE.md README.md docker/Dockerfile
git commit -m "Rename Docker image tag claude-dev -> ckipper-dev"
```

Note: the implementer's live deployment still has the `claude-dev` image cached. Phase 7 (`ckipper migrate`) runs `docker rmi claude-dev 2>/dev/null` to clean it up.

---

## Phase 2 — Move tooling location to `~/.ckipper/`

### Task 4: Update `install.sh` to deploy to `~/.ckipper/`

**Files:** Modify `install.sh`.

**Step 1:** Read the existing `install.sh` end-to-end. Identify every absolute reference to `~/.claude/docker/` and `~/.claude/hooks/`.

**Step 2:** Introduce `CKIPPER_DIR="${CKIPPER_DIR:-$HOME/.ckipper}"` at the top. Replace `~/.claude/docker/` with `$CKIPPER_DIR/docker/` throughout. Hooks deploy to `$CKIPPER_DIR/hooks/` (canonical source); per-account hook copies happen via `ckipper sync-hooks`.

**Step 3:** Preserve `w-config.zsh` (existing `install.sh` already special-cases this — extend the guard to also protect `accounts.json` and `aliases.zsh` if they exist in `$CKIPPER_DIR`).

**Step 4:** **Settings.json merge — decision: drop it from `install.sh` entirely.** The current install merges `settings-hooks.json` into `~/.claude/settings.json`. In the multi-account world, hook settings live per-account and are written by `ckipper sync-hooks` from `$CKIPPER_DIR/settings-template.json`. Move the existing `settings-hooks.json` content into a new file `$CKIPPER_DIR/settings-template.json` (deployed by `install.sh`); `ckipper add` and `ckipper sync-hooks` consume it.

**Step 5:** **`.zshrc` auto-edit policy — keep the existing auto-append behavior but update the source line.** The current `install.sh` (lines ~77-84) auto-appends `source ~/.claude/docker/w-function.zsh`. Update this to append `source ~/.ckipper/docker/w-function.zsh` instead, with an idempotent grep guard. **Print** (do not auto-append) the optional second line for `aliases.zsh` since that's user-choice and depends on whether they want per-account aliases.

**Step 6: Verify**

```bash
shellcheck install.sh
bash -n install.sh
```

Expected: no errors.

**Step 7: Commit**

```bash
git add install.sh
git commit -m "Deploy Ckipper tooling to ~/.ckipper/ and split settings template"
```

### Task 5: Update internal path references in `w-function.zsh`

**Files:** Modify `w-function.zsh`.

**Step 1:** Replace the config-source path:

```zsh
# old
_w_config="$HOME/.claude/docker/w-config.zsh"
# new
_w_config="${CKIPPER_DIR:-$HOME/.ckipper}/docker/w-config.zsh"
```

And in `_w_build_image`:

```zsh
local docker_dir="${CKIPPER_DIR:-$HOME/.ckipper}/docker"
```

**Step 2:** Verify no other `~/.claude/docker` strings remain:

```bash
grep -n "claude/docker" w-function.zsh
```

Expected: empty.

**Step 3:** Verify the function still parses:

```bash
zsh -n w-function.zsh
```

Expected: exit 0 with no output.

**Step 4: Commit**

```bash
git add w-function.zsh
git commit -m "Source w-function from ~/.ckipper/ instead of ~/.claude/docker/"
```

### Task 6: Add `install.sh` migration of legacy `~/.claude/docker/` layout

**Files:** Modify `install.sh`.

**Important ordering:** This task lands AFTER Task 4 in the same branch (Task 4 must rewrite the deploy targets first; otherwise `install.sh` writes to both `~/.claude/docker/` AND `~/.ckipper/`, leaving drifting copies). Verify Task 4's changes are present before applying this one.

**Step 1:** At the top of `install.sh`, after `CKIPPER_DIR` is defined, add a migration block:

```bash
# Migrate legacy ~/.claude/docker/ layout if present (idempotent)
LEGACY_DIR="$HOME/.claude/docker"
if [ -d "$LEGACY_DIR" ] && [ ! -d "$CKIPPER_DIR" ]; then
    echo "Migrating ~/.claude/docker/ -> $CKIPPER_DIR/"
    mkdir -p "$CKIPPER_DIR"
    cp -a "$LEGACY_DIR/." "$CKIPPER_DIR/"
    echo "Migrated. The legacy directory is left intact at $LEGACY_DIR for one release cycle."
    echo "After verifying the new location works (ckipper list shows your accounts):"
    echo "  rm -rf $LEGACY_DIR"
fi
```

**Step 2:** Sweep the user's `w-config.zsh` (just migrated) for stale `~/.claude/docker/` paths. If found, print a warning naming the lines so the user can update — do not auto-edit user-customized config.

**Step 3:** Update the `.zshrc` source line (extends Task 4's auto-append):

```bash
# Update legacy source line if present, otherwise auto-append the new one (existing pattern)
if grep -q "source.*\.claude/docker/w-function.zsh" "$HOME/.zshrc" 2>/dev/null; then
    sed -i.bak 's|source.*\.claude/docker/w-function\.zsh|source ~/.ckipper/docker/w-function.zsh|' "$HOME/.zshrc"
    echo "Updated ~/.zshrc source line. Backup at ~/.zshrc.bak."
fi
```

(`sed -i.bak` is portable across macOS and GNU sed.)

**Step 4: Verify**

```bash
shellcheck install.sh
```

Expected: no errors (warnings about quoting OK if pre-existing).

**Step 5: Commit**

```bash
git add install.sh
git commit -m "install.sh: migrate legacy ~/.claude/docker/ to ~/.ckipper/"
```

---

## Phase 3 — Account registry + `ckipper` CLI

### Task 7: Create the `ckipper` CLI scaffold

**Files:** Create `ckipper.zsh`.

**Step 1:** Create `ckipper.zsh` at the repo root:

```zsh
# Ckipper (pronounced "skipper") — multi-account Claude Code manager
# Sourced by w-function.zsh

CKIPPER_DIR="${CKIPPER_DIR:-$HOME/.ckipper}"
CKIPPER_REGISTRY="$CKIPPER_DIR/accounts.json"
CKIPPER_REGISTRY_VERSION=1

ckipper() {
    local cmd="$1"
    shift 2>/dev/null
    case "$cmd" in
        # --help on any subcommand short-circuits to subcommand help
        add|list|default|remove|sync-hooks|migrate)
            if [[ "$1" == "--help" || "$1" == "-h" ]]; then
                _ckipper_help_for "$cmd"
                return 0
            fi
            "_ckipper_${cmd//-/_}" "$@"
            ;;
        ""|help|-h|--help) _ckipper_help ;;
        *) echo "Unknown command: $cmd"; _ckipper_help; return 1 ;;
    esac
}

_ckipper_help() {
    cat <<'EOF'
ckipper (pronounced "skipper") — multi-account Claude Code manager

Usage:
  ckipper add <name>          Register a new account (interactive /login)
  ckipper add <name> --adopt  Register an existing populated config dir
  ckipper list                Show registered accounts
  ckipper default <name>      Set the default account
  ckipper remove <name>       Unregister (does not delete the dir)
  ckipper sync-hooks          Copy hooks into all registered accounts
  ckipper migrate             One-time migration from legacy layout

Companion commands (sourced via aliases.zsh):
  cca <name> [args...]        Run claude with account <name> (one-off)
  claude-<name> [args...]     Auto-generated alias per registered account

Run `ckipper <subcommand> --help` for per-subcommand details.
EOF
}

_ckipper_help_for() {
    case "$1" in
        add)
            cat <<'EOF'
ckipper add <name> [--adopt]

Register a new account. <name> must match ^[a-z0-9_-]+$.

Without --adopt: creates ~/.claude-<name>/ and walks you through /login.
With --adopt:    registers an existing populated ~/.claude-<name>/ directory.
EOF
            ;;
        list)    echo "ckipper list — print registered accounts, default, and last-login email."  ;;
        default) echo "ckipper default <name> — set the default account used when no flag/env is provided." ;;
        remove)  echo "ckipper remove <name> — unregister. Does not delete the dir or Keychain entry." ;;
        sync-hooks) echo "ckipper sync-hooks — copy ~/.ckipper/hooks/* into each account's <dir>/hooks/, rewrite settings.json paths." ;;
        migrate) echo "ckipper migrate — migrate from legacy ~/.claude/docker/ layout. Idempotent. Refuses if Claude is running." ;;
    esac
}

# Stubs — implemented in subsequent tasks
_ckipper_add()        { echo "ckipper add: not yet implemented"; return 1; }
_ckipper_list()       { echo "ckipper list: not yet implemented"; return 1; }
_ckipper_default()    { echo "ckipper default: not yet implemented"; return 1; }
_ckipper_remove()     { echo "ckipper remove: not yet implemented"; return 1; }
_ckipper_sync_hooks() { echo "ckipper sync-hooks: not yet implemented"; return 1; }
_ckipper_migrate()    { echo "ckipper migrate: not yet implemented"; return 1; }
```

**Step 2:** At the bottom of `w-function.zsh`, after the existing completion block, add:

```zsh
# Source ckipper subcommand dispatcher (if deployed)
[[ -f "${CKIPPER_DIR:-$HOME/.ckipper}/docker/ckipper.zsh" ]] && \
    source "${CKIPPER_DIR:-$HOME/.ckipper}/docker/ckipper.zsh"
```

**Step 3:** Update `install.sh` to deploy `ckipper.zsh` to `$CKIPPER_DIR/docker/ckipper.zsh`.

**Step 4: Verify**

```bash
zsh -n ckipper.zsh
zsh -c 'source ./w-function.zsh; source ./ckipper.zsh; ckipper'
zsh -c 'source ./ckipper.zsh; ckipper add --help'
```

Expected: top-level help, then `add` subcommand help.

**Step 5: Commit**

```bash
git add ckipper.zsh w-function.zsh install.sh
git commit -m "Add ckipper CLI scaffold with per-subcommand help"
```

### Task 8: Implement `ckipper list`

**Files:** Modify `ckipper.zsh`.

**Step 1:** Replace the `_ckipper_list` stub:

```zsh
_ckipper_list() {
    if [[ ! -f "$CKIPPER_REGISTRY" ]]; then
        echo "No accounts registered. Run: ckipper add <name>"
        return 0
    fi
    local default
    default=$(jq -r '.default // ""' "$CKIPPER_REGISTRY")
    echo "Registered accounts:"
    jq -r '.accounts | to_entries[] | "  \(.key)\t\(.value.config_dir)"' "$CKIPPER_REGISTRY" | \
        while IFS=$'\t' read -r name dir; do
            local marker="  "
            [[ "$name" == "$default" ]] && marker="* "
            local email=""
            if [[ -f "$dir/.claude.json" ]]; then
                email=$(jq -r '.oauthAccount.emailAddress // ""' "$dir/.claude.json" 2>/dev/null)
            fi
            local exists="(missing)"
            [[ -d "$dir" ]] && exists=""
            echo "$marker$name  $dir  ${email:+($email)} $exists"
        done
    echo ""
    echo "* = default. Run: ckipper default <name>"
    echo ""
    echo "Reminder: do not run the same account in two sessions concurrently — see #24317."
}
```

**Step 2: Verify** — fixture test driven through real derivation, not direct `CKIPPER_REGISTRY` overrides:

```bash
TEST_HOME=$(mktemp -d -t ckipper-test-list-XXXXXX)
trap "rm -rf '$TEST_HOME'" EXIT
mkdir -p "$TEST_HOME/.ckipper"
cat > "$TEST_HOME/.ckipper/accounts.json" <<EOF
{
  "version": 1,
  "default": "personal",
  "accounts": {
    "personal": {"config_dir": "$TEST_HOME/.claude-personal", "keychain_service": "Claude Code-credentials"},
    "work": {"config_dir": "$TEST_HOME/.claude-work", "keychain_service": "Claude Code-credentials-abc12345"}
  }
}
EOF
HOME="$TEST_HOME" CKIPPER_DIR="$TEST_HOME/.ckipper" \
  zsh -c 'source ./ckipper.zsh; ckipper list'
```

Expected: prints both accounts, marks `personal` as default, shows `(missing)` for both dirs, prints the concurrency reminder.

**Step 3: Commit**

```bash
git add ckipper.zsh
git commit -m "Implement ckipper list"
```

### Task 9: Implement `ckipper add <name>` (interactive login flow)

This task absorbs the heaviest revisions from the panel review. Read the **Reviewer notes** at the end before implementing.

**Files:** Modify `ckipper.zsh`. Create `tests/keychain-dump.sample`.

**Step 1: Capture a real Keychain-dump fixture.** On macOS:

```bash
mkdir -p tests
security dump-keychain 2>/dev/null | \
  awk '/^keychain: / || /class: "genp"/ || /"svce"<blob>=/ || /"acct"<blob>=/' | \
  sed 's|/Users/[^/]*/|/Users/<user>/|g' \
  > tests/keychain-dump.sample
```

This sample is what the snapshot parser expects to consume. Trim it to ~3 entries (one Claude entry, two unrelated) so the test is deterministic. Commit it under `tests/`.

**Step 2: Implement `_ckipper_keychain_snapshot` and validation helpers:**

```zsh
# Validates a keychain_service name before passing to `security`.
# Accepts "Claude Code-credentials" optionally followed by "-<8hex>".
_ckipper_validate_keychain_service() {
    local svc="$1"
    [[ -z "$svc" ]] && return 1
    [[ "$svc" =~ ^Claude\ Code-credentials(-[a-f0-9]+)?$ ]]
}

_ckipper_keychain_snapshot() {
    # macOS only. Returns service names of all "Claude Code-credentials*" entries, sorted.
    [[ "$OSTYPE" != darwin* ]] && return 0

    # Fail loudly if keychain is locked (timeout protects against GUI prompt blocking).
    local out
    if ! out=$(timeout 10 security dump-keychain 2>/dev/null); then
        echo "Warning: Keychain may be locked or slow. Unlock it (Keychain Access > File > Unlock) and retry." >&2
        return 1
    fi

    printf '%s\n' "$out" | \
        awk -F'"' '/"svce"<blob>="Claude Code-credentials/ {print $4}' | \
        sort -u
}

# Atomic registry write under flock. $1 = filter expression for jq.
_ckipper_registry_update() {
    local jq_filter="$1"
    shift
    local lock="$CKIPPER_DIR/.registry.lock"
    mkdir -p "$CKIPPER_DIR"
    : > "$lock"
    {
        flock -x 9
        local tmp; tmp=$(mktemp)
        jq "$@" "$jq_filter" "$CKIPPER_REGISTRY" > "$tmp" && mv "$tmp" "$CKIPPER_REGISTRY"
        chmod 600 "$CKIPPER_REGISTRY"
    } 9>"$lock"
}

# Initialize an empty registry with version field.
_ckipper_init_registry() {
    if [[ ! -f "$CKIPPER_REGISTRY" ]]; then
        mkdir -p "$CKIPPER_DIR"
        cat > "$CKIPPER_REGISTRY" <<EOF
{"version": $CKIPPER_REGISTRY_VERSION, "default": null, "accounts": {}}
EOF
        chmod 600 "$CKIPPER_REGISTRY"
    fi
}

# Refuse to operate on a registry whose version we don't understand.
_ckipper_check_registry_version() {
    [[ ! -f "$CKIPPER_REGISTRY" ]] && return 0
    local v
    v=$(jq -r '.version // 0' "$CKIPPER_REGISTRY")
    if (( v != CKIPPER_REGISTRY_VERSION )); then
        echo "Error: registry version $v not supported (this ckipper expects $CKIPPER_REGISTRY_VERSION). Update ckipper or restore from backup." >&2
        return 1
    fi
}
```

**Step 3: Implement `_ckipper_add`:**

```zsh
_ckipper_add() {
    _ckipper_check_registry_version || return 1
    local name="$1" adopt=0
    [[ "$2" == "--adopt" ]] && adopt=1
    if [[ -z "$name" ]]; then
        echo "Usage: ckipper add <name> [--adopt]"
        return 1
    fi
    if [[ ! "$name" =~ ^[a-z0-9_-]+$ ]]; then
        echo "Account name must match ^[a-z0-9_-]+$ (lowercase alphanumeric, underscore, hyphen)."
        return 1
    fi

    _ckipper_init_registry

    if jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null; then
        echo "Account '$name' is already registered."
        return 1
    fi

    local dir="$HOME/.claude-$name"

    if [[ $adopt -eq 1 ]]; then
        if [[ ! -d "$dir" ]]; then
            echo "Cannot adopt: $dir does not exist."
            return 1
        fi
        # In adopt mode, list candidate Keychain entries and let the user pick (or skip).
        local picked=""
        if [[ "$OSTYPE" == darwin* ]]; then
            local candidates
            candidates=$(_ckipper_keychain_snapshot) || return 1
            if [[ -n "$candidates" ]]; then
                echo "Candidate Keychain entries:"
                echo "$candidates" | nl
                read -r "?Pick a number (or empty to skip): " idx
                if [[ -n "$idx" ]]; then
                    picked=$(echo "$candidates" | sed -n "${idx}p")
                    if [[ -n "$picked" ]] && ! _ckipper_validate_keychain_service "$picked"; then
                        echo "Invalid Keychain service shape: $picked"
                        return 1
                    fi
                fi
            fi
        fi
        _ckipper_finalize_registration "$name" "$dir" "$picked" "adopt"
        return $?
    fi

    # Fresh registration
    if [[ -d "$dir" ]]; then
        echo "Directory $dir already exists. Use --adopt to register it."
        return 1
    fi
    mkdir -p "$dir/hooks"
    if [[ -f "$CKIPPER_DIR/settings-template.json" ]]; then
        cp "$CKIPPER_DIR/settings-template.json" "$dir/settings.json"
    fi

    local before_snapshot
    before_snapshot=$(_ckipper_keychain_snapshot) || return 1

    cat <<EOF

A new account directory was created at $dir.

In this same shell, run:

    CLAUDE_CONFIG_DIR=$dir claude

Complete the /login flow with the account you want to register as '$name'.
When done, exit Claude (Ctrl-D) and press enter here to finish registration.
If you closed the terminal by mistake, recover with: ckipper add $name --adopt

EOF
    read -r "?Press enter when /login is complete (or type 'skip' to abort): " ack
    if [[ "$ack" == "skip" ]]; then
        echo "Aborted. The directory $dir was created but not registered."
        echo "To complete registration later: ckipper add $name --adopt"
        return 1
    fi

    local after_snapshot
    after_snapshot=$(_ckipper_keychain_snapshot) || return 1

    # Diff using printf (not echo) for comm-friendly input
    local new_service
    new_service=$(comm -13 \
        <(printf '%s\n' "$before_snapshot") \
        <(printf '%s\n' "$after_snapshot") | head -1)

    if [[ -n "$new_service" ]]; then
        if ! _ckipper_validate_keychain_service "$new_service"; then
            echo "Detected entry has unexpected shape: $new_service"
            echo "Refusing to register. Use --adopt to register manually."
            return 1
        fi
        echo "Detected new Keychain entry: $new_service"
    else
        # No new entry. Could be: (a) login failed, (b) API-key auth (creds on disk), (c) keychain misread.
        if [[ -f "$dir/.credentials.json" ]]; then
            echo "No new Keychain entry, but $dir/.credentials.json exists — proceeding with on-disk credentials."
        else
            echo "Warning: no new Keychain entry detected and no .credentials.json on disk."
            echo "Login may not have completed. Re-run /login or use: ckipper add $name --adopt"
            return 1
        fi
    fi

    _ckipper_finalize_registration "$name" "$dir" "$new_service" "fresh"
}

_ckipper_finalize_registration() {
    local name="$1" dir="$2" service="$3" mode="$4"
    local now; now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    _ckipper_registry_update '
        .accounts[$n] = {config_dir: $d, keychain_service: (if $s == "" then null else $s end), registered_at: $t}
        | (if .default == null then .default = $n else . end)
    ' --arg n "$name" --arg d "$dir" --arg s "$service" --arg t "$now"

    _ckipper_regenerate_aliases
    _ckipper_sync_hooks_for "$name"

    echo "Registered '$name' (mode: $mode)."
    echo "Use it via: claude-$name   or   cca $name"
}
```

**Step 4:** Add `_ckipper_regenerate_aliases` and `_ckipper_sync_hooks_for` as stubs (Tasks 12, 13):

```zsh
_ckipper_regenerate_aliases() { :; }
_ckipper_sync_hooks_for() { :; }
```

**Step 5: Verify**

```bash
zsh -n ckipper.zsh

# Validation tests
zsh -c 'source ./ckipper.zsh; ckipper add'                  # usage error
zsh -c 'source ./ckipper.zsh; ckipper add Bad-Name'         # uppercase rejected
zsh -c 'source ./ckipper.zsh; _ckipper_validate_keychain_service "Claude Code-credentials" && echo OK'      # → OK
zsh -c 'source ./ckipper.zsh; _ckipper_validate_keychain_service "Claude Code-credentials-abc12345" && echo OK'  # → OK
zsh -c 'source ./ckipper.zsh; _ckipper_validate_keychain_service "" && echo OK || echo REJECTED'           # → REJECTED
zsh -c 'source ./ckipper.zsh; _ckipper_validate_keychain_service "Claude Code-credentials; rm -rf /" && echo OK || echo REJECTED'  # → REJECTED

# Snapshot regression test against fixture
zsh -c '
  source ./ckipper.zsh
  fake_dump() { cat tests/keychain-dump.sample; }
  printf "%s\n" "$(fake_dump | awk -F'"'"'"'"'"'"'"'"' '"'"'/"svce"<blob>="Claude Code-credentials/ {print $4}'"'"' | sort -u)"
'
```

The snapshot fixture test should print the Claude entry from the sample. If it prints nothing, the awk pattern is broken — fix it before continuing.

**Step 6: Commit**

```bash
git add ckipper.zsh tests/keychain-dump.sample
git commit -m "Implement ckipper add: validated keychain shape, atomic registry, fixture test"
```

**Reviewer notes folded into this task:**
- `printf '%s\n'` instead of `echo` for `comm` input (handles empty-snapshot case correctly).
- Locked-keychain detection via `timeout 10`.
- `keychain_service` shape validated before write.
- Registry is `chmod 600` and protected by `flock`.
- Schema `version: 1` written on creation.
- "skip" sentinel for the interactive prompt.
- `--adopt` lists candidates and asks the user to pick (no silent guessing).
- Fixture-based snapshot regression test.

### Task 10: Validate `--adopt` end-to-end

**Files:** No new files; verification only.

```bash
TEST_HOME=$(mktemp -d -t ckipper-test-adopt-XXXXXX)
trap "rm -rf '$TEST_HOME'" EXIT
mkdir -p "$TEST_HOME/.claude-personal"
echo '{"oauthAccount":{"emailAddress":"test@example.com"}}' > "$TEST_HOME/.claude-personal/.claude.json"
HOME="$TEST_HOME" CKIPPER_DIR="$TEST_HOME/.ckipper" OSTYPE=linux-gnu \
  zsh -c 'source ./ckipper.zsh; ckipper add personal --adopt < /dev/null'
HOME="$TEST_HOME" CKIPPER_DIR="$TEST_HOME/.ckipper" \
  zsh -c 'source ./ckipper.zsh; ckipper list'
```

Forcing `OSTYPE=linux-gnu` exercises the `keychain_service: null` path (Linux/on-disk credentials) — important regression coverage. Expected: `personal` registered with `(test@example.com)`.

**Commit only if changes were needed.**

### Task 11: Implement `ckipper default` and `ckipper remove`

**Files:** Modify `ckipper.zsh`.

**Step 1:**

```zsh
_ckipper_default() {
    _ckipper_check_registry_version || return 1
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: ckipper default <name>"; return 1; }
    if ! jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null; then
        echo "Account '$name' is not registered."
        return 1
    fi
    _ckipper_registry_update '.default = $n' --arg n "$name"
    echo "Default account is now '$name'."
}

_ckipper_remove() {
    _ckipper_check_registry_version || return 1
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: ckipper remove <name>"; return 1; }
    if ! jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null; then
        echo "Account '$name' is not registered."
        return 1
    fi
    local dir; dir=$(jq -r --arg n "$name" '.accounts[$n].config_dir' "$CKIPPER_REGISTRY")
    local service; service=$(jq -r --arg n "$name" '.accounts[$n].keychain_service // ""' "$CKIPPER_REGISTRY")
    _ckipper_registry_update 'del(.accounts[$n]) | (if .default == $n then .default = null else . end)' --arg n "$name"
    _ckipper_regenerate_aliases
    echo "Unregistered '$name'."
    echo ""
    echo "The directory and Keychain entry were not deleted. To remove them manually:"
    printf "  rm -rf %q\n" "$dir"
    if [[ -n "$service" ]]; then
        printf "  security delete-generic-password -s %q\n" "$service"
    fi
}
```

(`printf '%q'` quote-protects against unusual characters in `$dir`/`$service`.)

**Step 2: Verify** (uses fixture from Task 10):

```bash
TEST_HOME=$(mktemp -d -t ckipper-test-remove-XXXXXX)
trap "rm -rf '$TEST_HOME'" EXIT
# ... seed registry with 'personal' ...
HOME="$TEST_HOME" CKIPPER_DIR="$TEST_HOME/.ckipper" \
  zsh -c 'source ./ckipper.zsh; ckipper default personal; ckipper remove personal; ckipper list'
```

Expected: default set, then unregistered, then list shows no accounts.

**Step 3: Commit**

```bash
git add ckipper.zsh
git commit -m "Implement ckipper default and remove with quote safety"
```

### Task 12: Implement self-contained `aliases.zsh` auto-generation

**Files:** Modify `ckipper.zsh`.

**Critical constraint:** `aliases.zsh` must be self-contained — sourcing it alone (without `ckipper.zsh` or `w-function.zsh`) must produce a working `cca` and `claude-<name>` set. The generated file defines its own `CKIPPER_REGISTRY` path before defining `cca`.

**Step 1:**

```zsh
_ckipper_regenerate_aliases() {
    local out="$CKIPPER_DIR/aliases.zsh"
    {
        echo "# Auto-generated by ckipper. Do not edit by hand."
        echo "# Self-contained: does not depend on ckipper.zsh or w-function.zsh being sourced."
        echo "# Regenerated whenever an account is added or removed."
        echo ""
        echo "_CKIPPER_REGISTRY=\"\${CKIPPER_DIR:-\$HOME/.ckipper}/accounts.json\""
        echo ""
        echo "cca() {"
        echo "    local name=\"\$1\"; shift"
        echo "    if [[ -z \"\$name\" ]]; then echo \"Usage: cca <name> [args...]\"; return 1; fi"
        echo "    local dir"
        echo "    dir=\$(jq -r --arg n \"\$name\" '.accounts[\$n].config_dir // empty' \"\$_CKIPPER_REGISTRY\" 2>/dev/null)"
        echo "    if [[ -z \"\$dir\" ]]; then echo \"Unknown account: \$name. Run: ckipper list\"; return 1; fi"
        echo "    CLAUDE_CONFIG_DIR=\"\$dir\" command claude \"\$@\""
        echo "}"
        echo ""
        if [[ -f "$CKIPPER_REGISTRY" ]]; then
            jq -r '.accounts | to_entries[] | "\(.key)\t\(.value.config_dir)"' "$CKIPPER_REGISTRY" | \
                while IFS=$'\t' read -r name dir; do
                    echo "claude-$name() { CLAUDE_CONFIG_DIR=\"$dir\" command claude \"\$@\"; }"
                done
        fi
    } > "$out"
    chmod 644 "$out"
}
```

**Step 2:** `install.sh` already prints (Task 4 step 5) the optional source line for `aliases.zsh`. Confirm that message is still in the install output.

**Step 3: Verify (independence test)**

```bash
TEST_HOME=$(mktemp -d -t ckipper-test-aliases-XXXXXX)
trap "rm -rf '$TEST_HOME'" EXIT
mkdir -p "$TEST_HOME/.claude-personal"
echo '{"oauthAccount":{"emailAddress":"x@y.z"}}' > "$TEST_HOME/.claude-personal/.claude.json"
HOME="$TEST_HOME" CKIPPER_DIR="$TEST_HOME/.ckipper" OSTYPE=linux-gnu \
  zsh -c 'source ./ckipper.zsh; ckipper add personal --adopt < /dev/null'

# Source ONLY aliases.zsh (no ckipper.zsh) and confirm cca works.
HOME="$TEST_HOME" CKIPPER_DIR="$TEST_HOME/.ckipper" \
  zsh -c 'source "$CKIPPER_DIR/aliases.zsh"; type cca && type claude-personal'
```

Expected: both `cca` and `claude-personal` are defined as functions, even though `ckipper.zsh` was never sourced.

**Step 4: Commit**

```bash
git add ckipper.zsh
git commit -m "Auto-generate self-contained aliases.zsh with cca dispatcher"
```

### Task 13: Implement `ckipper sync-hooks`

**Files:** Modify `ckipper.zsh`.

**Step 1:**

```zsh
_ckipper_sync_hooks_for() {
    local name="$1"
    _ckipper_check_registry_version || return 1
    local dir; dir=$(jq -r --arg n "$name" '.accounts[$n].config_dir' "$CKIPPER_REGISTRY")
    [[ -z "$dir" || "$dir" == "null" ]] && return 1
    mkdir -p "$dir/hooks"
    cp -a "$CKIPPER_DIR/hooks/." "$dir/hooks/" 2>/dev/null || true

    # Rewrite settings.json hook paths to absolute paths under this account dir.
    if [[ -f "$dir/settings.json" ]] && command -v jq &>/dev/null; then
        local tmp; tmp=$(mktemp)
        jq --arg d "$dir" '
            (.hooks // {}) as $h |
            .hooks = ($h | walk(
                if type == "string" and (test("/.claude(-[a-z0-9_-]+)?/hooks/") or test("/.ckipper/hooks/"))
                then sub("(/.claude(-[a-z0-9_-]+)?|/.ckipper)/hooks/"; "\($d)/hooks/")
                else . end
            ))
        ' "$dir/settings.json" > "$tmp" && mv "$tmp" "$dir/settings.json"
    fi
}

_ckipper_sync_hooks() {
    if [[ ! -f "$CKIPPER_REGISTRY" ]]; then
        echo "No accounts registered."
        return 0
    fi
    _ckipper_check_registry_version || return 1
    local names; names=$(jq -r '.accounts | keys[]' "$CKIPPER_REGISTRY")
    while IFS= read -r name; do
        echo "Syncing hooks → $name"
        _ckipper_sync_hooks_for "$name"
    done <<< "$names"
}
```

**Step 2: Verify**

```bash
TEST_HOME=$(mktemp -d -t ckipper-test-sync-XXXXXX)
trap "rm -rf '$TEST_HOME'" EXIT
# ... seed account ...
mkdir -p "$TEST_HOME/.ckipper/hooks"
echo "echo test" > "$TEST_HOME/.ckipper/hooks/sample.sh"
HOME="$TEST_HOME" CKIPPER_DIR="$TEST_HOME/.ckipper" \
  zsh -c 'source ./ckipper.zsh; ckipper sync-hooks; ls "$HOME/.claude-personal/hooks/"'
```

Expected: `sample.sh` present in the per-account hooks dir.

**Note on settings-template ownership:** `settings-template.json` is owned by the repo (deployed by `install.sh` to `~/.ckipper/settings-template.json`). It is **seed-only** — accounts diverge after creation. When the template version drifts, already-registered accounts are NOT auto-updated; the user re-runs `ckipper sync-hooks` to refresh hook paths and (in a future task) `ckipper sync-settings` for full template re-application. This stance is documented in CLAUDE.md and README.

**Step 3: Commit**

```bash
git add ckipper.zsh
git commit -m "Implement ckipper sync-hooks; document template seed-only stance"
```

---

## Phase 4 — Account-aware `w` and entrypoint

### Task 14: `w` resolves the active account

**Files:** Modify `w-function.zsh`.

**Step 1:** Add `_w_resolve_account` at the top of `w-function.zsh` (before the `w()` function):

```zsh
_w_resolve_account() {
    local cli_account="$1"
    if [[ -n "$cli_account" ]]; then
        echo "$cli_account"; return 0
    fi
    if [[ -n "$CLAUDE_CONFIG_DIR" && -f "$CKIPPER_REGISTRY" ]]; then
        local matched
        matched=$(jq -r --arg d "$CLAUDE_CONFIG_DIR" \
            '.accounts | to_entries[] | select(.value.config_dir == $d) | .key' \
            "$CKIPPER_REGISTRY" | head -1)
        [[ -n "$matched" ]] && { echo "$matched"; return 0; }
    fi
    if [[ -f "$CKIPPER_REGISTRY" ]]; then
        local default
        default=$(jq -r '.default // ""' "$CKIPPER_REGISTRY")
        [[ -n "$default" ]] && { echo "$default"; return 0; }
    fi
    return 0
}
```

**Step 2:** Add `--account <name>` to the flag parser:

```zsh
local cli_account=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --docker)   docker_mode=1; shift ;;
        --firewall) firewall_mode=1; shift ;;
        --account)  cli_account="$2"; shift 2 ;;
        *)          command+=("$1"); shift ;;
    esac
done
```

**Step 3:** After existing arg validation, resolve and validate the account. **No legacy fallback** — if no account resolves, error out (per panel decision: error not silent fallback):

```zsh
local active_account
active_account=$(_w_resolve_account "$cli_account")
if [[ -z "$active_account" ]]; then
    echo "Error: no account selected and no default registered."
    echo "Run: ckipper list   (then: ckipper default <name>, or pass --account <name>)"
    return 1
fi
local active_config_dir; active_config_dir=$(jq -r --arg n "$active_account" '.accounts[$n].config_dir // empty' "$CKIPPER_REGISTRY")
local active_keychain_service; active_keychain_service=$(jq -r --arg n "$active_account" '.accounts[$n].keychain_service // empty' "$CKIPPER_REGISTRY")
if [[ -z "$active_config_dir" ]]; then
    echo "Error: account '$active_account' is not registered. Run: ckipper list"
    return 1
fi
```

**Step 4: Verify**

```bash
zsh -n w-function.zsh
TEST_HOME=$(mktemp -d -t w-resolve-XXXXXX)
trap "rm -rf '$TEST_HOME'" EXIT
# ... seed registry with default 'personal' ...
HOME="$TEST_HOME" CKIPPER_DIR="$TEST_HOME/.ckipper" CKIPPER_REGISTRY="$TEST_HOME/.ckipper/accounts.json" \
  zsh -c 'source ./w-function.zsh; _w_resolve_account ""'
```

Expected: prints `personal`.

**Step 5: Commit**

```bash
git add w-function.zsh
git commit -m "w: resolve active account from --account, env, or registered default"
```

### Task 15: `w` Docker args use per-account paths and Keychain service

**Files:** Modify `w-function.zsh`. Create `docker/cleanup-projects.py`.

**Pre-task audit (CRITICAL):** Before changing any mounts, run:

```bash
grep -rn "/home/claude/.claude" docker/ w-function.zsh
```

For each hit, decide: keep (it's a container `$HOME` path unrelated to Claude state, e.g., `.local/bin`) or migrate (it's a Claude-state path that must move to `$CLAUDE_CONFIG_DIR`). Document the decision in a comment near each line. **Only after this audit is the Step 2 mount change safe.**

**Step 1:** Replace the hardcoded credential extraction. Validate the service name first:

```zsh
if ! _ckipper_validate_keychain_service "$active_keychain_service" && [[ -n "$active_keychain_service" ]]; then
    echo "Error: account '$active_account' has invalid keychain_service in registry."
    echo "Re-register with: ckipper remove $active_account && ckipper add $active_account --adopt"
    return 1
fi
local claude_creds=""
if [[ -n "$active_keychain_service" ]]; then
    claude_creds=$(security find-generic-password -s "$active_keychain_service" -w 2>/dev/null) || true
fi
```

(Note: `_ckipper_validate_keychain_service` is sourced by `w-function.zsh` because `ckipper.zsh` is sourced from it.)

**Step 2:** Replace the `~/.claude` mount block. The dropped `/home/claude/.claude` mount is justified by the Step-0 audit:

```zsh
# old (three mounts)
-v "$HOME/.claude:/home/claude/.claude:rw"
-v "$HOME/.claude.json:/home/claude/.claude-host.json:ro"
-v "$HOME/.claude:$HOME/.claude:rw"
# new (single per-account mount + read-only staging copy)
-v "$active_config_dir:$active_config_dir:rw"
-v "$active_config_dir/.claude.json:$active_config_dir/.claude-host.json:ro"
-e "CLAUDE_CONFIG_DIR=$active_config_dir"
```

**Step 3:** Update the gh-token extraction to use the per-account `.claude.json`:

```zsh
gh_token=$(jq -r '.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN // empty' "$active_config_dir/.claude.json" 2>/dev/null) || true
```

**Step 4: Extract the worktree project-settings sync to `docker/cleanup-projects.py`** (replaces the inline Python heredocs at lines ~111 and ~232 of the current `w-function.zsh`). The script walks the registry (not a glob — registry-driven cleanup):

```python
#!/usr/bin/env python3
"""Remove or sync a worktree path entry from per-account .claude.json files."""
import json, os, sys

def all_account_dirs(registry):
    if not os.path.exists(registry): return []
    with open(registry) as f:
        d = json.load(f)
    return [a["config_dir"] for a in d.get("accounts", {}).values() if a.get("config_dir")]

def remove_worktree_from_all(registry, wt_path):
    seen = set()
    for cfg_dir in all_account_dirs(registry):
        cfg = os.path.join(cfg_dir, ".claude.json")
        cfg_real = os.path.realpath(cfg)
        if cfg_real in seen: continue
        seen.add(cfg_real)
        if not os.path.exists(cfg): continue
        with open(cfg) as f:
            d = json.load(f)
        if wt_path in d.get("projects", {}):
            del d["projects"][wt_path]
            with open(cfg, "w") as f:
                json.dump(d, f)
            print(f"Removed worktree entry from {cfg}")

def sync_worktree_settings(registry, account_name, main_path, wt_path):
    if not os.path.exists(registry): return
    with open(registry) as f:
        d = json.load(f)
    acc = d.get("accounts", {}).get(account_name)
    if not acc: return
    cfg = os.path.join(acc["config_dir"], ".claude.json")
    if not os.path.exists(cfg): return
    with open(cfg) as f:
        cd = json.load(f)
    main = cd.get("projects", {}).get(main_path, {})
    if not main: return
    keys = ["disabledMcpServers", "enabledMcpjsonServers", "disabledMcpjsonServers",
            "allowedTools", "hasTrustDialogAccepted", "hasClaudeMdExternalIncludesApproved",
            "hasClaudeMdExternalIncludesWarningShown", "hasCompletedProjectOnboarding"]
    wt = cd.setdefault("projects", {}).setdefault(wt_path, {})
    for k in keys:
        if k in main: wt[k] = main[k]
    with open(cfg, "w") as f:
        json.dump(cd, f)
    print(f"Synced settings for {wt_path} in {cfg}")

if __name__ == "__main__":
    cmd = sys.argv[1]
    registry = os.environ.get("CKIPPER_REGISTRY", os.path.expanduser("~/.ckipper/accounts.json"))
    if cmd == "remove":
        remove_worktree_from_all(registry, sys.argv[2])
    elif cmd == "sync":
        sync_worktree_settings(registry, sys.argv[2], sys.argv[3], sys.argv[4])
```

Update `w-function.zsh` to call this script in `--rm` cleanup and worktree-creation sync, replacing the inline heredocs.

**Step 5:** Drop the post-session credential symlink cleanup at lines ~416-420 of the current `w-function.zsh` — credentials now live inside the per-account dir, and the dir's `.credentials.json` is the symlink. Cleanup happens implicitly when the container exits (tmpfs disappears; the symlink target vanishes but the symlink remains on disk pointing at nothing — harmless and overwritten on next session).

**Step 6: Verify**

```bash
zsh -n w-function.zsh
shellcheck -s bash w-function.zsh   # warnings OK; errors not
python3 -c "import ast; ast.parse(open('docker/cleanup-projects.py').read())"
```

**Step 7: Commit**

```bash
git add w-function.zsh docker/cleanup-projects.py
git commit -m "w: thread active account through Docker; extract registry-driven cleanup"
```

### Task 16: Entrypoint uses `$CLAUDE_CONFIG_DIR` (and errors if unset)

**Files:** Modify `docker/entrypoint.sh`.

**Step 1:** At the top, after `set -e`, **error out** (no silent fallback) if the env var is unset:

```bash
if [ -z "$CLAUDE_CONFIG_DIR" ]; then
    echo "Error: CLAUDE_CONFIG_DIR is not set inside the container." >&2
    echo "This means w() did not pass the account context. Bug — please report." >&2
    exit 1
fi
if [ ! -d "$CLAUDE_CONFIG_DIR" ]; then
    echo "Error: CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR does not exist (mount failed?)." >&2
    exit 1
fi
```

(Per panel decision: silent fallback masks misconfiguration. Always require explicit account context inside the container.)

**Step 2:** Replace `~/.claude.json` and `~/.claude-host.json` references with `$CLAUDE_CONFIG_DIR/.claude.json` and `$CLAUDE_CONFIG_DIR/.claude-host.json`:

```bash
if [ -f "$CLAUDE_CONFIG_DIR/.claude-host.json" ]; then
    cp "$CLAUDE_CONFIG_DIR/.claude-host.json" "$CLAUDE_CONFIG_DIR/.claude.json"
    if command -v jq &>/dev/null; then
        jq '.claudeInChromeDefaultEnabled = false | .cachedChromeExtensionInstalled = false' \
            "$CLAUDE_CONFIG_DIR/.claude.json" > "$CLAUDE_CONFIG_DIR/.claude.json.tmp" \
            && mv "$CLAUDE_CONFIG_DIR/.claude.json.tmp" "$CLAUDE_CONFIG_DIR/.claude.json"
    fi
fi
```

**Step 3:** Update the credential symlink target:

```bash
ln -sf /tmp/claude-creds/.credentials.json "$CLAUDE_CONFIG_DIR/.credentials.json"
```

**Step 4:** Update git identity, MCP pre-install, and uvx jq queries to use `$CLAUDE_CONFIG_DIR/.claude.json`. Note that `$HOME` (container user home) is *not* changed — `.local/bin/bunx`, `.cache/uv`, `.ssh/`, etc. continue to live under `/home/claude/`. Only Claude-state paths move.

**Step 5: Verify**

```bash
shellcheck docker/entrypoint.sh
bash -n docker/entrypoint.sh
```

**Step 6: Commit**

```bash
git add docker/entrypoint.sh
git commit -m "entrypoint: read all Claude paths from CLAUDE_CONFIG_DIR; error if unset"
```

### Task 17: Hooks protect per-account dirs and `~/.ckipper/`

**Files:** Modify `hooks/protect-claude-config.sh`, `hooks/bash-guardrails.sh`. Update `test-prompt.md` Section 10.

**Critical fix from Security review:** without this, a Claude session in account A can edit `~/.ckipper/accounts.json` to redirect account B's keychain service into account A's container — credential cross-contamination.

**Step 1:** Read both hooks. Identify the existing `~/.claude/` substring patterns.

**Step 2:** Define the new protected-path regex. It must:
- Match `$HOME/.claude` and `$HOME/.claude-<name>` (any non-empty `[a-z0-9_-]+`)
- Match `$HOME/.ckipper`
- NOT match `$HOME/.claude-host.json` (the in-container read-only mount)

Required POSIX/PCRE-ish regex (test against both hook languages):

```
(^|/)\.claude(-[a-z0-9_-]+)?(/|$)|(^|/)\.ckipper(/|$)
```

**Step 3:** In `protect-claude-config.sh`, extend the protected-path check (PreToolUse on Edit/Write) to use the new regex. Block any path matching the regex unless it's in an explicit allow-list (e.g., `<account>/projects/`).

**Step 4:** In `bash-guardrails.sh`, extend the regex similarly so commands like `echo malicious > ~/.ckipper/accounts.json` are blocked.

**Step 5:** Add new bypass-attempt entries to `test-prompt.md` Section 10:
- Try editing `~/.ckipper/accounts.json` from inside Claude — must be BLOCKED.
- Try writing to `~/.claude-otheraccount/settings.json` from a session in `personal` — must be BLOCKED.
- Try writing to `$CLAUDE_CONFIG_DIR/projects/whatever.txt` — must be ALLOWED (under projects/).

**Step 6:** Re-run the existing Section 10 tests after the regex change. Confirm no regression. (Document this re-run in the PR test plan.)

**Step 7: Verify**

```bash
shellcheck hooks/*.sh
```

**Step 8: Commit**

```bash
git add hooks/protect-claude-config.sh hooks/bash-guardrails.sh test-prompt.md
git commit -m "hooks: extend protection to per-account dirs and ~/.ckipper"
```

---

## Phase 5 — Migration command

### Task 18: Implement `ckipper migrate` (safety-checked, no symlink)

**Files:** Modify `ckipper.zsh`.

**Decision-from-panel: drop the `~/.claude → ~/.claude-personal` symlink.** After migration, bare `claude` no longer maps to the personal account. Users use `claude-personal` (or whichever name they registered). The README and `migrate` output state this explicitly.

**Step 1:**

```zsh
_ckipper_migrate() {
    _ckipper_check_registry_version || return 1
    local legacy_docker="$HOME/.claude/docker"
    local legacy_claude="$HOME/.claude"

    # ── Precondition 1: no Claude process running ─────────────────
    if pgrep -f "[c]laude " >/dev/null 2>&1; then
        echo "Error: a Claude process is currently running. Quit all Claude sessions first." >&2
        echo "Detected: $(pgrep -af '[c]laude ' | head -3)" >&2
        return 1
    fi

    # ── Precondition 2: ~/.claude-personal must not already exist ─
    if [[ -e "$HOME/.claude-personal" ]]; then
        echo "Error: $HOME/.claude-personal already exists. Refusing to migrate." >&2
        echo "If you've already migrated, you're done. Run: ckipper list" >&2
        return 1
    fi

    # ── 1. Move ~/.claude/docker → ~/.ckipper/docker if not done ──
    if [[ -d "$legacy_docker" && ! -d "$CKIPPER_DIR/docker" ]]; then
        mkdir -p "$CKIPPER_DIR"
        cp -a "$legacy_docker/." "$CKIPPER_DIR/docker/"
        echo "Copied $legacy_docker → $CKIPPER_DIR/docker (legacy left intact for one release cycle)"
    fi

    # ── 2. Adopt ~/.claude as 'personal' if eligible ──────────────
    if [[ -f "$legacy_claude/.claude.json" || -f "$legacy_claude/settings.json" ]]; then
        if [[ ! -f "$CKIPPER_REGISTRY" ]] || \
           ! jq -e '.accounts | length > 0' "$CKIPPER_REGISTRY" >/dev/null 2>&1; then

            # Show the user what we're about to do.
            cat <<EOF

Detected existing $legacy_claude with login credentials.

This migration will:
  1. Rename $legacy_claude → $HOME/.claude-personal (NOT a symlink — bare 'claude' will no longer use this account; use 'claude-personal' instead).
  2. Register 'personal' in $CKIPPER_REGISTRY.
  3. Probe macOS Keychain for the matching 'Claude Code-credentials' entry.

If anything fails, the rename is automatically reverted.

EOF
            read -r "?Proceed? [y/N] " ans
            if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
                echo "Aborted."
                return 1
            fi

            # ── Precondition 3: probe Keychain entry exists ──────
            local probed_service="Claude Code-credentials"
            if [[ "$OSTYPE" == darwin* ]]; then
                if ! security find-generic-password -s "$probed_service" -w >/dev/null 2>&1; then
                    echo "Warning: '$probed_service' not found in Keychain."
                    echo "Listing available Claude Keychain entries:"
                    _ckipper_keychain_snapshot || return 1
                    read -r "?Enter the Keychain service for the personal account (or empty to skip): " probed_service
                    if [[ -n "$probed_service" ]] && ! _ckipper_validate_keychain_service "$probed_service"; then
                        echo "Invalid Keychain service shape. Aborting."
                        return 1
                    fi
                fi
            else
                probed_service=""
            fi

            # ── Destructive operation under trap-rollback ────────
            _migrate_rollback() {
                if [[ -d "$HOME/.claude-personal" && ! -e "$legacy_claude" ]]; then
                    mv "$HOME/.claude-personal" "$legacy_claude" 2>/dev/null
                    echo "Migration failed — restored $legacy_claude from rollback." >&2
                fi
            }
            trap _migrate_rollback ERR

            mv "$legacy_claude" "$HOME/.claude-personal"
            _ckipper_finalize_registration "personal" "$HOME/.claude-personal" "$probed_service" "migrate"

            trap - ERR
            unset -f _migrate_rollback
        fi
    fi

    # ── 3. Best-effort cleanup of old Docker image ────────────────
    if command -v docker >/dev/null 2>&1; then
        docker rmi claude-dev 2>/dev/null && echo "Removed old claude-dev Docker image."
    fi

    cat <<EOF

Migration complete.

Next steps:
  1. Confirm your ~/.zshrc sources the new path:
       source ~/.ckipper/docker/w-function.zsh
     (install.sh updates this automatically; if you used a manual install, edit it yourself.)
  2. Optional: add to ~/.zshrc to enable per-account aliases:
       [[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh
  3. Restart your shell.
  4. Run:  ckipper add <work-account-name>   to add additional accounts.

To launch Claude with your personal account, use:  claude-personal
(Bare 'claude' no longer resolves to your migrated personal account — it will start a fresh login.)

EOF
}
```

**Step 2: Verify with a synthetic legacy host**

```bash
TEST_HOME=$(mktemp -d -t ckipper-migrate-XXXXXX)
trap "rm -rf '$TEST_HOME'" EXIT
mkdir -p "$TEST_HOME/.claude/docker"
mkdir -p "$TEST_HOME/.claude/hooks"
echo "function w() { :; }" > "$TEST_HOME/.claude/docker/w-function.zsh"
echo '{"oauthAccount":{"emailAddress":"test@example.com"}}' > "$TEST_HOME/.claude/.claude.json"
HOME="$TEST_HOME" CKIPPER_DIR="$TEST_HOME/.ckipper" OSTYPE=linux-gnu \
  zsh -c 'source ./ckipper.zsh; echo y | ckipper migrate; ckipper list'
```

Expected: tooling copied, `~/.claude` renamed to `~/.claude-personal` (no symlink), `personal` registered, list prints reminder about using `claude-personal`.

**Step 3: Verify failure-rollback path:**

```bash
TEST_HOME=$(mktemp -d -t ckipper-migrate-rollback-XXXXXX)
trap "rm -rf '$TEST_HOME'" EXIT
mkdir -p "$TEST_HOME/.claude"
echo '{"oauthAccount":{"emailAddress":"test@example.com"}}' > "$TEST_HOME/.claude/.claude.json"
chmod -w "$TEST_HOME"   # make registry write fail
HOME="$TEST_HOME" CKIPPER_DIR="$TEST_HOME/.ckipper" OSTYPE=linux-gnu \
  zsh -c 'source ./ckipper.zsh; echo y | ckipper migrate' || true
chmod +w "$TEST_HOME"
ls "$TEST_HOME/"
```

Expected: `~/.claude` is restored (rollback fired); `~/.claude-personal` does not exist.

**Step 4: Commit**

```bash
git add ckipper.zsh
git commit -m "Implement ckipper migrate: precondition checks, error-trap rollback, no symlink"
```

---

## Phase 6 — Documentation

### Task 19: README rewrite (with panel-feedback expansions)

**Files:** Modify `README.md`.

**Step 1:** Restructure with the multi-account section surfaced earlier. New top-level section order:

1. What Ckipper is — one paragraph including the headline that it's multi-account-capable. Include pronunciation note.
2. Quickstart (single account, fresh install).
3. **Multiple accounts** — second-most-prominent section.
4. Migration from `claude-docker-sandbox` — `ckipper migrate` with the "what it will do" preamble.
5. Troubleshooting (concurrent-use warning lives here, prominently).
6. Architecture overview (link to design doc).

**Step 2: "Multiple accounts" section:**

````markdown
## Multiple accounts (Ckipper's headline feature)

Run a personal Claude account in one terminal and a work account in another, fully isolated. Each gets its own credentials, MCP servers, plugins, projects, and session history.

### Add an account

```bash
ckipper add work
```

`ckipper` walks you through `/login` and registers the account. Repeat for every account you want.

### Use an account

Three ways:

```bash
claude-work                                  # auto-generated alias (preferred)
cca work                                     # one-off dispatcher (claude-config-as)
CLAUDE_CONFIG_DIR=~/.claude-work claude      # raw form
```

### Inside Docker

```bash
w myorg/app feature --account work --docker claude
```

If you're already in a terminal where `CLAUDE_CONFIG_DIR` is set (e.g., via `claude-work`), `w` picks up the account automatically — no flag needed.

### List, default, remove

```bash
ckipper list
ckipper default personal
ckipper remove old-account
```
````

**Step 3: Concurrent-use warning** — its own section with stronger phrasing:

````markdown
## ⚠️ Don't run the same account in two sessions

Two terminals running the **same** account simultaneously will hit a known OAuth refresh-token race ([upstream issue #24317](https://github.com/anthropics/claude-code/issues/24317)) — symptoms: frequent re-login prompts, lost sessions.

**Safe:** `claude-personal` in one terminal, `claude-work` in another. Different accounts, different refresh tokens, no race.
**Bad:** `claude-personal` in two terminals at once.

If you want concurrent runs of the *same* account, register it twice under two names (`personal-a`, `personal-b`) — though this means re-`/login` for each.
````

**Step 4: Migration section:**

````markdown
## Migrating from claude-docker-sandbox

If you've been running this project under its previous name with a single `~/.claude/docker/` install, run:

```bash
ckipper migrate
```

This will:
1. Refuse to run if any `claude` process is currently active (quit them first).
2. Copy `~/.claude/docker/` → `~/.ckipper/`.
3. Offer to register your existing `~/.claude` as the `personal` account. If you accept: rename `~/.claude` → `~/.claude-personal`, probe Keychain for the matching credential entry, and write the registry. **No symlink is created** — after migration, you launch Claude with `claude-personal` (bare `claude` will start a fresh login).
4. If anything fails, the rename automatically reverses (rollback trap).

Then add additional accounts:

```bash
ckipper add work
```
````

**Step 5: Verify**

```bash
grep -n "claude-docker-sandbox" README.md
```

Expected: empty (or only in historical/migration context).

**Step 6: Commit**

```bash
git add README.md
git commit -m "README: rewrite for Ckipper with multi-account walkthrough and warnings"
```

### Task 20: Update CLAUDE.md and test-prompt.md

**Files:** Modify `CLAUDE.md`, `test-prompt.md`.

**Step 1: CLAUDE.md updates:**
- Tool layout diagram showing `~/.ckipper/` (move from `~/.claude/docker/`).
- New "Multi-account" section under Architecture.
- New "Critical Safety Rules" entry: registry tampering protection and `keychain_service` shape validation.
- Development Workflow table updated with `ckipper.zsh` → install.sh.
- Settings-template seed-only stance documented.

**Step 2: test-prompt.md — add Section 12 "Multi-account isolation"** with concrete assertions:

````markdown
## 12. Multi-account isolation

Run these checks in two concurrent containers (Window A: `--account personal`, Window B: `--account <other>`).

### A. Each container has the right CLAUDE_CONFIG_DIR
```bash
# In window A
[ "$CLAUDE_CONFIG_DIR" = "$HOME/.claude-personal" ] && echo PASS || echo FAIL
# In window B
[ "$CLAUDE_CONFIG_DIR" = "$HOME/.claude-<other>" ] && echo PASS || echo FAIL
```

### B. The right .claude.json was copied
```bash
# In each window
expected_email=$(jq -r .oauthAccount.emailAddress "$CLAUDE_CONFIG_DIR/.claude-host.json")
actual_email=$(jq -r .oauthAccount.emailAddress "$CLAUDE_CONFIG_DIR/.claude.json")
[ "$expected_email" = "$actual_email" ] && echo PASS || echo FAIL
```

### C. Credentials symlinked to tmpfs (and tmpfs is writable, host-mount is not)
```bash
[ -L "$CLAUDE_CONFIG_DIR/.credentials.json" ] && echo PASS || echo FAIL
[ "$(readlink "$CLAUDE_CONFIG_DIR/.credentials.json")" = "/tmp/claude-creds/.credentials.json" ] && echo PASS || echo FAIL
```

### D. Other accounts are NOT mounted
```bash
# Window A should NOT see Window B's dir
[ ! -d "$HOME/.claude-<other>" ] && echo PASS || echo FAIL
```

### E. Project sessions don't bleed across accounts
After both sessions touch a project (e.g., create a file in `/workspace`), check from the host:
```bash
diff <(ls ~/.claude-personal/projects/ 2>/dev/null) <(ls ~/.claude-<other>/projects/ 2>/dev/null)
# Expected: empty (no shared session dirs)
```

### F. Registry tampering blocked
Inside the container, attempt:
```bash
echo modified > ~/.ckipper/accounts.json
# Expected: BLOCKED by bash-guardrails.sh hook
```
````

**Step 3: Commit**

```bash
git add CLAUDE.md test-prompt.md
git commit -m "Docs: CLAUDE.md and test-prompt.md updates with concrete Section 12 isolation tests"
```

---

## Phase 6.5 — Pre-deploy Docker smoke test

### Task 20.5: Build the renamed image and run a single Docker session against a fixture account

**Why:** Phase 7 is the first time anything runs in real Docker. A bug in Tasks 14-16 (e.g., a dropped mount that breaks `gh auth` or `uvx` pre-install) won't surface until the implementer's host. This task catches it earlier.

**Files:** None modified — this is a verification task only.

**Step 1:** From the repo root:

```bash
# Build the renamed image
docker build --build-arg "CACHEBUST=$(date +%s)" -t ckipper-dev docker/

# Set up a test account in a temp HOME
TEST_HOME=$(mktemp -d -t ckipper-smoke-XXXXXX)
mkdir -p "$TEST_HOME/.claude-test/projects"
cat > "$TEST_HOME/.claude-test/.claude.json" <<'EOF'
{"oauthAccount":{"emailAddress":"smoke@test","displayName":"Smoke Test"},"projects":{}}
EOF
mkdir -p "$TEST_HOME/.ckipper"
cat > "$TEST_HOME/.ckipper/accounts.json" <<EOF
{"version":1,"default":"test","accounts":{"test":{"config_dir":"$TEST_HOME/.claude-test","keychain_service":null,"registered_at":"smoke"}}}
EOF
```

**Step 2:** Run a `--docker bash` session against the test account and verify:

```bash
docker run --rm -it \
    -v "$TEST_HOME/.claude-test:$TEST_HOME/.claude-test:rw" \
    -v "$TEST_HOME/.claude-test/.claude.json:$TEST_HOME/.claude-test/.claude-host.json:ro" \
    -e "CLAUDE_CONFIG_DIR=$TEST_HOME/.claude-test" \
    --tmpfs /tmp/claude-creds:mode=700,uid=1000,gid=1000,size=1m \
    ckipper-dev bash -c '
        echo "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR"
        ls -la "$CLAUDE_CONFIG_DIR/"
        [ -f "$CLAUDE_CONFIG_DIR/.claude.json" ] && echo "PASS: .claude.json exists"
        [ -d "$CLAUDE_CONFIG_DIR/projects" ] && echo "PASS: projects dir exists"
        [ "$HOME" = "/home/claude" ] && echo "PASS: $HOME unchanged"
        [ -d "/home/claude/.local/bin" ] && echo "PASS: container HOME paths intact"
    '
```

Expected: all PASS lines printed. No "command not found", no "directory does not exist", no entrypoint exit-1. If anything fails, fix the responsible task (14, 15, or 16) before proceeding.

**Step 3:** Cleanup:

```bash
rm -rf "$TEST_HOME"
docker image prune -f
```

**Step 4:** No commit needed — this is verification.

---

## Phase 7 — Local deployment + end-to-end validation

> **For the executing agent:** STOP at the end of Phase 6.5. **Phase 7 is user-driven**, not autonomous. These tasks modify the user's actual `~/.claude` (renaming, registering Keychain entries, opening interactive `/login` flows, requiring two Ghostty windows). The agent cannot meaningfully drive an interactive `/login` or coordinate two terminal windows. Hand control back to the user with a summary of what's done and a pointer to Task 21.
>
> The user runs Phase 7 themselves, in their terminal, following these steps as a checklist. The agent may be re-engaged after Task 25 to help compose the PR body if requested.

### Task 21: Deploy to host

**Step 1:**

```bash
./install.sh
```

Expected output: migrates `~/.claude/docker/` → `~/.ckipper/`, updates `.zshrc` source line (with `~/.zshrc.bak` backup), prints the optional `aliases.zsh` source line for the user to add manually.

**Step 2:** Add the optional `aliases.zsh` source line to `~/.zshrc` if not already there:

```zsh
[[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh
```

**Step 3:** Restart the shell (`exec zsh`).

### Task 22: Migrate the existing personal account

**Step 1:** Quit any running Claude sessions (the migration will refuse if any are active).

**Step 2:**

```bash
ckipper migrate
```

Confirm the prompt to register `~/.claude` as `personal`. After completion:

```bash
ckipper list
```

Expected: `personal` shown with the implementer's email (whatever's in their `~/.claude/.claude.json`'s `oauthAccount.emailAddress`) and a `* default` marker.

**Step 3:** Smoke test:

```bash
claude-personal --version
```

Expected: prints version. To verify the right account is loaded:

```bash
claude-personal
# inside Claude:
/status
```

Expected: shows the implementer's personal account email.

### Task 23: Add a second account

**Step 1:** Pick a placeholder name for the second account (e.g., `work`, `<your-second-account>`). The repo never sees the implementer's specific account name — it stays in the implementer's local registry only.

```bash
ckipper add <your-second-account>
```

Follow prompts: `CLAUDE_CONFIG_DIR=~/.claude-<your-second-account> claude`, complete `/login`, return and press enter.

**Step 2:** Verify:

```bash
ckipper list
```

Expected: both `personal` and `<your-second-account>` listed with their respective emails. Two distinct Keychain entries detected.

### Task 24: Validate Docker integration with both accounts

**Step 1:** In two separate Ghostty windows, register a test project in `w`:

Window A:
```bash
w some/project test-personal --account personal --docker claude
```

Window B:
```bash
w some/project test-work --account <your-second-account> --docker claude
```

Use different worktree branch names (`test-personal`, `test-work`) so the two sessions don't compete for the same worktree.

**Step 2:** Inside each container, run the new `test-prompt.md` Section 12 checks (A through F). All must PASS.

**Step 3:** Run `claude /status` inside each session. Verify each shows the correct account email.

**Step 4:** End both sessions cleanly. Confirm:

```bash
ls -la ~/.claude/.credentials.json 2>/dev/null
```

Expected: file does not exist on the host (credentials lived in the container's tmpfs and are gone).

### Task 25: Open PR to develop

**Step 1:**

```bash
git push -u origin feature/ckipper-multi-account
```

**Step 2:**

```bash
gh pr create --base develop --title "Ckipper: multi-account Claude Code sandbox" --body "$(cat <<'EOF'
## Summary
- Renames `claude-docker-sandbox` → **Ckipper** (pronounced "skipper").
- Adds multi-account support via `CLAUDE_CONFIG_DIR=~/.claude-<name>/` and a registry at `~/.ckipper/accounts.json` (versioned, chmod 600, flock-protected).
- New `ckipper` CLI: `add`, `list`, `default`, `remove`, `sync-hooks`, `migrate` — each with `--help`.
- Auto-generates self-contained `aliases.zsh` with `cca <name>` dispatcher and per-account `claude-<name>` functions.
- `w` and Docker entrypoint thread an active account through every credential, mount, and config path. Entrypoint errors out (no silent fallback) if `CLAUDE_CONFIG_DIR` is unset.
- Hook regex extended to cover `~/.ckipper/` and per-account dirs (closes a credential cross-contamination vector flagged by panel review).
- Migration path with running-Claude precondition, error-trap rollback, and Keychain probe-before-trust.

Design: `docs/plans/2026-04-27-ckipper-multi-account-design.md`
Plan:   `docs/plans/2026-04-27-ckipper-multi-account-implementation.md`

## Test plan
- [ ] `ckipper list` / `add --adopt` / `add` / `default` / `remove` against temp-HOME fixtures.
- [ ] Keychain snapshot regression test passes against `tests/keychain-dump.sample`.
- [ ] `ckipper migrate` against synthetic legacy `~/.claude/docker/` layout.
- [ ] `ckipper migrate` rollback when registry write fails.
- [ ] Phase 6.5 Docker smoke test passes against test account.
- [ ] Live deploy on host — migration succeeded; `personal` adopted; second account added cleanly.
- [ ] Two concurrent Docker sessions, different accounts, all six Section 12 isolation assertions PASS.
- [ ] No host-side `~/.claude/.credentials.json` symlink remains after sessions end.
- [ ] `test-prompt.md` Section 10 hook-bypass tests still pass after Task 17 regex change.
- [ ] Registry tampering (`echo X > ~/.ckipper/accounts.json` from inside a container) is BLOCKED by hooks.
EOF
)"
```

(Test plan checkboxes are unchecked here — the implementer/reviewer ticks them as they verify.)

---

## Follow-ups (out of scope for this PR)

- `ckipper rename <old> <new>` — rename a registered account in place.
- `ckipper sync-settings` — re-apply `settings-template.json` to existing accounts when the template changes.
- Bash + non-zsh shell support for `cca`/`claude-<name>` (currently zsh-only).
- Auto-detect account from cwd or git remote (deliberately YAGNI).
- Single-tenant install path skipping the registry (registry-with-one-account is already trivial; not needed).
- **Hooks-by-reference** instead of per-account `cp -a` — point each account's `settings.json` at `~/.ckipper/hooks/<name>.sh` directly. Eliminates drift; needs hook protection extended for the shared path.
- **CI** — GitHub Action running `shellcheck` + `zsh -n` + the fixture tests on every PR. Not blocking this PR but should land soon after.
- **Shell completion** for `ckipper` and `cca` (paralleling existing `w` completion).
- **Statusline indicator** for active account so a user with three terminals knows which is which.
- **`aliases.zsh` integrity** — generated file is currently writable by the user; consider hash-verification or moving to `~/.ckipper/lib/aliases.zsh` with stricter perms.
- **Audit trail** — `ckipper list` warns when `oauthAccount.emailAddress` doesn't appear to match the registered name (catches accidental wrong-account registration).
- **Drop the `w` legacy single-account fallback in v2** once everyone has migrated. Currently no fallback exists — Task 14 errors out — but if we ever add one, target it for removal.
- **Multi-machine credential sync** — registered accounts and their Keychain mappings don't sync across hosts. Not a goal for v1.
