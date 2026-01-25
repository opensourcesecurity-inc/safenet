#!/bin/bash
# =============================================================================
# SafeNet Peer Bandwidth Statistics
# =============================================================================
# Purpose: Generate JSON with per-peer bandwidth stats for admin dashboard
# Location: /usr/local/bin/get-peer-stats.sh
#
# Output: JSON array with peer data sorted by total transfer
# Used by: Admin dashboard (/var/www/admin/peer-stats.json)
#
# Fields per peer:
# - rank: Position by total bandwidth
# - client_num: Client number (from IP)
# - customer_name: From CSV database
# - tunnel_ip: 10.200.0.X
# - rx_mb / tx_mb / total_mb: Bandwidth in MB
# - last_seen: Human-readable time since last handshake
#
# Cron: Every minute
# =============================================================================

# REDACTED: Path contains customer data
CSV_FILE="/root/safenet-customers.csv"
OUTPUT_FILE="/var/www/admin/peer-stats.json"
TEMP_FILE="/tmp/peer-stats-temp.json"

# Start JSON array
echo '[' > "$TEMP_FILE"
FIRST=true

# Get WireGuard peer data and process each peer (skip first line which is interface info)
wg show wg0 dump | tail -n +2 | while IFS=$'\t' read -r pubkey preshared endpoint allowed_ips latest_handshake rx_bytes tx_bytes keepalive; do

    # Skip if no allowed_ips (shouldn't happen but safety check)
    [ -z "$allowed_ips" ] && continue

    # Extract tunnel IP from allowed_ips (remove /32)
    TUNNEL_IP=$(echo "$allowed_ips" | cut -d'/' -f1)

    # Look up customer info from CSV using EXACT match on IP field (column 2)
    # Format: Client_Number,IP_Address,Customer_Name,Vault_Serial,Email,Public_Key,Date_Added
    CUSTOMER_INFO=$(awk -F',' -v ip="$TUNNEL_IP" '$2 == ip {print; exit}' "$CSV_FILE" 2>/dev/null)

    if [ -n "$CUSTOMER_INFO" ]; then
        CLIENT_NUM=$(echo "$CUSTOMER_INFO" | cut -d',' -f1)
        # Extract customer name (field 3) and remove quotes
        CUSTOMER_NAME=$(echo "$CUSTOMER_INFO" | cut -d',' -f3 | tr -d '"')
    else
        CLIENT_NUM=""
        CUSTOMER_NAME="Unknown"
    fi

    # Calculate total transfer (rx + tx in bytes)
    TOTAL_BYTES=$((rx_bytes + tx_bytes))

    # Convert bytes to MB
    RX_MB=$(echo "scale=2; $rx_bytes / 1048576" | bc)
    TX_MB=$(echo "scale=2; $tx_bytes / 1048576" | bc)
    TOTAL_MB=$(echo "scale=2; $TOTAL_BYTES / 1048576" | bc)

    # Time since last handshake
    if [ "$latest_handshake" -eq 0 ] 2>/dev/null; then
        LAST_SEEN="Never"
    else
        SECONDS_AGO=$(($(date +%s) - latest_handshake))
        if [ $SECONDS_AGO -lt 60 ]; then
            LAST_SEEN="${SECONDS_AGO}s ago"
        elif [ $SECONDS_AGO -lt 3600 ]; then
            LAST_SEEN="$((SECONDS_AGO / 60))m ago"
        elif [ $SECONDS_AGO -lt 86400 ]; then
            LAST_SEEN="$((SECONDS_AGO / 3600))h ago"
        else
            LAST_SEEN="$((SECONDS_AGO / 86400))d ago"
        fi
    fi

    # Add comma before all entries except first
    if [ "$FIRST" = false ]; then
        echo ',' >> "$TEMP_FILE"
    fi
    FIRST=false

    # Write JSON object (escape any special characters in customer name)
    CUSTOMER_NAME_ESCAPED=$(echo "$CUSTOMER_NAME" | sed 's/"/\\"/g' | tr -d '\n')

    cat >> "$TEMP_FILE" << JSONEOF
  {
    "rank": 0,
    "client_num": "$CLIENT_NUM",
    "customer_name": "$CUSTOMER_NAME_ESCAPED",
    "tunnel_ip": "$TUNNEL_IP",
    "rx_mb": $RX_MB,
    "tx_mb": $TX_MB,
    "total_mb": $TOTAL_MB,
    "last_seen": "$LAST_SEEN"
  }
JSONEOF

done

echo ']' >> "$TEMP_FILE"

# Sort by total_mb (descending) and add rank numbers
if jq 'sort_by(.total_mb) | reverse | to_entries | map(.value + {rank: (.key + 1)})' "$TEMP_FILE" > "${OUTPUT_FILE}.tmp" 2>/dev/null; then
    mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
else
    # If jq fails, just use unsorted data
    mv "$TEMP_FILE" "$OUTPUT_FILE"
fi

chmod 644 "$OUTPUT_FILE"
rm -f "$TEMP_FILE" "${OUTPUT_FILE}.tmp" 2>/dev/null
