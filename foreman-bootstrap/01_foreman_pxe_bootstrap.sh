#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap
#
# Creates:
#
#   - Installation Media
#   - Operating Systems
#   - PXEGrub2 Templates
#   - OS Template Mapping
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
# Foreman Credentials
###############################################################################

FOREMAN_USER="${FOREMAN_USER:-admin}"

FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"


HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"



###############################################################################
# Installation Media
###############################################################################

CENTOS_MEDIA="CentOS 7 Remote"

ROCKY8_MEDIA="Rocky 8 Remote"

ROCKY92_MEDIA="Rocky 9.2 Remote"

ROCKY98_MEDIA="Rocky 9 Remote"



###############################################################################
# Operating System Mapping
#
# NAME:
#   Internal Foreman OS Name
#
# TITLE:
#   Foreman UI Display Title
#
# VERSION:
#   Major / Minor must exist
#
###############################################################################


###############################################################################
# CentOS 7
###############################################################################

CENTOS_RAID_NAME="CentOSLinux7-RAID"
CENTOS_RAID_TITLE="CentOSLinux-RAID"
CENTOS_RAID_MAJOR="7"
CENTOS_RAID_MINOR=""


CENTOS_SINGLE_NAME="CentOSLinux7-SingleDisk"
CENTOS_SINGLE_TITLE="CentOSLinux-SingleDisk"
CENTOS_SINGLE_MAJOR="7"
CENTOS_SINGLE_MINOR=""



###############################################################################
# Rocky Linux 8.10
###############################################################################

ROCKY8_RAID_NAME="RockyLinux8.10-RAID"
ROCKY8_RAID_TITLE="RockyLinux-RAID"
ROCKY8_RAID_MAJOR="8"
ROCKY8_RAID_MINOR="10"


ROCKY8_SINGLE_NAME="RockyLinux8.10-SingleDisk"
ROCKY8_SINGLE_TITLE="RockyLinux-SingleDisk"
ROCKY8_SINGLE_MAJOR="8"
ROCKY8_SINGLE_MINOR="10"



###############################################################################
# Rocky Linux 9.2
###############################################################################

ROCKY92_RAID_NAME="RockyLinux9.2-RAID"
ROCKY92_RAID_TITLE="RockyLinux-RAID"
ROCKY92_RAID_MAJOR="9"
ROCKY92_RAID_MINOR="2"


ROCKY92_SINGLE_NAME="RockyLinux9.2-SingleDisk"
ROCKY92_SINGLE_TITLE="RockyLinux-SingleDisk"
ROCKY92_SINGLE_MAJOR="9"
ROCKY92_SINGLE_MINOR="2"



###############################################################################
# Rocky Linux 9.8
###############################################################################

ROCKY98_RAID_NAME="RockyLinux9.8-RAID"
ROCKY98_RAID_TITLE="RockyLinux-RAID"
ROCKY98_RAID_MAJOR="9"
ROCKY98_RAID_MINOR="8"


ROCKY98_SINGLE_NAME="RockyLinux9.8-SingleDisk"
ROCKY98_SINGLE_TITLE="RockyLinux-SingleDisk"
ROCKY98_SINGLE_MAJOR="9"
ROCKY98_SINGLE_MINOR="8"



###############################################################################
# PXEGrub2 Template Mapping
###############################################################################

CENTOS_RAID_TEMPLATE="PXEGrub2 CentOS UEFI RAID Kickstart"

CENTOS_SINGLE_TEMPLATE="PXEGrub2 CentOS UEFI SingleDisk Kickstart"


ROCKY8_RAID_TEMPLATE="PXEGrub2 Rocky8 UEFI RAID Kickstart"

ROCKY8_SINGLE_TEMPLATE="PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"


ROCKY92_RAID_TEMPLATE="PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

ROCKY92_SINGLE_TEMPLATE="PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"


ROCKY98_RAID_TEMPLATE="PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

ROCKY98_SINGLE_TEMPLATE="PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"


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



###############################################################################
# Media Creation
###############################################################################

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



###############################################################################
# Verify Media
###############################################################################

header "Installation Media Verification"


$HAMMER medium list



###############################################################################
# Create Operating System
###############################################################################

create_os()
{

OS_NAME="$1"
OS_TITLE="$2"
MAJOR="$3"
MINOR="$4"
MEDIA="$5"


info "Checking OS : ${OS_NAME}"



OS_ID=$(
$HAMMER os list |
awk -F'|' -v name="${OS_NAME}" '
{
gsub(/^ +| +$/,"",$1)
gsub(/^ +| +$/,"",$2)

if($2 ~ "^"name)
{
print $1
}
}
'
)



if [ -n "${OS_ID}" ]

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



###############################################################################
# Update OS Title
###############################################################################

OS_ID=$(
$HAMMER os list |
awk -F'|' -v name="${OS_NAME}" '
{
gsub(/^ +| +$/,"",$1)
gsub(/^ +| +$/,"",$2)

if($2 ~ "^"name)
{
print $1
}
}
'
)



if [ -n "${OS_ID}" ]

then


    info "Updating OS Title : ${OS_TITLE}"


    $HAMMER os update \
    --id "${OS_ID}" \
    --title "${OS_TITLE}"


    if [ $? -eq 0 ]

    then

        ok "Title updated : ${OS_TITLE}"

    else

        warn "Title update failed : ${OS_NAME}"

    fi


fi


echo

}

