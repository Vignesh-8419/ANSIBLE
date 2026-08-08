#!/bin/bash

###############################################################################
# 03 - Foreman Hostgroup Bootstrap (Single Disk)
#
# Creates Hostgroups:
#
#   CentOSLinux 7 SingleDisk
#   RockyLinux 8.10 SingleDisk
#   RockyLinux 9.2 SingleDisk
#   RockyLinux 9.8 SingleDisk
#
# Features:
#
#   - Single Disk Installation
#   - PXEGrub2 UEFI Static Kickstart
#   - Installation Media mapping
#   - Operating System mapping
#   - Subnet mapping
#   - Domain mapping
#   - Hostgroup PXE Template mapping
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
# Logging Functions
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



###############################################################################
# Select Rocky Version
###############################################################################

case "$TARGET_VERSION" in

9.2)

    ROCKY_HOSTGROUPS=("RockyLinux 9.2 SingleDisk")
    ROCKY_OS_LIST=("RockyLinux 9.2")
    ROCKY_MEDIA_LIST=("Rocky 9.2 Remote")

;;

9.8)

    ROCKY_HOSTGROUPS=("RockyLinux 9.8 SingleDisk")
    ROCKY_OS_LIST=("RockyLinux 9.8")
    ROCKY_MEDIA_LIST=("Rocky 9 Remote")

;;

ALL)

    ROCKY_HOSTGROUPS=(
        "RockyLinux 9.2 SingleDisk"
        "RockyLinux 9.8 SingleDisk"
    )

    ROCKY_OS_LIST=(
        "RockyLinux 9.2"
        "RockyLinux 9.8"
    )

    ROCKY_MEDIA_LIST=(
        "Rocky 9.2 Remote"
        "Rocky 9 Remote"
    )

;;

*)

    echo "Unsupported TARGET_VERSION: ${TARGET_VERSION}"
    exit 1

;;

esac

###############################################################################
# Create CentOS Linux 7 SingleDisk Hostgroup
###############################################################################

create_centos_single_hostgroup()
{

HOSTGROUP="CentOSLinux 7 SingleDisk"


echo
echo "Checking Hostgroup : ${HOSTGROUP}"


if $HAMMER hostgroup list \
--search "name=\"${HOSTGROUP}\"" | grep -q "${HOSTGROUP}"
then

    skip "${HOSTGROUP} already exists."

else

    echo "Creating ${HOSTGROUP}..."


    $HAMMER hostgroup create \
    --name "${HOSTGROUP}" \
    --organization "${ORGANIZATION}" \
    --location "${LOCATION}" \
    --subnet "${CENTOS_SUBNET}" \
    --domain "${DOMAIN}" \
    --operatingsystem "CentOSLinux 7" \
    --architecture x86_64 \
    --medium "CentOS 7 Remote" \
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

}

###############################################################################
# Create Rocky Linux 8.10 SingleDisk Hostgroup
###############################################################################

create_rocky8_single_hostgroup()
{

HOSTGROUP="RockyLinux 8.10 SingleDisk"


echo
echo "Checking Hostgroup : ${HOSTGROUP}"


if $HAMMER hostgroup list \
--search "name=\"${HOSTGROUP}\"" | grep -q "${HOSTGROUP}"
then

    skip "${HOSTGROUP} already exists."

else

    echo "Creating ${HOSTGROUP}..."


    $HAMMER hostgroup create \
    --name "${HOSTGROUP}" \
    --organization "${ORGANIZATION}" \
    --location "${LOCATION}" \
    --subnet "${ROCKY_SUBNET}" \
    --domain "${DOMAIN}" \
    --operatingsystem "RockyLinux 8.10" \
    --architecture x86_64 \
    --medium "Rocky 8 Remote" \
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

}

###############################################################################
# Create Rocky Linux 9 SingleDisk Hostgroup
###############################################################################

create_rocky9_single_hostgroup()
{

for IDX in "${!ROCKY_HOSTGROUPS[@]}"
do

HOSTGROUP="${ROCKY_HOSTGROUPS[$IDX]}"
OS_NAME="${ROCKY_OS_LIST[$IDX]}"
MEDIA="${ROCKY_MEDIA_LIST[$IDX]}"


echo
echo "Checking Hostgroup : ${HOSTGROUP}"


if $HAMMER hostgroup list \
--search "name=\"${HOSTGROUP}\"" | grep -q "${HOSTGROUP}"
then

    skip "${HOSTGROUP} already exists."

else

    echo "Creating ${HOSTGROUP}..."


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

done

}

