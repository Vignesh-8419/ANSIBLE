#!/bin/bash
###############################################################################
# 01 - Foreman PXE Bootstrap - REST API
#
# Purpose:
#   Create and configure:
#     - Installation Media
#     - Operating Systems
#     - PXEGrub2 provisioning templates
#     - OS <-> PXEGrub2 template associations
#     - PXEGrub2 default templates
#     - PXE subnets
#
# Supported Operating Systems:
#
#   CentOSLinux7-RAID
#   CentOSLinux7-SingleDisk
#
#   RockyLinux8.10-RAID
#   RockyLinux8.10-SingleDisk
#
#   RockyLinux9.2-RAID
#   RockyLinux9.2-SingleDisk
#
#   RockyLinux9.8-RAID
#   RockyLinux9.8-SingleDisk
#
# Authentication:
#   Foreman REST API using admin + Personal Access Token
#
# Hammer:
#   NOT USED
#
# API:
#   https://cent-07-01.vgs.com/api
###############################################################################

set +e

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

section()
{
    echo
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
}

###############################################################################
# Failure Tracking
###############################################################################

FAILED_STEPS=()

record_failure()
{
    FAILED_STEPS+=("$1")
}

###############################################################################
# Foreman Configuration
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
API="${FOREMAN_URL}/api"

FOREMAN_USER="${FOREMAN_USER:-admin}"

#
# IMPORTANT:
# Export the token before running:
#
# export FOREMAN_TOKEN='YOUR_TOKEN'
#
# Do not hard-code the token in this script.
#

if [ -z "${FOREMAN_TOKEN}" ]
then
    error "FOREMAN_TOKEN is not set."
    echo
    echo "Run:"
    echo
    echo "export FOREMAN_TOKEN='YOUR_FOREMAN_TOKEN'"
    echo
    exit 1
fi

###############################################################################
# Required Commands
###############################################################################

for CMD in curl jq
do
    if ! command -v "${CMD}" >/dev/null 2>&1
    then
        error "Required command not found: ${CMD}"
        exit 1
    fi
done

###############################################################################
# API Request Helpers
###############################################################################

API_RESPONSE=""
API_HTTP_STATUS=""

api_request()
{
    METHOD="$1"
    URL="$2"
    DATA="$3"

    API_RESPONSE_FILE="$(mktemp)"

    if [ "${METHOD}" = "GET" ]
    then

        API_HTTP_STATUS="$(
            curl -k -sS \
                -o "${API_RESPONSE_FILE}" \
                -w '%{http_code}' \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                -H 'Accept: application/json,version=2' \
                "${URL}"
        )"

    else

        API_HTTP_STATUS="$(
            curl -k -sS \
                -o "${API_RESPONSE_FILE}" \
                -w '%{http_code}' \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                -H 'Accept: application/json,version=2' \
                -H 'Content-Type: application/json' \
                -X "${METHOD}" \
                -d "${DATA}" \
                "${URL}"
        )"

    fi

    API_RESPONSE="$(cat "${API_RESPONSE_FILE}")"

    rm -f "${API_RESPONSE_FILE}"

    return 0
}

api_get()
{
    api_request "GET" "$1" ""
    echo "${API_RESPONSE}"
}

api_post()
{
    api_request "POST" "$1" "$2"

    if [[ "${API_HTTP_STATUS}" =~ ^2[0-9][0-9]$ ]]
    then
        echo "${API_RESPONSE}"
        return 0
    fi

    error "API POST failed."
    error "HTTP Status : ${API_HTTP_STATUS}"
    error "URL         : $1"

    if echo "${API_RESPONSE}" | jq empty >/dev/null 2>&1
    then
        echo "${API_RESPONSE}" | jq .
    else
        echo "${API_RESPONSE}"
    fi

    return 1
}

api_put()
{
    api_request "PUT" "$1" "$2"

    if [[ "${API_HTTP_STATUS}" =~ ^2[0-9][0-9]$ ]]
    then
        echo "${API_RESPONSE}"
        return 0
    fi

    error "API PUT failed."
    error "HTTP Status : ${API_HTTP_STATUS}"
    error "URL         : $1"

    if echo "${API_RESPONSE}" | jq empty >/dev/null 2>&1
    then
        echo "${API_RESPONSE}" | jq .
    else
        echo "${API_RESPONSE}"
    fi

    return 1
}

api_delete()
{
    api_request "DELETE" "$1" ""

    if [[ "${API_HTTP_STATUS}" =~ ^2[0-9][0-9]$ ]]
    then
        echo "${API_RESPONSE}"
        return 0
    fi

    error "API DELETE failed."
    error "HTTP Status : ${API_HTTP_STATUS}"
    error "URL         : $1"

    if echo "${API_RESPONSE}" | jq empty >/dev/null 2>&1
    then
        echo "${API_RESPONSE}" | jq .
    else
        echo "${API_RESPONSE}"
    fi

    return 1
}

###############################################################################
# Foreman API Authentication Test
###############################################################################

header "01 - Foreman PXE Bootstrap - REST API"

header "Foreman API Authentication Test"

info "Testing Foreman REST API..."

STATUS_RESPONSE="$(
    api_get "${API}/status"
)"

if [ "${API_HTTP_STATUS}" != "200" ]
then
    error "Foreman API authentication failed."
    error "HTTP Status : ${API_HTTP_STATUS}"
    echo "${STATUS_RESPONSE}"
    exit 1
fi

FOREMAN_VERSION="$(
    echo "${STATUS_RESPONSE}" |
    jq -r '.version // empty'
)

API_VERSION="$(
    echo "${STATUS_RESPONSE}" |
    jq -r '.api_version // empty'
)

API_STATUS="$(
    echo "${STATUS_RESPONSE}" |
    jq -r '.status // empty'
)"

