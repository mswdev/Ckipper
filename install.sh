#!/bin/bash
set -e

echo "=== Claude Docker Sandbox Installer ==="
echo ""

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# 0. Check prerequisites
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

# 1. Copy Docker files
echo "Copying Docker files to ~/.claude/docker/..."
mkdir -p "$HOME/.claude/docker"
cp "$REPO_DIR/docker/Dockerfile" "$HOME/.claude/docker/"
cp "$REPO_DIR/docker/entrypoint.sh" "$HOME/.claude/docker/"
cp "$REPO_DIR/docker/init-firewall.sh" "$HOME/.claude/docker/"
chmod +x "$HOME/.claude/docker/entrypoint.sh"
chmod +x "$HOME/.claude/docker/init-firewall.sh"

# 2. Copy hooks
echo "Copying hooks to ~/.claude/hooks/..."
mkdir -p "$HOME/.claude/hooks"
cp "$REPO_DIR/hooks/protect-claude-config.sh" "$HOME/.claude/hooks/"
cp "$REPO_DIR/hooks/bash-guardrails.sh" "$HOME/.claude/hooks/"
cp "$REPO_DIR/hooks/docker-context.sh" "$HOME/.claude/hooks/"
chmod +x "$HOME/.claude/hooks/protect-claude-config.sh"
chmod +x "$HOME/.claude/hooks/bash-guardrails.sh"
chmod +x "$HOME/.claude/hooks/docker-context.sh"

# 3. Set up git hooks path
echo "Configuring git hooks path..."
mkdir -p "$HOME/.git-hooks"
git config --global core.hooksPath "$HOME/.git-hooks"

# 4. Print manual steps
echo ""
echo "=== Manual Steps Required ==="
echo ""
echo "1. Add the hooks to your ~/.claude/settings.json. Merge the contents of"
echo "   settings-hooks.json into your existing 'hooks' section:"
echo ""
echo "   cat $REPO_DIR/settings-hooks.json"
echo ""
echo "   IMPORTANT: Use \$HOME/ in all paths, not hardcoded /Users/yourname/"
echo ""

# Check if w() function already exists in .zshrc
if grep -q '^w()' "$HOME/.zshrc" 2>/dev/null || grep -q 'function w()' "$HOME/.zshrc" 2>/dev/null; then
    echo "2. The w() function already exists in your ~/.zshrc."
    echo "   To update it, remove the old version first, then append the new one:"
    echo ""
    echo "   # Remove old w() function from ~/.zshrc manually, then:"
    echo "   cat $REPO_DIR/w-function.zsh >> ~/.zshrc"
else
    echo "2. Append the w() function to your ~/.zshrc:"
    echo ""
    echo "   cat $REPO_DIR/w-function.zsh >> ~/.zshrc"
fi
echo ""
echo "   Then customize (search for these in the file):"
echo "   - 'MCP dependencies' — add volume mounts for your MCP servers"
echo "   - 'ports=' — change to your dev server ports"
echo "   - 'develop' — change if your default branch is main"
echo "   - 'ccstatusline' — uncomment if you use ccstatusline"
echo ""
echo "3. Build the Docker image and test:"
echo ""
echo "   source ~/.zshrc"
echo "   w --rebuild-image"
echo "   w <your-project> test-branch --docker claude"
echo ""
echo "=== Done ==="
