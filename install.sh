#!/bin/bash
set -e

echo "=== Claude Docker Sandbox Installer ==="
echo ""

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

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
echo "Copying Docker files to ~/.claude/docker/..."
mkdir -p "$HOME/.claude/docker"
cp "$REPO_DIR/docker/Dockerfile" "$HOME/.claude/docker/"
cp "$REPO_DIR/docker/entrypoint.sh" "$HOME/.claude/docker/"
cp "$REPO_DIR/docker/init-firewall.sh" "$HOME/.claude/docker/"
chmod +x "$HOME/.claude/docker/entrypoint.sh"
chmod +x "$HOME/.claude/docker/init-firewall.sh"

# 3. Copy hooks
echo "Copying hooks to ~/.claude/hooks/..."
mkdir -p "$HOME/.claude/hooks"
cp "$REPO_DIR/hooks/protect-claude-config.sh" "$HOME/.claude/hooks/"
cp "$REPO_DIR/hooks/bash-guardrails.sh" "$HOME/.claude/hooks/"
cp "$REPO_DIR/hooks/docker-context.sh" "$HOME/.claude/hooks/"
chmod +x "$HOME/.claude/hooks/protect-claude-config.sh"
chmod +x "$HOME/.claude/hooks/bash-guardrails.sh"
chmod +x "$HOME/.claude/hooks/docker-context.sh"

# 4. Copy w-function.zsh
echo "Copying w-function.zsh to ~/.claude/docker/..."
cp "$REPO_DIR/w-function.zsh" "$HOME/.claude/docker/"

# 5. Generate w-config.zsh (only if it doesn't exist — never overwrite)
config_file="$HOME/.claude/docker/w-config.zsh"
if [[ ! -f "$config_file" ]]; then
    cp "$REPO_DIR/w-config.zsh.example" "$config_file"
    echo "  Created w-config.zsh with defaults — edit to add your MCP mounts, ports, etc."
else
    echo "  w-config.zsh already exists (not overwritten)"
fi

# 6. Merge settings-hooks.json into ~/.claude/settings.json
echo "Merging hooks into ~/.claude/settings.json..."
settings_file="$HOME/.claude/settings.json"
if [[ ! -f "$settings_file" ]]; then
    echo '{}' > "$settings_file"
fi
hooks_json=$(jq 'del(._comment)' "$REPO_DIR/settings-hooks.json")
jq --argjson hooks "$hooks_json" '. * $hooks' "$settings_file" > "${settings_file}.tmp" \
    && mv "${settings_file}.tmp" "$settings_file"
echo "  Hooks merged."

# 7. Add source line to .zshrc (if not already present)
if ! grep -q 'w-function.zsh' "$HOME/.zshrc" 2>/dev/null; then
    echo '' >> "$HOME/.zshrc"
    echo '# Worktree Manager (w function)' >> "$HOME/.zshrc"
    echo 'source "$HOME/.claude/docker/w-function.zsh"' >> "$HOME/.zshrc"
    echo "  Added w() source line to ~/.zshrc"
else
    echo "  ~/.zshrc already sources w-function.zsh"
fi

# 8. Warn about inlined w() from old installs
if grep -q '^w()' "$HOME/.zshrc" 2>/dev/null || grep -q '^_w_build_image()' "$HOME/.zshrc" 2>/dev/null; then
    echo ""
    echo "WARNING: Your ~/.zshrc contains an inlined w() function from a previous install."
    echo "The new approach sources it from ~/.claude/docker/w-function.zsh instead."
    echo "Please remove the old inlined function from ~/.zshrc manually."
    echo "(Search for '_w_build_image()' or 'w()' and remove everything through the 'COMPEOF' line)"
fi

# 9. Set up git hooks path
echo "Configuring git hooks path..."
mkdir -p "$HOME/.git-hooks"
git config --global core.hooksPath "$HOME/.git-hooks"

# 10. Print summary
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit ~/.claude/docker/w-config.zsh with your MCP mounts, ports, etc."
echo "  2. source ~/.zshrc"
echo "  3. w --rebuild-image"
echo "  4. w <your-project> test-branch --docker claude"
echo ""
echo "To update later: git pull && ./install.sh"