if [ "${API_STATUS}" = "200" ]
then
    ok "Foreman API authentication successful."
else
    error "Foreman API returned unexpected status."
    echo "${STATUS_RESPONSE}"
    exit 1
fi

echo "Foreman Version : ${FOREMAN_VERSION}"
echo "API Version     : ${API_VERSION}"
echo "API Status      : ${API_STATUS}"

###############################################################################
# Find Architecture
###############################################################################

ARCH_ID="$(
    api_get "${API}/architectures?search=name%3D%22x86_64%22&per_page=all" |
    jq -r '.results[0].id // empty'
)"

if [ -z "${ARCH_ID}" ]
then
    error "x86_64 architecture not found."
    record_failure "x86_64 architecture"
else
    ok "x86_64 architecture found. ID=${ARCH_ID}"
fi

###############################################################################
# Find Kickstart Default Partition Table
###############################################################################

PTABLE_ID="$(
    api_get "${API}/ptables?search=name%3D%22Kickstart%20default%22&per_page=all" |
    jq -r '.results[0].id // empty'
)"

if [ -z "${PTABLE_ID}" ]
then
    error "Kickstart default partition table not found."
    record_failure "Kickstart default partition table"
else
    ok "Kickstart default partition table found. ID=${PTABLE_ID}"
fi

###############################################################################
# Installation Media Configuration
###############################################################################

CENTOS_MEDIA_NAME="CentOS 7 Remote"
CENTOS_MEDIA_PATH="http://192.168.253.136/repo/centos/"

ROCKY8_MEDIA_NAME="Rocky 8 Remote"
ROCKY8_MEDIA_PATH="http://192.168.253.136/repo/rocky8/"

ROCKY92_MEDIA_NAME="Rocky 9.2 Remote"
ROCKY92_MEDIA_PATH="http://192.168.253.136/repo/rocky9.2/"

ROCKY98_MEDIA_NAME="Rocky 9 Remote"
ROCKY98_MEDIA_PATH="http://192.168.253.136/repo/rocky9/"

###############################################################################
# Find Media ID
###############################################################################

find_media_id()
{
    MEDIA_NAME="$1"

    api_get \
        "${API}/media?search=name%3D%22$(printf '%s' "${MEDIA_NAME}" | sed 's/ /%20/g')%22&per_page=all" |
    jq -r --arg NAME "${MEDIA_NAME}" '
        .results[]? |
        select(.name == $NAME) |
        .id
    ' |
    head -1
}

###############################################################################
# Create / Update Installation Media
###############################################################################

create_media()
{
    MEDIA_NAME="$1"
    MEDIA_PATH="$2"

    echo
    echo "Checking Installation Media : ${MEDIA_NAME}"

    MEDIA_ID="$(
        find_media_id "${MEDIA_NAME}"
    )"

    if [ -n "${MEDIA_ID}" ]
    then

        skip "${MEDIA_NAME} already exists. ID=${MEDIA_ID}"

        CURRENT_PATH="$(
            api_get "${API}/media/${MEDIA_ID}" |
            jq -r '.path // empty'
        )"

        if [ "${CURRENT_PATH}" = "${MEDIA_PATH}" ]
        then

            ok "${MEDIA_NAME} path verified."

        else

            warn "${MEDIA_NAME} path differs."
            info "Updating installation media path..."

            JSON="$(
                jq -n \
                    --arg path "${MEDIA_PATH}" \
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

            if [ $? -eq 0 ]
            then
                ok "${MEDIA_NAME} path updated."
            else
                record_failure "${MEDIA_NAME} media path update"
            fi

        fi

        return 0
    fi

    info "Creating ${MEDIA_NAME}"

    JSON="$(
        jq -n \
            --arg name "${MEDIA_NAME}" \
            --arg path "${MEDIA_PATH}" \
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

    if [ $? -eq 0 ]
    then

        MEDIA_ID="$(
            echo "${RESPONSE}" |
            jq -r '.id // empty'
        )"

        ok "${MEDIA_NAME} created. ID=${MEDIA_ID}"

    else

        error "Failed creating ${MEDIA_NAME}."
        record_failure "${MEDIA_NAME} media"

    fi
}

###############################################################################
# Create Installation Media
###############################################################################

header "Creating Installation Media"

create_media \
    "${CENTOS_MEDIA_NAME}" \
    "${CENTOS_MEDIA_PATH}"

create_media \
    "${ROCKY8_MEDIA_NAME}" \
    "${ROCKY8_MEDIA_PATH}"

create_media \
    "${ROCKY92_MEDIA_NAME}" \
    "${ROCKY92_MEDIA_PATH}"

create_media \
    "${ROCKY98_MEDIA_NAME}" \
    "${ROCKY98_MEDIA_PATH}"

###############################################################################
# Installation Media Verification
###############################################################################

header "Installation Media Verification"

api_get "${API}/media?per_page=all" |
jq -r '
    .results[]? |
    [
        .id,
        .name,
        .path
    ] |
    @tsv
' |
while IFS=$'\t' read -r ID NAME PATH
do
    echo "${ID} | ${NAME} | ${PATH}"
done

###############################################################################
# Operating System Configuration
###############################################################################

CENTOS_RAID_OS="CentOSLinux7-RAID"
CENTOS_SINGLE_OS="CentOSLinux7-SingleDisk"

ROCKY8_RAID_OS="RockyLinux8.10-RAID"
ROCKY8_SINGLE_OS="RockyLinux8.10-SingleDisk"

ROCKY92_RAID_OS="RockyLinux9.2-RAID"
ROCKY92_SINGLE_OS="RockyLinux9.2-SingleDisk"

ROCKY98_RAID_OS="RockyLinux9.8-RAID"
ROCKY98_SINGLE_OS="RockyLinux9.8-SingleDisk"

###############################################################################
# Find Operating System ID
###############################################################################

