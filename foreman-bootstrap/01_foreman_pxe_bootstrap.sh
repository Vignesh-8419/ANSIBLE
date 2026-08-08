#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap
#
# Creates:
#
#   - Installation Media
#   - Operating Systems
#   - PXEGrub2 Templates
#   - Subnets
#
# Design:
#
#   OS Objects:
#
#       CentOSLinux7
#       RockyLinux8.10
#       RockyLinux9.2
#       RockyLinux9.8
#
#
#   RAID / SingleDisk:
#
#       Controlled by Hostgroups
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


DOMAIN="vgs.com"



###############################################################################
# Installation Media
###############################################################################

CENTOS_MEDIA="CentOS 7 Remote"

ROCKY8_MEDIA="Rocky 8 Remote"

ROCKY92_MEDIA="Rocky 9.2 Remote"

ROCKY98_MEDIA="Rocky 9 Remote"



###############################################################################
# Operating System Objects
#
# IMPORTANT:
#
# No spaces in OS object names.
#
###############################################################################

CENTOS_OS="CentOSLinux7"

ROCKY8_OS="RockyLinux8.10"

ROCKY92_OS="RockyLinux9.2"

ROCKY98_OS="RockyLinux9.8"



###############################################################################
# Select Rocky Target
###############################################################################

case "${TARGET_VERSION}" in


9.2)

    ROCKY_OS="${ROCKY92_OS}"

    ROCKY_MEDIA="${ROCKY92_MEDIA}"

;;


9.8)

    ROCKY_OS="${ROCKY98_OS}"

    ROCKY_MEDIA="${ROCKY98_MEDIA}"

;;


*)

    error "Unsupported TARGET_VERSION=${TARGET_VERSION}"

    exit 1

;;

esac


###############################################################################
# [1/6] Installation Media
###############################################################################

header "[1/6] Creating Installation Media"



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
# Create Installation Media
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



header "Installation Media Verification"


$HAMMER medium list




###############################################################################
# [2/6] Creating Operating Systems
###############################################################################

header "[2/6] Creating Operating Systems"



###############################################################################
# Create OS Function
###############################################################################

create_os()
{

TITLE="$1"

OS_NAME="$2"

MAJOR="$3"

MINOR="$4"

MEDIA="$5"



info "Checking OS : ${TITLE}"



if $HAMMER os info \
    --title "${TITLE}" >/dev/null 2>&1

then

    skip "${TITLE} already exists."

else


    info "Creating ${TITLE}"



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

        ok "${TITLE} created."

    else

        error "Failed creating ${TITLE}"

        record_failure "${TITLE}"

    fi


fi


echo

}



###############################################################################
# Create OS Objects
###############################################################################


###############################################################################
# CentOS Linux 7
###############################################################################

create_os \
"CentOSLinux 7" \
"CentOSLinux7" \
7 \
"" \
"${CENTOS_MEDIA}"



###############################################################################
# Rocky Linux 8.10
###############################################################################

create_os \
"RockyLinux 8.10" \
"RockyLinux8.10" \
8 \
10 \
"${ROCKY8_MEDIA}"



###############################################################################
# Rocky Linux 9.2
###############################################################################

create_os \
"RockyLinux 9.2" \
"RockyLinux9.2" \
9 \
2 \
"${ROCKY92_MEDIA}"



###############################################################################
# Rocky Linux 9.8
###############################################################################

create_os \
"RockyLinux 9.8" \
"RockyLinux9.8" \
9 \
8 \
"${ROCKY98_MEDIA}"



###############################################################################
# OS Verification
###############################################################################

header "Operating System Verification"


$HAMMER os list

###############################################################################
# [3/6] Creating PXEGrub2 Templates
###############################################################################

header "[3/6] Creating PXEGrub2 Templates"



###############################################################################
# Template Import Function
###############################################################################

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
# CentOS 7 RAID Template
###############################################################################

cat >/tmp/centos7-raid.erb <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI RAID Kickstart
kind: PXEGrub2
oses:
- CentOSLinux
%>

set default=0
set timeout=5


menuentry 'Install CentOS 7 RAID1' {


linuxefi /centos/vmlinuz \
inst.stage2=http://192.168.253.136/repo/centos/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/centos7.cfg \
inst.text \
BOOTIF=01-${net_default_mac} \
hostname=<%= @host.name %>


initrdefi /centos/initrd.img

}
EOF




###############################################################################
# CentOS 7 Single Disk Template
###############################################################################

