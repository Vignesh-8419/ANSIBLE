#!/bin/bash
###############################################################################
#02 - Foreman PXE Bootstrap (Single Disk)
#
#Purpose:
#Create Single Disk PXE templates
#Attach templates to existing Foreman Operating Systems
#
#Supported OS Objects:
#CentOSLinux7-SingleDisk
#RockyLinux8.10-SingleDisk
#RockyLinux9.2-SingleDisk
#RockyLinux9.8-SingleDisk
#
###############################################################################
set +e
FAILED_STEPS=()
record_failure()
{
FAILED_STEPS+=("$1")
}
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
###############################################################################
#Start
###############################################################################
header "02 - Foreman PXE Bootstrap (Single Disk)"
###############################################################################
#Foreman Credentials
###############################################################################
FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"
HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"
###############################################################################
#Target Version
###############################################################################
TARGET_VERSION="${TARGET_VERSION:-9.8}"
###############################################################################
#Existing Foreman Operating Systems
###############################################################################
CENTOS_SINGLE_OS="CentOSLinux7-SingleDisk"
ROCKY8_SINGLE_OS="RockyLinux8.10-SingleDisk"
ROCKY92_SINGLE_OS="RockyLinux9.2-SingleDisk"
ROCKY98_SINGLE_OS="RockyLinux9.8-SingleDisk"
###############################################################################
#Select Rocky Version
###############################################################################
case "${TARGET_VERSION}" in
9.2)
ROCKY_OS="${ROCKY92_SINGLE_OS}"
ROCKY_TEMPLATE="PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"
ROCKY_TEMPLATE_FILE="/tmp/rocky92-singledisk.erb"
ROCKY_KERNEL="/rocky92/vmlinuz"
ROCKY_INITRD="/rocky92/initrd.img"
ROCKY_REPO="http://192.168.253.136/repo/rocky9.2/"
ROCKY_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/Rocky9_2_Golden_SingleDisk_Minimal.cfg"
;;
9.8)
ROCKY_OS="${ROCKY98_SINGLE_OS}"
ROCKY_TEMPLATE="PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"
ROCKY_TEMPLATE_FILE="/tmp/rocky98-singledisk.erb"
ROCKY_KERNEL="/rocky9/vmlinuz"
ROCKY_INITRD="/rocky9/initrd.img"
ROCKY_REPO="http://192.168.253.136/repo/rocky9/"
ROCKY_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/Rocky9_Golden_SingleDisk_Minimal.cfg"
;;
*)
error "Unsupported TARGET_VERSION=${TARGET_VERSION}"
exit 1
;;
esac
###############################################################################
#[1/4]Create Single Disk PXE Templates
###############################################################################
header "[1/4] Creating Single Disk PXE Templates"
###############################################################################
#CentOS 7 Single Disk Template
###############################################################################
info "Generating CentOS 7 Single Disk template..."
cat > /tmp/centos-singledisk.erb <<'EOF'
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
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/CentOS7_Golden_SingleDisk_Minimal.cfg \
inst.text \
inst.ks.device=bootif \
BOOTIF=01-${net_default_mac} \
hostname=<%= @host.name %>
initrdefi /centos/initrd.img
}
EOF
ok "CentOS Single Disk template generated."
###############################################################################
#Rocky Linux 8 Single Disk Template
###############################################################################
info "Generating Rocky Linux 8 Single Disk template..."
cat > /tmp/rocky8-singledisk.erb <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5
menuentry 'Install Rocky Linux 8.10 Single Disk' {
linuxefi /rocky8/vmlinuz \
inst.stage2=http://192.168.253.136/repo/rocky8/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/Rocky8_Golden_SingleDisk_Minimal.cfg \
inst.text \
inst.ks.device=bootif \
BOOTIF=01-${net_default_mac} \
hostname=<%= @host.name %>
initrdefi /rocky8/initrd.img
}
EOF
ok "Rocky Linux 8 Single Disk template generated."
###############################################################################
#Rocky Linux 9 Single Disk Template
###############################################################################
info "Generating ${ROCKY_TEMPLATE}..."
cat > "${ROCKY_TEMPLATE_FILE}" <<EOF
<%#
name: ${ROCKY_TEMPLATE}
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5
menuentry 'Install ${ROCKY_OS} Single Disk' {
linuxefi ${ROCKY_KERNEL} \
ip=dhcp \
BOOTIF=01-\${net_default_mac} \
inst.repo=${ROCKY_REPO} \
inst.ks=${ROCKY_KS} \
inst.text \
inst.ks.device=bootif \
hostname=<%= @host.name %>
initrdefi ${ROCKY_INITRD}
}
EOF
ok "${ROCKY_TEMPLATE} generated."
###############################################################################
#[1/4]Create Single Disk PXE Templates
###############################################################################
header "[1/4] Creating Single Disk PXE Templates"
###############################################################################
#CentOS 7 Single Disk Template
###############################################################################
info "Generating CentOS 7 Single Disk template..."
cat > /tmp/centos-singledisk.erb <<'EOF'
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
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/CentOS7_Golden_SingleDisk_Minimal.cfg \
inst.text \
inst.ks.device=bootif \
BOOTIF=01-${net_default_mac} \
hostname=<%= @host.name %>
initrdefi /centos/initrd.img
}
EOF
ok "CentOS Single Disk template generated."
###############################################################################
#Rocky Linux 8 Single Disk Template
###############################################################################
info "Generating Rocky Linux 8 Single Disk template..."
cat > /tmp/rocky8-singledisk.erb <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5
menuentry 'Install Rocky Linux 8.10 Single Disk' {
linuxefi /rocky8/vmlinuz \
inst.stage2=http://192.168.253.136/repo/rocky8/ \
inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/Rocky8_Golden_SingleDisk_Minimal.cfg \
inst.text \
inst.ks.device=bootif \
BOOTIF=01-${net_default_mac} \
hostname=<%= @host.name %>
initrdefi /rocky8/initrd.img
}
EOF
ok "Rocky Linux 8 Single Disk template generated."
###############################################################################
#Rocky Linux 9 Single Disk Template
###############################################################################
info "Generating ${ROCKY_TEMPLATE}..."
cat > "${ROCKY_TEMPLATE_FILE}" <<EOF
<%#
name: ${ROCKY_TEMPLATE}
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5
menuentry 'Install ${ROCKY_OS} Single Disk' {
linuxefi ${ROCKY_KERNEL} \
ip=dhcp \
BOOTIF=01-\${net_default_mac} \
inst.repo=${ROCKY_REPO} \
inst.ks=${ROCKY_KS} \
inst.text \
inst.ks.device=bootif \
hostname=<%= @host.name %>
initrdefi ${ROCKY_INITRD}
}
EOF
ok "${ROCKY_TEMPLATE} generated."
###############################################################################
#[3/4]Associate Single Disk Templates
###############################################################################
header "[3/4] Associating Single Disk Templates"
###############################################################################
#CentOS 7 Single Disk
###############################################################################
associate_template \
"CentOSLinux7-SingleDisk" \
"PXEGrub2 CentOS UEFI SingleDisk Kickstart"
###############################################################################
#Rocky Linux 8.10 Single Disk
###############################################################################
associate_template \
"RockyLinux8.10-SingleDisk" \
"PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"
###############################################################################
#Rocky Linux 9.2 / 9.8 Single Disk
###############################################################################
associate_template \
"${ROCKY_OS}" \
"${ROCKY_TEMPLATE}"
###############################################################################
#Set Default PXEGrub2 Template
###############################################################################
set_default_template()
{
OS_NAME="$1"
TEMPLATE_NAME="$2"
info "Setting default PXEGrub2 template : ${OS_NAME}"
OS_ID=$(get_os_id "${OS_NAME}")
if [ -z "${OS_ID}" ]
then
error "Operating System not found : ${OS_NAME}"
record_failure "${OS_NAME}"
return 1
fi
TEMPLATE_ID=$(
$HAMMER template list |
grep -F "${TEMPLATE_NAME}" |
head -1 |
awk -F'|' '
{
gsub(/^ +| +$/,"",$1)
print $1
}'
)
if [ -z "${TEMPLATE_ID}" ]
then
error "Template not found : ${TEMPLATE_NAME}"
record_failure "${TEMPLATE_NAME}"
return 1
fi
$HAMMER os set-default-template \
--id "${OS_ID}" \
--provisioning-template-id "${TEMPLATE_ID}" >/dev/null 2>&1
if [ $? -eq 0 ]
then
ok "Default template assigned."
else
error "Default template assignment failed."
record_failure "${OS_NAME} default template"
fi
echo
}
###############################################################################
#Default Template Mapping
###############################################################################
set_default_template \
"CentOSLinux7-SingleDisk" \
"PXEGrub2 CentOS UEFI SingleDisk Kickstart"
set_default_template \
"RockyLinux8.10-SingleDisk" \
"PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"
set_default_template \
"${ROCKY_OS}" \
"${ROCKY_TEMPLATE}"
###############################################################################
#Verification Function
###############################################################################
verify_os_templates()
{
OS_NAME="$1"
EXPECTED_TEMPLATE="$2"
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
--id "${OS_ID}" |
grep -q "${EXPECTED_TEMPLATE}"
then
ok "${EXPECTED_TEMPLATE} mapping correct."
else
error "${EXPECTED_TEMPLATE} mapping missing."
record_failure "${OS_NAME}"
fi
}
###############################################################################
#[4/4]Single Disk Template Verification
###############################################################################
header "[4/4] Single Disk Template Verification"
verify_os_templates \
"CentOSLinux7-SingleDisk" \
"PXEGrub2 CentOS UEFI SingleDisk Kickstart"
verify_os_templates \
"RockyLinux8.10-SingleDisk" \
"PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"
verify_os_templates \
"${ROCKY_OS}" \
"${ROCKY_TEMPLATE}"
###############################################################################
#PXE Template Verification
###############################################################################
header "Single Disk PXE Templates"
$HAMMER template list | grep "SingleDisk"
echo
###############################################################################
#PXEGrub2 Template Verification
###############################################################################
header "PXEGrub2 Templates"
$HAMMER template list | grep PXEGrub2
echo
###############################################################################
#Operating System Verification
###############################################################################
header "Operating Systems"
$HAMMER os list |
egrep "CentOSLinux7-SingleDisk|RockyLinux8.10-SingleDisk|RockyLinux9.2-SingleDisk|RockyLinux9.8-SingleDisk"
echo
###############################################################################
#Selected Configuration
###############################################################################
header "Selected Single Disk Configuration"
echo
echo "TARGET_VERSION : ${TARGET_VERSION}"
echo "Operating System : ${ROCKY_OS}"
echo "PXE Template : ${ROCKY_TEMPLATE}"
echo "Repository : ${ROCKY_REPO}"
echo "Kickstart : ${ROCKY_KS}"
echo
###############################################################################
#Final Status
###############################################################################
header "02 - Foreman PXE Bootstrap (Single Disk) Completed"
if [ ${#FAILED_STEPS[@]} -eq 0 ]
then
ok "Single Disk PXE Bootstrap completed successfully."
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
echo 'hammer --username admin --password "PASSWORD" os info --title "CentOSLinux7-SingleDisk"'
echo
echo "Rocky Linux 8.10 Single Disk"
echo "------------------------------------------------------------"
echo 'hammer --username admin --password "PASSWORD" os info --title "RockyLinux8.10-SingleDisk"'
echo
echo "Rocky Linux 9.2 Single Disk"
echo "------------------------------------------------------------"
echo 'hammer --username admin --password "PASSWORD" os info --title "RockyLinux9.2-SingleDisk"'
echo
echo "Rocky Linux 9.8 Single Disk"
echo "------------------------------------------------------------"
echo 'hammer --username admin --password "PASSWORD" os info --title "RockyLinux9.8-SingleDisk"'
echo
echo "PXEGrub2 Templates"
echo "------------------------------------------------------------"
echo 'hammer --username admin --password "PASSWORD" template list | grep PXEGrub2'
echo
###############################################################################
#Expected Configuration
###############################################################################
header "Expected Single Disk Configuration"
cat <<EOF
Operating Systems:
CentOSLinux7-SingleDisk
 |
 +-- PXEGrub2 CentOS UEFI SingleDisk Kickstart
RockyLinux8.10-SingleDisk
 |
 +-- PXEGrub2 Rocky8 UEFI SingleDisk Kickstart
RockyLinux9.2-SingleDisk
 |
 +-- PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart
RockyLinux9.8-SingleDisk
 |
 +-- PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart
Hostgroups:
CentOSLinux 7 SingleDisk
RockyLinux 8.10 SingleDisk
RockyLinux 9.2 SingleDisk
RockyLinux 9.8 SingleDisk
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
###############################################################################
#Exit
###############################################################################
if [ ${#FAILED_STEPS[@]} -eq 0 ]
then
exit 0
else
exit 1
fi
