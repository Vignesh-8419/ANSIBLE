#!/bin/bash
###############################################################################
# 01 - Foreman PXE Bootstrap - REST API
#
# Purpose:
#   Complete Foreman PXE bootstrap using REST API only.
#
# Creates / verifies:
#   - Installation Media
#   - Operating Systems
#   - PXEGrub2 Provisioning Templates
#   - OS <-> PXEGrub2 template associations
#   - PXEGrub2 default templates
#   - PXE Subnets
#
# Supported OS Objects:
#   CentOSLinux7-RAID
#   CentOSLinux7-SingleDisk
#   RockyLinux8.10-RAID
#   RockyLinux8.10-SingleDisk
#   RockyLinux9.2-RAID
#   RockyLinux9.2-SingleDisk
#   RockyLinux9.8-RAID
#   RockyLinux9.8-SingleDisk
#
# Foreman:
#   REST API
#
# Hammer:
#   NOT USED
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

separator()
{
    echo
    echo "------------------------------------------------------------"
}

###############################################################################
# Foreman Configuration
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
API="${FOREMAN_URL}/api"

FOREMAN_USER="${FOREMAN_USER:-admin}"

###############################################################################
# IMPORTANT:
# Prefer:
#
# export FOREMAN_TOKEN='your-token'
#
# The script also accepts FOREMAN_PASSWORD for compatibility.
###############################################################################

FOREMAN_TOKEN="${FOREMAN_TOKEN:-}"

if [ -z "${FOREMAN_TOKEN}" ]
then
    FOREMAN_TOKEN="${FOREMAN_PASSWORD:-}"
fi

if [ -z "${FOREMAN_TOKEN}" ]
then
    error "FOREMAN_TOKEN is not set."
    echo
    echo "Example:"
    echo "export FOREMAN_TOKEN='YOUR_TOKEN'"
    exit 1
fi

###############################################################################
# curl
###############################################################################

CURL="curl -k -sS"

###############################################################################
# Check Dependencies
###############################################################################

if ! command -v curl >/dev/null 2>&1
then
    error "curl is not installed."
    exit 1
fi

if ! command -v jq >/dev/null 2>&1
then
    error "jq is not installed."
    exit 1
fi

###############################################################################
# REST API Functions
###############################################################################

api_get()
{
    URL="$1"

    ${CURL} \
        --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
        -H 'Accept: application/json,version=2' \
        "${URL}"
}

api_post()
{
    URL="$1"
    DATA="$2"

    ${CURL} \
        --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
        -X POST \
        -H 'Accept: application/json,version=2' \
        -H 'Content-Type: application/json' \
        -d "${DATA}" \
        "${URL}"
}

api_put()
{
    URL="$1"
    DATA="$2"

    ${CURL} \
        --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
        -X PUT \
        -H 'Accept: application/json,version=2' \
        -H 'Content-Type: application/json' \
        -d "${DATA}" \
        "${URL}"
}

api_delete()
{
    URL="$1"

    ${CURL} \
        --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
        -X DELETE \
        -H 'Accept: application/json,version=2' \
        "${URL}"
}

###############################################################################
# Start
###############################################################################

header "01 - Foreman PXE Bootstrap - REST API"

###############################################################################
# Foreman API Authentication Test
###############################################################################

header "Foreman API Authentication Test"

info "Testing Foreman REST API..."

STATUS_RESPONSE="$(
    api_get "${API}/status"
)"

API_STATUS="$(
    echo "${STATUS_RESPONSE}" |
    jq -r '.status // empty'
)"

FOREMAN_VERSION="$(
    echo "${STATUS_RESPONSE}" |
    jq -r '.version // empty'
)"

API_VERSION="$(
    echo "${STATUS_RESPONSE}" |
    jq -r '.api_version // empty'
)"

if [ "${API_STATUS}" = "200" ]
then
    ok "Foreman API authentication successful."
    echo "Foreman Version : ${FOREMAN_VERSION}"
    echo "API Version     : ${API_VERSION}"
    echo "API Status      : ${API_STATUS}"
else
    error "Foreman API authentication failed."
    echo "${STATUS_RESPONSE}"
    exit 1
fi

###############################################################################
# Installation Media Definitions
###############################################################################

MEDIA_CENTOS_NAME="CentOS 7 Remote"
MEDIA_CENTOS_PATH="http://192.168.253.136/repo/centos/"

MEDIA_ROCKY8_NAME="Rocky 8 Remote"
MEDIA_ROCKY8_PATH="http://192.168.253.136/repo/rocky8/"

MEDIA_ROCKY92_NAME="Rocky 9.2 Remote"
MEDIA_ROCKY92_PATH="http://192.168.253.136/repo/rocky9.2/"

MEDIA_ROCKY98_NAME="Rocky 9 Remote"
MEDIA_ROCKY98_PATH="http://192.168.253.136/repo/rocky9/"

###############################################################################
# Find Media ID
###############################################################################

find_media_id()
{
    NAME="$1"

    api_get \
        "${API}/media?search=name%3D%22$(printf '%s' "${NAME}" | sed 's/ /%20/g')%22&per_page=all" |
    jq -r '.results[]?.id' |
    head -1
}

###############################################################################
# Create / Verify Media
###############################################################################

create_media()
{
    NAME="$1"
    PATH_VALUE="$2"

    echo
    info "Checking Installation Media : ${NAME}"

    MEDIA_ID="$(find_media_id "${NAME}")"

    if [ -n "${MEDIA_ID}" ]
    then

        skip "${NAME} already exists. ID=${MEDIA_ID}"

        JSON="$(
            jq -n \
                --arg path "${PATH_VALUE}" \
                '{
                    medium: {
                        path: $path
                    }
                }'
        )"

        RESPONSE="$(
            api_put \
                "${API}/media/${MEDIA_ID}" \
                "${JSON}"
        )"

        UPDATED_PATH="$(
            echo "${RESPONSE}" |
            jq -r '.path // empty'
        )"

        if [ "${UPDATED_PATH}" = "${PATH_VALUE}" ]
        then
            ok "${NAME} path verified."
        else
            error "${NAME} path update failed."
            record_failure "${NAME} media"
        fi

        return 0
    fi

    info "Creating ${NAME}"

    JSON="$(
        jq -n \
            --arg name "${NAME}" \
            --arg path "${PATH_VALUE}" \
            '{
                medium: {
                    name: $name,
                    path: $path
                }
            }'
    )"

    RESPONSE="$(
        api_post \
            "${API}/media" \
            "${JSON}"
    )"

    MEDIA_ID="$(
        echo "${RESPONSE}" |
        jq -r '.id // empty'
    )"

    if [ -n "${MEDIA_ID}" ]
    then
        ok "${NAME} created. ID=${MEDIA_ID}"
    else
        error "Failed creating ${NAME}"
        echo "${RESPONSE}"
        record_failure "${NAME} media"
    fi
}

