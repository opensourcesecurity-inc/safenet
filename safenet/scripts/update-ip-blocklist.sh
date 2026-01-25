#!/bin/bash
# =============================================================================
# OSS IP Blocklist Aggregator
# =============================================================================
# Purpose: Pull from multiple IP threat intelligence sources
# Location: /opt/oss-blocklists/scripts/update-ip-blocklist.sh
#
# Sources:
# - Spamhaus DROP (hijacked networks, criminal operations)
# - DShield Top 20 (active attackers from real-world data)
# - Hagezi Threat Intelligence (C2 servers, malware hosting)
#
# Output: ~46,000+ unique malicious IPs
#
# Cron: Daily at 2:10 AM Chicago time
# =============================================================================

SCRIPT_DIR="/opt/oss-blocklists"
SOURCE_DIR="${SCRIPT_DIR}/sources"
OUTPUT_DIR="${SCRIPT_DIR}/output/ip"
LOG_FILE="${SCRIPT_DIR}/logs/ip-update.log"
TEMP_DIR="${SOURCE_DIR}/ip-temp"
OUTPUT_FILE="${OUTPUT_DIR}/ip-combined.txt"

timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

log() {
    echo "[$(timestamp)] $1" | tee -a "$LOG_FILE"
}

log "=== Starting IP blocklist update ==="

mkdir -p "$SOURCE_DIR"
mkdir -p "$OUTPUT_DIR"
mkdir -p "$TEMP_DIR"

# Download Spamhaus DROP
log "Downloading Spamhaus DROP..."
curl -s https://www.spamhaus.org/drop/drop.txt | \
    grep -v '^;' | \
    grep -v '^$' | \
    awk '{print $1}' | \
    cut -d'/' -f1 > "${TEMP_DIR}/spamhaus.txt"

# Download DShield Top 20
log "Downloading DShield Top 20..."
curl -s https://feeds.dshield.org/block.txt | \
    grep -v '^#' | \
    grep -v '^$' | \
    awk '{print $1}' > "${TEMP_DIR}/dshield.txt"

# Download Hagezi Threat Intelligence
log "Downloading Hagezi Threat Intelligence..."
curl -s https://raw.githubusercontent.com/hagezi/dns-blocklists/main/ips/tif.txt | \
    grep -v '^#' | \
    grep -v '^$' > "${TEMP_DIR}/hagezi.txt"

# Combine and deduplicate
log "Combining and deduplicating..."
cat "${TEMP_DIR}/spamhaus.txt" \
    "${TEMP_DIR}/dshield.txt" \
    "${TEMP_DIR}/hagezi.txt" | \
    sort -u > "$OUTPUT_FILE"

# Count results
IP_COUNT=$(wc -l < "$OUTPUT_FILE")
log "IP blocklist updated: ${IP_COUNT} unique IPs"

# Copy to web root for nginx
cp "$OUTPUT_FILE" /var/www/oss-blocklists/ip-combined.txt

log "Files published to web root"
log "=== IP blocklist update complete ==="

# Cleanup temp files
rm -rf "$TEMP_DIR"
