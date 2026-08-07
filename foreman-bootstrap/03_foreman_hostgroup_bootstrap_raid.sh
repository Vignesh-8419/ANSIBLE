#!/bin/bash
###############################################################################
# 03 - Foreman Hostgroup Bootstrap (RAID)
#
# Creates RAID Hostgroups for:
#   - CentOS Linux 7
#   - Rocky Linux 8.10
#   - Rocky Linux 9.2
#   - Rocky Linux 9.8
#
# Usage:
#
#   TARGET_VERSION=9.8 ./03_foreman_hostgroup_bootstrap_raid.sh
#   TARGET_VERSION=9.2 ./03_foreman_hostgroup_bootstrap_raid.sh
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

header "03 - Foreman Hostgroup Bootstrap (RAID)"

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

        ROCKY_OS="RockyLinux 9.2 RAID"
        ROCKY_HOSTGROUP="Rocky-9.2-RAID"
        ROCKY_MEDIUM="Rocky 9.2 Remote"

        ;;

    9.8)

        ROCKY_OS="RockyLinux 9.8 RAID"
        ROCKY_HOSTGROUP="Rocky-9.8-RAID"
        ROCKY_MEDIUM="Rocky 9 Remote"

        ;;

    *)

        error "Unsupported TARGET_VERSION : ${TARGET_VERSION}"
        exit 1

        ;;

esac

###############################################################################
# Common Variables
###############################################################################

CENTOS_OS="CentOSLinux 7 RAID"
CENTOS_HOSTGROUP="CentOS-7-RAID"

ROCKY8_OS="RockyLinux 8.10 RAID"
ROCKY8_HOSTGROUP="Rocky-8.10-RAID"

###############################################################################
# [1/4] Creating RAID Hostgroups
###############################################################################

header "[1/4] Creating RAID Hostgroups"

###############################################################################
# Function : Create Hostgroup
###############################################################################

create_hostgroup() {

    local HG_NAME="$1"
    local OS_TITLE="$2"
    local MEDIUM="$3"

    info "Checking Hostgroup : ${HG_NAME}"

    if $HAMMER hostgroup info \
        --name "${HG_NAME}" >/dev/null 2>&1; then

        skip "${HG_NAME} already exists."

    else

        info "Creating ${HG_NAME}..."

        $HAMMER hostgroup create \
            --name "${HG_NAME}" \
            --organization "Default Organization" \
            --location "Default Location" \
            --architecture "x86_64" \
            --operatingsystem "${OS_TITLE}" \
            --medium "${MEDIUM}" \
            --partition-table "Kickstart default" \
            --domain "vgs.com" \
            --subnet "vgs-subnet-rockyos" \
            --realm "" \
            --root-pass "changeme"

        if [ $? -eq 0 ]; then
            ok "${HG_NAME} created."
        else
            error "Failed to create ${HG_NAME}"
            record_failure "${HG_NAME}"
        fi

    fi

    echo

}

###############################################################################
# Create CentOS RAID Hostgroup
###############################################################################

create_hostgroup \
    "${CENTOS_HOSTGROUP}" \
    "${CENTOS_OS}" \
    "CentOS 7 Remote"

###############################################################################
# Create Rocky 8 RAID Hostgroup
###############################################################################

create_hostgroup \
    "${ROCKY8_HOSTGROUP}" \
    "${ROCKY8_OS}" \
    "Rocky 8 Remote"

###############################################################################
# Create Selected Rocky RAID Hostgroup
###############################################################################

create_hostgroup \
    "${ROCKY_HOSTGROUP}" \
    "${ROCKY_OS}" \
    "${ROCKY_MEDIUM}"

###############################################################################
# Verification
###############################################################################

header "RAID Hostgroups"

$HAMMER hostgroup list

echo

###############################################################################
# [2/4] Updating RAID Hostgroups
###############################################################################

header "[2/4] Updating RAID Hostgroups"

###############################################################################
# Function : Update Hostgroup
###############################################################################

update_hostgroup() {

    local HG_NAME="$1"
    local OS_TITLE="$2"
    local MEDIUM="$3"

    info "Updating Hostgroup : ${HG_NAME}"

    $HAMMER hostgroup update \
        --name "${HG_NAME}" \
        --organization "Default Organization" \
        --location "Default Location" \
        --architecture "x86_64" \
        --operatingsystem "${OS_TITLE}" \
        --medium "${MEDIUM}" \
        --partition-table "Kickstart default" \
        --domain "vgs.com" \
        --subnet "vgs-subnet-rockyos" \
        --pxe-loader "Grub2 UEFI" \
        --root-pass "changeme"

    if [ $? -eq 0 ]; then
        ok "${HG_NAME} updated."
    else
        error "Failed to update ${HG_NAME}"
        record_failure "${HG_NAME}"
    fi

    echo

}

###############################################################################
# Update CentOS RAID Hostgroup
###############################################################################

update_hostgroup \
    "${CENTOS_HOSTGROUP}" \
    "${CENTOS_OS}" \
    "CentOS 7 Remote"

###############################################################################
# Update Rocky 8 RAID Hostgroup
###############################################################################

update_hostgroup \
    "${ROCKY8_HOSTGROUP}" \
    "${ROCKY8_OS}" \
    "Rocky 8 Remote"

###############################################################################
# Update Selected Rocky RAID Hostgroup
###############################################################################

update_hostgroup \
    "${ROCKY_HOSTGROUP}" \
    "${ROCKY_OS}" \
    "${ROCKY_MEDIUM}"

###############################################################################
# Verification
###############################################################################

header "RAID Hostgroup Details"

echo

info "${CENTOS_HOSTGROUP}"

$HAMMER hostgroup info \
    --name "${CENTOS_HOSTGROUP}"

echo

info "${ROCKY8_HOSTGROUP}"

$HAMMER hostgroup info \
    --name "${ROCKY8_HOSTGROUP}"

echo

info "${ROCKY_HOSTGROUP}"

$HAMMER hostgroup info \
    --name "${ROCKY_HOSTGROUP}"

echo

###############################################################################
# [3/4] Verification
###############################################################################

header "[3/4] Verifying RAID Hostgroups"

###############################################################################
# Verify RAID Hostgroups
###############################################################################

echo

$HAMMER hostgroup list

echo

###############################################################################
# Display Selected Configuration
###############################################################################

header "Selected RAID Configuration"

echo "TARGET_VERSION      : ${TARGET_VERSION}"
echo "Operating System    : ${ROCKY_OS}"
echo "Installation Media  : ${ROCKY_MEDIUM}"
echo "RAID Hostgroup      : ${ROCKY_HOSTGROUP}"

echo

###############################################################################
# Summary
###############################################################################

header "03 - Foreman Hostgroup Bootstrap (RAID) Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then

    ok "RAID Hostgroup Bootstrap completed successfully."

else

    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

    for step in "${FAILED_STEPS[@]}"; do
        error "$step"
    done

fi

echo

###############################################################################
# Hostgroups Created
###############################################################################

header "Configured RAID Hostgroups"

printf "%-35s %s\n" "CentOS"        "${CENTOS_HOSTGROUP}"
printf "%-35s %s\n" "Rocky Linux 8" "${ROCKY8_HOSTGROUP}"
printf "%-35s %s\n" "Selected Rocky" "${ROCKY_HOSTGROUP}"

echo

###############################################################################
# Script Completed
###############################################################################

ok "RAID Hostgroup bootstrap finished."

exit 0