find_os_id()
{
    OS_NAME="$1"

    api_get "${API}/operatingsystems?search=name%3D%22$(printf '%s' "${OS_NAME}" | sed 's/ /%20/g')%22&per_page=all" |
    jq -r --arg NAME "${OS_NAME}" '
        .results[]? |
        select(.name == $NAME) |
        .id
    ' |
    head -1
}

###############################################################################
# Create Operating System
###############################################################################

create_os()
{
    OS_NAME="$1"
    MAJOR="$2"
    MINOR="$3"
    MEDIA_ID="$4"

    echo
    echo "Checking OS : ${OS_NAME}"

    OS_ID="$(
        find_os_id "${OS_NAME}"
    )"

    if [ -n "${OS_ID}" ]
    then
        skip "${OS_NAME} already exists. ID=${OS_ID}"
        return 0
    fi

    info "Creating ${OS_NAME}"

    if [ -z "${ARCH_ID}" ]
    then
        error "Architecture ID unavailable."
        record_failure "${OS_NAME} architecture"
        return 1
    fi

    if [ -z "${PTABLE_ID}" ]
    then
        error "Partition table ID unavailable."
        record_failure "${OS_NAME} partition table"
        return 1
    fi

    if [ -z "${MEDIA_ID}" ]
    then
        MEDIA_ID="$(
            find_media_id "${MEDIA_ID}"
        )"
    fi

    if [ -z "${MEDIA_ID}" ]
    then
        error "Installation media not found for ${OS_NAME}."
        record_failure "${OS_NAME} media"
        return 1
    fi

    JSON="$(
        jq -n \
            --arg name "${OS_NAME}" \
            --arg major "${MAJOR}" \
            --arg minor "${MINOR}" \
            --argjson architecture_id "${ARCH_ID}" \
            --argjson ptable_id "${PTABLE_ID}" \
            --argjson medium_id "${MEDIA_ID}" \
            '{
                operatingsystem: {
                    name: $name,
                    major: $major,
                    minor: $minor,
                    family: "Redhat",
                    architecture_ids: [$architecture_id],
                    ptable_ids: [$ptable_id],
                    medium_ids: [$medium_id]
                }
            }'
    )"

    RESPONSE="$(
        api_post \
            "${API}/operatingsystems" \
            "${JSON}"
    )"

    if [ $? -eq 0 ]
    then

        OS_ID="$(
            echo "${RESPONSE}" |
            jq -r '.id // empty'
        )"

        ok "${OS_NAME} created. ID=${OS_ID}"

    else

        error "Failed creating ${OS_NAME}."
        record_failure "${OS_NAME}"

    fi
}

###############################################################################
# Media IDs
###############################################################################

CENTOS_MEDIA_ID="$(
    find_media_id "${CENTOS_MEDIA_NAME}"
)"

ROCKY8_MEDIA_ID="$(
    find_media_id "${ROCKY8_MEDIA_NAME}"
)"

ROCKY92_MEDIA_ID="$(
    find_media_id "${ROCKY92_MEDIA_NAME}"
)"

ROCKY98_MEDIA_ID="$(
    find_media_id "${ROCKY98_MEDIA_NAME}"
)"

###############################################################################
# Create Operating Systems
###############################################################################

header "Creating Operating Systems"

create_os \
    "${CENTOS_RAID_OS}" \
    "7" \
    "" \
    "${CENTOS_MEDIA_ID}"

create_os \
    "${CENTOS_SINGLE_OS}" \
    "7" \
    "" \
    "${CENTOS_MEDIA_ID}"

create_os \
    "${ROCKY8_RAID_OS}" \
    "8" \
    "10" \
    "${ROCKY8_MEDIA_ID}"

create_os \
    "${ROCKY8_SINGLE_OS}" \
    "8" \
    "10" \
    "${ROCKY8_MEDIA_ID}"

create_os \
    "${ROCKY92_RAID_OS}" \
    "9" \
    "2" \
    "${ROCKY92_MEDIA_ID}"

create_os \
    "${ROCKY92_SINGLE_OS}" \
    "9" \
    "2" \
    "${ROCKY92_MEDIA_ID}"

create_os \
    "${ROCKY98_RAID_OS}" \
    "9" \
    "8" \
    "${ROCKY98_MEDIA_ID}"

create_os \
    "${ROCKY98_SINGLE_OS}" \
    "9" \
    "8" \
    "${ROCKY98_MEDIA_ID}"

###############################################################################
# Operating System Verification
###############################################################################

header "Operating System Verification"

api_get "${API}/operatingsystems?per_page=all" |
jq -r '
    .results[]? |
    select(
        .name == "CentOSLinux7-RAID" or
        .name == "CentOSLinux7-SingleDisk" or
        .name == "RockyLinux8.10-RAID" or
        .name == "RockyLinux8.10-SingleDisk" or
        .name == "RockyLinux9.2-RAID" or
        .name == "RockyLinux9.2-SingleDisk" or
        .name == "RockyLinux9.8-RAID" or
        .name == "RockyLinux9.8-SingleDisk"
    ) |
    "\(.id) | \(.name) | \(.major).\(.minor // "") | \(.family)"
'

###############################################################################
# PXEGrub2 Template Definitions
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
# Generate PXEGrub2 Template Files
###############################################################################

header "Generating PXEGrub2 Template Files"

###############################################################################
# CentOS 7 RAID
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
        inst.stage2=http://192.168.253.136/repo/centos/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/CentOS7_Golden_RAID_Minimal.cfg \
        inst.text \
        inst.ks.device=bootif \
        BOOTIF=01-${net_default_mac} \
        hostname=<%= @host.name %>

    initrdefi /centos/initrd.img
}
EOF

