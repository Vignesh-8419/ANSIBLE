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
# Logging
##############################################
LOG_FILE="/var/log/foreman-katello-install.log"

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

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

##############################################
# Error Handling
##############################################

trap 'print_error "Script failed at line $LINENO. Check ${LOG_FILE} for details."; exit 1' ERR

##############################################
# Root Check
##############################################

if [[ $EUID -ne 0 ]]; then
    print_error "Please run this script as root."
    exit 1
fi

##############################################
# Banner
##############################################

print_header "FOREMAN + KATELLO INSTALLATION"

echo -e "${GREEN}Log File:${NC} ${LOG_FILE}"
echo

##############################################
# PRE-CHECK: VERIFY /etc/hosts
##############################################

HOST_IP=$(hostname -I | awk '{print $1}')
SHORT_HOST=$(hostname -s)
FQDN_HOST=$(hostname -f)

print_header "PRE-CHECK: VERIFYING /etc/hosts"

if grep -Eq "^${HOST_IP}[[:space:]]+${FQDN_HOST}[[:space:]]+${SHORT_HOST}$" /etc/hosts; then
    print_success "/etc/hosts entry is correct."
else
    print_step "Updating /etc/hosts..."

    # Remove old entry for this IP
    sed -i "\|^${HOST_IP}[[:space:]]|d" /etc/hosts

    # Add correct entry
    echo "${HOST_IP}    ${FQDN_HOST}    ${SHORT_HOST}" >> /etc/hosts

    print_success "/etc/hosts updated successfully."
fi

##############################################
# Pre-Check: Verify System Patch Level
##############################################

print_header "PRE-CHECK: VERIFYING SYSTEM PATCH LEVEL"

print_step "Refreshing DNF metadata..."
dnf makecache -y >/dev/null 2>&1

print_step "Checking whether updates are available..."

if dnf check-update >/dev/null 2>&1; then
    print_success "Server is already running the latest packages."
    print_step "Proceeding with Foreman installation..."
else
    DNF_RC=$?

    if [[ ${DNF_RC} -eq 100 ]]; then
        echo
        echo -e "${YELLOW}[INFO]${NC} Updates are available."

        print_step "Installing all available updates..."
        dnf upgrade -y

        echo
        echo -e "${GREEN}============================================================${NC}"
        echo -e "${GREEN}System patching completed successfully.${NC}"
        echo -e "${YELLOW}Please reboot the server and run this script again.${NC}"
        echo -e "${GREEN}============================================================${NC}"
        echo

        exit 0
    else
        print_error "Unable to determine update status (DNF returned code ${DNF_RC})."
        exit 1
    fi
fi

##############################################
# STEP 1: Mount ISO Repository
##############################################

print_header "STEP 1: MOUNTING ISO REPOSITORY"

# Configuration
REPO_MOUNT="//192.168.31.87/ISO"
MOUNT_POINT="/var/www/html/repo"
USERNAME="vigne"
PASSWORD="Vigneshv12$"

print_step "Installing CIFS utilities..."
dnf install -y cifs-utils
print_success "CIFS utilities installed."

print_step "Creating mount point..."
mkdir -p "$MOUNT_POINT"

if findmnt -rno TARGET "$MOUNT_POINT" >/dev/null 2>&1; then
    print_success "ISO share is already mounted at ${MOUNT_POINT}. Skipping."
else
    print_step "Mounting ISO share..."

    mount -t cifs "$REPO_MOUNT" "$MOUNT_POINT" \
        -o username="$USERNAME",password="$PASSWORD",rw,dir_mode=0777,file_mode=0777,vers=3.0

    if findmnt -rno TARGET "$MOUNT_POINT" >/dev/null 2>&1; then
        print_success "ISO repository mounted successfully."
    else
        print_error "Failed to mount ISO repository."
        exit 1
    fi
fi

##############################################
# Step 2: Install EPEL Repository
##############################################

print_header "STEP 2: INSTALLING EPEL REPOSITORY"

print_step "Installing EPEL..."
dnf install -y epel-release

print_success "EPEL repository installed."

##############################################
# Step 3: Install Foreman Repository
##############################################

print_header "STEP 3: INSTALLING FOREMAN REPOSITORY"

print_step "Installing Foreman release package..."

dnf install -y \
https://yum.theforeman.org/releases/3.12/el8/x86_64/foreman-release.rpm

print_success "Foreman repository installed."

