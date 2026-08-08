#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap
#
# Creates:
#
#   - Installation Media
#   - Operating Systems
#   - PXEGrub2 Templates
#   - Template Assignment
#   - PXE Subnets
#
###############################################################################

set +e


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



###############################################################################
# Media
###############################################################################

CENTOS_MEDIA="CentOS 7 Remote"

ROCKY8_MEDIA="Rocky 8 Remote"

ROCKY92_MEDIA="Rocky 9.2 Remote"

ROCKY98_MEDIA="Rocky 9 Remote"



###############################################################################
# OS Names
###############################################################################
#
# IMPORTANT:
#
# Name is ONLY title.
#
# Foreman automatically stores release separately.
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
# Create Media
###############################################################################

create_media()
{

NAME="$1"

URL="$2"


info "Checking Installation Media : ${NAME}"


if $HAMMER medium info --name "${NAME}" >/dev/null 2>&1

then

skip "${NAME} already exists."

else


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

###############################################################################
# Create Operating System
###############################################################################

create_os()
{

OS_NAME="$1"
MAJOR="$2"
MINOR="$3"
MEDIA="$4"


info "Checking OS : ${OS_NAME}"



###############################################################################
# Exact OS Title Check
###############################################################################

OS_EXIST=$(
$HAMMER os list |
awk -F'|' -v name="${OS_NAME}" '

{
gsub(/^ +| +$/,"",$2)

if($2 == name)
{
print $2
}

}

'
)



if [ -n "${OS_EXIST}" ]

then

    skip "${OS_NAME} already exists."

else


    info "Creating ${OS_NAME}"



    if [ -n "${MINOR}" ]

    then


        $HAMMER os create \
        --name "${OS_NAME}" \
        --major "${MAJOR}" \
        --minor "${MINOR}" \
        --family Redhat \
        --architectures x86_64 \
        --partition-tables "Kickstart default" \
        --media "${MEDIA}"


    else


        $HAMMER os create \
        --name "${OS_NAME}" \
        --major "${MAJOR}" \
        --family Redhat \
        --architectures x86_64 \
        --partition-tables "Kickstart default" \
        --media "${MEDIA}"


    fi



    if [ $? -eq 0 ]

    then

        ok "${OS_NAME} created."

    else

        error "Failed creating ${OS_NAME}"

        record_failure "${OS_NAME}"

    fi


fi


echo

}

###############################################################################
# Assign Template To OS
###############################################################################

assign_template()
{

OS_NAME="$1"

TEMPLATE="$2"



info "Checking Template Assignment"

echo "OS       : ${OS_NAME}"

echo "Template : ${TEMPLATE}"



###############################################################################
# Get OS ID using TITLE only
###############################################################################

OS_ID=$(
$HAMMER os list |
awk -F'|' -v name="${OS_NAME}" '

{
gsub(/^ +| +$/,"",$1)
gsub(/^ +| +$/,"",$2)


if($2 == name)
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
grep -Fq "${TEMPLATE}"

then

    skip "${TEMPLATE} already assigned."

    return 0

fi



###############################################################################
# Assign Template
###############################################################################

info "Assigning template..."



$HAMMER os add-provisioning-template \
--id "${OS_ID}" \
--provisioning-template "${TEMPLATE}"



if [ $? -eq 0 ]

then

    ok "${TEMPLATE} assigned."

else

    error "Failed assigning ${TEMPLATE}"

    record_failure "${OS_NAME} -> ${TEMPLATE}"

fi


echo

}

###############################################################################
# Create PXE Subnet
###############################################################################

create_subnet()
{

SUBNET_NAME="$1"
NETWORK="$2"
MASK="$3"
GATEWAY="$4"
DNS="$5"
TFTP_PROXY="$6"
DHCP_PROXY="$7"



info "Checking Subnet : ${SUBNET_NAME}"



###############################################################################
# Check Existing Subnet
###############################################################################

if $HAMMER subnet info \
--name "${SUBNET_NAME}" >/dev/null 2>&1

then

    skip "${SUBNET_NAME} already exists."

else


    info "Creating subnet : ${SUBNET_NAME}"



    $HAMMER subnet create \
    --name "${SUBNET_NAME}" \
    --network "${NETWORK}" \
    --mask "${MASK}" \
    --gateway "${GATEWAY}" \
    --dns-primary "${DNS}" \
    --boot-mode DHCP \
    --ipam DHCP



    if [ $? -eq 0 ]

    then

        ok "${SUBNET_NAME} created."

    else

        error "Failed creating ${SUBNET_NAME}"

        record_failure "${SUBNET_NAME}"

    fi


fi



###############################################################################
# Assign Domain
###############################################################################

DOMAIN_ID=$(
$HAMMER domain list |
awk -F'|' -v d="vgs.com" '

{
gsub(/^ +| +$/,"",$1)
gsub(/^ +| +$/,"",$2)

if($2==d)
{
print $1
}

}

'
)



if [ -n "${DOMAIN_ID}" ]

then


$HAMMER subnet update \
--name "${SUBNET_NAME}" \
--domain-ids "${DOMAIN_ID}"


ok "Domain assigned."

else

warn "Domain not found."

fi



###############################################################################
# Assign TFTP Proxy
###############################################################################

TFTP_ID=$(
$HAMMER proxy list |
awk -F'|' -v p="${TFTP_PROXY}" '

{
gsub(/^ +| +$/,"",$1)
gsub(/^ +| +$/,"",$2)

if($2==p)
{
print $1
}

}

'
)



if [ -n "${TFTP_ID}" ]

then


$HAMMER subnet update \
--name "${SUBNET_NAME}" \
--tftp-id "${TFTP_ID}"


ok "TFTP proxy assigned."

else

warn "TFTP proxy not found : ${TFTP_PROXY}"

fi



###############################################################################
# Assign DHCP Proxy
###############################################################################

DHCP_ID=$(
$HAMMER proxy list |
awk -F'|' -v p="${DHCP_PROXY}" '

{
gsub(/^ +| +$/,"",$1)
gsub(/^ +| +$/,"",$2)

if($2==p)
{
print $1
}

}

'
)



if [ -n "${DHCP_ID}" ]

then


$HAMMER subnet update \
--name "${SUBNET_NAME}" \
--dhcp-id "${DHCP_ID}"


ok "DHCP proxy assigned."

else

warn "DHCP proxy not found : ${DHCP_PROXY}"

fi



echo

}

###############################################################################
# Final Verification
###############################################################################

header "PXE Bootstrap Verification"



###############################################################################
# Operating Systems
###############################################################################

echo
echo "==============================="
echo "Operating Systems"
echo "==============================="


$HAMMER os list |
egrep "CentOSLinux7|RockyLinux8.10|RockyLinux9.2|RockyLinux9.8" \
|| true



###############################################################################
# PXE Templates
###############################################################################

echo
echo "==============================="
echo "PXE Templates"
echo "==============================="


$HAMMER template list |
grep "PXEGrub2" \
|| true




###############################################################################
# Subnets
###############################################################################

echo
echo "==============================="
echo "PXE Subnets"
echo "==============================="


$HAMMER subnet list |
egrep "vgs-subnet-centos|vgs-subnet-rockyos" \
|| true




###############################################################################
# Detailed OS Template Verification
###############################################################################

header "OS Template Mapping Verification"



verify_os_template()
{

OS_ID="$1"


echo

echo "------------------------------------------------------------"

echo "OS ID : ${OS_ID}"

echo "------------------------------------------------------------"


$HAMMER os info \
--id "${OS_ID}" |
awk '
/Title:/,/Parameters:/
'


echo

}



###############################################################################
# Verify Created OS IDs
###############################################################################

OS_IDS=$(
$HAMMER os list |
awk -F'|' '

/CentOSLinux7-RAID/ {print $1}

/CentOSLinux7-SingleDisk/ {print $1}

/RockyLinux8.10-RAID/ {print $1}

/RockyLinux8.10-SingleDisk/ {print $1}

/RockyLinux9.2-RAID/ {print $1}

/RockyLinux9.2-SingleDisk/ {print $1}

/RockyLinux9.8-RAID/ {print $1}

/RockyLinux9.8-SingleDisk/ {print $1}

'
)



for ID in ${OS_IDS}
do

ID=$(echo ${ID} | tr -d ' ')

if [ -n "${ID}" ]

then

verify_os_template "${ID}"

fi

done




###############################################################################
# Final Status
###############################################################################

header "01 - Foreman PXE Bootstrap Completed"



if [ ${#FAILED_STEPS[@]} -eq 0 ]

then

    ok "PXE Bootstrap completed successfully."

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

echo

echo "Manual Verification Commands"

echo "------------------------------------------------------------"


echo

echo "Operating Systems:"
echo

echo 'hammer os list'


echo

echo "Templates:"
echo

echo 'hammer template list | grep PXEGrub2'


echo

echo "Subnets:"
echo

echo 'hammer subnet list'


echo



###############################################################################
# Expected Configuration
###############################################################################

header "Expected Configuration"



cat <<EOF


Operating Systems:

CentOSLinux7-RAID
    |
    +-- PXEGrub2 CentOS UEFI RAID Kickstart


CentOSLinux7-SingleDisk
    |
    +-- PXEGrub2 CentOS UEFI SingleDisk Kickstart



RockyLinux8.10-RAID
    |
    +-- PXEGrub2 Rocky8 UEFI RAID Kickstart


RockyLinux8.10-SingleDisk
    |
    +-- PXEGrub2 Rocky8 UEFI SingleDisk Kickstart



RockyLinux9.2-RAID
    |
    +-- PXEGrub2 Rocky9.2 UEFI RAID Kickstart


RockyLinux9.2-SingleDisk
    |
    +-- PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart



RockyLinux9.8-RAID
    |
    +-- PXEGrub2 Rocky9.8 UEFI RAID Kickstart


RockyLinux9.8-SingleDisk
    |
    +-- PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart



PXE Subnets:

vgs-subnet-centos

vgs-subnet-rockyos



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
