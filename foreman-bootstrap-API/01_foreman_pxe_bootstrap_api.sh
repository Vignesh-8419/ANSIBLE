#!/bin/bash
###############################################################################
# 01 - Foreman PXE Bootstrap - REST API
#
# Purpose:
#   Bootstrap Foreman PXE configuration using REST API.
#
# Creates / verifies:
#   1. Installation Media
#   2. Operating Systems
#   3. PXEGrub2 provisioning templates
#   4. OS <-> PXEGrub2 template associations
#   5. PXEGrub2 default templates
#   6. PXE subnets
#   7. Final verification
#
# Supported OS:
#   CentOS 7
#   Rocky Linux 8.10
#   Rocky Linux 9.2
#   Rocky Linux 9.8
#
# IMPORTANT:
#   This script is intentionally idempotent.
#   It can be executed multiple times.
###############################################################################

set +e

###############################################################################
# COLORS
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
MAGENTA='\033[0;35m'
NC='\033[0m'

###############################################################################
# LOGGING
###############################################################################

info()
{
    echo -e "${CYAN}[INFO]${NC} $1"
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
# FAILURE TRACKING
###############################################################################

FAILED_STEPS=()

record_failure()
{
    FAILED_STEPS+=("$1")
}

###############################################################################
# COMMAND PATHS
###############################################################################

CURL="/usr/bin/curl"
JQ="/usr/bin/jq"
HEAD="/usr/bin/head"
CAT="/usr/bin/cat"
SED="/usr/bin/sed"
AWK="/usr/bin/awk"
GREP="/usr/bin/grep"
MKDIR="/usr/bin/mkdir"
RM="/usr/bin/rm"
CP="/usr/bin/cp"
LS="/usr/bin/ls"
DATE="/usr/bin/date"
TR="/usr/bin/tr"

###############################################################################
# DEPENDENCY CHECK
###############################################################################

header "Dependency Check"

for CMD in "$CURL" "$JQ" "$HEAD" "$CAT" "$SED" "$AWK" "$GREP" "$MKDIR" "$RM" "$CP" "$LS" "$DATE" "$TR"
do
    if [ ! -x "$CMD" ]
    then
        error "Required command not found: ${CMD}"
        exit 1
    fi
done

ok "curl found: ${CURL}"
ok "jq found: ${JQ}"

###############################################################################
# FOREMAN CONFIGURATION
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
FOREMAN_API="${FOREMAN_URL}/api"

FOREMAN_USER="${FOREMAN_USER:-admin}"

#
# PAT supplied for this Foreman installation.
#
# You can override it safely:
#
# export FOREMAN_TOKEN='YOUR_NEW_PAT'
#
FOREMAN_TOKEN="${FOREMAN_TOKEN:-oUzg-aMfjcT3q_wZ8NRLfQ}"

###############################################################################
# TLS
###############################################################################

CURL_TLS="-k"

###############################################################################
# API TEMP DIRECTORY
###############################################################################

WORK_DIR="/tmp/foreman-pxe-bootstrap"

"${MKDIR}" -p "${WORK_DIR}"

API_BODY_FILE="${WORK_DIR}/api-body.json"
API_STATUS_FILE="${WORK_DIR}/api-status"

###############################################################################
# API REQUEST FUNCTION
#
# Usage:
#
#   api_request METHOD URL JSON_DATA
#
# Result:
#
#   API_STATUS
#   API_BODY
#
###############################################################################

api_request()
{
    API_METHOD="$1"
    API_URL="$2"
    API_DATA="$3"

    : > "${API_BODY_FILE}"
    : > "${API_STATUS_FILE}"

    if [ -n "${API_DATA}" ]
    then
        API_STATUS="$(
            "${CURL}" -sS ${CURL_TLS} \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                -X "${API_METHOD}" \
                -H 'Accept: application/json,version=2' \
                -H 'Content-Type: application/json' \
                --data "${API_DATA}" \
                -o "${API_BODY_FILE}" \
                -w '%{http_code}'
        )"
    else
        API_STATUS="$(
            "${CURL}" -sS ${CURL_TLS} \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                -X "${API_METHOD}" \
                -H 'Accept: application/json,version=2' \
                -o "${API_BODY_FILE}" \
                -w '%{http_code}'
        )"
    fi

    API_BODY="$("${CAT}" "${API_BODY_FILE}")"

    echo "${API_STATUS}" > "${API_STATUS_FILE}"
}

###############################################################################
# JSON VALIDATION
###############################################################################

json_valid()
{
    echo "${API_BODY}" | "${JQ}" empty >/dev/null 2>&1
}

###############################################################################
# API ERROR
###############################################################################

show_api_error()
{
    error "API request failed."
    error "HTTP Status : ${API_STATUS}"
    error "Method      : ${API_METHOD}"
    error "URL         : ${API_URL}"

    if json_valid
    then
        echo "${API_BODY}" | "${JQ}" .
    else
        echo "${API_BODY}"
    fi
}

###############################################################################
# API GET
###############################################################################

api_get()
{
    API_METHOD="GET"
    API_URL="$1"

    api_request "GET" "${API_URL}" ""

    if [ "${API_STATUS}" != "200" ]
    then
        show_api_error
        return 1
    fi

    if ! json_valid
    then
        error "Foreman returned invalid JSON."
        echo "${API_BODY}"
        return 1
    fi

    return 0
}

###############################################################################
# API POST
###############################################################################

api_post()
{
    API_METHOD="POST"
    API_URL="$1"
    API_DATA="$2"

    api_request "POST" "${API_URL}" "${API_DATA}"

    if [ "${API_STATUS}" != "200" ] &&
       [ "${API_STATUS}" != "201" ]
    then
        show_api_error
        return 1
    fi

    if ! json_valid
    then
        error "Foreman returned invalid JSON."
        echo "${API_BODY}"
        return 1
    fi

    return 0
}

###############################################################################
# API PUT
###############################################################################

