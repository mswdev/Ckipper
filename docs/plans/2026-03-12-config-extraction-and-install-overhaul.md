# Config Extraction & Install Overhaul

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split w-function.zsh into core logic + user config so updates are a simple file copy, and make install.sh fully automated (no manual steps).

**Architecture:** w-function.zsh sources w-config.zsh for user-specific values (ports, extra docker volumes, extra env vars). install.sh copies all core files, auto-merges hooks into settings.json, generates a default w-config.zsh (never overwrites existing), and adds the source line to .zshrc. The repo's w-function.zsh becomes the single source of truth — deployed as-is, no diverging copies.

**Tech Stack:** zsh, bash, jq

---

### Task 1: Create w-config.zsh template in repo

**Files:**
- Create: `w-config.zsh.example`

**Step 1: Create the example config file**

```zsh
# ── w-config.zsh ─────────────────────────────────────────────────
# User-specific configuration for the w() worktree manager.
# This file is sourced by w-function.zsh. It is never overwritten
# by install.sh — your customizations are safe across updates.
#
# After editing, run: source ~/.zshrc
# ─────────────────────────────────────────────────────────────────

# Ports to forward from container to host.
# These should match your dev servers (Next.js, Storybook, etc.)
W_PORTS=(3000 3030 6006)

# Extra Docker volume mounts (for MCP servers that reference local files).
# Mount at the exact same host path so MCP configs work unchanged.
# Format: "host_path:container_path:mode"
# Examples:
#   "$HOME/Developer/my-data:$HOME/Developer/my-data:ro"
#   "$HOME/path/to/file.json:$HOME/path/to/file.json:ro"
W_EXTRA_VOLUMES=()

# Extra Docker environment variables.
# Format: "KEY=value"
# Examples:
#   "MY_MCP_SERVER=host.docker.internal"
W_EXTRA_ENV=()
```

**Step 2: Commit**

```bash
git add w-config.zsh.example
git commit -m "Add w-config.zsh.example for user-specific Docker settings"
```

---

### Task 2: Modify w-function.zsh to source config and fold in improvements

This task modifies the repo's `w-function.zsh` to:
1. Source `w-config.zsh` at the top (with sensible defaults if missing)
2. Use `W_PORTS`, `W_EXTRA_VOLUMES`, `W_EXTRA_ENV` arrays from config
3. Fold in the GH token `gh auth token` fallback (currently only in deployed copy)
4. Remove the hardcoded ports, MCP mount examples, and statusline mount comments from the docker_args — these all move to config

**Files:**
- Modify: `w-function.zsh`

**Step 1: Add config sourcing at the top (after the header comment, before `_w_build_image`)**

Replace lines 24 (blank line before `_w_build_image`) with:

```zsh

# Source user config (ports, extra volumes, extra env vars)
_w_config="$HOME/.claude/docker/w-config.zsh"
if [[ -f "$_w_config" ]]; then
    source "$_w_config"
fi
# Defaults if config is missing or incomplete
: ${W_PORTS:=(3000)}
: ${W_EXTRA_VOLUMES:=()}
: ${W_EXTRA_ENV:=()}

```

**Step 2: Update the GH token extraction to include `gh auth token` fallback**

Find the GH token extraction block (around line 273) and ensure it has the fallback:

```zsh
        # Extract GitHub token for gh CLI auth inside container
        # Try .claude.json MCP config first, then fall back to host's gh CLI auth
        local gh_token
        gh_token=$(jq -r '.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN // empty' "$HOME/.claude.json" 2>/dev/null) || true
        if [[ -z "$gh_token" ]] && command -v gh &>/dev/null; then
            gh_token=$(gh auth token 2>/dev/null) || true
        fi
```

Note: The repo version already has this from the recent worktree-fix branch. Verify it's present; if so, no change needed.

**Step 3: Replace the hardcoded docker_args section**

In the `docker_args` array, replace everything from the statusline comment through the MCP dependencies comment block (the commented-out `-v` examples) with config-driven injection. The new structure after the `claude-uv-cache` volume:

```zsh
            # ──────────────────────────────────────────────────────────
        )

        # Add user-configured extra volumes from w-config.zsh
        for vol in "${W_EXTRA_VOLUMES[@]}"; do
            docker_args+=( -v "$vol" )
        done
```

Remove these lines from the hardcoded docker_args array:
- The `# ── Statusline (ccstatusline)` block (lines ~301-306)
- The `# ── MCP dependencies` block (lines ~320-326)

They are replaced by `W_EXTRA_VOLUMES` in config.

**Step 4: Replace hardcoded ports with config variable**

Change the ports line from:

```zsh
        local -a ports=(3000 3030 6006)
```

to:

```zsh
        local -a ports=("${W_PORTS[@]}")
```

**Step 5: Add extra env vars injection after GH_TOKEN block**

