#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap
#
# Creates:
#
#   - Installation Media
#   - Operating System Objects
#       RAID
#       SingleDisk
#   - PXEGrub2 Templates
#   - Template Assignment
#   - PXE Subnets
#
###############################################################################

set +e


###############################################################################
# Failure Tracking
###############################################################################

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



header "01 - Foreman PXE Bootstrap"



###############################################################################
# Variables
###############################################################################

FOREMAN_USER="${FOREMAN_USER:-admin}"

FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"


HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"


TARGET_VERSION="${TARGET_VERSION:-9.8}"



###############################################################################
# Installation Media
###############################################################################

CENTOS_MEDIA="CentOS 7 Remote"

ROCKY8_MEDIA="Rocky 8 Remote"

ROCKY92_MEDIA="Rocky 9.2 Remote"

ROCKY98_MEDIA="Rocky 9 Remote"



###############################################################################
# Operating System Names
#
# IMPORTANT:
#
# Foreman TITLE only.
# Release is controlled separately using --major and --minor.
#
# Example:
#
# TITLE          : RockyLinux9.8-RAID
# RELEASE        : 9.8
#
###############################################################################

CENTOS_RAID="CentOSLinux7-RAID"

CENTOS_SINGLE="CentOSLinux7-SingleDisk"



ROCKY8_RAID="RockyLinux8.10-RAID"

ROCKY8_SINGLE="RockyLinux8.10-SingleDisk"



ROCKY92_RAID="RockyLinux9.2-RAID"

ROCKY92_SINGLE="RockyLinux9.2-SingleDisk"



ROCKY98_RAID="RockyLinux9.8-RAID"

ROCKY98_SINGLE="RockyLinux9.8-SingleDisk"



###############################################################################
# Create Installation Media
###############################################################################

create_media()
{

NAME="$1"

URL="$2"


info "Checking Installation Media : ${NAME}"


if $HAMMER medium info \
--name "${NAME}" >/dev/null 2>&1

then

    skip "${NAME} already exists."

else

    info "Creating ${NAME}"


    $HAMMER medium create \
    --name "${NAME}" \
    --path "${URL}" \
    --os-family Redhat


    if [ $? -eq 0 ]

    then

        ok "${NAME} created."

    else

        error "Failed creating ${NAME}"

        record_failure "${NAME}"

    fi

fi


echo

}



create_media \
"CentOS 7 Remote" \
"http://192.168.253.136/repo/centos/"


create_media \
"Rocky 8 Remote" \
"http://192.168.253.136/repo/rocky8/"


create_media \
"Rocky 9 Remote" \
"http://192.168.253.136/repo/rocky9/"


create_media \
"Rocky 9.2 Remote" \
"http://192.168.253.136/repo/rocky9.2/"


header "Installation Media Verification"


$HAMMER medium list

#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap
#
# Creates:
#
#   - Installation Media
#   - Operating System Objects
#       RAID
#       SingleDisk
#   - PXEGrub2 Templates
#   - Template Assignment
#   - PXE Subnets
#
###############################################################################

set +e


###############################################################################
# Failure Tracking
###############################################################################

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



header "01 - Foreman PXE Bootstrap"



###############################################################################
# Variables
###############################################################################

FOREMAN_USER="${FOREMAN_USER:-admin}"

FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"


HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"


TARGET_VERSION="${TARGET_VERSION:-9.8}"



###############################################################################
# Installation Media
###############################################################################

CENTOS_MEDIA="CentOS 7 Remote"

ROCKY8_MEDIA="Rocky 8 Remote"

ROCKY92_MEDIA="Rocky 9.2 Remote"

ROCKY98_MEDIA="Rocky 9 Remote"



###############################################################################
# Operating System Names
#
# IMPORTANT:
#
# Foreman TITLE only.
# Release is controlled separately using --major and --minor.
#
# Example:
#
# TITLE          : RockyLinux9.8-RAID
# RELEASE        : 9.8
#
###############################################################################

CENTOS_RAID="CentOSLinux7-RAID"

CENTOS_SINGLE="CentOSLinux7-SingleDisk"



ROCKY8_RAID="RockyLinux8.10-RAID"

ROCKY8_SINGLE="RockyLinux8.10-SingleDisk"



ROCKY92_RAID="RockyLinux9.2-RAID"

ROCKY92_SINGLE="RockyLinux9.2-SingleDisk"



ROCKY98_RAID="RockyLinux9.8-RAID"

ROCKY98_SINGLE="RockyLinux9.8-SingleDisk"



###############################################################################
# Create Installation Media
###############################################################################

create_media()
{

NAME="$1"

URL="$2"


info "Checking Installation Media : ${NAME}"


if $HAMMER medium info \
--name "${NAME}" >/dev/null 2>&1

then

    skip "${NAME} already exists."

else

    info "Creating ${NAME}"


    $HAMMER medium create \
    --name "${NAME}" \
    --path "${URL}" \
    --os-family Redhat


    if [ $? -eq 0 ]

    then

        ok "${NAME} created."

    else

        error "Failed creating ${NAME}"

        record_failure "${NAME}"

    fi

fi


echo

}



