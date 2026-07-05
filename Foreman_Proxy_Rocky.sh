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
    echo
}

print_step() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[ OK ]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

trap 'print_error "Script failed at line $LINENO"; exit 1' ERR

##############################################
# Configuration
##############################################

FOREMAN_SERVER="rocky-08-01.vgs.com"
FOREMAN_IP="192.168.253.133"

PROXY_SERVER="rocky-08-02.vgs.com"
PROXY_IP="192.168.253.134"

SSH_PASSWORD="Vigneshv12$"

MOUNT_POINT="/var/www/html/repo"

ISO_USERNAME="vigne"
ISO_PASSWORD='Vigneshv12$'

CERT_PATH="/tmp/${PROXY_SERVER}-certs.tar.gz"

##############################################
# Banner
##############################################

export TERM=${TERM:-xterm}
clear 2>/dev/null || true

echo -e "${GREEN}"
echo "############################################################"
echo "#                                                          #"
echo "#        Foreman Smart Proxy Deployment Utility           #"
echo "#                                                          #"
echo "#          Foreman 3.12 / Katello 4.14                    #"
echo "#                                                          #"
echo "############################################################"
echo -e "${NC}"

##############################################
# Validate Hosts
##############################################

print_header "VALIDATING HOST ENTRIES"

sed -i "/^${FOREMAN_IP}[[:space:]]/d" /etc/hosts
sed -i "/^${PROXY_IP}[[:space:]]/d" /etc/hosts

echo "${FOREMAN_IP} ${FOREMAN_SERVER} rocky-08-01" >> /etc/hosts
echo "${PROXY_IP} ${PROXY_SERVER} rocky-08-02" >> /etc/hosts

print_success "/etc/hosts cleaned and updated"

##############################################
# Generate Certificates
##############################################

print_header "GENERATING SMART PROXY CERTIFICATES"

foreman-proxy-certs-generate \
    --foreman-proxy-fqdn "$PROXY_SERVER" \
    --certs-tar "$CERT_PATH" | tee /tmp/proxy_output.txt

##############################################
# Extract OAuth
##############################################

print_header "EXTRACTING OAUTH CREDENTIALS"

OAUTH_KEY=$(grep -- '--foreman-proxy-oauth-consumer-key' \
/tmp/proxy_output.txt | awk -F'"' '{print $2}')

OAUTH_SECRET=$(grep -- '--foreman-proxy-oauth-consumer-secret' \
/tmp/proxy_output.txt | awk -F'"' '{print $2}')

if [[ -z "$OAUTH_KEY" || -z "$OAUTH_SECRET" ]]; then
    print_error "Unable to extract OAuth credentials."
    exit 1
fi

print_success "OAuth credentials extracted"
##############################################
# Build Remote Installer
##############################################

print_header "BUILDING REMOTE INSTALLER"

cat > /tmp/proxy_remote.sh <<'EOF'
#!/bin/bash
set -euo pipefail

export TERM=${TERM:-xterm}

FOREMAN_SERVER="rocky-08-01.vgs.com"
FOREMAN_IP="192.168.253.133"

PROXY_SERVER="rocky-08-02.vgs.com"
PROXY_IP="192.168.253.134"

MOUNT_POINT="/var/www/html/repo"

ISO_USERNAME="vigne"
ISO_PASSWORD='Vigneshv12$'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo
}

print_step() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[ OK ]${NC} $1"
}

print_error() {
    echo -e "\${RED}[FAIL]\${NC} \$1"
}

trap 'print_error "Script failed at line $LINENO"; exit 1' ERR

##############################################
# Host Entries
##############################################

print_header "VALIDATING HOST ENTRIES"

sed -i "/${FOREMAN_SERVER}/d" /etc/hosts
sed -i "/${PROXY_SERVER}/d" /etc/hosts
sed -i "/^${FOREMAN_IP}[[:space:]]/d" /etc/hosts
sed -i "/^${PROXY_IP}[[:space:]]/d" /etc/hosts

echo "${FOREMAN_IP} ${FOREMAN_SERVER} rocky-08-01" >> /etc/hosts
echo "${PROXY_IP} ${PROXY_SERVER} rocky-08-02" >> /etc/hosts

print_success "/etc/hosts updated"

##############################################
# Pre-Check: Verify System Patch Level
##############################################

print_header "PRE-CHECK: VERIFYING SYSTEM PATCH LEVEL"

TARGET_KERNEL="4.18.0-553.132.1.el8_10.x86_64"
CURRENT_KERNEL="$(uname -r)"

print_step "Current running kernel: ${CURRENT_KERNEL}"
print_step "Required kernel level: ${TARGET_KERNEL}"