After the `docker_args+=( -e "GH_TOKEN=$gh_token" )` block (and the warning else branch), add:

```zsh

        # Add user-configured extra env vars from w-config.zsh
        for env_var in "${W_EXTRA_ENV[@]}"; do
            docker_args+=( -e "$env_var" )
        done
```

**Step 6: Update the CUSTOMIZATION header comment**

Replace the existing customization header (lines 14-23) with:

```zsh
# ── CUSTOMIZATION ────────────────────────────────────────────────
# Edit ~/.claude/docker/w-config.zsh to customize:
#   - W_PORTS: dev server ports to forward
#   - W_EXTRA_VOLUMES: MCP server mounts and other volume mounts
#   - W_EXTRA_ENV: extra environment variables for the container
#
# BASE BRANCH: Worktrees are created from origin/develop. Change
# "develop" below if your default branch is different (e.g. main).
# ─────────────────────────────────────────────────────────────────
```

**Step 7: Verify and commit**

Review the full file to ensure no stale comments reference "search for ports=" or "search for MCP dependencies".

```bash
git add w-function.zsh
git commit -m "Extract user config from w-function.zsh into w-config.zsh

Ports, extra Docker volumes, and extra env vars now come from
~/.claude/docker/w-config.zsh. The repo's w-function.zsh can be
deployed as-is — no more diverging copies with manual merges."
```

---

### Task 3: Make install.sh fully automated and idempotent

**Files:**
- Modify: `install.sh`

**Step 1: Rewrite install.sh**

The new install.sh should:

1. Check prerequisites (same as before)
2. Copy Docker files (same as before)
3. Copy hooks (same as before)
4. **Copy w-function.zsh** to `~/.claude/docker/w-function.zsh`
5. **Generate w-config.zsh** at `~/.claude/docker/w-config.zsh` — but ONLY if it doesn't exist. Never overwrite.
6. **Merge settings-hooks.json** into `~/.claude/settings.json` using jq (create the file if missing, merge hooks array without duplicating)
7. **Add source line** to `~/.zshrc` if not already present
8. Set up git hooks path (same as before)
9. Print summary (no "Manual Steps Required" section)

For step 6, the jq merge logic:

```bash
# 6. Merge hooks into settings.json
echo "Merging hooks into ~/.claude/settings.json..."
settings_file="$HOME/.claude/settings.json"
if [[ ! -f "$settings_file" ]]; then
    echo '{}' > "$settings_file"
fi
# Read desired hooks from settings-hooks.json (skip _comment key)
hooks_json=$(jq 'del(._comment)' "$REPO_DIR/settings-hooks.json")
# Merge: existing settings win for non-hooks keys, hooks are replaced
jq --argjson hooks "$hooks_json" '. * $hooks' "$settings_file" > "${settings_file}.tmp" \
    && mv "${settings_file}.tmp" "$settings_file"
echo "  Hooks merged."
```

For step 7, the .zshrc source line:

```bash
# 7. Add source line to .zshrc if missing
if ! grep -q 'w-function.zsh' "$HOME/.zshrc" 2>/dev/null; then
    echo '' >> "$HOME/.zshrc"
    echo '# Worktree Manager (w function)' >> "$HOME/.zshrc"
    echo 'source "$HOME/.claude/docker/w-function.zsh"' >> "$HOME/.zshrc"
    echo "  Added w() source line to ~/.zshrc"
else
    echo "  ~/.zshrc already sources w-function.zsh"
fi
```

For step 5, the config generation:

```bash
# 5. Generate w-config.zsh (never overwrite existing)
config_file="$HOME/.claude/docker/w-config.zsh"
if [[ ! -f "$config_file" ]]; then
    cp "$REPO_DIR/w-config.zsh.example" "$config_file"
    echo "  Created w-config.zsh with defaults — edit to add your MCP mounts, ports, etc."
else
    echo "  w-config.zsh already exists (not overwritten)"
fi
```

Also, remove the old `w()` function from .zshrc if it's inlined (handles upgrades from the old approach):

```bash
# Remove inlined w() function from .zshrc if present (upgrade from old approach)
if grep -q '^w()' "$HOME/.zshrc" 2>/dev/null || grep -q '^_w_build_image()' "$HOME/.zshrc" 2>/dev/null; then
    echo ""
    echo "WARNING: Your ~/.zshrc contains an inlined w() function from a previous install."
    echo "The new approach sources it from ~/.claude/docker/w-function.zsh instead."
    echo "Please remove the old inlined function from ~/.zshrc manually."
    echo "(Search for '_w_build_image()' or 'w()' and remove everything through the 'COMPEOF' line)"
fi
```

**Step 2: Commit**

