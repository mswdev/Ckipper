#!/bin/bash
set -e

# Copy host's .claude.json to writable location (mounted read-only to avoid race condition)
if [ -f "$HOME/.claude-host.json" ]; then
    cp "$HOME/.claude-host.json" "$HOME/.claude.json"
    # Disable Chrome extension check in container (no browser available)
    if command -v jq &>/dev/null; then
        jq '.claudeInChromeDefaultEnabled = false | .cachedChromeExtensionInstalled = false' \
            "$HOME/.claude.json" > "$HOME/.claude.json.tmp" && mv "$HOME/.claude.json.tmp" "$HOME/.claude.json"
    fi
fi

# Write credentials from environment variable (macOS stores in Keychain, not on disk)
if [ -n "$CLAUDE_CREDENTIALS" ]; then
    echo "$CLAUDE_CREDENTIALS" > "$HOME/.claude/.credentials.json"
    chmod 600 "$HOME/.claude/.credentials.json"
fi

# Set git identity from .claude.json account info (needed for commits inside container)
if [ -f "$HOME/.claude.json" ] && command -v jq &>/dev/null; then
    git_name=$(jq -r '.oauthAccount.displayName // empty' "$HOME/.claude.json" 2>/dev/null)
    git_email=$(jq -r '.oauthAccount.emailAddress // empty' "$HOME/.claude.json" 2>/dev/null)
    [ -n "$git_name" ] && git config --global user.name "$git_name"
    [ -n "$git_email" ] && git config --global user.email "$git_email"
fi

# Persist GitHub token for gh CLI (before we clear env vars)
if [ -n "$GH_TOKEN" ]; then
    echo "$GH_TOKEN" | gh auth login --with-token 2>/dev/null || true
fi

# Optionally enable the egress firewall
if [ "$ENABLE_FIREWALL" = "1" ]; then
    echo "Enabling egress firewall..."
    sudo /usr/local/bin/init-firewall.sh
    echo "Firewall active. Only whitelisted domains are accessible."
fi

cd /workspace

# Fix Turbo cache path — worktrees resolve to the host's main repo path which isn't writable
export TURBO_CACHE_DIR=/workspace/.turbo/cache

# Reinstall native binaries for Linux — npm install on the host (macOS) pulls
# macOS-specific binaries (rollup, biome, esbuild, swc, etc.) that don't work
# inside the Linux container. npm rebuild requires gcc which isn't installed,
# so we run npm install which downloads pre-built Linux binaries instead.
if [ -d node_modules ]; then
    echo "Installing platform-specific binaries for Linux..."
    npm install --prefer-offline 2>/dev/null || true
fi

# Clear credentials from environment (consumed above; exec ensures clean /proc/self/environ)
unset CLAUDE_CREDENTIALS GH_TOKEN

# Start interactive Claude session with skip-permissions
exec claude --dangerously-skip-permissions
