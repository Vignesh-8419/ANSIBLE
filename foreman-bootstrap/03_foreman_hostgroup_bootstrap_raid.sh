#!/bin/bash
###############################################################################
#03 - Foreman Hostgroup Bootstrap (RAID)
#
#Creates RAID Hostgroups:
#
#CentOSLinux7-RAID
#RockyLinux8.10-RAID
#RockyLinux9.2-RAID
#RockyLinux9.8-RAID
#
#Depends On:
#
#01_foreman_pxe_bootstrap.sh
#02_foreman_katello_bootstrap.sh
#
###############################################################################
set +e
FAILED_STEPS=()
record_failure()
{
FAILED_STEPS+=("$1")
}
###############################################################################
#Foreman Credentials
###############################################################################
FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"
HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"
###############################################################################
#Global Configuration
###############################################################################
DOMAIN="vgs.com"
LOCATION="Default Location"
ORGANIZATION="Default Organization"
CENTOS_SUBNET="vgs-subnet-centos"
ROCKY_SUBNET="vgs-subnet-rockyos"
TARGET_VERSION="${TARGET_VERSION:-ALL}"
###############################################################################
#Colors
###############################################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'
###############################################################################
#Logging
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
#RAID PXE Template Mapping
###############################################################################
CENTOS_RAID_TEMPLATE="PXEGrub2 CentOS UEFI RAID Kickstart"
ROCKY8_RAID_TEMPLATE="PXEGrub2 Rocky8 UEFI RAID Kickstart"
ROCKY92_RAID_TEMPLATE="PXEGrub2 Rocky9.2 UEFI RAID Kickstart"
ROCKY98_RAID_TEMPLATE="PXEGrub2 Rocky9.8 UEFI RAID Kickstart"
###############################################################################
#RAID Operating System Mapping
###############################################################################
CENTOS_RAID_OS="CentOSLinux7-RAID"
ROCKY8_RAID_OS="RockyLinux8.10-RAID"
ROCKY92_RAID_OS="RockyLinux9.2-RAID"
ROCKY98_RAID_OS="RockyLinux9.8-RAID"
###############################################################################
#Installation Media Mapping
###############################################################################
CENTOS_MEDIA="CentOS 7 Remote"
ROCKY8_MEDIA="Rocky 8 Remote"
ROCKY92_MEDIA="Rocky 9.2 Remote"
ROCKY98_MEDIA="Rocky 9 Remote"
###############################################################################
#Select Rocky Version
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
#Create CentOS 7 RAID Hostgroup
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
#Create Rocky Linux 8 RAID Hostgroup
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
#Create Rocky Linux 9.x RAID Hostgroups
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
#Create All RAID Hostgroups
###############################################################################
create_raid_hostgroups()
{
header "Creating RAID Hostgroups"
###############################################################################
#CentOS 7 RAID
###############################################################################
create_centos_raid_hostgroup
###############################################################################
#Rocky Linux 8 RAID
###############################################################################
create_rocky8_raid_hostgroup
###############################################################################
#Rocky Linux 9 RAID
###############################################################################
create_rocky9_raid_hostgroups
}
###############################################################################
#Execute Hostgroup Creation
###############################################################################
create_raid_hostgroups
###############################################################################
#Assign RAID Provisioning Templates
###############################################################################
assign_template()
{
OS_NAME="$1"
TEMPLATE="$2"
info "Checking Template Assignment"
echo "OS       : ${OS_NAME}"
echo "Template : ${TEMPLATE}"
###############################################################################
#Verify Template Exists
###############################################################################
if ! $HAMMER template info \
--name "${TEMPLATE}" >/dev/null 2>&1
then
warn "Template not found : ${TEMPLATE}"
record_failure "${TEMPLATE}"
return 1
fi
###############################################################################
#Find Operating System ID
###############################################################################
OS_ID=$(
$HAMMER os list 2>/dev/null |
awk -F'|' -v NAME="${OS_NAME}" '
{
gsub(/^ +| +$/,"",$2)
if($2==NAME)
{
gsub(/^ +| +$/,"",$1)
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
ok "Found Operating System ID : ${OS_ID}"
###############################################################################
#Check Existing Template Assignment
###############################################################################
if $HAMMER os info \
--id "${OS_ID}" 2>/dev/null |
grep -q "${TEMPLATE}"
then
skip "${TEMPLATE} already assigned to ${OS_NAME}"
else
info "Assigning ${TEMPLATE} to ${OS_NAME}"
$HAMMER os add-provisioning-template \
--operatingsystem-id "${OS_ID}" \
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
#Configure RAID PXE Templates
###############################################################################
configure_raid_templates()
{
header "Assigning RAID PXE Templates"
###############################################################################
#CentOS 7 RAID
###############################################################################
assign_template \
"${CENTOS_RAID_OS}" \
"${CENTOS_RAID_TEMPLATE}"
###############################################################################
#Rocky Linux 8 RAID
###############################################################################
assign_template \
"${ROCKY8_RAID_OS}" \
"${ROCKY8_RAID_TEMPLATE}"
###############################################################################
#Rocky Linux 9 RAID
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
###############################################################################
#Run Template Configuration
###############################################################################
configure_raid_templates
###############################################################################
#Set Default PXEGrub2 Template
###############################################################################
set_default_template()
{
OS_NAME="$1"
TEMPLATE="$2"
info "Setting default PXEGrub2 template : ${OS_NAME}"
OS_ID=$(
$HAMMER os list 2>/dev/null |
awk -F'|' -v NAME="${OS_NAME}" '
{
gsub(/^ +| +$/,"",$2)
if($2==NAME)
{
gsub(/^ +| +$/,"",$1)
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
TEMPLATE_ID=$(
$HAMMER template list 2>/dev/null |
awk -F'|' -v NAME="${TEMPLATE}" '
{
gsub(/^ +| +$/,"",$2)
if($2==NAME)
{
gsub(/^ +| +$/,"",$1)
print $1
}
}'
)
if [ -z "${TEMPLATE_ID}" ]
then
error "Template not found : ${TEMPLATE}"
record_failure "${TEMPLATE}"
return 1
fi
$HAMMER os set-default-template \
--id "${OS_ID}" \
--provisioning-template-id "${TEMPLATE_ID}"
if [ $? -eq 0 ]
then
ok "Default PXEGrub2 template assigned."
else
error "Default template assignment failed."
record_failure "${OS_NAME}"
fi
echo
}
###############################################################################
#Default PXEGrub2 Template Mapping
###############################################################################
header "Setting Default RAID PXEGrub2 Templates"
###############################################################################
#CentOS 7 RAID Default Template
###############################################################################
set_default_template \
"CentOSLinux7-RAID" \
"PXEGrub2 CentOS UEFI RAID Kickstart"
###############################################################################
#Rocky Linux 8 RAID Default Template
###############################################################################
set_default_template \
"RockyLinux8.10-RAID" \
"PXEGrub2 Rocky8 UEFI RAID Kickstart"
###############################################################################
#Rocky Linux 9 RAID Default Template
###############################################################################
for IDX in "${!ROCKY_OS_LIST[@]}"
do
OS_NAME="${ROCKY_OS_LIST[$IDX]}"
case "${OS_NAME}" in
"RockyLinux9.2-RAID")
set_default_template \
"${OS_NAME}" \
"PXEGrub2 Rocky9.2 UEFI RAID Kickstart"
;;
"RockyLinux9.8-RAID")
set_default_template \
"${OS_NAME}" \
"PXEGrub2 Rocky9.8 UEFI RAID Kickstart"
;;
esac
done
###############################################################################
#Verify Hostgroups
###############################################################################
verify_hostgroups()
{
HOSTGROUP="$1"
echo
info "Checking Hostgroup : ${HOSTGROUP}"
if $HAMMER hostgroup info \
--name "${HOSTGROUP}" >/dev/null 2>&1
then
ok "${HOSTGROUP} exists."
else
error "${HOSTGROUP} not found."
record_failure "${HOSTGROUP}"
fi
}
###############################################################################
#Verify Operating Systems
###############################################################################
verify_os()
{
OS_NAME="$1"
echo
info "Checking Operating System : ${OS_NAME}"
OS_ID=$(
$HAMMER os list 2>/dev/null |
awk -F'|' -v NAME="${OS_NAME}" '
{
gsub(/^ +| +$/,"",$2)
if($2==NAME)
{
gsub(/^ +| +$/,"",$1)
print $1
}
}'
)
if [ -n "${OS_ID}" ]
then
ok "${OS_NAME} exists with ID ${OS_ID}"
else
error "${OS_NAME} not found."
record_failure "${OS_NAME}"
fi
}
###############################################################################
#Verification Section
###############################################################################
header "RAID Hostgroup Verification"
verify_hostgroups "CentOSLinux7-RAID"
verify_hostgroups "RockyLinux8.10-RAID"
for OS in "${ROCKY_OS_LIST[@]}"
do
verify_hostgroups "${OS}"
done
header "RAID Operating System Verification"
verify_os "CentOSLinux7-RAID"
verify_os "RockyLinux8.10-RAID"
for OS in "${ROCKY_OS_LIST[@]}"
do
verify_os "${OS}"
done
###############################################################################
#Hostgroup List Verification
###############################################################################
header "Hostgroups"
$HAMMER hostgroup list
echo
###############################################################################
#Operating System List Verification
###############################################################################
header "Operating Systems"
$HAMMER os list |
egrep "CentOSLinux7-RAID|RockyLinux8.10-RAID|RockyLinux9.2-RAID|RockyLinux9.8-RAID"
echo
###############################################################################
#PXE Template Verification
###############################################################################
header "RAID PXEGrub2 Templates"
$HAMMER template list |
grep "RAID"
echo
###############################################################################
#Final RAID Configuration Summary
###############################################################################
header "RAID Hostgroup Configuration"
cat <<EOF
Hostgroups:
CentOSLinux7-RAID
 |
 +-- OS : CentOSLinux7-RAID
 +-- PXE : PXEGrub2 CentOS UEFI RAID Kickstart
 +-- Media : CentOS 7 Remote

RockyLinux8.10-RAID
 |
 +-- OS : RockyLinux8.10-RAID
 +-- PXE : PXEGrub2 Rocky8 UEFI RAID Kickstart
 +-- Media : Rocky 8 Remote

RockyLinux9.2-RAID
 |
 +-- OS : RockyLinux9.2-RAID
 +-- PXE : PXEGrub2 Rocky9.2 UEFI RAID Kickstart
 +-- Media : Rocky 9.2 Remote

RockyLinux9.8-RAID
 |
 +-- OS : RockyLinux9.8-RAID
 +-- PXE : PXEGrub2 Rocky9.8 UEFI RAID Kickstart
 +-- Media : Rocky 9 Remote


Disk Layout:
RAID1
 |
 +-- EFI
 |
 +-- RAID /boot
 |
 +-- RAID LVM PV
      |
      +-- /
      +-- swap
      +-- /home
EOF
echo
###############################################################################
#Final Status
###############################################################################
header "03 - Foreman RAID Hostgroup Bootstrap Completed"
if [ ${#FAILED_STEPS[@]} -eq 0 ]
then
ok "RAID Hostgroup Bootstrap completed successfully."
else
warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."
for STEP in "${FAILED_STEPS[@]}"
do
error "${STEP}"
done
fi
###############################################################################
#Manual Verification Commands
###############################################################################
header "Manual Verification Commands"
echo
echo "CentOS RAID"
echo "------------------------------------------------------------"
echo 'hammer --username admin --password "PASSWORD" hostgroup info --name "CentOSLinux7-RAID"'
echo
echo "Rocky Linux 8 RAID"
echo "------------------------------------------------------------"
echo 'hammer --username admin --password "PASSWORD" hostgroup info --name "RockyLinux8.10-RAID"'
echo
echo "Rocky Linux 9.2 RAID"
echo "------------------------------------------------------------"
echo 'hammer --username admin --password "PASSWORD" hostgroup info --name "RockyLinux9.2-RAID"'
echo
echo "Rocky Linux 9.8 RAID"
echo "------------------------------------------------------------"
echo 'hammer --username admin --password "PASSWORD" hostgroup info --name "RockyLinux9.8-RAID"'
echo
echo "PXE Templates"
echo "------------------------------------------------------------"
echo 'hammer --username admin --password "PASSWORD" template list | grep PXEGrub2'
###############################################################################
#Exit
###############################################################################
if [ ${#FAILED_STEPS[@]} -eq 0 ]
then
exit 0
else
exit 1
fi
