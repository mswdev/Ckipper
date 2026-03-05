#!/bin/bash
set -e

# ── Default-deny egress firewall ──────────────────────────────────
# Only allows outbound connections to whitelisted domains.
# Requires: iptables-legacy, dig (dnsutils)
# Must run as root (via sudo from entrypoint.sh).
# Uses iptables-legacy because Docker Desktop's VM doesn't support nf_tables.

# Whitelisted domains — edit this list to add/remove allowed destinations
ALLOWED_DOMAINS=(
    # Claude / Anthropic
    "api.anthropic.com"
    "statsig.anthropic.com"
    "sentry.io"

    # Package registries
    "registry.npmjs.org"
    "pypi.org"
    "files.pythonhosted.org"

    # GitHub
    "github.com"
    "api.github.com"
    "objects.githubusercontent.com"
    "raw.githubusercontent.com"

    # MCP services
    "mcp.atlassian.com"
    "mcp.clerk.com"
    "api.clerk.com"
    "api.figma.com"
    "api.clickup.com"
    "context7.com"

    # Monitoring & other
    "o4507371075665920.ingest.us.sentry.io"
    "fonts.googleapis.com"
    "fonts.gstatic.com"
)

echo "=== Configuring egress firewall ==="

# Detect DNS server from resolv.conf (Docker Desktop uses 192.168.65.x, not 127.0.0.11)
DNS_SERVER=$(grep '^nameserver' /etc/resolv.conf | head -1 | awk '{print $2}')
echo "  DNS server: $DNS_SERVER"

# Flush existing rules
iptables-legacy -F OUTPUT 2>/dev/null || true

# Allow loopback
iptables-legacy -A OUTPUT -o lo -j ACCEPT

# Allow established/related connections
iptables-legacy -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS to the container's resolver (prevents DNS tunneling to other servers)
iptables-legacy -A OUTPUT -p udp --dport 53 -d "$DNS_SERVER" -j ACCEPT
iptables-legacy -A OUTPUT -p tcp --dport 53 -d "$DNS_SERVER" -j ACCEPT

# Resolve each domain and add iptables rules for each IP
ip_count=0
for domain in "${ALLOWED_DOMAINS[@]}"; do
    ips=$(dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.' || true)
    for ip in $ips; do
        iptables-legacy -A OUTPUT -d "$ip" -j ACCEPT 2>/dev/null && ((ip_count++)) || true
    done
    echo "  Allowed: $domain ($(echo $ips | tr '\n' ' '))"
done

# Fetch GitHub IP ranges dynamically (CIDR blocks — iptables handles them natively)
echo "  Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta 2>/dev/null | jq -r '.git[],.api[],.web[]' 2>/dev/null || true)
for cidr in $gh_ranges; do
    iptables-legacy -A OUTPUT -d "$cidr" -j ACCEPT 2>/dev/null && ((ip_count++)) || true
done

# Default deny everything else
iptables-legacy -P OUTPUT DROP

echo "=== Firewall active: $ip_count rules added ==="

# Verification
echo "=== Verifying firewall ==="
if curl -s --max-time 5 https://api.anthropic.com > /dev/null 2>&1; then
    echo "  ok api.anthropic.com: reachable"
else
    echo "  FAIL api.anthropic.com: BLOCKED (this is a problem)"
fi