###############################################################################
# Create Installation Media
###############################################################################

header "Creating Installation Media"

create_media \
    "${MEDIA_CENTOS_NAME}" \
    "${MEDIA_CENTOS_PATH}"

create_media \
    "${MEDIA_ROCKY8_NAME}" \
    "${MEDIA_ROCKY8_PATH}"

create_media \
    "${MEDIA_ROCKY92_NAME}" \
    "${MEDIA_ROCKY92_PATH}"

create_media \
    "${MEDIA_ROCKY98_NAME}" \
    "${MEDIA_ROCKY98_PATH}"

###############################################################################
# Installation Media Verification
###############################################################################

header "Installation Media Verification"

api_get "${API}/media?per_page=all" |
jq -r '
.results[] |
[
    .id,
    .name,
    .path
] |
@tsv
' |
while IFS=$'\t' read -r ID NAME PATH_VALUE
do
    printf "%s | %s | %s\n" \
        "${ID}" \
        "${NAME}" \
        "${PATH_VALUE}"
done

###############################################################################
# Architecture
###############################################################################

find_architecture_id()
{
    ARCH="$1"

    api_get \
        "${API}/architectures?search=name%3D${ARCH}&per_page=all" |
    jq -r '.results[]?.id' |
    head -1
}

X86_64_ID="$(find_architecture_id "x86_64")"

if [ -z "${X86_64_ID}" ]
then
    error "x86_64 architecture not found."
    record_failure "x86_64 architecture"
else
    ok "x86_64 architecture found. ID=${X86_64_ID}"
fi

###############################################################################
# Operating System Definitions
###############################################################################

OS1="CentOSLinux7-RAID"
OS2="CentOSLinux7-SingleDisk"

OS3="RockyLinux8.10-RAID"
OS4="RockyLinux8.10-SingleDisk"

OS5="RockyLinux9.2-RAID"
OS6="RockyLinux9.2-SingleDisk"

OS7="RockyLinux9.8-RAID"
OS8="RockyLinux9.8-SingleDisk"

###############################################################################
# Find Operating System ID
###############################################################################

find_os_id()
{
    OS_NAME="$1"

    api_get \
        "${API}/operatingsystems?search=name%3D%22$(printf '%s' "${OS_NAME}" | sed 's/ /%20/g')%22&per_page=all" |
    jq -r '.results[]?.id' |
    head -1
}

###############################################################################
# Create Operating System
###############################################################################

create_os()
{
    NAME="$1"
    MAJOR="$2"
    MINOR="$3"
    MEDIA_ID="$4"

    echo
    info "Checking OS : ${NAME}"

    OS_ID="$(find_os_id "${NAME}")"

    if [ -n "${OS_ID}" ]
    then
        skip "${NAME} already exists. ID=${OS_ID}"
        return 0
    fi

    info "Creating ${NAME}"

    if [ -z "${MINOR}" ]
    then
        VERSION="${MAJOR}"
    else
        VERSION="${MAJOR}.${MINOR}"
    fi

    JSON="$(
        jq -n \
            --arg name "${NAME}" \
            --arg major "${MAJOR}" \
            --arg minor "${MINOR}" \
            --arg version "${VERSION}" \
            --argjson media_id "${MEDIA_ID}" \
            --argjson architecture_id "${X86_64_ID}" \
            '{
                operatingsystem: {
                    name: $name,
                    major: $major,
                    minor: $minor,
                    family: "Redhat",
                    architectures: [$architecture_id],
                    media_ids: [$media_id]
                }
            }'
    )"

    RESPONSE="$(
        api_post \
            "${API}/operatingsystems" \
            "${JSON}"
    )"

    OS_ID="$(
        echo "${RESPONSE}" |
        jq -r '.id // empty'
    )"

    if [ -n "${OS_ID}" ]
    then
        ok "${NAME} created. ID=${OS_ID}"
    else
        error "Failed creating ${NAME}"
        echo "${RESPONSE}"
        record_failure "${NAME} OS"
    fi
}

###############################################################################
# Get Media IDs
###############################################################################

CENTOS_MEDIA_ID="$(find_media_id "${MEDIA_CENTOS_NAME}")"
ROCKY8_MEDIA_ID="$(find_media_id "${MEDIA_ROCKY8_NAME}")"
ROCKY92_MEDIA_ID="$(find_media_id "${MEDIA_ROCKY92_NAME}")"
ROCKY98_MEDIA_ID="$(find_media_id "${MEDIA_ROCKY98_NAME}")"

###############################################################################
# Create Operating Systems
###############################################################################

header "Creating Operating Systems"

create_os "${OS1}" "7" "" "${CENTOS_MEDIA_ID}"
create_os "${OS2}" "7" "" "${CENTOS_MEDIA_ID}"

create_os "${OS3}" "8" "10" "${ROCKY8_MEDIA_ID}"
create_os "${OS4}" "8" "10" "${ROCKY8_MEDIA_ID}"

create_os "${OS5}" "9" "2" "${ROCKY92_MEDIA_ID}"
create_os "${OS6}" "9" "2" "${ROCKY92_MEDIA_ID}"

create_os "${OS7}" "9" "8" "${ROCKY98_MEDIA_ID}"
create_os "${OS8}" "9" "8" "${ROCKY98_MEDIA_ID}"

###############################################################################
# Operating System Verification
###############################################################################

header "Operating System Verification"

api_get "${API}/operatingsystems?per_page=all" |
jq -r '
.results[] |
[
    .id,
    .name,
    .major,
    .minor,
    .family
] |
@tsv
' |
while IFS=$'\t' read -r ID NAME MAJOR MINOR FAMILY
do
    case "${NAME}" in
        "${OS1}"|"${OS2}"|"${OS3}"|"${OS4}"|"${OS5}"|"${OS6}"|"${OS7}"|"${OS8}")
            printf "%s | %s | %s.%s | %s\n" \
                "${ID}" \
                "${NAME}" \
                "${MAJOR}" \
                "${MINOR}" \
                "${FAMILY}"
            ;;
    esac
