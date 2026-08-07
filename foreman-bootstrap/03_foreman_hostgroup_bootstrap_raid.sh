#!/bin/bash
###############################################################################
# 03 - Foreman Hostgroup Bootstrap - RAID
#
# Creates Hostgroups:
#
#   CentOS7-RAID
#   Rocky8-RAID
#   Rocky9.2-RAID
#   Rocky9.8-RAID
#
# RAID vs SingleDisk is controlled by Hostgroup.
# Operating Systems remain standard Foreman OS objects.
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


###############################################################################
# Variables
###############################################################################

FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"

HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"


ORGANIZATION="Default Organization"
LOCATION="Default Location"



###############################################################################
# Function : Check Hostgroup
###############################################################################

check_hostgroup()
{

HG="$1"


if $HAMMER hostgroup info \
    --name "${HG}" >/dev/null 2>&1; then

    skip "Hostgroup ${HG} already exists."

else

    info "Creating Hostgroup ${HG}..."

    $HAMMER hostgroup create \
        --name "${HG}" \
        --organization "${ORGANIZATION}" \
        --location "${LOCATION}"


    if [ $? -eq 0 ]; then

        ok "Hostgroup ${HG} created."

    else

        error "Failed creating ${HG}."

        record_failure "${HG}"

    fi

fi


echo

}



###############################################################################
# Create RAID Hostgroups
###############################################################################

header "Creating RAID Hostgroups"


check_hostgroup "CentOS7-RAID"

check_hostgroup "Rocky8-RAID"

check_hostgroup "Rocky9.2-RAID"

check_hostgroup "Rocky9.8-RAID"


###############################################################################
# Verification
###############################################################################

header "Hostgroups"

$HAMMER hostgroup list

echo

###############################################################################
# Hostgroup Configuration Function
###############################################################################

configure_hostgroup()
{

HG="$1"
OS="$2"
MEDIA="$3"
PXE_TEMPLATE="$4"
PARTITION="$5"


###############################################################################
# Verify Hostgroup
###############################################################################

info "Configuring Hostgroup : ${HG}"


###############################################################################
# Operating System
###############################################################################

info "Setting Operating System : ${OS}"


$HAMMER hostgroup set-parameter \
    --hostgroup "${HG}" \
    --name "os_name" \
    --value "${OS}" 2>/dev/null || true



###############################################################################
# Installation Media
###############################################################################

info "Setting Installation Media : ${MEDIA}"


$HAMMER hostgroup update \
    --name "${HG}" \
    --medium "${MEDIA}" 2>/dev/null


if [ $? -eq 0 ]; then

    ok "Installation media assigned."

else

    warn "Unable to assign installation media."

fi



###############################################################################
# Partition Table
###############################################################################

info "Setting Partition Table : ${PARTITION}"


$HAMMER hostgroup update \
    --name "${HG}" \
    --partition-table "${PARTITION}" 2>/dev/null


if [ $? -eq 0 ]; then

    ok "Partition table assigned."

else

    warn "Partition table assignment failed."

fi



###############################################################################
# PXE Template
###############################################################################

info "Setting PXE Template : ${PXE_TEMPLATE}"


$HAMMER os add-provisioning-template \
    --title "${OS}" \
    --provisioning-template "${PXE_TEMPLATE}" \
    2>/dev/null || true



###############################################################################
# Hostgroup Parameters
###############################################################################

info "Adding RAID parameters"


$HAMMER hostgroup set-parameter \
    --hostgroup "${HG}" \
    --name "disk_layout" \
    --value "raid1" \
    2>/dev/null || true


$HAMMER hostgroup set-parameter \
    --hostgroup "${HG}" \
    --name "storage_type" \
    --value "RAID1" \
    2>/dev/null || true



ok "${HG} configured."

echo


}



###############################################################################
# RAID Partition Tables
###############################################################################

header "Configuring RAID Hostgroups"



###############################################################################
# CentOS 7 RAID
###############################################################################

configure_hostgroup \
"CentOS7-RAID" \
"CentOSLinux 7" \
"CentOS 7 Remote" \
"PXEGrub2 CentOS UEFI Static Kickstart" \
"CentOS7 RAID"



