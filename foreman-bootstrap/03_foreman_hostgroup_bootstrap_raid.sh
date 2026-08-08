#!/bin/bash

###############################################################################
# 03 - Foreman Hostgroup Bootstrap (RAID)
#
# Creates Hostgroups:
#
#   CentOSLinux 7 RAID
#   RockyLinux 8.10 RAID
#   RockyLinux 9.2 RAID
#   RockyLinux 9.8 RAID
#
# Design:
#
#   RAID and SingleDisk use separate Operating System objects.
#
#   RAID OS:
#       CentOSLinux 7 RAID
#       RockyLinux 8.10 RAID
#       RockyLinux 9.2 RAID
#       RockyLinux 9.8 RAID
#
#   SingleDisk OS:
#       Created by script 04
#
###############################################################################

set +e


###############################################################################
# Foreman Credentials
###############################################################################

FOREMAN_USER="${FOREMAN_USER:-admin}"

FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"


HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"



###############################################################################
# Global Configuration
###############################################################################

DOMAIN="vgs.com"

LOCATION="Default Location"

ORGANIZATION="Default Organization"


CENTOS_SUBNET="vgs-subnet-centos"

ROCKY_SUBNET="vgs-subnet-rockyos"


TARGET_VERSION="${TARGET_VERSION:-ALL}"


FAILED_STEPS=()



record_failure()
{
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

info()
{
    echo -e "${CYAN}$1${NC}"
}


ok()
{
    echo -e "${GREEN}[OK]${NC} $1"
}


skip()
{
    echo -e "${YELLOW}[SKIP]${NC} $1"
}


warn()
{
    echo -e "${YELLOW}[WARN]${NC} $1"
}


error()
{
    echo -e "${RED}[ERROR]${NC} $1"
}


header()
{
    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}



header "03 - Foreman RAID Hostgroup Bootstrap"



###############################################################################
# RAID Template Mapping
###############################################################################

CENTOS_RAID_TEMPLATE="PXEGrub2 CentOS UEFI RAID Kickstart"

ROCKY8_RAID_TEMPLATE="PXEGrub2 Rocky8 UEFI RAID Kickstart"

ROCKY92_RAID_TEMPLATE="PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

ROCKY98_RAID_TEMPLATE="PXEGrub2 Rocky9.8 UEFI RAID Kickstart"



###############################################################################
# RAID Operating System Mapping
###############################################################################

CENTOS_RAID_OS="CentOSLinux 7 RAID"

ROCKY8_RAID_OS="RockyLinux 8.10 RAID"

ROCKY92_RAID_OS="RockyLinux 9.2 RAID"

ROCKY98_RAID_OS="RockyLinux 9.8 RAID"



###############################################################################
# Installation Media Mapping
###############################################################################

CENTOS_MEDIA="CentOS 7 Remote"

ROCKY8_MEDIA="Rocky 8 Remote"

ROCKY92_MEDIA="Rocky 9.2 Remote"

ROCKY98_MEDIA="Rocky 9 Remote"



###############################################################################
# Select Rocky Version
###############################################################################

case "${TARGET_VERSION}" in


9.2)

    ROCKY_HOSTGROUPS=(
        "RockyLinux 9.2 RAID"
    )

    ROCKY_OS_LIST=(
        "${ROCKY92_RAID_OS}"
    )

    ROCKY_MEDIA_LIST=(
        "${ROCKY92_MEDIA}"
    )

;;



9.8)

    ROCKY_HOSTGROUPS=(
        "RockyLinux 9.8 RAID"
    )

    ROCKY_OS_LIST=(
        "${ROCKY98_RAID_OS}"
    )

    ROCKY_MEDIA_LIST=(
        "${ROCKY98_MEDIA}"
    )

;;



ALL)

    ROCKY_HOSTGROUPS=(

        "RockyLinux 9.2 RAID"

        "RockyLinux 9.8 RAID"

    )


    ROCKY_OS_LIST=(

        "${ROCKY92_RAID_OS}"

        "${ROCKY98_RAID_OS}"

    )


    ROCKY_MEDIA_LIST=(

        "${ROCKY92_MEDIA}"

        "${ROCKY98_MEDIA}"

    )

;;



*)

    error "Unsupported TARGET_VERSION=${TARGET_VERSION}"

    exit 1