done

###############################################################################
# PXEGrub2 Template Definitions
###############################################################################

TEMPLATE1="PXEGrub2 CentOS UEFI RAID Kickstart"
TEMPLATE2="PXEGrub2 CentOS UEFI SingleDisk Kickstart"

TEMPLATE3="PXEGrub2 Rocky8 UEFI RAID Kickstart"
TEMPLATE4="PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

TEMPLATE5="PXEGrub2 Rocky9.2 UEFI RAID Kickstart"
TEMPLATE6="PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

TEMPLATE7="PXEGrub2 Rocky9.8 UEFI RAID Kickstart"
TEMPLATE8="PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

###############################################################################
# Generate PXEGrub2 Template Files
###############################################################################

header "Generating PXEGrub2 Template Files"

###############################################################################
# CentOS RAID
###############################################################################

cat > /tmp/centos-raid.erb <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI RAID Kickstart
kind: PXEGrub2
oses:
- CentOSLinux
%>
set default=0
set timeout=5

menuentry 'Install CentOS 7 RAID' {
    linuxefi /centos/vmlinuz \
        ip=dhcp \
        BOOTIF=01-${net_default_mac} \
        inst.stage2=http://192.168.253.136/repo/centos/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/CentOS7_Golden_RAID_Minimal.cfg \
        inst.text \
        inst.ks.device=bootif \
        hostname=<%= @host.name %>

    initrdefi /centos/initrd.img
}
EOF

###############################################################################
# CentOS Single Disk
###############################################################################

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
        ip=dhcp \
        BOOTIF=01-${net_default_mac} \
        inst.stage2=http://192.168.253.136/repo/centos/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/CentOS7_Golden_SingleDisk_Minimal.cfg \
        inst.text \
        inst.ks.device=bootif \
        hostname=<%= @host.name %>

    initrdefi /centos/initrd.img
}
EOF

###############################################################################
# Rocky 8 RAID
###############################################################################

cat > /tmp/rocky8-raid.erb <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI RAID Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5

menuentry 'Install Rocky Linux 8.10 RAID' {
    linuxefi /rocky8/vmlinuz \
        ip=dhcp \
        BOOTIF=01-${net_default_mac} \
        inst.stage2=http://192.168.253.136/repo/rocky8/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/Rocky8_Golden_RAID_Minimal.cfg \
        inst.text \
        inst.ks.device=bootif \
        hostname=<%= @host.name %>

    initrdefi /rocky8/initrd.img
}
EOF

###############################################################################
# Rocky 8 Single Disk
###############################################################################

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
        ip=dhcp \
        BOOTIF=01-${net_default_mac} \
        inst.stage2=http://192.168.253.136/repo/rocky8/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/Rocky8_Golden_SingleDisk_Minimal.cfg \
        inst.text \
        inst.ks.device=bootif \
        hostname=<%= @host.name %>

    initrdefi /rocky8/initrd.img
}
EOF

###############################################################################
# Rocky 9.2 RAID
###############################################################################

cat > /tmp/rocky92-raid.erb <<'EOF'
<%#
name: PXEGrub2 Rocky9.2 UEFI RAID Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5

menuentry 'Install Rocky Linux 9.2 RAID' {
    linuxefi /rocky92/vmlinuz \
        ip=dhcp \
        BOOTIF=01-${net_default_mac} \
        inst.repo=http://192.168.253.136/repo/rocky9.2/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_2-kickstart/Rocky9_2_Golden_RAID_Minimal.cfg \
        inst.text \
        inst.ks.device=bootif \
        hostname=<%= @host.name %>

    initrdefi /rocky92/initrd.img
}
EOF

###############################################################################
# Rocky 9.2 Single Disk
###############################################################################

cat > /tmp/rocky92-singledisk.erb <<'EOF'
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
        BOOTIF=01-${net_default_mac} \
        inst.repo=http://192.168.253.136/repo/rocky9.2/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_2-kickstart/Rocky9_2_Golden_SingleDisk_Minimal.cfg \
        inst.text \
        inst.ks.device=bootif \
        hostname=<%= @host.name %>

    initrdefi /rocky92/initrd.img
}
EOF

###############################################################################
# Rocky 9.8 RAID
###############################################################################

cat > /tmp/rocky98-raid.erb <<'EOF'
<%#
name: PXEGrub2 Rocky9.8 UEFI RAID Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5

menuentry 'Install Rocky Linux 9.8 RAID' {
    linuxefi /rocky9/vmlinuz \
        ip=dhcp \
        BOOTIF=01-${net_default_mac} \
        inst.repo=http://192.168.253.136/repo/rocky9/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/Rocky9_Golden_RAID_Minimal.cfg \
        inst.text \
        inst.ks.device=bootif \
        hostname=<%= @host.name %>

    initrdefi /rocky9/initrd.img
}
EOF

###############################################################################
# Rocky 9.8 Single Disk
###############################################################################

cat > /tmp/rocky98-singledisk.erb <<'EOF'
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
        BOOTIF=01-${net_default_mac} \
        inst.repo=http://192.168.253.136/repo/rocky9/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/Rocky9_Golden_SingleDisk_Minimal.cfg \
        inst.text \
        inst.ks.device=bootif \
        hostname=<%= @host.name %>

    initrdefi /rocky9/initrd.img
}
EOF

ok "All 8 PXEGrub2 template files generated."

###############################################################################
# Template Kind
###############################################################################

header "Finding PXEGrub2 Template Kind"

TEMPLATE_KIND_ID="$(
    api_get "${API}/provisioning_template_kinds?per_page=all" |
    jq -r '
        .results[] |
        select(
            (.name == "PXEGrub2") or
            (.name == "PXEGrub2 default")
        ) |
        .id
    ' |
    head -1
)"

if [ -z "${TEMPLATE_KIND_ID}" ]
then
    error "PXEGrub2 template kind not found."
    record_failure "PXEGrub2 template kind"
else
    ok "PXEGrub2 template kind found. ID=${TEMPLATE_KIND_ID}"
fi

###############################################################################
# Find Template ID
###############################################################################

