#!/bin/bash
###############################################################################
# 02 - Foreman PXE Bootstrap (Single Disk)
#
# Supports:
#   - CentOS Linux 7 SingleDisk
#   - Rocky Linux 8.10 SingleDisk
#   - Rocky Linux 9.2 SingleDisk
#   - Rocky Linux 9.8 SingleDisk
#
# Usage:
#
#   TARGET_VERSION=9.8 ./02_foreman_pxe_bootstrap_single_disk.sh
#   TARGET_VERSION=9.2 ./02_foreman_pxe_bootstrap_single_disk.sh
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

        ROCKY_SINGLE_OS="RockyLinux 9.2 SingleDisk"
        ROCKY_SINGLE_TEMPLATE="PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

        ROCKY_TEMPLATE_FILE="/tmp/rocky92-singledisk.erb"

        ROCKY_KERNEL="/rocky92/vmlinuz"
        ROCKY_INITRD="/rocky92/initrd.img"

        ROCKY_REPO="http://192.168.253.136/repo/rocky9.2/"
        ROCKY_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/Rocky9_2_Golden_SingleDisk_Minimal.cfg"

        ;;

    9.8)

        ROCKY_SINGLE_OS="RockyLinux 9.8 SingleDisk"
        ROCKY_SINGLE_TEMPLATE="PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

        ROCKY_TEMPLATE_FILE="/tmp/rocky98-singledisk.erb"

        ROCKY_KERNEL="/rocky9/vmlinuz"
        ROCKY_INITRD="/rocky9/initrd.img"

        ROCKY_REPO="http://192.168.253.136/repo/rocky9/"
        ROCKY_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/Rocky9_Golden_SingleDisk_Minimal.cfg"

        ;;

    *)

        error "Unsupported TARGET_VERSION : ${TARGET_VERSION}"
        exit 1

        ;;

esac

###############################################################################
# Common Operating Systems
###############################################################################

CENTOS_SINGLE_OS="CentOSLinux 7 SingleDisk"

ROCKY8_SINGLE_OS="RockyLinux 8.10 SingleDisk"

###############################################################################
# [1/4] Creating Single Disk PXE Templates
###############################################################################

header "[1/4] Creating Single Disk PXE Templates"

###############################################################################
# CentOS 7 Single Disk Template
###############################################################################

info "Generating CentOS 7 Single Disk template..."

cat > /tmp/centos-singledisk.erb <<'EOF'
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
        inst.ks.device=bootif \
        BOOTIF=01-${net_default_mac} \
        hostname=<%= @host.name %>

    initrdefi /centos/initrd.img
}
EOF

ok "CentOS template generated."

echo

###############################################################################
# Rocky Linux 8 Single Disk Template
###############################################################################

info "Generating Rocky Linux 8 Single Disk template..."

cat > /tmp/rocky8-singledisk.erb <<'EOF'
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
        inst.ks.device=bootif \
        BOOTIF=01-${net_default_mac} \
        hostname=<%= @host.name %>

    initrdefi /rocky8/initrd.img
}
EOF

ok "Rocky Linux 8 template generated."

echo

###############################################################################
# Selected Rocky Single Disk Template
###############################################################################

info "Generating ${ROCKY_SINGLE_TEMPLATE}..."

cat > "${ROCKY_TEMPLATE_FILE}" <<EOF
<%#
name: ${ROCKY_SINGLE_TEMPLATE}
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5

menuentry 'Install ${ROCKY_SINGLE_OS} (Single Disk)' {

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
# [2/4] Import Templates
###############################################################################

header "[2/4] Importing Single Disk Templates"

###############################################################################
# Function : Import Template
###############################################################################

import_template() {

    local TEMPLATE_NAME="$1"
    local TEMPLATE_FILE="$2"

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
            error "Failed to import ${TEMPLATE_NAME}"
            record_failure "${TEMPLATE_NAME}"
        fi

    fi

    echo

}

###############################################################################
# Import Templates
###############################################################################

import_template \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart" \
    "/tmp/centos-singledisk.erb"

import_template \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" \
    "/tmp/rocky8-singledisk.erb"

import_template \
    "${ROCKY_SINGLE_TEMPLATE}" \
    "${ROCKY_TEMPLATE_FILE}"

###############################################################################
# Verification
###############################################################################

header "Single Disk PXE Templates"

$HAMMER template list | grep "SingleDisk"

echo

###############################################################################
# Function : Associate Template
###############################################################################

associate_template() {

    local OS_TITLE="$1"
    local TEMPLATE_NAME="$2"

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
            error "Failed to assign template."
            record_failure "${OS_TITLE}"
        fi

    fi

    echo

}

###############################################################################
# Associate Templates
###############################################################################

associate_template \
    "${CENTOS_SINGLE_OS}" \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

associate_template \
    "${ROCKY8_SINGLE_OS}" \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

associate_template \
    "${ROCKY_SINGLE_OS}" \
    "${ROCKY_SINGLE_TEMPLATE}"

###############################################################################
# Verification
###############################################################################

echo

info "${CENTOS_SINGLE_OS}"

$HAMMER os info \
    --title "${CENTOS_SINGLE_OS}" | \
    awk '/Templates:/,/Parameters:/'

echo

info "${ROCKY8_SINGLE_OS}"

$HAMMER os info \
    --title "${ROCKY8_SINGLE_OS}" | \
    awk '/Templates:/,/Parameters:/'

echo

info "${ROCKY_SINGLE_OS}"

$HAMMER os info \
    --title "${ROCKY_SINGLE_OS}" | \
    awk '/Templates:/,/Parameters:/'

echo

###############################################################################
# [3/4] Setting Default PXE Templates
###############################################################################

header "[3/4] Setting Default PXE Templates"

###############################################################################
# Function : Set Default Template
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
        grep -q "${TEMPLATE_NAME}"; then

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
# Configure Single Disk Default Templates
###############################################################################

set_default_template \
    "${CENTOS_SINGLE_OS}" \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

set_default_template \
    "${ROCKY8_SINGLE_OS}" \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

set_default_template \
    "${ROCKY_SINGLE_OS}" \
    "${ROCKY_SINGLE_TEMPLATE}"

###############################################################################
# Verification
###############################################################################

header "Default Single Disk PXE Templates"

echo
info "${CENTOS_SINGLE_OS}"

$HAMMER os info \
    --title "${CENTOS_SINGLE_OS}" |
    awk '/Default templates:/,/Architectures:/'

echo

info "${ROCKY8_SINGLE_OS}"

$HAMMER os info \
    --title "${ROCKY8_SINGLE_OS}" |
    awk '/Default templates:/,/Architectures:/'

echo

info "${ROCKY_SINGLE_OS}"

$HAMMER os info \
    --title "${ROCKY_SINGLE_OS}" |
    awk '/Default templates:/,/Architectures:/'

echo

###############################################################################
# [4/4] Summary
###############################################################################

header "Single Disk PXE Provisioning Summary"

echo
info "PXE Templates"

$HAMMER template list | grep "SingleDisk"

echo

info "Operating Systems"

$HAMMER os list | grep "SingleDisk"

echo

header "Selected Single Disk Configuration"

echo "TARGET_VERSION      : ${TARGET_VERSION}"
echo "Operating System    : ${ROCKY_SINGLE_OS}"
echo "PXE Template        : ${ROCKY_SINGLE_TEMPLATE}"
echo "Repository          : ${ROCKY_REPO}"
echo "Kickstart           : ${ROCKY_KS}"

echo

###############################################################################
# Summary
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
