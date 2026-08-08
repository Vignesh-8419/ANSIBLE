#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap
#
# Creates:
#
#   - Installation Media
#   - Separate Operating Systems
#   - PXEGrub2 Templates
#   - OS Template Mapping
#   - Subnets
#
# Design:
#
#   RAID and SingleDisk have separate OS objects.
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


DOMAIN="vgs.com"


TARGET_VERSION="${TARGET_VERSION:-ALL}"



###############################################################################
# Operating System Names
###############################################################################

CENTOS7_RAID="CentOSLinux7-RAID"

CENTOS7_SINGLE="CentOSLinux7-SingleDisk"



ROCKY8_RAID="RockyLinux8.10-RAID"

ROCKY8_SINGLE="RockyLinux8.10-SingleDisk"



ROCKY92_RAID="RockyLinux9.2-RAID"

ROCKY92_SINGLE="RockyLinux9.2-SingleDisk"



ROCKY98_RAID="RockyLinux9.8-RAID"

ROCKY98_SINGLE="RockyLinux9.8-SingleDisk"



###############################################################################
# Installation Media
###############################################################################

CENTOS_MEDIA="CentOS 7 Remote"

ROCKY8_MEDIA="Rocky 8 Remote"

ROCKY92_MEDIA="Rocky 9.2 Remote"

ROCKY98_MEDIA="Rocky 9 Remote"



###############################################################################
# [1/6] Create Installation Media
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
# [2/6] Create Operating Systems
###############################################################################

header "[2/6] Creating Operating Systems"