###############################################################################
# Create Operating System Objects
###############################################################################

header "Creating Operating Systems"



###############################################################################
# CentOS 7
###############################################################################

create_os \
"${CENTOS_RAID_NAME}" \
"${CENTOS_RAID_TITLE}" \
"${CENTOS_RAID_MAJOR}" \
"${CENTOS_RAID_MINOR}" \
"${CENTOS_MEDIA}"


create_os \
"${CENTOS_SINGLE_NAME}" \
"${CENTOS_SINGLE_TITLE}" \
"${CENTOS_SINGLE_MAJOR}" \
"${CENTOS_SINGLE_MINOR}" \
"${CENTOS_MEDIA}"



###############################################################################
# Rocky Linux 8.10
###############################################################################

create_os \
"${ROCKY8_RAID_NAME}" \
"${ROCKY8_RAID_TITLE}" \
"${ROCKY8_RAID_MAJOR}" \
"${ROCKY8_RAID_MINOR}" \
"${ROCKY8_MEDIA}"


create_os \
"${ROCKY8_SINGLE_NAME}" \
"${ROCKY8_SINGLE_TITLE}" \
"${ROCKY8_SINGLE_MAJOR}" \
"${ROCKY8_SINGLE_MINOR}" \
"${ROCKY8_MEDIA}"



###############################################################################
# Rocky Linux 9.2
###############################################################################

create_os \
"${ROCKY92_RAID_NAME}" \
"${ROCKY92_RAID_TITLE}" \
"${ROCKY92_RAID_MAJOR}" \
"${ROCKY92_RAID_MINOR}" \
"${ROCKY92_MEDIA}"


create_os \
"${ROCKY92_SINGLE_NAME}" \
"${ROCKY92_SINGLE_TITLE}" \
"${ROCKY92_SINGLE_MAJOR}" \
"${ROCKY92_SINGLE_MINOR}" \
"${ROCKY92_MEDIA}"



###############################################################################
# Rocky Linux 9.8
###############################################################################

create_os \
"${ROCKY98_RAID_NAME}" \
"${ROCKY98_RAID_TITLE}" \
"${ROCKY98_RAID_MAJOR}" \
"${ROCKY98_RAID_MINOR}" \
"${ROCKY98_MEDIA}"


create_os \
"${ROCKY98_SINGLE_NAME}" \
"${ROCKY98_SINGLE_TITLE}" \
"${ROCKY98_SINGLE_MAJOR}" \
"${ROCKY98_SINGLE_MINOR}" \
"${ROCKY98_MEDIA}"



###############################################################################
# Verify Operating Systems
###############################################################################

header "Operating System Verification"


$HAMMER os list



###############################################################################
# Assign PXEGrub2 Template
###############################################################################

assign_pxegrub2_template()
{

OS_NAME="$1"

TEMPLATE="$2"


info "Assigning PXEGrub2 Template"

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

if($2 ~ "^"name)
{
print $1
}
}
'
)



if [ -z "${OS_ID}" ]

then

    error "OS not found : ${OS_NAME}"

    record_failure "${OS_NAME}"

    return 1

fi


ok "Found OS ID : ${OS_ID}"



###############################################################################
# Add Provisioning Template
###############################################################################

$HAMMER os add-provisioning-template \
--id "${OS_ID}" \
--provisioning-template "${TEMPLATE}"



if [ $? -eq 0 ]

then

    ok "Template attached."

else

    error "Failed attaching template."

    record_failure "${OS_NAME}"

fi



###############################################################################
# Set PXEGrub2 Default Template
###############################################################################

$HAMMER os set-default-template \
--id "${OS_ID}" \
--template "${TEMPLATE}" \
--kind PXEGrub2



if [ $? -eq 0 ]

then

    ok "PXEGrub2 default template set."

else

    warn "PXEGrub2 default template update failed."

fi


echo

}

###############################################################################
# PXEGrub2 Template Assignment
###############################################################################

header "Assigning PXEGrub2 Templates"



###############################################################################
# CentOS 7
###############################################################################

assign_pxegrub2_template \
"${CENTOS_RAID_NAME}" \
"${CENTOS_RAID_TEMPLATE}"


assign_pxegrub2_template \
"${CENTOS_SINGLE_NAME}" \
"${CENTOS_SINGLE_TEMPLATE}"



###############################################################################
# Rocky Linux 8.10
###############################################################################

