#!/bin/bash
set -e

echo "=== Ckipper Installer ==="
echo ""

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CKIPPER_DIR="${CKIPPER_DIR:-$HOME/.ckipper}"

# 1. Check prerequisites
echo "Checking prerequisites..."
missing_dependencies=()
command -v docker &>/dev/null || missing_dependencies+=("docker (install Docker Desktop)")
command -v jq &>/dev/null || missing_dependencies+=("jq (brew install jq)")
command -v git &>/dev/null || missing_dependencies+=("git")
if [[ "$(uname)" == "Darwin" ]]; then
    command -v security &>/dev/null || missing_dependencies+=("security (macOS Keychain CLI)")
fi

if [[ ${#missing_dependencies[@]} -gt 0 ]]; then
    echo "Missing prerequisites:"
    for dep in "${missing_dependencies[@]}"; do
        echo "  - $dep"
    done
    echo ""
    echo "Install the missing tools and re-run this script."
    exit 1
fi
echo "  All prerequisites found."
echo ""

# 2. Copy Docker files
echo "Copying Docker files to $CKIPPER_DIR/docker/..."
mkdir -p "$CKIPPER_DIR/docker"
cp "$REPO_DIR/docker/Dockerfile" "$CKIPPER_DIR/docker/"
cp "$REPO_DIR/docker/entrypoint.sh" "$CKIPPER_DIR/docker/"
cp "$REPO_DIR/docker/init-firewall.sh" "$CKIPPER_DIR/docker/"
cp "$REPO_DIR/docker/cleanup-projects.py" "$CKIPPER_DIR/docker/"
chmod +x "$CKIPPER_DIR/docker/entrypoint.sh"
chmod +x "$CKIPPER_DIR/docker/init-firewall.sh"
chmod +x "$CKIPPER_DIR/docker/cleanup-projects.py"

# 3. Copy hooks (canonical source for ckipper account sync-hooks)
echo "Copying hooks to $CKIPPER_DIR/hooks/..."
mkdir -p "$CKIPPER_DIR/hooks"
cp "$REPO_DIR/hooks/protect-claude-config.sh" "$CKIPPER_DIR/hooks/"
cp "$REPO_DIR/hooks/bash-guardrails.sh" "$CKIPPER_DIR/hooks/"
cp "$REPO_DIR/hooks/docker-context.sh" "$CKIPPER_DIR/hooks/"
cp "$REPO_DIR/hooks/notify-bell.sh" "$CKIPPER_DIR/hooks/"
chmod +x "$CKIPPER_DIR/hooks/protect-claude-config.sh"
chmod +x "$CKIPPER_DIR/hooks/bash-guardrails.sh"
chmod +x "$CKIPPER_DIR/hooks/docker-context.sh"
chmod +x "$CKIPPER_DIR/hooks/notify-bell.sh"

# 4. Copy ckipper.zsh and the lib/ tree.
echo "Copying ckipper.zsh and lib/ to $CKIPPER_DIR/docker/..."
cp "$REPO_DIR/ckipper.zsh" "$CKIPPER_DIR/docker/"

# Deploy lib/ tree, EXCLUDING test files (*_test.bats, *_test.py).
# Tests must NOT ship to user installs:
#   - they're noise in the runtime tree
#   - test stubs in tests/lib/stubs/ would appear as binaries on PATH if accidentally exposed
if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
        --exclude='*_test.bats' \
        --exclude='*_test.py' \
        --exclude='__pycache__' \
        "$REPO_DIR/lib/" "$CKIPPER_DIR/docker/lib/"
else
    # Fallback: tar pipe with excludes (no rsync available).
    rm -rf "$CKIPPER_DIR/docker/lib"
    (cd "$REPO_DIR" && tar -cf - --exclude='*_test.bats' --exclude='*_test.py' --exclude='__pycache__' lib) |
        (cd "$CKIPPER_DIR/docker" && tar -xf -)
fi

# Defense in depth: verify no test files leaked into the install.
if find "$CKIPPER_DIR/docker/lib" \( -name '*_test.*' -o -name '__pycache__' \) 2>/dev/null | grep -q .; then
    echo "ERROR: test files leaked into $CKIPPER_DIR/docker/lib/" >&2
    find "$CKIPPER_DIR/docker/lib" \( -name '*_test.*' -o -name '__pycache__' \) >&2
    exit 1
fi

# 5. Migrate any existing pre-merge config + clean up stale paths
# (w-function.zsh, w-config.zsh, _w completion file).
if [ -f "$CKIPPER_DIR/docker/w-config.zsh" ]; then
    if [ ! -f "$CKIPPER_DIR/docker/ckipper-config.zsh" ]; then
        echo "  Migrating $CKIPPER_DIR/docker/w-config.zsh → ckipper-config.zsh (preserves your settings)"
        # Rewrite assignments of the five known pre-merge variables to their
        # CKIPPER_* counterparts. Allow-list (not blanket W_* → CKIPPER_*) so
        # we don't mangle user comments or unrelated W_-prefixed names. The
        # anchor `^[[:space:]]*` matches assignment lines only, leaving
        # comment text intact.
        sed -E 's/^([[:space:]]*)W_(PROJECTS_DIR|WORKTREES_DIR|PORTS|EXTRA_VOLUMES|EXTRA_ENV)/\1CKIPPER_\2/' \
            "$CKIPPER_DIR/docker/w-config.zsh" >"$CKIPPER_DIR/docker/ckipper-config.zsh"
    fi
    echo "  Removing stale $CKIPPER_DIR/docker/w-config.zsh"
    rm -f "$CKIPPER_DIR/docker/w-config.zsh"
fi
if [ -f "$CKIPPER_DIR/docker/w-function.zsh" ]; then
    echo "  Removing stale $CKIPPER_DIR/docker/w-function.zsh (replaced by ckipper.zsh)"
    rm -f "$CKIPPER_DIR/docker/w-function.zsh"
fi
if [ -f "$HOME/.zsh/completions/_w" ]; then
    echo "  Removing stale $HOME/.zsh/completions/_w (replaced by _ckipper)"
    rm -f "$HOME/.zsh/completions/_w"
fi

# Generate ckipper-config.zsh (only if it doesn't exist — never overwrite user customizations).
# Also preserve accounts.json and aliases.zsh if they already exist (managed by ckipper CLI).
config_file="$CKIPPER_DIR/docker/ckipper-config.zsh"
if [[ ! -f $config_file ]]; then
    cp "$REPO_DIR/templates/ckipper-config.zsh.example" "$config_file"
    echo "  Created ckipper-config.zsh with defaults — edit to add your MCP mounts, ports, etc."
else
    echo "  ckipper-config.zsh already exists (not overwritten)"
fi
[[ -f "$CKIPPER_DIR/accounts.json" ]] && echo "  accounts.json already exists (not overwritten — managed by ckipper)"
[[ -f "$CKIPPER_DIR/aliases.zsh" ]] && echo "  aliases.zsh already exists (not overwritten — auto-generated)"

# 6. Deploy settings-template.json (consumed by ckipper account add / sync-hooks per-account)
echo "Copying settings-template.json to $CKIPPER_DIR/..."
cp "$REPO_DIR/templates/settings-template.json" "$CKIPPER_DIR/settings-template.json"
echo "  Settings template deployed. ckipper account sync-hooks applies it per-account."

# 7. Add or update source line in .zshrc
# Pre-merge installs sourced w-function.zsh from ~/.claude/docker/ or
# ~/.ckipper/docker/. The regex matches either install root and rewrites
# to the canonical ~/.ckipper/docker/ckipper.zsh.
#
# Edge cases handled:
#   - trailing comment on the source line (`source "..." # ckipper`)
#   - sed regex failing to match anything: we detect the no-op and append a
#     working source line so the user is never left with a broken zshrc.
#   - timestamped backup so re-runs don't clobber the previous .bak.
if grep -qE '/docker/w-function\.zsh' "$HOME/.zshrc" 2>/dev/null; then
    zshrc_backup="$HOME/.zshrc.ckipper-bak.$(date -u +%Y%m%dT%H%M%SZ)"
    cp "$HOME/.zshrc" "$zshrc_backup"
    zshrc_tmp="$HOME/.zshrc.ckipper-tmp.$$"
    sed -E 's|^[[:space:]]*source[[:space:]]+["'\'']?[$~/][^"'\'']*/docker/w-function\.zsh["'\'']?[[:space:]]*(#.*)?$|source "$HOME/.ckipper/docker/ckipper.zsh"|' \
        "$HOME/.zshrc" >"$zshrc_tmp" && mv "$zshrc_tmp" "$HOME/.zshrc"
    if grep -qE '/docker/w-function\.zsh' "$HOME/.zshrc" 2>/dev/null; then
        # Sed didn't match the stale source line (unusual whitespace,
        # quoting, or an exotic comment). Append a working source line so
        # ckipper still loads, and warn the user to remove the stale one.
        if ! grep -q 'ckipper/docker/ckipper\.zsh' "$HOME/.zshrc" 2>/dev/null; then
            echo '' >>"$HOME/.zshrc"
            echo '# Ckipper — multi-account Claude Code manager (ckipper + ckipper worktree run)' >>"$HOME/.zshrc"
            echo 'source "$HOME/.ckipper/docker/ckipper.zsh"' >>"$HOME/.zshrc"
        fi
        echo "  WARNING: could not rewrite stale w-function.zsh source line in ~/.zshrc."
        echo "  Appended a working ckipper.zsh source line; please remove the stale one manually."
        echo "  Backup: $zshrc_backup"
    else
        echo "  Updated ~/.zshrc source line to ~/.ckipper/docker/ckipper.zsh. Backup: $zshrc_backup"
    fi
elif ! grep -q 'ckipper/docker/ckipper\.zsh' "$HOME/.zshrc" 2>/dev/null; then
    echo '' >>"$HOME/.zshrc"
    echo '# Ckipper — multi-account Claude Code manager (ckipper + ckipper worktree run)' >>"$HOME/.zshrc"
    echo 'source "$HOME/.ckipper/docker/ckipper.zsh"' >>"$HOME/.zshrc"
    echo "  Added ckipper source line to ~/.zshrc"
else
    echo "  ~/.zshrc already sources ~/.ckipper/docker/ckipper.zsh"
fi

# 8. Print (do not auto-append) the optional aliases.zsh source line
echo ""
echo "Optional: enable per-account launchers (claude-<name> and bare <name>) by adding to ~/.zshrc:"
echo "    [[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh"
echo ""

# 9. Set up git hooks path (only if user hasn't already configured a different one,
# e.g. for husky, pre-commit, or another tool — never silently clobber)
echo "Configuring git hooks path..."
mkdir -p "$HOME/.git-hooks"
existing_hookspath=$(git config --global --get core.hooksPath 2>/dev/null || true)
if [ -z "$existing_hookspath" ] || [ "$existing_hookspath" = "$HOME/.git-hooks" ]; then
    git config --global core.hooksPath "$HOME/.git-hooks"
    echo "  Set core.hooksPath = $HOME/.git-hooks"
else
    echo "  Skipping core.hooksPath: existing value is '$existing_hookspath' (not overwriting)."
    echo "  If you want Ckipper's hook isolation, set manually:"
    echo '    git config --global core.hooksPath "$HOME/.git-hooks"'
fi

# 10. Print summary
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit $CKIPPER_DIR/docker/ckipper-config.zsh with your MCP mounts, ports, etc."
echo "  2. source ~/.zshrc"
echo "  3. ckipper worktree rebuild-image   # (or: ck wt rebuild-image)"
echo "  4. ckipper account add <name>       # register an account"
echo "  5. ckipper worktree run <project> test-branch --docker claude"
echo ""
echo "To update later: git pull && ./install.sh"
