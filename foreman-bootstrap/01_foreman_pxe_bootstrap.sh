#!/bin/bash
###############################################################################
# 01 - Foreman PXE Bootstrap
#
# Supports:
#   - CentOS Linux 7 (RAID)
#   - CentOS Linux 7 (SingleDisk)
#   - Rocky Linux 8.10 (RAID)
#   - Rocky Linux 8.10 (SingleDisk)
#   - Rocky Linux 9.2 (RAID)
#   - Rocky Linux 9.2 (SingleDisk)
#   - Rocky Linux 9.8 (RAID)
#   - Rocky Linux 9.8 (SingleDisk)
#
# Usage:
#
#   TARGET_VERSION=9.8 ./01_foreman_pxe_bootstrap.sh
#   TARGET_VERSION=9.2 ./01_foreman_pxe_bootstrap.sh
#
###############################################################################

set +e

FAILED_STEPS=()

record_failure() {
    FAILED_STEPS+=("$1")
}

###############################################################################
# Colors
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

###############################################################################
# Logging
###############################################################################

info() {
    echo -e "${CYAN}$1${NC}"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

header() {
    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

header "01 - Foreman PXE Bootstrap"

echo

###############################################################################
# Variables
###############################################################################

FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"

HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"

TARGET_VERSION="${TARGET_VERSION:-9.8}"

case "$TARGET_VERSION" in

    9.2)

        ROCKY_MEDIA_NAME="Rocky 9.2 Remote"
        ROCKY_MEDIA_PATH="http://192.168.253.136/repo/rocky9.2/"

        ROCKY_RAID_OS="RockyLinux 9.2 RAID"
        ROCKY_SINGLE_OS="RockyLinux 9.2 SingleDisk"

        ROCKY_RAID_TEMPLATE="PXEGrub2 Rocky9.2 UEFI Static Kickstart"
        ROCKY_SINGLE_TEMPLATE="PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

        ;;

    9.8)

        ROCKY_MEDIA_NAME="Rocky 9 Remote"
        ROCKY_MEDIA_PATH="http://192.168.253.136/repo/rocky9/"

        ROCKY_RAID_OS="RockyLinux 9.8 RAID"
        ROCKY_SINGLE_OS="RockyLinux 9.8 SingleDisk"

        ROCKY_RAID_TEMPLATE="PXEGrub2 Rocky9.8 UEFI Static Kickstart"
        ROCKY_SINGLE_TEMPLATE="PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

        ;;

    *)

        echo "Unsupported TARGET_VERSION : ${TARGET_VERSION}"
        exit 1
        ;;

esac

###############################################################################
# Common OS Names
###############################################################################

CENTOS_RAID_OS="CentOSLinux 7 RAID"
CENTOS_SINGLE_OS="CentOSLinux 7 SingleDisk"

ROCKY8_RAID_OS="RockyLinux 8.10 RAID"
ROCKY8_SINGLE_OS="RockyLinux 8.10 SingleDisk"

###############################################################################
# [1/6] Create Installation Media
###############################################################################

header "[1/6] Creating Installation Media"

###############################################################################
# CentOS 7 Installation Media
###############################################################################

info "Checking Installation Media : CentOS 7 Remote"

if $HAMMER medium info --name "CentOS 7 Remote" >/dev/null 2>&1; then

    skip "CentOS 7 Remote already exists."

else

    info "Creating CentOS 7 Remote..."

    $HAMMER medium create \
        --name "CentOS 7 Remote" \
        --path "http://192.168.253.136/repo/centos/" \
        --os-family Redhat

    if [ $? -eq 0 ]; then
        ok "CentOS 7 Remote created."
    else
        error "Failed to create CentOS 7 Remote."
        record_failure "CentOS 7 Remote"
    fi

fi

echo

###############################################################################
# Rocky Linux 8 Installation Media
###############################################################################

info "Checking Installation Media : Rocky 8 Remote"

if $HAMMER medium info --name "Rocky 8 Remote" >/dev/null 2>&1; then

    skip "Rocky 8 Remote already exists."

else

    info "Creating Rocky 8 Remote..."

    $HAMMER medium create \
        --name "Rocky 8 Remote" \
        --path "http://192.168.253.136/repo/rocky8/" \
        --os-family Redhat

    if [ $? -eq 0 ]; then
        ok "Rocky 8 Remote created."
    else
        error "Failed to create Rocky 8 Remote."
        record_failure "Rocky 8 Remote"
    fi

