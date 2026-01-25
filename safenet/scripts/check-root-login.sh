#!/bin/bash
# =============================================================================
# Root Login Detector
# =============================================================================
# Purpose: Detect NEW root SSH logins and alert via ntfy
# Location: /usr/local/bin/check-root-login
#
# This script maintains state so it only alerts on NEW logins,
# not every time Monit checks. Without state tracking, you'd get
# repeated alerts for the same login.
#
# Exit codes:
# - 0: No new login detected
# - 1: New login detected (triggers Monit alert)
#
# Called by: Monit (safenet-security.conf) every 2 cycles
# =============================================================================

STATE_FILE="/var/lib/monit/last-root-login"
AUTH_LOG="/var/log/auth.log"

# Get the latest root SSH login line
LATEST=$(grep "Accepted publickey for root" "$AUTH_LOG" | tail -1)

# If no logins found, exit OK
[ -z "$LATEST" ] && exit 0

# Compare with last known login
if [ -f "$STATE_FILE" ]; then
    LAST_KNOWN=$(cat "$STATE_FILE")
    if [ "$LATEST" != "$LAST_KNOWN" ]; then
        # New login detected!
        echo "$LATEST" > "$STATE_FILE"
        # Extract IP and time from the log line
        LOGIN_INFO=$(echo "$LATEST" | grep -oP 'from \K[0-9.]+')
        /usr/local/bin/monit-ntfy-alert "ROOT SSH LOGIN" "New SSH login from: $LOGIN_INFO" "high" "key"
        exit 1
    fi
else
    # First run - save current state without alerting
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$LATEST" > "$STATE_FILE"
fi

exit 0
