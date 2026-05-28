FROM node:24-slim

# Every `ckipper worktree rebuild-image` passes a unique CACHEBUST value, so all layers
# below are re-fetched. This keeps system packages, CLI tools, and Claude
# Code current without ever going stale. Only the base image (node:24-slim)
# is cached — pull it manually with `docker pull node:24-slim` if needed.
ARG CACHEBUST=1

# Install system dependencies + GitHub CLI repo setup
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    jq \
    python3 \
    ripgrep \
    sudo \
    tmux \
    iptables \
    dnsutils \
    ca-certificates \
    gnupg \
    openssh-client \
    unzip \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh chromium \
    && rm -rf /var/lib/apt/lists/*

ENV CHROME_BIN=/usr/bin/chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium
ENV CHROMIUM_FLAGS="--no-sandbox"
ENV PUPPETEER_CHROMIUM_ARGS="--no-sandbox"

# Install uv/uvx (Python package runner — needed for Python-based MCP servers)
# SHA256 fetched 2026-05-28 from https://astral.sh/uv/install.sh
ARG UV_INSTALLER_SHA256=d79d834572b5b5cdd521289c055adcdbacd43bfe9e6b896445f351075dac4113
RUN curl -LsSf https://astral.sh/uv/install.sh -o /tmp/install.sh && \
    echo "${UV_INSTALLER_SHA256}  /tmp/install.sh" | sha256sum -c - && \
    sh /tmp/install.sh && \
    rm /tmp/install.sh \
    && cp /root/.local/bin/uv /usr/local/bin/uv \
    && cp /root/.local/bin/uvx /usr/local/bin/uvx \
    && chmod +x /usr/local/bin/uv /usr/local/bin/uvx

# Install Claude Code via native installer — `@latest` channel.
# SHA256 fetched 2026-05-28 from https://claude.ai/install.sh
#
# The bootstrap script accepts a positional arg (`stable` | `latest` | a
# specific semver) that gets forwarded to `claude install <target>`. Passing
# `latest` selects Anthropic's @latest release channel (the same one the
# Homebrew `claude-code@latest` cask tracks) instead of the default stable
# channel — which lags @latest by ~a week. Refresh the SHA whenever the
# bootstrap script itself changes upstream (not just when a Claude Code
# release ships).
ARG CLAUDE_INSTALLER_SHA256=005ec1a937f32dfbb74f9e810287bcb12cba2d5cae4c9277aa8c6364adbf1787
RUN curl -fsSL https://claude.ai/install.sh -o /tmp/install.sh && \
    echo "${CLAUDE_INSTALLER_SHA256}  /tmp/install.sh" | sha256sum -c - && \
    bash /tmp/install.sh latest && \
    rm /tmp/install.sh \
    && cp /root/.local/bin/claude /usr/local/bin/claude \
    && chmod +x /usr/local/bin/claude

# Create non-root user and pre-seed SSH known hosts
RUN userdel -r node 2>/dev/null; groupdel node 2>/dev/null; \
    groupadd -g 1000 claude \
    && useradd -u 1000 -g claude -m -s /bin/bash claude \
    && echo "claude ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh, /usr/local/bin/fix-volume-perms.sh" >> /etc/sudoers.d/claude \
    && mkdir -p /home/claude/.local/bin /home/claude/.ssh /home/claude/.config /home/claude/.cache/uv /home/claude/.uv-tools \
    && ln -s /usr/local/bin/claude /home/claude/.local/bin/claude \
    && ssh-keyscan -t ed25519,rsa github.com >> /home/claude/.ssh/known_hosts 2>/dev/null || true \
    && chown -R claude:claude /home/claude/.local /home/claude/.ssh /home/claude/.config /home/claude/.cache /home/claude/.uv-tools

# Install bun (fast JS runtime — needed for bunx-based statusline commands and general use)
# SHA256 fetched 2026-04-30 from https://bun.sh/install
ARG BUN_INSTALLER_SHA256=bab8acfb046aac8c72407bdcce903957665d655d7acaa3e11c7c4616beae68dd
RUN curl -fsSL https://bun.sh/install -o /tmp/install.sh && \
    echo "${BUN_INSTALLER_SHA256}  /tmp/install.sh" | sha256sum -c - && \
    bash /tmp/install.sh && \
    rm /tmp/install.sh \
    && cp /root/.bun/bin/bun /usr/local/bin/bun \
    && cp /root/.bun/bin/bunx /usr/local/bin/bunx \
    && chmod +x /usr/local/bin/bun /usr/local/bin/bunx

# Create volume permission repair script (named volumes may retain stale UIDs
# from older image builds — this fixes ownership on container start)
RUN printf '#!/bin/bash\nchown -R claude:claude /home/claude/.cache/uv /home/claude/.uv-tools 2>/dev/null || true\n' \
    > /usr/local/bin/fix-volume-perms.sh \
    && chmod +x /usr/local/bin/fix-volume-perms.sh

# Copy scripts
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/init-firewall.sh

ENV PATH="/home/claude/.local/bin:${PATH}"

USER claude
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