find_template_id()
{
    TEMPLATE_NAME="$1"

    api_get \
        "${API}/provisioning_templates?search=name%3D%22$(printf '%s' "${TEMPLATE_NAME}" | sed 's/ /%20/g')%22&per_page=all" |
    jq -r '.results[]?.id' |
    head -1
}

###############################################################################
# Create PXEGrub2 Template
###############################################################################

create_template()
{
    TEMPLATE_NAME="$1"
    TEMPLATE_FILE="$2"

    echo
    info "Checking PXEGrub2 template : ${TEMPLATE_NAME}"

    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -n "${TEMPLATE_ID}" ]
    then
        skip "${TEMPLATE_NAME} already exists. ID=${TEMPLATE_ID}"
        return 0
    fi

    info "Creating ${TEMPLATE_NAME}"

    TEMPLATE_CONTENT="$(cat "${TEMPLATE_FILE}")"

    JSON="$(
        jq -n \
            --arg name "${TEMPLATE_NAME}" \
            --arg kind "PXEGrub2" \
            --arg template "${TEMPLATE_CONTENT}" \
            --argjson template_kind_id "${TEMPLATE_KIND_ID}" \
            '{
                provisioning_template: {
                    name: $name,
                    kind: $kind,
                    template: $template,
                    template_kind_id: $template_kind_id
                }
            }'
    )"

    RESPONSE="$(
        api_post \
            "${API}/provisioning_templates" \
            "${JSON}"
    )"

    TEMPLATE_ID="$(
        echo "${RESPONSE}" |
        jq -r '.id // empty'
    )"

    if [ -n "${TEMPLATE_ID}" ]
    then
        ok "${TEMPLATE_NAME} created. ID=${TEMPLATE_ID}"
    else
        error "Failed creating ${TEMPLATE_NAME}"
        echo "${RESPONSE}"
        record_failure "${TEMPLATE_NAME}"
    fi
}

###############################################################################
# Create All Templates
###############################################################################

header "Creating PXEGrub2 Templates"

create_template \
    "${TEMPLATE1}" \
    "/tmp/centos-raid.erb"

create_template \
    "${TEMPLATE2}" \
    "/tmp/centos-singledisk.erb"

create_template \
    "${TEMPLATE3}" \
    "/tmp/rocky8-raid.erb"

create_template \
    "${TEMPLATE4}" \
    "/tmp/rocky8-singledisk.erb"

create_template \
    "${TEMPLATE5}" \
    "/tmp/rocky92-raid.erb"

create_template \
    "${TEMPLATE6}" \
    "/tmp/rocky92-singledisk.erb"

create_template \
    "${TEMPLATE7}" \
    "/tmp/rocky98-raid.erb"

create_template \
    "${TEMPLATE8}" \
    "/tmp/rocky98-singledisk.erb"

###############################################################################
# Associate Template With OS
###############################################################################

associate_template()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    echo
    info "Associating:"
    echo "  OS       : ${OS_NAME}"
    echo "  Template : ${TEMPLATE_NAME}"

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then
        error "OS not found : ${OS_NAME}"
        record_failure "${OS_NAME} association"
        return
    fi

    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${TEMPLATE_NAME} association"
        return
    fi

    ###########################################################################
    # Check existing association
    ###########################################################################

    OS_RESPONSE="$(
        api_get "${API}/operatingsystems/${OS_ID}"
    )"

    ALREADY_ASSOCIATED="$(
        echo "${OS_RESPONSE}" |
        jq -r \
            --arg name "${TEMPLATE_NAME}" \
            '.provisioning_templates[]? |
             select(.name == $name) |
             .id' |
        head -1
    )"

    if [ -n "${ALREADY_ASSOCIATED}" ]
    then
        skip "Template already associated."
        return 0
    fi

    ###########################################################################
    # Associate
    ###########################################################################

    JSON="$(
        jq -n \
            --argjson provisioning_template_id "${TEMPLATE_ID}" \
            '{
                provisioning_template_id: $provisioning_template_id
            }'
    )"

    RESPONSE="$(
        api_post \
            "${API}/operatingsystems/${OS_ID}/provisioning_templates" \
            "${JSON}"
    )"

    if echo "${RESPONSE}" | jq -e '.error' >/dev/null 2>&1
    then
        error "Failed associating template."
        echo "${RESPONSE}"
        record_failure "${OS_NAME} -> ${TEMPLATE_NAME}"
    else
        ok "Template associated with ${OS_NAME}."
    fi
}

###############################################################################
# Associate All Templates
###############################################################################

header "Associating PXEGrub2 Templates"

associate_template \
    "${OS1}" \
    "${TEMPLATE1}"

associate_template \
    "${OS2}" \
    "${TEMPLATE2}"

associate_template \
    "${OS3}" \
    "${TEMPLATE3}"

associate_template \
    "${OS4}" \
    "${TEMPLATE4}"

associate_template \
    "${OS5}" \
    "${TEMPLATE5}"

associate_template \
    "${OS6}" \
    "${TEMPLATE6}"

associate_template \
    "${OS7}" \
    "${TEMPLATE7}"

associate_template \
    "${OS8}" \
    "${TEMPLATE8}"

###############################################################################
# Set / Update Default PXEGrub2 Template
#
# IMPORTANT:
#
# Foreman already has:
#
#   Kickstart default PXEGrub2
#
# for these OS objects.
#
# Creating another os_default_template with the same template_kind_id
# causes:
#
#   template_kind_id has already been taken
#
# Therefore:
#
#   Existing default -> UPDATE
#   No existing default -> CREATE
###############################################################################

header "Setting PXEGrub2 Default Templates"