api_put()
{
    API_METHOD="PUT"
    API_URL="$1"
    API_DATA="$2"

    api_request "PUT" "${API_URL}" "${API_DATA}"

    if [ "${API_STATUS}" != "200" ]
    then
        show_api_error
        return 1
    fi

    if ! json_valid
    then
        error "Foreman returned invalid JSON."
        echo "${API_BODY}"
        return 1
    fi

    return 0
}

###############################################################################
# API DELETE
###############################################################################

api_delete()
{
    API_METHOD="DELETE"
    API_URL="$1"

    api_request "DELETE" "${API_URL}" ""

    if [ "${API_STATUS}" != "200" ]
    then
        show_api_error
        return 1
    fi

    return 0
}

###############################################################################
# START
###############################################################################

header "01 - Foreman PXE Bootstrap - REST API"

###############################################################################
# AUTHENTICATION TEST
###############################################################################

header "Foreman API Authentication Test"

info "Testing Foreman REST API..."

api_get "${FOREMAN_API}/status"

if [ $? -ne 0 ]
then
    error "Foreman API authentication failed."
    exit 1
fi

FOREMAN_VERSION="$(echo "${API_BODY}" | "${JQ}" -r '.version // empty')"
API_VERSION="$(echo "${API_BODY}" | "${JQ}" -r '.api_version // empty')"
API_STATUS="$(echo "${API_BODY}" | "${JQ}" -r '.status // empty')"

ok "Foreman API authentication successful."

echo "Foreman Version : ${FOREMAN_VERSION}"
echo "API Version     : ${API_VERSION}"
echo "API Status      : ${API_STATUS}"

###############################################################################
# ARCHITECTURE
###############################################################################

api_get "${FOREMAN_API}/architectures?search=name%3D%22x86_64%22"

ARCH_ID="$(
    echo "${API_BODY}" |
    "${JQ}" -r '.results[0].id // empty'
)"

if [ -z "${ARCH_ID}" ]
then
    error "x86_64 architecture not found."
    record_failure "x86_64 architecture"
else
    ok "x86_64 architecture found. ID=${ARCH_ID}"
fi

###############################################################################
# PARTITION TABLE
###############################################################################

api_get "${FOREMAN_API}/ptables?search=name%3D%22Kickstart%20default%22"

PTABLE_ID="$(
    echo "${API_BODY}" |
    "${JQ}" -r '.results[0].id // empty'
)"

if [ -z "${PTABLE_ID}" ]
then
    error "Kickstart default partition table not found."
    record_failure "Kickstart default partition table"
else
    ok "Kickstart default partition table found. ID=${PTABLE_ID}"
fi

###############################################################################
# INSTALLATION MEDIA
###############################################################################

header "Creating Installation Media"

create_media()
{
    MEDIA_NAME="$1"
    MEDIA_PATH="$2"

    section "Installation Media : ${MEDIA_NAME}"

    api_get "${FOREMAN_API}/media?search=name%3D%22${MEDIA_NAME// /%20}%22"

    MEDIA_ID="$(
        echo "${API_BODY}" |
        "${JQ}" -r '.results[0].id // empty'
    )"

    if [ -n "${MEDIA_ID}" ]
    then
        skip "${MEDIA_NAME} already exists. ID=${MEDIA_ID}"

        EXISTING_PATH="$(
            echo "${API_BODY}" |
            "${JQ}" -r '.results[0].path // empty'
        )"

        if [ "${EXISTING_PATH}" = "${MEDIA_PATH}" ]
        then
            ok "${MEDIA_NAME} path verified."
        else
            warn "${MEDIA_NAME} path differs."
            info "Updating media path..."

            PAYLOAD="$(
                "${JQ}" -n \
                    --arg path "${MEDIA_PATH}" \
                    '{
                        medium: {
                            path: $path
                        }
                    }'
            )"

            api_put "${FOREMAN_API}/media/${MEDIA_ID}" "${PAYLOAD}"

            if [ $? -eq 0 ]
            then
                ok "${MEDIA_NAME} path updated."
            else
                record_failure "${MEDIA_NAME} path update"
            fi
        fi

        return 0
    fi

    info "Creating ${MEDIA_NAME}"

    PAYLOAD="$(
        "${JQ}" -n \
            --arg name "${MEDIA_NAME}" \
            --arg path "${MEDIA_PATH}" \
            '{
                medium: {
                    name: $name,
                    path: $path,
                    os_family: "Redhat"
                }
            }'
    )"

    api_post "${FOREMAN_API}/media" "${PAYLOAD}"

    if [ $? -eq 0 ]
    then
        MEDIA_ID="$(
            echo "${API_BODY}" |
            "${JQ}" -r '.id // empty'
        )"

        ok "${MEDIA_NAME} created. ID=${MEDIA_ID}"
    else
        error "${MEDIA_NAME} creation failed."
        record_failure "${MEDIA_NAME}"
    fi
}

###############################################################################
# MEDIA DEFINITIONS
###############################################################################

CENTOS_MEDIA_NAME="CentOS 7 Remote"
CENTOS_MEDIA_PATH="http://192.168.253.136/repo/centos/"

ROCKY8_MEDIA_NAME="Rocky 8 Remote"
ROCKY8_MEDIA_PATH="http://192.168.253.136/repo/rocky8/"

ROCKY92_MEDIA_NAME="Rocky 9.2 Remote"
ROCKY92_MEDIA_PATH="http://192.168.253.136/repo/rocky9.2/"

ROCKY98_MEDIA_NAME="Rocky 9 Remote"
ROCKY98_MEDIA_PATH="http://192.168.253.136/repo/rocky9/"

create_media "${CENTOS_MEDIA_NAME}" "${CENTOS_MEDIA_PATH}"
create_media "${ROCKY8_MEDIA_NAME}" "${ROCKY8_MEDIA_PATH}"
create_media "${ROCKY92_MEDIA_NAME}" "${ROCKY92_MEDIA_PATH}"
create_media "${ROCKY98_MEDIA_NAME}" "${ROCKY98_MEDIA_PATH}"

###############################################################################
# GET MEDIA IDs
###############################################################################

get_media_id()
{
    MEDIA_NAME="$1"

    api_get "${FOREMAN_API}/media?search=name%3D%22${MEDIA_NAME// /%20}%22"

    echo "${API_BODY}" |
    "${JQ}" -r '.results[0].id // empty'
}

