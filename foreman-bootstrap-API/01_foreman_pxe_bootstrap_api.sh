#!/bin/bash
###############################################################################
# 01 - Foreman PXE Bootstrap - REST API
#
# Purpose:
#   Complete Foreman PXE bootstrap using REST API.
#
# Creates / verifies:
#   1. Installation Media
#   2. Operating Systems
#   3. PXEGrub2 provisioning templates
#   4. OS <-> PXEGrub2 template associations
#   5. PXEGrub2 default templates
#   6. PXE Subnets
#   7. Verification
#
# Supported OS:
#   CentOS 7 RAID
#   CentOS 7 Single Disk
#   Rocky Linux 8.10 RAID
#   Rocky Linux 8.10 Single Disk
#   Rocky Linux 9.2 RAID
#   Rocky Linux 9.2 Single Disk
#   Rocky Linux 9.8 RAID
#   Rocky Linux 9.8 Single Disk
#
###############################################################################

set +e

###############################################################################
# Configuration
###############################################################################

FOREMAN_HOST="${FOREMAN_HOST:-https://cent-07-01.vgs.com}"

FOREMAN_USER="${FOREMAN_USER:-admin}"

# PAT
FOREMAN_TOKEN="${FOREMAN_TOKEN:-oUzg-aMfjcT3q_wZ8NRLfQ}"

API_BASE="${FOREMAN_HOST}/api"

###############################################################################
# Repository Configuration
###############################################################################

CENTOS_REPO="http://192.168.253.136/repo/centos/"
ROCKY8_REPO="http://192.168.253.136/repo/rocky8/"
ROCKY92_REPO="http://192.168.253.136/repo/rocky9.2/"
ROCKY98_REPO="http://192.168.253.136/repo/rocky9/"

###############################################################################
# Kickstart Configuration
###############################################################################

CENTOS_RAID_KS="http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/CentOS7_Golden_RAID_Minimal.cfg"

CENTOS_SINGLE_KS="http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/CentOS7_Golden_SingleDisk_Minimal.cfg"

ROCKY8_RAID_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/Rocky8_Golden_RAID_Minimal.cfg"

ROCKY8_SINGLE_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/Rocky8_Golden_SingleDisk_Minimal.cfg"

ROCKY92_RAID_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/Rocky9_2_Golden_RAID_Minimal.cfg"

ROCKY92_SINGLE_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/Rocky9_2_Golden_SingleDisk_Minimal.cfg"

ROCKY98_RAID_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/Rocky9_Golden_RAID_Minimal.cfg"

ROCKY98_SINGLE_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/Rocky9_Golden_SingleDisk_Minimal.cfg"

###############################################################################
# Temporary Working Directory
###############################################################################

WORK_DIR="/tmp/foreman-pxe-bootstrap"

mkdir -p "${WORK_DIR}"

API_BODY_FILE="${WORK_DIR}/api-body.json"
API_STATUS_FILE="${WORK_DIR}/api-status.txt"

###############################################################################
# Colors
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
# Logging
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
# Failure Tracking
###############################################################################

FAILED_STEPS=()

record_failure()
{
    FAILED_STEPS+=("$1")
}

###############################################################################
# Dependency Detection
###############################################################################

CURL="$(command -v curl 2>/dev/null)"
JQ="$(command -v jq 2>/dev/null)"
CAT="$(command -v cat 2>/dev/null)"
HEAD="$(command -v head 2>/dev/null)"
GREP="$(command -v grep 2>/dev/null)"
AWK="$(command -v awk 2>/dev/null)"
SED="$(command -v sed 2>/dev/null)"
MKDIR="$(command -v mkdir 2>/dev/null)"
RM="$(command -v rm 2>/dev/null)"
DATE="$(command -v date 2>/dev/null)"
BASENAME="$(command -v basename 2>/dev/null)"
TR="$(command -v tr 2>/dev/null)"

###############################################################################
# Dependency Check
###############################################################################

header "01 - Foreman PXE Bootstrap - REST API"

header "Dependency Check"

MISSING=0

check_command()
{
    COMMAND_NAME="$1"
    COMMAND_PATH="$2"

    if [ -x "${COMMAND_PATH}" ]
    then
        ok "${COMMAND_NAME} found: ${COMMAND_PATH}"
    else
        error "${COMMAND_NAME} not found."
        MISSING=1
    fi
}

check_command "curl" "${CURL}"
check_command "jq" "${JQ}"
check_command "cat" "${CAT}"
check_command "head" "${HEAD}"
check_command "grep" "${GREP}"
check_command "awk" "${AWK}"
check_command "sed" "${SED}"
check_command "mkdir" "${MKDIR}"

if [ "${MISSING}" -ne 0 ]
then
    error "Required dependencies are missing."
    exit 1
fi

###############################################################################
# Curl TLS Options
###############################################################################

CURL_TLS="-k"

###############################################################################
# API Request Function
#
# Usage:
#   api_request GET URL
#   api_request POST URL JSON
#   api_request PUT URL JSON
#   api_request DELETE URL
###############################################################################

api_request()
{
    API_METHOD="$1"
    API_URL="$2"
    API_DATA="${3:-}"

    : > "${API_BODY_FILE}"
    : > "${API_STATUS_FILE}"

    if [ -n "${API_DATA}" ]
    then

        API_STATUS="$(
            "${CURL}" \
                -sS \
                ${CURL_TLS} \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                -X "${API_METHOD}" \
                -H 'Accept: application/json,version=2' \
                -H 'Content-Type: application/json' \
                --data "${API_DATA}" \
                -o "${API_BODY_FILE}" \
                -w '%{http_code}' \
                "${API_URL}"
        )"

    else

        API_STATUS="$(
            "${CURL}" \
                -sS \
                ${CURL_TLS} \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                -X "${API_METHOD}" \
                -H 'Accept: application/json,version=2' \
                -o "${API_BODY_FILE}" \
                -w '%{http_code}' \
                "${API_URL}"
        )"

    fi

    echo "${API_STATUS}" > "${API_STATUS_FILE}"

    API_BODY="$("${CAT}" "${API_BODY_FILE}")"

    return 0
}

