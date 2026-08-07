#!/bin/bash
###############################################################################
# 01 - Foreman PXE Bootstrap
# Supports:
#   - CentOS Linux 7
#   - Rocky Linux 8.10
#   - Rocky Linux 9.2
#   - Rocky Linux 9.8
#
# Usage:
#   TARGET_VERSION=9.8 ./01_foreman_pxe_bootstrap.sh
#   TARGET_VERSION=9.2 ./01_foreman_pxe_bootstrap.sh
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
# Logging Functions
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

    ROCKY_OS_TITLE="RockyLinux 9.2"
    ROCKY_MAJOR="9"
    ROCKY_MINOR="2"

    ROCKY_TEMPLATE_NAME="PXEGrub2 Rocky9.2 UEFI Static Kickstart"
    ROCKY_TEMPLATE_FILE="/tmp/rocky92-pxegrub2.erb"

    ROCKY_KERNEL="/rocky92/vmlinuz"
    ROCKY_INITRD="/rocky92/initrd.img"

    ROCKY_REPO="http://192.168.253.136/repo/rocky9.2/"
    ROCKY_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/rocky9.cfg"

;;

9.8)

    ROCKY_MEDIA_NAME="Rocky 9 Remote"
    ROCKY_MEDIA_PATH="http://192.168.253.136/repo/rocky9/"

    ROCKY_OS_TITLE="RockyLinux 9.8"
    ROCKY_MAJOR="9"
    ROCKY_MINOR="8"

    ROCKY_TEMPLATE_NAME="PXEGrub2 Rocky9.8 UEFI Static Kickstart"
    ROCKY_TEMPLATE_FILE="/tmp/rocky98-pxegrub2.erb"

    ROCKY_KERNEL="/rocky9/vmlinuz"
    ROCKY_INITRD="/rocky9/initrd.img"

    ROCKY_REPO="http://192.168.253.136/repo/rocky9/"
    ROCKY_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/rocky9.cfg"

;;

*)

    error "Unsupported TARGET_VERSION: ${TARGET_VERSION}"
    exit 1

;;

esac

###############################################################################
# [1/6] Create Installation Media
###############################################################################

header "[1/6] Creating Installation Media"

###############################################################################
# Function : Create Installation Media
###############################################################################

create_media() {

    local NAME="$1"
    local URL="$2"

    info "Checking Installation Media : ${NAME}"

    if $HAMMER medium info --name "${NAME}" >/dev/null 2>&1; then

        skip "${NAME} already exists."

        return

    fi

    info "Creating ${NAME}..."

    $HAMMER medium create \
        --name "${NAME}" \
        --path "${URL}" \
        --os-family Redhat

    if [ $? -eq 0 ]; then
        ok "${NAME} created."
    else
        error "${NAME} creation failed."
        record_failure "${NAME}"
    fi

    echo
}

###############################################################################
# Create Installation Media
###############################################################################

create_media \
    "CentOS 7 Remote" \
    "http://192.168.253.136/repo/centos/"

create_media \
    "Rocky 8 Remote" \
    "http://192.168.253.136/repo/rocky8/"

create_media \
    "${ROCKY_MEDIA_NAME}" \
    "${ROCKY_MEDIA_PATH}"

###############################################################################
# Verification
###############################################################################

header "Installation Media"

$HAMMER medium list

echo

###############################################################################
# [2/6] Create Operating Systems
###############################################################################

header "[2/6] Creating Operating Systems"

###############################################################################
# Function : Create Operating System
###############################################################################

create_os() {

    local NAME="$1"
    local MAJOR="$2"
    local MINOR="$3"
    local MEDIA="$4"

    local TITLE="${NAME} ${MAJOR}"

    [ -n "$MINOR" ] && TITLE="${TITLE}.${MINOR}"

    info "Checking Operating System : ${TITLE}"

    if $HAMMER os info --title "${TITLE}" >/dev/null 2>&1; then

        skip "${TITLE} already exists."

        echo
        return

    fi

    info "Creating ${TITLE}..."

    CMD="$HAMMER os create \
        --name \"${NAME}\" \
        --major ${MAJOR}"

    if [ -n "$MINOR" ]; then
        CMD="${CMD} --minor ${MINOR}"
    fi

    CMD="${CMD} \
        --family Redhat \
        --architectures x86_64 \
        --partition-tables \"Kickstart default\" \
        --media \"${MEDIA}\""

    eval "$CMD"

    if [ $? -eq 0 ]; then
        ok "${TITLE} created."
    else
        error "${TITLE} creation failed."
        record_failure "${TITLE}"
    fi

    echo
}

###############################################################################
# Create Operating Systems
###############################################################################

create_os \
    "CentOSLinux" \
    "7" \
    "" \
    "CentOS 7 Remote"

