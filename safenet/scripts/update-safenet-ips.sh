#!/bin/bash
# =============================================================================
# SafeNet IP Blocklist Updater
# =============================================================================
# Purpose: Download OSS IP blocklist and load into ipset for iptables blocking
# Location: /opt/oss-blocklists/scripts/update-safenet-ips.sh
#
# Process:
# 1. Download combined IP blocklist from oss-blocklist.net
# 2. Create or flush ipset
# 3. Load IPs into ipset
# 4. Ensure iptables rules reference ipset
#
# The ipset is referenced by iptables FORWARD chain rules to drop
# traffic to/from known malicious IPs.
#
# Cron: Daily at 2:20 AM Chicago time
# =============================================================================

set -e

# Configuration
BLOCKLIST_URL="http://oss-blocklist.net/ip/ip-combined.txt"
IPSET_NAME="oss-blocklist"
TEMP_FILE="/tmp/oss-ip-blocklist.txt"
LOG_FILE="/opt/oss-blocklists/logs/safenet-ip-update.log"

timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

echo "$(timestamp) - Starting SafeNet IP blocklist update" >> "$LOG_FILE"

# Download blocklist
echo "$(timestamp) - Downloading blocklist from $BLOCKLIST_URL" >> "$LOG_FILE"
if ! curl -s -f -o "$TEMP_FILE" "$BLOCKLIST_URL"; then
    echo "$(timestamp) - ERROR: Failed to download blocklist" >> "$LOG_FILE"
    exit 1
fi

# Count IPs
IP_COUNT=$(wc -l < "$TEMP_FILE")
echo "$(timestamp) - Downloaded $IP_COUNT IPs" >> "$LOG_FILE"

# Create new ipset (or flush existing)
if ipset list "$IPSET_NAME" > /dev/null 2>&1; then
    echo "$(timestamp) - Flushing existing ipset" >> "$LOG_FILE"
    ipset flush "$IPSET_NAME"
else
    echo "$(timestamp) - Creating new ipset" >> "$LOG_FILE"
    ipset create "$IPSET_NAME" hash:net maxelem 100000
fi

# Load IPs into ipset
echo "$(timestamp) - Loading IPs into ipset" >> "$LOG_FILE"
while read -r ip; do
    # Skip empty lines and comments
    [[ -z "$ip" || "$ip" =~ ^# ]] && continue
    ipset add "$IPSET_NAME" "$ip" 2>/dev/null || true
done < "$TEMP_FILE"

# Verify ipset has entries
LOADED=$(ipset list "$IPSET_NAME" | grep -c "^[0-9]" || echo "0")
echo "$(timestamp) - Loaded $LOADED IPs into ipset" >> "$LOG_FILE"

# Add iptables rule if not exists
if ! iptables -C FORWARD -m set --match-set "$IPSET_NAME" dst -j DROP 2>/dev/null; then
    echo "$(timestamp) - Adding iptables FORWARD rule (outbound)" >> "$LOG_FILE"
    iptables -I FORWARD 1 -m set --match-set "$IPSET_NAME" dst -j DROP
fi

if ! iptables -C FORWARD -m set --match-set "$IPSET_NAME" src -j DROP 2>/dev/null; then
    echo "$(timestamp) - Adding iptables FORWARD rule (inbound)" >> "$LOG_FILE"
    iptables -I FORWARD 1 -m set --match-set "$IPSET_NAME" src -j DROP
fi

# Cleanup
rm -f "$TEMP_FILE"

echo "$(timestamp) - SUCCESS: IP blocklist updated with $IP_COUNT IPs" >> "$LOG_FILE"
