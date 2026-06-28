#!/bin/bash
###############################################################################
# Foreman / Katello Bootstrap Installer
#
# Version : 1.0
# Author  : VGS
#
# Description:
# Master bootstrap script for configuring Foreman + Katello from scratch.
#
###############################################################################

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$BASE_DIR/config.sh"
source "$BASE_DIR/lib/logger.sh"
source "$BASE_DIR/lib/common.sh"
source "$BASE_DIR/lib/hammer.sh"

LOG_FILE="$BASE_DIR/logs/bootstrap.log"

mkdir -p "$BASE_DIR/logs"

touch "$LOG_FILE"

clear

banner

log_info "====================================================="
log_info " Foreman / Katello Bootstrap Installer"
log_info "====================================================="

###############################################################################
# Root Check
###############################################################################

if [[ $EUID -ne 0 ]]; then
    log_error "Please run this script as root."
    exit 1
fi

###############################################################################
# Prerequisite Check
###############################################################################

log_step "Checking prerequisites"

check_command hammer
check_command curl
check_command awk
check_command sed
check_command grep

###############################################################################
# Connectivity
###############################################################################

log_step "Checking Foreman API"

check_foreman

###############################################################################
# Repository Server
###############################################################################

log_step "Checking Repository Server"

check_repo_server

###############################################################################
# Smart Proxies
###############################################################################

log_step "Checking Smart Proxies"

check_smart_proxies

###############################################################################
# Show Configuration
###############################################################################

echo
echo "=================================================="
echo "Configuration"
echo "=================================================="

echo "Foreman URL       : $FOREMAN_URL"
echo "Organization      : $ORG"
echo "Repository Server : $REPO_SERVER"
echo "Repository URL    : $REPO_URL"
echo "HTTP Server       : $HTTP_SERVER"

echo

###############################################################################
# Confirmation
###############################################################################

read -rp "Continue with bootstrap? (yes/no): " answer

case "$answer" in
yes|YES|y|Y)
    ;;
*)
    log_warn "Cancelled by user."
    exit 0
    ;;
esac

###############################################################################
# Script List
###############################################################################

SCRIPTS=(
scripts/01-media-os.sh
scripts/02-pxe-templates.sh
scripts/03-subnets.sh
scripts/04-hostgroups.sh
scripts/05-products.sh
scripts/06-repositories.sh
scripts/07-sync.sh
scripts/08-contentviews.sh
scripts/09-activationkeys.sh
scripts/10-subscriptions.sh
scripts/11-verify.sh
)

TOTAL=${#SCRIPTS[@]}
COUNT=1

###############################################################################
# Execute Modules
###############################################################################

for SCRIPT in "${SCRIPTS[@]}"
do

    FILE="$BASE_DIR/$SCRIPT"

    log_step "[$COUNT/$TOTAL] Running $(basename "$SCRIPT")"

    if [[ ! -f "$FILE" ]]
    then
        log_error "Missing module: $SCRIPT"
        exit 1
    fi

    chmod +x "$FILE"

    if "$FILE"
    then
        log_success "$(basename "$SCRIPT") completed."
    else
        log_error "$(basename "$SCRIPT") failed."
        exit 1
    fi

    ((COUNT++))

done

###############################################################################
# Summary
###############################################################################

echo

log_success "Bootstrap Completed Successfully"

echo

echo "======================================================="
echo "                INSTALLATION SUMMARY"
echo "======================================================="

echo "Installation Media      : OK"
echo "Operating Systems       : OK"
echo "PXE Templates           : OK"
echo "Subnets                 : OK"
echo "Host Groups             : OK"
echo "Products                : OK"
echo "Repositories            : OK"
echo "Synchronization         : OK"
echo "Content Views           : OK"
echo "Activation Keys         : OK"
echo "Subscriptions           : OK"
echo "Verification            : OK"

echo

echo "Log File"

echo "    $LOG_FILE"

echo

log_info "Done."

exit 0
