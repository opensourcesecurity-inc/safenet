#!/usr/bin/env python3
"""
WireGuard Control Daemon
========================
Purpose: Handle privileged WireGuard operations via Unix socket
Location: /opt/safenet-admin/wg-control.py

PRIVILEGE SEPARATION:
This daemon runs as 'wgctl' user with ONLY CAP_NET_ADMIN capability.
It is NOT root. It can only run wg commands and modify wg0.conf.

The safenet-admin Flask app connects via Unix socket to request operations.
This separation means a web app compromise cannot directly access WireGuard.

Supported Commands:
- show: Get peer statistics (wg show dump)
- add-live: Add peer to running interface
- remove-live: Remove peer from running interface  
- add-config: Append peer block to wg0.conf
- remove-config: Remove peer block from wg0.conf
- get-server-pubkey: Read server public key file

Input Validation:
- Public keys must be exactly 44 chars, base64 format
- IPs must be in 10.200.0.2-254/32 range
- Text fields sanitized (no newlines, length limited)

See AIW Part 19 for full architecture documentation.
"""

import json
import os
import re
import socket
import subprocess
import sys

SOCKET_PATH = "/run/wg-control/wg-control.sock"
WG_CONF = "/etc/wireguard/wg0.conf"
WG_INTERFACE = "wg0"
SERVER_PUBKEY_FILE = "/etc/wireguard/server_public.key"

# Validation patterns
PUBKEY_PATTERN = re.compile(r'^[A-Za-z0-9+/]{42,43}=$')
IP_PATTERN = re.compile(r'^10\.200\.0\.([2-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-4])/32$')


def validate_pubkey(pubkey):
    """Validate WireGuard public key format"""
    if not pubkey or not isinstance(pubkey, str):
        return False
    if len(pubkey) != 44:
        return False
    return bool(PUBKEY_PATTERN.match(pubkey))


def validate_ip(ip):
    """Validate IP is in SafeNet range (10.200.0.2-254/32)"""
    if not ip or not isinstance(ip, str):
        return False
    return bool(IP_PATTERN.match(ip))


def cmd_show():
    """Get WireGuard peer stats"""
    try:
        result = subprocess.run(
            ['/usr/bin/wg', 'show', WG_INTERFACE, 'dump'],
            capture_output=True, text=True, timeout=5
        )
        return {'success': True, 'output': result.stdout, 'returncode': result.returncode}
    except Exception as e:
        return {'success': False, 'error': str(e)}


def cmd_add_live(pubkey, allowed_ip):
    """Add peer to live WireGuard interface"""
    if not validate_pubkey(pubkey):
        return {'success': False, 'error': 'Invalid public key format'}
    if not validate_ip(allowed_ip):
        return {'success': False, 'error': 'Invalid IP format (must be 10.200.0.X/32)'}

    try:
        result = subprocess.run(
            ['/usr/bin/wg', 'set', WG_INTERFACE, 'peer', pubkey, 'allowed-ips', allowed_ip],
            capture_output=True, text=True, timeout=10
        )
        return {'success': result.returncode == 0, 'stderr': result.stderr}
    except Exception as e:
        return {'success': False, 'error': str(e)}


def cmd_remove_live(pubkey):
    """Remove peer from live WireGuard interface"""
    if not validate_pubkey(pubkey):
        return {'success': False, 'error': 'Invalid public key format'}

    try:
        result = subprocess.run(
            ['/usr/bin/wg', 'set', WG_INTERFACE, 'peer', pubkey, 'remove'],
            capture_output=True, text=True, timeout=10
        )
        return {'success': result.returncode == 0, 'stderr': result.stderr}
    except Exception as e:
        return {'success': False, 'error': str(e)}