###############################################################################
# CentOS 7 Single Disk
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
        inst.stage2=http://192.168.253.136/repo/centos/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/CentOS7_Golden_SingleDisk_Minimal.cfg \
        inst.text \
        inst.ks.device=bootif \
        BOOTIF=01-${net_default_mac} \
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
        inst.repo=http://192.168.253.136/repo/rocky8/ \
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
        inst.repo=http://192.168.253.136/repo/rocky8/ \
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
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/Rocky9_2_Golden_RAID_Minimal.cfg \
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
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/Rocky9_2_Golden_SingleDisk_Minimal.cfg \
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
# Find PXEGrub2 Template Kind
###############################################################################

header "Finding PXEGrub2 Template Kind"

TEMPLATE_KIND_ID="$(
    api_get "${API}/template_kinds?per_page=all" |
    jq -r '
        .results[]? |
        select(.name == "PXEGrub2") |
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
# Find Provisioning Template ID
###############################################################################

find_template_id()
{
    TEMPLATE_NAME="$1"

    api_get "${API}/provisioning_templates?search=name%3D%22$(printf '%s' "${TEMPLATE_NAME}" | sed 's/ /%20/g')%22&per_page=all" |
    jq -r --arg NAME "${TEMPLATE_NAME}" '
        .results[]? |
        select(.name == $NAME) |
        .id
    ' |
    head -1
}

###############################################################################
# Create PXEGrub2 Template
###############################################################################

create_pxe_template()
{
    TEMPLATE_NAME="$1"
    TEMPLATE_FILE="$2"

    echo
    echo "Checking PXEGrub2 template : ${TEMPLATE_NAME}"

    TEMPLATE_ID="$(
        find_template_id "${TEMPLATE_NAME}"
    )"

    if [ -n "${TEMPLATE_ID}" ]
    then
        skip "${TEMPLATE_NAME} already exists. ID=${TEMPLATE_ID}"
        return 0
    fi

    info "Creating ${TEMPLATE_NAME}"

    TEMPLATE_CONTENT="$(
        cat "${TEMPLATE_FILE}"
    )"

    JSON="$(
        jq -n \
            --arg name "${TEMPLATE_NAME}" \
            --arg kind "${TEMPLATE_KIND_ID}" \
            --arg template "${TEMPLATE_CONTENT}" \
            '{
                provisioning_template: {
                    name: $name,
                    kind: "PXEGrub2",
                    template: $template
                }
            }'
    )"

    RESPONSE="$(
        api_post \
            "${API}/provisioning_templates" \
            "${JSON}"
    )"

    if [ $? -eq 0 ]
    then

        TEMPLATE_ID="$(
            echo "${RESPONSE}" |
            jq -r '.id // empty'
        )"

        ok "${TEMPLATE_NAME} created. ID=${TEMPLATE_ID}"

    else

        error "Failed creating ${TEMPLATE_NAME}."
        record_failure "${TEMPLATE_NAME}"

    fi
}

###############################################################################
# Create All PXEGrub2 Templates
###############################################################################

header "Creating PXEGrub2 Templates"

create_pxe_template \
    "${CENTOS_RAID_TEMPLATE}" \
    "/tmp/centos-raid.erb"

create_pxe_template \
    "${CENTOS_SINGLE_TEMPLATE}" \
    "/tmp/centos-singledisk.erb"

create_pxe_template \
    "${ROCKY8_RAID_TEMPLATE}" \
    "/tmp/rocky8-raid.erb"

create_pxe_template \
    "${ROCKY8_SINGLE_TEMPLATE}" \
    "/tmp/rocky8-singledisk.erb"

create_pxe_template \
    "${ROCKY92_RAID_TEMPLATE}" \
    "/tmp/rocky92-raid.erb"

create_pxe_template \
    "${ROCKY92_SINGLE_TEMPLATE}" \
    "/tmp/rocky92-singledisk.erb"

create_pxe_template \
    "${ROCKY98_RAID_TEMPLATE}" \
    "/tmp/rocky98-raid.erb"

create_pxe_template \
    "${ROCKY98_SINGLE_TEMPLATE}" \
    "/tmp/rocky98-singledisk.erb"

###############################################################################
# Associate Template With Operating System
###############################################################################

associate_template()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    echo
    echo "Associating:"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"

    OS_ID="$(
        find_os_id "${OS_NAME}"
    )"

    if [ -z "${OS_ID}" ]
    then
        error "OS not found : ${OS_NAME}"
        record_failure "${OS_NAME} association"
        return 1
    fi

    TEMPLATE_ID="$(
        find_template_id "${TEMPLATE_NAME}"
    )"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${OS_NAME} -> ${TEMPLATE_NAME}"
        return 1
    fi

    OS_INFO="$(
        api_get "${API}/operatingsystems/${OS_ID}"
    )"

    ALREADY_ASSOCIATED="$(
        echo "${OS_INFO}" |
        jq -r --arg NAME "${TEMPLATE_NAME}" '
            [
                .provisioning_templates[]? |
                select(.name == $NAME)
            ] |
            length
        '
    )"

    if [ "${ALREADY_ASSOCIATED}" -gt 0 ]
    then
        skip "Template already associated."
        return 0
    fi

    JSON="$(
        jq -n \
            --argjson template_id "${TEMPLATE_ID}" \
            '{
                provisioning_template_id: $template_id
            }'
    )"

    RESPONSE="$(
        api_post \
            "${API}/operatingsystems/${OS_ID}/provisioning_templates" \
            "${JSON}"
    )"

    if [ $? -eq 0 ]
    then

        ok "Template associated with ${OS_NAME}."

    else

        #
        # Some Foreman versions expose the association through
        # /os_default_templates rather than this endpoint.
        #
        # Try the standard OS provisioning-template endpoint first.
        #

        error "Failed associating ${TEMPLATE_NAME}."
        record_failure "${OS_NAME} -> ${TEMPLATE_NAME}"

    fi
}