###############################################################################
# API Error Display
###############################################################################

show_api_error()
{
    error "API request failed."
    error "HTTP Status : ${API_STATUS}"
    error "Method      : ${API_METHOD}"
    error "URL         : ${API_URL}"

    if [ -s "${API_BODY_FILE}" ]
    then
        echo "${API_BODY}"
    fi
}

###############################################################################
# API JSON Validation
###############################################################################

json_valid()
{
    "${JQ}" empty "${API_BODY_FILE}" >/dev/null 2>&1
    return $?
}

###############################################################################
# Foreman Authentication Test
###############################################################################

header "Foreman API Authentication Test"

info "Testing Foreman REST API..."

api_request \
    GET \
    "${API_BASE}/status"

if [ "${API_STATUS}" = "200" ] && json_valid
then

    FOREMAN_VERSION="$(
        "${JQ}" -r '.version // empty' "${API_BODY_FILE}"
    )"

    FOREMAN_API_VERSION="$(
        "${JQ}" -r '.api_version // empty' "${API_BODY_FILE}"
    )"

    FOREMAN_API_STATUS="$(
        "${JQ}" -r '.status // empty' "${API_BODY_FILE}"
    )"

    RESULT="$(
        "${JQ}" -r '.result // empty' "${API_BODY_FILE}"
    )"

    if [ "${RESULT}" = "ok" ]
    then
        ok "Foreman API authentication successful."

        echo "Foreman Version : ${FOREMAN_VERSION}"
        echo "API Version     : ${FOREMAN_API_VERSION}"
        echo "API Status      : ${FOREMAN_API_STATUS}"
    else
        error "Foreman API returned unexpected result."
        cat "${API_BODY_FILE}"
        exit 1
    fi

else

    show_api_error
    error "Foreman API authentication failed."
    exit 1

fi

###############################################################################
# Get Architecture
###############################################################################

ARCH_ID="$(
    api_request GET "${API_BASE}/architectures?search=name%3D%22x86_64%22&per_page=all" >/dev/null 2>&1

    "${JQ}" -r \
        '.results[] | select(.name=="x86_64") | .id' \
        "${API_BODY_FILE}" 2>/dev/null |
        "${HEAD}" -1
)"

if [ -z "${ARCH_ID}" ]
then
    ARCH_ID="$(
        api_request GET "${API_BASE}/architectures?per_page=all" >/dev/null 2>&1

        "${JQ}" -r \
            '.results[] | select(.name=="x86_64") | .id' \
            "${API_BODY_FILE}" 2>/dev/null |
            "${HEAD}" -1
    )"
fi

if [ -n "${ARCH_ID}" ]
then
    ok "x86_64 architecture found. ID=${ARCH_ID}"
else
    error "x86_64 architecture not found."
    record_failure "x86_64 architecture"
fi

###############################################################################
# Get Kickstart Default Partition Table
###############################################################################

PTABLE_ID="$(
    api_request GET "${API_BASE}/ptables?per_page=all" >/dev/null 2>&1

    "${JQ}" -r \
        '.results[] | select(.name=="Kickstart default") | .id' \
        "${API_BODY_FILE}" 2>/dev/null |
        "${HEAD}" -1
)"

if [ -n "${PTABLE_ID}" ]
then
    ok "Kickstart default partition table found. ID=${PTABLE_ID}"
else
    warn "Kickstart default partition table not found."
fi

###############################################################################
# Installation Media
###############################################################################

header "Creating Installation Media"

create_or_update_media()
{
    MEDIA_NAME="$1"
    MEDIA_PATH="$2"

    section "Installation Media : ${MEDIA_NAME}"

    api_request \
        GET \
        "${API_BASE}/media?search=name%3D%22${MEDIA_NAME}%22&per_page=all"

    MEDIA_ID="$(
        "${JQ}" -r \
            --arg NAME "${MEDIA_NAME}" \
            '.results[] | select(.name==$NAME) | .id' \
            "${API_BODY_FILE}" 2>/dev/null |
            "${HEAD}" -1
    )"

    if [ -n "${MEDIA_ID}" ]
    then

        skip "${MEDIA_NAME} already exists. ID=${MEDIA_ID}"

        api_request \
            GET \
            "${API_BASE}/media/${MEDIA_ID}"

        CURRENT_PATH="$(
            "${JQ}" -r '.path // empty' "${API_BODY_FILE}" 2>/dev/null
        )"

        if [ "${CURRENT_PATH}" = "${MEDIA_PATH}" ]
        then

            ok "${MEDIA_NAME} path verified."

        else

            warn "${MEDIA_NAME} path differs."
            info "Updating path..."

            MEDIA_JSON="$(
                "${JQ}" -n \
                    --arg PATH "${MEDIA_PATH}" \
                    '{
                        medium: {
                            path: $PATH
                        }
                    }'
            )"

            api_request \
                PUT \
                "${API_BASE}/media/${MEDIA_ID}" \
                "${MEDIA_JSON}"

            if [[ "${API_STATUS}" =~ ^2[0-9][0-9]$ ]]
            then
                ok "${MEDIA_NAME} path updated."
            else
                show_api_error
                record_failure "${MEDIA_NAME} media update"
            fi

        fi

    else

        info "Creating ${MEDIA_NAME}"

        MEDIA_JSON="$(
            "${JQ}" -n \
                --arg NAME "${MEDIA_NAME}" \
                --arg PATH "${MEDIA_PATH}" \
                '{
                    medium: {
                        name: $NAME,
                        path: $PATH,
                        os_family: "Redhat"
                    }
                }'
        )"

        api_request \
            POST \
            "${API_BASE}/media" \
            "${MEDIA_JSON}"

        if [[ "${API_STATUS}" =~ ^2[0-9][0-9]$ ]] &&
           json_valid
        then

            MEDIA_ID="$(
                "${JQ}" -r '.id // empty' "${API_BODY_FILE}"
            )"

            ok "${MEDIA_NAME} created. ID=${MEDIA_ID}"

        else

            error "${MEDIA_NAME} creation failed."
            show_api_error
            record_failure "${MEDIA_NAME} media creation"

        fi

    fi
}