set_default_template()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    echo
    info "Setting default template:"
    echo "  OS       : ${OS_NAME}"
    echo "  Template : ${TEMPLATE_NAME}"

    ###########################################################################
    # Find OS
    ###########################################################################

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then
        error "OS not found : ${OS_NAME}"
        record_failure "${OS_NAME} default template"
        return 1
    fi

    ###########################################################################
    # Find Template
    ###########################################################################

    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${TEMPLATE_NAME} default template"
        return 1
    fi

    ###########################################################################
    # Read Template
    ###########################################################################

    TEMPLATE_RESPONSE="$(
        api_get \
            "${API}/provisioning_templates/${TEMPLATE_ID}"
    )"

    TEMPLATE_KIND_ID="$(
        echo "${TEMPLATE_RESPONSE}" |
        jq -r '.template_kind_id // empty'
    )"

    TEMPLATE_KIND_NAME="$(
        echo "${TEMPLATE_RESPONSE}" |
        jq -r '.template_kind_name // .kind // empty'
    )"

    ###########################################################################
    # Fallback to known PXEGrub2 kind
    ###########################################################################

    if [ -z "${TEMPLATE_KIND_ID}" ]
    then
        TEMPLATE_KIND_ID="${TEMPLATE_KIND_ID_GLOBAL}"
    fi

    if [ -z "${TEMPLATE_KIND_ID}" ]
    then
        TEMPLATE_KIND_ID=4
    fi

    if [ -z "${TEMPLATE_KIND_NAME}" ]
    then
        TEMPLATE_KIND_NAME="PXEGrub2"
    fi

    info "OS ID            : ${OS_ID}"
    info "Template ID      : ${TEMPLATE_ID}"
    info "Template Kind    : ${TEMPLATE_KIND_NAME}"
    info "Template Kind ID : ${TEMPLATE_KIND_ID}"

    ###########################################################################
    # Read Existing Default Templates
    ###########################################################################

    DEFAULTS_RESPONSE="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    )"

    if echo "${DEFAULTS_RESPONSE}" | jq -e '.error' >/dev/null 2>&1
    then
        error "Unable to read OS default templates."
        echo "${DEFAULTS_RESPONSE}"
        record_failure "${OS_NAME} default template"
        return 1
    fi

    ###########################################################################
    # Find Existing Default By Template Kind
    ###########################################################################

    EXISTING_DEFAULT_ID="$(
        echo "${DEFAULTS_RESPONSE}" |
        jq -r \
            --argjson kind_id "${TEMPLATE_KIND_ID}" \
            '
            .results[]? |
            select(
                (.template_kind_id // -1) == $kind_id
            ) |
            .id
            ' |
        head -1
    )"

    EXISTING_TEMPLATE_ID="$(
        echo "${DEFAULTS_RESPONSE}" |
        jq -r \
            --argjson kind_id "${TEMPLATE_KIND_ID}" \
            '
            .results[]? |
            select(
                (.template_kind_id // -1) == $kind_id
            ) |
            .provisioning_template_id
            ' |
        head -1
    )"

    EXISTING_TEMPLATE_NAME="$(
        echo "${DEFAULTS_RESPONSE}" |
        jq -r \
            --argjson kind_id "${TEMPLATE_KIND_ID}" \
            '
            .results[]? |
            select(
                (.template_kind_id // -1) == $kind_id
            ) |
            .provisioning_template_name
            ' |
        head -1
    )"

    ###########################################################################
    # Existing Default
    ###########################################################################

    if [ -n "${EXISTING_DEFAULT_ID}" ]
    then

        info "Existing ${TEMPLATE_KIND_NAME} default found."

        echo "  Default ID        : ${EXISTING_DEFAULT_ID}"
        echo "  Existing Template : ${EXISTING_TEMPLATE_NAME}"
        echo "  Existing ID       : ${EXISTING_TEMPLATE_ID}"
        echo "  New Template      : ${TEMPLATE_NAME}"
        echo "  New Template ID   : ${TEMPLATE_ID}"

        #######################################################################
        # Already Correct
        #######################################################################

        if [ "${EXISTING_TEMPLATE_ID}" = "${TEMPLATE_ID}" ]
        then
            skip "Default template already correct."
            return 0
        fi

        #######################################################################
        # Update Existing Default
        #######################################################################

        info "Updating existing ${TEMPLATE_KIND_NAME} default..."

        JSON="$(
            jq -n \
                --argjson provisioning_template_id "${TEMPLATE_ID}" \
                --argjson template_kind_id "${TEMPLATE_KIND_ID}" \
                '{
                    os_default_template: {
                        provisioning_template_id: $provisioning_template_id,
                        template_kind_id: $template_kind_id
                    }
                }'
        )"

        RESPONSE="$(
            api_put \
                "${API}/operatingsystems/${OS_ID}/os_default_templates/${EXISTING_DEFAULT_ID}" \
                "${JSON}"
        )"

        if echo "${RESPONSE}" | jq -e '.error' >/dev/null 2>&1
        then
            error "Failed updating default template."
            echo "${RESPONSE}"
            record_failure "${OS_NAME} default template"
            return 1
        fi

        UPDATED_TEMPLATE="$(
            echo "${RESPONSE}" |
            jq -r '.provisioning_template_name // empty'
        )"

        if [ -z "${UPDATED_TEMPLATE}" ]
        then
            UPDATED_TEMPLATE="${TEMPLATE_NAME}"
        fi

        ok "Default template updated."
        echo "  OS       : ${OS_NAME}"
        echo "  Kind     : ${TEMPLATE_KIND_NAME}"
        echo "  Template : ${UPDATED_TEMPLATE}"
        echo "  ID       : ${EXISTING_DEFAULT_ID}"

        return 0
    fi

    ###########################################################################
    # No Existing Default
    ###########################################################################

    info "No existing ${TEMPLATE_KIND_NAME} default found."
    info "Creating new default template..."

    JSON="$(
        jq -n \
            --argjson provisioning_template_id "${TEMPLATE_ID}" \
            --argjson template_kind_id "${TEMPLATE_KIND_ID}" \
            '{
                os_default_template: {
                    provisioning_template_id: $provisioning_template_id,
                    template_kind_id: $template_kind_id
                }
            }'
    )"

    RESPONSE="$(
        api_post \
            "${API}/operatingsystems/${OS_ID}/os_default_templates" \
            "${JSON}"
    )"

    if echo "${RESPONSE}" | jq -e '.error' >/dev/null 2>&1
    then
        error "Failed creating default template."
        echo "${RESPONSE}"
        record_failure "${OS_NAME} default template"
        return 1
    fi

    DEFAULT_ID="$(
        echo "${RESPONSE}" |
        jq -r '.id // empty'
    )"

    ok "Default template created."
    echo "  OS       : ${OS_NAME}"
    echo "  Kind     : ${TEMPLATE_KIND_NAME}"
    echo "  Template : ${TEMPLATE_NAME}"
    echo "  ID       : ${DEFAULT_ID}"
}

###############################################################################
# Global Template Kind ID
###############################################################################

