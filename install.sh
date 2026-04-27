#!/bin/bash
set -e

echo "=== Ckipper Installer ==="
echo ""

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CKIPPER_DIR="${CKIPPER_DIR:-$HOME/.ckipper}"

# Migrate legacy ~/.claude/docker/ layout if present (idempotent)
LEGACY_DIR="$HOME/.claude/docker"
if [ -d "$LEGACY_DIR" ] && [ ! -d "$CKIPPER_DIR" ]; then
    echo "Migrating ~/.claude/docker/ -> $CKIPPER_DIR/"
    mkdir -p "$CKIPPER_DIR"
    cp -a "$LEGACY_DIR/." "$CKIPPER_DIR/"
    echo "Migrated. The legacy directory is left intact at $LEGACY_DIR for one release cycle."
    echo "After verifying the new location works (ckipper list shows your accounts):"
    echo "  rm -rf $LEGACY_DIR"

    # Sweep migrated w-config.zsh for stale path strings (warn only — never auto-edit user config)
    if [ -f "$CKIPPER_DIR/w-config.zsh" ]; then
        stale=$(grep -n "\.claude/docker" "$CKIPPER_DIR/w-config.zsh" 2>/dev/null || true)
        if [ -n "$stale" ]; then
            echo ""
            echo "WARNING: Your migrated w-config.zsh contains stale ~/.claude/docker/ paths:"
            echo "$stale"
            echo "Update these to ~/.ckipper/docker/ manually."
            echo ""
        fi
    fi
fi

# 1. Check prerequisites
echo "Checking prerequisites..."
missing=()
command -v docker &>/dev/null || missing+=("docker (install Docker Desktop)")
command -v jq &>/dev/null || missing+=("jq (brew install jq)")
command -v git &>/dev/null || missing+=("git")
if [[ "$(uname)" == "Darwin" ]]; then
    command -v security &>/dev/null || missing+=("security (macOS Keychain CLI)")
fi

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing prerequisites:"
    for dep in "${missing[@]}"; do
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
chmod +x "$CKIPPER_DIR/docker/entrypoint.sh"
chmod +x "$CKIPPER_DIR/docker/init-firewall.sh"

# 3. Copy hooks (canonical source for ckipper sync-hooks)
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

# 4. Copy w-function.zsh and ckipper.zsh
echo "Copying w-function.zsh and ckipper.zsh to $CKIPPER_DIR/docker/..."
cp "$REPO_DIR/w-function.zsh" "$CKIPPER_DIR/docker/"
cp "$REPO_DIR/ckipper.zsh" "$CKIPPER_DIR/docker/"

# 5. Generate w-config.zsh (only if it doesn't exist — never overwrite user customizations)
# Also preserve accounts.json and aliases.zsh if they already exist (managed by ckipper CLI).
config_file="$CKIPPER_DIR/docker/w-config.zsh"
if [[ ! -f "$config_file" ]]; then
    cp "$REPO_DIR/w-config.zsh.example" "$config_file"
    echo "  Created w-config.zsh with defaults — edit to add your MCP mounts, ports, etc."
else
    echo "  w-config.zsh already exists (not overwritten)"
fi
[[ -f "$CKIPPER_DIR/accounts.json" ]] && echo "  accounts.json already exists (not overwritten — managed by ckipper)"
[[ -f "$CKIPPER_DIR/aliases.zsh" ]] && echo "  aliases.zsh already exists (not overwritten — auto-generated)"

# 6. Deploy settings-template.json (consumed by ckipper add / sync-hooks per-account)
echo "Copying settings-template.json to $CKIPPER_DIR/..."
cp "$REPO_DIR/settings-hooks.json" "$CKIPPER_DIR/settings-template.json"
echo "  Settings template deployed. ckipper sync-hooks applies it per-account."

# 7. Add or update source line in .zshrc
if grep -q "source.*\.claude/docker/w-function.zsh" "$HOME/.zshrc" 2>/dev/null; then
    sed -i.bak 's|source.*\.claude/docker/w-function\.zsh|source ~/.ckipper/docker/w-function.zsh|' "$HOME/.zshrc"
    echo "  Updated ~/.zshrc source line to ~/.ckipper/. Backup at ~/.zshrc.bak."
elif ! grep -q 'ckipper/docker/w-function.zsh' "$HOME/.zshrc" 2>/dev/null; then
    echo '' >> "$HOME/.zshrc"
    echo '# Ckipper — Worktree Manager (w function)' >> "$HOME/.zshrc"
    echo 'source "$HOME/.ckipper/docker/w-function.zsh"' >> "$HOME/.zshrc"
    echo "  Added w() source line to ~/.zshrc"
else
    echo "  ~/.zshrc already sources ~/.ckipper/docker/w-function.zsh"
fi

# 8. Print (do not auto-append) the optional aliases.zsh source line
echo ""
echo "Optional: enable per-account aliases (claude-<name>, cca <name>) by adding to ~/.zshrc:"
echo "    [[ -f ~/.ckipper/aliases.zsh ]] && source ~/.ckipper/aliases.zsh"
echo ""

# 9. Warn about inlined w() from old installs
if grep -q '^w()' "$HOME/.zshrc" 2>/dev/null || grep -q '^_w_build_image()' "$HOME/.zshrc" 2>/dev/null; then
    echo ""
    echo "WARNING: Your ~/.zshrc contains an inlined w() function from a previous install."
    echo "The new approach sources it from $CKIPPER_DIR/docker/w-function.zsh instead."
    echo "Please remove the old inlined function from ~/.zshrc manually."
    echo "(Search for '_w_build_image()' or 'w()' and remove everything through the 'COMPEOF' line)"
fi

# 10. Set up git hooks path
echo "Configuring git hooks path..."
mkdir -p "$HOME/.git-hooks"
git config --global core.hooksPath "$HOME/.git-hooks"

# 11. Print summary
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit $CKIPPER_DIR/docker/w-config.zsh with your MCP mounts, ports, etc."
echo "  2. source ~/.zshrc"
echo "  3. w --rebuild-image"
echo "  4. ckipper add <name>   # register an account"
echo "  5. w <your-project> test-branch --docker claude"
echo ""
echo "To update later: git pull && ./install.sh"
