#!/bin/bash
###############################################################################
#03 - Foreman Hostgroup Bootstrap (Single Disk)
#
#Creates Single Disk Hostgroups:
#
#CentOSLinux7-SingleDisk
#RockyLinux8.10-SingleDisk
#RockyLinux9.2-SingleDisk
#RockyLinux9.8-SingleDisk
#
#Depends:
#01_foreman_pxe_bootstrap.sh
#02_foreman_katello_bootstrap.sh
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
header "03 - Foreman Single Disk Hostgroup Bootstrap"
###############################################################################
#Single Disk OS Mapping
###############################################################################
CENTOS_SINGLE_OS="CentOSLinux7-SingleDisk"
ROCKY8_SINGLE_OS="RockyLinux8.10-SingleDisk"
ROCKY92_SINGLE_OS="RockyLinux9.2-SingleDisk"
ROCKY98_SINGLE_OS="RockyLinux9.8-SingleDisk"
###############################################################################
#Installation Media Mapping
###############################################################################
CENTOS_MEDIA="CentOS 7 Remote"
ROCKY8_MEDIA="Rocky 8 Remote"
ROCKY92_MEDIA="Rocky 9.2 Remote"
ROCKY98_MEDIA="Rocky 9 Remote"
###############################################################################
#PXE Template Mapping
###############################################################################
CENTOS_SINGLE_TEMPLATE="PXEGrub2 CentOS UEFI SingleDisk Kickstart"
ROCKY8_SINGLE_TEMPLATE="PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"
ROCKY92_SINGLE_TEMPLATE="PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"
ROCKY98_SINGLE_TEMPLATE="PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"
###############################################################################
#OS ID Lookup
###############################################################################
get_os_id()
{
OS_NAME="$1"
$HAMMER os list 2>/dev/null |
awk -F'|' -v NAME="${OS_NAME}" '
{
gsub(/^ +| +$/,"",$2)
if($2 ~ NAME)
{
gsub(/^ +| +$/,"",$1)
print $1
}
}'
}
###############################################################################
#Select Rocky Version
###############################################################################
case "${TARGET_VERSION}" in
9.2)
ROCKY_HOSTGROUPS=(
"RockyLinux9.2-SingleDisk"
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
"RockyLinux9.8-SingleDisk"
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
"RockyLinux9.2-SingleDisk"
"RockyLinux9.8-SingleDisk"
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
error "Unsupported TARGET_VERSION=${TARGET_VERSION}"
exit 1
;;
esac
###############################################################################
#Create Single Disk Hostgroup Function
###############################################################################
create_hostgroup()
{
HOSTGROUP="$1"
SUBNET="$2"
OS_NAME="$3"
MEDIA="$4"
info "Checking Hostgroup : ${HOSTGROUP}"
if $HAMMER hostgroup info \
--name "${HOSTGROUP}" >/dev/null 2>&1
then
skip "${HOSTGROUP} already exists."
else
OS_ID=$(get_os_id "${OS_NAME}")
if [ -z "${OS_ID}" ]
then
error "Operating System not found : ${OS_NAME}"
record_failure "${OS_NAME}"
return 1
fi
info "Creating ${HOSTGROUP}..."
$HAMMER hostgroup create \
--name "${HOSTGROUP}" \
--organization "${ORGANIZATION}" \
--location "${LOCATION}" \
--subnet "${SUBNET}" \
--domain "${DOMAIN}" \
--operatingsystem-id "${OS_ID}" \
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
}
###############################################################################
#Create CentOS 7 SingleDisk Hostgroup
###############################################################################
create_centos_single_hostgroup()
{
create_hostgroup \
"CentOSLinux7-SingleDisk" \
"${CENTOS_SUBNET}" \
"${CENTOS_SINGLE_OS}" \
"${CENTOS_MEDIA}"
}
###############################################################################
#Create Rocky 8 SingleDisk Hostgroup
###############################################################################
create_rocky8_single_hostgroup()
{
create_hostgroup \
"RockyLinux8.10-SingleDisk" \
"${ROCKY_SUBNET}" \
"${ROCKY8_SINGLE_OS}" \
"${ROCKY8_MEDIA}"
}
###############################################################################
#Create Rocky 9 SingleDisk Hostgroups
###############################################################################
create_rocky9_single_hostgroups()
{
for IDX in "${!ROCKY_HOSTGROUPS[@]}"
do
create_hostgroup \
"${ROCKY_HOSTGROUPS[$IDX]}" \
"${ROCKY_SUBNET}" \
"${ROCKY_OS_LIST[$IDX]}" \
"${ROCKY_MEDIA_LIST[$IDX]}"
done
}
###############################################################################
#Create All Single Disk Hostgroups
###############################################################################
create_single_hostgroups()
{
header "Creating Single Disk Hostgroups"
create_centos_single_hostgroup
create_rocky8_single_hostgroup
create_rocky9_single_hostgroups
}
###############################################################################
#Run Creation
###############################################################################
create_single_hostgroups
###############################################################################
#Select Rocky Version
###############################################################################
case "${TARGET_VERSION}" in
9.2)
ROCKY_HOSTGROUPS=(
"RockyLinux9.2-SingleDisk"
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
"RockyLinux9.8-SingleDisk"
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
"RockyLinux9.2-SingleDisk"
"RockyLinux9.8-SingleDisk"
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
error "Unsupported TARGET_VERSION=${TARGET_VERSION}"
exit 1
;;
esac
###############################################################################
#Create Single Disk Hostgroup Function
###############################################################################
create_hostgroup()
{
HOSTGROUP="$1"
SUBNET="$2"
OS_NAME="$3"
MEDIA="$4"
info "Checking Hostgroup : ${HOSTGROUP}"
if $HAMMER hostgroup info \
--name "${HOSTGROUP}" >/dev/null 2>&1
then
skip "${HOSTGROUP} already exists."
else
OS_ID=$(get_os_id "${OS_NAME}")
if [ -z "${OS_ID}" ]
then
error "Operating System not found : ${OS_NAME}"
record_failure "${OS_NAME}"
return 1
fi
info "Creating ${HOSTGROUP}..."
$HAMMER hostgroup create \
--name "${HOSTGROUP}" \
--organization "${ORGANIZATION}" \
--location "${LOCATION}" \
--subnet "${SUBNET}" \
--domain "${DOMAIN}" \
--operatingsystem-id "${OS_ID}" \
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
}
###############################################################################
#Create CentOS 7 SingleDisk Hostgroup
###############################################################################
create_centos_single_hostgroup()
{
create_hostgroup \
"CentOSLinux7-SingleDisk" \
"${CENTOS_SUBNET}" \
"${CENTOS_SINGLE_OS}" \
"${CENTOS_MEDIA}"
}
###############################################################################
#Create Rocky 8 SingleDisk Hostgroup
###############################################################################
create_rocky8_single_hostgroup()
{
create_hostgroup \
"RockyLinux8.10-SingleDisk" \
"${ROCKY_SUBNET}" \
"${ROCKY8_SINGLE_OS}" \
"${ROCKY8_MEDIA}"
}
###############################################################################
#Create Rocky 9 SingleDisk Hostgroups
###############################################################################
create_rocky9_single_hostgroups()
{
for IDX in "${!ROCKY_HOSTGROUPS[@]}"
do
create_hostgroup \
"${ROCKY_HOSTGROUPS[$IDX]}" \
"${ROCKY_SUBNET}" \
"${ROCKY_OS_LIST[$IDX]}" \
"${ROCKY_MEDIA_LIST[$IDX]}"
done
}
###############################################################################
#Create All Single Disk Hostgroups
###############################################################################
create_single_hostgroups()
{
header "Creating Single Disk Hostgroups"
create_centos_single_hostgroup
create_rocky8_single_hostgroup
create_rocky9_single_hostgroups
}
###############################################################################
#Run Creation
###############################################################################
create_single_hostgroups
###############################################################################
#Set Default PXEGrub2 Template Function
###############################################################################
set_default_template()
{
OS_NAME="$1"
TEMPLATE="$2"
info "Setting default PXEGrub2 template : ${OS_NAME}"
OS_ID=$(get_os_id "${OS_NAME}")
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
#Set Default Single Disk PXEGrub2 Templates
###############################################################################
header "Setting Default Single Disk PXEGrub2 Templates"
set_default_template \
"CentOSLinux7-SingleDisk" \
"PXEGrub2 CentOS UEFI SingleDisk Kickstart"
set_default_template \
"RockyLinux8.10-SingleDisk" \
"PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"
set_default_template \
"RockyLinux9.2-SingleDisk" \
"PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"
set_default_template \
"RockyLinux9.8-SingleDisk" \
"PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"
###############################################################################
#Verify Hostgroup
###############################################################################
verify_hostgroup()
{
HOSTGROUP="$1"
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
#Verify Template Mapping
###############################################################################
verify_template_mapping()
{
OS_NAME="$1"
TEMPLATE="$2"
echo
info "${OS_NAME}"
OS_ID=$(get_os_id "${OS_NAME}")
if [ -z "${OS_ID}" ]
then
error "Operating System not found : ${OS_NAME}"
record_failure "${OS_NAME}"
return
fi
if $HAMMER os info \
--id "${OS_ID}" 2>/dev/null |
grep -q "${TEMPLATE}"
then
ok "Template mapping correct."
else
error "Template mapping missing."
record_failure "${OS_NAME} -> ${TEMPLATE}"
fi
}
###############################################################################
#Verification
###############################################################################
header "Single Disk Hostgroup Verification"
verify_hostgroup "CentOSLinux7-SingleDisk"
verify_hostgroup "RockyLinux8.10-SingleDisk"
verify_hostgroup "RockyLinux9.2-SingleDisk"
verify_hostgroup "RockyLinux9.8-SingleDisk"
###############################################################################
#Template Verification
###############################################################################
header "Single Disk Template Mapping Verification"
verify_template_mapping \
"CentOSLinux7-SingleDisk" \
"PXEGrub2 CentOS UEFI SingleDisk Kickstart"
verify_template_mapping \
"RockyLinux8.10-SingleDisk" \
"PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"
verify_template_mapping \
"RockyLinux9.2-SingleDisk" \
"PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"
verify_template_mapping \
"RockyLinux9.8-SingleDisk" \
"PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"
###############################################################################
#Final Verification
###############################################################################
header "Single Disk Hostgroups"
$HAMMER hostgroup list
echo
###############################################################################
#Operating System Verification
###############################################################################
header "Single Disk Operating Systems"
$HAMMER os list |
egrep "CentOSLinux7-SingleDisk|RockyLinux8.10-SingleDisk|RockyLinux9.2-SingleDisk|RockyLinux9.8-SingleDisk"
echo
###############################################################################
#PXE Template Verification
###############################################################################
header "Single Disk PXEGrub2 Templates"
$HAMMER template list |
grep "SingleDisk"
echo
###############################################################################
#Single Disk Configuration Summary
###############################################################################
header "Single Disk Configuration Summary"
cat <<EOF
Hostgroups:

CentOSLinux7-SingleDisk
 |
 +-- OS : CentOSLinux7-SingleDisk
 +-- PXE : PXEGrub2 CentOS UEFI SingleDisk Kickstart
 +-- Media : CentOS 7 Remote


RockyLinux8.10-SingleDisk
 |
 +-- OS : RockyLinux8.10-SingleDisk
 +-- PXE : PXEGrub2 Rocky8 UEFI SingleDisk Kickstart
 +-- Media : Rocky 8 Remote


RockyLinux9.2-SingleDisk
 |
 +-- OS : RockyLinux9.2-SingleDisk
 +-- PXE : PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart
 +-- Media : Rocky 9.2 Remote


RockyLinux9.8-SingleDisk
 |
 +-- OS : RockyLinux9.8-SingleDisk
 +-- PXE : PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart
 +-- Media : Rocky 9 Remote


Disk Layout:

Single Disk
 |
 +-- EFI
 |
 +-- /boot
 |
 +-- LVM
      |
      +-- /
      +-- swap
      +-- /home

EOF

echo

###############################################################################
#Final Status
###############################################################################
header "03 - Foreman Single Disk Hostgroup Bootstrap Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]
then
ok "Single Disk Hostgroup Bootstrap completed successfully."
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

echo "CentOS 7 Single Disk"
echo "------------------------------------------------------------"
echo 'hammer --username admin --password "PASSWORD" hostgroup info --name "CentOSLinux7-SingleDisk"'

echo

echo "Rocky Linux 8.10 Single Disk"
echo "------------------------------------------------------------"
echo 'hammer --username admin --password "PASSWORD" hostgroup info --name "RockyLinux8.10-SingleDisk"'

echo

echo "Rocky Linux 9.2 Single Disk"
echo "------------------------------------------------------------"
echo 'hammer --username admin --password "PASSWORD" hostgroup info --name "RockyLinux9.2-SingleDisk"'

echo

echo "Rocky Linux 9.8 Single Disk"
echo "------------------------------------------------------------"
echo 'hammer --username admin --password "PASSWORD" hostgroup info --name "RockyLinux9.8-SingleDisk"'

echo

echo "PXE Templates"
echo "------------------------------------------------------------"
echo 'hammer --username admin --password "PASSWORD" template list | grep PXEGrub2'

echo

###############################################################################
#Exit
###############################################################################
if [ ${#FAILED_STEPS[@]} -eq 0 ]
then
exit 0
else
exit 1
fi