create_or_update_media "CentOS 7 Remote" "${CENTOS_REPO}"
create_or_update_media "Rocky 8 Remote" "${ROCKY8_REPO}"
create_or_update_media "Rocky 9.2 Remote" "${ROCKY92_REPO}"
create_or_update_media "Rocky 9 Remote" "${ROCKY98_REPO}"

###############################################################################
# Installation Media Verification
###############################################################################

header "Installation Media Verification"

api_request \
    GET \
    "${API_BASE}/media?per_page=all"

if json_valid
then
    "${JQ}" -r '
        .results[] |
        [
            .id,
            .name,
            .path
        ] |
        @tsv
    ' "${API_BODY_FILE}"
else
    show_api_error
    record_failure "Installation media verification"
fi

###############################################################################
# OS Definitions
###############################################################################

OS_CENTOS_RAID="CentOSLinux7-RAID"
OS_CENTOS_SINGLE="CentOSLinux7-SingleDisk"

OS_ROCKY8_RAID="RockyLinux8.10-RAID"
OS_ROCKY8_SINGLE="RockyLinux8.10-SingleDisk"

OS_ROCKY92_RAID="RockyLinux9.2-RAID"
OS_ROCKY92_SINGLE="RockyLinux9.2-SingleDisk"

OS_ROCKY98_RAID="RockyLinux9.8-RAID"
OS_ROCKY98_SINGLE="RockyLinux9.8-SingleDisk"

###############################################################################
# Get Media ID
###############################################################################

get_media_id()
{
    MEDIA_NAME="$1"

    api_request \
        GET \
        "${API_BASE}/media?search=name%3D%22${MEDIA_NAME}%22&per_page=all"

    "${JQ}" -r \
        --arg NAME "${MEDIA_NAME}" \
        '.results[] | select(.name==$NAME) | .id' \
        "${API_BODY_FILE}" 2>/dev/null |
        "${HEAD}" -1
}

###############################################################################
# Create OS
###############################################################################

create_or_update_os()
{
    OS_NAME="$1"
    MAJOR="$2"
    MINOR="$3"
    MEDIA_NAME="$4"

    section "Operating System : ${OS_NAME}"

    MEDIA_ID="$(get_media_id "${MEDIA_NAME}")"

    if [ -z "${MEDIA_ID}" ]
    then
        error "Installation media not found : ${MEDIA_NAME}"
        record_failure "${OS_NAME} media"
        return
    fi

    api_request \
        GET \
        "${API_BASE}/operatingsystems?search=name%3D%22${OS_NAME}%22&per_page=all"

    OS_ID="$(
        "${JQ}" -r \
            --arg NAME "${OS_NAME}" \
            '.results[] | select(.name==$NAME) | .id' \
            "${API_BODY_FILE}" 2>/dev/null |
            "${HEAD}" -1
    )"

    if [ -n "${OS_ID}" ]
    then

        skip "${OS_NAME} already exists. ID=${OS_ID}"

    else

        info "Creating ${OS_NAME}"

        OS_JSON="$(
            "${JQ}" -n \
                --arg NAME "${OS_NAME}" \
                --argjson MAJOR "${MAJOR}" \
                --arg MINOR "${MINOR}" \
                --argjson ARCH "${ARCH_ID}" \
                --argjson MEDIA "${MEDIA_ID}" \
                '{
                    operatingsystem: {
                        name: $NAME,
                        major: ($MAJOR|tostring),
                        minor: $MINOR,
                        family: "Redhat",
                        architecture_ids: [$ARCH],
                        medium_ids: [$MEDIA]
                    }
                }'
        )"

        api_request \
            POST \
            "${API_BASE}/operatingsystems" \
            "${OS_JSON}"

        if [[ "${API_STATUS}" =~ ^2[0-9][0-9]$ ]] &&
           json_valid
        then

            OS_ID="$(
                "${JQ}" -r '.id // empty' "${API_BODY_FILE}"
            )"

            ok "${OS_NAME} created. ID=${OS_ID}"

        else

            error "${OS_NAME} creation failed."
            show_api_error
            record_failure "${OS_NAME} creation"
            return

        fi

    fi
}

###############################################################################
# Create All Operating Systems
###############################################################################

header "Creating Operating Systems"

create_or_update_os \
    "${OS_CENTOS_RAID}" \
    7 \
    "" \
    "CentOS 7 Remote"

create_or_update_os \
    "${OS_CENTOS_SINGLE}" \
    7 \
    "" \
    "CentOS 7 Remote"

create_or_update_os \
    "${OS_ROCKY8_RAID}" \
    8 \
    "10" \
    "Rocky 8 Remote"

create_or_update_os \
    "${OS_ROCKY8_SINGLE}" \
    8 \
    "10" \
    "Rocky 8 Remote"

create_or_update_os \
    "${OS_ROCKY92_RAID}" \
    9 \
    "2" \
    "Rocky 9.2 Remote"

create_or_update_os \
    "${OS_ROCKY92_SINGLE}" \
    9 \
    "2" \
    "Rocky 9.2 Remote"

create_or_update_os \
    "${OS_ROCKY98_RAID}" \
    9 \
    "8" \
    "Rocky 9 Remote"

create_or_update_os \
    "${OS_ROCKY98_SINGLE}" \
    9 \
    "8" \
    "Rocky 9 Remote"

###############################################################################
# OS Verification
###############################################################################

header "Operating System Verification"

api_request \
    GET \
    "${API_BASE}/operatingsystems?per_page=all"

if json_valid
then
    "${JQ}" -r '
        .results[] |
        select(
            .name=="CentOSLinux7-RAID" or
            .name=="CentOSLinux7-SingleDisk" or
            .name=="RockyLinux8.10-RAID" or
            .name=="RockyLinux8.10-SingleDisk" or
            .name=="RockyLinux9.2-RAID" or
            .name=="RockyLinux9.2-SingleDisk" or
            .name=="RockyLinux9.8-RAID" or
            .name=="RockyLinux9.8-SingleDisk"
        ) |
        [
            .id,
            .name,
            .major,
            .minor,
            .family
        ] |
        @tsv
    ' "${API_BODY_FILE}"