;;

esac



###############################################################################
# Create CentOS Linux 7 RAID Hostgroup
###############################################################################

create_centos_raid_hostgroup()
{

HOSTGROUP="CentOSLinux 7 RAID"


info "Checking Hostgroup : ${HOSTGROUP}"


if $HAMMER hostgroup info \
    --name "${HOSTGROUP}" >/dev/null 2>&1

then

    skip "${HOSTGROUP} already exists."

else


    info "Creating ${HOSTGROUP}..."


    $HAMMER hostgroup create \
        --name "${HOSTGROUP}" \
        --organization "${ORGANIZATION}" \
        --location "${LOCATION}" \
        --subnet "${CENTOS_SUBNET}" \
        --domain "${DOMAIN}" \
        --operatingsystem "${CENTOS_RAID_OS}" \
        --architecture x86_64 \
        --medium "${CENTOS_MEDIA}" \
        --partition-table "Kickstart default" \
        --root-password "password" \
        --pxe-loader "Grub2 UEFI"



    if [ $? -eq 0 ]

    then

        ok "${HOSTGROUP} created."

    else

        error "Failed creating ${HOSTGROUP}"

        record_failure "${HOSTGROUP}"

    fi


fi

echo

}



###############################################################################
# Create Rocky Linux 8.10 RAID Hostgroup
###############################################################################

create_rocky8_raid_hostgroup()
{

HOSTGROUP="RockyLinux 8.10 RAID"


info "Checking Hostgroup : ${HOSTGROUP}"


if $HAMMER hostgroup info \
    --name "${HOSTGROUP}" >/dev/null 2>&1

then

    skip "${HOSTGROUP} already exists."

else


    info "Creating ${HOSTGROUP}..."


    $HAMMER hostgroup create \
        --name "${HOSTGROUP}" \
        --organization "${ORGANIZATION}" \
        --location "${LOCATION}" \
        --subnet "${ROCKY_SUBNET}" \
        --domain "${DOMAIN}" \
        --operatingsystem "${ROCKY8_RAID_OS}" \
        --architecture x86_64 \
        --medium "${ROCKY8_MEDIA}" \
        --partition-table "Kickstart default" \
        --root-password "password" \
        --pxe-loader "Grub2 UEFI"



    if [ $? -eq 0 ]

    then

        ok "${HOSTGROUP} created."

    else

        error "Failed creating ${HOSTGROUP}"

        record_failure "${HOSTGROUP}"

    fi


fi

echo

}

###############################################################################
# Create Rocky Linux 9 RAID Hostgroups
###############################################################################

create_rocky9_raid_hostgroups()
{

for IDX in "${!ROCKY_HOSTGROUPS[@]}"
do


HOSTGROUP="${ROCKY_HOSTGROUPS[$IDX]}"

OS_NAME="${ROCKY_OS_LIST[$IDX]}"

MEDIA="${ROCKY_MEDIA_LIST[$IDX]}"



info "Checking Hostgroup : ${HOSTGROUP}"


if $HAMMER hostgroup info \
    --name "${HOSTGROUP}" >/dev/null 2>&1

then

    skip "${HOSTGROUP} already exists."

else


    info "Creating ${HOSTGROUP}..."



    $HAMMER hostgroup create \
        --name "${HOSTGROUP}" \
        --organization "${ORGANIZATION}" \
        --location "${LOCATION}" \
        --subnet "${ROCKY_SUBNET}" \
        --domain "${DOMAIN}" \
        --operatingsystem "${OS_NAME}" \
        --architecture x86_64 \
        --medium "${MEDIA}" \
        --partition-table "Kickstart default" \
        --root-password "password" \
        --pxe-loader "Grub2 UEFI"



    if [ $? -eq 0 ]

    then

        ok "${HOSTGROUP} created."

    else

        error "Failed creating ${HOSTGROUP}"

        record_failure "${HOSTGROUP}"

    fi


fi


echo


done


}



###############################################################################
# Assign RAID Provisioning Templates
###############################################################################

