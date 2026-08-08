#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap
#
# Creates:
#
#   - Installation Media
#   - 2 OS Objects per version
#       RAID
#       SingleDisk
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


TARGET_VERSION="${TARGET_VERSION:-9.8}"



###############################################################################
# Media
###############################################################################

CENTOS_MEDIA="CentOS 7 Remote"

ROCKY8_MEDIA="Rocky 8 Remote"

ROCKY92_MEDIA="Rocky 9.2 Remote"

ROCKY98_MEDIA="Rocky 9 Remote"



###############################################################################
# OS Names
#
# IMPORTANT:
# No spaces.
# Foreman automatically appends release version.
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
# Create Operating System
###############################################################################

create_os()
{

OS_NAME="$1"
MAJOR="$2"
MINOR="$3"
MEDIA="$4"


info "Checking OS : ${OS_NAME}"


if $HAMMER os list | awk -F'|' '{print $2}' | grep -q "${OS_NAME}"
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
# Create OS Objects
###############################################################################


###############################################################################
# CentOS 7
###############################################################################

create_os \
"${CENTOS_RAID}" \
7 \
"" \
"${CENTOS_MEDIA}"


create_os \
"${CENTOS_SINGLE}" \
7 \
"" \
"${CENTOS_MEDIA}"



###############################################################################
# Rocky Linux 8.10
###############################################################################

create_os \
"${ROCKY8_RAID}" \
8 \
10 \
"${ROCKY8_MEDIA}"


create_os \
"${ROCKY8_SINGLE}" \
8 \
10 \
"${ROCKY8_MEDIA}"



###############################################################################
# Rocky Linux 9.2
###############################################################################

create_os \
"${ROCKY92_RAID}" \
9 \
2 \
"${ROCKY92_MEDIA}"


create_os \
"${ROCKY92_SINGLE}" \
9 \
2 \
"${ROCKY92_MEDIA}"



###############################################################################
# Rocky Linux 9.8
###############################################################################

create_os \
"${ROCKY98_RAID}" \
9 \
8 \
"${ROCKY98_MEDIA}"


create_os \
"${ROCKY98_SINGLE}" \
9 \
8 \
"${ROCKY98_MEDIA}"



###############################################################################
# Verify OS
###############################################################################

header "Operating System Verification"


$HAMMER os list

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
# Example Templates
#
# Keep your existing .erb files.
# Only import logic changed.
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
# Get OS ID
###############################################################################

OS_ID=$(
$HAMMER os list |
awk -F'|' -v name="${OS_NAME}" '

{
gsub(/^ +| +$/,"",$1)
gsub(/^ +| +$/,"",$2)

if ($2 ~ "^"name" ")
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


assign_template \
"${CENTOS_RAID}" \
"PXEGrub2 CentOS UEFI RAID Kickstart"


assign_template \
"${CENTOS_SINGLE}" \
"PXEGrub2 CentOS UEFI SingleDisk Kickstart"



assign_template \
"${ROCKY8_RAID}" \
"PXEGrub2 Rocky8 UEFI RAID Kickstart"


assign_template \
"${ROCKY8_SINGLE}" \
"PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"



assign_template \
"${ROCKY92_RAID}" \
"PXEGrub2 Rocky9.2 UEFI RAID Kickstart"


assign_template \
"${ROCKY92_SINGLE}" \
"PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"



assign_template \
"${ROCKY98_RAID}" \
"PXEGrub2 Rocky9.8 UEFI RAID Kickstart"


assign_template \
"${ROCKY98_SINGLE}" \
"PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"



###############################################################################
# Verify Assignment
###############################################################################

header "OS Template Verification"


$HAMMER os list

###############################################################################
# Create PXE Subnets
###############################################################################

header "[4/6] Creating PXE Subnets"



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



if $HAMMER subnet info \
--name "${SUBNET_NAME}" >/dev/null 2>&1

then

    skip "${SUBNET_NAME} already exists."

else


    info "Creating ${SUBNET_NAME}"


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
print $1

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
print $1

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
print $1

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
# CentOS PXE Subnet
###############################################################################

create_subnet \
"vgs-subnet-centos" \
"192.168.253.0" \
"255.255.255.0" \
"192.168.253.2" \
"192.168.253.1" \
"cent-07-01.vgs.com" \
"cent-07-01.vgs.com"




###############################################################################
# Rocky PXE Subnet
###############################################################################

create_subnet \
"vgs-subnet-rockyos" \
"192.168.253.0" \
"255.255.255.0" \
"192.168.253.2" \
"192.168.253.1" \
"cent-07-02.vgs.com" \
"cent-07-02.vgs.com"




###############################################################################
# Final Verification
###############################################################################

header "[5/6] PXE Bootstrap Verification"



echo
echo "==============================="
echo "Operating Systems"
echo "==============================="

$HAMMER os list



echo
echo "==============================="
echo "PXE Templates"
echo "==============================="

$HAMMER template list | grep PXEGrub2



echo
echo "==============================="
echo "Subnets"
echo "==============================="

$HAMMER subnet list





###############################################################################
# Final Status
###############################################################################

header "[6/6] PXE Bootstrap Completed"



if [ ${#FAILED_STEPS[@]} -eq 0 ]
then

    ok "PXE Bootstrap completed successfully."

else

    warn "Completed with ${#FAILED_STEPS[@]} failure(s)."


    for ITEM in "${FAILED_STEPS[@]}"
    do

        error "${ITEM}"

    done

fi



echo

echo "Manual Verification:"
echo "------------------------------------------------------------"

echo

echo "hammer os list"

echo

echo "hammer template list | grep PXEGrub2"

echo

echo "hammer subnet list"

echo


exit 0