else
    show_api_error
    record_failure "Operating system verification"
fi

###############################################################################
# Generate PXEGrub2 Templates
###############################################################################

header "Generating PXEGrub2 Template Files"

###############################################################################
# CentOS RAID
###############################################################################

cat > "${WORK_DIR}/centos-raid.erb" <<'EOF'
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
        inst.ks.device=bootif
    initrdefi /centos/initrd.img
}
EOF

###############################################################################
# CentOS Single Disk
###############################################################################

cat > "${WORK_DIR}/centos-singledisk.erb" <<'EOF'
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
        inst.ks.device=bootif
    initrdefi /centos/initrd.img
}
EOF

###############################################################################
# Rocky 8 RAID
###############################################################################

cat > "${WORK_DIR}/rocky8-raid.erb" <<'EOF'
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
        inst.ks.device=bootif
    initrdefi /rocky8/initrd.img
}
EOF

###############################################################################
# Rocky 8 Single Disk
###############################################################################

cat > "${WORK_DIR}/rocky8-singledisk.erb" <<'EOF'
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
        inst.ks.device=bootif
    initrdefi /rocky8/initrd.img
}
EOF

###############################################################################
# Rocky 9.2 RAID
###############################################################################

cat > "${WORK_DIR}/rocky92-raid.erb" <<'EOF'
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
        inst.ks.device=bootif
    initrdefi /rocky92/initrd.img
}
EOF

###############################################################################
# Rocky 9.2 Single Disk
###############################################################################

cat > "${WORK_DIR}/rocky92-singledisk.erb" <<'EOF'
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
        inst.ks.device=bootif
    initrdefi /rocky92/initrd.img
}
EOF

###############################################################################
# Rocky 9.8 RAID
###############################################################################

cat > "${WORK_DIR}/rocky98-raid.erb" <<'EOF'
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
        inst.ks.device=bootif
    initrdefi /rocky9/initrd.img
}
EOF

###############################################################################
# Rocky 9.8 Single Disk
###############################################################################

cat > "${WORK_DIR}/rocky98-singledisk.erb" <<'EOF'
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
        inst.ks.device=bootif
    initrdefi /rocky9/initrd.img
}
EOF

ok "All 8 PXEGrub2 template files generated."

###############################################################################
# Template Kind
###############################################################################

header "Finding PXEGrub2 Template Kind"

api_request \
    GET \
    "${API_BASE}/template_kinds?per_page=all"

if ! json_valid
then
    error "Invalid JSON returned while querying template kinds."
    show_api_error
    exit 1
fi

PXEGRUB2_KIND_ID="$(
    "${JQ}" -r \
        '.results[] | select(.name=="PXEGrub2") | .id' \
        "${API_BODY_FILE}" 2>/dev/null |
        "${HEAD}" -1
)"

if [ -z "${PXEGRUB2_KIND_ID}" ] ||
   [ "${PXEGRUB2_KIND_ID}" = "null" ]
then

    error "PXEGrub2 template kind not found."

    "${CAT}" "${API_BODY_FILE}"

    record_failure "PXEGrub2 template kind"

else

    ok "PXEGrub2 template kind found. ID=${PXEGRUB2_KIND_ID}"

fi

###############################################################################
# Template Definitions
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
# Get Template ID
###############################################################################

get_template_id()
{
    TEMPLATE_NAME="$1"

    api_request \
        GET \
        "${API_BASE}/provisioning_templates?search=name%3D%22${TEMPLATE_NAME}%22&per_page=all"

    "${JQ}" -r \
        --arg NAME "${TEMPLATE_NAME}" \
        '.results[] | select(.name==$NAME) | .id' \
        "${API_BODY_FILE}" 2>/dev/null |
        "${HEAD}" -1
}

###############################################################################
# Create Template
###############################################################################

create_or_update_template()
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
        error "PXEGrub2 kind ID unavailable."
        record_failure "${TEMPLATE_NAME}"
        return 1
    fi

    if [ ! -f "${TEMPLATE_FILE}" ]
    then
        error "Template file missing : ${TEMPLATE_FILE}"
        record_failure "${TEMPLATE_NAME}"
        return 1
    fi

    TEMPLATE_CONTENT="$("${CAT}" "${TEMPLATE_FILE}")"

    TEMPLATE_JSON="$(
        "${JQ}" -n \
            --arg NAME "${TEMPLATE_NAME}" \
            --arg TEMPLATE "${TEMPLATE_CONTENT}" \
            --argjson KIND "${PXEGRUB2_KIND_ID}" \
            '{
                provisioning_template: {
                    name: $NAME,
                    template: $TEMPLATE,
                    template_kind_id: $KIND
                }
            }'
    )"

    info "Creating ${TEMPLATE_NAME}"

    api_request \
        POST \
        "${API_BASE}/provisioning_templates" \
        "${TEMPLATE_JSON}"

    if [[ "${API_STATUS}" =~ ^2[0-9][0-9]$ ]] &&
       json_valid
    then

        TEMPLATE_ID="$(
            "${JQ}" -r '.id // empty' "${API_BODY_FILE}"
        )"

        ok "${TEMPLATE_NAME} created. ID=${TEMPLATE_ID}"

    else

        error "${TEMPLATE_NAME} creation failed. HTTP=${API_STATUS}"
        show_api_error
        record_failure "${TEMPLATE_NAME}"

    fi
}

###############################################################################
# Create All Templates
###############################################################################

header "Creating PXEGrub2 Templates"

INDEX=0

for TEMPLATE_NAME in "${TEMPLATE_NAMES[@]}"
do

    TEMPLATE_FILE="${TEMPLATE_FILES[$INDEX]}"

    create_or_update_template \
        "${TEMPLATE_NAME}" \
        "${TEMPLATE_FILE}"

    INDEX=$((INDEX + 1))

done

###############################################################################
# Associate Template With OS
###############################################################################

