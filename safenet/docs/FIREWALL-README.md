# SafeNet Chicago Server - Firewall Architecture

**Server:** oss-safenet-chi-01 (XXX.XXX.XXX.XXX)  
**Last Updated:** January 2026

## Overview

The server uses a five-layer security approach:

1. **iptables** - Core packet filtering for VPN traffic
2. **WireGuard PostUp/PostDown** - Dynamic rules when tunnel starts
3. **nginx** - Application-level access control by IP
4. **Unbound DNS** - Domain blocking for threats and streaming
5. **ipset** - IP blocklist for known malicious IPs

## Layer 1: iptables FORWARD Chain

All VPN client traffic flows through the FORWARD chain. This is where we block unwanted protocols.

**Current blocks:**
- FTP: ports 20-21 TCP
- BitTorrent DHT: port 6771 UDP
- BitTorrent: ports 6881-6999 TCP/UDP
- New outbound UDP except DNS (port 53)

**View rules:**

    iptables -L FORWARD -n --line-numbers

**Save rules to persist across reboot:**

    iptables-save > /etc/iptables/rules.v4

## Layer 2: WireGuard PostUp/PostDown

Located in `/etc/wireguard/wg0.conf`, these rules run when the tunnel starts:

    PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o nic1 -j MASQUERADE
    PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o nic1 -j MASQUERADE

This allows tunnel traffic through and NATs it to the public IP.

## Layer 3: nginx Access Control

Located in `/etc/nginx/sites-available/status.oss-vpn.net`

Controls web access by tunnel IP address:
- Status dashboard: all tunnel users (10.200.0.0/24)
- Full Netdata API: Admin only
- Admin dashboard: Admin only
- Netdata interface: Admin only

Rate limits: 30 req/min for pages, 300 req/min for API

**Reload after changes:**

    nginx -t && systemctl reload nginx

## Layer 4: Unbound DNS Blocking

Located in `/etc/unbound/unbound.conf.d/`

- **oss-blocklist.conf** - 850,000+ threat/ad/malware domains (minus whitelist)
- **streaming-blocks.conf** - Netflix, Hulu, Disney+, HBO, etc.
- **safenet.conf** - Main config, forwards to 1.1.1.1 and 8.8.8.8

**Blocklist source:** `http://oss-blocklist.net/dns/dns-combined.txt`  
**Whitelist source:** `http://oss-blocklist.net/dns/dns-whitelist.txt`

**Update script:** `/opt/oss-blocklists/scripts/update-safenet-dns.sh`  
**Cron:** Daily at 2:15 AM

The update script downloads both lists, removes whitelisted domains from the blocklist, then applies to Unbound.

**Test blocking:**

    dig @10.200.0.1 doubleclick.net +short    # Empty = blocked
    dig @10.200.0.1 google.com +short         # Returns IP = allowed

**Manage whitelist:**

    /opt/oss-blocklists/scripts/whitelist-manager.sh add example.com
    /opt/oss-blocklists/scripts/whitelist-manager.sh remove example.com
    /opt/oss-blocklists/scripts/whitelist-manager.sh list

After whitelist changes, copy to web root and re-run update:

    cp /opt/oss-blocklists/output/dns/whitelist.txt /var/www/oss-blocklists/dns-whitelist.txt
    bash /opt/oss-blocklists/scripts/update-safenet-dns.sh

## Layer 5: IP Blocklist (ipset)

Uses ipset with iptables to block 46,000+ malicious IPs.

**Blocklist source:** `http://oss-blocklist.net/ip/ip-combined.txt`  
**Update script:** `/opt/oss-blocklists/scripts/update-safenet-ips.sh`  
**Cron:** Daily at 2:20 AM  
**Persistence:** `/etc/iptables/ipsets` (survives reboot via netfilter-persistent)

**View blocked IPs:**

    ipset list oss-blocklist | head -30

**Check iptables rules:**

    iptables -L FORWARD -n --line-numbers | head -5

The ipset rules drop traffic TO or FROM any IP in the blocklist.

## Traffic Flow

```
VPN Client -> WireGuard (51820) -> wg0 interface -> FORWARD chain -> NAT -> Internet
                                        |
                                        v
                                IP blocklist (ipset)
                                FTP blocked
                                Torrent blocked
```

## Quick Commands

```bash
# View iptables rules
iptables -L -n --line-numbers | head -50

# View NAT rules
iptables -t nat -L -n

# View ipset blocklist
ipset list oss-blocklist | head -30

# View WireGuard config
cat /etc/wireguard/wg0.conf | head -10

# View DNS blocking configs
ls /etc/unbound/unbound.conf.d/

# Check services
systemctl status wg-quick@wg0
systemctl status unbound
systemctl status nginx
```

## Cron Schedule

| Time | Script | Purpose |
|------|--------|---------|
| 2:00 AM | backup-safenet.sh | Backup to secondary server |
| 2:05 AM | update-dns-blocklist.sh | Update source DNS list |
| 2:10 AM | update-ip-blocklist.sh | Update source IP list |
| 2:15 AM | update-safenet-dns.sh | Apply DNS blocklist to Unbound |
| 2:20 AM | update-safenet-ips.sh | Apply IP blocklist to ipset |
| 2:25 AM | daily-blocklist-report.sh | Send summary notification |
| Every minute | count-vpn-users.sh | Update active user count |
| Every minute | get-peer-stats.sh | Update bandwidth stats |

## Key Files

| File | Purpose |
|------|---------|
| /etc/wireguard/wg0.conf | WireGuard server config and peers |
| /etc/nginx/sites-available/ | Web server configs |
| /etc/unbound/unbound.conf.d/ | DNS blocking configs |
| /opt/oss-blocklists/scripts/ | Update scripts |
| /opt/safenet-admin/app.py | Admin API |
| /opt/safenet-admin/wg-control.py | WireGuard control daemon |