fi

echo

###############################################################################
# Selected Rocky Installation Media
###############################################################################

info "Checking Installation Media : ${ROCKY_MEDIA_NAME}"

if $HAMMER medium info --name "${ROCKY_MEDIA_NAME}" >/dev/null 2>&1; then

    skip "${ROCKY_MEDIA_NAME} already exists."

else

    info "Creating ${ROCKY_MEDIA_NAME}..."

    $HAMMER medium create \
        --name "${ROCKY_MEDIA_NAME}" \
        --path "${ROCKY_MEDIA_PATH}" \
        --os-family Redhat

    if [ $? -eq 0 ]; then
        ok "${ROCKY_MEDIA_NAME} created."
    else
        error "Failed to create ${ROCKY_MEDIA_NAME}."
        record_failure "${ROCKY_MEDIA_NAME}"
    fi

fi

echo

###############################################################################
# Verification
###############################################################################

header "Installation Media"

$HAMMER medium list

echo

###############################################################################
# [2/6] Creating Operating Systems
###############################################################################

header "[2/6] Creating Operating Systems"

###############################################################################
# Function : Create Operating System
###############################################################################

create_os() {

    local OS_TITLE="$1"
    local MAJOR="$2"
    local MINOR="$3"
    local MEDIA="$4"

    info "Checking Operating System : ${OS_TITLE}"

    if $HAMMER os info --title "${OS_TITLE}" >/dev/null 2>&1; then

        skip "${OS_TITLE} already exists."

    else

        info "Creating ${OS_TITLE}..."

        if [ -n "$MINOR" ]; then

            $HAMMER os create \
                --name "$(echo "${OS_TITLE}" | awk '{print $1}')" \
                --major "$MAJOR" \
                --minor "$MINOR" \
                --family Redhat \
                --architectures x86_64 \
                --partition-tables "Kickstart default" \
                --media "$MEDIA" \
                --title "$OS_TITLE"

        else

            $HAMMER os create \
                --name "$(echo "${OS_TITLE}" | awk '{print $1}')" \
                --major "$MAJOR" \
                --family Redhat \
                --architectures x86_64 \
                --partition-tables "Kickstart default" \
                --media "$MEDIA" \
                --title "$OS_TITLE"

        fi

        if [ $? -eq 0 ]; then
            ok "${OS_TITLE} created."
        else
            error "Failed to create ${OS_TITLE}."
            record_failure "${OS_TITLE}"
        fi

    fi

    echo
}

###############################################################################
# CentOS 7
###############################################################################

create_os \
    "$CENTOS_RAID_OS" \
    "7" \
    "" \
    "CentOS 7 Remote"

create_os \
    "$CENTOS_SINGLE_OS" \
    "7" \
    "" \
    "CentOS 7 Remote"

###############################################################################
# Rocky Linux 8
###############################################################################

create_os \
    "$ROCKY8_RAID_OS" \
    "8" \
    "10" \
    "Rocky 8 Remote"

create_os \
    "$ROCKY8_SINGLE_OS" \
    "8" \
    "10" \
    "Rocky 8 Remote"

###############################################################################
# Rocky Linux 9
###############################################################################

create_os \
    "$ROCKY_RAID_OS" \
    "9" \
    "${TARGET_VERSION#9.}" \
    "$ROCKY_MEDIA_NAME"

create_os \
    "$ROCKY_SINGLE_OS" \
    "9" \
    "${TARGET_VERSION#9.}" \
    "$ROCKY_MEDIA_NAME"

###############################################################################
# Verification
###############################################################################

header "Operating Systems"

$HAMMER os list

echo

###############################################################################
# [3/6] Creating RAID PXE Templates
###############################################################################

header "[3/6] Creating RAID PXE Templates"

###############################################################################
# Generate Selected Rocky RAID Template
###############################################################################

info "Generating ${ROCKY_RAID_TEMPLATE}..."

case "$TARGET_VERSION" in

9.2)

cat >/tmp/rocky-raid.erb <<'EOF'
<%#
name: PXEGrub2 Rocky9.2 UEFI Static Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5

menuentry 'Install Rocky Linux 9.2 (RAID1)' {

    linuxefi /rocky92/vmlinuz \
        ip=dhcp \
        BOOTIF=01-${net_default_mac} \
        inst.repo=http://192.168.253.136/repo/rocky9.2/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/rocky9.cfg \
        inst.text \
        inst.ks.device=bootif \
        hostname=<%= @host.name %>

    initrdefi /rocky92/initrd.img
}
EOF