associate_template()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    section "Associating:"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"

    api_request \
        GET \
        "${API_BASE}/operatingsystems?search=name%3D%22${OS_NAME}%22&per_page=all"

    OS_ID="$(
        "${JQ}" -r \
            --arg NAME "${OS_NAME}" \
            '.results[] | select(.name==$NAME) | .id' \
            "${API_BODY_FILE}" 2>/dev/null |
            "${HEAD}" -1
    )"

    if [ -z "${OS_ID}" ]
    then
        error "Operating System not found : ${OS_NAME}"
        record_failure "${OS_NAME} -> ${TEMPLATE_NAME}"
        return
    fi

    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${OS_NAME} -> ${TEMPLATE_NAME}"
        return
    fi

    api_request \
        GET \
        "${API_BASE}/operatingsystems/${OS_ID}/provisioning_templates?per_page=all"

    if json_valid &&
       "${JQ}" -e \
           --arg NAME "${TEMPLATE_NAME}" \
           '.results[] | select(.name==$NAME)' \
           "${API_BODY_FILE}" >/dev/null 2>&1
    then

        skip "Template already associated."

        return

    fi

    ASSOCIATION_JSON="$(
        "${JQ}" -n \
            --argjson OS "${OS_ID}" \
            --argjson TEMPLATE "${TEMPLATE_ID}" \
            '{
                provisioning_template: {
                    operatingsystem_ids: [$OS]
                }
            }'
    )"

    api_request \
        PUT \
        "${API_BASE}/provisioning_templates/${TEMPLATE_ID}" \
        "${ASSOCIATION_JSON}"

    if [[ "${API_STATUS}" =~ ^2[0-9][0-9]$ ]]
    then

        ok "Template associated with ${OS_NAME}."

    else

        error "Failed associating template with ${OS_NAME}."
        show_api_error
        record_failure "${OS_NAME} -> ${TEMPLATE_NAME}"

    fi
}

###############################################################################
# Associate All Templates
###############################################################################

header "Associating PXEGrub2 Templates"

associate_template \
    "${OS_CENTOS_RAID}" \
    "PXEGrub2 CentOS UEFI RAID Kickstart"

associate_template \
    "${OS_CENTOS_SINGLE}" \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

associate_template \
    "${OS_ROCKY8_RAID}" \
    "PXEGrub2 Rocky8 UEFI RAID Kickstart"

associate_template \
    "${OS_ROCKY8_SINGLE}" \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

associate_template \
    "${OS_ROCKY92_RAID}" \
    "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

associate_template \
    "${OS_ROCKY92_SINGLE}" \
    "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

associate_template \
    "${OS_ROCKY98_RAID}" \
    "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

associate_template \
    "${OS_ROCKY98_SINGLE}" \
    "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

###############################################################################
# Get OS Default Template Record
###############################################################################

get_default_template_record()
{
    OS_ID="$1"
    KIND_ID="$2"

    api_request \
        GET \
        "${API_BASE}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"

    "${JQ}" -r \
        --argjson KIND "${KIND_ID}" \
        '.results[] |
         select(.template_kind_id==$KIND) |
         [
             .id,
             .provisioning_template_id,
             .template_kind_id,
             .provisioning_template_name
         ] |
         @tsv' \
        "${API_BODY_FILE}" 2>/dev/null |
        "${HEAD}" -1
}

###############################################################################
# Set / Update PXEGrub2 Default
###############################################################################

set_pxegrub2_default()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    section "Setting PXEGrub2 Default:"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"

    api_request \
        GET \
        "${API_BASE}/operatingsystems?search=name%3D%22${OS_NAME}%22&per_page=all"

    OS_ID="$(
        "${JQ}" -r \
            --arg NAME "${OS_NAME}" \
            '.results[] | select(.name==$NAME) | .id' \
            "${API_BODY_FILE}" 2>/dev/null |
            "${HEAD}" -1
    )"

    if [ -z "${OS_ID}" ]
    then
        error "Operating System not found : ${OS_NAME}"
        record_failure "${OS_NAME} default template"
        return
    fi

    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${OS_NAME} default template"
        return
    fi

    if [ -z "${PXEGRUB2_KIND_ID}" ]
    then
        error "PXEGrub2 template kind ID unavailable."
        record_failure "${OS_NAME} default template"
        return
    fi

    DEFAULT_RECORD="$(
        get_default_template_record \
            "${OS_ID}" \
            "${PXEGRUB2_KIND_ID}"
    )"

    if [ -n "${DEFAULT_RECORD}" ]
    then

        DEFAULT_ID="$(
            echo "${DEFAULT_RECORD}" |
            "${AWK}" -F'\t' '{print $1}'
        )"

        CURRENT_TEMPLATE_ID="$(
            echo "${DEFAULT_RECORD}" |
            "${AWK}" -F'\t' '{print $2}'
        )"

        CURRENT_TEMPLATE_NAME="$(
            echo "${DEFAULT_RECORD}" |
            "${AWK}" -F'\t' '{print $4}'
        )"

        if [ "${CURRENT_TEMPLATE_ID}" = "${TEMPLATE_ID}" ]
        then

            ok "PXEGrub2 default already correct."
            echo "Default ID : ${DEFAULT_ID}"

            return

        fi

        warn "Existing PXEGrub2 default found."
        echo "Current : ${CURRENT_TEMPLATE_NAME}"
        echo "New     : ${TEMPLATE_NAME}"

        UPDATE_JSON="$(
            "${JQ}" -n \
                --argjson TEMPLATE "${TEMPLATE_ID}" \
                --argjson KIND "${PXEGRUB2_KIND_ID}" \
                '{
                    os_default_template: {
                        provisioning_template_id: $TEMPLATE,
                        template_kind_id: $KIND
                    }
                }'
        )"

        api_request \
            PUT \
            "${API_BASE}/operatingsystems/${OS_ID}/os_default_templates/${DEFAULT_ID}" \
            "${UPDATE_JSON}"

        if [[ "${API_STATUS}" =~ ^2[0-9][0-9]$ ]]
        then
            ok "PXEGrub2 default updated."
        else
            error "Failed updating PXEGrub2 default."
            show_api_error
            record_failure "${OS_NAME} default template"
        fi

    else

        info "No PXEGrub2 default found. Creating one..."

        CREATE_JSON="$(
            "${JQ}" -n \
                --argjson TEMPLATE "${TEMPLATE_ID}" \
                --argjson KIND "${PXEGRUB2_KIND_ID}" \
                '{
                    os_default_template: {
                        provisioning_template_id: $TEMPLATE,
                        template_kind_id: $KIND
                    }
                }'
        )"

        api_request \
            POST \
            "${API_BASE}/operatingsystems/${OS_ID}/os_default_templates" \
            "${CREATE_JSON}"

        if [[ "${API_STATUS}" =~ ^2[0-9][0-9]$ ]]
        then
            ok "PXEGrub2 default created."
        else
            error "Failed creating PXEGrub2 default."
            show_api_error
            record_failure "${OS_NAME} default template"
        fi

    fi
}