CENTOS_MEDIA_ID="$(get_media_id "${CENTOS_MEDIA_NAME}")"
ROCKY8_MEDIA_ID="$(get_media_id "${ROCKY8_MEDIA_NAME}")"
ROCKY92_MEDIA_ID="$(get_media_id "${ROCKY92_MEDIA_NAME}")"
ROCKY98_MEDIA_ID="$(get_media_id "${ROCKY98_MEDIA_NAME}")"

###############################################################################
# MEDIA VERIFICATION
###############################################################################

header "Installation Media Verification"

api_get "${FOREMAN_API}/media?per_page=all"

if [ $? -eq 0 ]
then
    echo "${API_BODY}" |
    "${JQ}" -r '
        .results[] |
        [
            .id,
            .name,
            .path
        ] |
        @tsv
    '
fi

###############################################################################
# OPERATING SYSTEMS
###############################################################################

header "Creating Operating Systems"

create_os()
{
    OS_NAME="$1"
    OS_MAJOR="$2"
    OS_MINOR="$3"
    MEDIA_ID="$4"

    section "Operating System : ${OS_NAME}"

    api_get "${FOREMAN_API}/operatingsystems?search=name%3D%22${OS_NAME}%22"

    OS_ID="$(
        echo "${API_BODY}" |
        "${JQ}" -r '.results[0].id // empty'
    )"

    if [ -n "${OS_ID}" ]
    then
        skip "${OS_NAME} already exists. ID=${OS_ID}"
        return 0
    fi

    PAYLOAD="$(
        "${JQ}" -n \
            --arg name "${OS_NAME}" \
            --arg major "${OS_MAJOR}" \
            --arg minor "${OS_MINOR}" \
            --argjson arch "${ARCH_ID}" \
            --argjson media "${MEDIA_ID}" \
            --argjson ptable "${PTABLE_ID}" \
            '{
                operatingsystem: {
                    name: $name,
                    major: $major,
                    minor: $minor,
                    family: "Redhat",
                    architecture_ids: [$arch],
                    medium_ids: [$media],
                    ptable_ids: [$ptable]
                }
            }'
    )"

    info "Creating ${OS_NAME}"

    api_post "${FOREMAN_API}/operatingsystems" "${PAYLOAD}"

    if [ $? -eq 0 ]
    then
        OS_ID="$(
            echo "${API_BODY}" |
            "${JQ}" -r '.id // empty'
        )"

        ok "${OS_NAME} created. ID=${OS_ID}"
    else
        error "${OS_NAME} creation failed."
        record_failure "${OS_NAME}"
    fi
}

###############################################################################
# CREATE ALL OS
###############################################################################

create_os \
    "CentOSLinux7-RAID" \
    "7" \
    "" \
    "${CENTOS_MEDIA_ID}"

create_os \
    "CentOSLinux7-SingleDisk" \
    "7" \
    "" \
    "${CENTOS_MEDIA_ID}"

create_os \
    "RockyLinux8.10-RAID" \
    "8" \
    "10" \
    "${ROCKY8_MEDIA_ID}"

create_os \
    "RockyLinux8.10-SingleDisk" \
    "8" \
    "10" \
    "${ROCKY8_MEDIA_ID}"

create_os \
    "RockyLinux9.2-RAID" \
    "9" \
    "2" \
    "${ROCKY92_MEDIA_ID}"

create_os \
    "RockyLinux9.2-SingleDisk" \
    "9" \
    "2" \
    "${ROCKY92_MEDIA_ID}"

create_os \
    "RockyLinux9.8-RAID" \
    "9" \
    "8" \
    "${ROCKY98_MEDIA_ID}"

create_os \
    "RockyLinux9.8-SingleDisk" \
    "9" \
    "8" \
    "${ROCKY98_MEDIA_ID}"

###############################################################################
# GET OS ID
###############################################################################

get_os_id()
{
    OS_NAME="$1"

    api_get "${FOREMAN_API}/operatingsystems?search=name%3D%22${OS_NAME}%22"

    echo "${API_BODY}" |
    "${JQ}" -r '.results[0].id // empty'
}

###############################################################################
# OPERATING SYSTEM VERIFICATION
###############################################################################

header "Operating System Verification"

api_get "${FOREMAN_API}/operatingsystems?per_page=all"

if [ $? -eq 0 ]
then
    echo "${API_BODY}" |
    "${JQ}" -r '
        .results[] |
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
        [
            .id,
            .name,
            .major,
            .minor,
            .family
        ] |
        @tsv
    '
fi

###############################################################################
# TEMPLATE DIRECTORY
###############################################################################

header "Generating PXEGrub2 Template Files"

"${MKDIR}" -p "${WORK_DIR}"

###############################################################################
# CENTOS RAID
###############################################################################

"${CAT}" > "${WORK_DIR}/centos-raid.erb" <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI RAID Kickstart
kind: PXEGrub2
oses:
- CentOSLinux7-RAID
-%>
set default=0
set timeout=5

menuentry 'Install CentOS 7 RAID' {
    linuxefi /centos/vmlinuz \
        inst.stage2=http://192.168.253.136/repo/centos/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/CentOS7_Golden_RAID_Minimal.cfg \
        inst.text \
        inst.ks.device=bootif \
        BOOTIF=01-${net_default_mac} \
        ip=dhcp \
        hostname=<%= @host.name %>
    initrdefi /centos/initrd.img
}
EOF

###############################################################################
# CENTOS SINGLE DISK
###############################################################################

"${CAT}" > "${WORK_DIR}/centos-singledisk.erb" <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- CentOSLinux7-SingleDisk
-%>
set default=0
set timeout=5

menuentry 'Install CentOS 7 Single Disk' {
    linuxefi /centos/vmlinuz \
        inst.stage2=http://192.168.253.136/repo/centos/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/CentOS7_Golden_SingleDisk_Minimal.cfg \
        inst.text \
        inst.ks.device=bootif \
        BOOTIF=01-${net_default_mac} \
        ip=dhcp \
        hostname=<%= @host.name %>
    initrdefi /centos/initrd.img
}
EOF

