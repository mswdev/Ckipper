# Ckipper Multi-Account Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rename `claude-docker-sandbox` to **Ckipper** and add support for running N concurrent Claude Code accounts with full isolation across credentials, settings, MCP, plugins, hooks, projects, and Docker sessions.

**Architecture:** Each account is a `CLAUDE_CONFIG_DIR=~/.claude-<name>/` directory. A registry at `~/.ckipper/accounts.json` maps account names to dirs and macOS Keychain service names. The new `ckipper` CLI registers/lists/removes accounts and auto-generates `claude-<name>` shell aliases. The `w` script and Docker entrypoint become account-aware via an `--account` flag, falling back to `CLAUDE_CONFIG_DIR` env var, then a default. Sandbox tooling moves out of `~/.claude/docker/` to its own root `~/.ckipper/` so tooling and account state are decoupled.

**Tech Stack:** zsh (functions, completions), bash (entrypoint, hooks, install), `jq` for JSON, `security` (macOS Keychain), Docker, git worktrees.

**Reference:** `docs/plans/2026-04-27-ckipper-multi-account-design.md`

---

## Working Conventions

- **Branch:** `feature/ckipper-multi-account` (off `develop`).
- **Commits:** small and frequent — one per task. PR target: `develop`.
- **Verification per task:** at minimum, `shellcheck` on changed shell files, then a smoke test that sources the function and exercises it. Heavyweight end-to-end testing happens once at Phase 7.
- **Local deployment:** the user has a live install at `~/.claude/docker/` (old) → `~/.ckipper/` (new). Do not run `install.sh` on their host until Phase 7.
- **Naming:** generic placeholders only in repo (`<name>`, `personal`, `work`). Never hardcode `af` or other user-specific names.
- **Scope guard:** if a task tempts you to "also clean up X", stop. Add it to a follow-up list. The plan is the plan.

---

## Phase 1 — Rename to Ckipper (text-only, no behavior change)

### Task 1: Rename in CLAUDE.md

**Files:** Modify `CLAUDE.md`.

**Step 1: Replace project name in description**

Change the first paragraph from:
> Docker-based sandbox for running Claude Code with `--dangerously-skip-permissions` safely.

To:
> **Ckipper** (pronounced "skipper") — Docker-based sandbox for running Claude Code with `--dangerously-skip-permissions` safely.

**Step 2: Update the `Architecture` and `Development Workflow` sections to reference `~/.ckipper/` instead of `~/.claude/docker/` and `~/.claude/hooks/`.** Note this is documentation forward-looking; actual file moves happen in Phase 2.

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

**Step 1: Replace project name and tagline.** Replace all occurrences of "claude-docker-sandbox" with "Ckipper". Add the pronunciation note ("pronounced 'skipper'") to the heading.

**Step 2: Update install/source instructions** to reference `~/.ckipper/docker/w-function.zsh`. Leave a "migrating from previous versions" callout for existing users (filled in by Phase 5/6).

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

**Files:** Modify `w-function.zsh` (occurrences of `claude-dev` image tag).

**Step 1:** Rename the Docker image tag from `claude-dev` to `ckipper-dev` in `_w_build_image` (line 41), in the existence check (line 269), and in the parallel-container detection (line 417). The `ancestor=claude-dev` filter in `docker ps` must also become `ancestor=ckipper-dev`.

**Step 2:** Update CLAUDE.md's "Development Workflow" table: `claude-dev` → `ckipper-dev`.

**Step 3: Verify**

```bash
grep -n "claude-dev" w-function.zsh CLAUDE.md README.md
```

Expected: empty.

**Step 4: Commit**

```bash
git add w-function.zsh CLAUDE.md
git commit -m "Rename Docker image tag claude-dev -> ckipper-dev"
```

Note: the user's live deployment still has the `claude-dev` image cached. After Phase 7 deploy, they'll run `w --rebuild-image` to rebuild as `ckipper-dev`. The old image can be deleted manually with `docker rmi claude-dev`.

---

## Phase 2 — Move tooling location to `~/.ckipper/`

### Task 4: Add `--target-dir` support to `install.sh`

**Files:** Modify `install.sh` (read it first to understand current behavior).

**Step 1:** Read the existing `install.sh` end-to-end. Identify every absolute reference to `~/.claude/docker/` and `~/.claude/hooks/`.

**Step 2:** Introduce a single variable `CKIPPER_DIR="${CKIPPER_DIR:-$HOME/.ckipper}"` at the top, and replace `~/.claude/docker/` with `$CKIPPER_DIR/docker/` throughout. Hooks deploy to `$CKIPPER_DIR/hooks/` (canonical source); per-account hook copies happen via `ckipper sync-hooks` later.

**Step 3:** The settings.json merge step (which adds `settings-hooks.json` content to `~/.claude/settings.json`) is now per-account. For Phase 2, leave this merge pointing at `~/.claude/settings.json` for backward compat. Phase 3 makes it account-aware.

**Step 4: Verify**

```bash
shellcheck install.sh
bash -n install.sh   # syntax check only
```

Expected: no errors.

**Step 5: Commit**