```bash
git add install.sh
git commit -m "Make install.sh fully automated and idempotent

Copies w-function.zsh, generates w-config.zsh (never overwrites),
auto-merges hooks into settings.json, and adds source line to .zshrc.
No more manual steps. Safe to re-run for updates: git pull && ./install.sh"
```

---

### Task 4: Update CLAUDE.md and README.md

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md`

**Step 1: Update CLAUDE.md**

Architecture section: add bullet for `w-config.zsh.example`.

Development Workflow table: update `w-function.zsh` row to:

```
| `w-function.zsh` | `./install.sh` (copies to `~/.claude/docker/`; user config in `w-config.zsh` is preserved) |
```

Add row for `w-config.zsh.example`:

```
| `w-config.zsh.example` | Template only — user's `~/.claude/docker/w-config.zsh` is never overwritten |
```

Update the "Two copies" paragraph to:

```
Two copies of the code exist: this repo (development) and deployed files on the host (`~/.claude/docker/`, `~/.claude/hooks/`). Run `./install.sh` to sync all core files. User customizations live in `~/.claude/docker/w-config.zsh` and are never overwritten.
```

**Step 2: Update README.md**

Update the "What Gets Installed Where" table to add:

```
| `w-function.zsh` | `~/.claude/docker/w-function.zsh` | w() function (sourced by .zshrc) |
| `w-config.zsh.example` | `~/.claude/docker/w-config.zsh` | User config (ports, mounts, env) |
| `settings-hooks.json` | Auto-merged into `~/.claude/settings.json` | Hook registration |
```

Remove the old row that says `w-function.zsh | Append to ~/.zshrc`.
Remove the old row that says `settings-hooks.json | Merge into ~/.claude/settings.json`.

Update "Option 1: Manual Install" to:

```bash
git clone https://github.com/whmoro/claude-docker-sandbox.git
cd claude-docker-sandbox
./install.sh
# Edit ~/.claude/docker/w-config.zsh with your MCP mounts, ports, etc.
source ~/.zshrc
w --rebuild-image
w <your-project> test-branch --docker claude
```

Update "Option 2: Let Claude Do It" prompt to something simpler since install.sh handles everything now.

Update the Customization section — remove references to "search for X in w-function.zsh" and point to `~/.claude/docker/w-config.zsh` instead.

**Step 3: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "Update docs for config extraction and automated install"
```

---

### Task 5: Deploy to Matt's system

This task updates the live deployment to match the new architecture.

**Files:**
- Modify: `~/.claude/docker/w-function.zsh` (overwrite with repo version)
- Create: `~/.claude/docker/w-config.zsh` (Matt's customizations)

**Step 1: Create Matt's w-config.zsh**

```zsh
# ── w-config.zsh ─────────────────────────────────────────────────
# User-specific configuration for the w() worktree manager.
# This file is sourced by w-function.zsh. It is never overwritten
# by install.sh — your customizations are safe across updates.
#
# After editing, run: source ~/.zshrc
# ─────────────────────────────────────────────────────────────────

# Ports to forward from container to host.
W_PORTS=(3000 3030 6006)

# Extra Docker volume mounts.
W_EXTRA_VOLUMES=(
    # Statusline (ccstatusline)
    "$HOME/.config/ccstatusline:/home/claude/.config/ccstatusline:ro"
    "$HOME/.cache/ccstatusline:/home/claude/.cache/ccstatusline:rw"
    # MCP dependencies
    "$HOME/Developer/Vibma:$HOME/Developer/Vibma:ro"
    "$HOME/Developer/tailwindplus-components-2026-02-27-222441.json:$HOME/Developer/tailwindplus-components-2026-02-27-222441.json:ro"
)

# Extra Docker environment variables.
W_EXTRA_ENV=(
    # Vibma MCP: relay runs on host, container reaches it via host.docker.internal
    "VIBMA_SERVER=host.docker.internal"
)
```

**Step 2: Copy the repo's w-function.zsh over the deployed version**

```bash
cp /Users/matt/Developer/Whmoro/claude-docker-sandbox/w-function.zsh ~/.claude/docker/w-function.zsh
```

This replaces the old customized monolithic file with the clean repo version that reads from config.

**Step 3: Verify .zshrc source line exists**

Check that `~/.zshrc` already has `source "$HOME/.claude/docker/w-function.zsh"` (it does from the earlier change in this conversation).

**Step 4: Verify by sourcing**

```bash
source ~/.zshrc
w --help  # or just `w` with no args to see usage
```

**Step 5: No commit needed** — these are host-only deployed files, not in the repo.

---

### Task 6: Final commit and PR update

**Step 1: Ensure all repo changes are committed on the branch**

Verify git status is clean on `fix/worktree-remote-branch-tracking`.

**Step 2: Push and update PR #20**

```bash
git push
```

The PR at https://github.com/whmoro/claude-docker-sandbox/pull/20 will automatically include the new commits.
