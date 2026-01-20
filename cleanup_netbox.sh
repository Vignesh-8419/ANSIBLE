#!/bin/bash
# --- NETBOX & POSTGRESQL TOTAL CLEANUP SCRIPT ---

log() { echo -e "\e[31m[CLEANUP]\e[0m $1"; }

# 1. Stop and disable all related services
log "Stopping all services..."
systemctl stop netbox netbox-worker nginx redis postgresql-15 postgresql || true
systemctl disable netbox netbox-worker nginx redis postgresql-15 postgresql || true

# 2. Kill any lingering Python/Gunicorn processes
log "Killing lingering processes..."
pkill -9 -f gunicorn || true
pkill -9 -f rqworker || true

# 3. Remove Application files
log "Removing NetBox application files and virtual environment..."
rm -rf /opt/netbox

# 4. Wipe Database Data
log "Wiping PostgreSQL 15 database data..."
# This ensures a fresh 'initdb' can run later
rm -rf /var/lib/pgsql/15/data/*

# 5. Remove Configuration and Logs
log "Removing Nginx and SSL configurations..."
rm -f /etc/nginx/conf.d/netbox.conf
rm -rf /etc/ssl/netbox
rm -rf /var/log/netbox

# 6. Clear Systemd unit files
log "Removing Systemd service files..."
rm -f /etc/systemd/system/netbox.service
rm -f /etc/systemd/system/netbox-worker.service
systemctl daemon-reload

# 7. Reset DNF/YUM Repositories (To prepare for Offline Repos)
log "Backing up old repo files and clearing DNF cache..."
mkdir -p /etc/yum.repos.d/backup_online
# Move all current repos to backup so only your internal_mirror.repo remains
mv /etc/yum.repos.d/Rocky* /etc/yum.repos.d/backup_online/ 2>/dev/null || true
mv /etc/yum.repos.d/epel* /etc/yum.repos.d/backup_online/ 2>/dev/null || true
mv /etc/yum.repos.d/pgdg* /etc/yum.repos.d/backup_online/ 2>/dev/null || true

dnf clean all

log "------------------------------------------------"
log "CLEANUP COMPLETE."
log "System is ready for offline installation."
log "------------------------------------------------"
