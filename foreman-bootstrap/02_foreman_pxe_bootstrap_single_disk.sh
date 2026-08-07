#!/bin/bash
###############################################################################
# 02 - Foreman PXE Bootstrap (Single Disk)
#
# Supports:
#   - CentOS Linux 7
#   - Rocky Linux 8.10
#   - Rocky Linux 9.2
#   - Rocky Linux 9.8
#
# Usage:
#   TARGET_VERSION=9.8 ./02_foreman_pxe_bootstrap_single_disk.sh
#   TARGET_VERSION=9.2 ./02_foreman_pxe_bootstrap_single_disk.sh
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

header "02 - Foreman PXE Bootstrap (Single Disk)"

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

        ROCKY_OS_TITLE="RockyLinux 9.2"

        ROCKY_TEMPLATE_NAME="PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

        ROCKY_TEMPLATE_FILE="/tmp/rocky92-singledisk.erb"

        ROCKY_KERNEL="/rocky92/vmlinuz"

        ROCKY_INITRD="/rocky92/initrd.img"

        ROCKY_REPO="http://192.168.253.136/repo/rocky9.2/"

        ROCKY_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/Rocky9_2_Golden_SingleDisk_Minimal.cfg"

        ;;

    9.8)

        ROCKY_OS_TITLE="RockyLinux 9.8"

        ROCKY_TEMPLATE_NAME="PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

        ROCKY_TEMPLATE_FILE="/tmp/rocky98-singledisk.erb"

        ROCKY_KERNEL="/rocky9/vmlinuz"

        ROCKY_INITRD="/rocky9/initrd.img"

        ROCKY_REPO="http://192.168.253.136/repo/rocky9/"

        ROCKY_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/Rocky9_Golden_SingleDisk_Minimal.cfg"

        ;;

    *)

        error "Unsupported TARGET_VERSION: ${TARGET_VERSION}"
        exit 1

        ;;

esac

###############################################################################
# [1/4] Generate PXE Templates
###############################################################################

header "[1/4] Generating PXE Templates"

###############################################################################
# CentOS 7 Template
###############################################################################

info "Generating CentOS 7 Single Disk template..."

cat >/tmp/centos-singledisk.erb <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- CentOSLinux
%>

set default=0
set timeout=5

menuentry 'Install CentOS 7 (Single Disk)' {

    linuxefi /centos/vmlinuz \
        inst.stage2=http://192.168.253.136/repo/centos/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/CentOS7_Golden_SingleDisk_Minimal.cfg \
        inst.text \
        BOOTIF=01-${net_default_mac} \
        hostname=<%= @host.name %>

    initrdefi /centos/initrd.img

}
EOF

ok "CentOS template generated."

echo

###############################################################################
# Rocky Linux 8 Template
###############################################################################

info "Generating Rocky Linux 8 Single Disk template..."

cat >/tmp/rocky8-singledisk.erb <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5

menuentry 'Install Rocky Linux 8.10 (Single Disk)' {

    linuxefi /rocky8/vmlinuz \
        inst.stage2=http://192.168.253.136/repo/rocky8/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/Rocky8_Golden_SingleDisk_Minimal.cfg \
        inst.text \
        BOOTIF=01-${net_default_mac} \
        hostname=<%= @host.name %>

    initrdefi /rocky8/initrd.img

}
EOF

ok "Rocky Linux 8 template generated."

echo

###############################################################################
# Selected Rocky Template
###############################################################################

info "Generating ${ROCKY_TEMPLATE_NAME}..."

cat >"${ROCKY_TEMPLATE_FILE}" <<EOF
<%#
name: ${ROCKY_TEMPLATE_NAME}
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5

