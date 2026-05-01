#!/bin/bash
set -e

# ── Default-deny egress firewall ──────────────────────────────────
# Only allows outbound connections to whitelisted domains.
# Requires: iptables-legacy, dig (dnsutils)
# Must run as root (via sudo from entrypoint.sh).
# Uses iptables-legacy because Docker Desktop's VM doesn't support nf_tables.

# Constants
readonly FIREWALL_VERIFY_TIMEOUT=5

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

# Validate DNS server is a proper IPv4 address
if [[ ! $DNS_SERVER =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: invalid DNS server '$DNS_SERVER'" >&2
    exit 1
fi

# Flush existing rules
iptables-legacy -F OUTPUT 2>/dev/null || true

# Set default-deny FIRST so the bootstrap window (between flush and final
# rule installation) inherits deny-by-default. Allow rules added below take
# effect via -A; anything not matched falls through to the DROP policy.
iptables-legacy -P OUTPUT DROP

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
    echo "  Allowed: $domain ($(echo "$ips" | tr '\n' ' '))"
done

# Fetch GitHub IP ranges dynamically (CIDR blocks — iptables handles them natively)
echo "  Fetching GitHub IP ranges..."
gh_ranges=$(curl -fsSL https://api.github.com/meta | jq -r '.git[],.api[],.web[]' | grep -E '^[0-9.]+/[0-9]+$')
if [ -z "$gh_ranges" ]; then
    echo "Error: GitHub API returned no valid CIDR ranges" >&2
    exit 1
fi
for cidr in $gh_ranges; do
    iptables-legacy -A OUTPUT -d "$cidr" -j ACCEPT 2>/dev/null && ((ip_count++)) || true
done

# IPv6 default-deny — defense-in-depth in case container IPv6 is enabled.
# We keep no IPv6 allowlist; all IPv4-resolved allowlisted services route over
# v4. If a user explicitly enables container v6 and needs traffic through, they
# must extend this section (and the v4 allowlist) in tandem.
v6_present=true
if ! command -v ip6tables-legacy >/dev/null 2>&1; then
    echo "  WARNING: ip6tables-legacy not present; skipping IPv6 rules (v6 traffic may be unfiltered if enabled)" >&2
    v6_present=false
fi

configure_ipv6_firewall() {
    ip6tables-legacy -F OUTPUT || return 1
    ip6tables-legacy -F INPUT || return 1
    ip6tables-legacy -F FORWARD || return 1
    # Default deny first (same race-avoidance reasoning as v4 above)
    ip6tables-legacy -P INPUT DROP || return 1
    ip6tables-legacy -P OUTPUT DROP || return 1
    ip6tables-legacy -P FORWARD DROP || return 1
    # Allow loopback
    ip6tables-legacy -A INPUT -i lo -j ACCEPT || return 1
    ip6tables-legacy -A OUTPUT -o lo -j ACCEPT || return 1
    # Allow established/related return traffic
    ip6tables-legacy -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT || return 1
    ip6tables-legacy -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT || return 1
}

if [[ $v6_present == "true" ]]; then
    # SC2310: we WANT set -e suppression here — a kernel without v6 support
    # should warn-and-continue, not abort the script.
    # shellcheck disable=SC2310
    if configure_ipv6_firewall; then
        echo "  IPv6: default-deny applied"
    else
        echo "  WARNING: ip6tables-legacy commands failed (kernel may lack v6 support); v6 traffic may be unfiltered if enabled" >&2
        v6_present=false
    fi
fi

echo "=== Firewall active: $ip_count rules added ==="

# Post-check: verify the OUTPUT chain is actually default-DROP. A regression
# that loses the policy line while keeping ACCEPT rules would silently leave
# the container fully open, so we assert the policy itself.
if ! iptables-legacy -L OUTPUT -n | head -1 | grep -q '(policy DROP)'; then
    echo "ERROR: iptables OUTPUT policy is not DROP after firewall init" >&2
    exit 1
fi
if [[ $v6_present == "true" ]]; then
    if ! ip6tables-legacy -L OUTPUT -n | head -1 | grep -q '(policy DROP)'; then
        echo "ERROR: ip6tables OUTPUT policy is not DROP after firewall init" >&2
        exit 1
    fi
fi

# Verification
echo "=== Verifying firewall ==="
if curl -s --max-time "$FIREWALL_VERIFY_TIMEOUT" https://api.anthropic.com >/dev/null 2>&1; then
    echo "  ok api.anthropic.com: reachable"
else
    echo "  FAIL api.anthropic.com: BLOCKED (this is a problem)"
fi
