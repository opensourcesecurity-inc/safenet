#!/bin/bash
# =============================================================================
# SafeNet DNS Blocklist Updater
# =============================================================================
# Purpose: Download OSS blocklist and convert to Unbound local-zone format
# Location: /opt/oss-blocklists/scripts/update-safenet-dns.sh
#
# Process:
# 1. Download combined blocklist from oss-blocklist.net
# 2. Download whitelist (customer exceptions)
# 3. Validate domain format (reject malformed entries)
# 4. Remove whitelisted domains
# 5. Convert to Unbound local-zone format
# 6. Validate config with unbound-checkconf
# 7. Reload Unbound
#
# Cron: Daily at 2:15 AM Chicago time
# =============================================================================

set -e

# Configuration
BLOCKLIST_URL="http://oss-blocklist.net/dns/dns-combined.txt"
WHITELIST_URL="http://oss-blocklist.net/dns/dns-whitelist.txt"
OUTPUT_FILE="/etc/unbound/unbound.conf.d/oss-blocklist.conf"
TEMP_FILE="/tmp/oss-blocklist-download.txt"
WHITELIST_FILE="/tmp/oss-whitelist-download.txt"
VALIDATED_FILE="/tmp/oss-blocklist-validated.txt"
LOG_FILE="/opt/oss-blocklists/logs/safenet-dns-update.log"

timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

echo "$(timestamp) - Starting SafeNet DNS blocklist update" >> "$LOG_FILE"

# Download blocklist
echo "$(timestamp) - Downloading blocklist from $BLOCKLIST_URL" >> "$LOG_FILE"
if ! curl -s -f -o "$TEMP_FILE" "$BLOCKLIST_URL"; then
    echo "$(timestamp) - ERROR: Failed to download blocklist" >> "$LOG_FILE"
    exit 1
fi

# Download whitelist
echo "$(timestamp) - Downloading whitelist from $WHITELIST_URL" >> "$LOG_FILE"
if ! curl -s -f -o "$WHITELIST_FILE" "$WHITELIST_URL"; then
    echo "$(timestamp) - WARNING: Failed to download whitelist, continuing without" >> "$LOG_FILE"
    WHITELIST_FILE="/dev/null"
fi

# Count raw download
RAW_LINES=$(wc -l < "$TEMP_FILE")
echo "$(timestamp) - Downloaded $RAW_LINES raw lines" >> "$LOG_FILE"

# Validate domains - only allow valid domain characters
# Valid: letters, numbers, dots, hyphens
# Invalid: spaces, quotes, parentheses, brackets, slashes, etc.
echo "$(timestamp) - Validating domain format" >> "$LOG_FILE"
grep -v '^#' "$TEMP_FILE" | \
    grep -v '^$' | \
    grep -v '^[[:space:]]*$' | \
    tr '[:upper:]' '[:lower:]' | \
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
    grep -E '^(\*\.)?[a-z0-9]([a-z0-9\.\-]*[a-z0-9])?(\.[a-z]{2,})+$' \
    > "$VALIDATED_FILE" || true

VALID_DOMAINS=$(wc -l < "$VALIDATED_FILE")
REJECTED=$((RAW_LINES - VALID_DOMAINS))
echo "$(timestamp) - Validated $VALID_DOMAINS domains ($REJECTED rejected as malformed)" >> "$LOG_FILE"

# Count whitelist
WHITELIST_COUNT=$(grep -v '^#' "$WHITELIST_FILE" 2>/dev/null | grep -v '^$' | wc -l || echo "0")
echo "$(timestamp) - Whitelist contains $WHITELIST_COUNT domains" >> "$LOG_FILE"

# Convert to Unbound local-zone format (excluding whitelist)
echo "$(timestamp) - Converting to Unbound format" >> "$LOG_FILE"
{
    echo "# OSS SafeNet DNS Blocklist"
    echo "# Generated: $(timestamp)"
    echo "# Source: $BLOCKLIST_URL"
    echo "# Whitelist: $WHITELIST_URL"
    echo "# Valid domains: $VALID_DOMAINS (rejected $REJECTED malformed)"
    echo "server:"

    # Filter out whitelisted domains
    if [ -s "$WHITELIST_FILE" ] && [ "$WHITELIST_FILE" != "/dev/null" ]; then
        grep -v -F -x -f <(grep -v '^#' "$WHITELIST_FILE" | grep -v '^$' | tr '[:upper:]' '[:lower:]') "$VALIDATED_FILE" | \
        while read -r domain; do
            echo "    local-zone: \"$domain\" refuse"
        done
    else
        while read -r domain; do
            echo "    local-zone: \"$domain\" refuse"
        done < "$VALIDATED_FILE"
    fi
} > "${OUTPUT_FILE}.tmp"

# Count after filtering
FINAL_COUNT=$(grep -c 'local-zone' "${OUTPUT_FILE}.tmp" || echo "0")
WHITELISTED=$((VALID_DOMAINS - FINAL_COUNT))
echo "$(timestamp) - Final count: $FINAL_COUNT domains ($WHITELISTED removed by whitelist)" >> "$LOG_FILE"

# Validate the NEW config file before applying
echo "$(timestamp) - Validating new Unbound configuration" >> "$LOG_FILE"
if ! unbound-checkconf "${OUTPUT_FILE}.tmp" > /dev/null 2>&1; then
    echo "$(timestamp) - ERROR: Invalid Unbound config in new file, keeping old blocklist" >> "$LOG_FILE"
    echo "$(timestamp) - Running checkconf for details:" >> "$LOG_FILE"
    unbound-checkconf "${OUTPUT_FILE}.tmp" >> "$LOG_FILE" 2>&1 || true
    rm -f "${OUTPUT_FILE}.tmp" "$TEMP_FILE" "$WHITELIST_FILE" "$VALIDATED_FILE"
    exit 1
fi
echo "$(timestamp) - Validation passed" >> "$LOG_FILE"

# Move new config into place
mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

# Reload Unbound
echo "$(timestamp) - Reloading Unbound" >> "$LOG_FILE"
if systemctl reload unbound; then
    echo "$(timestamp) - SUCCESS: Blocklist updated with $FINAL_COUNT domains" >> "$LOG_FILE"
else
    echo "$(timestamp) - ERROR: Failed to reload Unbound" >> "$LOG_FILE"
    exit 1
fi

# Cleanup
rm -f "$TEMP_FILE" "$WHITELIST_FILE" "$VALIDATED_FILE"

echo "$(timestamp) - Update complete" >> "$LOG_FILE"