###############################################################################
# Assign OS Provisioning Template
###############################################################################

assign_template()
{

OS_NAME="$1"
TEMPLATE="$2"


echo
echo "Checking OS Template:"
echo "OS       : ${OS_NAME}"
echo "Template : ${TEMPLATE}"


EXISTING=$(
$HAMMER os info \
--title "${OS_NAME}" 2>/dev/null |
grep "${TEMPLATE}"
)


if echo "${EXISTING}" | grep -q "${TEMPLATE}"
then

    skip "${TEMPLATE} already assigned to ${OS_NAME}"

else

    echo "Assigning OS template..."


    $HAMMER os add-provisioning-template \
    --title "${OS_NAME}" \
    --provisioning-template "${TEMPLATE}"


    if [ $? -eq 0 ]
    then

        ok "OS template assigned."

    else

        error "Failed assigning OS template."

        record_failure "${OS_NAME} -> ${TEMPLATE}"

    fi

fi

}



###############################################################################
# Assign PXE Template Through Hostgroup Operating System
###############################################################################

assign_os_template_from_hostgroup()
{

HOSTGROUP="$1"
TEMPLATE="$2"


echo
echo "Assigning PXE Template"
echo "Hostgroup : ${HOSTGROUP}"
echo "Template  : ${TEMPLATE}"


###############################################################################
# Get Operating System from Hostgroup
###############################################################################

HG_OS=$(
$HAMMER hostgroup info \
--name "${HOSTGROUP}" |
awk -F':' '/Operating System:/ {
    gsub(/^ +| +$/, "", $2)
    print $2
}'
)


if [ -z "${HG_OS}" ]
then

    error "Operating System not found for ${HOSTGROUP}"

    record_failure "${HOSTGROUP}"

    return 1

fi


echo "Operating System : ${HG_OS}"



###############################################################################
# Check Existing OS Template
###############################################################################

EXISTING=$(
$HAMMER os info \
--title "${HG_OS}" 2>/dev/null |
grep -F "${TEMPLATE}"
)



if [ -n "${EXISTING}" ]
then

    skip "${TEMPLATE} already assigned to ${HG_OS}"

else

    echo "Adding template to OS ${HG_OS}"


    $HAMMER os add-provisioning-template \
    --title "${HG_OS}" \
    --provisioning-template "${TEMPLATE}"


    if [ $? -eq 0 ]
    then

        ok "${TEMPLATE} assigned to ${HG_OS}"

    else

        error "Failed assigning ${TEMPLATE} to ${HG_OS}"

        record_failure "${HG_OS} -> ${TEMPLATE}"

    fi

fi


}
###############################################################################
# Configure Single Disk PXE Templates
###############################################################################

configure_single_pxe_templates()
{

header "Assign Single Disk PXE Templates"



###############################################################################
# CentOS 7
###############################################################################

assign_template \
"CentOSLinux 7" \
"PXEGrub2 CentOS UEFI SingleDisk Kickstart"


assign_os_template_from_hostgroup \
"CentOSLinux 7 SingleDisk" \
"PXEGrub2 CentOS UEFI SingleDisk Kickstart"



###############################################################################
# Rocky 8.10
###############################################################################

assign_template \
"RockyLinux 8.10" \
"PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"


assign_os_template_from_hostgroup \
"RockyLinux 8.10 SingleDisk" \
"PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"



###############################################################################
# Rocky 9.2
###############################################################################

assign_template \
"RockyLinux 9.2" \
"PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"


assign_os_template_from_hostgroup \
"RockyLinux 9.2 SingleDisk" \
"PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"



###############################################################################
# Rocky 9.8
###############################################################################

assign_template \
"RockyLinux 9.8" \
"PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"


assign_os_template_from_hostgroup \
"RockyLinux 9.8 SingleDisk" \
"PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"



}

###############################################################################
# Create Single Disk Hostgroups
###############################################################################

create_single_hostgroups()
{

header "Creating Single Disk Hostgroups"



###############################################################################
# CentOS Linux 7 Single Disk
###############################################################################

create_centos_single_hostgroup



###############################################################################
# Rocky Linux 8.10 Single Disk
###############################################################################

create_rocky8_single_hostgroup



###############################################################################
# Rocky Linux 9 Single Disk
###############################################################################

create_rocky9_single_hostgroup



}

