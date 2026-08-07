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
#   - RAID1 partition layout
#   - PXEGrub2 UEFI Static Kickstart
#   - Installation Media mapping
#   - Operating System mapping
#   - Subnet mapping
#   - Root password
#   - Kickstart repository configuration
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
# Configuration
###############################################################################

DOMAIN="vgs.com"

LOCATION="Default Location"
ORGANIZATION="Default Organization"
CENTOS_SUBNET="vgs-subnet-centos"
ROCKY_SUBNET="vgs-subnet-rockyos"

TARGET_VERSION="${TARGET_VERSION:-9.8}"


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


###############################################################################
# Select Rocky Version
###############################################################################

case "$TARGET_VERSION" in

9.2)

    ROCKY_OS="RockyLinux 9.2 RAID"

    ROCKY_BASE_OS="RockyLinux 9.2"

    ROCKY_MEDIA="Rocky 9.2 Remote"

    ROCKY_TEMPLATE="PXEGrub2 Rocky9.2 UEFI Static Kickstart"

    ROCKY_REPO="http://192.168.253.136/repo/rocky9.2/"

    ROCKY_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/rocky9.cfg"

    ;;


9.8)

    ROCKY_OS="RockyLinux 9.8 RAID"

    ROCKY_BASE_OS="RockyLinux 9.8"

    ROCKY_MEDIA="Rocky 9 Remote"

    ROCKY_TEMPLATE="PXEGrub2 Rocky9.8 UEFI Static Kickstart"

    ROCKY_REPO="http://192.168.253.136/repo/rocky9/"

    ROCKY_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/rocky9.cfg"

    ;;


*)

    echo "Unsupported TARGET_VERSION"
    exit 1

    ;;

esac

###############################################################################
# CentOS 7 RAID Configuration
###############################################################################

create_centos_hostgroup()
{

HOSTGROUP="CentOSLinux 7 RAID"

echo
echo "Checking Hostgroup : ${HOSTGROUP}"


if $HAMMER hostgroup list --search "name=\"${HOSTGROUP}\"" | grep -q "${HOSTGROUP}"
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
# Rocky Linux 8 RAID Configuration
###############################################################################

create_rocky8_hostgroup()
{

HOSTGROUP="RockyLinux 8.10 RAID"


echo
echo "Checking Hostgroup : ${HOSTGROUP}"


if $HAMMER hostgroup list --search "name=\"${HOSTGROUP}\"" | grep -q "${HOSTGROUP}"
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
# Rocky Linux 9 RAID Configuration
###############################################################################

create_rocky9_hostgroup()
{

HOSTGROUP="${ROCKY_OS}"


echo
echo "Checking Hostgroup : ${HOSTGROUP}"


if $HAMMER hostgroup list --search "name=\"${HOSTGROUP}\"" | grep -q "${HOSTGROUP}"
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
    --operatingsystem "${ROCKY_BASE_OS}" \
    --architecture x86_64 \
    --medium "${ROCKY_MEDIA}" \
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
# Assign PXE Templates
###############################################################################

assign_template()
{

OS_NAME="$1"
TEMPLATE="$2"


echo
echo "Checking PXE Template:"
echo "${OS_NAME} -> ${TEMPLATE}"


EXISTING=$(
$HAMMER os info \
--title "${OS_NAME}" 2>/dev/null |
grep "${TEMPLATE}"
)


if echo "${EXISTING}" | grep -q "${TEMPLATE}"
then

    skip "Template already assigned."

else


    echo "Assigning template..."


    $HAMMER os add-provisioning-template \
    --title "${OS_NAME}" \
    --provisioning-template "${TEMPLATE}"


    if [ $? -eq 0 ]
    then

        ok "Template assigned."

    else

        error "Failed assigning ${TEMPLATE}"
        record_failure "${OS_NAME} -> ${TEMPLATE}"

    fi


fi

}



###############################################################################
# Create RAID Hostgroups
###############################################################################

header "03 - Creating RAID Hostgroups"


create_centos_hostgroup


create_rocky8_hostgroup


create_rocky9_hostgroup

###############################################################################
# Configure Hostgroup PXE Defaults
###############################################################################

configure_pxe_defaults()
{

echo
header "Setting RAID PXE Templates"


echo "Checking CentOSLinux 7 RAID..."

assign_template \
"CentOSLinux 7" \
"PXEGrub2 CentOS UEFI Static Kickstart"


echo
echo "Checking RockyLinux 8.10 RAID..."

assign_template \
"RockyLinux 8.10" \
"PXEGrub2 RockyOS UEFI Static Kickstart"



echo
echo "Checking ${ROCKY_BASE_OS} RAID..."

assign_template \
"${ROCKY_BASE_OS}" \
"${ROCKY_TEMPLATE}"


}



###############################################################################
# Display Hostgroup Summary
###############################################################################

summary()
{

header "RAID Hostgroup Summary"


echo
echo "Hostgroups"
echo "------------------------------------------------------------"


$HAMMER hostgroup list


echo
echo "Operating Systems"
echo "------------------------------------------------------------"


$HAMMER os list



echo
echo "PXE Templates"
echo "------------------------------------------------------------"


$HAMMER template list \
--search "PXEGrub2"



echo
echo "Selected RAID Configuration"
echo "------------------------------------------------------------"


echo "TARGET_VERSION       : ${TARGET_VERSION}"
echo "Operating System     : ${ROCKY_OS}"
echo "PXE Template         : ${ROCKY_TEMPLATE}"
echo "Installation Media   : ${ROCKY_MEDIA}"
echo "Repository           : ${ROCKY_REPO}"
echo "Kickstart            : ${ROCKY_KS}"

}



###############################################################################
# Main
###############################################################################

configure_pxe_defaults


summary



header "03 - Foreman RAID Hostgroup Bootstrap Completed"



if [ ${#FAILED_STEPS[@]} -eq 0 ]
then

    echo "[OK] RAID Hostgroup Bootstrap completed successfully."

else

    echo "[WARN] Completed with ${#FAILED_STEPS[@]} failure(s)."

    for ITEM in "${FAILED_STEPS[@]}"
    do
        echo "[ERROR] ${ITEM}"
    done

fi