###############################################################################
# Associate All Templates
###############################################################################

header "Associating PXEGrub2 Templates"

associate_template \
    "${CENTOS_RAID_OS}" \
    "${CENTOS_RAID_TEMPLATE}"

associate_template \
    "${CENTOS_SINGLE_OS}" \
    "${CENTOS_SINGLE_TEMPLATE}"

associate_template \
    "${ROCKY8_RAID_OS}" \
    "${ROCKY8_RAID_TEMPLATE}"

associate_template \
    "${ROCKY8_SINGLE_OS}" \
    "${ROCKY8_SINGLE_TEMPLATE}"

associate_template \
    "${ROCKY92_RAID_OS}" \
    "${ROCKY92_RAID_TEMPLATE}"

associate_template \
    "${ROCKY92_SINGLE_OS}" \
    "${ROCKY92_SINGLE_TEMPLATE}"

associate_template \
    "${ROCKY98_RAID_OS}" \
    "${ROCKY98_RAID_TEMPLATE}"

associate_template \
    "${ROCKY98_SINGLE_OS}" \
    "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# Find Existing PXEGrub2 Default
###############################################################################

find_pxegrub2_default_id()
{
    OS_ID="$1"

    RESPONSE="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    )"

    if ! echo "${RESPONSE}" | jq empty >/dev/null 2>&1
    then
        return 1
    fi

    echo "${RESPONSE}" |
    jq -r '
        .results[]? |
        select(
            (.template_kind_name // "") == "PXEGrub2"
        ) |
        .id
    ' |
    head -1
}

###############################################################################
# Set / Update PXEGrub2 Default
###############################################################################

set_pxegrub2_default()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    echo
    echo "------------------------------------------------------------"
    echo "Setting PXEGrub2 Default:"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"
    echo "------------------------------------------------------------"

    ###########################################################################
    # OS ID
    ###########################################################################

    OS_ID="$(
        find_os_id "${OS_NAME}"
    )"

    if [ -z "${OS_ID}" ]
    then
        error "OS not found : ${OS_NAME}"
        record_failure "${OS_NAME} default template"
        return 1
    fi

    ###########################################################################
    # Template ID
    ###########################################################################

    TEMPLATE_ID="$(
        find_template_id "${TEMPLATE_NAME}"
    )"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${OS_NAME} default template"
        return 1
    fi

    ###########################################################################
    # Existing PXEGrub2 Default
    ###########################################################################

    DEFAULT_ID="$(
        find_pxegrub2_default_id "${OS_ID}"
    )"

    ###########################################################################
    # Existing Record
    ###########################################################################

    if [ -n "${DEFAULT_ID}" ]
    then

        ok "Existing PXEGrub2 default found. ID=${DEFAULT_ID}"

        JSON="$(
            jq -n \
                --argjson template_id "${TEMPLATE_ID}" \
                --argjson kind_id "${TEMPLATE_KIND_ID}" \
                '{
                    os_default_template: {
                        provisioning_template_id: $template_id,
                        template_kind_id: $kind_id
                    }
                }'
        )"

        RESPONSE="$(
            api_put \
                "${API}/operatingsystems/${OS_ID}/os_default_templates/${DEFAULT_ID}" \
                "${JSON}"
        )"

        if [ $? -eq 0 ]
        then

            UPDATED_ID="$(
                echo "${RESPONSE}" |
                jq -r '.id // empty'
            )"

            UPDATED_TEMPLATE="$(
                echo "${RESPONSE}" |
                jq -r '.provisioning_template_name // empty'
            )"

            UPDATED_KIND="$(
                echo "${RESPONSE}" |
                jq -r '.template_kind_name // empty'
            )"

            if [ "${UPDATED_TEMPLATE}" = "${TEMPLATE_NAME}" ] &&
               [ "${UPDATED_KIND}" = "PXEGrub2" ]
            then

                ok "PXEGrub2 default updated."
                echo "Default ID : ${UPDATED_ID}"
                echo "Template   : ${UPDATED_TEMPLATE}"
                echo "Kind       : ${UPDATED_KIND}"

            else

                error "PXEGrub2 default update returned unexpected mapping."
                echo "${RESPONSE}" | jq .

                record_failure "${OS_NAME} default template"

            fi

        else

            error "Failed updating PXEGrub2 default."
            record_failure "${OS_NAME} default template"

        fi

        return 0
    fi

    ###########################################################################
    # No Existing Record
    ###########################################################################

    warn "No existing PXEGrub2 default found."
    info "Creating PXEGrub2 default..."

    JSON="$(
        jq -n \
            --argjson template_id "${TEMPLATE_ID}" \
            --argjson kind_id "${TEMPLATE_KIND_ID}" \
            '{
                os_default_template: {
                    provisioning_template_id: $template_id,
                    template_kind_id: $kind_id
                }
            }'
    )"

    RESPONSE="$(
        api_post \
            "${API}/operatingsystems/${OS_ID}/os_default_templates" \
            "${JSON}"
    )"

    if [ $? -eq 0 ]
    then

        DEFAULT_ID="$(
            echo "${RESPONSE}" |
            jq -r '.id // empty'
        )"

        CREATED_TEMPLATE="$(
            echo "${RESPONSE}" |
            jq -r '.provisioning_template_name // empty'
        )"

        CREATED_KIND="$(
            echo "${RESPONSE}" |
            jq -r '.template_kind_name // empty'
        )"

        if [ "${CREATED_TEMPLATE}" = "${TEMPLATE_NAME}" ] &&
           [ "${CREATED_KIND}" = "PXEGrub2" ]
        then

            ok "PXEGrub2 default created."
            echo "Default ID : ${DEFAULT_ID}"
            echo "Template   : ${CREATED_TEMPLATE}"
            echo "Kind       : ${CREATED_KIND}"

        else

            error "Created default returned unexpected mapping."
            echo "${RESPONSE}" | jq .

            record_failure "${OS_NAME} default template"

        fi

    else

        error "Failed creating PXEGrub2 default."
        record_failure "${OS_NAME} default template"

    fi
}