###############################################################################
# Set All PXEGrub2 Defaults
###############################################################################

header "Setting PXEGrub2 Default Templates"

set_pxegrub2_default \
    "${OS_CENTOS_RAID}" \
    "PXEGrub2 CentOS UEFI RAID Kickstart"

set_pxegrub2_default \
    "${OS_CENTOS_SINGLE}" \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

set_pxegrub2_default \
    "${OS_ROCKY8_RAID}" \
    "PXEGrub2 Rocky8 UEFI RAID Kickstart"

set_pxegrub2_default \
    "${OS_ROCKY8_SINGLE}" \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

set_pxegrub2_default \
    "${OS_ROCKY92_RAID}" \
    "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

set_pxegrub2_default \
    "${OS_ROCKY92_SINGLE}" \
    "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

set_pxegrub2_default \
    "${OS_ROCKY98_RAID}" \
    "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

set_pxegrub2_default \
    "${OS_ROCKY98_SINGLE}" \
    "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

###############################################################################
# Subnet Configuration
###############################################################################

DOMAIN_NAME="vgs.com"
CENTOS_PROXY="cent-07-01.vgs.com"
ROCKY_PROXY="cent-07-02.vgs.com"

CENTOS_SUBNET="vgs-subnet-centos"
ROCKY_SUBNET="vgs-subnet-rockyos"

NETWORK="192.168.253.0"
MASK="255.255.255.0"
GATEWAY="192.168.253.2"
DNS="192.168.253.1"

###############################################################################
# Get Domain ID
###############################################################################

get_domain_id()
{
    api_request \
        GET \
        "${API_BASE}/domains?search=name%3D%22${DOMAIN_NAME}%22&per_page=all"

    "${JQ}" -r \
        --arg NAME "${DOMAIN_NAME}" \
        '.results[] | select(.name==$NAME) | .id' \
        "${API_BODY_FILE}" 2>/dev/null |
        "${HEAD}" -1
}

###############################################################################
# Get Proxy ID
###############################################################################

get_proxy_id()
{
    PROXY_NAME="$1"

    api_request \
        GET \
        "${API_BASE}/smart_proxies?search=name%3D%22${PROXY_NAME}%22&per_page=all"

    "${JQ}" -r \
        --arg NAME "${PROXY_NAME}" \
        '.results[] | select(.name==$NAME) | .id' \
        "${API_BODY_FILE}" 2>/dev/null |
        "${HEAD}" -1
}

###############################################################################
# Create / Update Subnet
###############################################################################

create_or_update_subnet()
{
    SUBNET_NAME="$1"
    TFTP_PROXY="$2"
    DHCP_PROXY="$3"

    section "Subnet : ${SUBNET_NAME}"

    echo "Network      : ${NETWORK}"
    echo "Mask         : ${MASK}"
    echo "Gateway      : ${GATEWAY}"
    echo "DNS          : ${DNS}"
    echo "TFTP Proxy   : ${TFTP_PROXY}"
    echo "DHCP Proxy   : ${DHCP_PROXY}"

    DOMAIN_ID="$(get_domain_id)"

    if [ -z "${DOMAIN_ID}" ]
    then
        error "Domain not found : ${DOMAIN_NAME}"
        record_failure "${SUBNET_NAME} domain"
        return
    fi

    ok "Domain found : ${DOMAIN_NAME} ID=${DOMAIN_ID}"

    TFTP_PROXY_ID="$(get_proxy_id "${TFTP_PROXY}")"

    if [ -z "${TFTP_PROXY_ID}" ]
    then
        error "TFTP proxy not found : ${TFTP_PROXY}"
        record_failure "${SUBNET_NAME} TFTP proxy"
        return
    fi

    ok "TFTP proxy found : ${TFTP_PROXY} ID=${TFTP_PROXY_ID}"

    DHCP_PROXY_ID="$(get_proxy_id "${DHCP_PROXY}")"

    if [ -z "${DHCP_PROXY_ID}" ]
    then
        error "DHCP proxy not found : ${DHCP_PROXY}"
        record_failure "${SUBNET_NAME} DHCP proxy"
        return
    fi

    ok "DHCP proxy found : ${DHCP_PROXY} ID=${DHCP_PROXY_ID}"

    api_request \
        GET \
        "${API_BASE}/subnets?search=name%3D%22${SUBNET_NAME}%22&per_page=all"

    SUBNET_ID="$(
        "${JQ}" -r \
            --arg NAME "${SUBNET_NAME}" \
            '.results[] | select(.name==$NAME) | .id' \
            "${API_BODY_FILE}" 2>/dev/null |
            "${HEAD}" -1
    )"

    SUBNET_JSON="$(
        "${JQ}" -n \
            --arg NAME "${SUBNET_NAME}" \
            --arg NETWORK "${NETWORK}" \
            --arg MASK "${MASK}" \
            --arg GATEWAY "${GATEWAY}" \
            --arg DNS "${DNS}" \
            --argjson DOMAIN "${DOMAIN_ID}" \
            --argjson TFTP "${TFTP_PROXY_ID}" \
            --argjson DHCP "${DHCP_PROXY_ID}" \
            '{
                subnet: {
                    name: $NAME,
                    network: $NETWORK,
                    mask: $MASK,
                    gateway: $GATEWAY,
                    dns_primary: $DNS,
                    domain_ids: [$DOMAIN],
                    tftp_id: $TFTP,
                    dhcp_id: $DHCP
                }
            }'
    )"

    if [ -n "${SUBNET_ID}" ]
    then

        skip "${SUBNET_NAME} already exists. ID=${SUBNET_ID}"

        api_request \
            PUT \
            "${API_BASE}/subnets/${SUBNET_ID}" \
            "${SUBNET_JSON}"

        if [[ "${API_STATUS}" =~ ^2[0-9][0-9]$ ]]
        then
            ok "${SUBNET_NAME} updated."
        else
            error "${SUBNET_NAME} update failed."
            show_api_error
            record_failure "${SUBNET_NAME} update"
        fi

    else

        info "Creating ${SUBNET_NAME}"

        api_request \
            POST \
            "${API_BASE}/subnets" \
            "${SUBNET_JSON}"

        if [[ "${API_STATUS}" =~ ^2[0-9][0-9]$ ]]
        then

            SUBNET_ID="$(
                "${JQ}" -r '.id // empty' "${API_BODY_FILE}"
            )"

            ok "${SUBNET_NAME} created. ID=${SUBNET_ID}"

        else

            error "${SUBNET_NAME} creation failed."
            show_api_error
            record_failure "${SUBNET_NAME} creation"

        fi

    fi
}

