#!/bin/bash
###############################################################################
# 01 - Foreman PXE Bootstrap
#
# Creates:
#   - Installation Media
#   - Operating Systems
#   - RAID PXE Templates
#   - Subnets
#   - Default PXE Templates
#
# NOTE:
#   One Operating System per release.
#   RAID/Single Disk selection is handled by Host Groups.
###############################################################################

set +e

FAILED_STEPS=()

record_failure() {
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

info() {
    echo -e "${CYAN}$1${NC}"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

header() {
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

case "$TARGET_VERSION" in

9.2)

    ROCKY_MEDIA_NAME="Rocky 9.2 Remote"
    ROCKY_MEDIA_PATH="http://192.168.253.136/repo/rocky9.2/"

    ROCKY_OS="RockyLinux 9.2"

    ROCKY_RAID_TEMPLATE="PXEGrub2 Rocky9.2 UEFI Static Kickstart"

    ;;

9.8)

    ROCKY_MEDIA_NAME="Rocky 9 Remote"
    ROCKY_MEDIA_PATH="http://192.168.253.136/repo/rocky9/"

    ROCKY_OS="RockyLinux 9.8"

    ROCKY_RAID_TEMPLATE="PXEGrub2 Rocky9.8 UEFI Static Kickstart"

    ;;

*)

    echo "Unsupported TARGET_VERSION : ${TARGET_VERSION}"
    exit 1

    ;;

esac

CENTOS_OS="CentOSLinux 7"
ROCKY8_OS="RockyLinux 8.10"

###############################################################################
# [1/6] Installation Media
###############################################################################

header "[1/6] Creating Installation Media"

create_media() {

    local NAME="$1"
    local URL="$2"

    info "Checking Installation Media : ${NAME}"

    if $HAMMER medium info --name "${NAME}" >/dev/null 2>&1; then

        skip "${NAME} already exists."

    else

        info "Creating ${NAME}..."

        $HAMMER medium create \
            --name "${NAME}" \
            --path "${URL}" \
            --os-family Redhat

        if [ $? -eq 0 ]; then
            ok "${NAME} created."
        else
            error "Failed to create ${NAME}."
            record_failure "${NAME}"
        fi
    fi

    echo
}

create_media "CentOS 7 Remote" "http://192.168.253.136/repo/centos/"
create_media "Rocky 8 Remote" "http://192.168.253.136/repo/rocky8/"
create_media "${ROCKY_MEDIA_NAME}" "${ROCKY_MEDIA_PATH}"

header "Installation Media"

$HAMMER medium list

echo

###############################################################################
# [2/6] Operating Systems
###############################################################################

header "[2/6] Creating Operating Systems"

create_os() {

    local TITLE="$1"
    local MAJOR="$2"
    local MINOR="$3"
    local MEDIA="$4"

    info "Checking Operating System : ${TITLE}"

    if $HAMMER os info --title "${TITLE}" >/dev/null 2>&1; then

        skip "${TITLE} already exists."

    else

        info "Creating ${TITLE}..."

        if [ -n "${MINOR}" ]; then

            $HAMMER os create \
                --name "$(echo "${TITLE}" | awk '{print $1}')" \
                --major "${MAJOR}" \
                --minor "${MINOR}" \
                --family Redhat \
                --architectures x86_64 \
                --partition-tables "Kickstart default" \
                --media "${MEDIA}"

        else

            $HAMMER os create \
                --name "$(echo "${TITLE}" | awk '{print $1}')" \
                --major "${MAJOR}" \
                --family Redhat \
                --architectures x86_64 \
                --partition-tables "Kickstart default" \
                --media "${MEDIA}"

        fi

        if [ $? -eq 0 ]; then
            ok "${TITLE} created."
        else
            error "Failed to create ${TITLE}."
            record_failure "${TITLE}"
        fi
    fi

    echo
}

create_os "${CENTOS_OS}" 7 "" "CentOS 7 Remote"
create_os "${ROCKY8_OS}" 8 10 "Rocky 8 Remote"
create_os "${ROCKY_OS}" 9 "${TARGET_VERSION#9.}" "${ROCKY_MEDIA_NAME}"

header "Operating Systems"

$HAMMER os list

echo

###############################################################################
# [3/6] Creating RAID PXE Templates
###############################################################################

header "[3/6] Creating RAID PXE Templates"

###############################################################################
# Rocky RAID Template
###############################################################################

case "$TARGET_VERSION" in

9.2)

ROCKY_TEMPLATE_FILE="/tmp/rocky92-pxegrub2.erb"