if [[ "${CURRENT_KERNEL}" == "${TARGET_KERNEL}" ]]; then
    print_success "System is already at the required patch level."
    print_step "Proceeding with Foreman installation..."
else
    echo
    echo -e "\${YELLOW}[INFO]\${NC} System patch level does not match the required version."
    echo -e "\${YELLOW}[INFO]\${NC} Upgrading system packages to obtain kernel ${TARGET_KERNEL}."

    print_step "Refreshing DNF metadata..."
    dnf makecache -y

    print_step "Installing all available updates..."
    dnf upgrade -y

    NEWEST_KERNEL="$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -1)"

    echo
    echo -e "\${GREEN}============================================================\${NC}"
    echo -e "\${GREEN}System patching completed successfully.\${NC}"
    echo -e "\${GREEN}Latest installed kernel: ${NEWEST_KERNEL}\${NC}"
    
    if [[ "${NEWEST_KERNEL}" == "${TARGET_KERNEL}" ]]; then
        echo -e "\${YELLOW}Please reboot the server to boot into ${TARGET_KERNEL} and run this script again.\${NC}"
    else
        echo -e "\${RED}Warning: Target kernel ${TARGET_KERNEL} was not installed.\${NC}"
        echo -e "\${RED}Installed latest kernel: ${NEWEST_KERNEL}\${NC}"
        echo -e "\${RED}Verify that the correct Rocky Linux 8.10 repositories are enabled.\${NC}"
    fi
    
    echo -e "\${GREEN}============================================================\${NC}"
    echo
    
    exit 0
fi

##############################################
# Repository Installation
##############################################

print_header "INSTALLING REPOSITORIES"

dnf install -y epel-release

dnf install -y \
https://yum.theforeman.org/releases/3.12/el8/x86_64/foreman-release.rpm

dnf install -y \
https://yum.theforeman.org/katello/4.14/katello/el8/x86_64/katello-repos-latest.rpm

dnf install -y \
https://yum.puppet.com/puppet7-release-el-8.noarch.rpm

print_success "Repositories installed"

##############################################
# Module Configuration
##############################################

print_header "CONFIGURING MODULES"

dnf module reset ruby foreman katello postgresql -y || true

dnf module enable ruby:2.7 -y
dnf module enable postgresql:13 -y
dnf module enable foreman:el8 -y
dnf module enable katello:el8 -y

print_success "Modules configured"

##############################################
# Puppet
##############################################

print_header "INSTALLING PUPPET"

dnf install -y puppet-agent

print_success "Puppet installed"

##############################################
# Proxy Packages
##############################################

print_header "INSTALLING PROXY PACKAGES"

dnf install -y \
    foreman-installer-katello \
    sshpass

print_success "Proxy packages installed"

EOF

cat >> /tmp/proxy_remote.sh <<EOF
OAUTH_KEY="${OAUTH_KEY}"
OAUTH_SECRET="${OAUTH_SECRET}"
EOF

cat >> /tmp/proxy_remote.sh <<'EOF'

##############################################
# STEP 6: CONFIGURING SMART PROXY
##############################################

print_header "CONFIGURING SMART PROXY"

print_step "Running Foreman installer..."

foreman-installer \
  --scenario foreman-proxy-content \
  --certs-tar-file "/home/admin/${PROXY_SERVER}-certs.tar.gz" \
  --foreman-proxy-register-in-foreman true \
  --foreman-proxy-foreman-base-url "https://rocky-08-01.vgs.com" \
  --foreman-proxy-trusted-hosts "rocky-08-01.vgs.com" \
  --foreman-proxy-trusted-hosts "rocky-08-02.vgs.com" \
  --foreman-proxy-oauth-consumer-key "${OAUTH_KEY}" \
  --foreman-proxy-oauth-consumer-secret "${OAUTH_SECRET}" \
  --foreman-proxy-dhcp true \
  --foreman-proxy-dhcp-interface "ens192" \
  --foreman-proxy-dns true \
  --foreman-proxy-dns-interface "ens192" \
  --foreman-proxy-tftp true \
  --foreman-proxy-tftp-managed true \
  --foreman-proxy-tftp-root "/var/lib/tftpboot" \
  --foreman-proxy-tftp-servername "rocky-08-02.vgs.com"

print_success "Smart Proxy configured"

##############################################
# Firewall
##############################################

print_header "CONFIGURING FIREWALL"

systemctl enable --now firewalld

firewall-cmd --permanent --add-service=tftp
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-port=9090/tcp
firewall-cmd --reload

print_success "Firewall configured"