assign_template()
{

OS_NAME="$1"

TEMPLATE="$2"



info "Checking Template Assignment"

echo "OS       : ${OS_NAME}"

echo "Template : ${TEMPLATE}"



###############################################################################
# Verify Template Exists
###############################################################################

if ! $HAMMER template info \
    --name "${TEMPLATE}" >/dev/null 2>&1

then

    warn "Template not found : ${TEMPLATE}"

    record_failure "${TEMPLATE}"

    return 1

fi



###############################################################################
# Verify OS Exists
###############################################################################

if ! $HAMMER os info \
    --title "${OS_NAME}" >/dev/null 2>&1

then

    error "Operating System not found : ${OS_NAME}"

    record_failure "${OS_NAME}"

    return 1

fi



###############################################################################
# Check Existing Assignment
###############################################################################

if $HAMMER os info \
    --title "${OS_NAME}" |
    grep -q "${TEMPLATE}"

then

    skip "${TEMPLATE} already assigned to ${OS_NAME}"

else


    info "Assigning ${TEMPLATE} to ${OS_NAME}"



    $HAMMER os add-provisioning-template \
        --title "${OS_NAME}" \
        --provisioning-template "${TEMPLATE}"



    if [ $? -eq 0 ]

    then

        ok "${TEMPLATE} assigned."

    else

        error "Template assignment failed."

        record_failure "${OS_NAME} -> ${TEMPLATE}"

    fi


fi


echo


}



###############################################################################
# Configure RAID PXE Templates
###############################################################################

configure_raid_templates()
{

header "Assigning RAID PXE Templates"



###############################################################################
# CentOS 7 RAID
###############################################################################

assign_template \
"${CENTOS_RAID_OS}" \
"${CENTOS_RAID_TEMPLATE}"



###############################################################################
# Rocky Linux 8.10 RAID
###############################################################################

assign_template \
"${ROCKY8_RAID_OS}" \
"${ROCKY8_RAID_TEMPLATE}"



###############################################################################
# Rocky Linux 9 RAID
###############################################################################

for IDX in "${!ROCKY_OS_LIST[@]}"
do


OS_NAME="${ROCKY_OS_LIST[$IDX]}"



case "${OS_NAME}" in



"RockyLinux 9.2 RAID")


assign_template \
"${OS_NAME}" \
"${ROCKY92_RAID_TEMPLATE}"


;;



"RockyLinux 9.8 RAID")


assign_template \
"${OS_NAME}" \
"${ROCKY98_RAID_TEMPLATE}"


;;


esac


done


}



###############################################################################
# Create All RAID Hostgroups
###############################################################################

create_raid_hostgroups()
{

header "Creating RAID Hostgroups"



###############################################################################
# CentOS 7
###############################################################################

create_centos_raid_hostgroup



###############################################################################
# Rocky 8.10
###############################################################################

create_rocky8_raid_hostgroup



###############################################################################
# Rocky 9.x
###############################################################################

create_rocky9_raid_hostgroups


}



###############################################################################
# Verify Hostgroups
###############################################################################

verify_hostgroups()
{

header "RAID Hostgroup Verification"



HOSTGROUPS=(

"CentOSLinux 7 RAID"

"RockyLinux 8.10 RAID"

"RockyLinux 9.2 RAID"

"RockyLinux 9.8 RAID"

)



for HG in "${HOSTGROUPS[@]}"
do


echo

echo "------------------------------------------------------------"

echo "Hostgroup : ${HG}"

echo "------------------------------------------------------------"



$HAMMER hostgroup info \
    --name "${HG}" || true


done


}



###############################################################################
# Main Execution
###############################################################################

header "Starting RAID Hostgroup Creation"



create_raid_hostgroups



configure_raid_templates



verify_hostgroups

###############################################################################
# RAID Hostgroup Summary
###############################################################################

raid_summary()
{

header "RAID Hostgroup Summary"



echo

echo "============================================================"

echo "RAID Hostgroups"

echo "============================================================"



$HAMMER hostgroup list \
    --search "RAID" || true



echo

echo "============================================================"

echo "RAID Operating Systems"

echo "============================================================"



$HAMMER os list |
egrep "CentOSLinux 7 RAID|RockyLinux 8.10 RAID|RockyLinux 9.2 RAID|RockyLinux 9.8 RAID" \
|| true



echo

echo "============================================================"

echo "RAID PXE Templates"

echo "============================================================"



echo

echo "CentOS 7"

echo " -> ${CENTOS_RAID_TEMPLATE}"



echo

echo "Rocky Linux 8.10"

echo " -> ${ROCKY8_RAID_TEMPLATE}"



echo

echo "Rocky Linux 9.2"

echo " -> ${ROCKY92_RAID_TEMPLATE}"



echo

echo "Rocky Linux 9.8"

echo " -> ${ROCKY98_RAID_TEMPLATE}"



}



