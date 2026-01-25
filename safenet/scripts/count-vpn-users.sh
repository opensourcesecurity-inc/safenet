#!/bin/bash
# =============================================================================
# SafeNet Active User Counter
# =============================================================================
# Purpose: Count WireGuard peers with recent handshakes (active connections)
# Location: /usr/local/bin/count-vpn-users.sh
#
# A peer is considered "active" if their last handshake was within 3 minutes.
# This accounts for WireGuard's keepalive interval (25 seconds).
#
# Output: Single integer (number of active peers)
# Used by: Status dashboard (/var/www/status/vpn-count.txt)
#
# Cron: Every minute
# =============================================================================

wg show wg0 latest-handshakes | awk '{
    if ($2 > 0 && (systime() - $2) < 180) count++
} END {
    print count+0
}'