###############################################################################
# Rocky Linux 8 RAID
###############################################################################

configure_hostgroup \
"Rocky8-RAID" \
"RockyLinux 8.10" \
"Rocky 8 Remote" \
"PXEGrub2 RockyOS UEFI Static Kickstart" \
"Rocky8 RAID"



###############################################################################
# Rocky Linux 9.2 RAID
###############################################################################

configure_hostgroup \
"Rocky9.2-RAID" \
"RockyLinux 9.2" \
"Rocky 9.2 Remote" \
"PXEGrub2 Rocky9.2 UEFI Static Kickstart" \
"Rocky9.2 RAID"



###############################################################################
# Rocky Linux 9.8 RAID
###############################################################################

configure_hostgroup \
"Rocky9.8-RAID" \
"RockyLinux 9.8" \
"Rocky 9 Remote" \
"PXEGrub2 Rocky9.8 UEFI Static Kickstart" \
"Rocky9.8 RAID"


###############################################################################
# Verification
###############################################################################

header "RAID Hostgroup Verification"


###############################################################################
# Hostgroup List
###############################################################################

info "Current Hostgroups"


$HAMMER hostgroup list


echo


###############################################################################
# Detailed Verification
###############################################################################

verify_hostgroup()
{

HG="$1"


echo
info "Checking Hostgroup : ${HG}"


$HAMMER hostgroup info \
    --name "${HG}"


echo

}



###############################################################################
# Verify RAID Hostgroups
###############################################################################

verify_hostgroup "CentOS7-RAID"

verify_hostgroup "Rocky8-RAID"

verify_hostgroup "Rocky9.2-RAID"

verify_hostgroup "Rocky9.8-RAID"



###############################################################################
# PXE Template Verification
###############################################################################

header "RAID PXE Template Verification"


$HAMMER template list | grep -i "RAID" || true


echo



###############################################################################
# Operating System Template Verification
###############################################################################

header "Operating System PXE Mapping"


verify_os_template()
{

OS="$1"


echo

info "${OS}"


$HAMMER os info \
    --title "${OS}" |
    awk '/Default templates:/,/Architectures:/'


}



verify_os_template "CentOSLinux 7"

verify_os_template "RockyLinux 8.10"

verify_os_template "RockyLinux 9.2"

verify_os_template "RockyLinux 9.8"



###############################################################################
# Hostgroup Summary
###############################################################################

header "RAID Hostgroup Summary"


echo

printf "%-25s %-30s %-35s\n" \
"HOSTGROUP" \
"OPERATING SYSTEM" \
"PXE TEMPLATE"


echo "--------------------------------------------------------------------------------"



printf "%-25s %-30s %-35s\n" \
"CentOS7-RAID" \
"CentOSLinux 7" \
"PXEGrub2 CentOS UEFI Static Kickstart"



printf "%-25s %-30s %-35s\n" \
"Rocky8-RAID" \
"RockyLinux 8.10" \
"PXEGrub2 RockyOS UEFI Static Kickstart"



printf "%-25s %-30s %-35s\n" \
"Rocky9.2-RAID" \
"RockyLinux 9.2" \
"PXEGrub2 Rocky9.2 UEFI Static Kickstart"



printf "%-25s %-30s %-35s\n" \
"Rocky9.8-RAID" \
"RockyLinux 9.8" \
"PXEGrub2 Rocky9.8 UEFI Static Kickstart"



echo



###############################################################################
# Final Summary
###############################################################################

header "03 - RAID Hostgroup Bootstrap Completed"


if [ ${#FAILED_STEPS[@]} -eq 0 ]; then

    ok "RAID Hostgroup Bootstrap completed successfully."

else

    warn "Completed with ${#FAILED_STEPS[@]} failure(s)."


    for step in "${FAILED_STEPS[@]}";
    do
        error "$step"
    done

fi



echo


###############################################################################
# Script Completed
###############################################################################

ok "03_foreman_hostgroup_bootstrap_raid.sh finished."


exit 0