TEMPLATE_KIND_ID_GLOBAL="${TEMPLATE_KIND_ID}"

###############################################################################
# Set Defaults
###############################################################################

set_default_template "${OS1}" "${TEMPLATE1}"
set_default_template "${OS2}" "${TEMPLATE2}"

set_default_template "${OS3}" "${TEMPLATE3}"
set_default_template "${OS4}" "${TEMPLATE4}"

set_default_template "${OS5}" "${TEMPLATE5}"
set_default_template "${OS6}" "${TEMPLATE6}"

set_default_template "${OS7}" "${TEMPLATE7}"
set_default_template "${OS8}" "${TEMPLATE8}"

###############################################################################
# PXE Subnet Definitions
###############################################################################

SUBNET1_NAME="vgs-subnet-centos"
SUBNET2_NAME="vgs-subnet-rockyos"

SUBNET_NETWORK="192.168.253.0"
SUBNET_MASK="255.255.255.0"
SUBNET_GATEWAY="192.168.253.2"
SUBNET_DNS="192.168.253.1"

SUBNET1_TFTP="cent-07-01.vgs.com"
SUBNET1_DHCP="cent-07-01.vgs.com"

SUBNET2_TFTP="cent-07-02.vgs.com"
SUBNET2_DHCP="cent-07-02.vgs.com"

###############################################################################
# Find Domain
###############################################################################

DOMAIN_ID="$(
    api_get "${API}/domains?search=name%3Dvgs.com&per_page=all" |
    jq -r '.results[]?.id' |
    head -1
)"

if [ -z "${DOMAIN_ID}" ]
then
    error "Domain vgs.com not found."
    record_failure "vgs.com domain"
else
    ok "Domain found : vgs.com ID=${DOMAIN_ID}"
fi

###############################################################################
# Find Smart Proxy
###############################################################################

find_proxy_id()
{
    PROXY_NAME="$1"

    api_get "${API}/smart_proxies?search=name%3D${PROXY_NAME}&per_page=all" |
    jq -r '.results[]?.id' |
    head -1
}

###############################################################################
# Create / Update Subnet
###############################################################################

create_or_update_subnet()
{
    NAME="$1"
    TFTP_PROXY="$2"
    DHCP_PROXY="$3"

    echo
    separator

    echo "Subnet       : ${NAME}"
    echo "Network      : ${SUBNET_NETWORK}"
    echo "Mask         : ${SUBNET_MASK}"
    echo "Gateway      : ${SUBNET_GATEWAY}"
    echo "DNS          : ${SUBNET_DNS}"
    echo "TFTP Proxy   : ${TFTP_PROXY}"
    echo "DHCP Proxy   : ${DHCP_PROXY}"

    separator

    TFTP_ID="$(find_proxy_id "${TFTP_PROXY}")"
    DHCP_ID="$(find_proxy_id "${DHCP_PROXY}")"

    if [ -n "${TFTP_ID}" ]
    then
        ok "TFTP proxy found : ${TFTP_PROXY} ID=${TFTP_ID}"
    else
        error "TFTP proxy not found : ${TFTP_PROXY}"
        record_failure "${NAME} TFTP proxy"
        return
    fi

    if [ -n "${DHCP_ID}" ]
    then
        ok "DHCP proxy found : ${DHCP_PROXY} ID=${DHCP_ID}"
    else
        error "DHCP proxy not found : ${DHCP_PROXY}"
        record_failure "${NAME} DHCP proxy"
        return
    fi

    ###########################################################################
    # Find Subnet
    ###########################################################################

    SUBNET_ID="$(
        api_get \
            "${API}/subnets?search=name%3D%22$(printf '%s' "${NAME}" | sed 's/ /%20/g')%22&per_page=all" |
        jq -r '.results[]?.id' |
        head -1
    )"

    JSON="$(
        jq -n \
            --arg name "${NAME}" \
            --arg network "${SUBNET_NETWORK}" \
            --arg mask "${SUBNET_MASK}" \
            --arg gateway "${SUBNET_GATEWAY}" \
            --arg dns "${SUBNET_DNS}" \
            --argjson domain_id "${DOMAIN_ID}" \
            --argjson tftp_id "${TFTP_ID}" \
            --argjson dhcp_id "${DHCP_ID}" \
            '{
                subnet: {
                    name: $name,
                    network: $network,
                    mask: $mask,
                    gateway: $gateway,
                    dns_primary: $dns,
                    domain_ids: [$domain_id],
                    tftp_id: $tftp_id,
                    dhcp_id: $dhcp_id
                }
            }'
    )"

    ###########################################################################
    # Create
    ###########################################################################

    if [ -z "${SUBNET_ID}" ]
    then

        info "Creating ${NAME}"

        RESPONSE="$(
            api_post \
                "${API}/subnets" \
                "${JSON}"
        )"

        SUBNET_ID="$(
            echo "${RESPONSE}" |
            jq -r '.id // empty'
        )"

        if [ -n "${SUBNET_ID}" ]
        then
            ok "${NAME} created. ID=${SUBNET_ID}"
        else
            error "Failed creating ${NAME}"
            echo "${RESPONSE}"
            record_failure "${NAME} subnet"
        fi

        return
    fi

    ###########################################################################
    # Update
    ###########################################################################

    skip "${NAME} already exists. ID=${SUBNET_ID}"

    RESPONSE="$(
        api_put \
            "${API}/subnets/${SUBNET_ID}" \
            "${JSON}"
    )"

    if echo "${RESPONSE}" | jq -e '.error' >/dev/null 2>&1
    then
        error "${NAME} update failed."
        echo "${RESPONSE}"
        record_failure "${NAME} subnet update"
    else
        ok "${NAME} updated."
    fi
}

###############################################################################
# Create / Update Subnets
###############################################################################

header "Creating PXE Subnets"

create_or_update_subnet \
    "${SUBNET1_NAME}" \
    "${SUBNET1_TFTP}" \
    "${SUBNET1_DHCP}"

create_or_update_subnet \
    "${SUBNET2_NAME}" \
    "${SUBNET2_TFTP}" \
    "${SUBNET2_DHCP}"

###############################################################################
# PXE Subnet Verification
###############################################################################

header "PXE Subnet Verification"