###############################################################################
# Create Subnets
###############################################################################

header "Creating PXE Subnets"

create_or_update_subnet \
    "${CENTOS_SUBNET}" \
    "${CENTOS_PROXY}" \
    "${CENTOS_PROXY}"

create_or_update_subnet \
    "${ROCKY_SUBNET}" \
    "${ROCKY_PROXY}" \
    "${ROCKY_PROXY}"

###############################################################################
# Subnet Verification
###############################################################################

header "PXE Subnet Verification"

api_request \
    GET \
    "${API_BASE}/subnets?per_page=all"

if json_valid
then

    "${JQ}" -r '
        .results[] |
        select(
            .name=="vgs-subnet-centos" or
            .name=="vgs-subnet-rockyos"
        ) |
        [
            .id,
            .name,
            (.network + "/" + .mask),
            (.dhcp.name // ""),
            (.tftp.name // "")
        ] |
        @tsv
    ' "${API_BODY_FILE}"

else

    show_api_error
    record_failure "PXE subnet verification"

fi

###############################################################################
# PXEGrub2 Template Verification
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

    api_request \
        GET \
        "${API_BASE}/provisioning_templates/${TEMPLATE_ID}"

    if json_valid
    then

        TEMPLATE_KIND="$(
            "${JQ}" -r '.template_kind_name // empty' "${API_BODY_FILE}"
        )"

        TEMPLATE_KIND_ID="$(
            "${JQ}" -r '.template_kind_id // empty' "${API_BODY_FILE}"
        )"

        if [ "${TEMPLATE_KIND}" = "PXEGrub2" ] &&
           [ "${TEMPLATE_KIND_ID}" = "${PXEGRUB2_KIND_ID}" ]
        then

            ok "${TEMPLATE_NAME} | ID=${TEMPLATE_ID} | kind=${TEMPLATE_KIND} | kind_id=${TEMPLATE_KIND_ID}"

        else

            error "${TEMPLATE_NAME} has incorrect template kind."
            record_failure "${TEMPLATE_NAME} kind verification"

        fi

    else

        error "${TEMPLATE_NAME} returned invalid JSON."
        record_failure "${TEMPLATE_NAME} verification"

    fi

done

###############################################################################
# OS Template Mapping Verification
###############################################################################

header "OS Template Mapping Verification"

verify_mapping()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    api_request \
        GET \
        "${API_BASE}/operatingsystems?search=name%3D%22${OS_NAME}%22&per_page=all"

    OS_ID="$(
        "${JQ}" -r \
            --arg NAME "${OS_NAME}" \
            '.results[] | select(.name==$NAME) | .id' \
            "${API_BODY_FILE}" 2>/dev/null |
            "${HEAD}" -1
    )"

    if [ -z "${OS_ID}" ]
    then
        error "${OS_NAME} not found."
        record_failure "${OS_NAME} mapping"
        return
    fi

    api_request \
        GET \
        "${API_BASE}/operatingsystems/${OS_ID}/provisioning_templates?per_page=all"

    if json_valid &&
       "${JQ}" -e \
           --arg NAME "${TEMPLATE_NAME}" \
           '.results[] | select(.name==$NAME)' \
           "${API_BODY_FILE}" >/dev/null 2>&1
    then

        ok "${OS_NAME} -> ${TEMPLATE_NAME}"

    else

        error "${OS_NAME} -> ${TEMPLATE_NAME} mapping missing."
        record_failure "${OS_NAME} mapping"

    fi
}

verify_mapping \
    "${OS_CENTOS_RAID}" \
    "PXEGrub2 CentOS UEFI RAID Kickstart"

verify_mapping \
    "${OS_CENTOS_SINGLE}" \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

verify_mapping \
    "${OS_ROCKY8_RAID}" \
    "PXEGrub2 Rocky8 UEFI RAID Kickstart"

verify_mapping \
    "${OS_ROCKY8_SINGLE}" \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

verify_mapping \
    "${OS_ROCKY92_RAID}" \
    "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

verify_mapping \
    "${OS_ROCKY92_SINGLE}" \
    "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

verify_mapping \
    "${OS_ROCKY98_RAID}" \
    "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

verify_mapping \
    "${OS_ROCKY98_SINGLE}" \
    "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

###############################################################################
# Default Template Verification
###############################################################################

header "PXEGrub2 Default Template Verification"

