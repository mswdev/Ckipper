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

# Copy SSH config from staging mount, stripping macOS-specific options.
# Same pattern as .claude.json → .claude-host.json.
if [ -d "$HOME/.ssh-host" ]; then
    cp -a "$HOME/.ssh-host/." "$HOME/.ssh/" 2>/dev/null || true
    chmod 700 "$HOME/.ssh"
    # UseKeychain is Apple-specific (not in upstream OpenSSH); causes errors on Linux
    if [ -f "$HOME/.ssh/config" ]; then
        sed -i '/^\s*UseKeychain\b/Id' "$HOME/.ssh/config"
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

# Disable GPG signing via environment (no GPG key in container).
# Uses GIT_CONFIG_COUNT instead of git config so we never modify the host's
# .git/config (mounted rw). Env vars take highest priority, overriding both
# local and global config, and disappear when the container exits.
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=commit.gpgsign
export GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_KEY_1=tag.gpgsign
export GIT_CONFIG_VALUE_1=false

# Persist GitHub token for gh CLI — must unset GH_TOKEN first because gh refuses
# to store credentials while the env var is set (it treats the env var as authoritative)
if [ -n "$GH_TOKEN" ]; then
    _gh_token="$GH_TOKEN"
    unset GH_TOKEN
    echo "$_gh_token" | gh auth login --with-token 2>/dev/null || true
    # Configure gh as git credential helper (enables git push over HTTPS)
    gh auth setup-git 2>/dev/null || true
    unset _gh_token
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

# Force truecolor output for statusline — Claude Code may not pass FORCE_COLOR
# to the statusline subprocess, so we inject it via a bunx wrapper that sits
# earlier in PATH (~/.local/bin is prepended in Dockerfile). The wrapper also
# unsets NO_COLOR to prevent chalk from stripping ANSI codes.
export FORCE_COLOR=3
export COLORTERM=truecolor
cat > "$HOME/.local/bin/bunx" << 'WRAPPER'
#!/bin/bash
export FORCE_COLOR=3
export COLORTERM=truecolor
unset NO_COLOR
exec /usr/local/bin/bunx "$@"
WRAPPER
chmod +x "$HOME/.local/bin/bunx"

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

# Run the provided command, or drop to an interactive shell if none given.
# When called via `w <project> <branch> --docker claude`, Docker passes
# "claude --dangerously-skip-permissions" as arguments. Without arguments
# (just `--docker`), the user gets a fully set-up bash shell.
if [ $# -gt 0 ]; then
    exec "$@"
else
    exec /bin/bash
fi