cat > "${ROCKY_TEMPLATE_FILE}" <<'EOF'
<%#
name: PXEGrub2 Rocky9.2 UEFI Static Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5

menuentry 'Install Rocky Linux 9.2 (RAID1)' {

 linuxefi /rocky92/vmlinuz \
 ip=dhcp \
 BOOTIF=01-${net_default_mac} \
 inst.repo=http://192.168.253.136/repo/rocky9.2/ \
 inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/rocky9.cfg \
 inst.text \
 inst.ks.device=bootif \
 hostname=<%= @host.name %>

 initrdefi /rocky92/initrd.img
}
EOF

;;

9.8)

ROCKY_TEMPLATE_FILE="/tmp/rocky98-pxegrub2.erb"

cat > "${ROCKY_TEMPLATE_FILE}" <<'EOF'
<%#
name: PXEGrub2 Rocky9.8 UEFI Static Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5

menuentry 'Install Rocky Linux 9.8 (RAID1)' {

 linuxefi /rocky9/vmlinuz \
 ip=dhcp \
 BOOTIF=01-${net_default_mac} \
 inst.repo=http://192.168.253.136/repo/rocky9/ \
 inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/rocky9.cfg \
 inst.text \
 inst.ks.device=bootif \
 hostname=<%= @host.name %>

 initrdefi /rocky9/initrd.img
}
EOF

;;

esac

info "Generating ${ROCKY_RAID_TEMPLATE}..."

ok "Selected Rocky RAID template generated."

echo

###############################################################################
# Import Rocky RAID Template
###############################################################################

info "Checking ${ROCKY_RAID_TEMPLATE}..."

if $HAMMER template info \
    --name "${ROCKY_RAID_TEMPLATE}" >/dev/null 2>&1; then

    skip "Template already exists."

else

    info "Importing template..."

    $HAMMER template create \
        --name "${ROCKY_RAID_TEMPLATE}" \
        --type PXEGrub2 \
        --file "${ROCKY_TEMPLATE_FILE}"

    if [ $? -eq 0 ]; then
        ok "Template imported."
    else
        error "Failed to import template."
        record_failure "${ROCKY_RAID_TEMPLATE}"
    fi

fi

echo

###############################################################################
# Assign Rocky RAID Template
###############################################################################

info "Checking template assignment..."

if $HAMMER os info \
    --title "${ROCKY_OS}" | \
    grep -q "${ROCKY_RAID_TEMPLATE}"; then

    skip "Already assigned."

else

    info "Assigning template..."

    $HAMMER os add-provisioning-template \
        --title "${ROCKY_OS}" \
        --provisioning-template "${ROCKY_RAID_TEMPLATE}"

    if [ $? -eq 0 ]; then
        ok "Template assigned."
    else
        error "Template assignment failed."
        record_failure "${ROCKY_RAID_TEMPLATE}"
    fi

fi

echo

###############################################################################
# CentOS 7 RAID Template
###############################################################################

CENTOS_TEMPLATE_FILE="/tmp/centos-pxegrub2.erb"

cat > "${CENTOS_TEMPLATE_FILE}" <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI Static Kickstart
kind: PXEGrub2
oses:
- CentOSLinux
%>

set default=0
set timeout=5

menuentry 'Install CentOS 7 (RAID1)' {

 linuxefi /centos/vmlinuz \
 inst.stage2=http://192.168.253.136/repo/centos/ \
 inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/centos7.cfg \
 inst.text \
 inst.ks.device=bootif \
 BOOTIF=01-${net_default_mac} \
 hostname=<%= @host.name %>

 initrdefi /centos/initrd.img
}
EOF

info "Generating CentOS 7 RAID template..."

ok "CentOS RAID template generated."

echo

###############################################################################
# Rocky Linux 8 RAID Template
###############################################################################

ROCKY8_TEMPLATE_FILE="/tmp/rocky8-pxegrub2.erb"

cat > "${ROCKY8_TEMPLATE_FILE}" <<'EOF'
<%#
name: PXEGrub2 RockyOS UEFI Static Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5

menuentry 'Install Rocky Linux 8.10 (RAID1)' {

 linuxefi /rocky8/vmlinuz \
 inst.stage2=http://192.168.253.136/repo/rocky8/ \
 inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/rocky8.cfg \
 inst.text \
 inst.ks.device=bootif \
 BOOTIF=01-${net_default_mac} \
 hostname=<%= @host.name %>

 initrdefi /rocky8/initrd.img
}
EOF

info "Generating Rocky Linux 8 RAID template..."