verify_default()
{
    OS_NAME="$1"
    EXPECTED_TEMPLATE="$2"

    api_request \
        GET \
        "${API_BASE}/operatingsystems?search=name%3D%22${OS_NAME}%22&per_page=all"

    OS_ID="$(
        "${JQ}" -r \
            --arg NAME "${OS_NAME}" \
            '.results[] | select(.name==$NAME) | .id' \
            "${API_BODY_FILE}" 2>/dev/null |
            "${HEAD}" -1
    )"

    if [ -z "${OS_ID}" ]
    then
        error "${OS_NAME} not found."
        record_failure "${OS_NAME} default verification"
        return
    fi

    api_request \
        GET \
        "${API_BASE}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"

    DEFAULT_TEMPLATE="$(
        "${JQ}" -r \
            --argjson KIND "${PXEGRUB2_KIND_ID}" \
            '.results[] |
             select(.template_kind_id==$KIND) |
             .provisioning_template_name' \
            "${API_BODY_FILE}" 2>/dev/null |
            "${HEAD}" -1
    )"

    if [ "${DEFAULT_TEMPLATE}" = "${EXPECTED_TEMPLATE}" ]
    then

        ok "${OS_NAME} default -> ${EXPECTED_TEMPLATE}"

    else

        error "${OS_NAME} default incorrect."
        echo "Expected : ${EXPECTED_TEMPLATE}"
        echo "Actual   : ${DEFAULT_TEMPLATE:-<none>}"

        record_failure "${OS_NAME} default verification"

    fi
}

verify_default \
    "${OS_CENTOS_RAID}" \
    "PXEGrub2 CentOS UEFI RAID Kickstart"

verify_default \
    "${OS_CENTOS_SINGLE}" \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

verify_default \
    "${OS_ROCKY8_RAID}" \
    "PXEGrub2 Rocky8 UEFI RAID Kickstart"

verify_default \
    "${OS_ROCKY8_SINGLE}" \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

verify_default \
    "${OS_ROCKY92_RAID}" \
    "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

verify_default \
    "${OS_ROCKY92_SINGLE}" \
    "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

verify_default \
    "${OS_ROCKY98_RAID}" \
    "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

verify_default \
    "${OS_ROCKY98_SINGLE}" \
    "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

###############################################################################
# PXEGrub2 Template List
###############################################################################

header "PXEGrub2 Templates"

api_request \
    GET \
    "${API_BASE}/provisioning_templates?per_page=all"

if json_valid
then

    "${JQ}" -r '
        .results[] |
        select(.template_kind_name=="PXEGrub2") |
        [
            .id,
            .name,
            .template_kind_name
        ] |
        @tsv
    ' "${API_BODY_FILE}"

else

    show_api_error

fi

###############################################################################
# Final Operating System Verification
###############################################################################

header "Final Operating System Verification"

for OS_NAME in \
    "${OS_CENTOS_RAID}" \
    "${OS_CENTOS_SINGLE}" \
    "${OS_ROCKY8_RAID}" \
    "${OS_ROCKY8_SINGLE}" \
    "${OS_ROCKY92_RAID}" \
    "${OS_ROCKY92_SINGLE}" \
    "${OS_ROCKY98_RAID}" \
    "${OS_ROCKY98_SINGLE}"
do

    api_request \
        GET \
        "${API_BASE}/operatingsystems?search=name%3D%22${OS_NAME}%22&per_page=all"

    OS_ID="$(
        "${JQ}" -r \
            --arg NAME "${OS_NAME}" \
            '.results[] | select(.name==$NAME) | .id' \
            "${API_BODY_FILE}" 2>/dev/null |
            "${HEAD}" -1
    )"

    if [ -z "${OS_ID}" ]
    then
        error "${OS_NAME} not found."
        continue
    fi

    api_request \
        GET \
        "${API_BASE}/operatingsystems/${OS_ID}"

    if json_valid
    then

        echo
        echo "------------------------------------------------------------"
        echo "OS : ${OS_NAME}"
        echo "ID : ${OS_ID}"
        echo "------------------------------------------------------------"

        "${JQ}" -r '
            "Name          : \(.name)",
            "Title         : \(.title)",
            "Major         : \(.major)",
            "Minor         : \(.minor)",
            "Family        : \(.family)",
            "Architecture  : " + (
                [.architectures[]?.name] | join(", ")
            ),
            "Media         : " + (
                [.media[]?.name] | join(", ")
            ),
            "Ptable        : " + (
                [.ptables[]?.name] | join(", ")
            ),
            "Templates     : " + (
                [.provisioning_templates[]?.name] | join(", ")
            )
        ' "${API_BODY_FILE}"

    else

        error "${OS_NAME} verification returned invalid JSON."

    fi

done

###############################################################################
# Generated Files
###############################################################################

header "Generated PXE Template Files"

ls -lh "${WORK_DIR}"/*.erb 2>/dev/null

###############################################################################
# Authentication Information
###############################################################################

header "Authentication"

echo "Method        : Foreman REST API"
echo "Username      : ${FOREMAN_USER}"
echo "Authentication: Personal Access Token"
echo "Hammer        : NOT USED"
echo "curl          : USED"
echo "API           : ${API_BASE}"

###############################################################################
# Manual API Verification
###############################################################################

header "Manual API Verification"

echo
echo "Foreman status:"
echo
echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  ${API_BASE}/status"
echo

echo "Template kinds:"
echo
echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API_BASE}/template_kinds?per_page=all' | jq"
echo

echo "PXEGrub2 templates:"
echo
echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API_BASE}/provisioning_templates?per_page=all' | jq"
echo

echo "Operating systems:"
echo
echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API_BASE}/operatingsystems?per_page=all' | jq"
echo

echo "Subnets:"
echo
echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API_BASE}/subnets?per_page=all' | jq"
echo

###############################################################################
# Final Status
###############################################################################

header "01 - Foreman PXE Bootstrap API Completed"

if [ "${#FAILED_STEPS[@]}" -eq 0 ]
then

    ok "Bootstrap completed successfully."
    echo
    ok "Installation Media       : OK"
    ok "Operating Systems        : OK"
    ok "PXEGrub2 Templates       : OK"
    ok "OS Template Associations : OK"
    ok "PXEGrub2 Defaults        : OK"
    ok "PXE Subnets              : OK"
    ok "Verification              : OK"

    exit 0

else

    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

    echo

    for STEP in "${FAILED_STEPS[@]}"
    do
        error "${STEP}"
    done

    exit 1

fi
