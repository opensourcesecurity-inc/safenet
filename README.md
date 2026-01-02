# SafeNet VPN

**Private browsing VPN for SecureNet customers.**

[![Ubuntu Version](https://img.shields.io/badge/Ubuntu-24.04%20LTS-E95420)](https://ubuntu.com/)
[![WireGuard](https://img.shields.io/badge/Protocol-WireGuard-88171a)](https://www.wireguard.com/)
[![License](https://img.shields.io/badge/License-BSD%202--Clause-orange)](LICENSE)

---

## What Is SafeNet?

SafeNet is a network-level VPN service for Protectli vaults running [SecureNet](https://github.com/opensourcesecurity-inc/securenet). All devices on SafeNet-enabled networks route through our hardened Chicago server automatically—no apps to install on each device.

This repository contains the complete server configuration. Keys and passwords are excluded—everything else is here.

**Verify our privacy claims. Inspect our code. That's the point.**

---

## What SafeNet Is For

| Designed For | Not For |
|--------------|---------|
| Private browsing | Streaming services (blocked) |
| ISP privacy protection | Torrenting / P2P (blocked) |
| Keeping your IP private | Gaming (UDP restricted) |
| Whole-network VPN | High-bandwidth applications |

**SafeNet is a browsing-focused VPN by design.** We deliberately restrict bandwidth-heavy traffic to maintain performance and protect our IP reputation.

---

## Server Infrastructure

| Component | Specification |
|-----------|---------------|
| Location | Chicago, USA (expansion planned) |
| Hardware | Dedicated server, Intel Xeon E3-1230 v6, 32GB RAM |
| Network | 10 Gbps dedicated fiber (unmetered) |
| OS | Ubuntu Server 24.04 LTS |
| Protocol | WireGuard (ChaCha20-Poly1305) |
| DNS | Unbound with zero query logging |

---

## Security Architecture

SafeNet runs a **privilege-separated architecture** with defense in depth. No single compromise gives an attacker full access.

### Privilege Separation Model

```
┌────────────────────────────────────────────────────┐
│                     nginx                          │
│              (reverse proxy, rate limiting)        │
└─────────────────────────┬──────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────┐
│          Flask Admin API (User: safenet)           │
│                                                    │
│  • Unprivileged user                               │
│  • Cannot access WireGuard configs                 │
│  • Cannot execute system commands                  │
│  • Sandboxed by systemd                            │
└─────────────────────────┬──────────────────────────┘
                          │ Unix socket (restricted)
                          ▼
┌────────────────────────────────────────────────────┐
│        WireGuard Control Daemon (User: wgctl)      │
│                                                    │
│  • Dedicated unprivileged user                     │
│  • CAP_NET_ADMIN capability only (not root)        │
│  • Strict input validation                         │
│  • Only accepts commands via local socket          │
└────────────────────────────────────────────────────┘
```

**If the web application is compromised:** Attacker gets an unprivileged user with no access to VPN configs, keys, or system commands.

**If the daemon is compromised:** Attacker only has CAP_NET_ADMIN capability—cannot read files, cannot escalate to root.

### Six-Layer Security Stack

| Layer | Protection |
|-------|------------|
| 1. iptables | Protocol blocking (torrents, unauthorized UDP) |
| 2. WireGuard | Encrypted tunnel with modern cryptography |
| 3. nginx | Rate limiting, IP-based access control |
| 4. Unbound DNS | 850,000+ malicious domains blocked |
| 5. ipset | 46,000+ malicious IPs blocked at kernel level |
| 6. Privilege Separation | Flask and daemon run as unprivileged users |

### Server Hardening

| Measure | Implementation |
|---------|----------------|
| SSH | Key-only authentication, password disabled |
| Brute Force | fail2ban (3 failures = 1 hour ban) |
| Updates | Unattended security upgrades enabled |
| Firewall | iptables with ipset integration |
| IPv6 | Disabled system-wide |
| Systemd | Services hardened with ProtectSystem, PrivateTmp, NoNewPrivileges |
| File Permissions | WireGuard private key readable only by root |

### Open Ports (Public Interface)

| Port | Service | Protection |
|------|---------|------------|
| 22/tcp | SSH | Key-only, fail2ban |
| 80/tcp | Blocklist distribution | Static files only |
| 51820/udp | WireGuard | Encrypted tunnel |

Port 53 (DNS) is bound to the tunnel interface only—not accessible from the public internet.

---

## Privacy Architecture

### What We Know vs. Don't Know

| We Know | We Don't Know |
|---------|---------------|
| Your tunnel IP (10.200.0.x) | Your DNS queries (not logged) |
| Your WireGuard public key | Websites you visit |
| Connection status | Your browsing history |
| Aggregate bandwidth | Individual connection timestamps |
| Last handshake time | Contents of your traffic |

### Zero-Logging Implementation

```bash
# Unbound DNS - query logging disabled
cat unbound/safenet.conf | grep -E "(log-queries|verbosity)"
# verbosity: 0
# No log-queries directive = logging disabled

# Journal limited to errors only
cat systemd/journald.conf
# MaxRetentionSec=7day
# SystemMaxUse=500M
```

---

## Browse-Only Enforcement

SafeNet restricts traffic to browsing use cases:

| Allowed | Blocked |
|---------|---------|
| HTTP/HTTPS (web browsing) | BitTorrent (ports + protocol detection) |
| Email (IMAP, SMTP, POP3) | Streaming CDNs (DNS-level blocking) |
| SSH, SFTP | FTP (ports 20-21) |
| Standard TCP applications | Most UDP (except DNS) |

### Enforcement Methods

1. **iptables** - UDP blocked except DNS (port 53) and WireGuard (port 51820)
2. **Port blocking** - BitTorrent ports 6881-6999, DHT port 6771
3. **DNS filtering** - Streaming services (Netflix, Hulu, Disney+, HBO, YouTube) return NXDOMAIN
4. **IP blocklists** - Known malicious IPs dropped at kernel level

---

## Status Dashboard

Server metrics available to connected SafeNet users:

**http://status.oss-vpn.net** (tunnel access only)

- Real-time CPU, RAM, disk, network utilization
- Service status indicators
- 5-second auto-refresh
- Powered by Netdata

---

## Repository Structure

```
safenet/
├── README.md
├── LICENSE
├── ubuntu/
│   ├── hardening.md            # OS hardening configuration
│   ├── packages.txt            # Installed packages
│   └── sysctl.conf             # Kernel security parameters
├── wireguard/
│   ├── wg0.conf.example        # Server config (keys removed)
│   └── peer-management.md      # Peer add/remove procedures
├── unbound/
│   ├── safenet.conf            # DNS resolver settings
│   └── blocklist.conf          # Domain blocking configuration
├── nginx/
│   └── status.oss-vpn.net      # Web server configuration
├── systemd/
│   ├── wg-control.service      # Privilege-separated daemon
│   └── safenet-admin.service   # Flask API service
├── iptables/
│   ├── rules.v4                # Firewall rules (raw iptables)
│   └── ipsets                  # IP blocklist persistence
└── scripts/
    ├── wg-control.py           # WireGuard control daemon
    └── update-blocklists.sh    # Daily blocklist updates
```

---

## Pricing

| Plan | Cost |
|------|------|
| Monthly | $9/month |
| Annual | $89/year (save 18%) |

SafeNet is available exclusively to Protectli vaults running SecureNet.

---

## Related Repositories

| Repository | Description |
|------------|-------------|
| [securenet](https://github.com/opensourcesecurity-inc/securenet) | OPNsense firewall configuration for Protectli vaults |
| [aiw](https://github.com/opensourcesecurity-inc/aiw) | AI Whitepaper - complete technical documentation |
| [spl](https://github.com/opensourcesecurity-inc/spl) | Security Performance Lab methodology and results |
| [oss-blocklist](https://github.com/opensourcesecurity-inc/oss-blocklist) | Curated threat intelligence feeds |

---

## License

BSD 2-Clause License. See [LICENSE](LICENSE).

---

## About Open Source Security

Open Source Security, Inc. provides enterprise-grade network security for home users through professionally configured OPNsense firewalls on Protectli hardware.

**Transparency is our foundation.** Every configuration is published. Every claim is verifiable. That's what "open source security" means.

[opensourcesecurity.net](https://opensourcesecurity.net)