;;

9.8)

cat >/tmp/rocky-raid.erb <<'EOF'
<%#
name: PXEGrub2 Rocky9.8 UEFI Static Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5

menuentry 'Install Rocky Linux 9.8 (RAID1)' {

    linuxefi /rocky9/vmlinuz \
        ip=dhcp \
        BOOTIF=01-${net_default_mac} \
        inst.repo=http://192.168.253.136/repo/rocky9/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/rocky9.cfg \
        inst.text \
        inst.ks.device=bootif \
        hostname=<%= @host.name %>

    initrdefi /rocky9/initrd.img
}
EOF

;;

esac

ok "Selected Rocky RAID template generated."

echo

###############################################################################
# Import Selected Rocky RAID Template
###############################################################################

info "Checking ${ROCKY_RAID_TEMPLATE}..."

if $HAMMER template info \
    --name "${ROCKY_RAID_TEMPLATE}" >/dev/null 2>&1; then

    skip "Template already exists."

else

    info "Importing template..."

    $HAMMER template create \
        --name "${ROCKY_RAID_TEMPLATE}" \
        --type PXEGrub2 \
        --file /tmp/rocky-raid.erb

    if [ $? -eq 0 ]; then
        ok "Template imported."
    else
        error "Template import failed."
        record_failure "${ROCKY_RAID_TEMPLATE}"
    fi

fi

echo

###############################################################################
# Assign RAID Template
###############################################################################

info "Checking template assignment..."

if $HAMMER os info \
    --title "${ROCKY_RAID_OS}" | \
    grep -q "${ROCKY_RAID_TEMPLATE}"; then

    skip "Template already assigned."

else

    info "Assigning template..."

    $HAMMER os add-provisioning-template \
        --title "${ROCKY_RAID_OS}" \
        --provisioning-template "${ROCKY_RAID_TEMPLATE}"

    if [ $? -eq 0 ]; then
        ok "Template assigned."
    else
        error "Template assignment failed."
        record_failure "${ROCKY_RAID_OS}"
    fi

fi

echo

###############################################################################
# CentOS 7 RAID Template
###############################################################################

info "Generating CentOS 7 RAID template..."

cat >/tmp/centos-raid.erb <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI Static Kickstart
kind: PXEGrub2
oses:
- CentOSLinux
%>

set default=0
set timeout=5

menuentry 'Install CentOS 7 (RAID1)' {

    linuxefi /centos/vmlinuz \
        inst.stage2=http://192.168.253.136/repo/centos/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/centos7.cfg \
        inst.text \
        inst.default_fstype=ext4 \
        inst.ks.device=bootif \
        BOOTIF=01-${net_default_mac} \
        hostname=<%= @host.name %>

    initrdefi /centos/initrd.img
}
EOF

ok "CentOS RAID template generated."

echo

###############################################################################
# Rocky Linux 8 RAID Template
###############################################################################

info "Generating Rocky Linux 8 RAID template..."

cat >/tmp/rocky8-raid.erb <<'EOF'
<%#
name: PXEGrub2 RockyOS UEFI Static Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5

menuentry 'Install Rocky Linux 8.10 (RAID1)' {

    linuxefi /rocky8/vmlinuz \
        inst.stage2=http://192.168.253.136/repo/rocky8/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/rockyos.cfg \
        inst.text \
        inst.default_fstype=ext4 \
        inst.ks.device=bootif \
        BOOTIF=01-${net_default_mac} \
        hostname=<%= @host.name %>

    initrdefi /rocky8/initrd.img
}
EOF

ok "Rocky Linux 8 RAID template generated."

echo

###############################################################################
# Import CentOS RAID Template
###############################################################################

info "Checking PXEGrub2 CentOS UEFI Static Kickstart..."

if $HAMMER template info \
    --name "PXEGrub2 CentOS UEFI Static Kickstart" >/dev/null 2>&1; then

    skip "Template already exists."

else

    info "Importing template..."

    $HAMMER template create \
        --name "PXEGrub2 CentOS UEFI Static Kickstart" \
        --type PXEGrub2 \
        --file /tmp/centos-raid.erb

    ok "Template imported."

fi

echo

###############################################################################
# Import Rocky 8 RAID Template
###############################################################################

info "Checking PXEGrub2 RockyOS UEFI Static Kickstart..."

