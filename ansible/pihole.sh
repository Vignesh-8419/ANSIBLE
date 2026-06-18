#!/bin/bash

set -euo pipefail

##############################################
# Colors
##############################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

##############################################
# Helper Functions
##############################################
print_header() {
    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

##############################################
# Banner
##############################################
clear

echo -e "${GREEN}"
echo "=================================="
echo "      Pi-hole Clean Installer     "
echo "=================================="
echo -e "${NC}"

##############################################
# 0. TEMP DNS FIX (CRITICAL)
##############################################
print_header "SETTING TEMPORARY DNS"

print_info "Backing up resolv.conf"
cp /etc/resolv.conf /etc/resolv.conf.backup || true

print_info "Applying temporary DNS 8.8.8.8"
echo "nameserver 8.8.8.8" > /etc/resolv.conf

##############################################
# 1. Install dependencies
##############################################
print_header "INSTALLING DEPENDENCIES"

yum install -y epel-release
yum install -y git curl psmisc

print_success "Dependencies installed"

##############################################
# 2. Stop & Clean existing Pi-hole
##############################################
print_header "REMOVING OLD PI-HOLE INSTALLATION"

systemctl stop pihole-FTL 2>/dev/null || true
killall -9 pihole-FTL 2>/dev/null || true

rm -rf \
    /etc/pihole \
    /etc/.pihole \
    /var/www/html/admin \
    /opt/pihole

print_success "Previous installation removed"

##############################################
# 3. Firewall
##############################################
print_header "CONFIGURING FIREWALL"

firewall-cmd --permanent --add-service=dns || true
firewall-cmd --permanent --add-service=http || true
firewall-cmd --permanent --add-service=https || true
firewall-cmd --reload

print_success "Firewall configured"

##############################################
# 4. SELinux
##############################################
print_header "CONFIGURING SELINUX"

setenforce 0 2>/dev/null || true
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config || true

print_success "SELinux set to permissive"

##############################################
# 5. Install Pi-hole
##############################################
print_header "INSTALLING PI-HOLE"

curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended

print_success "Pi-hole installation completed"

##############################################
# 6. Configure Upstream DNS
##############################################
print_header "CONFIGURING UPSTREAM DNS"

mkdir -p /etc/pihole

cat <<EOF > /etc/pihole/setupVars.conf
PIHOLE_DNS_1=192.168.253.2
PIHOLE_DNS_2=8.8.4.4
DNS_FQDN_REQUIRED=true
DNS_BOGUS_PRIV=true
DNSSEC=false
REV_SERVER=false
EOF

pihole -g || true
systemctl restart pihole-FTL

print_success "Upstream DNS configured"

##############################################
# 7. Download Custom DNS Script
##############################################
print_header "DOWNLOADING CUSTOM DNS SCRIPT"

curl -fsSL \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/pihole-customdns.sh" \
-o /root/pihole-customdns.sh

chmod +x /root/pihole-customdns.sh

print_success "Downloaded: /root/pihole-customdns.sh"
print_success "Execute permission granted"

##############################################
# 8. Restore DNS
##############################################
print_header "RESTORING ORIGINAL DNS"

mv -f /etc/resolv.conf.backup /etc/resolv.conf || true

print_success "Original DNS restored"

##############################################
# 9. Status Check
##############################################
print_header "VERIFYING PI-HOLE STATUS"

pihole status || true

IP=$(hostname -I | awk '{print $1}')

echo
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}PI-HOLE INSTALLATION COMPLETED SUCCESSFULLY${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "${CYAN}Web UI:${NC} http://$IP/admin"
echo -e "${CYAN}Custom DNS Script:${NC} /root/pihole-customdns.sh"
echo -e "${GREEN}============================================================${NC}"
