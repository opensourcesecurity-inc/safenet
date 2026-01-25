#!/usr/bin/env python3
"""
SafeNet Admin API
=================
Purpose: REST API for managing WireGuard peers
Location: /opt/safenet-admin/app.py

PRIVILEGE SEPARATION:
This Flask app runs as unprivileged 'safenet' user and communicates
with wg-control daemon via Unix socket for any WireGuard operations.
It CANNOT directly modify WireGuard configuration or run wg commands.

Endpoints:
- GET  /peers          - List all peers with stats
- POST /peers          - Add new peer
- DELETE /peers/<id>   - Remove peer (admin only)
- GET  /health         - Health check
- GET  /next-client    - Get next available client number

Access Control:
- ADMIN_IPS: Full access including delete
- ENGINEER_IPS: View and add only

See AIW Part 19 for full architecture documentation.
"""

import os
import re
import csv
import json
import socket
from datetime import datetime
from flask import Flask, jsonify, request, abort

app = Flask(__name__)

# Configuration
WG_CONTROL_SOCKET = "/run/wg-control/wg-control.sock"
CUSTOMER_CSV = "/opt/safenet-admin/customers.csv"
WG_INTERFACE = "wg0"

# Admin IPs - full access including delete
# REDACTED: Replace with actual admin tunnel IPs
ADMIN_IPS = ["10.200.0.2", "10.200.0.3", "10.200.0.4", "10.200.0.5"]

# Engineer IPs - can view and add, but not delete
ENGINEER_IPS = []  # Add engineer tunnel IPs here as they're onboarded


def wg_control(command, **params):
    """Send command to wg-control daemon via Unix socket"""
    request_data = {'command': command, **params}

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(10)
        sock.connect(WG_CONTROL_SOCKET)
        sock.sendall(json.dumps(request_data).encode('utf-8'))

        response = sock.recv(65536).decode('utf-8')
        sock.close()

        return json.loads(response)
    except Exception as e:
        app.logger.error(f"wg-control error: {e}")
        return {'success': False, 'error': str(e)}


def get_client_ip():
    """Get the real client IP from nginx proxy headers"""
    return request.headers.get('X-Real-IP', request.remote_addr)


def is_admin():
    """Check if request is from admin IP"""
    return get_client_ip() in ADMIN_IPS


def is_authorized():
    """Check if request is from admin or engineer IP"""
    client_ip = get_client_ip()
    return client_ip in ADMIN_IPS or client_ip in ENGINEER_IPS


def get_wg_stats():
    """Get live WireGuard statistics via wg-control daemon"""
    stats = {}

    result = wg_control('show')

    if not result.get('success'):
        app.logger.error(f"wg show failed: {result.get('error')}")
        return stats

    output = result.get('output', '')
    lines = output.strip().split('\n')

    # First line is interface info, skip it
    # Peer lines: pubkey, preshared, endpoint, allowed_ips, handshake, rx, tx, keepalive
    for line in lines[1:]:
        parts = line.split('\t')
        if len(parts) >= 8:
            pubkey = parts[0]
            handshake_ts = int(parts[4]) if parts[4] and parts[4] != '0' else None
            rx_bytes = int(parts[5]) if parts[5] else 0
            tx_bytes = int(parts[6]) if parts[6] else 0

            # Calculate online status (handshake within 3 minutes)
            online = False
            if handshake_ts and handshake_ts > 0:
                age = datetime.now().timestamp() - handshake_ts
                online = age < 180

            stats[pubkey] = {
                'endpoint': parts[2] if parts[2] != '(none)' else None,
                'allowed_ips': parts[3],
                'latest_handshake': handshake_ts,
                'rx_bytes': rx_bytes,
                'tx_bytes': tx_bytes,
                'online': online,
            }

    return stats