```bash
git add install.sh
git commit -m "Deploy Ckipper tooling to ~/.ckipper/ instead of ~/.claude/docker/"
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

**Step 2:** Verify no other `~/.claude/docker` strings remain in `w-function.zsh`.

```bash
grep -n "claude/docker" w-function.zsh
```

Expected: empty.

**Step 3: Verify the function still parses**

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

**Step 1:** At the top of `install.sh`, after `CKIPPER_DIR` is defined, add a migration block:

```bash
# Migrate legacy ~/.claude/docker/ layout if present
LEGACY_DIR="$HOME/.claude/docker"
if [ -d "$LEGACY_DIR" ] && [ ! -d "$CKIPPER_DIR" ]; then
    echo "Migrating ~/.claude/docker/ -> $CKIPPER_DIR/"
    mkdir -p "$CKIPPER_DIR"
    # Preserve user's w-config.zsh customizations
    cp -a "$LEGACY_DIR/." "$CKIPPER_DIR/"
    echo "Migrated. The legacy directory is left intact at $LEGACY_DIR for now."
    echo "Remove it manually once you've verified the new location works."
fi
```

**Step 2:** Add a `.zshrc` source-line update step. After deploying files, check if `.zshrc` sources the legacy path and prompt to update:

```bash
if grep -q "source.*\.claude/docker/w-function.zsh" "$HOME/.zshrc" 2>/dev/null; then
    echo ""
    echo "Update your ~/.zshrc to source from the new location:"
    echo "  source ~/.ckipper/docker/w-function.zsh"
    echo "(replacing the existing source ~/.claude/docker/w-function.zsh line)"
fi
```

We **do not** auto-edit `.zshrc` — touching the user's shell config silently is too invasive. Print the instruction and let them edit it.

**Step 3: Verify**

```bash
shellcheck install.sh
```

Expected: no errors (warnings about quoting are OK if pre-existing).

**Step 4: Commit**

```bash
git add install.sh
git commit -m "install.sh: migrate legacy ~/.claude/docker/ to ~/.ckipper/"
```

---

## Phase 3 — Account registry + `ckipper` CLI

### Task 7: Create the `ckipper` CLI scaffold

**Files:** Create `ckipper.zsh`.

**Step 1:** Create `ckipper.zsh` at the repo root with a top-level dispatcher:

```zsh
# Ckipper — multi-account Claude Code manager
# Sourced by w-function.zsh

CKIPPER_DIR="${CKIPPER_DIR:-$HOME/.ckipper}"
CKIPPER_REGISTRY="$CKIPPER_DIR/accounts.json"

ckipper() {
    local cmd="$1"
    shift 2>/dev/null
    case "$cmd" in
        add)        _ckipper_add "$@" ;;
        list)       _ckipper_list "$@" ;;
        default)    _ckipper_default "$@" ;;
        remove)     _ckipper_remove "$@" ;;
        sync-hooks) _ckipper_sync_hooks "$@" ;;
        migrate)    _ckipper_migrate "$@" ;;
        ""|help|-h|--help) _ckipper_help ;;
        *) echo "Unknown command: $cmd"; _ckipper_help; return 1 ;;
    esac
}

