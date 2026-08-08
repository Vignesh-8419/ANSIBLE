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
#   - PXEGrub2 UEFI Kickstart
#   - Installation Media mapping
#   - SingleDisk Operating System mapping
#   - Subnet mapping
#   - Domain mapping
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
# Single Disk OS Definitions
###############################################################################

CENTOS_SINGLE_OS="CentOSLinux 7 SingleDisk"

ROCKY8_SINGLE_OS="RockyLinux 8.10 SingleDisk"

ROCKY92_SINGLE_OS="RockyLinux 9.2 SingleDisk"

ROCKY98_SINGLE_OS="RockyLinux 9.8 SingleDisk"



###############################################################################
# Medium Definitions
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

        "RockyLinux 9.2 SingleDisk"

    )


    ROCKY_OS_LIST=(

        "${ROCKY92_SINGLE_OS}"

    )


    ROCKY_MEDIA_LIST=(

        "${ROCKY92_MEDIA}"

    )

;;

9.8)

    ROCKY_HOSTGROUPS=(

        "RockyLinux 9.8 SingleDisk"

    )


    ROCKY_OS_LIST=(

        "${ROCKY98_SINGLE_OS}"

    )


    ROCKY_MEDIA_LIST=(

        "${ROCKY98_MEDIA}"

    )

;;

ALL)

    ROCKY_HOSTGROUPS=(

        "RockyLinux 9.2 SingleDisk"

        "RockyLinux 9.8 SingleDisk"

    )


    ROCKY_OS_LIST=(

        "${ROCKY92_SINGLE_OS}"

        "${ROCKY98_SINGLE_OS}"

    )


    ROCKY_MEDIA_LIST=(

        "${ROCKY92_MEDIA}"

        "${ROCKY98_MEDIA}"

    )

;;

*)

    error "Unsupported TARGET_VERSION ${TARGET_VERSION}"

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

    info "Creating ${HOSTGROUP}..."



    $HAMMER hostgroup create \
    --name "${HOSTGROUP}" \
    --organization "${ORGANIZATION}" \
    --location "${LOCATION}" \
    --subnet "${CENTOS_SUBNET}" \
    --domain "${DOMAIN}" \
    --operatingsystem "${CENTOS_SINGLE_OS}" \
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

    info "Creating ${HOSTGROUP}..."



    $HAMMER hostgroup create \
    --name "${HOSTGROUP}" \
    --organization "${ORGANIZATION}" \
    --location "${LOCATION}" \
    --subnet "${ROCKY_SUBNET}" \
    --domain "${DOMAIN}" \
    --operatingsystem "${ROCKY8_SINGLE_OS}" \
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

}



###############################################################################
# Create Rocky Linux 9 SingleDisk Hostgroups
###############################################################################

create_rocky9_single_hostgroups()
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


done

}



###############################################################################
# Create All SingleDisk Hostgroups
###############################################################################

create_single_hostgroups()
{

header "Creating Single Disk Hostgroups"



###############################################################################
# CentOS 7 SingleDisk
###############################################################################

create_centos_single_hostgroup



###############################################################################
# Rocky 8.10 SingleDisk
###############################################################################

create_rocky8_single_hostgroup



###############################################################################
# Rocky 9.x SingleDisk
###############################################################################

create_rocky9_single_hostgroups


}



###############################################################################
# Assign PXE Provisioning Template
###############################################################################

assign_template()
{

OS_NAME="$1"

TEMPLATE="$2"



echo

echo "Checking Template Assignment"

echo "Operating System : ${OS_NAME}"

echo "Template         : ${TEMPLATE}"



###############################################################################
# Check Template Exists
###############################################################################

TEMPLATE_EXISTS=$(
$HAMMER template list \
--search "name=\"${TEMPLATE}\"" 2>/dev/null |
grep -F "${TEMPLATE}"
)



if [ -z "${TEMPLATE_EXISTS}" ]

then

    warn "Template not found : ${TEMPLATE}"

    record_failure "${TEMPLATE}"

    return 1

fi



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

    info "Assigning template..."



    $HAMMER os add-provisioning-template \
    --title "${OS_NAME}" \
    --provisioning-template "${TEMPLATE}"



    if [ $? -eq 0 ]

    then

        ok "${TEMPLATE} assigned."

    else

        error "Failed assigning ${TEMPLATE}"

        record_failure "${OS_NAME} -> ${TEMPLATE}"

    fi

fi


}



###############################################################################
# Configure SingleDisk PXE Templates
###############################################################################