create_os \
    "RockyLinux" \
    "8" \
    "10" \
    "Rocky 8 Remote"

create_os \
    "RockyLinux" \
    "${ROCKY_MAJOR}" \
    "${ROCKY_MINOR}" \
    "${ROCKY_MEDIA_NAME}"

###############################################################################
# Verification
###############################################################################

header "Operating Systems"

$HAMMER os list

echo

###############################################################################
# [3/6] Create PXE Provisioning Templates
###############################################################################

header "[3/6] Creating PXE Provisioning Templates"

###############################################################################
# Generate Rocky PXE Template
###############################################################################

info "Generating ${ROCKY_TEMPLATE_NAME}..."

cat > "${ROCKY_TEMPLATE_FILE}" <<EOF
<%#
name: ${ROCKY_TEMPLATE_NAME}
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5

menuentry 'Install ${ROCKY_OS_TITLE} (Automatic RAID1)' {

    linuxefi ${ROCKY_KERNEL} \
        ip=dhcp \
        BOOTIF=01-\${net_default_mac} \
        inst.repo=${ROCKY_REPO} \
        inst.ks=${ROCKY_KS} \
        inst.text \
        inst.ks.device=bootif \
        hostname=<%= @host.name %>

    initrdefi ${ROCKY_INITRD}
}
EOF

ok "Rocky template generated."

echo

###############################################################################
# Generate Rocky Linux 8 Template
###############################################################################

info "Generating Rocky Linux 8 template..."

cat >/tmp/rocky8-pxegrub2.erb <<'EOF'
<%#
name: PXEGrub2 RockyOS UEFI Static Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5

menuentry 'Install Rocky Linux 8.10 (Automatic RAID1)' {

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

ok "Rocky Linux 8 template generated."

echo

###############################################################################
# Generate CentOS 7 Template
###############################################################################

info "Generating CentOS 7 template..."

cat >/tmp/centos-pxegrub2.erb <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI Static Kickstart
kind: PXEGrub2
oses:
- CentOSLinux
%>

set default=0
set timeout=5

menuentry 'Install CentOS 7 (Automatic RAID1)' {

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

ok "CentOS template generated."

echo

###############################################################################
# Function : Import PXE Template
###############################################################################

import_template() {

    local NAME="$1"
    local FILE="$2"
    local OS="$3"

    info "Checking ${NAME}..."

    if $HAMMER template info \
        --name "${NAME}" >/dev/null 2>&1; then

        skip "Template already exists."

    else

        info "Importing template..."

        $HAMMER template create \
            --name "${NAME}" \
            --type PXEGrub2 \
            --file "${FILE}"

        if [ $? -eq 0 ]; then
            ok "Template imported."
        else
            error "Template import failed."
            record_failure "${NAME}"
        fi

    fi

    echo

    info "Checking template assignment..."

    if $HAMMER os info \
        --title "${OS}" |
        grep -q "${NAME}"; then

        skip "Already assigned."

    else

        $HAMMER os add-provisioning-template \
            --title "${OS}" \
            --provisioning-template "${NAME}"

        if [ $? -eq 0 ]; then
            ok "Template assigned."
        else
            error "Template assignment failed."
            record_failure "${OS} Template"
        fi

    fi

    echo
}

###############################################################################
# Import Templates
###############################################################################

import_template \
    "PXEGrub2 CentOS UEFI Static Kickstart" \
    "/tmp/centos-pxegrub2.erb" \
    "CentOSLinux 7"

import_template \
    "PXEGrub2 RockyOS UEFI Static Kickstart" \
    "/tmp/rocky8-pxegrub2.erb" \
    "RockyLinux 8.10"

import_template \
    "${ROCKY_TEMPLATE_NAME}" \
    "${ROCKY_TEMPLATE_FILE}" \
    "${ROCKY_OS_TITLE}"

###############################################################################
# Verification
###############################################################################

header "PXE Templates"

$HAMMER template list | grep -i UEFI || true

echo

###############################################################################
# [4/6] Create Subnets
###############################################################################

header "[4/6] Creating Subnets"

###############################################################################
# Function : Create Subnet
###############################################################################

create_subnet() {

    local NAME="$1"
    local DHCP_SERVER="$2"
    local TFTP_SERVER="$3"

    info "Checking Subnet : ${NAME}"

    if $HAMMER subnet info \
        --name "${NAME}" >/dev/null 2>&1; then

        skip "${NAME} already exists."

        echo
        return

    fi

    info "Creating ${NAME}..."

    $HAMMER subnet create \
        --name "${NAME}" \
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
        --dhcp "${DHCP_SERVER}" \
        --tftp "${TFTP_SERVER}"

    if [ $? -eq 0 ]; then
        ok "${NAME} created."
    else
        error "${NAME} creation failed."
        record_failure "${NAME}"
    fi

    echo
}

###############################################################################
# Create Subnets
###############################################################################

create_subnet \
    "vgs-subnet-centos" \
    "cent-07-01.vgs.com" \
    "cent-07-01.vgs.com"

create_subnet \
    "vgs-subnet-rockyos" \
    "cent-07-02.vgs.com" \
    "cent-07-02.vgs.com"

###############################################################################
# Verification
###############################################################################

header "Subnets"

$HAMMER subnet list

echo

info "CentOS Subnet"

$HAMMER subnet info \
    --name "vgs-subnet-centos"

echo

info "Rocky Linux Subnet"

$HAMMER subnet info \
    --name "vgs-subnet-rockyos"

echo

###############################################################################
# [5/6] Configure Default PXE Templates
###############################################################################

header "[5/6] Setting Default PXE Templates"

###############################################################################
# Get OS IDs
###############################################################################

CENTOS_OS_ID=$(
$HAMMER os list |
awk -F'|' '/CentOSLinux 7/ {
    gsub(/ /,"",$1)
    print $1
}'
)

ROCKY8_OS_ID=$(
$HAMMER os list |
awk -F'|' '/RockyLinux 8.10/ {
    gsub(/ /,"",$1)
    print $1
}'
)