##############################################
# Step 4: Install Katello Repository
##############################################

print_header "STEP 4: INSTALLING KATELLO REPOSITORY"

print_step "Installing Katello release package..."

dnf install -y \
https://yum.theforeman.org/katello/4.14/katello/el8/x86_64/katello-repos-latest.rpm

print_success "Katello repository installed."

##############################################
# Step 5: Install PKI Dependency
##############################################

print_header "STEP 5: INSTALLING PKI DEPENDENCY"

print_step "Installing pki-servlet-engine..."

dnf install -y \
https://ftp.riken.jp/Linux/centos-vault/8-stream/AppStream/x86_64/os/Packages/pki-servlet-engine-9.0.62-1.module_el8+1002+021a2ab4.noarch.rpm

print_success "PKI dependency installed."

##############################################
# Step 6: Install Candlepin
##############################################

print_header "STEP 6: INSTALLING CANDLEPIN"

print_step "Installing Candlepin packages..."

dnf install -y \
https://yum.theforeman.org/candlepin/4.4/el8/x86_64/candlepin-4.4.20-1.el8.noarch.rpm \
https://yum.theforeman.org/candlepin/4.4/el8/x86_64/candlepin-selinux-4.4.20-1.el8.noarch.rpm

print_success "Candlepin packages installed."

##############################################
# Step 7: Install Puppet Agent
##############################################

print_header "STEP 7: INSTALLING PUPPET AGENT"

print_step "Installing Puppet repository..."

dnf install -y \
https://yum.puppet.com/puppet7-release-el-8.noarch.rpm

print_step "Installing Puppet agent..."

dnf install -y puppet-agent

print_success "Puppet agent installed."

##############################################
# Step 8: Configure DNF Modules
##############################################

print_header "STEP 8: CONFIGURING DNF MODULES"

print_step "Configuring Ruby 2.7..."

dnf module reset ruby -y
dnf module enable ruby:2.7 -y

print_success "Ruby 2.7 enabled."

print_step "Configuring PostgreSQL 13..."

dnf module reset postgresql -y
dnf module enable postgresql:13 -y

print_success "PostgreSQL 13 enabled."

print_step "Enabling Foreman module..."

dnf module enable foreman:el8 -y

print_success "Foreman module enabled."

print_step "Enabling Katello module..."

dnf module enable katello:el8 -y

print_success "Katello module enabled."

##############################################
# Step 9: Install Foreman and Katello
##############################################

print_header "STEP 9: INSTALLING FOREMAN AND KATELLO"

print_step "Installing Foreman Installer..."

dnf install -y foreman-installer-katello

print_success "Foreman Installer installed."

print_step "Installing Katello package..."

dnf install -y katello

print_success "Katello installed."

##############################################
# Step 10: Configure Foreman + Katello
##############################################

print_header "STEP 10: CONFIGURING FOREMAN"

print_step "Running Foreman installer..."

foreman-installer --scenario katello


##############################################
# STEP 11: Configure Foreman Proxy Services
##############################################

print_header "STEP 11: CONFIGURING FOREMAN PROXY"

print_step "Opening required firewall ports..."

firewall-cmd --add-service=dhcp --permanent
firewall-cmd --add-service=tftp --permanent
firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --add-port=8140/tcp --permanent

firewall-cmd --reload

print_success "Firewall configuration completed."

##############################################
# Configure TFTP Boot Files
##############################################

print_step "Creating TFTP boot directory..."

mkdir -p /var/lib/tftpboot/centos

print_step "Copying PXE boot files..."

cp -rp /var/www/html/repo/centos/isolinux/initrd.img \
       /var/lib/tftpboot/centos/

cp -rp /var/www/html/repo/centos/isolinux/vmlinuz \
       /var/lib/tftpboot/centos/

print_step "Setting ownership..."

chown -R foreman-proxy:root /var/lib/tftpboot/centos

print_success "Foreman proxy services configured successfully."

print_success "Foreman and Katello configuration completed."

##############################################
# Completion
##############################################

print_header "INSTALLATION COMPLETED"

echo -e "${GREEN}"
echo "############################################################"
echo "#                                                          #"
echo "#   Foreman + Katello installation completed successfully  #"
echo "#                                                          #"
echo "############################################################"
echo -e "${NC}"

echo
echo -e "${GREEN}Installation Log:${NC} ${LOG_FILE}"
echo
