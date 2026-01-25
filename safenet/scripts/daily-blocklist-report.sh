#!/bin/bash
# =============================================================================
# OSS Daily Blocklist Report
# =============================================================================
# Purpose: Read blocklist counts and send summary to ntfy
# Location: /opt/oss-blocklists/scripts/daily-blocklist-report.sh
#
# Runs AFTER the update scripts complete to report final counts.
# Alerts if files are missing or stale (not updated recently).
#
# Cron: Daily at 2:25 AM Chicago time (after all updates complete)
# =============================================================================

# REDACTED: Replace with your ntfy server and topic
NTFY_URL="http://ntfy.chi.oss-vpn.net/REDACTED_NTFY_TOPIC"

DNS_FILE="/opt/oss-blocklists/output/dns/combined.txt"
IP_FILE="/opt/oss-blocklists/output/ip/ip-combined.txt"

# Get counts
DNS_COUNT=0
IP_COUNT=0
DNS_STATUS="OK"
IP_STATUS="OK"

if [[ -f "$DNS_FILE" ]]; then
    DNS_COUNT=$(wc -l < "$DNS_FILE")
    # Check if file was updated today
    if [[ $(find "$DNS_FILE" -mmin +120 2>/dev/null) ]]; then
        DNS_STATUS="STALE"
    fi
else
    DNS_STATUS="MISSING"
fi

if [[ -f "$IP_FILE" ]]; then
    IP_COUNT=$(wc -l < "$IP_FILE")
    if [[ $(find "$IP_FILE" -mmin +120 2>/dev/null) ]]; then
        IP_STATUS="STALE"
    fi
else
    IP_STATUS="MISSING"
fi

# Format counts with commas
DNS_FORMATTED=$(printf "%'d" "$DNS_COUNT")
IP_FORMATTED=$(printf "%'d" "$IP_COUNT")

# Determine overall status
if [[ "$DNS_STATUS" == "OK" && "$IP_STATUS" == "OK" ]]; then
    TITLE="Blocklist Update Complete"
    PRIORITY="default"
    TAGS="white_check_mark,shield"
    MESSAGE="DNS: ${DNS_FORMATTED} domains
IP: ${IP_FORMATTED} addresses"
else
    TITLE="Blocklist Update PROBLEM"
    PRIORITY="high"
    TAGS="warning,shield"
    MESSAGE="DNS: ${DNS_STATUS} (${DNS_FORMATTED})
IP: ${IP_STATUS} (${IP_FORMATTED})

Check server logs!"
fi

# Send notification
curl -s -X POST "$NTFY_URL" \
    -H "Title: $TITLE" \
    -H "Priority: $PRIORITY" \
    -H "Tags: $TAGS" \
    -d "$MESSAGE"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Report sent - DNS: $DNS_STATUS ($DNS_FORMATTED) | IP: $IP_STATUS ($IP_FORMATTED)"