ok "Rocky Linux 8 RAID template generated."

echo

###############################################################################
# Import CentOS Template
###############################################################################

info "Checking PXEGrub2 CentOS UEFI Static Kickstart..."

if $HAMMER template info \
    --name "PXEGrub2 CentOS UEFI Static Kickstart" >/dev/null 2>&1; then

    skip "Template already exists."

else

    info "Importing template..."

    $HAMMER template create \
        --name "PXEGrub2 CentOS UEFI Static Kickstart" \
        --type PXEGrub2 \
        --file "${CENTOS_TEMPLATE_FILE}"

    if [ $? -eq 0 ]; then
        ok "Template imported."
    else
        error "Template import failed."
        record_failure "CentOS RAID Template"
    fi

fi

echo

###############################################################################
# Import Rocky 8 Template
###############################################################################

info "Checking PXEGrub2 RockyOS UEFI Static Kickstart..."

if $HAMMER template info \
    --name "PXEGrub2 RockyOS UEFI Static Kickstart" >/dev/null 2>&1; then

    skip "Template already exists."

else

    info "Importing template..."

    $HAMMER template create \
        --name "PXEGrub2 RockyOS UEFI Static Kickstart" \
        --type PXEGrub2 \
        --file "${ROCKY8_TEMPLATE_FILE}"

    if [ $? -eq 0 ]; then
        ok "Template imported."
    else
        error "Template import failed."
        record_failure "Rocky8 RAID Template"
    fi

fi

echo

###############################################################################
# Assign CentOS RAID Template
###############################################################################

info "Checking template assignment for ${CENTOS_OS}..."

if $HAMMER os info \
    --title "${CENTOS_OS}" | \
    grep -q "PXEGrub2 CentOS UEFI Static Kickstart"; then

    skip "Already assigned."

else

    info "Assigning template..."

    $HAMMER os add-provisioning-template \
        --title "${CENTOS_OS}" \
        --provisioning-template "PXEGrub2 CentOS UEFI Static Kickstart"

    if [ $? -eq 0 ]; then
        ok "Template assigned."
    else
        error "Template assignment failed."
        record_failure "${CENTOS_OS}"
    fi

fi

echo

###############################################################################
# Assign Rocky 8 RAID Template
###############################################################################

info "Checking template assignment for ${ROCKY8_OS}..."

if $HAMMER os info \
    --title "${ROCKY8_OS}" | \
    grep -q "PXEGrub2 RockyOS UEFI Static Kickstart"; then

    skip "Already assigned."

else

    info "Assigning template..."

    $HAMMER os add-provisioning-template \
        --title "${ROCKY8_OS}" \
        --provisioning-template "PXEGrub2 RockyOS UEFI Static Kickstart"

    if [ $? -eq 0 ]; then
        ok "Template assigned."
    else
        error "Template assignment failed."
        record_failure "${ROCKY8_OS}"
    fi

fi

echo

header "RAID PXE Templates"

$HAMMER template list | grep -E "Static Kickstart" || true

echo

###############################################################################
# [4/6] Creating Subnets
###############################################################################

header "[4/6] Creating Subnets"

###############################################################################
# Function : Create Subnet
###############################################################################

create_subnet() {

    SUBNET_NAME="$1"
    NETWORK="$2"
    MASK="$3"
    GATEWAY="$4"
    DNS="$5"
    TFTP_PROXY="$6"
    DHCP_PROXY="$7"

    info "Checking Subnet : ${SUBNET_NAME}"

    if $HAMMER subnet info \
        --name "${SUBNET_NAME}" >/dev/null 2>&1; then

        skip "${SUBNET_NAME} already exists."

    else

        info "Creating subnet ${SUBNET_NAME}..."

        $HAMMER subnet create \
            --name "${SUBNET_NAME}" \
            --network "${NETWORK}" \
            --mask "${MASK}" \
            --gateway "${GATEWAY}" \
            --dns-primary "${DNS}" \
            --boot-mode DHCP \
            --ipam DHCP

        if [ $? -eq 0 ]; then
            ok "${SUBNET_NAME} created."
        else
            error "Subnet creation failed."
            record_failure "${SUBNET_NAME}"
        fi

    fi


    ###########################################################################
    # Assign Smart Proxies
    ###########################################################################

    info "Assigning Smart Proxies..."

    $HAMMER subnet update \
        --name "${SUBNET_NAME}" \
        --tftp-id "$(
            $HAMMER smart-proxy list |
            awk -F'|' "/${TFTP_PROXY}/ {gsub(/ /,\"\",\$1);print \$1}"
        )" >/dev/null 2>&1


    $HAMMER subnet update \
        --name "${SUBNET_NAME}" \
        --dhcp-id "$(
            $HAMMER smart-proxy list |
            awk -F'|' "/${DHCP_PROXY}/ {gsub(/ /,\"\",\$1);print \$1}"
        )" >/dev/null 2>&1


    echo
}