def parse_wg_conf_from_dump():
    """Parse peer information from wg show dump output"""
    peers = []

    result = wg_control('show')
    if not result.get('success'):
        return peers

    output = result.get('output', '')
    lines = output.strip().split('\n')

    # Load customer data from CSV for enrichment
    customer_data = {}
    if os.path.exists(CUSTOMER_CSV):
        try:
            with open(CUSTOMER_CSV, 'r') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    pubkey = row.get('Public_Key', '')
                    if pubkey:
                        customer_data[pubkey] = row
        except Exception as e:
            app.logger.error(f"Error reading CSV: {e}")

    # Parse peer lines (skip first line which is interface info)
    for line in lines[1:]:
        parts = line.split('\t')
        if len(parts) >= 4:
            pubkey = parts[0]
            allowed_ips = parts[3]

            # Extract IP from allowed_ips
            ip_match = re.search(r'([\d.]+)', allowed_ips)
            ip_address = ip_match.group(1) if ip_match else ''

            # Extract client number from IP
            client_number = 0
            if ip_address:
                ip_parts = ip_address.split('.')
                client_number = int(ip_parts[3]) if len(ip_parts) == 4 else 0

            peer = {
                'public_key': pubkey,
                'public_key_short': pubkey[:12] + '...',
                'allowed_ips': allowed_ips,
                'ip_address': ip_address,
                'client_number': client_number,
                'customer_name': 'Unknown',
                'vault_serial': '',
                'email': '',
                'date_added': '',
            }

            # Enrich with CSV data if available
            if pubkey in customer_data:
                csv_row = customer_data[pubkey]
                peer['customer_name'] = csv_row.get('Customer_Name', 'Unknown')
                peer['vault_serial'] = csv_row.get('Vault_Serial', '')
                peer['email'] = csv_row.get('Email', '')
                peer['date_added'] = csv_row.get('Date_Added', '')

            peers.append(peer)

    return sorted(peers, key=lambda x: x.get('client_number', 0))


def format_bytes(bytes_val):
    """Format bytes to human readable"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_val < 1024:
            return f"{bytes_val:.1f} {unit}"
        bytes_val /= 1024
    return f"{bytes_val:.1f} PB"


@app.route('/peers', methods=['GET'])
def list_peers():
    """List all WireGuard peers with stats"""
    if not is_authorized():
        abort(403, description="Access denied")

    peers = parse_wg_conf_from_dump()
    stats = get_wg_stats()

    online_count = 0

    # Merge stats into peer data
    for peer in peers:
        pubkey = peer.get('public_key')
        if pubkey and pubkey in stats:
            peer_stats = stats[pubkey]
            peer['online'] = peer_stats.get('online', False)
            peer['endpoint'] = peer_stats.get('endpoint')
            peer['rx_bytes'] = peer_stats.get('rx_bytes', 0)
            peer['tx_bytes'] = peer_stats.get('tx_bytes', 0)
            peer['rx_formatted'] = format_bytes(peer_stats.get('rx_bytes', 0))
            peer['tx_formatted'] = format_bytes(peer_stats.get('tx_bytes', 0))
            peer['latest_handshake'] = peer_stats.get('latest_handshake')
            if peer['online']:
                online_count += 1
        else:
            peer['online'] = False
            peer['rx_bytes'] = 0
            peer['tx_bytes'] = 0
            peer['rx_formatted'] = '0 B'
            peer['tx_formatted'] = '0 B'

    return jsonify({
        'peers': peers,
        'total': len(peers),
        'online': online_count,
        'timestamp': datetime.now().isoformat()
    })


@app.route('/peers', methods=['POST'])
def add_peer():
    """Add a new WireGuard peer"""
    if not is_authorized():
        abort(403, description="Access denied")

    data = request.get_json()

    # Validate required fields
    required = ['customer_name', 'public_key']
    for field in required:
        if not data.get(field):
            abort(400, description=f"Missing required field: {field}")

    pubkey = data['public_key'].strip()
    customer_name = data['customer_name'].strip()
    email = data.get('email', '').strip()
    vault_serial = data.get('vault_serial', '').strip()

    # Validate public key format (base64, 44 chars for WireGuard)
    if len(pubkey) != 44 or not re.match(r'^[A-Za-z0-9+/]+=*$', pubkey):
        abort(400, description="Invalid public key format")

    # Check for duplicate public key
    existing_peers = parse_wg_conf_from_dump()
    for peer in existing_peers:
        if peer.get('public_key') == pubkey:
            abort(409, description="Public key already exists")

    # Find next available client number
    used_numbers = {p.get('client_number', 0) for p in existing_peers}
    client_number = data.get('client_number')

    if client_number:
        client_number = int(client_number)
        if client_number in used_numbers:
            abort(409, description=f"Client number {client_number} already in use")
    else:
        # Auto-assign next available (start from 50, skip used)
        client_number = 50
        while client_number in used_numbers:
            client_number += 1
        if client_number > 250:
            abort(507, description="No available client numbers (50-250 range full)")

    ip_address = f"10.200.0.{client_number}"
    allowed_ip = f"{ip_address}/32"
    date_added = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # Add to config file via daemon
    result = wg_control('add-config',
        pubkey=pubkey,
        allowed_ip=allowed_ip,
        customer_name=customer_name,
        client_number=client_number,
        vault_serial=vault_serial,
        email=email,
        date_added=date_added
    )

    if not result.get('success'):
        abort(500, description=f"Failed to write config: {result.get('error')}")

    # Append to CSV
    try:
        csv_exists = os.path.exists(CUSTOMER_CSV)
        with open(CUSTOMER_CSV, 'a', newline='') as f:
            writer = csv.writer(f)
            if not csv_exists:
                writer.writerow(['Client_Number', 'IP_Address', 'Customer_Name',
                               'Vault_Serial', 'Email', 'Public_Key', 'Date_Added'])
            writer.writerow([client_number, ip_address, customer_name,
                           vault_serial, email, pubkey, date_added])
    except Exception as e:
        app.logger.error(f"Failed to write CSV: {e}")
        # Continue anyway - wg0.conf is the source of truth

    # Hot reload WireGuard via daemon
    result = wg_control('add-live', pubkey=pubkey, allowed_ip=allowed_ip)
    if not result.get('success'):
        app.logger.error(f"wg set failed: {result.get('error')}")

    # Generate client config for response
    server_result = wg_control('get-server-pubkey')
    server_pubkey = server_result.get('pubkey', '<SERVER_PUBLIC_KEY>')

    client_config = f"""[Interface]
