#!/bin/bash
# Firewall for a project's dev container: blocks all outbound traffic except Claude Code, VS Code, npm, GitHub and
# the domains in /workspace/.devcontainer/allowed-domains.txt.
# Based on Anthropic's reference init-firewall.sh. Every deviation from it is marked "CHANGE:".
set -euo pipefail
IFS=$'\n\t'

# CHANGE: if this script fails halfway, the network stays CLOSED. The reference script leaves it open.
close_network_on_failure() {
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        iptables -P INPUT DROP; iptables -P FORWARD DROP; iptables -P OUTPUT DROP
        ip6tables -P INPUT DROP 2>/dev/null || true
        ip6tables -P FORWARD DROP 2>/dev/null || true
        ip6tables -P OUTPUT DROP 2>/dev/null || true
        echo "ERROR: the firewall setup did not finish, so the container network is CLOSED." >&2
        echo "Fix the error and run: sudo /usr/local/bin/init-firewall.sh" >&2
    fi
}
trap close_network_on_failure EXIT

# Keep Docker's internal DNS rules
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# CHANGE: safe to run again on a running container (start from open policies, close them at the end)
iptables -P INPUT ACCEPT; iptables -P FORWARD ACCEPT; iptables -P OUTPUT ACCEPT
ip6tables -P INPUT ACCEPT 2>/dev/null || true
ip6tables -P FORWARD ACCEPT 2>/dev/null || true
ip6tables -P OUTPUT ACCEPT 2>/dev/null || true

iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# CHANGE: DNS over TCP too (large answers arrive truncated over UDP)
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -m state --state ESTABLISHED -j ACCEPT
# CHANGE: no outbound SSH to any host. SSH still works to allowed hosts, GitHub included.
# Localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

ipset create allowed-domains hash:net

echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi
if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    # CHANGE: explain GitHub's limit (60 requests per hour without login, shared by every container on your network)
    if echo "$gh_ranges" | grep -qi 'rate limit'; then
        echo "GitHub's hourly limit was reached. Wait a few minutes and run: sudo /usr/local/bin/init-firewall.sh"
    fi
    exit 1
fi
echo "Processing GitHub IPs..."
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
    ipset add allowed-domains "$cidr"
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

add_domain() {
    local domain=$1 ips ip
    echo "Resolving $domain..."
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    if [ -z "$ips" ]; then
        echo "ERROR: Failed to resolve $domain"
        exit 1
    fi
    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
        # CHANGE: -exist, because some domains return the same IP twice
        ipset add -exist allowed-domains "$ip"
    done < <(echo "$ips")
}

# CHANGE: plus the Claude hosts from Anthropic's "Network access requirements" that the reference list doesn't have
# (platform.claude.com is needed for /login)
for domain in \
    "registry.npmjs.org" \
    "api.anthropic.com" \
    "platform.claude.com" \
    "downloads.claude.ai" \
    "claude.ai" \
    "claude.com" \
    "code.claude.com" \
    "sentry.io" \
    "statsig.com" \
    "marketplace.visualstudio.com" \
    "vscode.blob.core.windows.net" \
    "update.code.visualstudio.com"; do
    add_domain "$domain"
done

# CHANGE: the project's own domains, one per line, from a text file (anything after # is ignored)
PROJECT_DOMAINS_FILE="/workspace/.devcontainer/allowed-domains.txt"
if [ -f "$PROJECT_DOMAINS_FILE" ]; then
    while read -r domain || [ -n "$domain" ]; do
        domain="${domain%%#*}"
        domain="$(echo "$domain" | awk '{print $1}')"
        [ -z "$domain" ] && continue
        add_domain "$domain"
    done < "$PROJECT_DOMAINS_FILE"
fi

HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi
HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# CHANGE: IPv6 closed too
if ip6tables -L >/dev/null 2>&1; then
    ip6tables -F
    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -A OUTPUT -o lo -j ACCEPT
    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT DROP
fi

iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
fi
# CHANGE: a second check that doesn't depend on DNS
if curl --connect-timeout 5 https://1.1.1.1 >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://1.1.1.1"
    exit 1
fi
if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
    exit 1
fi
echo "Firewall verification passed"
