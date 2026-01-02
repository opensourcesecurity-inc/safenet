# SafeNet VPN

**Private browsing VPN for SecureNet customers.**

[![Ubuntu Version](https://img.shields.io/badge/Ubuntu-24.04%20LTS-E95420)](https://ubuntu.com/)
[![WireGuard](https://img.shields.io/badge/Protocol-WireGuard-88171a)](https://www.wireguard.com/)
[![License](https://img.shields.io/badge/License-BSD%202--Clause-orange)](LICENSE)

---

## What Is SafeNet?

SafeNet is a network-level VPN service for Protectli Vaults running [SecureNet](https://github.com/opensourcesecurity-inc/securenet). All devices on SafeNet-enabled networks route through a hardened Chicago-based server automatically. No applications are required on individual devices.

This repository contains the complete SafeNet server configuration. Keys and passwords are excluded. Everything else is published.

**Verify our privacy claims. Inspect our code. That is the point.**

---

## What SafeNet Is For

| Designed For | Not For |
|--------------|---------|
| Private browsing | Streaming services (blocked) |
| ISP privacy protection | Torrenting and P2P (blocked) |
| Keeping your IP private | Real-time gaming (UDP restricted) |
| Whole-network VPN | High-bandwidth applications |

**SafeNet is a browsing-focused VPN by design.** Bandwidth-intensive traffic is intentionally restricted to maintain performance, reduce abuse, and protect IP reputation.

---

## Server Infrastructure

| Component | Specification |
|-----------|---------------|
| Location | Chicago, USA (additional regions planned) |
| Hardware | Dedicated server, Intel Xeon E3-1230 v6, 32GB RAM |
| Network | 10 Gbps dedicated fiber, unmetered |
| OS | Ubuntu Server 24.04 LTS |
| Protocol | WireGuard (ChaCha20-Poly1305) |
| DNS | Unbound with query logging disabled |

---

## Security Architecture

SafeNet uses a **privilege-separated architecture** with defense in depth. No single compromise results in full system control.

### Privilege Separation Model

```text
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
│  • No access to WireGuard configs                  │
│  • No ability to execute system commands           │
│  • Sandboxed via systemd                           │
└─────────────────────────┬──────────────────────────┘
                          │ Unix socket (restricted)
                          ▼
┌────────────────────────────────────────────────────┐
│        WireGuard Control Daemon (User: wgctl)      │
│                                                    │
│  • Dedicated unprivileged user                     │
│  • CAP_NET_ADMIN capability only                  │
│  • Strict input validation                         │
│  • Local socket access only                        │
└────────────────────────────────────────────────────┘
```

**If the web application is compromised:**  
The attacker gains an unprivileged user with no access to VPN keys, configuration files, or system commands.

**If the daemon is compromised:**  
The attacker gains CAP_NET_ADMIN only. They cannot read files or escalate to root.

### Six-Layer Security Stack

| Layer | Protection |
|-------|------------|
| 1. iptables | Protocol blocking and traffic filtering |
| 2. WireGuard | Encrypted tunnel with modern cryptography |
| 3. nginx | Rate limiting and IP-based access control |
| 4. Unbound DNS | ~850,000 malicious domains blocked (changes daily) |
| 5. ipset | ~46,000 malicious IPs blocked in kernel (changes daily) |
| 6. Privilege Separation | Web and control layers fully isolated |

### Server Hardening

| Measure | Implementation |
|---------|----------------|
| SSH | Key-only authentication, passwords disabled |
| Brute force | fail2ban with automatic bans |
| Updates | Unattended security upgrades enabled |
| Firewall | iptables with ipset integration |
| IPv6 | Disabled system-wide |
| systemd | ProtectSystem, PrivateTmp, NoNewPrivileges |
| File permissions | WireGuard private key readable by root only |

### Open Ports (Public Interface)

| Port | Service | Protection |
|------|---------|------------|
| 22/tcp | SSH | Key-only authentication, fail2ban |
| 80/tcp | Blocklist distribution | Static files only |
| 51820/udp | WireGuard | Encrypted tunnel |

Port 53 (DNS) is bound to the tunnel interface only and is not reachable from the public internet.

---

## Privacy Architecture

### What We Know vs. What We Do Not Know

| We Know | We Do Not Know |
|---------|----------------|
| Assigned tunnel IP (10.200.0.x) | DNS queries |
| WireGuard public key | Websites visited |
| Connection status | Browsing history |
| Aggregate bandwidth usage | Per-connection timestamps |
| Last handshake time | Traffic contents |

### Zero-Logging Implementation

```bash
grep -E "(log-queries|verbosity)" unbound/safenet.conf
# verbosity: 0

cat systemd/journald.conf
# MaxRetentionSec=7day
# SystemMaxUse=500M
```

---

## Browse-Only Enforcement

SafeNet restricts traffic to browsing-oriented use cases.

| Allowed | Blocked |
|---------|---------|
| HTTP and HTTPS | BitTorrent and DHT |
| Email protocols | Streaming CDNs |
| SSH and SFTP | FTP |
| Standard TCP applications | Most UDP traffic |

### Enforcement Methods

1. iptables blocks all outbound UDP except DNS and WireGuard
2. Known BitTorrent and DHT ports are blocked
3. Streaming services return NXDOMAIN via DNS filtering
4. Malicious IP ranges are dropped at kernel level

---

## Status Dashboard

Read-only server metrics are available to connected SafeNet users.

**http://status.oss-vpn.net** (tunnel access only)

- Real-time CPU, memory, disk, and network usage
- Service health indicators
- Five-second auto refresh
- Powered by Netdata

---

## Repository Structure

```text
safenet/
├── README.md
├── LICENSE
├── ubuntu/
│   ├── hardening.md
│   ├── packages.txt
│   └── sysctl.conf
├── wireguard/
│   ├── wg0.conf.example
│   └── peer-management.md
├── unbound/
│   ├── safenet.conf
│   └── blocklist.conf
├── nginx/
│   └── status.oss-vpn.net
├── systemd/
│   ├── wg-control.service
│   └── safenet-admin.service
├── iptables/
│   ├── rules.v4
│   └── ipsets
└── scripts/
    ├── wg-control.py
    └── update-blocklists.sh
```

---

## Pricing

| Plan | Cost |
|------|------|
| Monthly | $9 per month |
| Annual | $89 per year (18 percent discount) |

Pricing reflects infrastructure costs, threat intelligence maintenance, and professional configuration. SafeNet is available exclusively to Protectli Vaults running SecureNet.

---

## About Open Source Security

Open Source Security, Inc. delivers enterprise-grade network security to home users through professionally configured OPNsense firewalls on Protectli hardware.

**Transparency is the foundation.** Every configuration is published. Every claim is verifiable.

[opensourcesecurity.net](https://opensourcesecurity.net)
