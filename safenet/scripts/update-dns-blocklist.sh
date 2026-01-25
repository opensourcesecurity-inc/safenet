#!/bin/bash
# =============================================================================
# OSS DNS Blocklist Aggregator
# =============================================================================
# Purpose: Pull from multiple curated sources, deduplicate, output combined list
# Location: /opt/oss-blocklists/scripts/update-dns-blocklist.sh
#
# Sources:
# - Hagezi Pro++ and TIF (aggressive malware/tracking)
# - OISD Big (balanced, low false positives)
# - Steven Black Unified (conservative malware/adware)
# - 1Hosts Pro (malware/tracking/suspicious)
# - AdGuard DNS (ads and trackers)
#
# Output: ~850,000+ unique domains after deduplication
# Supports whitelist overrides for customer exceptions.
#
# Cron: Daily at 2:05 AM Chicago time
# =============================================================================

SCRIPT_DIR="/opt/oss-blocklists"
SOURCE_DIR="${SCRIPT_DIR}/sources"
OUTPUT_DIR="${SCRIPT_DIR}/output/dns"
LOG_FILE="${SCRIPT_DIR}/logs/dns-update.log"
TEMP_FILE="${SOURCE_DIR}/dns-temp-combined.txt"
OUTPUT_FILE="${OUTPUT_DIR}/combined.txt"
WHITELIST_FILE="${OUTPUT_DIR}/whitelist.txt"

timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

log() {
    echo "[$(timestamp)] $1" | tee -a "$LOG_FILE"
}

declare -A SOURCES=(
    ["Hagezi Pro++"]="https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/domains/pro.plus.txt"
    ["Hagezi TIF"]="https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/domains/tif.txt"
    ["OISD Big"]="https://big.oisd.nl/domainswild"
    ["Steven Black Unified"]="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
    ["1Hosts Pro"]="https://o0.pages.dev/Pro/domains.txt"
    ["AdGuard DNS"]="https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"
)

if [[ "$1" == "--interactive" ]] || [[ "$1" == "-i" ]]; then
    echo "=== OSS DNS Blocklist Sources ==="
    echo ""
    for source in "${!SOURCES[@]}"; do
        echo "  ✓ $source"
        echo "    ${SOURCES[$source]}"
        echo ""
    done
    echo "Current sources will be used. To modify, edit the script at:"
    echo "/opt/oss-blocklists/scripts/update-dns-blocklist.sh"
    echo ""
    read -p "Continue with update? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Update cancelled."
        exit 0
    fi
fi

log "=== Starting DNS blocklist update ==="

mkdir -p "$SOURCE_DIR"
mkdir -p "$OUTPUT_DIR"

if [[ ! -f "$WHITELIST_FILE" ]]; then
    log "Creating whitelist file..."
    cat > "$WHITELIST_FILE" << 'WHITELIST_EOF'
# OSS DNS Whitelist
# Domains listed here will NEVER be blocked
# Add one domain per line (without www.)
#
# Example customer exceptions:
# mybank.com
# important-site.com
WHITELIST_EOF
fi

> "$TEMP_FILE"

for source_name in "${!SOURCES[@]}"; do
    log "Downloading $source_name..."
    url="${SOURCES[$source_name]}"

    if [[ "$source_name" == "Steven Black Unified" ]]; then
        curl -sL "$url" | grep "^0.0.0.0" | awk '{print $2}' >> "$TEMP_FILE"
    elif [[ "$source_name" == "AdGuard DNS" ]]; then
        # AdGuard uses different format: ||domain.com^
        curl -sL "$url" | grep "^||" | sed 's/||//g' | sed 's/\^.*//g' >> "$TEMP_FILE"
    else
        curl -sL "$url" >> "$TEMP_FILE"
    fi
done

if [[ -f "${SOURCE_DIR}/oss-custom-additions.txt" ]]; then
    log "Adding OSS custom security additions..."
    cat "${SOURCE_DIR}/oss-custom-additions.txt" >> "$TEMP_FILE"
fi

log "Processing and deduplicating..."

RAW_COUNT=$(wc -l < "$TEMP_FILE")
log "Raw entries from all sources: ${RAW_COUNT}"

cat "$TEMP_FILE" | \
    grep -v "^#" | \
    grep -v "^!" | \
    grep -v "^$" | \
    grep -v "localhost" | \
    grep -v "127.0.0.1" | \
    grep -v "::1" | \
    grep -v "0.0.0.0 0.0.0.0" | \
    sed 's/^0.0.0.0 //' | \
    sed 's/^127.0.0.1 //' | \
    tr '[:upper:]' '[:lower:]' | \
    sed 's/^www\.//' | \
    sort -u > "${OUTPUT_FILE}.tmp"

WWW_STRIPPED_COUNT=$(wc -l < "${OUTPUT_FILE}.tmp")
log "After www. stripping and dedupe: ${WWW_STRIPPED_COUNT}"

log "Applying whitelist overrides..."
if [[ -s "$WHITELIST_FILE" ]]; then
    WHITELIST_COUNT=$(grep -v "^#" "$WHITELIST_FILE" | grep -v "^$" | wc -l)

    if [[ $WHITELIST_COUNT -gt 0 ]]; then
        log "Found $WHITELIST_COUNT whitelisted domains"
        grep -vFf <(grep -v "^#" "$WHITELIST_FILE" | grep -v "^$") "${OUTPUT_FILE}.tmp" > "$OUTPUT_FILE"
    else
        log "No whitelist entries found"
        mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
    fi
else
    mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
fi

DOMAIN_COUNT=$(wc -l < "$OUTPUT_FILE")

log "DNS blocklist updated: ${DOMAIN_COUNT} unique domains"
log "Reduction from processing: $((RAW_COUNT - DOMAIN_COUNT)) duplicates/invalid removed"

cp "$OUTPUT_FILE" /var/www/oss-blocklists/dns-combined.txt
cp "$WHITELIST_FILE" /var/www/oss-blocklists/dns-whitelist.txt

log "Files published to web root"
log "=== DNS blocklist update complete ==="

rm -f "$TEMP_FILE"
rm -f "${OUTPUT_FILE}.tmp"