cat >/tmp/centos7-single.erb <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- CentOSLinux
%>

set default=0
set timeout=5


menuentry 'Install CentOS 7 Single Disk' {


linuxefi /centos/vmlinuz \
inst.stage2=http://192.168.253.136/repo/centos/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/centos7-single.cfg \
inst.text \
BOOTIF=01-${net_default_mac} \
hostname=<%= @host.name %>


initrdefi /centos/initrd.img

}
EOF




###############################################################################
# Rocky Linux 8 RAID Template
###############################################################################

cat >/tmp/rocky8-raid.erb <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI RAID Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5


menuentry 'Install Rocky Linux 8 RAID1' {


linuxefi /rocky8/vmlinuz \
inst.stage2=http://192.168.253.136/repo/rocky8/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/rocky8.cfg \
inst.text \
BOOTIF=01-${net_default_mac} \
hostname=<%= @host.name %>


initrdefi /rocky8/initrd.img

}
EOF




###############################################################################
# Rocky Linux 8 Single Disk Template
###############################################################################

cat >/tmp/rocky8-single.erb <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5


menuentry 'Install Rocky Linux 8 Single Disk' {


linuxefi /rocky8/vmlinuz \
inst.stage2=http://192.168.253.136/repo/rocky8/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/rocky8-single.cfg \
inst.text \
BOOTIF=01-${net_default_mac} \
hostname=<%= @host.name %>


initrdefi /rocky8/initrd.img

}
EOF




###############################################################################
# Rocky Linux 9.2 RAID Template
###############################################################################

cat >/tmp/rocky92-raid.erb <<'EOF'
<%#
name: PXEGrub2 Rocky9.2 UEFI RAID Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5


menuentry 'Install Rocky Linux 9.2 RAID1' {


linuxefi /rocky92/vmlinuz \
ip=dhcp \
inst.repo=http://192.168.253.136/repo/rocky9.2/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/rocky9.cfg \
inst.text \
BOOTIF=01-${net_default_mac} \
hostname=<%= @host.name %>


initrdefi /rocky92/initrd.img

}
EOF




###############################################################################
# Rocky Linux 9.2 Single Disk Template
###############################################################################

cat >/tmp/rocky92-single.erb <<'EOF'
<%#
name: PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5


menuentry 'Install Rocky Linux 9.2 Single Disk' {


linuxefi /rocky92/vmlinuz \
ip=dhcp \
inst.repo=http://192.168.253.136/repo/rocky9.2/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/rocky9-single.cfg \
inst.text \
BOOTIF=01-${net_default_mac} \
hostname=<%= @host.name %>


initrdefi /rocky92/initrd.img

}
EOF

###############################################################################
# Rocky Linux 9.8 RAID Template
###############################################################################

cat >/tmp/rocky98-raid.erb <<'EOF'
<%#
name: PXEGrub2 Rocky9.8 UEFI RAID Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5


menuentry 'Install Rocky Linux 9.8 RAID1' {


linuxefi /rocky9/vmlinuz \
ip=dhcp \
inst.repo=http://192.168.253.136/repo/rocky9/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/rocky9.cfg \
inst.text \
BOOTIF=01-${net_default_mac} \
hostname=<%= @host.name %>


initrdefi /rocky9/initrd.img

}
EOF




###############################################################################
# Rocky Linux 9.8 Single Disk Template
###############################################################################

cat >/tmp/rocky98-single.erb <<'EOF'
<%#
name: PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5


menuentry 'Install Rocky Linux 9.8 Single Disk' {


linuxefi /rocky9/vmlinuz \
ip=dhcp \
inst.repo=http://192.168.253.136/repo/rocky9/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/rocky9-single.cfg \
inst.text \
BOOTIF=01-${net_default_mac} \
hostname=<%= @host.name %>


initrdefi /rocky9/initrd.img

}
EOF



###############################################################################
# Import PXE Templates
###############################################################################

header "Importing PXEGrub2 Templates"



create_template \
"PXEGrub2 CentOS UEFI RAID Kickstart" \
"/tmp/centos7-raid.erb"


create_template \
"PXEGrub2 CentOS UEFI SingleDisk Kickstart" \
"/tmp/centos7-single.erb"



create_template \
"PXEGrub2 Rocky8 UEFI RAID Kickstart" \
"/tmp/rocky8-raid.erb"


create_template \
"PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" \
"/tmp/rocky8-single.erb"



