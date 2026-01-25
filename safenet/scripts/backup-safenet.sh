#!/bin/bash
# =============================================================================
# SafeNet Chicago Backup Script
# =============================================================================
# Purpose: Push critical files to backup server daily
# Location: /usr/local/bin/backup-safenet.sh
#
# Backs up:
# - WireGuard configs (all peers/customers, server keys)
# - Customer database and onboarding scripts
# - Unbound DNS configs and blocklists
# - nginx site configs
# - Monit configs
# - Blocklist scripts and whitelist
# - ntfy config
# - Web dashboards
# - fail2ban configs
# - iptables rules
# - Crontab
#
# Retention: 7 days on backup server
# Cron: Daily at 2:00 AM Chicago time
# =============================================================================

# REDACTED: Replace with your backup server details
BACKUP_HOST="safenet-backup@XXX.XXX.XXX.XXX"
BACKUP_DIR="/home/safenet-backup/chicago-backups"
SSH_KEY="/root/.ssh/backup_key"

DATE=$(date +%Y-%m-%d)
LOG="/var/log/safenet-backup.log"

echo "========================================" >> $LOG
echo "Backup started: $(date)" >> $LOG

# Create dated backup directory on backup server
ssh -i $SSH_KEY $BACKUP_HOST "mkdir -p $BACKUP_DIR/$DATE"

# WireGuard configs (all peers/customers, server keys)
rsync -avz --delete -e "ssh -i $SSH_KEY" \
    /etc/wireguard/ \
    $BACKUP_HOST:$BACKUP_DIR/$DATE/wireguard/

# Customer database and onboarding script
rsync -avz --delete -e "ssh -i $SSH_KEY" \
    /root/safenet-customers.csv \
    /root/add-safenet-client.sh \
    $BACKUP_HOST:$BACKUP_DIR/$DATE/root-scripts/

# Unbound DNS configs and blocklists
rsync -avz --delete -e "ssh -i $SSH_KEY" \
    /etc/unbound/unbound.conf.d/ \
    $BACKUP_HOST:$BACKUP_DIR/$DATE/unbound/

# nginx site configs
rsync -avz --delete -e "ssh -i $SSH_KEY" \
    /etc/nginx/sites-available/ \
    $BACKUP_HOST:$BACKUP_DIR/$DATE/nginx/

# Monit configs (main config + conf.d)
rsync -avz --delete -e "ssh -i $SSH_KEY" \
    /etc/monit/monitrc \
    /etc/monit/conf.d/ \
    $BACKUP_HOST:$BACKUP_DIR/$DATE/monit/

# Blocklist scripts and whitelist
rsync -avz --delete -e "ssh -i $SSH_KEY" \
    /opt/oss-blocklists/scripts/ \
    /opt/oss-blocklists/output/dns/whitelist.txt \
    $BACKUP_HOST:$BACKUP_DIR/$DATE/blocklists/

# ntfy config (contains topic secret)
rsync -avz --delete -e "ssh -i $SSH_KEY" \
    /etc/ntfy/ \
    $BACKUP_HOST:$BACKUP_DIR/$DATE/ntfy/

# Web root (status dashboard, admin dashboard)
rsync -avz --delete -e "ssh -i $SSH_KEY" \
    /var/www/ \
    $BACKUP_HOST:$BACKUP_DIR/$DATE/www/

# fail2ban configs
rsync -avz --delete -e "ssh -i $SSH_KEY" \
    /etc/fail2ban/ \
    $BACKUP_HOST:$BACKUP_DIR/$DATE/fail2ban/

# iptables rules (persisted rules)
rsync -avz --delete -e "ssh -i $SSH_KEY" \
    /etc/iptables/ \
    $BACKUP_HOST:$BACKUP_DIR/$DATE/iptables/

# Crontab backup
crontab -l > /tmp/root-crontab.txt 2>/dev/null
rsync -avz -e "ssh -i $SSH_KEY" \
    /tmp/root-crontab.txt \
    $BACKUP_HOST:$BACKUP_DIR/$DATE/
rm /tmp/root-crontab.txt

# Delete backups older than 7 days
ssh -i $SSH_KEY $BACKUP_HOST "find $BACKUP_DIR -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;"

echo "Backup completed: $(date)" >> $LOG

# Send notification via ntfy
/usr/local/bin/monit-ntfy-alert "Backup Complete" "SafeNet Chicago backup successful" "default" "package"