# ======================================================
# Rocky Linux 8 PXE Boot Files
# ======================================================

sshpass -p 'Vigneshv12$' ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  admin@netbox.vgs.com \
  "echo 'Vigneshv12$' | sudo -S cat /boot/efi/EFI/rocky/shimx64.efi" \
  > /var/lib/tftpboot/grub2/shimx64.efi

sshpass -p 'Vigneshv12$' ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  admin@netbox.vgs.com \
  "echo 'Vigneshv12$' | sudo -S cat /boot/efi/EFI/rocky/grub.cfg" \
  > /var/lib/tftpboot/grub2/grub.cfg

mkdir -p /var/lib/tftpboot/rocky8

curl -o /var/lib/tftpboot/rocky8/vmlinuz \
http://http-server-01/repo/rocky8/isolinux/vmlinuz

curl -o /var/lib/tftpboot/rocky8/initrd.img \
http://http-server-01/repo/rocky8/isolinux/initrd.img

chown -R foreman-proxy:root /var/lib/tftpboot/rocky8
chmod 644 /var/lib/tftpboot/rocky8/*


# ======================================================
# Rocky Linux 9 PXE Boot Files
# ======================================================
mkdir -p /var/lib/tftpboot/rocky9

curl -o /var/lib/tftpboot/rocky9/vmlinuz \
http://http-server-01/repo/rocky9/images/pxeboot/vmlinuz

curl -o /var/lib/tftpboot/rocky9/initrd.img \
http://http-server-01/repo/rocky9/images/pxeboot/initrd.img

chown -R foreman-proxy:root /var/lib/tftpboot/rocky9
chmod 644 /var/lib/tftpboot/rocky9/*

echo "✅ Smart Proxy installation completed."


##############################################
# Completion
##############################################

print_header "SMART PROXY INSTALLATION COMPLETED"

echo
echo "############################################################"
echo "#                                                          #"
echo "#   Foreman Smart Proxy Installation Completed            #"
echo "#                                                          #"
echo "#   Proxy  : ${PROXY_SERVER}"
echo "#   Foreman: ${FOREMAN_SERVER}"
echo "#                                                          #"
echo "############################################################"
echo

EOF

##############################################
# Finalize Remote Script
##############################################

print_step "Validating generated remote script"

bash -n /tmp/proxy_remote.sh

print_success "Remote script syntax validated"

chmod +x /tmp/proxy_remote.sh

print_success "Remote installer created"

##############################################
# Remove Old Remote Installer
##############################################

print_header "REMOVING OLD REMOTE INSTALLER"

sshpass -p "$SSH_PASSWORD" ssh \
-o StrictHostKeyChecking=no \
-o UserKnownHostsFile=/dev/null \
admin@"$PROXY_SERVER" \
"rm -f /home/admin/proxy_remote.sh /home/admin/${PROXY_SERVER}-certs.tar.gz"

print_success "Old remote installer removed"

##############################################
# Transfer Files
##############################################

print_header "COPYING FILES TO PROXY"

sshpass -p "$SSH_PASSWORD" scp \
-o StrictHostKeyChecking=no \
-o UserKnownHostsFile=/dev/null \
/tmp/proxy_remote.sh \
admin@"$PROXY_SERVER":/home/admin/

sshpass -p "$SSH_PASSWORD" scp \
-o StrictHostKeyChecking=no \
-o UserKnownHostsFile=/dev/null \
"$CERT_PATH" \
admin@"$PROXY_SERVER":/home/admin/
print_success "Files copied successfully"

##############################################
# Execute Remote Script
##############################################

print_header "EXECUTING REMOTE INSTALLER"

print_step "Starting installation on ${PROXY_SERVER}..."

sshpass -p "$SSH_PASSWORD" ssh -tt \
-o StrictHostKeyChecking=no \
-o UserKnownHostsFile=/dev/null \
admin@"$PROXY_SERVER" <<EOF
echo "$SSH_PASSWORD" | sudo -S chmod +x /home/admin/proxy_remote.sh
echo "$SSH_PASSWORD" | sudo -S env TERM=xterm-256color bash /home/admin/proxy_remote.sh
EOF

print_success "Remote execution completed"

##############################################
# Final Banner
##############################################

print_header "PROXY DEPLOYMENT FINISHED"

echo
echo "############################################################"
echo "#                                                          #"
echo "#   Smart Proxy Deployment Completed                      #"
echo "#                                                          #"
echo "#   Foreman : ${FOREMAN_SERVER}"
echo "#   Proxy   : ${PROXY_SERVER}"
echo "#                                                          #"
echo "############################################################"
echo
