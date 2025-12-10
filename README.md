# SafeNet VPN

**Private browsing VPN service for SecureNet customers.**

[![Ubuntu Version](https://img.shields.io/badge/Ubuntu-24.04%20LTS-E95420)](https://ubuntu.com/)
[![WireGuard](https://img.shields.io/badge/Protocol-WireGuard-88171a)](https://www.wireguard.com/)
[![License](https://img.shields.io/badge/License-BSD%202--Clause-orange)](LICENSE)
[![Download Config](https://img.shields.io/github/v/release/opensourcesecurity-inc/safenet?label=Download&color=ff6b35)](https://github.com/opensourcesecurity-inc/safenet/releases/latest)

---

## What Is SafeNet?

SafeNet is a network-level VPN service for [SecureNet](https://github.com/opensourcesecurity-inc/securenet) customers. All devices on SafeNet networks route through our Chicago server automatically—no apps to install on each device.

This repository contains the complete server configuration (sanitized).

**Verify our privacy claims. Inspect our logging configuration.**

---

## What SafeNet Is For

| ✅ Designed For | ❌ Not For |
|-----------------|-----------|
| Private browsing at home | Streaming services (blocked) |
| ISP privacy protection | Torrenting / P2P (prohibited) |
| Keeping your IP private from websites | Gaming (UDP blocked) |
| Whole-network VPN | Travel / coffee shop security |

**SafeNet is browse-only by design.**

---

## Server Infrastructure

| Component | Specification |
|-----------|---------------|
| Location | Chicago, USA |
| OS | Ubuntu Server 24.04 LTS |
| Network | 10 Gbps dedicated fiber (unmetered) |
| Protocol | WireGuard |
| Encryption | ChaCha20-Poly1305 |
| DNS | Unbound (zero query logging) |

---

## Privacy Architecture

### What the Server Knows vs. Doesn't Know

| Server KNOWS | Server DOES NOT Know |
|--------------|----------------------|
| Tunnel IP (10.200.0.x) | DNS queries |
| Public key | Websites visited |
| Connection status | Browsing history |
| Total bandwidth (aggregate) | Connection timestamps |
| Last handshake time | Customer's real IP |

### Zero-Logging Verification

You can verify our logging configuration in this repository:

```bash
# Unbound DNS - no query logging
cat unbound/safenet.conf | grep -i log

# WireGuard - only startup/shutdown logged
journalctl -u wg-quick@wg0 --since today

# System journal size (should be small, not gigabytes)
journalctl --disk-usage
```

---

## Repository Structure

```
safenet/
├── README.md
├── LICENSE
├── ubuntu/
│   ├── hardening.md            # OS hardening steps
│   ├── packages.md             # Installed packages
│   └── ufw-rules.md            # Firewall configuration
├── wireguard/
│   ├── wg0.conf.example        # WireGuard server config (sanitized)
│   └── peer-management.md      # How peers are added/removed
├── unbound/
│   ├── unbound.conf            # DNS resolver configuration
│   └── safenet.conf            # SafeNet-specific settings
└── monitoring/
    └── netdata.md              # Server monitoring setup
```

> ⚠️ **Coming Soon:** Configuration files will be published prior to launch (January 27, 2026). README structure shown above reflects planned organization.

---

## Security Hardening

| Layer | Configuration |
|-------|---------------|
| SSH | Key-only authentication, no root password login |
| Firewall | UFW with minimal open ports (22, 80, 51820, 53) |
| Brute Force | Fail2ban (3 failures = 1 hour ban) |
| Updates | Unattended security upgrades enabled |
| IPv6 | Disabled |

### Open Ports

| Port | Service | Notes |
|------|---------|-------|
| 22 | SSH | Key-only, fail2ban protected |
| 80 | HTTP | Status dashboard, blocklist distribution |
| 51820 | WireGuard | VPN tunnel |
| 53 | DNS | Tunnel interface ONLY |

---

## Browse-Only Enforcement

SafeNet restricts traffic to browsing-focused use:

| Allowed | Blocked |
|---------|---------|
| HTTP/HTTPS browsing | Streaming (Netflix, Hulu, YouTube, Disney+) |
| Email (IMAP, SMTP, POP3) | Torrenting (BitTorrent) |
| SSH, SFTP | Gaming (UDP-based) |
| Standard TCP protocols | VoIP/Video calls (Zoom, Teams, Discord) |

### Enforcement Methods

1. **Protocol blocking** - UDP largely blocked
2. **DNS filtering** - Streaming CDNs return NXDOMAIN
3. **Application detection** - Zenarmor identifies and blocks streaming apps

---

## Status Dashboard

Live server metrics are publicly visible:

🌐 [status.oss-vpn.net](http://status.oss-vpn.net)

- Real-time CPU, RAM, disk, network
- Service status (WireGuard, Unbound, nginx)
- Uptime statistics
- 5-second refresh

---

## Pricing

| Plan | Cost |
|------|------|
| Monthly | $9/month |
| Annual | $89/year (18% discount) |

SafeNet is available exclusively to SecureNet customers.

---

## Related Repositories

| Repository | Description |
|------------|-------------|
| [securenet](https://github.com/opensourcesecurity-inc/securenet) | OPNsense firewall configuration |
| [aiw](https://github.com/opensourcesecurity-inc/aiw) | AI Whitepaper - complete technical documentation |
| [spl](https://github.com/opensourcesecurity-inc/spl) | Security Performance Lab data |
| [oss-blocklist](https://github.com/opensourcesecurity-inc/oss-blocklist) | IP blocklist aggregation |

---

## License

This project is licensed under the [BSD 2-Clause License](LICENSE).

---

## About Open Source Security

Open Source Security, Inc. provides enterprise-grade home network security through professionally configured OPNsense firewalls on Protectli hardware.

🌐 [opensourcesecurity.net](https://opensourcesecurity.net)

**Transparency is our foundation.** Every configuration, every test result, every claim is publicly verifiable.
