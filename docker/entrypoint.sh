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

# Optionally enable the egress firewall
if [ "$ENABLE_FIREWALL" = "1" ]; then
    echo "Enabling egress firewall..."
    sudo /usr/local/bin/init-firewall.sh
    echo "Firewall active. Only whitelisted domains are accessible."
fi

cd /workspace

# Rebuild native binaries for Linux (node_modules may have been installed on macOS)
if [ -d node_modules ]; then
    npm rebuild 2>/dev/null || true
fi

# Clear credentials from environment (consumed above; exec ensures clean /proc/self/environ)
unset CLAUDE_CREDENTIALS GH_TOKEN

# Start interactive Claude session with skip-permissions
exec claude --dangerously-skip-permissions
