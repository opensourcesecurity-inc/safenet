# SafeNet VPN Infrastructure

**Open Source Security Inc. - Chicago SafeNet Server**

This repository contains the complete server configuration for OSS's SafeNet VPN service. Everything except private keys, customer data, and API tokens is published here for transparency and independent verification.

## Philosophy: Don't Trust, Verify

Other VPN providers ask you to trust their "no-log" claims. We give you the actual configurations to verify yourself.

- **Zero DNS logging** - See `unbound/safenet.conf` (verbosity: 0, no query logging)
- **Browse-only enforcement** - See `iptables/rules.v4` and `unbound/streaming-blocks.conf`
- **Privilege separation** - See `systemd/` services (web app can't touch VPN keys)
- **Security hardening** - See `scripts/safenet-harden.sh`

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    SafeNet Chicago Server                        │
│                                                                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐  │
│  │ WireGuard│───▶│ iptables │───▶│   NAT    │───▶│ Internet │  │
│  │  :51820  │    │ FORWARD  │    │          │    │          │  │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘  │
│       │              │                                          │
│       │              ▼                                          │
│       │         ┌──────────┐                                    │
│       │         │  ipset   │ ◀── 46K+ malicious IPs blocked    │
│       │         │ blocklist│                                    │
│       │         └──────────┘                                    │
│       │                                                         │
│       ▼                                                         │
│  ┌──────────┐    ┌──────────┐                                  │
│  │ Unbound  │───▶│Cloudflare│  Zero query logging              │
│  │   DNS    │    │ + Google │  850K+ domains blocked           │
│  └──────────┘    └──────────┘                                  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              Privilege Separation                         │  │
│  │  ┌─────────────┐         ┌─────────────┐                 │  │
│  │  │safenet-admin│◀──sock──│ wg-control  │                 │  │
│  │  │ (unprivileged)│        │(CAP_NET_ADMIN)│                │  │
│  │  │  Flask API  │         │ WG commands │                 │  │
│  │  └─────────────┘         └─────────────┘                 │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Security Stack

| Layer | Component | Protection |
|-------|-----------|------------|
| 1 | iptables | Protocol blocking (FTP, torrents, UDP except DNS) |
| 2 | ipset | 46,000+ malicious IPs blocked |
| 3 | Unbound DNS | 850,000+ malicious/ad domains blocked |
| 4 | WireGuard | ChaCha20-Poly1305 encryption |
| 5 | fail2ban | Brute force protection (3 attempts = 1hr ban) |
| 6 | Privilege separation | Web app compromise doesn't expose VPN |

## Repository Structure

```
safenet/
├── README.md                    # This file
├── LICENSE                      # BSD 2-Clause
├── unbound/
│   ├── safenet.conf             # Main DNS config (zero logging)
│   └── streaming-blocks.conf    # Browse-only policy enforcement
├── nginx/
│   ├── status.oss-vpn.net       # Customer status dashboard
│   ├── oss-blocklist.net        # Blocklist distribution
│   └── ntfy.chi.oss-vpn.net     # Push notification proxy
├── systemd/
│   ├── safenet-admin.service    # Flask API (unprivileged)
│   └── wg-control.service       # WireGuard daemon (CAP_NET_ADMIN only)
├── monit/
│   ├── safenet-security.conf    # Root login detection
│   ├── safenet-services.conf    # Service monitoring
│   └── safenet-system.conf      # Resource monitoring
├── iptables/
│   └── rules.v4                 # Firewall rules (browse-only enforcement)
├── scripts/
│   ├── app.py                   # SafeNet Admin API
│   ├── wg-control.py            # Privileged WireGuard daemon
│   ├── update-dns-blocklist.sh  # DNS blocklist aggregation
│   ├── update-ip-blocklist.sh   # IP blocklist aggregation
│   ├── update-safenet-dns.sh    # Apply DNS blocklist to Unbound
│   ├── update-safenet-ips.sh    # Apply IP blocklist to ipset
│   ├── daily-blocklist-report.sh # Daily stats notification
│   ├── whitelist-manager.sh     # DNS whitelist management
│   ├── count-vpn-users.sh       # Active user count
│   ├── get-peer-stats.sh        # Bandwidth statistics
│   ├── backup-safenet.sh        # Daily backup to Texas
│   ├── monit-ntfy-alert.sh      # Alert notification helper
│   ├── check-root-login.sh      # Root login detector
│   ├── safenet-harden.sh        # Server hardening script
│   ├── safenet-wireguard-setup.sh # WireGuard initialization
│   └── add-safenet-client.sh    # Customer onboarding helper
├── dashboard/
│   └── index.html               # Customer status dashboard
└── docs/
    └── FIREWALL-README.md       # Firewall architecture documentation
```

## What's Redacted

The following items are replaced with placeholders:

| Item | Placeholder | Reason |
|------|-------------|--------|
| WireGuard private keys | `REDACTED_PRIVATE_KEY` | Security |
| Server public IP | `XXX.XXX.XXX.XXX` | Security |
| Backup server IP | `XXX.XXX.XXX.XXX` | Security |
| ntfy topic ID | `REDACTED_NTFY_TOPIC` | Prevents alert spam |
| Customer data | Not included | Privacy |

## Server Specifications

| Component | Specification |
|-----------|---------------|
| CPU | Intel Xeon E3-1230 v6 (4C/8T @ 3.5GHz) |
| RAM | 32GB DDR4 |
| Storage | 250GB SSD |
| Network | 10Gbps dedicated fiber (unmetered) |
| OS | Ubuntu Server 24.04 LTS |
| Location | Chicago, USA |

## Browse-Only Policy

SafeNet is designed for private browsing, not streaming or torrenting.

**Allowed:** Web browsing, email, apps, TCP-based services

**Blocked:**
- Streaming services (DNS-level): Netflix, Hulu, Disney+, HBO, Prime Video, etc.
- BitTorrent (iptables): Ports 6881-6999, DHT port 6771
- FTP (iptables): Ports 20-21
- UDP except DNS (iptables): Kills most streaming protocols

## Verification

### Check DNS Logging (Should be disabled)
```bash
grep -r "log-queries\|verbosity" /etc/unbound/
# Should show: verbosity: 0 (or no log-queries directive)
```

### Check Blocklist Counts
```bash
wc -l /var/www/oss-blocklists/dns-combined.txt
wc -l /var/www/oss-blocklists/ip-combined.txt
```

### Check Privilege Separation
```bash
ps aux | grep -E "safenet|wg-control"
# safenet-admin runs as 'safenet' user
# wg-control runs as 'wgctl' user with CAP_NET_ADMIN only
```

## Related Documentation

- [AI Whitepaper Part 19: SafeNet VPN Infrastructure](https://github.com/opensourcesecurity-inc/aiw)
- [SecureNet OS Configuration](https://github.com/opensourcesecurity-inc/securenet)

## License

BSD 2-Clause License - See [LICENSE](LICENSE)

## Contact

Open Source Security Inc.  
https://opensourcesecurity.net