assign_pxegrub2_template \
"${ROCKY8_RAID_NAME}" \
"${ROCKY8_RAID_TEMPLATE}"


assign_pxegrub2_template \
"${ROCKY8_SINGLE_NAME}" \
"${ROCKY8_SINGLE_TEMPLATE}"



###############################################################################
# Rocky Linux 9.2
###############################################################################

assign_pxegrub2_template \
"${ROCKY92_RAID_NAME}" \
"${ROCKY92_RAID_TEMPLATE}"


assign_pxegrub2_template \
"${ROCKY92_SINGLE_NAME}" \
"${ROCKY92_SINGLE_TEMPLATE}"



###############################################################################
# Rocky Linux 9.8
###############################################################################

assign_pxegrub2_template \
"${ROCKY98_RAID_NAME}" \
"${ROCKY98_RAID_TEMPLATE}"


assign_pxegrub2_template \
"${ROCKY98_SINGLE_NAME}" \
"${ROCKY98_SINGLE_TEMPLATE}"



###############################################################################
# Verify OS Template Mapping
###############################################################################

header "OS Template Mapping Verification"


verify_os_template()
{

OS_NAME="$1"


echo

echo "------------------------------------------------------------"

echo "Operating System : ${OS_NAME}"

echo "------------------------------------------------------------"


OS_ID=$(
$HAMMER os list |
awk -F'|' -v name="${OS_NAME}" '
{
gsub(/^ +| +$/,"",$1)
gsub(/^ +| +$/,"",$2)

if($2 ~ "^"name)
{
print $1
}
}
'
)


if [ -z "${OS_ID}" ]

then

    error "OS not found : ${OS_NAME}"

    record_failure "${OS_NAME}"

    return

fi



$HAMMER os info \
--id "${OS_ID}" |
awk '
/Templates:/,/Parameters:/
'


}



verify_os_template "${CENTOS_RAID_NAME}"

verify_os_template "${CENTOS_SINGLE_NAME}"


verify_os_template "${ROCKY8_RAID_NAME}"

verify_os_template "${ROCKY8_SINGLE_NAME}"


verify_os_template "${ROCKY92_RAID_NAME}"

verify_os_template "${ROCKY92_SINGLE_NAME}"


verify_os_template "${ROCKY98_RAID_NAME}"

verify_os_template "${ROCKY98_SINGLE_NAME}"

###############################################################################
# Create PXE Subnets
###############################################################################

header "Creating PXE Subnets"



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

header "PXE Bootstrap Verification"



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

echo "PXE Subnets"

echo "==============================="


$HAMMER subnet list



###############################################################################
# Final OS Template Mapping Check
###############################################################################

header "Final OS Template Mapping"



check_template()
{

OS_NAME="$1"

EXPECTED_TEMPLATE="$2"



echo

echo "------------------------------------------------------------"

echo "OS       : ${OS_NAME}"

echo "Expected : ${EXPECTED_TEMPLATE}"

echo "------------------------------------------------------------"



OS_ID=$(
$HAMMER os list |
awk -F'|' -v name="${OS_NAME}" '
{
gsub(/^ +| +$/,"",$1)
gsub(/^ +| +$/,"",$2)

if($2 ~ "^"name)
{
print $1
}

}
'
)



if [ -z "${OS_ID}" ]

then

    error "OS not found : ${OS_NAME}"

    return

fi



if $HAMMER os info \
--id "${OS_ID}" |
grep -q "${EXPECTED_TEMPLATE}"

then

    ok "Template mapping correct."

else

    error "Template mapping missing."

    record_failure "${OS_NAME}"

fi


}



check_template \
"${CENTOS_RAID_NAME}" \
"${CENTOS_RAID_TEMPLATE}"


check_template \
"${CENTOS_SINGLE_NAME}" \
"${CENTOS_SINGLE_TEMPLATE}"



check_template \
"${ROCKY8_RAID_NAME}" \
"${ROCKY8_RAID_TEMPLATE}"


check_template \
"${ROCKY8_SINGLE_NAME}" \
"${ROCKY8_SINGLE_TEMPLATE}"



check_template \
"${ROCKY92_RAID_NAME}" \
"${ROCKY92_RAID_TEMPLATE}"


check_template \
"${ROCKY92_SINGLE_NAME}" \
"${ROCKY92_SINGLE_TEMPLATE}"



check_template \
"${ROCKY98_RAID_NAME}" \
"${ROCKY98_RAID_TEMPLATE}"


check_template \
"${ROCKY98_SINGLE_NAME}" \
"${ROCKY98_SINGLE_TEMPLATE}"



###############################################################################
# Final Status
###############################################################################

header "01 - Foreman PXE Bootstrap Completed"



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

echo "Manual Verification Commands"

echo "------------------------------------------------------------"

echo

echo "hammer os list"

echo

echo "hammer template list | grep PXEGrub2"

echo

echo "hammer subnet list"

echo


exit 0
