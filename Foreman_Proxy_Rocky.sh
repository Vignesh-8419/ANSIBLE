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

SSH_PASSWORD="Root@123"

REPO_MOUNT="//192.168.31.87/ISO"
MOUNT_POINT="/var/www/html/repo"

ISO_USERNAME="vigne"
ISO_PASSWORD='Vigneshv12$'

CERT_PATH="/root/${PROXY_SERVER}-certs.tar.gz"

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

cat > /tmp/proxy_remote.sh <<EOF
#!/bin/bash
set -euo pipefail

export TERM=\${TERM:-xterm}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo
    echo -e "\${BLUE}============================================================\${NC}"
    echo -e "\${CYAN}\$1\${NC}"
    echo -e "\${BLUE}============================================================\${NC}"
    echo
}

print_step() {
    echo -e "\${YELLOW}[INFO]\${NC} \$1"
}

print_success() {
    echo -e "\${GREEN}[ OK ]\${NC} \$1"
}

print_error() {
    echo -e "\${RED}[FAIL]\${NC} \$1"
}

trap 'print_error "Script failed at line \$LINENO"; exit 1' ERR

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
# Patch Verification
##############################################

print_header "VERIFYING PATCH LEVEL"

dnf makecache -y >/dev/null

if dnf check-update >/tmp/check_updates.log 2>&1; then
    print_success "System already patched."
else
    rc=\$?

    if [[ \$rc -eq 100 ]]; then
        print_step "Installing updates..."
        dnf update -y

        print_error "System updated. Reboot required."
        exit 0
    fi
fi

##############################################
# Mount ISO
##############################################

print_header "MOUNTING ISO SHARE"

mkdir -p "${MOUNT_POINT}"

if findmnt -rno TARGET "${MOUNT_POINT}" >/dev/null 2>&1; then
    print_success "ISO already mounted."
else
    mount -t cifs "${REPO_MOUNT}" "${MOUNT_POINT}" \
      -o username="${ISO_USERNAME}",password="${ISO_PASSWORD}",rw,vers=3.0

    print_success "ISO mounted."
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

##############################################
# Append Smart Proxy Configuration Section
##############################################

cat >> /tmp/proxy_remote.sh <<EOF

##############################################
# STEP 6: CONFIGURING SMART PROXY
##############################################

print_header "CONFIGURING SMART PROXY"

print_step "Running Foreman installer..."

foreman-installer \
  --scenario foreman-proxy-content \
  --certs-tar-file "/root/${PROXY_SERVER}-certs.tar.gz" \
  --foreman-proxy-register-in-foreman true \
  --foreman-proxy-foreman-base-url "https://${FOREMAN_SERVER}" \
  --foreman-proxy-oauth-consumer-key "${OAUTH_KEY}" \
  --foreman-proxy-oauth-consumer-secret "${OAUTH_SECRET}" \
  --foreman-proxy-tftp true \
  --enable-foreman-proxy-plugin-tftp true \
  --enable-foreman-proxy-plugin-templates true

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

##############################################
# UEFI Files
##############################################

print_header "COPYING UEFI FILES"

mkdir -p /var/lib/tftpboot/grub2

sshpass -p '${SSH_PASSWORD}' scp \
-o StrictHostKeyChecking=no \
-o UserKnownHostsFile=/dev/null \
root@${FOREMAN_SERVER}:/boot/efi/EFI/rocky/shimx64.efi \
/var/lib/tftpboot/grub2/

sshpass -p '${SSH_PASSWORD}' scp \
-o StrictHostKeyChecking=no \
-o UserKnownHostsFile=/dev/null \
root@${FOREMAN_SERVER}:/boot/efi/EFI/rocky/grub.cfg \
/var/lib/tftpboot/grub2/

print_success "UEFI files copied"

##############################################
# PXE Files
##############################################

print_header "CONFIGURING PXE FILES"

mkdir -p /var/lib/tftpboot/rockyos

cp -rp \
${MOUNT_POINT}/rocky8/isolinux/vmlinuz \
/var/lib/tftpboot/rockyos/

cp -rp \
${MOUNT_POINT}/rocky8/isolinux/initrd.img \
/var/lib/tftpboot/rockyos/

chown -R foreman-proxy:root /var/lib/tftpboot/rockyos

print_success "PXE files configured"

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
# Transfer Files
##############################################

print_header "COPYING FILES TO PROXY"

sshpass -p "$SSH_PASSWORD" scp \
-o StrictHostKeyChecking=no \
-o UserKnownHostsFile=/dev/null \
/tmp/proxy_remote.sh \
root@"$PROXY_SERVER":/root/

sshpass -p "$SSH_PASSWORD" scp \
-o StrictHostKeyChecking=no \
-o UserKnownHostsFile=/dev/null \
"$CERT_PATH" \
root@"$PROXY_SERVER":/root/

print_success "Files copied successfully"

##############################################
# Execute Remote Script
##############################################

print_header "EXECUTING REMOTE INSTALLER"

print_step "Starting installation on ${PROXY_SERVER}..."

sshpass -p "$SSH_PASSWORD" ssh -tt \
-o StrictHostKeyChecking=no \
-o UserKnownHostsFile=/dev/null \
root@"$PROXY_SERVER" \
"export TERM=xterm-256color; bash /root/proxy_remote.sh"

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
