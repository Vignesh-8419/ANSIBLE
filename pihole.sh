#!/bin/bash

set -e

echo "=================================="
echo "      Pi-hole Clean Installer      "
echo "=================================="

# -------------------------------
# 0. TEMP DNS FIX (CRITICAL)
# -------------------------------
echo ">>> Setting temporary DNS (upstream)"
cp /etc/resolv.conf /etc/resolv.conf.backup || true
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# -------------------------------
# 1. Install dependencies
# -------------------------------
echo ">>> Installing dependencies"
yum install -y epel-release
yum install -y git curl psmisc

# -------------------------------
# 2. Stop & Clean existing Pi-hole
# -------------------------------
echo ">>> Stopping and cleaning old installation"
systemctl stop pihole-FTL 2>/dev/null || true
killall -9 pihole-FTL 2>/dev/null || true
rm -rf /etc/pihole /etc/.pihole /var/www/html/admin /opt/pihole

# -------------------------------
# 3. Firewall
# -------------------------------
echo ">>> Configuring firewall"
firewall-cmd --permanent --add-service=dns || true
firewall-cmd --permanent --add-service=http || true
firewall-cmd --permanent --add-service=https || true
firewall-cmd --reload

# -------------------------------
# 4. SELinux
# -------------------------------
echo ">>> Configuring SELinux"
setenforce 0 2>/dev/null || true
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config || true

# -------------------------------
# 5. Install Pi-hole
# -------------------------------
echo ">>> Installing Pi-hole"
curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended

# -------------------------------
# 6. Configure Upstream DNS (The Fix)
# -------------------------------
echo ">>> Configuring upstream DNS to 192.168.253.2"

# We manually inject the DNS settings into the config file
mkdir -p /etc/pihole
cat <<EOF > /etc/pihole/setupVars.conf
PIHOLE_DNS_1=192.168.253.2
PIHOLE_DNS_2=8.8.4.4
DNS_FQDN_REQUIRED=true
DNS_BOGUS_PRIV=true
DNSSEC=false
REV_SERVER=false
EOF

# Apply the changes
pihole -g || true
systemctl restart pihole-FTL

# -------------------------------
# 7. Restore & Status
# -------------------------------
echo ">>> Restoring original DNS"
mv -f /etc/resolv.conf.backup /etc/resolv.conf || true

echo ">>> Checking status"
pihole status || true

IP=$(hostname -I | awk '{print $1}')
echo "=================================="
echo "   Installation Task Complete     "
echo "   Web UI: http://$IP/admin       "
echo "=================================="