if $HAMMER template info \
    --name "PXEGrub2 RockyOS UEFI Static Kickstart" >/dev/null 2>&1; then

    skip "Template already exists."

else

    info "Importing template..."

    $HAMMER template create \
        --name "PXEGrub2 RockyOS UEFI Static Kickstart" \
        --type PXEGrub2 \
        --file /tmp/rocky8-raid.erb

    ok "Template imported."

fi

echo

###############################################################################
# Assign RAID Templates
###############################################################################

info "Checking template assignment for ${CENTOS_RAID_OS}..."

if $HAMMER os info \
    --title "${CENTOS_RAID_OS}" | \
    grep -q "PXEGrub2 CentOS UEFI Static Kickstart"; then

    skip "Already assigned."

else

    $HAMMER os add-provisioning-template \
        --title "${CENTOS_RAID_OS}" \
        --provisioning-template "PXEGrub2 CentOS UEFI Static Kickstart"

    ok "Template assigned."

fi

echo

info "Checking template assignment for ${ROCKY8_RAID_OS}..."

if $HAMMER os info \
    --title "${ROCKY8_RAID_OS}" | \
    grep -q "PXEGrub2 RockyOS UEFI Static Kickstart"; then

    skip "Already assigned."

else

    $HAMMER os add-provisioning-template \
        --title "${ROCKY8_RAID_OS}" \
        --provisioning-template "PXEGrub2 RockyOS UEFI Static Kickstart"

    ok "Template assigned."

fi

echo

###############################################################################
# Verification
###############################################################################

header "RAID PXE Templates"

$HAMMER template list | grep -E "Static Kickstart"

echo

###############################################################################
# [4/6] Creating Subnets
###############################################################################

header "[4/6] Creating Subnets"

###############################################################################
# CentOS Subnet
###############################################################################

info "Checking Subnet : vgs-subnet-centos"

if $HAMMER subnet info \
    --name "vgs-subnet-centos" >/dev/null 2>&1; then

    skip "vgs-subnet-centos already exists."

else

    info "Creating CentOS subnet..."

    $HAMMER subnet create \
        --name "vgs-subnet-centos" \
        --network "192.168.253.0" \
        --mask "255.255.255.0" \
        --gateway "192.168.253.2" \
        --dns-primary "192.168.253.1" \
        --from "192.168.253.10" \
        --to "192.168.253.240" \
        --ipam DHCP \
        --boot-mode DHCP \
        --mtu 1500 \
        --domains "vgs.com" \
        --dhcp "cent-07-01.vgs.com" \
        --tftp "cent-07-01.vgs.com"

    if [ $? -eq 0 ]; then
        ok "CentOS subnet created."
    else
        error "Failed to create CentOS subnet."
        record_failure "vgs-subnet-centos"
    fi

fi

echo

###############################################################################
# Rocky Linux Subnet
###############################################################################

info "Checking Subnet : vgs-subnet-rockyos"

if $HAMMER subnet info \
    --name "vgs-subnet-rockyos" >/dev/null 2>&1; then

    skip "vgs-subnet-rockyos already exists."

else

    info "Creating Rocky subnet..."

    $HAMMER subnet create \
        --name "vgs-subnet-rockyos" \
        --network "192.168.253.0" \
        --mask "255.255.255.0" \
        --gateway "192.168.253.2" \
        --dns-primary "192.168.253.1" \
        --from "192.168.253.10" \
        --to "192.168.253.240" \
        --ipam DHCP \
        --boot-mode DHCP \
        --mtu 1500 \
        --domains "vgs.com" \
        --dhcp "cent-07-02.vgs.com" \
        --tftp "cent-07-02.vgs.com"

    if [ $? -eq 0 ]; then
        ok "Rocky subnet created."
    else
        error "Failed to create Rocky subnet."
        record_failure "vgs-subnet-rockyos"
    fi

fi

echo

###############################################################################
# Verification
###############################################################################

header "Subnets"

$HAMMER subnet list

echo

$HAMMER subnet info --name "vgs-subnet-centos"

echo

$HAMMER subnet info --name "vgs-subnet-rockyos"

echo

###############################################################################
# [5/6] Setting Default PXE Templates
###############################################################################

header "[5/6] Setting Default PXE Templates"

###############################################################################
# Function : Set Default PXE Template
###############################################################################

