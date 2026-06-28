#!/bin/bash
###############################################################################
# Script : 01-media-os.sh
#
# Purpose:
#   Create Installation Media
#   Create Operating Systems
#
###############################################################################

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$BASE_DIR/config.sh"
source "$BASE_DIR/lib/logger.sh"
source "$BASE_DIR/lib/common.sh"

header "STEP 01 - Installation Media & Operating Systems"

###############################################################################
# Installation Media
###############################################################################

log_step "Creating Installation Media"

###############################################################################
# CentOS Media
###############################################################################

create_media \
    "$CENTOS_MEDIA_NAME" \
    "$CENTOS_MEDIA_URL"

###############################################################################
# Rocky Media
###############################################################################

create_media \
    "$ROCKY_MEDIA_NAME" \
    "$ROCKY_MEDIA_URL"

###############################################################################
# Verify Installation Media
###############################################################################

log_step "Verifying Installation Media"

if media_exists "$CENTOS_MEDIA_NAME"
then
    log_success "$CENTOS_MEDIA_NAME verified"
else
    log_error "$CENTOS_MEDIA_NAME missing"
    exit 1
fi

if media_exists "$ROCKY_MEDIA_NAME"
then
    log_success "$ROCKY_MEDIA_NAME verified"
else
    log_error "$ROCKY_MEDIA_NAME missing"
    exit 1
fi

###############################################################################
# Display Media Summary
###############################################################################

echo
echo "Installed Media"
echo "---------------"

$HAMMER medium list

echo

###############################################################################
# Continue to Operating Systems
###############################################################################

log_step "Creating Operating Systems"

###############################################################################
# Operating Systems
###############################################################################

###############################################################################
# Create CentOS Linux 7
###############################################################################

create_os \
    "$CENTOS_OS_NAME" \
    "$CENTOS_MAJOR" \
    "" \
    "$CENTOS_MEDIA_NAME"

###############################################################################
# Create Rocky Linux 8.10
###############################################################################

create_os \
    "$ROCKY_OS_NAME" \
    "$ROCKY_MAJOR" \
    "$ROCKY_MINOR" \
    "$ROCKY_MEDIA_NAME"

###############################################################################
# Wait Until OS Objects Exist
###############################################################################

wait_for_object \
    "os list" \
    "$CENTOS_OS_NAME"

wait_for_object \
    "os list" \
    "$ROCKY_OS_NAME"

###############################################################################
# Verification
###############################################################################

log_step "Verifying Operating Systems"

if os_exists "$CENTOS_OS_NAME"
then
    log_success "Verified : ${CENTOS_OS_NAME} ${CENTOS_MAJOR}"
else
    log_error "Verification failed : ${CENTOS_OS_NAME}"
    exit 1
fi

if os_exists "$ROCKY_OS_NAME"
then
    log_success "Verified : ${ROCKY_OS_NAME} ${ROCKY_MAJOR}.${ROCKY_MINOR}"
else
    log_error "Verification failed : ${ROCKY_OS_NAME}"
    exit 1
fi

###############################################################################
# Summary
###############################################################################

echo
echo "============================================================"
echo "Installation Media"
echo "============================================================"

$HAMMER medium list

echo

echo "============================================================"
echo "Operating Systems"
echo "============================================================"

$HAMMER os list

echo

log_success "STEP 01 completed successfully."

exit 0