create_template \
"PXEGrub2 Rocky9.2 UEFI RAID Kickstart" \
"/tmp/rocky92-raid.erb"


create_template \
"PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart" \
"/tmp/rocky92-single.erb"



create_template \
"PXEGrub2 Rocky9.8 UEFI RAID Kickstart" \
"/tmp/rocky98-raid.erb"


create_template \
"PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart" \
"/tmp/rocky98-single.erb"




###############################################################################
# Assign Templates To Operating Systems
###############################################################################

header "Assigning PXE Templates To OS"



assign_template()
{

OS="$1"

TPL="$2"



info "Checking ${TPL} -> ${OS}"



if $HAMMER os info \
    --title "${OS}" 2>/dev/null |
    grep -q "${TPL}"

then

    skip "${TPL} already assigned."

else


    $HAMMER os add-provisioning-template \
        --title "${OS}" \
        --provisioning-template "${TPL}"



    if [ $? -eq 0 ]

    then

        ok "${TPL} assigned."

    else

        error "Failed assigning ${TPL}"

        record_failure "${OS}"

    fi


fi


echo

}



assign_template \
"CentOSLinux 7 RAID" \
"PXEGrub2 CentOS UEFI RAID Kickstart"


assign_template \
"CentOSLinux 7 SingleDisk" \
"PXEGrub2 CentOS UEFI SingleDisk Kickstart"



assign_template \
"RockyLinux 8.10 RAID" \
"PXEGrub2 Rocky8 UEFI RAID Kickstart"


assign_template \
"RockyLinux 8.10 SingleDisk" \
"PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"



assign_template \
"RockyLinux 9.2 RAID" \
"PXEGrub2 Rocky9.2 UEFI RAID Kickstart"


assign_template \
"RockyLinux 9.2 SingleDisk" \
"PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"



assign_template \
"RockyLinux 9.8 RAID" \
"PXEGrub2 Rocky9.8 UEFI RAID Kickstart"


assign_template \
"RockyLinux 9.8 SingleDisk" \
"PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"




###############################################################################
# Create PXE Subnets
###############################################################################

header "[4/6] Creating PXE Subnets"



create_subnet()
{

SUBNET="$1"

NETWORK="$2"

MASK="$3"

GATEWAY="$4"

DNS="$5"



info "Checking Subnet : ${SUBNET}"



if $HAMMER subnet info \
    --name "${SUBNET}" >/dev/null 2>&1

then

    skip "${SUBNET} already exists."

else


    $HAMMER subnet create \
        --name "${SUBNET}" \
        --network "${NETWORK}" \
        --mask "${MASK}" \
        --gateway "${GATEWAY}" \
        --dns-primary "${DNS}" \
        --boot-mode DHCP \
        --ipam DHCP



    if [ $? -eq 0 ]

    then

        ok "${SUBNET} created."

    else

        error "Failed creating ${SUBNET}"

        record_failure "${SUBNET}"

    fi


fi


echo

}



create_subnet \
"vgs-subnet-centos" \
"192.168.253.0" \
"255.255.255.0" \
"192.168.253.2" \
"192.168.253.1"



create_subnet \
"vgs-subnet-rockyos" \
"192.168.253.0" \
"255.255.255.0" \
"192.168.253.2" \
"192.168.253.1"




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
# Final Summary
###############################################################################

header "[6/6] PXE Bootstrap Summary"



echo

echo "Created OS Objects:"
echo "-------------------"

echo "CentOSLinux 7 RAID"

echo "CentOSLinux 7 SingleDisk"

echo "RockyLinux 8.10 RAID"

echo "RockyLinux 8.10 SingleDisk"

echo "RockyLinux 9.2 RAID"

echo "RockyLinux 9.2 SingleDisk"

echo "RockyLinux 9.8 RAID"

echo "RockyLinux 9.8 SingleDisk"



echo

echo "PXE Templates:"
echo "---------------"

$HAMMER template list | grep PXEGrub2



echo

echo "Hostgroups can now use:"
echo "-----------------------"

echo "CentOSLinux 7 RAID"

echo "CentOSLinux 7 SingleDisk"

echo "RockyLinux 8.10 RAID"

echo "RockyLinux 8.10 SingleDisk"

echo "RockyLinux 9.2 RAID"

echo "RockyLinux 9.2 SingleDisk"

echo "RockyLinux 9.8 RAID"

echo "RockyLinux 9.8 SingleDisk"




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


echo

exit 0
