#!/bin/bash

###############################################################################
# 03 - Foreman Hostgroup Bootstrap (RAID)
#
# Creates RAID Hostgroups:
#
#   CentOSLinux7-RAID
#   RockyLinux8.10-RAID
#   RockyLinux9.2-RAID
#   RockyLinux9.8-RAID
#
# OS objects are created by:
#   01_foreman_pxe_bootstrap.sh
#
# Content is created by:
#   02_foreman_katello_bootstrap.sh
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
# RAID PXE Template Mapping
###############################################################################

CENTOS_RAID_TEMPLATE="PXEGrub2 CentOS UEFI RAID Kickstart"

ROCKY8_RAID_TEMPLATE="PXEGrub2 Rocky8 UEFI RAID Kickstart"

ROCKY92_RAID_TEMPLATE="PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

ROCKY98_RAID_TEMPLATE="PXEGrub2 Rocky9.8 UEFI RAID Kickstart"



###############################################################################
# RAID Operating System Mapping
#
# MUST match Script 01 exactly
###############################################################################

CENTOS_RAID_OS="CentOSLinux7-RAID"

ROCKY8_RAID_OS="RockyLinux8.10-RAID"

ROCKY92_RAID_OS="RockyLinux9.2-RAID"

ROCKY98_RAID_OS="RockyLinux9.8-RAID"



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
        "RockyLinux9.2-RAID"
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
        "RockyLinux9.8-RAID"
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

        "RockyLinux9.2-RAID"

        "RockyLinux9.8-RAID"

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
# Create CentOS 7 RAID Hostgroup
###############################################################################

create_centos_raid_hostgroup()
{

HOSTGROUP="CentOSLinux7-RAID"


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

HOSTGROUP="RockyLinux8.10-RAID"


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
# Create Rocky Linux 9.x RAID Hostgroups
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
# Create All RAID Hostgroups
###############################################################################

create_raid_hostgroups()
{

header "Creating RAID Hostgroups"



###############################################################################
# CentOS 7 RAID
###############################################################################

create_centos_raid_hostgroup



###############################################################################
# Rocky 8.10 RAID
###############################################################################

create_rocky8_raid_hostgroup



###############################################################################
# Rocky 9.x RAID
###############################################################################

create_rocky9_raid_hostgroups


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
# Verify Operating System Exists
###############################################################################

OS_ID=$(
$HAMMER os list |
awk -F'|' -v NAME="${OS_NAME}" '
{
    gsub(/^ +| +$/, "", $2)

    if ($2 == NAME)
    {
        gsub(/^ +| +$/, "", $1)
        print $1
    }
}'
)



if [ -z "${OS_ID}" ]

then

    error "Operating System not found : ${OS_NAME}"

    record_failure "${OS_NAME}"

    return 1

fi



###############################################################################
# Check Existing Template Assignment
###############################################################################

if $HAMMER os info \
    --id "${OS_ID}" |
    grep -q "${TEMPLATE}"

then

    skip "${TEMPLATE} already assigned to ${OS_NAME}"

else


    info "Assigning ${TEMPLATE} to ${OS_NAME}"



    $HAMMER os add-provisioning-template \
        --id "${OS_ID}" \
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


"RockyLinux9.2-RAID")

    assign_template \
    "${OS_NAME}" \
    "${ROCKY92_RAID_TEMPLATE}"

;;


"RockyLinux9.8-RAID")

    assign_template \
    "${OS_NAME}" \
    "${ROCKY98_RAID_TEMPLATE}"

;;


esac


done


}