###############################################################################
# Create CentOS Subnet
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
# Create Rocky Subnet
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
# Verification
###############################################################################

header "Subnet Verification"

echo

$HAMMER subnet list

echo


###############################################################################
# Detailed Verification
###############################################################################

info "CentOS PXE Subnet"

$HAMMER subnet info \
    --name "vgs-subnet-centos"

echo


info "Rocky PXE Subnet"

$HAMMER subnet info \
    --name "vgs-subnet-rockyos"

echo

###############################################################################
# [5/6] Setting Default PXE Templates
###############################################################################

header "[5/6] Setting Default PXE Templates"


###############################################################################
# Function : Set Default PXE Template
###############################################################################

set_default_template() {

    OS_TITLE="$1"
    TEMPLATE="$2"


    info "Checking ${OS_TITLE}..."


    CURRENT=$(
        $HAMMER os info \
            --title "${OS_TITLE}" 2>/dev/null |
            grep "PXEGrub2" |
            grep "${TEMPLATE}"
    )


    if [ -n "${CURRENT}" ]; then

        skip "Default template already configured."

    else

        info "Setting default template..."

        $HAMMER os set-default-template \
            --title "${OS_TITLE}" \
            --config-template-id "$(
                $HAMMER template list |
                awk -F'|' "/${TEMPLATE}/ {gsub(/ /,\"\",\$1);print \$1}"
            )"


        if [ $? -eq 0 ]; then

            ok "Default template configured."

        else

            error "Failed to configure default template."

            record_failure "${OS_TITLE} -> ${TEMPLATE}"

        fi

    fi

    echo
}


###############################################################################
# Default Templates
#
# IMPORTANT:
#
# Default remains RAID template.
# SingleDisk is selected by Hostgroup.
###############################################################################


set_default_template \
    "CentOSLinux 7" \
    "PXEGrub2 CentOS UEFI Static Kickstart"


set_default_template \
    "RockyLinux 8.10" \
    "PXEGrub2 RockyOS UEFI Static Kickstart"


set_default_template \
    "${ROCKY_OS}" \
    "${ROCKY_RAID_TEMPLATE}"



###############################################################################
# Verify Default Templates
###############################################################################

header "Default PXE Templates"


info "CentOSLinux 7"

$HAMMER os info \
    --title "CentOSLinux 7" |
    awk '/Default templates:/,/Architectures:/'


echo


info "RockyLinux 8.10"

$HAMMER os info \
    --title "RockyLinux 8.10" |
    awk '/Default templates:/,/Architectures:/'


echo


info "${ROCKY_OS}"

$HAMMER os info \
    --title "${ROCKY_OS}" |
    awk '/Default templates:/,/Architectures:/'

echo



###############################################################################
# [6/6] Final Verification
###############################################################################

header "[6/6] PXE Provisioning Configuration Summary"



###############################################################################
# Installation Media
###############################################################################

info "Installation Media"

$HAMMER medium list

echo



###############################################################################
# Operating Systems
###############################################################################

info "Operating Systems"

$HAMMER os list

echo



###############################################################################
# PXE Templates
###############################################################################

info "PXE Templates"

$HAMMER template list |
grep -E "PXEGrub2" || true

echo



###############################################################################
# Subnets
###############################################################################

info "Subnets"

$HAMMER subnet list

echo



###############################################################################
# Selected Configuration
###############################################################################

header "Selected Rocky Configuration"


echo "TARGET_VERSION     : ${TARGET_VERSION}"
echo "Operating System   : ${ROCKY_OS}"
echo "Installation Media : ${ROCKY_MEDIA_NAME}"
echo "RAID PXE Template  : ${ROCKY_RAID_TEMPLATE}"

echo



###############################################################################
# Summary
###############################################################################

header "01 - Foreman PXE Bootstrap Completed"


if [ ${#FAILED_STEPS[@]} -eq 0 ]; then

    ok "Foreman PXE Bootstrap completed successfully."

else

    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."


    for step in "${FAILED_STEPS[@]}"; do

        error "${step}"

    done

fi


echo

ok "Bootstrap finished."

exit 0
