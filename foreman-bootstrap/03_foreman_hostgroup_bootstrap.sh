#!/bin/bash
###############################################################################
# 03 - Foreman HostGroup Bootstrap
# Creates Foreman Host Groups
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

echo

###############################################################################
# 1. Create Host Groups
###############################################################################

header "[1/1] Creating Host Groups"

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
        record_failure "VGS HOSTS CentOS 7"
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
        ok "Rocky 8 Host Group created."
    else
        error "Host Group creation failed."
        record_failure "VGS HOSTS ROCKY 8"
    fi

fi

echo

###############################################################################
# Rocky Linux 9.8 Host Group
###############################################################################

info "Checking Rocky Linux 9.8 Host Group..."

if $HAMMER hostgroup info \
    --organization "Default Organization" \
    --name "VGS HOSTS ROCKY 9.8" >/dev/null 2>&1; then

    skip "Host Group 'VGS HOSTS ROCKY 9.8' already exists."

else

    info "Creating Rocky Linux 9.8 Host Group..."

    $HAMMER hostgroup create \
        --organization "Default Organization" \
        --name "VGS HOSTS ROCKY 9.8" \
        --architecture x86_64 \
        --operatingsystem "RockyLinux 9.8" \
        --medium "Rocky 9.8 Remote" \
        --partition-table "Kickstart default" \
        --pxe-loader "Grub2 UEFI" \
        --domain "vgs.com" \
        --subnet "vgs-subnet-rockyos" \
        --content-source "cent-07-01.vgs.com" \
        --content-view "Rocky9.8-CV" \
        --lifecycle-environment "Library"

    if [ $? -eq 0 ]; then
        ok "Rocky 9.8 Host Group created."
    else
        error "Host Group creation failed."
        record_failure "VGS HOSTS ROCKY 9.8"
    fi

fi

echo


###############################################################################
# Rocky Linux 9.2 Host Group
###############################################################################

info "Checking Rocky Linux 9.2 Host Group..."

if $HAMMER hostgroup info \
    --organization "Default Organization" \
    --name "VGS HOSTS ROCKY 9.2" >/dev/null 2>&1; then

    skip "Host Group 'VGS HOSTS ROCKY 9.2' already exists."

else

    info "Creating Rocky Linux 9.2 Host Group..."

    $HAMMER hostgroup create \
        --organization "Default Organization" \
        --name "VGS HOSTS ROCKY 9.2" \
        --architecture x86_64 \
        --operatingsystem "RockyLinux 9.2" \
        --medium "Rocky 9.2 Remote" \
        --partition-table "Kickstart default" \
        --pxe-loader "Grub2 UEFI" \
        --domain "vgs.com" \
        --subnet "vgs-subnet-rockyos" \
        --content-source "cent-07-01.vgs.com" \
        --content-view "Rocky9.2-CV" \
        --lifecycle-environment "Library"

    if [ $? -eq 0 ]; then
        ok "Rocky 9.2 Host Group created."
    else
        error "Host Group creation failed."
        record_failure "VGS HOSTS ROCKY 9.2"
    fi

fi

echo


###############################################################################
# Verification
###############################################################################

header "[Verification] Host Groups"

echo
info "Host Groups"
$HAMMER hostgroup list


echo
info "CentOS Host Group"
$HAMMER hostgroup info \
  --organization "Default Organization" \
  --name "VGS HOSTS CENTOS 7"

echo
info "Rocky 8 Host Group"
$HAMMER hostgroup info \
  --organization "Default Organization" \
  --name "VGS HOSTS ROCKY 8"

echo
info "Rocky 9.8 Host Group"

$HAMMER hostgroup info \
  --organization "Default Organization" \
  --name "VGS HOSTS ROCKY 9.8"

echo
info "Rocky 9.2 Host Group"

$HAMMER hostgroup info \
  --organization "Default Organization" \
  --name "VGS HOSTS ROCKY 9.2"


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
