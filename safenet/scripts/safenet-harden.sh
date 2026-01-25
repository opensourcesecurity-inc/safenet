#!/bin/bash
# =============================================================================
# SafeNet Server Hardening Script
# =============================================================================
# Purpose: Initial security hardening for SafeNet VPN server
# Location: /root/safenet-harden.sh
#
# Run once after fresh Ubuntu Server 24.04 LTS installation.
#
# Configures:
# 1. Automatic security updates (unattended-upgrades)
# 2. fail2ban SSH protection (3 attempts = 1 hour ban)
# 3. UFW firewall (SSH + WireGuard only)
# 4. Kernel hardening (sysctl)
# 5. Time synchronization (chrony)
# 6. Journal log limits
# =============================================================================

echo "=== SafeNet Server Hardening ==="
echo ""

# 1. Configure unattended-upgrades
echo "[1/6] Configuring automatic security updates..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

# 2. Configure fail2ban
echo "[2/6] Configuring fail2ban..."
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
destemail = admin@example.com
sendername = SafeNet-Server
action = %(action_mwl)s

[sshd]
enabled = true
port = 22
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# 3. Configure UFW firewall
echo "[3/6] Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 51820/udp comment 'WireGuard'
ufw --force enable

# 4. Kernel hardening via sysctl
echo "[4/6] Applying kernel hardening..."
cat > /etc/sysctl.d/99-safenet-hardening.conf << 'EOF'
# IP Forwarding (required for WireGuard)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 0

# Disable IPv6 (reducing attack surface)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

# Network security hardening
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1

# Increase connection tracking for WireGuard
net.netfilter.nf_conntrack_max = 262144

# Kernel security
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 2
EOF

sysctl -p /etc/sysctl.d/99-safenet-hardening.conf

# 5. Configure chrony for accurate time
echo "[5/6] Configuring time synchronization..."
cat > /etc/chrony/chrony.conf << 'EOF'
# Use public NTP servers
pool time.cloudflare.com iburst maxsources 4
pool time.google.com iburst maxsources 2

# Record drift
driftfile /var/lib/chrony/drift

# Allow large time corrections
makestep 1.0 3

# Serve time even if not synchronized
local stratum 10

# Logging
logdir /var/log/chrony
EOF

systemctl enable chrony
systemctl restart chrony

# 6. Configure journald limits
echo "[6/6] Configuring logging limits..."
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-safenet.conf << 'EOF'
[Journal]
SystemMaxUse=500M
SystemKeepFree=1G
MaxRetentionSec=7day
EOF

systemctl restart systemd-journald

echo ""
echo "=== Hardening Complete! ==="
echo ""
echo "Summary:"
echo "✅ Automatic security updates enabled"
echo "✅ fail2ban protecting SSH (3 attempts, 1 hour ban)"
echo "✅ Firewall enabled (SSH 22, WireGuard 51820)"
echo "✅ Kernel hardened, IP forwarding enabled"
echo "✅ IPv6 disabled"
echo "✅ Time sync configured (chrony)"
echo "✅ Journal logs limited to 500MB, 7 days"
echo ""
echo "Check status:"
echo "  systemctl status fail2ban"
echo "  ufw status verbose"
echo "  chronyc tracking"
echo ""