ROCKY9_OS_ID=$(
$HAMMER os list |
awk -F'|' -v os="$ROCKY_OS_TITLE" '
$0 ~ os {
    gsub(/ /,"",$1)
    print $1
}'
)

###############################################################################
# Get Template IDs
###############################################################################

CENTOS_TEMPLATE_ID=$(
$HAMMER template list |
awk -F'|' '/PXEGrub2 CentOS UEFI Static Kickstart/ {
    gsub(/ /,"",$1)
    print $1
}'
)

ROCKY8_TEMPLATE_ID=$(
$HAMMER template list |
awk -F'|' '/PXEGrub2 RockyOS UEFI Static Kickstart/ {
    gsub(/ /,"",$1)
    print $1
}'
)

ROCKY9_TEMPLATE_ID=$(
$HAMMER template list |
awk -F'|' -v tmpl="$ROCKY_TEMPLATE_NAME" '
$0 ~ tmpl {
    gsub(/ /,"",$1)
    print $1
}'
)

###############################################################################
# Function
###############################################################################

set_default_template() {

    local OS_ID="$1"
    local OS_TITLE="$2"
    local TEMPLATE_NAME="$3"
    local TEMPLATE_ID="$4"

    info "Checking ${OS_TITLE}..."

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
            record_failure "${OS_TITLE} Default Template"
        fi

    fi

    echo
}

###############################################################################
# Configure Default Templates
###############################################################################

set_default_template \
    "$CENTOS_OS_ID" \
    "CentOSLinux 7" \
    "PXEGrub2 CentOS UEFI Static Kickstart" \
    "$CENTOS_TEMPLATE_ID"

set_default_template \
    "$ROCKY8_OS_ID" \
    "RockyLinux 8.10" \
    "PXEGrub2 RockyOS UEFI Static Kickstart" \
    "$ROCKY8_TEMPLATE_ID"

set_default_template \
    "$ROCKY9_OS_ID" \
    "$ROCKY_OS_TITLE" \
    "$ROCKY_TEMPLATE_NAME" \
    "$ROCKY9_TEMPLATE_ID"

###############################################################################
# Verification
###############################################################################

header "Default PXE Templates"

echo
info "CentOSLinux 7"

$HAMMER os info \
    --title "CentOSLinux 7" |
    awk '/Default templates:/,/Architectures:/'

echo

info "RockyLinux 8.10"

$HAMMER os info \
    --title "RockyLinux 8.10" |
    awk '/Default templates:/,/Architectures:/'

echo

info "${ROCKY_OS_TITLE}"

$HAMMER os info \
    --title "${ROCKY_OS_TITLE}" |
    awk '/Default templates:/,/Architectures:/'

echo

###############################################################################
# [6/6] Final Verification
###############################################################################

header "PXE Provisioning Configuration Summary"

echo
info "Installation Media"

$HAMMER medium list

echo

info "Operating Systems"

$HAMMER os list

echo

info "PXE Templates"

$HAMMER template list | grep -i UEFI || true

echo

info "Subnets"

$HAMMER subnet list

echo

###############################################################################
# Selected Rocky Configuration
###############################################################################

header "Selected Rocky Configuration"

echo "TARGET_VERSION      : ${TARGET_VERSION}"
echo "Operating System    : ${ROCKY_OS_TITLE}"
echo "Installation Media  : ${ROCKY_MEDIA_NAME}"
echo "PXE Template        : ${ROCKY_TEMPLATE_NAME}"
echo "Repository          : ${ROCKY_REPO_URL}"
echo "Kickstart           : ${ROCKY_KS_URL}"

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