###############################################################################
# Detailed Hostgroup Verification
###############################################################################

verify_details()
{

header "Detailed RAID Hostgroup Verification"



HOSTGROUPS=(

"CentOSLinux 7 RAID"

"RockyLinux 8.10 RAID"

"RockyLinux 9.2 RAID"

"RockyLinux 9.8 RAID"

)



for HG in "${HOSTGROUPS[@]}"
do


echo

echo "############################################################"

echo "Hostgroup : ${HG}"

echo "############################################################"



if $HAMMER hostgroup info \
    --name "${HG}" >/dev/null 2>&1

then

    $HAMMER hostgroup info \
        --name "${HG}"

else

    warn "${HG} not found."

fi


done


}



###############################################################################
# Template Verification
###############################################################################

verify_templates()
{

header "RAID Template Verification"



echo

info "CentOS RAID Template"

$HAMMER template info \
    --name "${CENTOS_RAID_TEMPLATE}" || true



echo

info "Rocky 8 RAID Template"

$HAMMER template info \
    --name "${ROCKY8_RAID_TEMPLATE}" || true



echo

info "Rocky 9.2 RAID Template"

$HAMMER template info \
    --name "${ROCKY92_RAID_TEMPLATE}" || true



echo

info "Rocky 9.8 RAID Template"

$HAMMER template info \
    --name "${ROCKY98_RAID_TEMPLATE}" || true


}



###############################################################################
# Final Execution
###############################################################################

header "03 - Foreman RAID Hostgroup Bootstrap Completed"



raid_summary



verify_templates



echo


###############################################################################
# Failure Summary
###############################################################################

header "Execution Status"



if [ ${#FAILED_STEPS[@]} -eq 0 ]

then


    ok "RAID Hostgroup Bootstrap completed successfully."


else


    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."



    for ITEM in "${FAILED_STEPS[@]}"

    do

        error "${ITEM}"

    done


fi



###############################################################################
# Manual Verification Commands
###############################################################################

header "Manual Verification Commands"



echo

echo "CentOS RAID"

echo "------------------------------------------------------------"

echo 'hammer hostgroup info --name "CentOSLinux 7 RAID"'



echo

echo "Rocky 8 RAID"

echo "------------------------------------------------------------"

echo 'hammer hostgroup info --name "RockyLinux 8.10 RAID"'



echo

echo "Rocky 9.2 RAID"

echo "------------------------------------------------------------"

echo 'hammer hostgroup info --name "RockyLinux 9.2 RAID"'



echo

echo "Rocky 9.8 RAID"

echo "------------------------------------------------------------"

echo 'hammer hostgroup info --name "RockyLinux 9.8 RAID"'



echo


###############################################################################
# Expected Configuration
###############################################################################

header "Expected RAID Configuration"



cat <<EOF

Operating Systems:

CentOSLinux 7 RAID
    |
    +-- PXEGrub2 CentOS UEFI RAID Kickstart


RockyLinux 8.10 RAID
    |
    +-- PXEGrub2 Rocky8 UEFI RAID Kickstart


RockyLinux 9.2 RAID
    |
    +-- PXEGrub2 Rocky9.2 UEFI RAID Kickstart


RockyLinux 9.8 RAID
    |
    +-- PXEGrub2 Rocky9.8 UEFI RAID Kickstart



Hostgroups:

CentOSLinux 7 RAID
RockyLinux 8.10 RAID
RockyLinux 9.2 RAID
RockyLinux 9.8 RAID


Disk Layout:

Disk 1 + Disk 2

EFI
 |
 +-- /boot RAID1
 |
 +-- LVM RAID1
        |
        +-- /
        +-- swap
        +-- /home


EOF



###############################################################################
# Exit
###############################################################################

if [ ${#FAILED_STEPS[@]} -eq 0 ]

then

    exit 0

else

    exit 1

fi