set_default_template() {

    local OS_TITLE="$1"
    local TEMPLATE_NAME="$2"

    info "Checking ${OS_TITLE}..."

    OS_ID=$(
        $HAMMER os list |
        awk -F'|' -v os="$OS_TITLE" '
            $2 ~ os {
                gsub(/ /,"",$1)
                print $1
            }'
    )

    TEMPLATE_ID=$(
        $HAMMER template list |
        awk -F'|' -v tpl="$TEMPLATE_NAME" '
            $2 ~ tpl {
                gsub(/ /,"",$1)
                print $1
            }'
    )

    if [ -z "$OS_ID" ] || [ -z "$TEMPLATE_ID" ]; then

        error "Unable to locate ${OS_TITLE} or ${TEMPLATE_NAME}"
        record_failure "${OS_TITLE}"
        echo
        return

    fi

    if $HAMMER os info --id "$OS_ID" |
        awk '/Default templates:/,/Architectures:/' |
        grep -q "$TEMPLATE_NAME"; then

        skip "Default template already configured."

    else

        info "Setting default template..."

        $HAMMER os set-default-template \
            --id "$OS_ID" \
            --provisioning-template-id "$TEMPLATE_ID"

        if [ $? -eq 0 ]; then
            ok "Default template configured."
        else
            error "Failed to configure default template."
            record_failure "${OS_TITLE}"
        fi

    fi

    echo

}

###############################################################################
# Configure RAID Operating Systems
###############################################################################

set_default_template \
    "$CENTOS_RAID_OS" \
    "PXEGrub2 CentOS UEFI Static Kickstart"

set_default_template \
    "$ROCKY8_RAID_OS" \
    "PXEGrub2 RockyOS UEFI Static Kickstart"

set_default_template \
    "$ROCKY_RAID_OS" \
    "$ROCKY_RAID_TEMPLATE"

###############################################################################
# Verification
###############################################################################

header "Default RAID PXE Templates"

echo
info "$CENTOS_RAID_OS"

$HAMMER os info \
    --title "$CENTOS_RAID_OS" |
    awk '/Default templates:/,/Architectures:/'

echo

info "$ROCKY8_RAID_OS"

$HAMMER os info \
    --title "$ROCKY8_RAID_OS" |
    awk '/Default templates:/,/Architectures:/'

echo

info "$ROCKY_RAID_OS"

$HAMMER os info \
    --title "$ROCKY_RAID_OS" |
    awk '/Default templates:/,/Architectures:/'

echo

###############################################################################
# [6/6] Final Verification
###############################################################################

header "[6/6] PXE Provisioning Configuration Summary"

echo

info "Installation Media"

$HAMMER medium list

echo

info "Operating Systems"

$HAMMER os list

echo

info "PXE Templates"

$HAMMER template list | \
grep -E "Static Kickstart|SingleDisk Kickstart" || true

echo

info "Subnets"

$HAMMER subnet list

echo

###############################################################################
# Selected Configuration
###############################################################################

header "Selected RAID Configuration"

echo "TARGET_VERSION      : ${TARGET_VERSION}"
echo "Operating System    : ${ROCKY_RAID_OS}"
echo "PXE Template        : ${ROCKY_RAID_TEMPLATE}"
echo "Installation Media  : ${ROCKY_MEDIA_NAME}"

case "$TARGET_VERSION" in

9.2)

echo "Repository          : http://192.168.253.136/repo/rocky9.2/"
echo "Kickstart           : http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/rocky9.cfg"

;;

9.8)

echo "Repository          : http://192.168.253.136/repo/rocky9/"
echo "Kickstart           : http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/rocky9.cfg"

;;

esac

echo

###############################################################################
# Display RAID Operating Systems
###############################################################################

header "RAID Operating Systems"

echo "CentOSLinux 7 RAID"
echo "RockyLinux 8.10 RAID"
echo "${ROCKY_RAID_OS}"

echo

###############################################################################
# Display Single Disk Operating Systems
###############################################################################

header "Single Disk Operating Systems"

echo "CentOSLinux 7 SingleDisk"
echo "RockyLinux 8.10 SingleDisk"
echo "${ROCKY_SINGLE_OS}"

echo

###############################################################################
# Summary
###############################################################################

header "01 - Foreman PXE Bootstrap Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then

    ok "Foreman PXE Bootstrap completed successfully."

else

    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

    for step in "${FAILED_STEPS[@]}"; do
        error "$step"
    done

fi

echo

exit 0
