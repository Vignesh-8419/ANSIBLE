#!/bin/bash
###############################################################################
#01 - Foreman PXE Bootstrap
###############################################################################
set +e
FAILED_STEPS=()
record_failure(){ FAILED_STEPS+=("$1"); }
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'
info(){ echo -e "${CYAN}$1${NC}"; }
ok(){ echo -e "${GREEN}[OK]${NC} $1"; }
skip(){ echo -e "${YELLOW}[SKIP]${NC} $1"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
error(){ echo -e "${RED}[ERROR]${NC} $1"; }
header(){
echo
echo -e "${BLUE}============================================================${NC}"
echo -e "${WHITE}$1${NC}"
echo -e "${BLUE}============================================================${NC}"
}
header "01 - Foreman PXE Bootstrap"
FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"
HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"
CENTOS_MEDIA="CentOS 7 Remote"
ROCKY8_MEDIA="Rocky 8 Remote"
ROCKY92_MEDIA="Rocky 9.2 Remote"
ROCKY98_MEDIA="Rocky 9 Remote"
CENTOS_RAID_NAME="CentOSLinux7-RAID"
CENTOS_RAID_TITLE="CentOSLinux-RAID"
CENTOS_SINGLE_NAME="CentOSLinux7-SingleDisk"
CENTOS_SINGLE_TITLE="CentOSLinux-SingleDisk"
ROCKY8_RAID_NAME="RockyLinux8.10-RAID"
ROCKY8_RAID_TITLE="RockyLinux-RAID"
ROCKY8_SINGLE_NAME="RockyLinux8.10-SingleDisk"
ROCKY8_SINGLE_TITLE="RockyLinux-SingleDisk"
ROCKY92_RAID_NAME="RockyLinux9.2-RAID"
ROCKY92_RAID_TITLE="RockyLinux-RAID"
ROCKY92_SINGLE_NAME="RockyLinux9.2-SingleDisk"
ROCKY92_SINGLE_TITLE="RockyLinux-SingleDisk"
ROCKY98_RAID_NAME="RockyLinux9.8-RAID"
ROCKY98_RAID_TITLE="RockyLinux-RAID"
ROCKY98_SINGLE_NAME="RockyLinux9.8-SingleDisk"
ROCKY98_SINGLE_TITLE="RockyLinux-SingleDisk"
CENTOS_RAID_TEMPLATE="PXEGrub2 CentOS UEFI RAID Kickstart"
CENTOS_SINGLE_TEMPLATE="PXEGrub2 CentOS UEFI SingleDisk Kickstart"
ROCKY8_RAID_TEMPLATE="PXEGrub2 Rocky8 UEFI RAID Kickstart"
ROCKY8_SINGLE_TEMPLATE="PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"
ROCKY92_RAID_TEMPLATE="PXEGrub2 Rocky9.2 UEFI RAID Kickstart"
ROCKY92_SINGLE_TEMPLATE="PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"
ROCKY98_RAID_TEMPLATE="PXEGrub2 Rocky9.8 UEFI RAID Kickstart"
ROCKY98_SINGLE_TEMPLATE="PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"
create_media()
{
NAME="$1"
URL="$2"
info "Checking Installation Media : ${NAME}"
if $HAMMER medium info --name "${NAME}" >/dev/null 2>&1
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
create_media "CentOS 7 Remote" "http://192.168.253.136/repo/centos/"
create_media "Rocky 8 Remote" "http://192.168.253.136/repo/rocky8/"
create_media "Rocky 9 Remote" "http://192.168.253.136/repo/rocky9/"
create_media "Rocky 9.2 Remote" "http://192.168.253.136/repo/rocky9.2/"
header "Installation Media Verification"
$HAMMER medium list
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
}'
)
if [ -z "${OS_ID}" ]
then
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
else
skip "${OS_NAME} already exists."
fi
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
}'
)
if [ -n "${OS_ID}" ]
then
$HAMMER os update \
--id "${OS_ID}" \
--title "${OS_TITLE}" >/dev/null 2>&1
fi
echo
}
###############################################################################
#Create Operating Systems
###############################################################################
header "Creating Operating Systems"
create_os "${CENTOS_RAID_NAME}" "${CENTOS_RAID_TITLE}" 7 "" "${CENTOS_MEDIA}"
create_os "${CENTOS_SINGLE_NAME}" "${CENTOS_SINGLE_TITLE}" 7 "" "${CENTOS_MEDIA}"
create_os "${ROCKY8_RAID_NAME}" "${ROCKY8_RAID_TITLE}" 8 10 "${ROCKY8_MEDIA}"
create_os "${ROCKY8_SINGLE_NAME}" "${ROCKY8_SINGLE_TITLE}" 8 10 "${ROCKY8_MEDIA}"
create_os "${ROCKY92_RAID_NAME}" "${ROCKY92_RAID_TITLE}" 9 2 "${ROCKY92_MEDIA}"
create_os "${ROCKY92_SINGLE_NAME}" "${ROCKY92_SINGLE_TITLE}" 9 2 "${ROCKY92_MEDIA}"
create_os "${ROCKY98_RAID_NAME}" "${ROCKY98_RAID_TITLE}" 9 8 "${ROCKY98_MEDIA}"
create_os "${ROCKY98_SINGLE_NAME}" "${ROCKY98_SINGLE_TITLE}" 9 8 "${ROCKY98_MEDIA}"
header "Operating System Verification"
$HAMMER os list
###############################################################################
#Attach Provisioning Template
###############################################################################
attach_template()
{
OS_NAME="$1"
TEMPLATE="$2"
info "Assigning Template"
echo "OS       : ${OS_NAME}"
echo "Template : ${TEMPLATE}"
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
}'
)
if [ -z "${OS_ID}" ]
then
error "OS not found : ${OS_NAME}"
record_failure "${OS_NAME}"
return
fi
ok "Found OS ID : ${OS_ID}"
$HAMMER os add-provisioning-template \
--id "${OS_ID}" \
--provisioning-template "${TEMPLATE}"
if [ $? -eq 0 ]
then
ok "Template attached."
else
error "Template attach failed."
record_failure "${OS_NAME}"
fi
###############################################################################
#Set PXEGrub2 Default Template
###############################################################################
TEMPLATE_ID=$(
$HAMMER template list |
awk -F'|' -v name="${TEMPLATE}" '
{
gsub(/^ +| +$/,"",$1)
gsub(/^ +| +$/,"",$2)
if($2==name)
{
print $1
}
}'
)
if [ -n "${TEMPLATE_ID}" ]
then
$HAMMER os set-default-template \
--id "${OS_ID}" \
--provisioning-template-id "${TEMPLATE_ID}"
if [ $? -eq 0 ]
then
ok "PXEGrub2 default template assigned."
else
warn "PXEGrub2 default template assignment failed."
fi
else
error "Template ID not found : ${TEMPLATE}"
record_failure "${TEMPLATE}"
fi
echo
}
###############################################################################
#Template Mapping
###############################################################################
header "Assigning PXEGrub2 Templates"
attach_template "${CENTOS_RAID_NAME}" "${CENTOS_RAID_TEMPLATE}"
attach_template "${CENTOS_SINGLE_NAME}" "${CENTOS_SINGLE_TEMPLATE}"
attach_template "${ROCKY8_RAID_NAME}" "${ROCKY8_RAID_TEMPLATE}"
attach_template "${ROCKY8_SINGLE_NAME}" "${ROCKY8_SINGLE_TEMPLATE}"
attach_template "${ROCKY92_RAID_NAME}" "${ROCKY92_RAID_TEMPLATE}"
attach_template "${ROCKY92_SINGLE_NAME}" "${ROCKY92_SINGLE_TEMPLATE}"
attach_template "${ROCKY98_RAID_NAME}" "${ROCKY98_RAID_TEMPLATE}"
attach_template "${ROCKY98_SINGLE_NAME}" "${ROCKY98_SINGLE_TEMPLATE}"
###############################################################################
#Verify Template Mapping
###############################################################################
header "OS Template Mapping Verification"
verify_template()
{
OS_NAME="$1"
EXPECTED="$2"
echo
echo "------------------------------------------------------------"
echo "OS       : ${OS_NAME}"
echo "Expected : ${EXPECTED}"
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
}'
)
if [ -z "${OS_ID}" ]
then
error "OS not found : ${OS_NAME}"
record_failure "${OS_NAME}"
return
fi
if $HAMMER os info --id "${OS_ID}" | grep -q "${EXPECTED}"
then
ok "Template mapping correct."
else
error "Template mapping missing."
record_failure "${OS_NAME}"
fi
}
verify_template "${CENTOS_RAID_NAME}" "${CENTOS_RAID_TEMPLATE}"
verify_template "${CENTOS_SINGLE_NAME}" "${CENTOS_SINGLE_TEMPLATE}"
verify_template "${ROCKY8_RAID_NAME}" "${ROCKY8_RAID_TEMPLATE}"
verify_template "${ROCKY8_SINGLE_NAME}" "${ROCKY8_SINGLE_TEMPLATE}"
verify_template "${ROCKY92_RAID_NAME}" "${ROCKY92_RAID_TEMPLATE}"
verify_template "${ROCKY92_SINGLE_NAME}" "${ROCKY92_SINGLE_TEMPLATE}"
verify_template "${ROCKY98_RAID_NAME}" "${ROCKY98_RAID_TEMPLATE}"
verify_template "${ROCKY98_SINGLE_NAME}" "${ROCKY98_SINGLE_TEMPLATE}"
###############################################################################
#Create PXE Subnets
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
if $HAMMER subnet info --name "${SUBNET_NAME}" >/dev/null 2>&1
then
skip "${SUBNET_NAME} already exists."
else
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
#Domain Mapping
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
}'
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
#TFTP Proxy Mapping
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
}'
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
#DHCP Proxy Mapping
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
}'
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
#Subnet Creation
###############################################################################
create_subnet \
"vgs-subnet-centos" \
"192.168.253.0" \
"255.255.255.0" \
"192.168.253.2" \
"192.168.253.1" \
"cent-07-01.vgs.com" \
"cent-07-01.vgs.com"
create_subnet \
"vgs-subnet-rockyos" \
"192.168.253.0" \
"255.255.255.0" \
"192.168.253.2" \
"192.168.253.1" \
"cent-07-02.vgs.com" \
"cent-07-02.vgs.com"
###############################################################################
#Final Verification
###############################################################################
header "PXE Bootstrap Verification"
echo
echo "==============================="
echo "Operating Systems"
echo "==============================="
$HAMMER os list
echo
echo "==============================="
echo "PXEGrub2 Templates"
echo "==============================="
$HAMMER template list | grep PXEGrub2
echo
echo "==============================="
echo "PXE Subnets"
echo "==============================="
$HAMMER subnet list
###############################################################################
#Final Default Template Verification
###############################################################################
header "PXEGrub2 Default Template Verification"
check_default_template()
{
OS_NAME="$1"
EXPECTED="$2"
echo
echo "------------------------------------------------------------"
echo "OS       : ${OS_NAME}"
echo "Expected : ${EXPECTED}"
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
}'
)
if [ -z "${OS_ID}" ]
then
error "OS not found : ${OS_NAME}"
record_failure "${OS_NAME}"
return
fi
if $HAMMER os info --id "${OS_ID}" | grep -q "${EXPECTED}"
then
ok "${EXPECTED} mapped."
else
error "${EXPECTED} not mapped."
record_failure "${OS_NAME}"
fi
}
check_default_template "${CENTOS_RAID_NAME}" "${CENTOS_RAID_TEMPLATE}"
check_default_template "${CENTOS_SINGLE_NAME}" "${CENTOS_SINGLE_TEMPLATE}"
check_default_template "${ROCKY8_RAID_NAME}" "${ROCKY8_RAID_TEMPLATE}"
check_default_template "${ROCKY8_SINGLE_NAME}" "${ROCKY8_SINGLE_TEMPLATE}"
check_default_template "${ROCKY92_RAID_NAME}" "${ROCKY92_RAID_TEMPLATE}"
check_default_template "${ROCKY92_SINGLE_NAME}" "${ROCKY92_SINGLE_TEMPLATE}"
check_default_template "${ROCKY98_RAID_NAME}" "${ROCKY98_RAID_TEMPLATE}"
check_default_template "${ROCKY98_SINGLE_NAME}" "${ROCKY98_SINGLE_TEMPLATE}"
###############################################################################
#Completion
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