###############################################################################
# ROCKY 8 RAID
###############################################################################

"${CAT}" > "${WORK_DIR}/rocky8-raid.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI RAID Kickstart
kind: PXEGrub2
oses:
- RockyLinux8.10-RAID
-%>
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
# ROCKY 8 SINGLE DISK
###############################################################################

"${CAT}" > "${WORK_DIR}/rocky8-singledisk.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux8.10-SingleDisk
-%>
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
# ROCKY 9.2 RAID
###############################################################################

"${CAT}" > "${WORK_DIR}/rocky92-raid.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky9.2 UEFI RAID Kickstart
kind: PXEGrub2
oses:
- RockyLinux9.2-RAID
-%>
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
# ROCKY 9.2 SINGLE DISK
###############################################################################

"${CAT}" > "${WORK_DIR}/rocky92-singledisk.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux9.2-SingleDisk
-%>
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
# ROCKY 9.8 RAID
###############################################################################

"${CAT}" > "${WORK_DIR}/rocky98-raid.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky9.8 UEFI RAID Kickstart
kind: PXEGrub2
oses:
- RockyLinux9.8-RAID
-%>
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
# ROCKY 9.8 SINGLE DISK
###############################################################################

"${CAT}" > "${WORK_DIR}/rocky98-singledisk.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux9.8-SingleDisk
-%>
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

