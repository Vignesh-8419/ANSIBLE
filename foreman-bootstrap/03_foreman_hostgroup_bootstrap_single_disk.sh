#!/bin/bash
###############################################################################
# 03 - Foreman HostGroup Bootstrap
# Supports CentOS 7, Rocky Linux 8.10, Rocky Linux 9.2 and Rocky Linux 9.8
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

header "03 - Foreman HostGroup Bootstrap"

###############################################################################
# Variables
###############################################################################

FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"

HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"

TARGET_VERSION="${TARGET_VERSION:-9.8}"

case "$TARGET_VERSION" in
    9.2)
        ROCKY_OS="RockyLinux 9.2"
        ROCKY_HOSTGROUP="VGS HOSTS ROCKY 9.2"
        ROCKY_MEDIUM="Rocky 9.2 Remote"
        ROCKY_CONTENT_VIEW="Rocky9.2-CV"
        ;;
    9.8)
        ROCKY_OS="RockyLinux 9.8"
        ROCKY_HOSTGROUP="VGS HOSTS ROCKY 9.8"
        ROCKY_MEDIUM="Rocky 9 Remote"
        ROCKY_CONTENT_VIEW="Rocky9.8-CV"
        ;;
    *)
        echo "Unsupported TARGET_VERSION: $TARGET_VERSION"
        exit 1
        ;;
esac

echo

###############################################################################
# [1/2] Create Host Groups
###############################################################################

header "[1/2] Creating Host Groups"

###############################################################################
# CentOS 7 Host Group
###############################################################################

info "Checking CentOS 7 Host Group..."

if $HAMMER hostgroup info \
    --organization "Default Organization" \
    --name "VGS HOSTS CENTOS 7" >/dev/null 2>&1; then

    skip "Host Group 'VGS HOSTS CENTOS 7' already exists."

else

    info "Creating CentOS 7 Host Group..."

    $HAMMER hostgroup create \
        --organization "Default Organization" \
        --name "VGS HOSTS CENTOS 7" \
        --architecture x86_64 \
        --operatingsystem "CentOSLinux 7" \
        --medium "CentOS 7 Remote" \
        --partition-table "Kickstart default" \
        --pxe-loader "Grub2 UEFI" \
        --domain "vgs.com" \
        --subnet "vgs-subnet-centos" \
        --content-source "cent-07-01.vgs.com" \
        --content-view "CentOS7-CV" \
        --lifecycle-environment "Library"

    if [ $? -eq 0 ]; then
        ok "CentOS 7 Host Group created."
    else
        error "Host Group creation failed."
        record_failure "VGS HOSTS CENTOS 7"
    fi

fi

echo

###############################################################################
# Rocky Linux 8 Host Group
###############################################################################

info "Checking Rocky Linux 8 Host Group..."

if $HAMMER hostgroup info \
    --organization "Default Organization" \
    --name "VGS HOSTS ROCKY 8" >/dev/null 2>&1; then

    skip "Host Group 'VGS HOSTS ROCKY 8' already exists."

else

    info "Creating Rocky Linux 8 Host Group..."

    $HAMMER hostgroup create \
        --organization "Default Organization" \
        --name "VGS HOSTS ROCKY 8" \
        --architecture x86_64 \
        --operatingsystem "RockyLinux 8.10" \
        --medium "Rocky 8 Remote" \
        --partition-table "Kickstart default" \
        --pxe-loader "Grub2 UEFI" \
        --domain "vgs.com" \
        --subnet "vgs-subnet-rockyos" \
        --content-source "cent-07-01.vgs.com" \
        --content-view "Rocky8-CV" \
        --lifecycle-environment "Library"

    if [ $? -eq 0 ]; then
        ok "Rocky Linux 8 Host Group created."
    else
        error "Host Group creation failed."
        record_failure "VGS HOSTS ROCKY 8"
    fi

fi

echo

###############################################################################
# Rocky Linux 9 Host Group (9.2 or 9.8)
###############################################################################

info "Checking ${ROCKY_HOSTGROUP} Host Group..."

if $HAMMER hostgroup info \
    --organization "Default Organization" \
    --name "${ROCKY_HOSTGROUP}" >/dev/null 2>&1; then

    skip "Host Group '${ROCKY_HOSTGROUP}' already exists."

else

    info "Creating ${ROCKY_HOSTGROUP}..."

    $HAMMER hostgroup create \
        --organization "Default Organization" \
        --name "${ROCKY_HOSTGROUP}" \
        --architecture x86_64 \
        --operatingsystem "${ROCKY_OS}" \
        --medium "${ROCKY_MEDIUM}" \
        --partition-table "Kickstart default" \
        --pxe-loader "Grub2 UEFI" \
        --domain "vgs.com" \
        --subnet "vgs-subnet-rockyos" \
        --content-source "cent-07-01.vgs.com" \
        --content-view "${ROCKY_CONTENT_VIEW}" \
        --lifecycle-environment "Library"

    if [ $? -eq 0 ]; then
        ok "${ROCKY_HOSTGROUP} created."
    else
        error "Host Group creation failed."
        record_failure "${ROCKY_HOSTGROUP}"
    fi

fi

echo

###############################################################################
# [2/2] Verification
###############################################################################

header "[2/2] Verification"

echo
info "Host Groups"

$HAMMER hostgroup list

echo

###############################################################################
# CentOS 7 Host Group
###############################################################################

echo
info "CentOS 7 Host Group"

$HAMMER hostgroup info \
    --organization "Default Organization" \
    --name "VGS HOSTS CENTOS 7"

echo

###############################################################################
# Rocky Linux 8 Host Group
###############################################################################

info "Rocky Linux 8 Host Group"

$HAMMER hostgroup info \
    --organization "Default Organization" \
    --name "VGS HOSTS ROCKY 8"

echo

###############################################################################
# Selected Rocky Linux 9 Host Group
###############################################################################

info "${ROCKY_HOSTGROUP}"

$HAMMER hostgroup info \
    --organization "Default Organization" \
    --name "${ROCKY_HOSTGROUP}"

echo

###############################################################################
# Summary
###############################################################################

header "03 - Foreman HostGroup Bootstrap Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then

    ok "Foreman HostGroup Bootstrap completed successfully."

else

    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

    for step in "${FAILED_STEPS[@]}"; do
        error "$step"
    done

fi

echo