create_media \
"CentOS 7 Remote" \
"http://192.168.253.136/repo/centos/"


create_media \
"Rocky 8 Remote" \
"http://192.168.253.136/repo/rocky8/"


create_media \
"Rocky 9 Remote" \
"http://192.168.253.136/repo/rocky9/"


create_media \
"Rocky 9.2 Remote" \
"http://192.168.253.136/repo/rocky9.2/"


header "Installation Media Verification"


$HAMMER medium list

###############################################################################
# Create PXEGrub2 Templates
###############################################################################

header "[3/6] Creating PXEGrub2 Templates"



create_template()
{

TEMPLATE_NAME="$1"

TEMPLATE_FILE="$2"


info "Checking Template : ${TEMPLATE_NAME}"


if $HAMMER template info \
--name "${TEMPLATE_NAME}" >/dev/null 2>&1

then

    skip "${TEMPLATE_NAME} already exists."

else

    info "Importing ${TEMPLATE_NAME}"


    $HAMMER template create \
    --name "${TEMPLATE_NAME}" \
    --type PXEGrub2 \
    --file "${TEMPLATE_FILE}"


    if [ $? -eq 0 ]

    then

        ok "${TEMPLATE_NAME} imported."

    else

        error "Failed importing ${TEMPLATE_NAME}"

        record_failure "${TEMPLATE_NAME}"

    fi

fi


echo

}



###############################################################################
# Import PXE Templates
###############################################################################

create_template \
"PXEGrub2 CentOS UEFI RAID Kickstart" \
"/tmp/centos7-raid.erb"


create_template \
"PXEGrub2 CentOS UEFI SingleDisk Kickstart" \
"/tmp/centos7-singledisk.erb"



create_template \
"PXEGrub2 Rocky8 UEFI RAID Kickstart" \
"/tmp/rocky8-raid.erb"


create_template \
"PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" \
"/tmp/rocky8-singledisk.erb"



create_template \
"PXEGrub2 Rocky9.2 UEFI RAID Kickstart" \
"/tmp/rocky92-raid.erb"


create_template \
"PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart" \
"/tmp/rocky92-singledisk.erb"



create_template \
"PXEGrub2 Rocky9.8 UEFI RAID Kickstart" \
"/tmp/rocky98-raid.erb"


create_template \
"PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart" \
"/tmp/rocky98-singledisk.erb"




###############################################################################
# Assign Template To Operating System
###############################################################################

assign_template()
{

OS_NAME="$1"

TEMPLATE="$2"



info "Checking Template Assignment"

echo "OS       : ${OS_NAME}"

echo "Template : ${TEMPLATE}"



###############################################################################
# Get OS ID using exact TITLE
###############################################################################

OS_ID=$(
$HAMMER os list |
awk -F'|' -v name="${OS_NAME}" '

{
gsub(/^ +| +$/,"",$1)
gsub(/^ +| +$/,"",$2)

if ($2 == name)
{
print $1
}

}
'
)



if [ -z "${OS_ID}" ]

then

    error "Operating System not found : ${OS_NAME}"

    record_failure "${OS_NAME}"

    return 1

fi



ok "Found OS ID : ${OS_ID}"



###############################################################################
# Check Existing Assignment
###############################################################################

if $HAMMER os info \
--id "${OS_ID}" 2>/dev/null |
grep -q "${TEMPLATE}"

then

    skip "${TEMPLATE} already assigned."

    return 0

fi



###############################################################################
# Assign Template
###############################################################################

$HAMMER os add-provisioning-template \
--id "${OS_ID}" \
--provisioning-template "${TEMPLATE}"



if [ $? -eq 0 ]

then

    ok "${TEMPLATE} assigned."

else

    error "Failed assigning ${TEMPLATE}"

    record_failure "${OS_NAME}"

fi


echo

}

###############################################################################
# Template Mapping
###############################################################################

header "Assigning PXE Templates"



###############################################################################
# CentOS 7
###############################################################################

assign_template \
"${CENTOS_RAID}" \
"PXEGrub2 CentOS UEFI RAID Kickstart"


assign_template \
"${CENTOS_SINGLE}" \
"PXEGrub2 CentOS UEFI SingleDisk Kickstart"



###############################################################################
# Rocky Linux 8.10
###############################################################################

assign_template \
"${ROCKY8_RAID}" \
"PXEGrub2 Rocky8 UEFI RAID Kickstart"


assign_template \
"${ROCKY8_SINGLE}" \
"PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"



###############################################################################
# Rocky Linux 9.2
###############################################################################

assign_template \
"${ROCKY92_RAID}" \
"PXEGrub2 Rocky9.2 UEFI RAID Kickstart"


assign_template \
"${ROCKY92_SINGLE}" \
"PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"



###############################################################################
# Rocky Linux 9.8
###############################################################################

assign_template \
"${ROCKY98_RAID}" \
"PXEGrub2 Rocky9.8 UEFI RAID Kickstart"


assign_template \
"${ROCKY98_SINGLE}" \
"PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"



###############################################################################
# Verify Template Assignment
###############################################################################

header "OS Template Verification"


$HAMMER os list