###############################################################################
# Set All PXEGrub2 Defaults
###############################################################################

header "Setting PXEGrub2 Default Templates"

set_pxegrub2_default \
    "${CENTOS_RAID_OS}" \
    "${CENTOS_RAID_TEMPLATE}"

set_pxegrub2_default \
    "${CENTOS_SINGLE_OS}" \
    "${CENTOS_SINGLE_TEMPLATE}"

set_pxegrub2_default \
    "${ROCKY8_RAID_OS}" \
    "${ROCKY8_RAID_TEMPLATE}"

set_pxegrub2_default \
    "${ROCKY8_SINGLE_OS}" \
    "${ROCKY8_SINGLE_TEMPLATE}"

set_pxegrub2_default \
    "${ROCKY92_RAID_OS}" \
    "${ROCKY92_RAID_TEMPLATE}"

set_pxegrub2_default \
    "${ROCKY92_SINGLE_OS}" \
    "${ROCKY92_SINGLE_TEMPLATE}"

set_pxegrub2_default \
    "${ROCKY98_RAID_OS}" \
    "${ROCKY98_RAID_TEMPLATE}"

set_pxegrub2_default \
    "${ROCKY98_SINGLE_OS}" \
    "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# PXE Subnet Configuration
###############################################################################

CENTOS_SUBNET="vgs-subnet-centos"
ROCKY_SUBNET="vgs-subnet-rockyos"

CENTOS_PROXY="cent-07-01.vgs.com"
ROCKY_PROXY="cent-07-02.vgs.com"

NETWORK="192.168.253.0"
MASK="255.255.255.0"
GATEWAY="192.168.253.2"
DNS="192.168.253.1"

###############################################################################
# Find Domain
###############################################################################

DOMAIN_ID="$(
    api_get "${API}/domains?search=name%3D%22vgs.com%22&per_page=all" |
    jq -r '
        .results[]? |
        select(.name == "vgs.com") |
        .id
    ' |
    head -1
)"

if [ -n "${DOMAIN_ID}" ]
then
    ok "Domain found : vgs.com ID=${DOMAIN_ID}"
else
    error "Domain vgs.com not found."
    record_failure "vgs.com domain"
fi

###############################################################################
# Find Proxy ID
###############################################################################

find_proxy_id()
{
    PROXY_NAME="$1"

    api_get "${API}/smart_proxies?search=name%3D%22$(printf '%s' "${PROXY_NAME}" | sed 's/ /%20/g')%22&per_page=all" |
    jq -r --arg NAME "${PROXY_NAME}" '
        .results[]? |
        select(.name == $NAME) |
        .id
    ' |
    head -1
}

###############################################################################
# Create / Update Subnet
###############################################################################

create_subnet()
{
    SUBNET_NAME="$1"
    PROXY_NAME="$2"

    echo
    echo "------------------------------------------------------------"
    echo "Subnet       : ${SUBNET_NAME}"
    echo "Network      : ${NETWORK}"
    echo "Mask         : ${MASK}"
    echo "Gateway      : ${GATEWAY}"
    echo "DNS          : ${DNS}"
    echo "TFTP Proxy   : ${PROXY_NAME}"
    echo "DHCP Proxy   : ${PROXY_NAME}"
    echo "------------------------------------------------------------"

    info "Checking Subnet : ${SUBNET_NAME}"

    PROXY_ID="$(
        find_proxy_id "${PROXY_NAME}"
    )"

    if [ -n "${PROXY_ID}" ]
    then

        ok "TFTP/DHCP proxy found : ${PROXY_NAME} ID=${PROXY_ID}"

    else

        error "Proxy not found : ${PROXY_NAME}"
        record_failure "${SUBNET_NAME} proxy"
        return 1

    fi

    SUBNET_ID="$(
        api_get "${API}/subnets?search=name%3D%22$(printf '%s' "${SUBNET_NAME}" | sed 's/ /%20/g')%22&per_page=all" |
        jq -r --arg NAME "${SUBNET_NAME}" '
            .results[]? |
            select(.name == $NAME) |
            .id
        ' |
        head -1
    )"

    JSON="$(
        jq -n \
            --arg name "${SUBNET_NAME}" \
            --arg network "${NETWORK}" \
            --arg mask "${MASK}" \
            --arg gateway "${GATEWAY}" \
            --arg dns "${DNS}" \
            --argjson domain_id "${DOMAIN_ID}" \
            --argjson tftp_proxy_id "${PROXY_ID}" \
            --argjson dhcp_proxy_id "${PROXY_ID}" \
            '{
                subnet: {
                    name: $name,
                    network: $network,
                    mask: $mask,
                    gateway: $gateway,
                    dns_primary: $dns,
                    domain_ids: [$domain_id],
                    tftp_id: $tftp_proxy_id,
                    dhcp_id: $dhcp_proxy_id
                }
            }'
    )"

    if [ -n "${SUBNET_ID}" ]
    then

        skip "${SUBNET_NAME} already exists. ID=${SUBNET_ID}"

        RESPONSE="$(
            api_put \
                "${API}/subnets/${SUBNET_ID}" \
                "${JSON}"
        )"

        if [ $? -eq 0 ]
        then
            ok "${SUBNET_NAME} updated."
        else
            error "Failed updating ${SUBNET_NAME}."
            record_failure "${SUBNET_NAME}"
        fi

    else

        info "Creating ${SUBNET_NAME}"

        RESPONSE="$(
            api_post \
                "${API}/subnets" \
                "${JSON}"
        )"

        if [ $? -eq 0 ]
        then

            SUBNET_ID="$(
                echo "${RESPONSE}" |
                jq -r '.id // empty'
            )"

            ok "${SUBNET_NAME} created. ID=${SUBNET_ID}"

        else

            error "Failed creating ${SUBNET_NAME}."
            record_failure "${SUBNET_NAME}"

        fi

    fi
}