###############################################################################
# Verify Single Disk Hostgroups
###############################################################################

verify_single_hostgroups()
{

header "Single Disk Hostgroup Verification"



HOSTGROUPS=(

"CentOSLinux 7 SingleDisk"

"RockyLinux 8.10 SingleDisk"

"RockyLinux 9.2 SingleDisk"

"RockyLinux 9.8 SingleDisk"

)



for HG in "${HOSTGROUPS[@]}"
do


echo
echo "------------------------------------------------------------"

echo "Hostgroup : ${HG}"

echo "------------------------------------------------------------"



$HAMMER hostgroup info \
--name "${HG}"


done


}

###############################################################################
# Single Disk Hostgroup Summary
###############################################################################

summary()
{

header "Single Disk Hostgroup Summary"



echo
echo "============================================================"
echo "Hostgroups"
echo "============================================================"


$HAMMER hostgroup list \
--search "SingleDisk"



echo
echo "============================================================"
echo "Operating Systems"
echo "============================================================"


$HAMMER os list



echo
echo "============================================================"
echo "PXE Templates"
echo "============================================================"


$HAMMER template list \
--search "PXEGrub2"



echo
echo "============================================================"
echo "Single Disk Configuration"
echo "============================================================"



echo

echo "CentOS 7 Single Disk"
echo "--------------------"
echo "Hostgroup : CentOSLinux 7 SingleDisk"
echo "PXE       : PXEGrub2 CentOS UEFI SingleDisk Kickstart"



echo

echo "Rocky Linux 8.10 Single Disk"
echo "----------------------------"
echo "Hostgroup : RockyLinux 8.10 SingleDisk"
echo "PXE       : PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"



echo

echo "Rocky Linux 9.2 Single Disk"
echo "---------------------------"
echo "Hostgroup : RockyLinux 9.2 SingleDisk"
echo "PXE       : PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"



echo

echo "Rocky Linux 9.8 Single Disk"
echo "---------------------------"
echo "Hostgroup : RockyLinux 9.8 SingleDisk"
echo "PXE       : PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"



}

###############################################################################
# Main Execution
###############################################################################

header "03 - Foreman Single Disk Hostgroup Bootstrap Started"



###############################################################################
# Create Single Disk Hostgroups
###############################################################################

create_single_hostgroups



###############################################################################
# Assign PXE Templates
###############################################################################

configure_single_pxe_templates



###############################################################################
# Verify Hostgroups
###############################################################################

verify_single_hostgroups



###############################################################################
# Summary
###############################################################################

summary



header "03 - Foreman Single Disk Hostgroup Bootstrap Completed"



###############################################################################
# Final Status
###############################################################################

if [ ${#FAILED_STEPS[@]} -eq 0 ]
then

    echo
    ok "Single Disk Hostgroup Bootstrap completed successfully."

else

    echo
    warn "Completed with ${#FAILED_STEPS[@]} failure(s)."


    for ITEM in "${FAILED_STEPS[@]}"
    do

        error "${ITEM}"

    done

fi

###############################################################################
# Script Completed
###############################################################################

echo

header "03 - Single Disk Hostgroup Bootstrap Finished"



###############################################################################
# Final Verification Commands
###############################################################################

echo

echo "Verify Hostgroups:"
echo "------------------------------------------------------------"


echo

echo "hammer hostgroup info --name \"CentOSLinux 7 SingleDisk\""


echo

echo "hammer hostgroup info --name \"RockyLinux 8.10 SingleDisk\""


echo

echo "hammer hostgroup info --name \"RockyLinux 9.2 SingleDisk\""


echo

echo "hammer hostgroup info --name \"RockyLinux 9.8 SingleDisk\""



echo

echo "Expected PXE Templates:"
echo "------------------------------------------------------------"


echo

echo "CentOSLinux 7 SingleDisk"
echo " -> PXEGrub2 CentOS UEFI SingleDisk Kickstart"


echo

echo "RockyLinux 8.10 SingleDisk"
echo " -> PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"


echo

echo "RockyLinux 9.2 SingleDisk"
echo " -> PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"


echo

echo "RockyLinux 9.8 SingleDisk"
echo " -> PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"



exit 0
