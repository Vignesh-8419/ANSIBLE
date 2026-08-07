#!/bin/bash
###############################################################################
# 03 - Foreman Hostgroup Bootstrap (Single Disk)
#
# Supports:
#   - CentOS Linux 7
#   - Rocky Linux 8.10
#   - Rocky Linux 9.2
#   - Rocky Linux 9.8
#
# Usage:
#   TARGET_VERSION=9.8 ./03_foreman_hostgroup_bootstrap_single_disk.sh
#   TARGET_VERSION=9.2 ./03_foreman_hostgroup_bootstrap_single_disk.sh
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

header "03 - Foreman Hostgroup Bootstrap (Single Disk)"

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

        ROCKY_OS="RockyLinux 9.2 SingleDisk"
        ROCKY_MEDIUM="Rocky 9.2 Remote"
        ROCKY_HOSTGROUP="Rocky-9.2-SingleDisk"

        ;;

    9.8)

        ROCKY_OS="RockyLinux 9.8 SingleDisk"
        ROCKY_MEDIUM="Rocky 9 Remote"
        ROCKY_HOSTGROUP="Rocky-9.8-SingleDisk"

        ;;

    *)

        error "Unsupported TARGET_VERSION: $TARGET_VERSION"
        exit 1

        ;;

esac

###############################################################################
# Common Hostgroups
###############################################################################

CENTOS_HOSTGROUP="CentOS-7-SingleDisk"
ROCKY8_HOSTGROUP="Rocky-8.10-SingleDisk"

###############################################################################
# [1/2] Create Hostgroups
###############################################################################

header "[1/2] Creating Single Disk Hostgroups"

create_hostgroup() {

    local HG_NAME="$1"
    local OS_TITLE="$2"
    local MEDIUM="$3"
    local SUBNET="$4"

    info "Checking Hostgroup : ${HG_NAME}"

    if $HAMMER hostgroup info \
        --name "${HG_NAME}" >/dev/null 2>&1; then

        skip "Hostgroup already exists."

    else

        info "Creating Hostgroup..."

        $HAMMER hostgroup create \
            --name "${HG_NAME}" \
            --organizations "Default Organization" \
            --locations "Default Location" \
            --operatingsystem "${OS_TITLE}" \
            --architecture x86_64 \
            --medium "${MEDIUM}" \
            --domain vgs.com \
            --subnet "${SUBNET}" \
            --root-pass "changeme" \
            --pxe-loader "Grub2 UEFI"

        if [ $? -eq 0 ]; then
            ok "Hostgroup created."
        else
            error "Hostgroup creation failed."
            record_failure "${HG_NAME}"
        fi

    fi

    echo
}

###############################################################################
# CentOS 7
###############################################################################

create_hostgroup \
    "${CENTOS_HOSTGROUP}" \
    "CentOSLinux 7 SingleDisk" \
    "CentOS 7 Remote" \
    "vgs-subnet-centos"

###############################################################################
# Rocky Linux 8.10
###############################################################################

create_hostgroup \
    "${ROCKY8_HOSTGROUP}" \
    "RockyLinux 8.10 SingleDisk" \
    "Rocky 8 Remote" \
    "vgs-subnet-rockyos"

###############################################################################
# Rocky Linux (Selected Version)
###############################################################################

create_hostgroup \
    "${ROCKY_HOSTGROUP}" \
    "${ROCKY_OS}" \
    "${ROCKY_MEDIUM}" \
    "vgs-subnet-rockyos"

###############################################################################
# Verification
###############################################################################

header "Hostgroups"

$HAMMER hostgroup list

echo

###############################################################################
# [2/2] Verification
###############################################################################

header "[2/2] Verification"

echo
info "Hostgroups"

$HAMMER hostgroup list

echo

info "CentOSLinux 7 SingleDisk"

$HAMMER hostgroup info \
    --name "${CENTOS_HOSTGROUP}"

echo

info "RockyLinux 8.10 SingleDisk"

$HAMMER hostgroup info \
    --name "${ROCKY8_HOSTGROUP}"

echo

info "${ROCKY_OS}"

$HAMMER hostgroup info \
    --name "${ROCKY_HOSTGROUP}"

echo

###############################################################################
# Selected Configuration
###############################################################################

header "Selected Single Disk Configuration"

echo "TARGET_VERSION : ${TARGET_VERSION}"
echo "Operating System : ${ROCKY_OS}"
echo "Installation Media : ${ROCKY_MEDIUM}"
echo "Hostgroup : ${ROCKY_HOSTGROUP}"

echo

###############################################################################
# Summary
###############################################################################

header "03 - Foreman Hostgroup Bootstrap (Single Disk) Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then

    ok "Single Disk Hostgroup Bootstrap completed successfully."

else

    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

    for step in "${FAILED_STEPS[@]}"; do
        error "$step"
    done

fi

echo

exit 0