_ckipper_help() {
    cat <<'EOF'
ckipper — multi-account Claude Code manager

Usage:
  ckipper add <name>          Register a new account (interactive /login)
  ckipper add <name> --adopt  Register an existing populated config dir
  ckipper list                Show registered accounts
  ckipper default <name>      Set the default account
  ckipper remove <name>       Unregister (does not delete the dir)
  ckipper sync-hooks          Copy hooks into all registered accounts
  ckipper migrate             One-time migration from legacy layout
EOF
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
# Source ckipper subcommand dispatcher
[[ -f "${CKIPPER_DIR:-$HOME/.ckipper}/docker/ckipper.zsh" ]] && \
    source "${CKIPPER_DIR:-$HOME/.ckipper}/docker/ckipper.zsh"
```

**Step 3:** Update `install.sh` to deploy `ckipper.zsh` to `$CKIPPER_DIR/docker/ckipper.zsh`.

**Step 4: Verify**

```bash
zsh -c 'source ./w-function.zsh; source ./ckipper.zsh; ckipper'
```

Expected: prints help text. `ckipper add foo` prints the "not yet implemented" stub.

**Step 5: Commit**

```bash
git add ckipper.zsh w-function.zsh install.sh
git commit -m "Add ckipper CLI scaffold with help and subcommand stubs"
```

### Task 8: Implement `ckipper list`

**Files:** Modify `ckipper.zsh`.

**Step 1:** Replace `_ckipper_list` stub with:

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
}
```

**Step 2: Verify with a fixture registry**

```bash
mkdir -p /tmp/ckipper-test/.ckipper
cat > /tmp/ckipper-test/.ckipper/accounts.json <<'EOF'
{
  "default": "personal",
  "accounts": {
    "personal": {"config_dir": "/tmp/ckipper-test/.claude-personal", "keychain_service": "Claude Code-credentials"},
    "work": {"config_dir": "/tmp/ckipper-test/.claude-work", "keychain_service": "Claude Code-credentials-abc12345"}
  }
}
EOF
zsh -c 'CKIPPER_DIR=/tmp/ckipper-test/.ckipper source ./ckipper.zsh; CKIPPER_REGISTRY=/tmp/ckipper-test/.ckipper/accounts.json ckipper list'
```

Expected: prints both accounts, marks `personal` as default, shows `(missing)` for both dirs.

**Step 3: Commit**

```bash
git add ckipper.zsh
git commit -m "Implement ckipper list"
```

### Task 9: Implement `ckipper add <name>` (interactive login flow)

**Files:** Modify `ckipper.zsh`.

**Step 1:** Add a helper that snapshots Keychain entries:

```zsh
_ckipper_keychain_snapshot() {
    # macOS only. Returns service names of all "Claude Code-credentials*" entries.
    if [[ "$OSTYPE" != darwin* ]]; then
        return 0
    fi
    security dump-keychain 2>/dev/null | \
        awk -F'"' '/"svce"<blob>="Claude Code-credentials/ {print $4}' | \
        sort -u
}
```

**Step 2:** Implement `_ckipper_add`:

```zsh
_ckipper_add() {
    local name="$1" adopt=0
    [[ "$2" == "--adopt" ]] && adopt=1
    if [[ -z "$name" ]]; then
        echo "Usage: ckipper add <name> [--adopt]"
        return 1
    fi
    if [[ ! "$name" =~ ^[a-z0-9_-]+$ ]]; then
        echo "Account name must be lowercase alphanumeric, underscore, or hyphen."
        return 1
    fi

    local dir="$HOME/.claude-$name"
    mkdir -p "$CKIPPER_DIR"

    # Initialize registry if missing
    if [[ ! -f "$CKIPPER_REGISTRY" ]]; then
        echo '{"default":null,"accounts":{}}' > "$CKIPPER_REGISTRY"
    fi

    # Refuse if already registered
    if jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null; then
        echo "Account '$name' is already registered."
        return 1
    fi

    if [[ $adopt -eq 1 ]]; then
        if [[ ! -d "$dir" ]]; then
            echo "Cannot adopt: $dir does not exist."
            return 1
        fi
        _ckipper_finalize_registration "$name" "$dir" "" "adopt"
        return $?
    fi

    # Fresh registration: create dir, snapshot keychain, prompt /login
    if [[ -d "$dir" ]]; then
        echo "Directory $dir already exists. Use --adopt to register it."
        return 1
    fi
    mkdir -p "$dir/hooks"
    if [[ -f "$CKIPPER_DIR/settings-template.json" ]]; then
        cp "$CKIPPER_DIR/settings-template.json" "$dir/settings.json"
    fi

    local before_snapshot
    before_snapshot=$(_ckipper_keychain_snapshot)

    cat <<EOF

A new account directory was created at $dir.

In this same shell, run:

    CLAUDE_CONFIG_DIR=$dir claude

Complete the /login flow with the account you want to register as '$name'.
When done and you see the Claude Code prompt, exit Claude (Ctrl-D) and
press enter here to finish registration.

EOF
    read -r "?Press enter when /login is complete: "

    local after_snapshot
    after_snapshot=$(_ckipper_keychain_snapshot)
    local new_service
    new_service=$(comm -13 <(echo "$before_snapshot") <(echo "$after_snapshot") | head -1)

    if [[ -z "$new_service" ]]; then
        echo "Warning: no new Keychain entry detected."
        echo "If you authenticated with an API key, credentials are on disk and that is fine."
        new_service=""
    else
        echo "Detected new Keychain entry: $new_service"
    fi

    _ckipper_finalize_registration "$name" "$dir" "$new_service" "fresh"
}

_ckipper_finalize_registration() {
    local name="$1" dir="$2" service="$3" mode="$4"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local tmp
    tmp=$(mktemp)
    jq --arg n "$name" --arg d "$dir" --arg s "$service" --arg t "$now" \
        '.accounts[$n] = {config_dir: $d, keychain_service: (if $s == "" then null else $s end), registered_at: $t}
         | (if .default == null then .default = $n else . end)' \
        "$CKIPPER_REGISTRY" > "$tmp" && mv "$tmp" "$CKIPPER_REGISTRY"

    _ckipper_regenerate_aliases
    _ckipper_sync_hooks_for "$name"

    echo "Registered '$name' (mode: $mode)."
    echo "Use it via: claude-$name   or   cca $name"
}
```

**Step 3:** Add `_ckipper_regenerate_aliases` and `_ckipper_sync_hooks_for` as stubs (filled in next tasks):

```zsh
_ckipper_regenerate_aliases() { :; }   # implemented in Task 12
_ckipper_sync_hooks_for() { :; }       # implemented in Task 13
```

**Step 4: Verify (dry-run, no real account)**

```bash
zsh -c 'source ./w-function.zsh; source ./ckipper.zsh; ckipper add'
```

Expected: prints usage error.

```bash
zsh -c 'source ./w-function.zsh; source ./ckipper.zsh; ckipper add Bad-Name'
```

Expected: prints validation error (uppercase rejected).

**Step 5: Commit**

```bash
git add ckipper.zsh
git commit -m "Implement ckipper add with Keychain snapshot/diff"
```

### Task 10: Implement `--adopt` mode end-to-end

Already covered structurally in Task 9. Verify by:

```bash
mkdir -p /tmp/ckipper-test-adopt/.claude-personal
echo '{"oauthAccount":{"emailAddress":"test@example.com"}}' > /tmp/ckipper-test-adopt/.claude-personal/.claude.json
HOME=/tmp/ckipper-test-adopt CKIPPER_DIR=/tmp/ckipper-test-adopt/.ckipper \
  zsh -c 'source ./ckipper.zsh; ckipper add personal --adopt'
HOME=/tmp/ckipper-test-adopt CKIPPER_DIR=/tmp/ckipper-test-adopt/.ckipper \
  zsh -c 'source ./ckipper.zsh; ckipper list'
```

Expected: registration succeeds, `ckipper list` shows `personal` with `test@example.com`.

**Commit only if changes were needed.**

### Task 11: Implement `ckipper default` and `ckipper remove`

**Files:** Modify `ckipper.zsh`.

**Step 1:** Implement:

```zsh
_ckipper_default() {
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: ckipper default <name>"; return 1; }
    if ! jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null; then
        echo "Account '$name' is not registered."
        return 1
    fi
    local tmp; tmp=$(mktemp)
    jq --arg n "$name" '.default = $n' "$CKIPPER_REGISTRY" > "$tmp" && mv "$tmp" "$CKIPPER_REGISTRY"
    echo "Default account is now '$name'."
}

_ckipper_remove() {
    local name="$1"
    [[ -z "$name" ]] && { echo "Usage: ckipper remove <name>"; return 1; }
    if ! jq -e --arg n "$name" '.accounts[$n]' "$CKIPPER_REGISTRY" >/dev/null; then
        echo "Account '$name' is not registered."
        return 1
    fi
    local dir; dir=$(jq -r --arg n "$name" '.accounts[$n].config_dir' "$CKIPPER_REGISTRY")
    local service; service=$(jq -r --arg n "$name" '.accounts[$n].keychain_service // ""' "$CKIPPER_REGISTRY")
    local tmp; tmp=$(mktemp)
    jq --arg n "$name" 'del(.accounts[$n]) | (if .default == $n then .default = null else . end)' \
        "$CKIPPER_REGISTRY" > "$tmp" && mv "$tmp" "$CKIPPER_REGISTRY"
    _ckipper_regenerate_aliases
    echo "Unregistered '$name'."
    echo ""
    echo "The directory and Keychain entry were not deleted. To remove them manually:"
    echo "  rm -rf $dir"
    [[ -n "$service" ]] && echo "  security delete-generic-password -s '$service'"
}
```

**Step 2: Verify**

```bash
HOME=/tmp/ckipper-test-adopt CKIPPER_DIR=/tmp/ckipper-test-adopt/.ckipper \
  zsh -c 'source ./ckipper.zsh; ckipper default personal; ckipper remove personal; ckipper list'
```

Expected: default set, then unregistered, then list shows no accounts.

**Step 3: Commit**

```bash
git add ckipper.zsh
git commit -m "Implement ckipper default and ckipper remove"
```

### Task 12: Implement aliases.zsh auto-generation

**Files:** Modify `ckipper.zsh`.

**Step 1:** Replace the `_ckipper_regenerate_aliases` stub with:

```zsh
_ckipper_regenerate_aliases() {
    local out="$CKIPPER_DIR/aliases.zsh"
    {
        echo "# Auto-generated by ckipper. Do not edit by hand."
        echo "# Regenerated whenever an account is added or removed."
        echo ""
        echo "cca() {"
        echo "    local name=\$1; shift"
        echo "    local dir"
        echo "    dir=\$(jq -r --arg n \"\$name\" '.accounts[\$n].config_dir // empty' \"\$CKIPPER_REGISTRY\")"
        echo "    if [[ -z \"\$dir\" ]]; then echo \"Unknown account: \$name\"; return 1; fi"
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
}
```

**Step 2:** Update `install.sh` to add a one-time `.zshrc` line suggesting:

```zsh
[[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh
```

(Suggestion only; do not auto-edit `.zshrc`.)

**Step 3: Verify**

```bash
HOME=/tmp/ckipper-test-adopt CKIPPER_DIR=/tmp/ckipper-test-adopt/.ckipper \
  zsh -c 'source ./ckipper.zsh; ckipper add personal --adopt; cat /tmp/ckipper-test-adopt/.ckipper/aliases.zsh'
```

Expected: file contains `cca` function and `claude-personal` function.

**Step 4: Commit**

```bash
git add ckipper.zsh install.sh
git commit -m "Auto-generate per-account aliases and cca dispatcher"
```

### Task 13: Implement `ckipper sync-hooks`

**Files:** Modify `ckipper.zsh`.

**Step 1:** Implement two functions: one that syncs all accounts, one for a single account (used by `add`):

```zsh
_ckipper_sync_hooks_for() {
    local name="$1"
    local dir; dir=$(jq -r --arg n "$name" '.accounts[$n].config_dir' "$CKIPPER_REGISTRY")
    [[ -z "$dir" || "$dir" == "null" ]] && return 1
    mkdir -p "$dir/hooks"
    cp -a "$CKIPPER_DIR/hooks/." "$dir/hooks/" 2>/dev/null || true

    # Rewrite settings.json to use absolute hook paths under this account dir.
    if [[ -f "$dir/settings.json" ]] && command -v jq &>/dev/null; then
        local tmp; tmp=$(mktemp)
        jq --arg d "$dir" '
            (.hooks // {}) as $h |
            .hooks = ($h | walk(if type == "string" and test("\\.claude(-[a-z0-9_-]+)?/hooks/")
                                 then sub("/.claude(-[a-z0-9_-]+)?/hooks/"; "\($d)/hooks/")
                                 else . end))
        ' "$dir/settings.json" > "$tmp" && mv "$tmp" "$dir/settings.json"
    fi
}

_ckipper_sync_hooks() {
    if [[ ! -f "$CKIPPER_REGISTRY" ]]; then
        echo "No accounts registered."
        return 0
    fi
    local names; names=$(jq -r '.accounts | keys[]' "$CKIPPER_REGISTRY")
    while IFS= read -r name; do
        echo "Syncing hooks → $name"
        _ckipper_sync_hooks_for "$name"
    done <<< "$names"
}
```

**Step 2: Verify**

```bash
mkdir -p /tmp/ckipper-test-adopt/.ckipper/hooks
echo "echo test" > /tmp/ckipper-test-adopt/.ckipper/hooks/sample.sh
HOME=/tmp/ckipper-test-adopt CKIPPER_DIR=/tmp/ckipper-test-adopt/.ckipper \
  zsh -c 'source ./ckipper.zsh; ckipper sync-hooks; ls /tmp/ckipper-test-adopt/.claude-personal/hooks/'
```

Expected: `sample.sh` exists in the per-account hooks dir.

**Step 3: Commit**

```bash
git add ckipper.zsh
git commit -m "Implement ckipper sync-hooks for per-account hook deployment"
```

---

## Phase 4 — Account-aware `w` and entrypoint

### Task 14: `w` resolves the active account

**Files:** Modify `w-function.zsh`.

**Step 1:** Add a helper at the top of the `w()` function (before flag parsing):

```zsh
_w_resolve_account() {
    local cli_account="$1"
    # 1. CLI flag wins
    if [[ -n "$cli_account" ]]; then
        echo "$cli_account"
        return 0
    fi
    # 2. CLAUDE_CONFIG_DIR env var matching a registered config_dir
    if [[ -n "$CLAUDE_CONFIG_DIR" && -f "$CKIPPER_REGISTRY" ]]; then
        local matched
        matched=$(jq -r --arg d "$CLAUDE_CONFIG_DIR" \
            '.accounts | to_entries[] | select(.value.config_dir == $d) | .key' \
            "$CKIPPER_REGISTRY" | head -1)
        if [[ -n "$matched" ]]; then
            echo "$matched"
            return 0
        fi
    fi
    # 3. Default from registry
    if [[ -f "$CKIPPER_REGISTRY" ]]; then
        local default
        default=$(jq -r '.default // ""' "$CKIPPER_REGISTRY")
        if [[ -n "$default" ]]; then
            echo "$default"
            return 0
        fi
    fi
    # 4. No accounts: return empty (legacy mode)
    return 0
}
```

**Step 2:** Add `--account <name>` to the flag parser:

```zsh
local cli_account=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --docker)  docker_mode=1; shift ;;
        --firewall) firewall_mode=1; shift ;;
        --account) cli_account="$2"; shift 2 ;;
        *) command+=("$1"); shift ;;
    esac
done
```

**Step 3:** After the existing arg validation, resolve and validate the account:

```zsh
local active_account
active_account=$(_w_resolve_account "$cli_account")
local active_config_dir=""
local active_keychain_service=""
if [[ -n "$active_account" && -f "$CKIPPER_REGISTRY" ]]; then
    active_config_dir=$(jq -r --arg n "$active_account" '.accounts[$n].config_dir // empty' "$CKIPPER_REGISTRY")
    active_keychain_service=$(jq -r --arg n "$active_account" '.accounts[$n].keychain_service // empty' "$CKIPPER_REGISTRY")
    if [[ -z "$active_config_dir" ]]; then
        echo "Error: account '$active_account' is not registered. Run: ckipper list"
        return 1
    fi
fi
# Fallback: legacy single-account ~/.claude
[[ -z "$active_config_dir" ]] && active_config_dir="$HOME/.claude"
[[ -z "$active_keychain_service" ]] && active_keychain_service="Claude Code-credentials"
```

**Step 4: Verify**

```bash
zsh -n w-function.zsh
```

Expected: parse OK.

```bash
zsh -c 'source ./w-function.zsh; CKIPPER_REGISTRY=/tmp/ckipper-test/.ckipper/accounts.json _w_resolve_account ""'
```

Expected: prints `personal` (the default from earlier fixture).

**Step 5: Commit**

```bash
git add w-function.zsh
git commit -m "w: resolve active account from --account flag, env, or default"
```

### Task 15: `w` Docker args use per-account paths and Keychain service

**Files:** Modify `w-function.zsh`.

**Step 1:** In the Docker block, replace the hardcoded credential extraction:

```zsh
# old
claude_creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || true
# new
claude_creds=$(security find-generic-password -s "$active_keychain_service" -w 2>/dev/null) || true
```

**Step 2:** Replace the `~/.claude` mount block:

```zsh
# old
-v "$HOME/.claude:/home/claude/.claude:rw"
-v "$HOME/.claude.json:/home/claude/.claude-host.json:ro"
-v "$HOME/.claude:$HOME/.claude:rw"
# new
-v "$active_config_dir:$active_config_dir:rw"
-v "$active_config_dir/.claude.json:$active_config_dir/.claude-host.json:ro"
-e "CLAUDE_CONFIG_DIR=$active_config_dir"
```

(The dual mount under `/home/claude/.claude` is dropped — entrypoint now reads from `$CLAUDE_CONFIG_DIR` directly. The `:ro` mount of the host `.claude.json` becomes the per-account file.)

**Step 3:** Update the gh-token extraction to use the per-account `.claude.json`:

```zsh
gh_token=$(jq -r '.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN // empty' "$active_config_dir/.claude.json" 2>/dev/null) || true
```

**Step 4:** Update the worktree project-settings sync (the python heredoc near line 232) to use `$active_config_dir/.claude.json` instead of `~/.claude.json`. The cleanup in `--rm` (line 111) similarly uses the active account's `.claude.json`. For `--rm`, the simplest path is to clean the worktree entry from **all** accounts that have it:

```python
# Sketch — in --rm cleanup:
import json, os, glob
wt_path = os.environ['WT_PATH']
for cfg in glob.glob(os.path.expanduser('~/.claude-*/.claude.json')) + [os.path.expanduser('~/.claude/.claude.json')]:
    if not os.path.exists(cfg): continue
    with open(cfg) as f: d = json.load(f)
    if wt_path in d.get('projects', {}):
        del d['projects'][wt_path]
        with open(cfg, 'w') as f: json.dump(d, f)
        print(f'Removed worktree entry from {cfg}')
```

**Step 5:** Drop the post-session credential symlink cleanup at line 416–420 if `active_config_dir != $HOME/.claude` — the symlink lives inside the container's tmpfs now and no longer pollutes `~/.claude/.credentials.json`. Keep the legacy cleanup for the fallback path where `active_config_dir == $HOME/.claude`.

**Step 6: Verify**

```bash
zsh -n w-function.zsh
shellcheck -s bash w-function.zsh   # may have warnings, ignore non-errors
```

**Step 7: Commit**

```bash
git add w-function.zsh
git commit -m "w: thread active account through Docker args and project sync"
```

### Task 16: Entrypoint uses `$CLAUDE_CONFIG_DIR`

**Files:** Modify `docker/entrypoint.sh`.

**Step 1:** At the top, after `set -e`, add:

```bash
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
```

This makes the script account-aware in container while preserving legacy behavior when no account is set.

**Step 2:** Replace `~/.claude.json` and `~/.claude-host.json` references with `$CLAUDE_CONFIG_DIR/.claude.json` and `$CLAUDE_CONFIG_DIR/.claude-host.json`. The "copy from staging" step becomes:

```bash
if [ -f "$CLAUDE_CONFIG_DIR/.claude-host.json" ]; then
    cp "$CLAUDE_CONFIG_DIR/.claude-host.json" "$CLAUDE_CONFIG_DIR/.claude.json"
    # ... existing jq edits ...
fi
```

**Step 3:** Update the credential symlink target:

```bash
ln -sf /tmp/claude-creds/.credentials.json "$CLAUDE_CONFIG_DIR/.credentials.json"
```

**Step 4:** Update git identity, MCP pre-install, and uvx jq queries to use `$CLAUDE_CONFIG_DIR/.claude.json`.

**Step 5: Verify**

```bash
shellcheck docker/entrypoint.sh
bash -n docker/entrypoint.sh
```

Expected: no errors.

**Step 6: Commit**

```bash
git add docker/entrypoint.sh
git commit -m "entrypoint: read all paths from CLAUDE_CONFIG_DIR"
```

### Task 17: Hooks adapt to per-account paths

**Files:** Modify `hooks/protect-claude-config.sh`, `hooks/bash-guardrails.sh`.

**Step 1:** Read both hooks. Identify hardcoded `~/.claude/` references that should generalize.

**Step 2:** In `protect-claude-config.sh`: replace the protected-path list to include both legacy (`~/.claude/`) and per-account (`~/.claude-*/`) directories. The hook should match any path under `$HOME/.claude` or `$HOME/.claude-<name>` as well as `$HOME/.ckipper`.

**Step 3:** In `bash-guardrails.sh`: same treatment for any patterns that reference `~/.claude` paths.

**Step 4: Verify**

```bash
shellcheck hooks/*.sh
```

Expected: no new errors.

**Step 5: Commit**

```bash
git add hooks/protect-claude-config.sh hooks/bash-guardrails.sh
git commit -m "hooks: protect per-account dirs and ~/.ckipper"
```

---

## Phase 5 — Migration command

### Task 18: Implement `ckipper migrate`

**Files:** Modify `ckipper.zsh`.

**Step 1:** Replace the `_ckipper_migrate` stub:

```zsh
_ckipper_migrate() {
    local legacy_docker="$HOME/.claude/docker"
    local legacy_claude="$HOME/.claude"

    # 1. Move ~/.claude/docker → ~/.ckipper/docker if not already done
    if [[ -d "$legacy_docker" && ! -d "$CKIPPER_DIR/docker" ]]; then
        mkdir -p "$CKIPPER_DIR"
        cp -a "$legacy_docker/." "$CKIPPER_DIR/docker/"
        echo "Copied $legacy_docker → $CKIPPER_DIR/docker (legacy left intact)"
    fi

    # 2. Adopt ~/.claude as 'personal' if not already registered
    if [[ -f "$legacy_claude/.claude.json" || -f "$legacy_claude/settings.json" ]]; then
        if [[ ! -f "$CKIPPER_REGISTRY" ]] || \
           ! jq -e '.accounts | length > 0' "$CKIPPER_REGISTRY" >/dev/null; then
            echo ""
            echo "Detected existing ~/.claude with login. Register it as 'personal'?"
            read -r "?[Y/n] " ans
            if [[ "$ans" != "n" && "$ans" != "N" ]]; then
                if [[ -L "$legacy_claude" ]]; then
                    echo "~/.claude is already a symlink — skipping rename."
                else
                    mv "$legacy_claude" "$HOME/.claude-personal"
                    ln -s "$HOME/.claude-personal" "$legacy_claude"
                    echo "Renamed ~/.claude → ~/.claude-personal and symlinked back."
                fi
                # Adopt with the no-suffix Keychain entry (default for ~/.claude)
                _ckipper_finalize_registration "personal" "$HOME/.claude-personal" "Claude Code-credentials" "migrate"
            fi
        fi
    fi

    echo ""
    echo "Migration complete. Next steps:"
    echo "  1. Update ~/.zshrc to source ~/.ckipper/docker/w-function.zsh"
    echo "     (replace any source ~/.claude/docker/w-function.zsh)"
    echo "  2. Add: [[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh"
    echo "  3. Restart your shell."
    echo "  4. Run: ckipper add <name>   to add additional accounts."
}
```

**Step 2: Verify with a synthetic legacy host**

```bash
mkdir -p /tmp/ckipper-migrate/.claude/docker
mkdir -p /tmp/ckipper-migrate/.claude/hooks
echo "function w() { :; }" > /tmp/ckipper-migrate/.claude/docker/w-function.zsh
echo '{"oauthAccount":{"emailAddress":"test@example.com"}}' > /tmp/ckipper-migrate/.claude/.claude.json
HOME=/tmp/ckipper-migrate CKIPPER_DIR=/tmp/ckipper-migrate/.ckipper \
  zsh -c 'source ./ckipper.zsh; echo y | ckipper migrate; ckipper list'
```

Expected: tooling copied, `~/.claude` renamed and symlinked, `personal` registered.

**Step 3: Commit**

```bash
git add ckipper.zsh
git commit -m "Implement ckipper migrate for legacy layout"
```

---

## Phase 6 — Documentation

### Task 19: README rewrite

**Files:** Modify `README.md`.

**Step 1:** Restructure into sections:

1. What Ckipper is (one paragraph + the paddock-style metaphor for safety + autonomy).
2. Quickstart (single-account: `./install.sh`, source line, `w project branch --docker claude`).
3. **Multiple accounts** — new section.
4. Migration from `claude-docker-sandbox` — `ckipper migrate`.
5. Architecture overview (link to `docs/plans/2026-04-27-ckipper-multi-account-design.md`).

**Step 2:** Multiple-accounts section template:

````markdown
## Multiple accounts

Run a personal Claude account in one terminal and a work account in another, fully isolated. Each gets its own credentials, MCP servers, plugins, projects, and session history.

### Add an account

```bash
ckipper add work
```

Follow the prompts to `/login` with the account in question. Repeat for as many accounts as you want.

### Use an account

Three ways:

```bash
claude-work              # auto-generated alias (preferred)
cca work                 # one-off dispatcher
CLAUDE_CONFIG_DIR=~/.claude-work claude    # raw form
```

### Inside Docker

```bash
w myorg/app feature --account work --docker claude
```

If you're already in a terminal where `CLAUDE_CONFIG_DIR` is set (e.g., via `claude-work`), `w` picks up the account automatically — no flag needed.

### Concurrent-use warning

Two terminals running the **same** account simultaneously can hit a known OAuth refresh-token race ([upstream issue #24317](https://github.com/anthropics/claude-code/issues/24317)) and require frequent re-login. Two terminals running **different** accounts is fine.

### List, default, remove

```bash
ckipper list
ckipper default personal
ckipper remove old-account
```
````

**Step 3:** Verify

```bash
grep -n "claude-docker-sandbox" README.md
```

Expected: empty (or only in historical/migration context).

**Step 4: Commit**

```bash
git add README.md
git commit -m "README: rewrite for Ckipper with multi-account walkthrough"
```

### Task 20: Update CLAUDE.md and test-prompt.md

**Files:** Modify `CLAUDE.md`, `test-prompt.md`.

**Step 1:** CLAUDE.md gets:
- Updated tool layout diagram showing `~/.ckipper/`.
- New "Multi-account" section under Architecture.
- Updated Development Workflow table including `ckipper.zsh` → install.sh.

**Step 2:** test-prompt.md gets a new section "12. Multi-account isolation" with checks:
- Run `ckipper list` inside the container — should show the active account only.
- Verify `$CLAUDE_CONFIG_DIR` is set inside the container.
- Verify `~/.claude.json` is a copy of `$CLAUDE_CONFIG_DIR/.claude-host.json`.
- Confirm credentials are at `$CLAUDE_CONFIG_DIR/.credentials.json` (symlinked to tmpfs).
- Confirm no other account dir is mounted (e.g., `ls /home/claude/.claude-other` → not found).

**Step 3:** Commit

```bash
git add CLAUDE.md test-prompt.md
git commit -m "Docs: update CLAUDE.md and test-prompt.md for Ckipper"
```

---

## Phase 7 — Local deployment + end-to-end validation

These tasks run on the user's actual host. Do not run earlier.

### Task 21: Deploy to user's host

**Step 1:** From the repo root:

```bash
./install.sh
```

Expected output: migrates `~/.claude/docker/` → `~/.ckipper/`, prints `.zshrc` update instructions.

**Step 2:** Update `~/.zshrc` per printed instructions:

```zsh
source ~/.ckipper/docker/w-function.zsh
[[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh
```

**Step 3:** Restart the shell (or `source ~/.zshrc`).

### Task 22: Migrate existing personal account

**Step 1:** Run:

```bash
ckipper migrate
```

Confirm the prompt to register `~/.claude` as `personal`. After completion:

```bash
ckipper list
```

Expected: `personal` shown with `matt@msw.dev` and `* default` marker.

**Step 2:** Smoke test:

```bash
claude-personal --version
```

Expected: prints version (and uses the personal account — verify by `claude-personal` then `/status`).

### Task 23: Add the user's second account

**Step 1:**

```bash
ckipper add af
```

Follow prompts: open `CLAUDE_CONFIG_DIR=~/.claude-af claude`, complete `/login` with the Animal Farm account, return and press enter.

**Step 2:** Verify:

```bash
ckipper list
```

Expected: both `personal` and `af` listed with their respective emails. New Keychain entry detected.

### Task 24: Validate Docker integration with both accounts

**Step 1:** In two separate Ghostty windows:

Window A:
```bash
w some/project main --account personal --docker claude
```

Window B:
```bash
w some/project main --account af --docker claude
```

(Use different worktree branches or projects so they don't collide on the worktree path.)

**Step 2:** Inside each container, run the new "Multi-account isolation" section of `test-prompt.md`. Verify:
- Each container has its own `CLAUDE_CONFIG_DIR`.
- `claude /status` in each shows the right account email.
- Project sessions don't appear in the other account's `~/.claude-<other>/projects/`.

**Step 3:** End both sessions cleanly. Confirm no `~/.claude/.credentials.json` symlink remains on the host.

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
- Adds multi-account support via `CLAUDE_CONFIG_DIR=~/.claude-<name>/` and a registry at `~/.ckipper/accounts.json`.
- New `ckipper` CLI: `add`, `list`, `default`, `remove`, `sync-hooks`, `migrate`.
- Auto-generates `claude-<name>` aliases and a `cca <name>` dispatcher.
- `w` and Docker entrypoint thread an active account through every credential, mount, and config path.
- Migration path for existing single-account installs.

Design: `docs/plans/2026-04-27-ckipper-multi-account-design.md`
Plan:   `docs/plans/2026-04-27-ckipper-multi-account-implementation.md`

## Test plan
- [x] `ckipper list` / `add --adopt` / `add` / `default` / `remove` against a temp HOME fixture.
- [x] `ckipper migrate` against a synthetic legacy `~/.claude/docker/` layout.
- [x] Live deploy on host — migration succeeded; `personal` adopted; second account `<name>` added cleanly.
- [x] Two concurrent Docker sessions, different accounts, validated against `test-prompt.md` Section 12.
- [x] No host-side credential symlink remains after sessions end.
EOF
)"
```

---

## Follow-ups (out of scope for this PR)

- `ckipper rename <old> <new>` — rename a registered account in-place.
- Bash + non-zsh shell support for the `cca`/`claude-<name>` aliases (currently zsh-only).
- Auto-detect account from cwd or git remote (deliberately YAGNI for now).
- Single-tenant install path that skips the registry entirely (probably unnecessary — registry with one account is already trivial).
