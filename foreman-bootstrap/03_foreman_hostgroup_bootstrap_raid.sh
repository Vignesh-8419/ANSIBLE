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
# Features:
#
#   - RAID1 partition layout
#   - PXEGrub2 UEFI RAID Kickstart
#   - Installation Media mapping
#   - Operating System mapping
#   - Subnet mapping
#   - Domain mapping
#   - OS Template mapping
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
# RAID Template Mapping
###############################################################################

CENTOS_RAID_TEMPLATE="PXEGrub2 CentOS UEFI RAID Kickstart"

ROCKY8_RAID_TEMPLATE="PXEGrub2 Rocky8 UEFI RAID Kickstart"

ROCKY92_RAID_TEMPLATE="PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

ROCKY98_RAID_TEMPLATE="PXEGrub2 Rocky9.8 UEFI RAID Kickstart"



###############################################################################
# Select Rocky Version
###############################################################################

case "${TARGET_VERSION}" in


9.2)

    ROCKY_HOSTGROUPS=(
        "RockyLinux 9.2 RAID"
    )

    ROCKY_OS_LIST=(
        "RockyLinux 9.2"
    )

    ROCKY_MEDIA_LIST=(
        "Rocky 9.2 Remote"
    )

;;

9.8)

    ROCKY_HOSTGROUPS=(
        "RockyLinux 9.8 RAID"
    )

    ROCKY_OS_LIST=(
        "RockyLinux 9.8"
    )

    ROCKY_MEDIA_LIST=(
        "Rocky 9 Remote"
    )

;;

ALL)

    ROCKY_HOSTGROUPS=(
        "RockyLinux 9.2 RAID"
        "RockyLinux 9.8 RAID"
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

    echo "Unsupported TARGET_VERSION=${TARGET_VERSION}"
    exit 1

;;

esac

###############################################################################
# Create CentOS Linux 7 RAID Hostgroup
###############################################################################

create_centos_raid_hostgroup()
{

HOSTGROUP="CentOSLinux 7 RAID"


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
# Create Rocky Linux 8.10 RAID Hostgroup
###############################################################################

create_rocky8_raid_hostgroup()
{

HOSTGROUP="RockyLinux 8.10 RAID"


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
# Create Rocky Linux 9 RAID Hostgroups
###############################################################################

create_rocky9_raid_hostgroups()
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



###############################################################################
# Check Existing Assignment
###############################################################################

EXISTING=$(
$HAMMER os info \
--title "${OS_NAME}" 2>/dev/null |
grep -F "${TEMPLATE}"
)



if [ -n "${EXISTING}" ]

then

    skip "${TEMPLATE} already assigned to ${OS_NAME}"

else


    echo "Assigning template to ${OS_NAME}..."



    $HAMMER os add-provisioning-template \
    --title "${OS_NAME}" \
    --provisioning-template "${TEMPLATE}"



    if [ $? -eq 0 ]

    then

        ok "${TEMPLATE} assigned to ${OS_NAME}"

    else

        error "Failed assigning ${TEMPLATE} to ${OS_NAME}"

        record_failure "${OS_NAME} -> ${TEMPLATE}"

    fi


fi


}



###############################################################################
# Configure RAID PXE Templates
###############################################################################

configure_raid_pxe_templates()
{

header "Assign RAID PXE Templates"



###############################################################################
# CentOS 7 RAID
###############################################################################

assign_template \
"CentOSLinux 7" \
"${CENTOS_RAID_TEMPLATE}"



###############################################################################
# Rocky Linux 8.10 RAID
###############################################################################

assign_template \
"RockyLinux 8.10" \
"${ROCKY8_RAID_TEMPLATE}"



###############################################################################
# Rocky Linux 9 RAID
###############################################################################

for IDX in "${!ROCKY_OS_LIST[@]}"
do


OS_NAME="${ROCKY_OS_LIST[$IDX]}"



case "${OS_NAME}" in


"RockyLinux 9.2")


assign_template \
"${OS_NAME}" \
"${ROCKY92_RAID_TEMPLATE}"


;;



"RockyLinux 9.8")


assign_template \
"${OS_NAME}" \
"${ROCKY98_RAID_TEMPLATE}"


;;


esac


done


}

###############################################################################
# Create RAID Hostgroups
###############################################################################

create_raid_hostgroups()
{

header "Creating RAID Hostgroups"



###############################################################################
# CentOS Linux 7 RAID
###############################################################################

create_centos_raid_hostgroup



###############################################################################
# Rocky Linux 8.10 RAID
###############################################################################

create_rocky8_raid_hostgroup



###############################################################################
# Rocky Linux 9 RAID
###############################################################################

create_rocky9_raid_hostgroups


}



###############################################################################
# Verify RAID Hostgroups
###############################################################################

verify_raid_hostgroups()
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
--name "${HG}"


done


}



###############################################################################
# RAID Summary
###############################################################################

summary()
{

header "RAID Hostgroup Summary"



echo

echo "============================================================"

echo "RAID Hostgroups"

echo "============================================================"



$HAMMER hostgroup list \
--search "RAID"



echo

echo "============================================================"

echo "Operating Systems"

echo "============================================================"



$HAMMER os list



echo

echo "============================================================"

echo "RAID PXE Templates"

echo "============================================================"



echo

echo "CentOS Linux 7"

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
# Main Execution
###############################################################################

header "03 - Foreman RAID Hostgroup Bootstrap Started"



###############################################################################
# Create RAID Hostgroups
###############################################################################

create_raid_hostgroups



###############################################################################
# Assign RAID PXE Templates
###############################################################################

configure_raid_pxe_templates



###############################################################################
# Verify Hostgroups
###############################################################################

verify_raid_hostgroups



###############################################################################
# Summary
###############################################################################

summary



header "03 - Foreman RAID Hostgroup Bootstrap Completed"



###############################################################################
# Final Status
###############################################################################

if [ ${#FAILED_STEPS[@]} -eq 0 ]

then

    echo

    ok "RAID Hostgroup Bootstrap completed successfully."

else


    echo

    warn "Completed with ${#FAILED_STEPS[@]} failure(s)."



    for ITEM in "${FAILED_STEPS[@]}"

    do

        error "${ITEM}"

    done


fi



###############################################################################
# Final Verification Commands
###############################################################################

echo

echo "Manual Verification Commands"

echo "------------------------------------------------------------"



echo

echo 'hammer hostgroup info --name "CentOSLinux 7 RAID"'


echo

echo 'hammer hostgroup info --name "RockyLinux 8.10 RAID"'


echo

echo 'hammer hostgroup info --name "RockyLinux 9.2 RAID"'


echo

echo 'hammer hostgroup info --name "RockyLinux 9.8 RAID"'



echo

echo "Expected RAID PXE Templates"

echo "------------------------------------------------------------"



echo

echo "CentOSLinux 7 RAID"

echo " -> PXEGrub2 CentOS UEFI RAID Kickstart"



echo

echo "RockyLinux 8.10 RAID"

echo " -> PXEGrub2 Rocky8 UEFI RAID Kickstart"



echo

echo "RockyLinux 9.2 RAID"

echo " -> PXEGrub2 Rocky9.2 UEFI RAID Kickstart"



echo

echo "RockyLinux 9.8 RAID"

echo " -> PXEGrub2 Rocky9.8 UEFI RAID Kickstart"



exit 0