menuentry 'Install ${ROCKY_OS_TITLE} (Single Disk)' {

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

ok "Selected Rocky template generated."

echo

###############################################################################
# [2/4] Import PXE Templates
###############################################################################

header "[2/4] Importing PXE Templates"

###############################################################################
# Function : Import Template
###############################################################################

import_template() {

    TEMPLATE_NAME="$1"
    TEMPLATE_FILE="$2"

    info "Checking ${TEMPLATE_NAME}..."

    if $HAMMER template info \
        --name "${TEMPLATE_NAME}" >/dev/null 2>&1; then

        skip "Template already exists."

    else

        info "Importing template..."

        $HAMMER template create \
            --name "${TEMPLATE_NAME}" \
            --type PXEGrub2 \
            --file "${TEMPLATE_FILE}"

        if [ $? -eq 0 ]; then
            ok "Template imported."
        else
            error "Template import failed."
            record_failure "${TEMPLATE_NAME}"
        fi

    fi

    echo
}

###############################################################################
# Import CentOS Template
###############################################################################

import_template \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart" \
    "/tmp/centos-singledisk.erb"

###############################################################################
# Import Rocky Linux 8 Template
###############################################################################

import_template \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" \
    "/tmp/rocky8-singledisk.erb"

###############################################################################
# Import Selected Rocky Template
###############################################################################

import_template \
    "${ROCKY_TEMPLATE_NAME}" \
    "${ROCKY_TEMPLATE_FILE}"

###############################################################################
# Verification
###############################################################################

header "PXE Templates"

$HAMMER template list | grep -i SingleDisk || true

echo

###############################################################################
# [3/4] Assign Templates to Operating Systems
###############################################################################

header "[3/4] Assigning PXE Templates"

###############################################################################
# Function : Assign Template
###############################################################################

assign_template() {

    OS_TITLE="$1"
    TEMPLATE_NAME="$2"

    info "Checking template assignment for ${OS_TITLE}..."

    if $HAMMER os info \
        --title "${OS_TITLE}" | \
        grep -q "${TEMPLATE_NAME}"; then

        skip "Template already assigned."

    else

        info "Assigning template..."

        $HAMMER os add-provisioning-template \
            --title "${OS_TITLE}" \
            --provisioning-template "${TEMPLATE_NAME}"

        if [ $? -eq 0 ]; then
            ok "Template assigned."
        else
            error "Template assignment failed."
            record_failure "${OS_TITLE} Template Assignment"
        fi

    fi

    echo
}

###############################################################################
# CentOS Linux 7
###############################################################################

assign_template \
    "CentOSLinux 7" \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

###############################################################################
# Rocky Linux 8.10
###############################################################################

assign_template \
    "RockyLinux 8.10" \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

###############################################################################
# Selected Rocky Linux Version
###############################################################################

assign_template \
    "${ROCKY_OS_TITLE}" \
    "${ROCKY_TEMPLATE_NAME}"

###############################################################################
# Verification
###############################################################################

header "PXE Template Assignments"

echo
info "CentOSLinux 7"

$HAMMER os info \
    --title "CentOSLinux 7" | \
    awk '/Templates:/,/Operating systems:/'

echo

info "RockyLinux 8.10"

$HAMMER os info \
    --title "RockyLinux 8.10" | \
    awk '/Templates:/,/Operating systems:/'

echo

info "${ROCKY_OS_TITLE}"

$HAMMER os info \
    --title "${ROCKY_OS_TITLE}" | \
    awk '/Templates:/,/Operating systems:/'

echo

###############################################################################
# [4/4] Configure Default PXE Templates
###############################################################################

header "[4/4] Setting Default PXE Templates"

###############################################################################
# Function : Configure Default Template
###############################################################################

set_default_template() {

    OS_TITLE="$1"
    TEMPLATE_NAME="$2"

    OS_ID=$(
        $HAMMER os list |
        awk -F'|' -v os="$OS_TITLE" '
        $0 ~ os {
            gsub(/ /,"",$1)
            print $1
            exit
        }'
    )

    TEMPLATE_ID=$(
        $HAMMER template list |
        awk -F'|' -v tmpl="$TEMPLATE_NAME" '
        $0 ~ tmpl {
            gsub(/ /,"",$1)
            print $1
            exit
        }'
    )

    if [[ -z "$OS_ID" || -z "$TEMPLATE_ID" ]]; then
        error "Unable to locate ${OS_TITLE} or ${TEMPLATE_NAME}"
        record_failure "${OS_TITLE} Default Template"
        echo
        return
    fi

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
# Configure Defaults
###############################################################################

set_default_template \
    "CentOSLinux 7" \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

set_default_template \
    "RockyLinux 8.10" \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

set_default_template \
    "${ROCKY_OS_TITLE}" \
    "${ROCKY_TEMPLATE_NAME}"

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
# Summary
###############################################################################

header "Single Disk PXE Configuration Summary"

echo
info "PXE Templates"

$HAMMER template list | grep -i SingleDisk || true

echo

info "Operating Systems"

$HAMMER os list

echo

###############################################################################
# Selected Rocky Configuration
###############################################################################

header "Selected Rocky Configuration"

echo "TARGET_VERSION      : ${TARGET_VERSION}"
echo "Operating System    : ${ROCKY_OS_TITLE}"
echo "PXE Template        : ${ROCKY_TEMPLATE_NAME}"
echo "Repository          : ${ROCKY_REPO}"
echo "Kickstart           : ${ROCKY_KS}"

echo

###############################################################################
# Script Summary
###############################################################################

header "02 - Foreman PXE Bootstrap (Single Disk) Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
    ok "Single Disk PXE Bootstrap completed successfully."
else
    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

    for step in "${FAILED_STEPS[@]}"; do
        error "$step"
    done
fi

echo

exit 0