def cmd_add_config(pubkey, allowed_ip, customer_name, client_number, vault_serial, email, date_added):
    """Append peer block to wg0.conf"""
    if not validate_pubkey(pubkey):
        return {'success': False, 'error': 'Invalid public key format'}
    if not validate_ip(allowed_ip):
        return {'success': False, 'error': 'Invalid IP format'}

    # Sanitize text fields (remove newlines, limit length)
    def sanitize(s, max_len=100):
        if not s:
            return ''
        return str(s).replace('\n', ' ').replace('\r', '')[:max_len]

    customer_name = sanitize(customer_name)
    vault_serial = sanitize(vault_serial, 50)
    email = sanitize(email, 100)
    date_added = sanitize(date_added, 30)
    client_number = int(client_number) if client_number else 0

    peer_block = f"""
[Peer]
# Customer: {customer_name}
# Client #: {client_number}
# Vault Serial: {vault_serial}
# Email: {email}
# Added: {date_added}
PublicKey = {pubkey}
AllowedIPs = {allowed_ip}
"""

    try:
        with open(WG_CONF, 'a') as f:
            f.write(peer_block)
        return {'success': True}
    except Exception as e:
        return {'success': False, 'error': str(e)}


def cmd_remove_config(pubkey):
    """Remove peer block from wg0.conf"""
    if not validate_pubkey(pubkey):
        return {'success': False, 'error': 'Invalid public key format'}

    try:
        with open(WG_CONF, 'r') as f:
            content = f.read()

        # Remove peer block containing this public key
        # Matches [Peer] section with this key, including comments
        pattern = rf'\[Peer\][^\[]*PublicKey\s*=\s*{re.escape(pubkey)}[^\[]*'
        new_content = re.sub(pattern, '', content)

        # Clean up extra blank lines
        new_content = re.sub(r'\n{3,}', '\n\n', new_content)

        with open(WG_CONF, 'w') as f:
            f.write(new_content)

        return {'success': True}
    except Exception as e:
        return {'success': False, 'error': str(e)}


def cmd_get_server_pubkey():
    """Read server public key"""
    try:
        with open(SERVER_PUBKEY_FILE, 'r') as f:
            return {'success': True, 'pubkey': f.read().strip()}
    except Exception as e:
        return {'success': False, 'error': str(e)}


def handle_request(data):
    """Process incoming request"""
    try:
        request = json.loads(data)
    except json.JSONDecodeError:
        return {'success': False, 'error': 'Invalid JSON'}

    cmd = request.get('command')

    if cmd == 'show':
        return cmd_show()
    elif cmd == 'add-live':
        return cmd_add_live(request.get('pubkey'), request.get('allowed_ip'))
    elif cmd == 'remove-live':
        return cmd_remove_live(request.get('pubkey'))
    elif cmd == 'add-config':
        return cmd_add_config(
            request.get('pubkey'),
            request.get('allowed_ip'),
            request.get('customer_name'),
            request.get('client_number'),
            request.get('vault_serial'),
            request.get('email'),
            request.get('date_added')
        )
    elif cmd == 'remove-config':
        return cmd_remove_config(request.get('pubkey'))
    elif cmd == 'get-server-pubkey':
        return cmd_get_server_pubkey()
    else:
        return {'success': False, 'error': f'Unknown command: {cmd}'}


def main():
    # Remove stale socket
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    # Create socket
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET_PATH)

    # Set permissions: owner rw, group rw (safenet user is in wgctl group)
    os.chmod(SOCKET_PATH, 0o660)

    # Change group to wgctl so safenet user can connect
    import grp
    wgctl_gid = grp.getgrnam('wgctl').gr_gid
    os.chown(SOCKET_PATH, -1, wgctl_gid)

    server.listen(5)
    print(f"wg-control daemon listening on {SOCKET_PATH}", flush=True)

    while True:
        try:
            conn, _ = server.accept()
            data = conn.recv(4096).decode('utf-8')

            if data:
                response = handle_request(data)
                conn.sendall(json.dumps(response).encode('utf-8'))

            conn.close()
        except Exception as e:
            print(f"Error handling connection: {e}", file=sys.stderr, flush=True)


if __name__ == '__main__':
    main()