api_get "${API}/subnets?per_page=all" |
jq -r '
.results[] |
[
    .id,
    .name,
    .network,
    .mask,
    (.dhcp_proxy.name // ""),
    (.tftp_proxy.name // "")
] |
@tsv
' |
while IFS=$'\t' read -r ID NAME NETWORK MASK DHCP TFTP
do
    case "${NAME}" in
        "${SUBNET1_NAME}"|"${SUBNET2_NAME}")
            PREFIX="${NETWORK}/24"
            printf "%s | %s | %s | DHCP=%s | TFTP=%s\n" \
                "${ID}" \
                "${NAME}" \
                "${PREFIX}" \
                "${DHCP}" \
                "${TFTP}"
            ;;
    esac
done

###############################################################################
# PXEGrub2 Template Verification
###############################################################################

header "PXEGrub2 Template Verification"

for TEMPLATE_NAME in \
    "${TEMPLATE1}" \
    "${TEMPLATE2}" \
    "${TEMPLATE3}" \
    "${TEMPLATE4}" \
    "${TEMPLATE5}" \
    "${TEMPLATE6}" \
    "${TEMPLATE7}" \
    "${TEMPLATE8}"
do

    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "${TEMPLATE_NAME} not found."
        record_failure "${TEMPLATE_NAME} verification"
        continue
    fi

    TEMPLATE_RESPONSE="$(
        api_get \
            "${API}/provisioning_templates/${TEMPLATE_ID}"
    )"

    TEMPLATE_KIND="$(
        echo "${TEMPLATE_RESPONSE}" |
        jq -r '.kind // empty'
    )"

    TEMPLATE_KIND_CHECK="$(
        echo "${TEMPLATE_RESPONSE}" |
        jq -r '.template_kind_id // empty'
    )"

    if [ "${TEMPLATE_KIND}" = "PXEGrub2" ]
    then
        ok "${TEMPLATE_NAME} | ID=${TEMPLATE_ID} | kind=${TEMPLATE_KIND} | kind_id=${TEMPLATE_KIND_CHECK}"
    else
        error "${TEMPLATE_NAME} has incorrect kind."
        record_failure "${TEMPLATE_NAME} verification"
    fi

done

###############################################################################
# OS Template Mapping Verification
###############################################################################

header "OS Template Mapping Verification"

verify_os_template()
{
    OS_NAME="$1"
    EXPECTED_TEMPLATE="$2"

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then
        error "${OS_NAME} not found."
        record_failure "${OS_NAME} mapping"
        return
    fi

    OS_RESPONSE="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}"
    )"

    MATCH="$(
        echo "${OS_RESPONSE}" |
        jq -r \
            --arg name "${EXPECTED_TEMPLATE}" \
            '.provisioning_templates[]? |
             select(.name == $name) |
             .name' |
        head -1
    )"

    if [ "${MATCH}" = "${EXPECTED_TEMPLATE}" ]
    then
        ok "${OS_NAME} -> ${EXPECTED_TEMPLATE}"
    else
        error "${OS_NAME} -> ${EXPECTED_TEMPLATE} mapping missing."
        record_failure "${OS_NAME} -> ${EXPECTED_TEMPLATE}"
    fi
}

verify_os_template "${OS1}" "${TEMPLATE1}"
verify_os_template "${OS2}" "${TEMPLATE2}"

verify_os_template "${OS3}" "${TEMPLATE3}"
verify_os_template "${OS4}" "${TEMPLATE4}"

verify_os_template "${OS5}" "${TEMPLATE5}"
verify_os_template "${OS6}" "${TEMPLATE6}"

verify_os_template "${OS7}" "${TEMPLATE7}"
verify_os_template "${OS8}" "${TEMPLATE8}"

###############################################################################
# Default Template Verification
###############################################################################

header "PXEGrub2 Default Template Verification"

verify_default_template()
{
    OS_NAME="$1"
    EXPECTED_TEMPLATE="$2"

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then
        error "${OS_NAME} not found."
        record_failure "${OS_NAME} default verification"
        return
    fi

    TEMPLATE_ID="$(find_template_id "${EXPECTED_TEMPLATE}")"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "${EXPECTED_TEMPLATE} not found."
        record_failure "${EXPECTED_TEMPLATE} default verification"
        return
    fi

    TEMPLATE_RESPONSE="$(
        api_get \
            "${API}/provisioning_templates/${TEMPLATE_ID}"
    )"

    KIND_ID="$(
        echo "${TEMPLATE_RESPONSE}" |
        jq -r '.template_kind_id // empty'
    )"

    if [ -z "${KIND_ID}" ]
    then
        KIND_ID="${TEMPLATE_KIND_ID}"
    fi

    DEFAULTS_RESPONSE="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    )"

    ACTUAL_TEMPLATE="$(
        echo "${DEFAULTS_RESPONSE}" |
        jq -r \
            --argjson kind_id "${KIND_ID}" \
            '
            .results[]? |
            select(
                (.template_kind_id // -1) == $kind_id
            ) |
            .provisioning_template_name
            ' |
        head -1
    )"

    if [ "${ACTUAL_TEMPLATE}" = "${EXPECTED_TEMPLATE}" ]
    then
        ok "${OS_NAME} default = ${EXPECTED_TEMPLATE}"
    else
        error "${OS_NAME} default template mismatch."
        echo "  Expected : ${EXPECTED_TEMPLATE}"
        echo "  Actual   : ${ACTUAL_TEMPLATE:-NONE}"
        record_failure "${OS_NAME} default template"
    fi
}

verify_default_template "${OS1}" "${TEMPLATE1}"
verify_default_template "${OS2}" "${TEMPLATE2}"

verify_default_template "${OS3}" "${TEMPLATE3}"
verify_default_template "${OS4}" "${TEMPLATE4}"

verify_default_template "${OS5}" "${TEMPLATE5}"
verify_default_template "${OS6}" "${TEMPLATE6}"

verify_default_template "${OS7}" "${TEMPLATE7}"
verify_default_template "${OS8}" "${TEMPLATE8}"

###############################################################################
# PXEGrub2 Templates List
###############################################################################

header "PXEGrub2 Templates"

api_get "${API}/provisioning_templates?per_page=all" |
jq -r '
.results[] |
select(.kind == "PXEGrub2") |
[
    .id,
    .name,
    .kind
] |
@tsv
' |
while IFS=$'\t' read -r ID NAME KIND
do
    printf "%s | %s | kind=%s\n" \
        "${ID}" \
        "${NAME}" \
        "${KIND}"
