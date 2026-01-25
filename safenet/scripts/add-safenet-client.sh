#!/bin/bash
# =============================================================================
# SafeNet Client Add Helper Script
# =============================================================================
# Purpose: Add new WireGuard peer with customer tracking
# Location: /root/add-safenet-client.sh
#
# Usage:
#   ./add-safenet-client.sh <pubkey> <client_num> <name> [vault_serial] [email]
#
# Examples:
#   ./add-safenet-client.sh "Abc123...=" 15 "John Doe" "V1410-12345" "john@example.com"
#   ./add-safenet-client.sh "Abc123...=" 15 "Jane Smith" "VP2430-67890"
#   ./add-safenet-client.sh "Abc123...=" 15 "Bob's Vault"
#
# This script:
# 1. Adds peer to live WireGuard interface
# 2. Saves peer to wg0.conf with customer comments
# 3. Logs to CSV database for easy searching
# 4. Outputs client config for customer
#
# Note: The Flask API (app.py) is the preferred method for adding clients.
# This script is for manual/emergency additions.
# =============================================================================

# Color output for readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check arguments (minimum 3 required)
if [ $# -lt 3 ]; then
    echo -e "${RED}Error: Wrong number of arguments${NC}"
    echo "Usage: $0 <client_pubkey> <client_number> <customer_name> [vault_serial] [email]"
    echo ""
    echo "Examples:"
    echo "  $0 \"Abc123XYZ...=\" 15 \"John Doe\" \"V1410-12345\" \"john@example.com\""
    echo "  $0 \"Abc123XYZ...=\" 15 \"Jane Smith\" \"VP2430-67890\""
    echo "  $0 \"Abc123XYZ...=\" 15 \"Bob's Vault\""
    exit 1
fi

PUBKEY=$1
CLIENT_NUM=$2
CUSTOMER_NAME=$3
VAULT_SERIAL=${4:-"Not provided"}
EMAIL=${5:-"Not provided"}
CLIENT_IP="10.200.0.$CLIENT_NUM"
SERVER_PUBKEY=$(cat /etc/wireguard/server_public.key)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Validate client number (2-254)
if [ $CLIENT_NUM -lt 2 ] || [ $CLIENT_NUM -gt 254 ]; then
    echo -e "${RED}Error: Client number must be between 2 and 254${NC}"
    exit 1
fi

# Check if IP already assigned
if wg show wg0 | grep -q "allowed ips:.*$CLIENT_IP/32"; then
    echo -e "${YELLOW}Warning: IP $CLIENT_IP already assigned!${NC}"
    echo "Current peers:"
    wg show wg0 | grep "allowed ips"
    read -p "Continue anyway? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Add peer to WireGuard
echo -e "${YELLOW}Adding client #$CLIENT_NUM ($CLIENT_IP)...${NC}"
wg set wg0 peer "$PUBKEY" allowed-ips $CLIENT_IP/32

# Save configuration (this creates the base file)
wg-quick save wg0

# Now add customer tracking comments to the config file
# Find the peer entry and add comments above it
TEMP_FILE=$(mktemp)
PEER_FOUND=false

while IFS= read -r line; do
    # If we find this peer's public key, add comments above it
    if [[ "$line" == *"$PUBKEY"* ]] && [ "$PEER_FOUND" = false ]; then
        echo "" >> "$TEMP_FILE"
        echo "# Customer: $CUSTOMER_NAME" >> "$TEMP_FILE"
        echo "# Client #: $CLIENT_NUM" >> "$TEMP_FILE"
        echo "# Vault Serial: $VAULT_SERIAL" >> "$TEMP_FILE"
        echo "# Email: $EMAIL" >> "$TEMP_FILE"
        echo "# Added: $TIMESTAMP" >> "$TEMP_FILE"
        PEER_FOUND=true
    fi
    echo "$line" >> "$TEMP_FILE"
done < /etc/wireguard/wg0.conf

# Replace original config with annotated version
mv "$TEMP_FILE" /etc/wireguard/wg0.conf

# Also log to CSV database for easy searching
CSV_FILE="/root/safenet-customers.csv"
if [ ! -f "$CSV_FILE" ]; then
    echo "Client_Number,IP_Address,Customer_Name,Vault_Serial,Email,Public_Key,Date_Added" > "$CSV_FILE"
fi
echo "$CLIENT_NUM,$CLIENT_IP,\"$CUSTOMER_NAME\",\"$VAULT_SERIAL\",\"$EMAIL\",\"$PUBKEY\",\"$TIMESTAMP\"" >> "$CSV_FILE"

# Verify it was added
if wg show wg0 | grep -q "$PUBKEY"; then
    echo -e "${GREEN}✅ Client added successfully!${NC}"
else
    echo -e "${RED}❌ Failed to add client${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=== Configuration for Customer ===${NC}"
echo -e "${YELLOW}Copy everything below and send to customer:${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat << CUSTOMER_CONFIG
[Interface]
Address = $CLIENT_IP/32
DNS = 10.200.0.1

[Peer]
PublicKey = $SERVER_PUBKEY
Endpoint = chi.oss-vpn.net:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
CUSTOMER_CONFIG
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${GREEN}Customer Details:${NC}"
echo "  Name: $CUSTOMER_NAME"
echo "  Client #: $CLIENT_NUM"
echo "  Tunnel IP: $CLIENT_IP"
echo "  Vault Serial: $VAULT_SERIAL"
echo "  Email: $EMAIL"
echo "  Public Key: $PUBKEY"
echo ""
echo -e "${YELLOW}Next steps for customer:${NC}"
echo "  1. Add tunnel with config above"
echo "  2. Enable the tunnel"
echo "  3. Test: ping 10.200.0.1"
echo ""
echo -e "${GREEN}Logged to: $CSV_FILE${NC}"