###############################################################################
# Create PXE Subnets
###############################################################################

header "Creating PXE Subnets"

create_subnet \
    "${CENTOS_SUBNET}" \
    "${CENTOS_PROXY}"

create_subnet \
    "${ROCKY_SUBNET}" \
    "${ROCKY_PROXY}"

###############################################################################
# PXE Subnet Verification
###############################################################################

header "PXE Subnet Verification"

api_get "${API}/subnets?per_page=all" |
jq -r '
    .results[]? |
    select(
        .name == "vgs-subnet-centos" or
        .name == "vgs-subnet-rockyos"
    ) |
    "\(.id) | \(.name) | \(.network)/\(.mask | if . == "255.255.255.0" then "24" else . end) | DHCP=\(.dhcp.name // "-") | TFTP=\(.tftp.name // "-")"
'

###############################################################################
# PXEGrub2 Template Verification
###############################################################################

header "PXEGrub2 Template Verification"

for TEMPLATE_NAME in \
    "${CENTOS_RAID_TEMPLATE}" \
    "${CENTOS_SINGLE_TEMPLATE}" \
    "${ROCKY8_RAID_TEMPLATE}" \
    "${ROCKY8_SINGLE_TEMPLATE}" \
    "${ROCKY92_RAID_TEMPLATE}" \
    "${ROCKY92_SINGLE_TEMPLATE}" \
    "${ROCKY98_RAID_TEMPLATE}" \
    "${ROCKY98_SINGLE_TEMPLATE}"
do

    TEMPLATE_RESPONSE="$(
        api_get "${API}/provisioning_templates?search=name%3D%22$(printf '%s' "${TEMPLATE_NAME}" | sed 's/ /%20/g')%22&per_page=all"
    )"

    TEMPLATE_ID="$(
        echo "${TEMPLATE_RESPONSE}" |
        jq -r --arg NAME "${TEMPLATE_NAME}" '
            .results[]? |
            select(.name == $NAME) |
            .id
        ' |
        head -1
    )"

    TEMPLATE_KIND="$(
        echo "${TEMPLATE_RESPONSE}" |
        jq -r --arg NAME "${TEMPLATE_NAME}" '
            .results[]? |
            select(.name == $NAME) |
            .kind
        ' |
        head -1
    )"

    if [ -n "${TEMPLATE_ID}" ]
    then

        ok "${TEMPLATE_NAME} | ID=${TEMPLATE_ID} | kind=${TEMPLATE_KIND}"

    else

        error "${TEMPLATE_NAME} not found."
        record_failure "${TEMPLATE_NAME} verification"

    fi

done

###############################################################################
# OS Template Mapping Verification
###############################################################################

header "OS Template Mapping Verification"

verify_os_template_mapping()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    OS_ID="$(
        find_os_id "${OS_NAME}"
    )"

    if [ -z "${OS_ID}" ]
    then
        error "${OS_NAME} not found."
        record_failure "${OS_NAME} mapping"
        return 1
    fi

    RESPONSE="$(
        api_get "${API}/operatingsystems/${OS_ID}"
    )"

    MATCH="$(
        echo "${RESPONSE}" |
        jq -r --arg TEMPLATE "${TEMPLATE_NAME}" '
            [
                .provisioning_templates[]? |
                select(.name == $TEMPLATE)
            ] |
            length
        '
    )"

    if [ "${MATCH}" -gt 0 ]
    then

        ok "${OS_NAME} -> ${TEMPLATE_NAME}"

    else

        error "${OS_NAME} -> ${TEMPLATE_NAME} mapping missing."
        record_failure "${OS_NAME} mapping"

    fi
}

verify_os_template_mapping \
    "${CENTOS_RAID_OS}" \
    "${CENTOS_RAID_TEMPLATE}"

verify_os_template_mapping \
    "${CENTOS_SINGLE_OS}" \
    "${CENTOS_SINGLE_TEMPLATE}"

verify_os_template_mapping \
    "${ROCKY8_RAID_OS}" \
    "${ROCKY8_RAID_TEMPLATE}"

verify_os_template_mapping \
    "${ROCKY8_SINGLE_OS}" \
    "${ROCKY8_SINGLE_TEMPLATE}"

verify_os_template_mapping \
    "${ROCKY92_RAID_OS}" \
    "${ROCKY92_RAID_TEMPLATE}"

verify_os_template_mapping \
    "${ROCKY92_SINGLE_OS}" \
    "${ROCKY92_SINGLE_TEMPLATE}"

verify_os_template_mapping \
    "${ROCKY98_RAID_OS}" \
    "${ROCKY98_RAID_TEMPLATE}"

verify_os_template_mapping \
    "${ROCKY98_SINGLE_OS}" \
    "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# PXEGrub2 Default Verification
###############################################################################

header "PXEGrub2 Default Template Verification"