done

###############################################################################
# Final Operating System Verification
###############################################################################

header "Final Operating System Verification"

show_os()
{
    OS_NAME="$1"

    OS_ID="$(find_os_id "${OS_NAME}")"

    echo
    echo "------------------------------------------------------------"
    echo "OS : ${OS_NAME}"
    echo "ID : ${OS_ID}"
    echo "------------------------------------------------------------"

    if [ -z "${OS_ID}" ]
    then
        error "OS not found."
        return
    fi

    api_get \
        "${API}/operatingsystems/${OS_ID}" |
    jq -r '
        "Name          : \(.name)",
        "Title         : \(.title)",
        "Major         : \(.major)",
        "Minor         : \(.minor)",
        "Family        : \(.family)",
        "Architecture  : \([.architectures[]?.name] | join(", "))",
        "Media         : \([.media[]?.name] | join(", "))",
        "Ptable        : \([.ptables[]?.name] | join(", "))",
        "Templates     : \([.provisioning_templates[]?.name] | join(", "))"
    '
}

show_os "${OS1}"
show_os "${OS2}"

show_os "${OS3}"
show_os "${OS4}"

show_os "${OS5}"
show_os "${OS6}"

show_os "${OS7}"
show_os "${OS8}"

###############################################################################
# PXE Subnets
###############################################################################

header "PXE Subnets"

api_get "${API}/subnets?per_page=all" |
jq -r '
.results[] |
select(
    .name == "vgs-subnet-centos" or
    .name == "vgs-subnet-rockyos"
) |
[
    .id,
    .name,
    .network,
    .mask,
    (.dhcp_proxy.name // ""),
    (.tftp_proxy.name // "")
] |
@tsv
' |
while IFS=$'\t' read -r ID NAME NETWORK MASK DHCP TFTP
do
    printf "%s | %s | %s/24 | DHCP=%s | TFTP=%s\n" \
        "${ID}" \
        "${NAME}" \
        "${NETWORK}" \
        "${DHCP}" \
        "${TFTP}"
done

###############################################################################
# Generated Template Files
###############################################################################

header "Generated PXE Template Files"

ls -lh \
    /tmp/centos-raid.erb \
    /tmp/centos-singledisk.erb \
    /tmp/rocky8-raid.erb \
    /tmp/rocky8-singledisk.erb \
    /tmp/rocky92-raid.erb \
    /tmp/rocky92-singledisk.erb \
    /tmp/rocky98-raid.erb \
    /tmp/rocky98-singledisk.erb

###############################################################################
# Final Status
###############################################################################

header "01 - Foreman PXE Bootstrap API Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]
then

    ok "Foreman PXE Bootstrap completed successfully."

else

    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

    for STEP in "${FAILED_STEPS[@]}"
    do
        error "${STEP}"
    done

fi

###############################################################################
# Authentication Information
###############################################################################

echo
echo "Authentication:"
echo "------------------------------------------------------------"
echo "Method        : Foreman REST API"
echo "Username      : ${FOREMAN_USER}"
echo "Authentication: Personal Access Token"
echo "Hammer        : NOT USED"
echo "curl          : USED"
echo "API           : ${API}"
echo "------------------------------------------------------------"

###############################################################################
# Manual API Verification
###############################################################################

header "Manual API Verification"

echo
echo "Foreman status:"
echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  ${API}/status"
echo

echo "PXEGrub2 templates:"
echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/provisioning_templates?per_page=all' | jq"
echo

echo "Operating systems:"
echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/operatingsystems?per_page=all' | jq"
echo

echo "Subnets:"
echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/subnets?per_page=all' | jq"
echo

echo "OS default templates:"
echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/operatingsystems/2/os_default_templates?per_page=all' | jq"
echo

###############################################################################
# Expected Configuration
###############################################################################

header "Expected PXE Configuration"

cat <<'EOF'

Operating Systems
=================

CentOSLinux7-RAID
 |
 +-- PXEGrub2 CentOS UEFI RAID Kickstart
 |
 +-- Default PXEGrub2
       |
       +-- PXEGrub2 CentOS UEFI RAID Kickstart


CentOSLinux7-SingleDisk
 |
 +-- PXEGrub2 CentOS UEFI SingleDisk Kickstart
 |
 +-- Default PXEGrub2
       |
       +-- PXEGrub2 CentOS UEFI SingleDisk Kickstart


RockyLinux8.10-RAID
 |
 +-- PXEGrub2 Rocky8 UEFI RAID Kickstart
 |
 +-- Default PXEGrub2
       |
       +-- PXEGrub2 Rocky8 UEFI RAID Kickstart


RockyLinux8.10-SingleDisk
 |
 +-- PXEGrub2 Rocky8 UEFI SingleDisk Kickstart
 |
 +-- Default PXEGrub2
       |
       +-- PXEGrub2 Rocky8 UEFI SingleDisk Kickstart


RockyLinux9.2-RAID
 |
 +-- PXEGrub2 Rocky9.2 UEFI RAID Kickstart
 |
 +-- Default PXEGrub2
       |
       +-- PXEGrub2 Rocky9.2 UEFI RAID Kickstart


RockyLinux9.2-SingleDisk
 |
 +-- PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart
 |
 +-- Default PXEGrub2
       |
       +-- PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart


RockyLinux9.8-RAID
 |
 +-- PXEGrub2 Rocky9.8 UEFI RAID Kickstart
 |
 +-- Default PXEGrub2
       |
       +-- PXEGrub2 Rocky9.8 UEFI RAID Kickstart


RockyLinux9.8-SingleDisk
 |
 +-- PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart
 |
 +-- Default PXEGrub2
       |
       +-- PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart


PXE Subnets
===========

vgs-subnet-centos
 |
 +-- Network : 192.168.253.0/24
 +-- Gateway : 192.168.253.2
 +-- DNS     : 192.168.253.1
 +-- DHCP    : cent-07-01.vgs.com
 +-- TFTP    : cent-07-01.vgs.com


vgs-subnet-rockyos
 |
 +-- Network : 192.168.253.0/24
 +-- Gateway : 192.168.253.2
 +-- DNS     : 192.168.253.1
 +-- DHCP    : cent-07-02.vgs.com
 +-- TFTP    : cent-07-02.vgs.com

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