"${LS}" -l "${WORK_DIR}"/*.erb

###############################################################################
# FIND PXEGRUB2 TEMPLATE KIND
#
# IMPORTANT:
# Do NOT use /api/template_kinds here.
#
# Your Foreman returned:
#
# {
#   "total": 13,
#   "results": []
# }
#
# Instead derive the kind from an existing PXEGrub2 template.
###############################################################################

header "Finding PXEGrub2 Template Kind"

PXEGRUB2_KIND_ID=""

api_get \
    "${FOREMAN_API}/provisioning_templates?search=name%3D%22PXEGrub2%20default%20local%20boot%22"

if [ $? -eq 0 ]
then
    PXEGRUB2_KIND_ID="$(
        echo "${API_BODY}" |
        "${JQ}" -r '.results[] | select(.name=="PXEGrub2 default local boot") | .template_kind_id' |
        "${HEAD}" -1
    )"
fi

###############################################################################
# FALLBACK: SEARCH ANY EXISTING PXEGRUB2 TEMPLATE
###############################################################################

if [ -z "${PXEGRUB2_KIND_ID}" ] ||
   [ "${PXEGRUB2_KIND_ID}" = "null" ]
then

    api_get \
        "${FOREMAN_API}/provisioning_templates?per_page=all"

    if [ $? -eq 0 ]
    then
        PXEGRUB2_KIND_ID="$(
            echo "${API_BODY}" |
            "${JQ}" -r '
                .results[]
                | select(.template_kind_name=="PXEGrub2")
                | .template_kind_id
            ' |
            "${HEAD}" -1
        )"
    fi
fi

###############################################################################
# RESULT
###############################################################################

if [ -n "${PXEGRUB2_KIND_ID}" ] &&
   [ "${PXEGRUB2_KIND_ID}" != "null" ]
then
    ok "PXEGrub2 template kind found. ID=${PXEGRUB2_KIND_ID}"
else
    error "PXEGrub2 template kind could not be determined."

    info "Available provisioning templates:"
    api_get "${FOREMAN_API}/provisioning_templates?per_page=all"

    if [ $? -eq 0 ]
    then
        echo "${API_BODY}" |
        "${JQ}" -r '
            .results[] |
            [
                .id,
                .name,
                .template_kind_id,
                .template_kind_name
            ] |
            @tsv
        '
    fi

    record_failure "PXEGrub2 template kind"
fi

###############################################################################
# TEMPLATE DEFINITIONS
###############################################################################

TEMPLATE_NAMES=(
    "PXEGrub2 CentOS UEFI RAID Kickstart"
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart"
    "PXEGrub2 Rocky8 UEFI RAID Kickstart"
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"
    "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"
    "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"
    "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"
    "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"
)

TEMPLATE_FILES=(
    "${WORK_DIR}/centos-raid.erb"
    "${WORK_DIR}/centos-singledisk.erb"
    "${WORK_DIR}/rocky8-raid.erb"
    "${WORK_DIR}/rocky8-singledisk.erb"
    "${WORK_DIR}/rocky92-raid.erb"
    "${WORK_DIR}/rocky92-singledisk.erb"
    "${WORK_DIR}/rocky98-raid.erb"
    "${WORK_DIR}/rocky98-singledisk.erb"
)

###############################################################################
# FIND TEMPLATE ID
###############################################################################

get_template_id()
{
    TEMPLATE_NAME="$1"

    api_get \
        "${FOREMAN_API}/provisioning_templates?search=name%3D%22${TEMPLATE_NAME// /%20}%22"

    echo "${API_BODY}" |
    "${JQ}" -r \
        --arg NAME "${TEMPLATE_NAME}" \
        '.results[] | select(.name==$NAME) | .id' |
    "${HEAD}" -1
}

###############################################################################
# CREATE OR VERIFY TEMPLATE
###############################################################################

create_template()
{
    TEMPLATE_NAME="$1"
    TEMPLATE_FILE="$2"

    section "PXEGrub2 template : ${TEMPLATE_NAME}"

    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -n "${TEMPLATE_ID}" ]
    then
        skip "${TEMPLATE_NAME} already exists. ID=${TEMPLATE_ID}"
        return 0
    fi

    if [ -z "${PXEGRUB2_KIND_ID}" ]
    then
        error "Cannot create ${TEMPLATE_NAME}: PXEGrub2 kind ID unavailable."
        record_failure "${TEMPLATE_NAME}"
        return 1
    fi

    TEMPLATE_CONTENT="$("${CAT}" "${TEMPLATE_FILE}")"

    PAYLOAD="$(
        "${JQ}" -n \
            --arg name "${TEMPLATE_NAME}" \
            --arg template "${TEMPLATE_CONTENT}" \
            --argjson kind "${PXEGRUB2_KIND_ID}" \
            '{
                provisioning_template: {
                    name: $name,
                    template: $template,
                    template_kind_id: $kind
                }
            }'
    )"

    info "Creating ${TEMPLATE_NAME}"

    api_post \
        "${FOREMAN_API}/provisioning_templates" \
        "${PAYLOAD}"

    if [ $? -eq 0 ]
    then
        TEMPLATE_ID="$(
            echo "${API_BODY}" |
            "${JQ}" -r '.id // empty'
        )"

        ok "${TEMPLATE_NAME} created. ID=${TEMPLATE_ID}"
    else
        error "${TEMPLATE_NAME} creation failed. HTTP=${API_STATUS}"
        record_failure "${TEMPLATE_NAME}"
    fi
}

###############################################################################
# CREATE ALL 8 TEMPLATES
###############################################################################

header "Creating PXEGrub2 Templates"

INDEX=0

while [ "${INDEX}" -lt 8 ]
do
    create_template \
        "${TEMPLATE_NAMES[${INDEX}]}" \
        "${TEMPLATE_FILES[${INDEX}]}"

    INDEX=$((INDEX + 1))
done

###############################################################################
# ASSOCIATE TEMPLATE WITH OS
###############################################################################

associate_template()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    section "Associating:"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"

    OS_ID="$(get_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then
        error "Operating System not found : ${OS_NAME}"
        record_failure "${OS_NAME}"
        return 1
    fi

    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${TEMPLATE_NAME}"
        return 1
    fi

    ###########################################################################
    # GET CURRENT OS
    ###########################################################################

    api_get "${FOREMAN_API}/operatingsystems/${OS_ID}"

    if [ $? -ne 0 ]
    then
        record_failure "${OS_NAME} information"
        return 1
    fi

    ALREADY_ASSOCIATED="$(
        echo "${API_BODY}" |
        "${JQ}" -r \
            --argjson ID "${TEMPLATE_ID}" \
            '
            [
                .provisioning_templates[]?
                | select(.id == $ID)
            ] |
            length
            '
    )"

    if [ "${ALREADY_ASSOCIATED}" -gt 0 ]
    then
        skip "Template already associated."
        return 0
    fi

    ###########################################################################
    # CURRENT TEMPLATE IDs
    ###########################################################################

    CURRENT_TEMPLATE_IDS="$(
        echo "${API_BODY}" |
        "${JQ}" -c '
            [
                .provisioning_templates[]?.id
            ]
        '
    )"

    if [ "${CURRENT_TEMPLATE_IDS}" = "null" ] ||
       [ -z "${CURRENT_TEMPLATE_IDS}" ]
    then
        CURRENT_TEMPLATE_IDS="[]"
    fi

    NEW_TEMPLATE_IDS="$(
        echo "${CURRENT_TEMPLATE_IDS}" |
        "${JQ}" \
            --argjson NEW_ID "${TEMPLATE_ID}" \
            '. + [$NEW_ID] | unique'
    )"

    PAYLOAD="$(
        "${JQ}" -n \
            --argjson IDS "${NEW_TEMPLATE_IDS}" \
            '{
                operatingsystem: {
                    provisioning_template_ids: $IDS
                }
            }'
    )"

    api_put \
        "${FOREMAN_API}/operatingsystems/${OS_ID}" \
        "${PAYLOAD}"

    if [ $? -eq 0 ]
    then
        ok "Template associated with ${OS_NAME}."
    else
        error "Template association failed."
        record_failure "${OS_NAME} -> ${TEMPLATE_NAME}"
    fi
}

###############################################################################
# ASSOCIATE ALL 8
###############################################################################

header "Associating PXEGrub2 Templates"

associate_template \
    "CentOSLinux7-RAID" \
    "PXEGrub2 CentOS UEFI RAID Kickstart"

associate_template \
    "CentOSLinux7-SingleDisk" \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

associate_template \
    "RockyLinux8.10-RAID" \
    "PXEGrub2 Rocky8 UEFI RAID Kickstart"

associate_template \
    "RockyLinux8.10-SingleDisk" \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

associate_template \
    "RockyLinux9.2-RAID" \
    "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

associate_template \
    "RockyLinux9.2-SingleDisk" \
    "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

associate_template \
    "RockyLinux9.8-RAID" \
    "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

associate_template \
    "RockyLinux9.8-SingleDisk" \
    "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

###############################################################################
# SET PXEGRUB2 DEFAULT
#
# IMPORTANT:
# Existing default records must be UPDATED rather than POSTed again.
#
# Foreman API:
#
# GET  /api/operatingsystems/:id/os_default_templates
# PUT  /api/operatingsystems/:id/os_default_templates/:default_id
#
###############################################################################

set_pxegrub2_default()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    section "Setting PXEGrub2 Default:"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"

    OS_ID="$(get_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then
        error "Operating System not found : ${OS_NAME}"
        record_failure "${OS_NAME} default"
        return 1
    fi

    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${TEMPLATE_NAME} default"
        return 1
    fi

    ###########################################################################
    # GET EXISTING DEFAULT TEMPLATE RECORDS
    ###########################################################################

    api_get \
        "${FOREMAN_API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"

    if [ $? -ne 0 ]
    then
        record_failure "${OS_NAME} default lookup"
        return 1
    fi

    EXISTING_DEFAULT_ID="$(
        echo "${API_BODY}" |
        "${JQ}" -r \
            --argjson KIND "${PXEGRUB2_KIND_ID}" \
            '
            .results[]?
            | select(.template_kind_id == $KIND)
            | .id
            ' |
        "${HEAD}" -1
    )"

    EXISTING_TEMPLATE_ID="$(
        echo "${API_BODY}" |
        "${JQ}" -r \
            --argjson KIND "${PXEGRUB2_KIND_ID}" \
            '
            .results[]?
            | select(.template_kind_id == $KIND)
            | .provisioning_template_id
            ' |
        "${HEAD}" -1
    )"

    ###########################################################################
    # EXISTING DEFAULT
    ###########################################################################

    if [ -n "${EXISTING_DEFAULT_ID}" ]
    then

        if [ "${EXISTING_TEMPLATE_ID}" = "${TEMPLATE_ID}" ]
        then
            skip "PXEGrub2 default already correct. Default ID=${EXISTING_DEFAULT_ID}"
            return 0
        fi

        info "Existing PXEGrub2 default found."
        info "Default ID            : ${EXISTING_DEFAULT_ID}"
        info "Current Template ID   : ${EXISTING_TEMPLATE_ID}"
        info "Required Template ID  : ${TEMPLATE_ID}"
        info "Updating PXEGrub2 default..."

        PAYLOAD="$(
            "${JQ}" -n \
                --argjson template "${TEMPLATE_ID}" \
                --argjson kind "${PXEGRUB2_KIND_ID}" \
                '{
                    os_default_template: {
                        provisioning_template_id: $template,
                        template_kind_id: $kind
                    }
                }'
        )"

        api_put \
            "${FOREMAN_API}/operatingsystems/${OS_ID}/os_default_templates/${EXISTING_DEFAULT_ID}" \
            "${PAYLOAD}"

        if [ $? -eq 0 ]
        then
            ok "PXEGrub2 default updated."
        else
            error "PXEGrub2 default update failed."
            record_failure "${OS_NAME} default"
        fi

        return 0
    fi

    ###########################################################################
    # NO DEFAULT EXISTS
    ###########################################################################

    info "No PXEGrub2 default found. Creating one..."

    PAYLOAD="$(
        "${JQ}" -n \
            --argjson template "${TEMPLATE_ID}" \
            --argjson kind "${PXEGRUB2_KIND_ID}" \
            '{
                os_default_template: {
                    provisioning_template_id: $template,
                    template_kind_id: $kind
                }
            }'
    )"

    api_post \
        "${FOREMAN_API}/operatingsystems/${OS_ID}/os_default_templates" \
        "${PAYLOAD}"

    if [ $? -eq 0 ]
    then
        DEFAULT_ID="$(
            echo "${API_BODY}" |
            "${JQ}" -r '.id // empty'
        )"

        ok "PXEGrub2 default created. ID=${DEFAULT_ID}"
    else
        error "PXEGrub2 default creation failed."
        record_failure "${OS_NAME} default"
    fi
}

###############################################################################
# SET ALL DEFAULTS
###############################################################################

header "Setting PXEGrub2 Default Templates"

set_pxegrub2_default \
    "CentOSLinux7-RAID" \
    "PXEGrub2 CentOS UEFI RAID Kickstart"

set_pxegrub2_default \
    "CentOSLinux7-SingleDisk" \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

set_pxegrub2_default \
    "RockyLinux8.10-RAID" \
    "PXEGrub2 Rocky8 UEFI RAID Kickstart"

set_pxegrub2_default \
    "RockyLinux8.10-SingleDisk" \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

set_pxegrub2_default \
    "RockyLinux9.2-RAID" \
    "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

set_pxegrub2_default \
    "RockyLinux9.2-SingleDisk" \
    "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

set_pxegrub2_default \
    "RockyLinux9.8-RAID" \
    "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

set_pxegrub2_default \
    "RockyLinux9.8-SingleDisk" \
    "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

###############################################################################
# DOMAIN
###############################################################################

get_domain_id()
{
    DOMAIN_NAME="$1"

    api_get \
        "${FOREMAN_API}/domains?search=name%3D%22${DOMAIN_NAME}%22"

    echo "${API_BODY}" |
    "${JQ}" -r '.results[0].id // empty'
}

###############################################################################
# PROXY
###############################################################################

get_proxy_id()
{
    PROXY_NAME="$1"

    api_get \
        "${FOREMAN_API}/smart_proxies?search=name%3D%22${PROXY_NAME// /%20}%22"

    echo "${API_BODY}" |
    "${JQ}" -r '.results[0].id // empty'
}

###############################################################################
# CREATE / UPDATE SUBNET
###############################################################################

create_or_update_subnet()
{
    SUBNET_NAME="$1"
    NETWORK="$2"
    MASK="$3"
    GATEWAY="$4"
    DNS="$5"
    TFTP_PROXY_NAME="$6"
    DHCP_PROXY_NAME="$7"

    section "Subnet : ${SUBNET_NAME}"

    echo "Network      : ${NETWORK}"
    echo "Mask         : ${MASK}"
    echo "Gateway      : ${GATEWAY}"
    echo "DNS          : ${DNS}"
    echo "TFTP Proxy   : ${TFTP_PROXY_NAME}"
    echo "DHCP Proxy   : ${DHCP_PROXY_NAME}"

    DOMAIN_ID="$(get_domain_id "vgs.com")"

    if [ -n "${DOMAIN_ID}" ]
    then
        ok "Domain found : vgs.com ID=${DOMAIN_ID}"
    else
        error "Domain not found : vgs.com"
        record_failure "${SUBNET_NAME} domain"
        return 1
    fi

    TFTP_PROXY_ID="$(get_proxy_id "${TFTP_PROXY_NAME}")"

    if [ -n "${TFTP_PROXY_ID}" ]
    then
        ok "TFTP proxy found : ${TFTP_PROXY_NAME} ID=${TFTP_PROXY_ID}"
    else
        error "TFTP proxy not found : ${TFTP_PROXY_NAME}"
        record_failure "${SUBNET_NAME} TFTP proxy"
        return 1
    fi

    DHCP_PROXY_ID="$(get_proxy_id "${DHCP_PROXY_NAME}")"

    if [ -n "${DHCP_PROXY_ID}" ]
    then
        ok "DHCP proxy found : ${DHCP_PROXY_NAME} ID=${DHCP_PROXY_ID}"
    else
        error "DHCP proxy not found : ${DHCP_PROXY_NAME}"
        record_failure "${SUBNET_NAME} DHCP proxy"
        return 1
    fi

    ###########################################################################
    # LOOKUP SUBNET
    ###########################################################################

    api_get \
        "${FOREMAN_API}/subnets?search=name%3D%22${SUBNET_NAME// /%20}%22"

    SUBNET_ID="$(
        echo "${API_BODY}" |
        "${JQ}" -r '.results[0].id // empty'
    )"

    ###########################################################################
    # PAYLOAD
    ###########################################################################

    PAYLOAD="$(
        "${JQ}" -n \
            --arg name "${SUBNET_NAME}" \
            --arg network "${NETWORK}" \
            --arg mask "${MASK}" \
            --arg gateway "${GATEWAY}" \
            --arg dns "${DNS}" \
            --argjson domain "${DOMAIN_ID}" \
            --argjson tftp "${TFTP_PROXY_ID}" \
            --argjson dhcp "${DHCP_PROXY_ID}" \
            '{
                subnet: {
                    name: $name,
                    network: $network,
                    mask: $mask,
                    gateway: $gateway,
                    dns_primary: $dns,
                    domain_ids: [$domain],
                    tftp_id: $tftp,
                    dhcp_id: $dhcp
                }
            }'
    )"

    ###########################################################################
    # CREATE
    ###########################################################################

    if [ -z "${SUBNET_ID}" ]
    then
        info "Creating ${SUBNET_NAME}"

        api_post \
            "${FOREMAN_API}/subnets" \
            "${PAYLOAD}"

        if [ $? -eq 0 ]
        then
            SUBNET_ID="$(
                echo "${API_BODY}" |
                "${JQ}" -r '.id // empty'
            )"

            ok "${SUBNET_NAME} created. ID=${SUBNET_ID}"
        else
            error "${SUBNET_NAME} creation failed."
            record_failure "${SUBNET_NAME}"
        fi

        return 0
    fi

    ###########################################################################
    # UPDATE
    ###########################################################################

    skip "${SUBNET_NAME} already exists. ID=${SUBNET_ID}"

    api_put \
        "${FOREMAN_API}/subnets/${SUBNET_ID}" \
        "${PAYLOAD}"

    if [ $? -eq 0 ]
    then
        ok "${SUBNET_NAME} updated."
    else
        error "${SUBNET_NAME} update failed."
        record_failure "${SUBNET_NAME} update"
    fi
}

###############################################################################
# SUBNETS
###############################################################################

header "Creating PXE Subnets"

create_or_update_subnet \
    "vgs-subnet-centos" \
    "192.168.253.0" \
    "255.255.255.0" \
    "192.168.253.2" \
    "192.168.253.1" \
    "cent-07-01.vgs.com" \
    "cent-07-01.vgs.com"

create_or_update_subnet \
    "vgs-subnet-rockyos" \
    "192.168.253.0" \
    "255.255.255.0" \
    "192.168.253.2" \
    "192.168.253.1" \
    "cent-07-02.vgs.com" \
    "cent-07-02.vgs.com"

###############################################################################
# SUBNET VERIFICATION
###############################################################################

header "PXE Subnet Verification"

api_get "${FOREMAN_API}/subnets?per_page=all"

if [ $? -eq 0 ]
then
    echo "${API_BODY}" |
    "${JQ}" -r '
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
            (.dhcp.name // "-"),
            (.tftp.name // "-")
        ] |
        @tsv
    '
fi

###############################################################################
# PXEGRUB2 TEMPLATE VERIFICATION
###############################################################################

header "PXEGrub2 Template Verification"

for TEMPLATE_NAME in "${TEMPLATE_NAMES[@]}"
do
    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "${TEMPLATE_NAME} verification failed."
        record_failure "${TEMPLATE_NAME} verification"
        continue
    fi

    api_get \
        "${FOREMAN_API}/provisioning_templates/${TEMPLATE_ID}"

    if [ $? -ne 0 ]
    then
        record_failure "${TEMPLATE_NAME} verification"
        continue
    fi

    KIND_ID="$(
        echo "${API_BODY}" |
        "${JQ}" -r '.template_kind_id // empty'
    )"

    KIND_NAME="$(
        echo "${API_BODY}" |
        "${JQ}" -r '.template_kind_name // empty'
    )"

    if [ "${KIND_ID}" = "${PXEGRUB2_KIND_ID}" ] &&
       [ "${KIND_NAME}" = "PXEGrub2" ]
    then
        ok "${TEMPLATE_NAME} | ID=${TEMPLATE_ID} | kind=${KIND_NAME} | kind_id=${KIND_ID}"
    else
        error "${TEMPLATE_NAME} has incorrect template kind."
        record_failure "${TEMPLATE_NAME} kind verification"
    fi
done

###############################################################################
# OS TEMPLATE MAPPING VERIFICATION
###############################################################################

header "OS Template Mapping Verification"

verify_mapping()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    OS_ID="$(get_os_id "${OS_NAME}")"
    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -z "${OS_ID}" ] ||
       [ -z "${TEMPLATE_ID}" ]
    then
        error "${OS_NAME} -> ${TEMPLATE_NAME}"
        record_failure "${OS_NAME} mapping"
        return
    fi

    api_get "${FOREMAN_API}/operatingsystems/${OS_ID}"

    if [ $? -ne 0 ]
    then
        record_failure "${OS_NAME} mapping"
        return
    fi

    FOUND="$(
        echo "${API_BODY}" |
        "${JQ}" -r \
            --argjson TEMPLATE "${TEMPLATE_ID}" \
            '
            [
                .provisioning_templates[]?
                | select(.id == $TEMPLATE)
            ] |
            length
            '
    )"

    if [ "${FOUND}" -gt 0 ]
    then
        ok "${OS_NAME} -> ${TEMPLATE_NAME}"
    else
        error "${OS_NAME} -> ${TEMPLATE_NAME}"
        record_failure "${OS_NAME} mapping"
    fi
}

verify_mapping \
    "CentOSLinux7-RAID" \
    "PXEGrub2 CentOS UEFI RAID Kickstart"

verify_mapping \
    "CentOSLinux7-SingleDisk" \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

verify_mapping \
    "RockyLinux8.10-RAID" \
    "PXEGrub2 Rocky8 UEFI RAID Kickstart"

verify_mapping \
    "RockyLinux8.10-SingleDisk" \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

verify_mapping \
    "RockyLinux9.2-RAID" \
    "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

verify_mapping \
    "RockyLinux9.2-SingleDisk" \
    "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

verify_mapping \
    "RockyLinux9.8-RAID" \
    "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

verify_mapping \
    "RockyLinux9.8-SingleDisk" \
    "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

###############################################################################
# PXEGRUB2 DEFAULT VERIFICATION
###############################################################################

header "PXEGrub2 Default Template Verification"

verify_default()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    OS_ID="$(get_os_id "${OS_NAME}")"
    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -z "${OS_ID}" ] ||
       [ -z "${TEMPLATE_ID}" ]
    then
        error "${OS_NAME} default verification failed."
        record_failure "${OS_NAME} default verification"
        return
    fi

    api_get \
        "${FOREMAN_API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"

    if [ $? -ne 0 ]
    then
        record_failure "${OS_NAME} default verification"
        return
    fi

    DEFAULT_TEMPLATE_ID="$(
        echo "${API_BODY}" |
        "${JQ}" -r \
            --argjson KIND "${PXEGRUB2_KIND_ID}" \
            '
            .results[]?
            | select(.template_kind_id == $KIND)
            | .provisioning_template_id
            ' |
        "${HEAD}" -1
    )"

    if [ "${DEFAULT_TEMPLATE_ID}" = "${TEMPLATE_ID}" ]
    then
        ok "${OS_NAME} default -> ${TEMPLATE_NAME}"
    else
        error "${OS_NAME} default template missing or incorrect."
        record_failure "${OS_NAME} default verification"
    fi
}

verify_default \
    "CentOSLinux7-RAID" \
    "PXEGrub2 CentOS UEFI RAID Kickstart"

verify_default \
    "CentOSLinux7-SingleDisk" \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

verify_default \
    "RockyLinux8.10-RAID" \
    "PXEGrub2 Rocky8 UEFI RAID Kickstart"

verify_default \
    "RockyLinux8.10-SingleDisk" \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

verify_default \
    "RockyLinux9.2-RAID" \
    "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

verify_default \
    "RockyLinux9.2-SingleDisk" \
    "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

verify_default \
    "RockyLinux9.8-RAID" \
    "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

verify_default \
    "RockyLinux9.8-SingleDisk" \
    "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

###############################################################################
# FINAL OS INFORMATION
###############################################################################

header "Final Operating System Verification"

for OS_NAME in \
    "CentOSLinux7-RAID" \
    "CentOSLinux7-SingleDisk" \
    "RockyLinux8.10-RAID" \
    "RockyLinux8.10-SingleDisk" \
    "RockyLinux9.2-RAID" \
    "RockyLinux9.2-SingleDisk" \
    "RockyLinux9.8-RAID" \
    "RockyLinux9.8-SingleDisk"
do

    OS_ID="$(get_os_id "${OS_NAME}")"

    section "OS : ${OS_NAME}"
    echo "ID : ${OS_ID}"

    if [ -z "${OS_ID}" ]
    then
        error "OS not found."
        continue
    fi

    api_get "${FOREMAN_API}/operatingsystems/${OS_ID}"

    if [ $? -ne 0 ]
    then
        continue
    fi

    echo "${API_BODY}" |
    "${JQ}" -r '
        "Name          : " + (.name // ""),
        "Title         : " + (.title // ""),
        "Major         : " + (.major // ""),
        "Minor         : " + (.minor // ""),
        "Family        : " + (.family // ""),
        "Architecture  : " + (
            [
                .architectures[]?.name
            ] | join(", ")
        ),
        "Media         : " + (
            [
                .media[]?.name
            ] | join(", ")
        ),
        "Ptable        : " + (
            [
                .ptables[]?.name
            ] | join(", ")
        ),
        "Templates     : " + (
            [
                .provisioning_templates[]?.name
            ] | join(", ")
        ),
        "Defaults      : " + (
            [
                .os_default_templates[]?.provisioning_template_name
            ] | join(", ")
        )
    '
done

###############################################################################
# PXEGRUB2 TEMPLATE LIST
###############################################################################

header "PXEGrub2 Templates"

api_get "${FOREMAN_API}/provisioning_templates?per_page=all"

if [ $? -eq 0 ]
then
    echo "${API_BODY}" |
    "${JQ}" -r '
        .results[] |
        select(.template_kind_name == "PXEGrub2") |
        [
            .id,
            .name,
            .template_kind_name,
            .template_kind_id
        ] |
        @tsv
    '
fi

###############################################################################
# GENERATED FILES
###############################################################################

header "Generated PXE Template Files"

"${LS}" -lh "${WORK_DIR}"/*.erb

###############################################################################
# AUTHENTICATION INFORMATION
###############################################################################

header "Authentication"

echo "Method        : Foreman REST API"
echo "Username      : ${FOREMAN_USER}"
echo "Authentication: Personal Access Token"
echo "Hammer        : NOT USED"
echo "curl          : USED"
echo "API           : ${FOREMAN_API}"

###############################################################################
# MANUAL API VERIFICATION
###############################################################################

header "Manual API Verification"

echo
echo "Foreman status:"
echo "------------------------------------------------------------"
echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  ${FOREMAN_API}/status"
echo

echo "PXEGrub2 templates:"
echo "------------------------------------------------------------"
echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${FOREMAN_API}/provisioning_templates?per_page=all' | jq"
echo

echo "Operating systems:"
echo "------------------------------------------------------------"
echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${FOREMAN_API}/operatingsystems?per_page=all' | jq"
echo

echo "Subnets:"
echo "------------------------------------------------------------"
echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${FOREMAN_API}/subnets?per_page=all' | jq"
echo

###############################################################################
# FINAL STATUS
###############################################################################

header "01 - Foreman PXE Bootstrap API Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]
then
    ok "Bootstrap completed successfully."
    ok "All PXEGrub2 templates, OS mappings, defaults and subnets verified."
    exit 0
fi

warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

echo

for STEP in "${FAILED_STEPS[@]}"
do
    error "${STEP}"
done

exit 1