create_os()
{

NAME="$1"
MAJOR="$2"
MINOR="$3"
MEDIA="$4"


info "Checking OS : ${NAME}"


if $HAMMER os info \
--title "${NAME}" >/dev/null 2>&1

then

    skip "${NAME} already exists."

else


    info "Creating ${NAME}"


    if [ -n "${MINOR}" ]

    then

        $HAMMER os create \
        --name "${NAME}" \
        --major "${MAJOR}" \
        --minor "${MINOR}" \
        --family Redhat \
        --architectures x86_64 \
        --partition-tables "Kickstart default" \
        --media "${MEDIA}"


    else


        $HAMMER os create \
        --name "${NAME}" \
        --major "${MAJOR}" \
        --family Redhat \
        --architectures x86_64 \
        --partition-tables "Kickstart default" \
        --media "${MEDIA}"

    fi



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
# CentOS 7
###############################################################################

create_os \
"${CENTOS7_RAID}" \
7 \
"" \
"${CENTOS_MEDIA}"


create_os \
"${CENTOS7_SINGLE}" \
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


header "Operating System Verification"


$HAMMER os list

###############################################################################
# [3/6] Creating PXEGrub2 Templates
###############################################################################

header "[3/6] Creating PXEGrub2 Templates"



###############################################################################
# Create Template Function
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
# CentOS 7 RAID PXE Template
###############################################################################

cat >/tmp/centos7-raid.erb <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI RAID Kickstart
kind: PXEGrub2
%>

set default=0
set timeout=5


menuentry 'Install CentOS 7 RAID' {

linuxefi /centos/vmlinuz \
inst.stage2=http://192.168.253.136/repo/centos/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/centos7.cfg \
inst.text \
ip=dhcp \
hostname=<%= @host.name %>


initrdefi /centos/initrd.img

}
EOF



###############################################################################
# CentOS 7 Single Disk PXE Template
###############################################################################

cat >/tmp/centos7-single.erb <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI SingleDisk Kickstart
kind: PXEGrub2
%>

set default=0
set timeout=5


menuentry 'Install CentOS 7 Single Disk' {

linuxefi /centos/vmlinuz \
inst.stage2=http://192.168.253.136/repo/centos/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/centos7-single.cfg \
inst.text \
ip=dhcp \
hostname=<%= @host.name %>


initrdefi /centos/initrd.img

}
EOF



###############################################################################
# Rocky Linux 8 RAID PXE Template
###############################################################################

cat >/tmp/rocky8-raid.erb <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI RAID Kickstart
kind: PXEGrub2
%>

set default=0
set timeout=5


menuentry 'Install Rocky Linux 8 RAID' {

linuxefi /rocky8/vmlinuz \
inst.stage2=http://192.168.253.136/repo/rocky8/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/rocky8.cfg \
inst.text \
ip=dhcp \
hostname=<%= @host.name %>


initrdefi /rocky8/initrd.img

}
EOF



###############################################################################
# Rocky Linux 8 Single Disk PXE Template
###############################################################################

cat >/tmp/rocky8-single.erb <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI SingleDisk Kickstart
kind: PXEGrub2
%>

set default=0
set timeout=5


menuentry 'Install Rocky Linux 8 Single Disk' {

linuxefi /rocky8/vmlinuz \
inst.stage2=http://192.168.253.136/repo/rocky8/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/rocky8-single.cfg \
inst.text \
ip=dhcp \
hostname=<%= @host.name %>


initrdefi /rocky8/initrd.img

}
EOF

###############################################################################
# [3/6] Creating PXEGrub2 Templates
###############################################################################

header "[3/6] Creating PXEGrub2 Templates"



###############################################################################
# Create Template Function
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
# CentOS 7 RAID PXE Template
###############################################################################

cat >/tmp/centos7-raid.erb <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI RAID Kickstart
kind: PXEGrub2
%>

set default=0
set timeout=5


menuentry 'Install CentOS 7 RAID' {

linuxefi /centos/vmlinuz \
inst.stage2=http://192.168.253.136/repo/centos/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/centos7.cfg \
inst.text \
ip=dhcp \
hostname=<%= @host.name %>


initrdefi /centos/initrd.img

}
EOF



###############################################################################
# CentOS 7 Single Disk PXE Template
###############################################################################

cat >/tmp/centos7-single.erb <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI SingleDisk Kickstart
kind: PXEGrub2
%>

set default=0
set timeout=5


menuentry 'Install CentOS 7 Single Disk' {

linuxefi /centos/vmlinuz \
inst.stage2=http://192.168.253.136/repo/centos/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/centos7-single.cfg \
inst.text \
ip=dhcp \
hostname=<%= @host.name %>


initrdefi /centos/initrd.img

}
EOF



###############################################################################
# Rocky Linux 8 RAID PXE Template
###############################################################################

cat >/tmp/rocky8-raid.erb <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI RAID Kickstart
kind: PXEGrub2
%>

set default=0
set timeout=5


menuentry 'Install Rocky Linux 8 RAID' {

linuxefi /rocky8/vmlinuz \
inst.stage2=http://192.168.253.136/repo/rocky8/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/rocky8.cfg \
inst.text \
ip=dhcp \
hostname=<%= @host.name %>


initrdefi /rocky8/initrd.img

}
EOF



###############################################################################
# Rocky Linux 8 Single Disk PXE Template
###############################################################################

cat >/tmp/rocky8-single.erb <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI SingleDisk Kickstart
kind: PXEGrub2
%>

set default=0
set timeout=5


menuentry 'Install Rocky Linux 8 Single Disk' {

linuxefi /rocky8/vmlinuz \
inst.stage2=http://192.168.253.136/repo/rocky8/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/rocky8-single.cfg \
inst.text \
ip=dhcp \
hostname=<%= @host.name %>


initrdefi /rocky8/initrd.img

}
EOF

###############################################################################
# Assign PXE Templates To Operating Systems
###############################################################################

header "Assigning PXE Templates To Operating Systems"



assign_template()
{

OS_NAME="$1"
TEMPLATE="$2"


info "Checking Template Assignment"

echo "OS       : ${OS_NAME}"
echo "Template : ${TEMPLATE}"



###############################################################################
# Check OS Exists
###############################################################################

if ! $HAMMER os info \
--name "${OS_NAME}" >/dev/null 2>&1

then

    error "Operating System not found : ${OS_NAME}"

    record_failure "${OS_NAME}"

    return 1

fi



###############################################################################
# Check Existing Assignment
###############################################################################

if $HAMMER os info \
--name "${OS_NAME}" 2>/dev/null |
grep -q "${TEMPLATE}"

then

    skip "${TEMPLATE} already assigned to ${OS_NAME}"

else


    info "Assigning ${TEMPLATE} -> ${OS_NAME}"


    $HAMMER os add-provisioning-template \
    --name "${OS_NAME}" \
    --provisioning-template "${TEMPLATE}"



    if [ $? -eq 0 ]

    then

        ok "${TEMPLATE} assigned."

    else

        error "Failed assigning ${TEMPLATE}"

        record_failure "${OS_NAME}"

    fi


fi


echo

}



###############################################################################
# CentOS 7
###############################################################################

assign_template \
"CentOSLinux7-RAID" \
"PXEGrub2 CentOS UEFI RAID Kickstart"


assign_template \
"CentOSLinux7-SingleDisk" \
"PXEGrub2 CentOS UEFI SingleDisk Kickstart"



###############################################################################
# Rocky Linux 8.10
###############################################################################

assign_template \
"RockyLinux8.10-RAID" \
"PXEGrub2 Rocky8 UEFI RAID Kickstart"


assign_template \
"RockyLinux8.10-SingleDisk" \
"PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"



###############################################################################
# Rocky Linux 9.2
###############################################################################

assign_template \
"RockyLinux9.2-RAID" \
"PXEGrub2 Rocky9.2 UEFI RAID Kickstart"


assign_template \
"RockyLinux9.2-SingleDisk" \
"PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"



###############################################################################
# Rocky Linux 9.8
###############################################################################

assign_template \
"RockyLinux9.8-RAID" \
"PXEGrub2 Rocky9.8 UEFI RAID Kickstart"


assign_template \
"RockyLinux9.8-SingleDisk" \
"PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"



###############################################################################
# Set Default PXE Templates
###############################################################################

header "Setting Default PXE Templates"



set_default_template()
{

OS_NAME="$1"
TEMPLATE="$2"



TEMPLATE_ID=$(
$HAMMER template list |
awk -F'|' -v t="${TEMPLATE}" '
{
gsub(/^ +| +$/,"",$1)
gsub(/^ +| +$/,"",$2)

if($2==t)
print $1
}'
)



if [ -z "${TEMPLATE_ID}" ]

then

    error "Template not found : ${TEMPLATE}"

    record_failure "${TEMPLATE}"

    return

fi



info "Setting default template"

echo "OS       : ${OS_NAME}"
echo "Template : ${TEMPLATE}"



$HAMMER os set-default-template \
--title "${OS_NAME}" \
--config-template-id "${TEMPLATE_ID}"



if [ $? -eq 0 ]

then

    ok "Default template configured."

else

    error "Failed setting default template."

    record_failure "${OS_NAME}"

fi


echo

}



###############################################################################
# Default Templates
###############################################################################

set_default_template \
"CentOSLinux7-RAID" \
"PXEGrub2 CentOS UEFI RAID Kickstart"


set_default_template \
"CentOSLinux7-SingleDisk" \
"PXEGrub2 CentOS UEFI SingleDisk Kickstart"



set_default_template \
"RockyLinux8.10-RAID" \
"PXEGrub2 Rocky8 UEFI RAID Kickstart"


set_default_template \
"RockyLinux8.10-SingleDisk" \
"PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"



set_default_template \
"RockyLinux9.2-RAID" \
"PXEGrub2 Rocky9.2 UEFI RAID Kickstart"


set_default_template \
"RockyLinux9.2-SingleDisk" \
"PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"



set_default_template \
"RockyLinux9.8-RAID" \
"PXEGrub2 Rocky9.8 UEFI RAID Kickstart"


set_default_template \
"RockyLinux9.8-SingleDisk" \
"PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"



###############################################################################
# Final Verification
###############################################################################

header "Final PXE Bootstrap Verification"


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
echo "Provisioning Template Mapping"
echo "==============================="


for OS in \
"CentOSLinux7-RAID" \
"CentOSLinux7-SingleDisk" \
"RockyLinux8.10-RAID" \
"RockyLinux8.10-SingleDisk" \
"RockyLinux9.2-RAID" \
"RockyLinux9.2-SingleDisk" \
"RockyLinux9.8-RAID" \
"RockyLinux9.8-SingleDisk"

do

echo
echo "--------------------------------"
echo "OS : ${OS}"
echo "--------------------------------"

$HAMMER os info \
--title "${OS}"


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


echo

ok "Bootstrap finished."

exit 0
