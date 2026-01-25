#!/bin/bash
# =============================================================================
# SafeNet WireGuard Server Setup
# =============================================================================
# Purpose: Initialize WireGuard server with keys and base configuration
# Location: /root/safenet-wireguard-setup.sh
#
# Run once after hardening script to set up WireGuard.
# Generates server keys and creates initial wg0.conf.
#
# After running:
# - Server public key displayed (save this!)
# - WireGuard service enabled and started
# - Ready to add clients via add-safenet-client.sh
# =============================================================================

echo "=== SafeNet WireGuard Setup ==="
echo ""

# Generate server keys
echo "[1/4] Generating WireGuard keys..."
cd /etc/wireguard
umask 077
wg genkey | tee server_private.key | wg pubkey > server_public.key

PRIVATE_KEY=$(cat server_private.key)
PUBLIC_KEY=$(cat server_public.key)

echo "Server Public Key: $PUBLIC_KEY"
echo ""

# Create WireGuard config
echo "[2/4] Creating WireGuard configuration..."
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 10.200.0.1/24
ListenPort = 51820
PrivateKey = $PRIVATE_KEY

# Routing and NAT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o nic1 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o nic1 -j MASQUERADE

# Peer configurations added via add-safenet-client.sh
EOF

chmod 600 /etc/wireguard/wg0.conf

# Enable WireGuard
echo "[3/4] Enabling WireGuard service..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Verify
echo "[4/4] Verifying..."
sleep 2
wg show

echo ""
echo "=== WireGuard Running! ==="
echo "Server Public Key: $PUBLIC_KEY"
echo ""
echo "IMPORTANT: Save this public key! Customers need it for their configs."
echo ""