configure_single_pxe_templates()
{

header "Assign Single Disk PXE Templates"



###############################################################################
# CentOS Linux 7
###############################################################################

assign_template \
"${CENTOS_SINGLE_OS}" \
"PXEGrub2 CentOS UEFI SingleDisk Kickstart"



###############################################################################
# Rocky Linux 8.10
###############################################################################

assign_template \
"${ROCKY8_SINGLE_OS}" \
"PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"



###############################################################################
# Rocky Linux 9.2
###############################################################################

assign_template \
"${ROCKY92_SINGLE_OS}" \
"PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"



###############################################################################
# Rocky Linux 9.8
###############################################################################

assign_template \
"${ROCKY98_SINGLE_OS}" \
"PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"


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



if $HAMMER hostgroup info \
--name "${HG}" >/dev/null 2>&1

then

    ok "${HG} exists."

    $HAMMER hostgroup info \
    --name "${HG}"

else

    error "${HG} not found."

    record_failure "${HG}"

fi


done


}



###############################################################################
# Verify OS Template Mapping
###############################################################################

verify_template_mapping()
{

header "Operating System Template Verification"



OS_LIST=(

"CentOSLinux 7"

"RockyLinux 8.10"

"RockyLinux 9.2"

"RockyLinux 9.8"

)



for OS in "${OS_LIST[@]}"

do


echo

echo "------------------------------------------------------------"

echo "Operating System : ${OS}"

echo "------------------------------------------------------------"



$HAMMER os info \
--title "${OS}" |
awk '
/Templates:/,/Parameters:/
'


done


}



###############################################################################
# Single Disk Summary
###############################################################################

summary()
{

header "Single Disk Hostgroup Summary"



echo

echo "============================================================"

echo "Single Disk Hostgroups"

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

echo "Expected Configuration"

echo "============================================================"



echo

echo "CentOS Linux 7 SingleDisk"

echo "--------------------------------"

echo "Hostgroup : CentOSLinux 7 SingleDisk"

echo "OS        : CentOSLinux 7"

echo "Medium    : CentOS 7 Remote"

echo "PXE       : PXEGrub2 CentOS UEFI SingleDisk Kickstart"



echo

echo "Rocky Linux 8.10 SingleDisk"

echo "--------------------------------"

echo "Hostgroup : RockyLinux 8.10 SingleDisk"

echo "OS        : RockyLinux 8.10"

echo "Medium    : Rocky 8 Remote"

echo "PXE       : PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"



echo

echo "Rocky Linux 9.2 SingleDisk"

echo "--------------------------------"

echo "Hostgroup : RockyLinux 9.2 SingleDisk"

echo "OS        : RockyLinux 9.2"

echo "Medium    : Rocky 9.2 Remote"

echo "PXE       : PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"



echo

echo "Rocky Linux 9.8 SingleDisk"

echo "--------------------------------"

echo "Hostgroup : RockyLinux 9.8 SingleDisk"

echo "OS        : RockyLinux 9.8"

echo "Medium    : Rocky 9 Remote"

echo "PXE       : PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"


}



###############################################################################
# Main Execution
###############################################################################

header "03 - Foreman Single Disk Hostgroup Bootstrap Started"



###############################################################################
# Create Hostgroups
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
# Verify Template Mapping
###############################################################################

verify_template_mapping



###############################################################################
# Summary
###############################################################################

summary

###############################################################################
# Completion Header
###############################################################################

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
# Manual Verification Commands
###############################################################################

echo

echo "Manual Verification Commands"

echo "------------------------------------------------------------"



echo

echo 'hammer hostgroup info --name "CentOSLinux 7 SingleDisk"'



echo

echo 'hammer hostgroup info --name "RockyLinux 8.10 SingleDisk"'



echo

echo 'hammer hostgroup info --name "RockyLinux 9.2 SingleDisk"'



echo

echo 'hammer hostgroup info --name "RockyLinux 9.8 SingleDisk"'



echo

echo "Verify OS Template Mapping"

echo "------------------------------------------------------------"



echo

echo 'hammer os info --title "CentOSLinux 7"'



echo

echo 'hammer os info --title "RockyLinux 8.10"'



echo

echo 'hammer os info --title "RockyLinux 9.2"'



echo

echo 'hammer os info --title "RockyLinux 9.8"'



###############################################################################
# Expected Configuration
###############################################################################

echo

echo "Expected Single Disk PXE Templates"

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



###############################################################################
# Script End
###############################################################################

exit 0
