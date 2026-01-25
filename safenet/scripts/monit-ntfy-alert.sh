#!/bin/bash
# =============================================================================
# Monit ntfy Alert Script
# =============================================================================
# Purpose: Send push notifications via ntfy for Monit alerts
# Location: /usr/local/bin/monit-ntfy-alert
#
# Usage: monit-ntfy-alert "title" "message" "priority" "tags"
#
# Priority levels: urgent, high, default, low, min
# Tags: emoji shortcodes (e.g., warning, rotating_light, skull)
#
# Called by Monit service checks when conditions are met.
# =============================================================================

# REDACTED: Replace with your ntfy server and topic
NTFY_URL="http://ntfy.chi.oss-vpn.net/REDACTED_NTFY_TOPIC"

TITLE="${1:-SafeNet Alert}"
MESSAGE="${2:-An alert was triggered}"
PRIORITY="${3:-high}"
TAGS="${4:-warning}"

curl -s -X POST "$NTFY_URL" \
  -H "Title: $TITLE" \
  -H "Priority: $PRIORITY" \
  -H "Tags: $TAGS" \
  -d "$MESSAGE"