verify_default_template()
{
    OS_NAME="$1"
    EXPECTED_TEMPLATE="$2"

    OS_ID="$(
        find_os_id "${OS_NAME}"
    )"

    if [ -z "${OS_ID}" ]
    then
        error "${OS_NAME} not found."
        record_failure "${OS_NAME} default"
        return 1
    fi

    RESPONSE="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    )"

    if ! echo "${RESPONSE}" | jq empty >/dev/null 2>&1
    then
        error "${OS_NAME}: invalid API response."
        record_failure "${OS_NAME} default"
        return 1
    fi

    MATCH="$(
        echo "${RESPONSE}" |
        jq -r \
            --arg EXPECTED "${EXPECTED_TEMPLATE}" '
                .results[]? |
                select(
                    (.template_kind_name // "") == "PXEGrub2" and
                    (.provisioning_template_name // "") == $EXPECTED
                ) |
                .provisioning_template_name
            ' |
        head -1
    )"

    if [ "${MATCH}" = "${EXPECTED_TEMPLATE}" ]
    then

        DEFAULT_ID="$(
            echo "${RESPONSE}" |
            jq -r \
                --arg EXPECTED "${EXPECTED_TEMPLATE}" '
                    .results[]? |
                    select(
                        (.template_kind_name // "") == "PXEGrub2" and
                        (.provisioning_template_name // "") == $EXPECTED
                    ) |
                    .id
                ' |
            head -1
        )"

        ok "${OS_NAME} default -> ${EXPECTED_TEMPLATE} | ID=${DEFAULT_ID}"

    else

        error "${OS_NAME} default template incorrect."

        echo "${RESPONSE}" |
        jq -r '
            .results[]? |
            "  ID=\(.id // "-") | kind=\(.template_kind_name // "-") | template=\(.provisioning_template_name // "-")"
        '

        record_failure "${OS_NAME} default"

    fi
}

verify_default_template \
    "${CENTOS_RAID_OS}" \
    "${CENTOS_RAID_TEMPLATE}"

verify_default_template \
    "${CENTOS_SINGLE_OS}" \
    "${CENTOS_SINGLE_TEMPLATE}"

verify_default_template \
    "${ROCKY8_RAID_OS}" \
    "${ROCKY8_RAID_TEMPLATE}"

verify_default_template \
    "${ROCKY8_SINGLE_OS}" \
    "${ROCKY8_SINGLE_TEMPLATE}"

verify_default_template \
    "${ROCKY92_RAID_OS}" \
    "${ROCKY92_RAID_TEMPLATE}"

verify_default_template \
    "${ROCKY92_SINGLE_OS}" \
    "${ROCKY92_SINGLE_TEMPLATE}"

verify_default_template \
    "${ROCKY98_RAID_OS}" \
    "${ROCKY98_RAID_TEMPLATE}"

verify_default_template \
    "${ROCKY98_SINGLE_OS}" \
    "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# Final Operating System Verification
###############################################################################

header "Final Operating System Verification"

for OS_NAME in \
    "${CENTOS_RAID_OS}" \
    "${CENTOS_SINGLE_OS}" \
    "${ROCKY8_RAID_OS}" \
    "${ROCKY8_SINGLE_OS}" \
    "${ROCKY92_RAID_OS}" \
    "${ROCKY92_SINGLE_OS}" \
    "${ROCKY98_RAID_OS}" \
    "${ROCKY98_SINGLE_OS}"
do

    OS_ID="$(
        find_os_id "${OS_NAME}"
    )"

    echo
    echo "------------------------------------------------------------"
    echo "OS : ${OS_NAME}"
    echo "ID : ${OS_ID}"
    echo "------------------------------------------------------------"

    api_get "${API}/operatingsystems/${OS_ID}" |
    jq -r '
        "Name          : \(.name)",
        "Title         : \(.title)",
        "Major         : \(.major)",
        "Minor         : \(.minor // "")",
        "Family        : \(.family)",
        "Architecture  : ([.architectures[]?.name] | join(", "))",
        "Media         : ([.media[]?.name] | join(", "))",
        "Ptable        : ([.ptables[]?.name] | join(", "))",
        "Templates     : ([.provisioning_templates[]?.name] | join(", "))"
    '

done

###############################################################################
# PXEGrub2 Template List
###############################################################################

header "PXEGrub2 Templates"

api_get "${API}/provisioning_templates?per_page=all" |
jq -r '
    .results[]? |
    select(.kind == "PXEGrub2") |
    "\(.id) | \(.name) | kind=\(.kind)"
'

###############################################################################
# PXE Subnets
###############################################################################

header "PXE Subnets"

api_get "${API}/subnets?per_page=all" |
jq -r '
    .results[]? |
    select(
        .name == "vgs-subnet-centos" or
        .name == "vgs-subnet-rockyos"
    ) |
    "\(.id) | \(.name) | \(.network)/24 | DHCP=\(.dhcp.name // "-") | TFTP=\(.tftp.name // "-")"
'

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
# Completion
###############################################################################

header "01 - Foreman PXE Bootstrap API Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]
then

    ok "Bootstrap completed successfully."
    echo
    ok "Installation Media       : OK"
    ok "Operating Systems        : OK"
    ok "PXEGrub2 Templates       : OK"
    ok "OS Template Associations : OK"
    ok "PXEGrub2 Defaults        : OK"
    ok "PXE Subnets              : OK"

else

    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

    echo

    for STEP in "${FAILED_STEPS[@]}"
    do
        error "${STEP}"
    done

fi

###############################################################################
# Authentication Information
###############################################################################

header "Authentication"

echo
echo "Method        : Foreman REST API"
echo "Username      : ${FOREMAN_USER}"
echo "Authentication: Personal Access Token"
echo "Hammer        : NOT USED"
echo "curl          : USED"
echo "API           : ${API}"
echo

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

echo "CentOS 7 RAID PXEGrub2 default:"
echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/operatingsystems/2/os_default_templates?per_page=all' | jq"
echo

echo "Rocky 9.8 SingleDisk PXEGrub2 default:"
echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/operatingsystems/9/os_default_templates?per_page=all' | jq"
echo

echo "Subnets:"
echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/subnets?per_page=all' | jq"
echo

###############################################################################
# Exit
###############################################################################

if [ ${#FAILED_STEPS[@]} -eq 0 ]
then
    exit 0
else
    exit 1
fi