PrivateKey = <PASTE_PRIVATE_KEY_HERE>
Address = {ip_address}/32
DNS = 10.200.0.1

[Peer]
PublicKey = {server_pubkey}
Endpoint = chi.oss-vpn.net:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25"""

    return jsonify({
        'success': True,
        'client_number': client_number,
        'ip_address': ip_address,
        'customer_name': customer_name,
        'client_config': client_config,
        'message': f"Peer {client_number} added successfully"
    }), 201


@app.route('/peers/<int:client_number>', methods=['DELETE'])
def delete_peer(client_number):
    """Delete a WireGuard peer (admin only)"""
    if not is_admin():
        abort(403, description="Delete requires admin access")

    peers = parse_wg_conf_from_dump()
    peer_to_delete = None

    for peer in peers:
        if peer.get('client_number') == client_number:
            peer_to_delete = peer
            break

    if not peer_to_delete:
        abort(404, description=f"Peer {client_number} not found")

    pubkey = peer_to_delete['public_key']

    # Remove from config via daemon
    result = wg_control('remove-config', pubkey=pubkey)
    if not result.get('success'):
        abort(500, description=f"Failed to update config: {result.get('error')}")

    # Hot reload WireGuard via daemon
    result = wg_control('remove-live', pubkey=pubkey)
    if not result.get('success'):
        app.logger.error(f"wg remove failed: {result.get('error')}")

    return jsonify({
        'success': True,
        'deleted': client_number,
        'customer_name': peer_to_delete.get('customer_name'),
        'message': f"Peer {client_number} deleted successfully"
    })


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    # Test daemon connectivity
    result = wg_control('get-server-pubkey')
    daemon_ok = result.get('success', False)

    return jsonify({
        'status': 'healthy' if daemon_ok else 'degraded',
        'daemon': 'connected' if daemon_ok else 'disconnected',
        'timestamp': datetime.now().isoformat()
    })


@app.route('/next-client', methods=['GET'])
def next_client():
    """Get next available client number"""
    if not is_authorized():
        abort(403, description="Access denied")

    peers = parse_wg_conf_from_dump()
    used_numbers = {p.get('client_number', 0) for p in peers}

    next_num = 50
    while next_num in used_numbers:
        next_num += 1

    return jsonify({
        'next_available': next_num,
        'ip_address': f"10.200.0.{next_num}"
    })


if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=True)
