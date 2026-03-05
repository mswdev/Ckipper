#!/bin/bash
set -e

echo "=== Claude Docker Sandbox Installer ==="
echo ""

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

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

# 4. Register hooks in settings.json
echo ""
echo "=== Manual Steps Required ==="
echo ""
echo "1. Add the hooks to your ~/.claude/settings.json. Merge this into the"
echo "   existing 'hooks' section (don't replace other settings):"
echo ""
echo '   See the hooks configuration in the README or settings-hooks.json'
echo ""
echo "2. Append the w() function to your ~/.zshrc:"
echo ""
echo "   cat $REPO_DIR/w-function.zsh >> ~/.zshrc"
echo ""
echo "   Or copy-paste the contents manually. Then customize:"
echo "   - MCP mount paths (search for 'MCP dependencies')"
echo "   - Port numbers (search for 'ports=')"
echo "   - Base branch (search for 'develop' if yours is 'main')"
echo ""
echo "3. Build the Docker image and test:"
echo ""
echo "   source ~/.zshrc"
echo "   w --rebuild-image"
echo "   w <your-project> test-branch --auto"
echo ""
echo "=== Done ==="
