#!/bin/bash
###############################################################################
# 01 - Foreman PXE Bootstrap - REST API
#
# Purpose:
#   Configure Foreman PXE provisioning using REST API + Personal Access Token.
#
# Authentication:
#   FOREMAN_USER  = Foreman username
#   FOREMAN_TOKEN = Foreman Personal Access Token
#
# Example:
#   export FOREMAN_USER="admin"
#   export FOREMAN_TOKEN="YOUR_PAT"
#   ./01_foreman_pxe_bootstrap_api.sh
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
MAGENTA='\033[1;35m'
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
    echo -e "${MAGENTA}------------------------------------------------------------${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${MAGENTA}------------------------------------------------------------${NC}"
}

###############################################################################
# Configuration
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
API="${FOREMAN_URL}/api"

FOREMAN_USER="${FOREMAN_USER:-admin}"

###############################################################################
# Personal Access Token
#
# IMPORTANT:
# Do NOT hardcode the PAT in this script.
#
# Export it before running:
#
#   export FOREMAN_TOKEN='YOUR_PAT'
#
###############################################################################

FOREMAN_TOKEN="${FOREMAN_TOKEN:-}"

if [ -z "${FOREMAN_TOKEN}" ]
then
    echo
    read -rsp "Enter Foreman Personal Access Token: " FOREMAN_TOKEN
    echo

    if [ -z "${FOREMAN_TOKEN}" ]
    then
        error "FOREMAN_TOKEN is empty."
        exit 1
    fi
fi

###############################################################################
# Temporary Files
###############################################################################

TMP_DIR="/tmp/foreman-pxe-bootstrap"

mkdir -p "${TMP_DIR}"

###############################################################################
# Dependency Check
###############################################################################

header "Dependency Check"

for CMD in curl jq
do
    if command -v "${CMD}" >/dev/null 2>&1
    then
        ok "${CMD} found: $(command -v "${CMD}")"
    else
        error "${CMD} command not found."
        exit 1
    fi
done

###############################################################################
# API Variables
###############################################################################

API_RESPONSE=""
API_HTTP_STATUS=""

###############################################################################
# REST API Request
#
# IMPORTANT:
# API_RESPONSE and API_HTTP_STATUS are intentionally assigned in the
# current shell. Do NOT call this function using:
#
#   RESPONSE="$(api_request ...)"
#
# because command substitution creates a subshell.
###############################################################################

api_request()
{
    METHOD="$1"
    URL="$2"
    DATA="$3"

    API_BODY_FILE="${TMP_DIR}/api_response.body"
    API_HEADER_FILE="${TMP_DIR}/api_response.headers"

    rm -f "${API_BODY_FILE}" "${API_HEADER_FILE}"

    if [ "${METHOD}" = "GET" ]
    then

        API_HTTP_STATUS="$(
            curl -k -sS \
                -o "${API_BODY_FILE}" \
                -D "${API_HEADER_FILE}" \
                -w '%{http_code}' \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                -H 'Accept: application/json,version=2' \
                "${URL}"
        )"

    elif [ "${METHOD}" = "DELETE" ]
    then

        API_HTTP_STATUS="$(
            curl -k -sS \
                -o "${API_BODY_FILE}" \
                -D "${API_HEADER_FILE}" \
                -w '%{http_code}' \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                -H 'Accept: application/json,version=2' \
                -X DELETE \
                "${URL}"
        )"

    else

        API_HTTP_STATUS="$(
            curl -k -sS \
                -o "${API_BODY_FILE}" \
                -D "${API_HEADER_FILE}" \
                -w '%{http_code}' \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                -H 'Accept: application/json,version=2' \
                -H 'Content-Type: application/json' \
                -X "${METHOD}" \
                -d "${DATA}" \
                "${URL}"
        )"

    fi

    if [ -f "${API_BODY_FILE}" ]
    then
        API_RESPONSE="$(cat "${API_BODY_FILE}")"
    else
        API_RESPONSE=""
    fi
}

###############################################################################
# GET
###############################################################################

api_get()
{
    api_request "GET" "$1" ""
}

###############################################################################
# POST
###############################################################################

api_post()
{
    api_request "POST" "$1" "$2"
}

###############################################################################
# PUT
###############################################################################

api_put()
{
    api_request "PUT" "$1" "$2"
}

###############################################################################
# DELETE
###############################################################################

api_delete()
{
    api_request "DELETE" "$1" ""
}

###############################################################################
# Validate HTTP Status
###############################################################################

api_success()
{
    [[ "${API_HTTP_STATUS}" =~ ^2[0-9][0-9]$ ]]
}

###############################################################################
# Show API Error
###############################################################################

show_api_error()
{
    error "API request failed."
    error "HTTP Status : ${API_HTTP_STATUS}"
    error "Method      : ${1}"
    error "URL         : ${2}"

    if echo "${API_RESPONSE}" | jq empty >/dev/null 2>&1
    then
        echo "${API_RESPONSE}" | jq .
    else
        echo "${API_RESPONSE}"
    fi
}

###############################################################################
# JSON Escape Helper
###############################################################################

json_escape()
{
    printf '%s' "$1" | jq -Rs .
}

###############################################################################
# Foreman API Authentication Test
###############################################################################

header "Foreman API Authentication Test"

info "Testing Foreman REST API..."

api_get "${API}/status"

if [ "${API_HTTP_STATUS}" != "200" ]
then
    error "Foreman API authentication failed."
    error "HTTP Status : ${API_HTTP_STATUS}"

    if echo "${API_RESPONSE}" | jq empty >/dev/null 2>&1
    then
        echo "${API_RESPONSE}" | jq .
    else
        echo "${API_RESPONSE}"
    fi

    exit 1
fi

FOREMAN_VERSION="$(
    echo "${API_RESPONSE}" |
    jq -r '.version // empty'
)"

API_VERSION="$(
    echo "${API_RESPONSE}" |
    jq -r '.api_version // empty'
)"

API_STATUS="$(
    echo "${API_RESPONSE}" |
    jq -r '.status // empty'
)"

if [ "${API_STATUS}" = "200" ]
then
    ok "Foreman API authentication successful."
else
    error "Foreman API returned unexpected status."
    echo "${API_RESPONSE}"
    exit 1
fi

echo "Foreman Version : ${FOREMAN_VERSION}"
echo "API Version     : ${API_VERSION}"
echo "API Status      : ${API_STATUS}"

###############################################################################
# Architecture
###############################################################################

ARCH_ID=""

api_get "${API}/architectures?per_page=all"

if api_success
then
    ARCH_ID="$(
        echo "${API_RESPONSE}" |
        jq -r '
            .results[]
            | select(.name == "x86_64")
            | .id
        ' |
        head -1
    )"
fi

if [ -z "${ARCH_ID}" ]
then
    error "x86_64 architecture not found."
    record_failure "x86_64 architecture"
else
    ok "x86_64 architecture found. ID=${ARCH_ID}"
fi

###############################################################################
# Installation Media Definitions
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

get_media_id()
{
    MEDIA_NAME="$1"

    api_get "${API}/media?search=$(printf '%s' "name=\"${MEDIA_NAME}\"" | sed 's/ /%20/g')&per_page=all"

    if ! api_success
    then
        echo ""
        return
    fi

    echo "${API_RESPONSE}" |
        jq -r --arg NAME "${MEDIA_NAME}" '
            .results[]
            | select(.name == $NAME)
            | .id
        ' |
        head -1
}

###############################################################################
# Create/Verify Media
###############################################################################

create_media()
{
    MEDIA_NAME="$1"
    MEDIA_PATH="$2"

    echo
    info "Checking Installation Media : ${MEDIA_NAME}"

    MEDIA_ID="$(get_media_id "${MEDIA_NAME}")"

    if [ -n "${MEDIA_ID}" ]
    then
        skip "${MEDIA_NAME} already exists. ID=${MEDIA_ID}"

        api_get "${API}/media/${MEDIA_ID}"

        if api_success
        then
            CURRENT_PATH="$(
                echo "${API_RESPONSE}" |
                jq -r '.path // empty'
            )"

            if [ "${CURRENT_PATH}" = "${MEDIA_PATH}" ]
            then
                ok "${MEDIA_NAME} path verified."
            else
                warn "${MEDIA_NAME} path differs."
                info "Updating media path..."

                PAYLOAD="$(
                    jq -n \
                    --arg PATH "${MEDIA_PATH}" \
                    '{
                        medium: {
                            path: $PATH
                        }
                    }'
                )"

                api_put "${API}/media/${MEDIA_ID}" "${PAYLOAD}"

                if api_success
                then
                    ok "${MEDIA_NAME} path updated."
                else
                    show_api_error "PUT" "${API}/media/${MEDIA_ID}"
                    record_failure "${MEDIA_NAME} path update"
                fi
            fi
        fi

        echo "${MEDIA_ID}"
        return
    fi

    info "Creating ${MEDIA_NAME}"

    PAYLOAD="$(
        jq -n \
        --arg NAME "${MEDIA_NAME}" \
        --arg PATH "${MEDIA_PATH}" \
        '{
            medium: {
                name: $NAME,
                path: $PATH
            }
        }'
    )"

    api_post "${API}/media" "${PAYLOAD}"

    if api_success
    then
        MEDIA_ID="$(
            echo "${API_RESPONSE}" |
            jq -r '.id // empty'
        )"

        ok "${MEDIA_NAME} created. ID=${MEDIA_ID}"
    else
        show_api_error "POST" "${API}/media"
        record_failure "${MEDIA_NAME}"
        MEDIA_ID=""
    fi

    echo "${MEDIA_ID}"
}

###############################################################################
# Installation Media
###############################################################################

header "Creating Installation Media"

CENTOS_MEDIA_ID="$(create_media \
    "${CENTOS_MEDIA_NAME}" \
    "${CENTOS_MEDIA_PATH}")"

ROCKY8_MEDIA_ID="$(create_media \
    "${ROCKY8_MEDIA_NAME}" \
    "${ROCKY8_MEDIA_PATH}")"

ROCKY92_MEDIA_ID="$(create_media \
    "${ROCKY92_MEDIA_NAME}" \
    "${ROCKY92_MEDIA_PATH}")"

ROCKY98_MEDIA_ID="$(create_media \
    "${ROCKY98_MEDIA_NAME}" \
    "${ROCKY98_MEDIA_PATH}")"

###############################################################################
# Installation Media Verification
###############################################################################

header "Installation Media Verification"

api_get "${API}/media?per_page=all"

if api_success
then
    echo "${API_RESPONSE}" |
        jq -r '
            .results[] |
            [
                .id,
                .name,
                .path
            ] |
            @tsv
        ' |
        column -t -s $'\t'
else
    show_api_error "GET" "${API}/media?per_page=all"
    record_failure "Installation media verification"
fi

###############################################################################
# Partition Table
###############################################################################

PTABLE_ID=""

api_get "${API}/ptables?per_page=all"

if api_success
then
    PTABLE_ID="$(
        echo "${API_RESPONSE}" |
        jq -r '
            .results[]
            | select(.name == "Kickstart default")
            | .id
        ' |
        head -1
    )"
fi

if [ -z "${PTABLE_ID}" ]
then
    error "Kickstart default partition table not found."
    record_failure "Kickstart default partition table"
else
    ok "Kickstart default partition table found. ID=${PTABLE_ID}"
fi

###############################################################################
# Operating System Definitions
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
# Get Operating System ID
###############################################################################

get_os_id()
{
    OS_NAME="$1"

    api_get "${API}/operatingsystems?search=$(printf '%s' "name=\"${OS_NAME}\"" | sed 's/ /%20/g')&per_page=all"

    if ! api_success
    then
        echo ""
        return
    fi

    echo "${API_RESPONSE}" |
        jq -r --arg NAME "${OS_NAME}" '
            .results[]
            | select(.name == $NAME)
            | .id
        ' |
        head -1
}

###############################################################################
# Create Operating System
###############################################################################

create_os()
{
    OS_NAME="$1"
    OS_MAJOR="$2"
    OS_MINOR="$3"
    MEDIA_ID="$4"

    echo
    info "Checking OS : ${OS_NAME}"

    OS_ID="$(get_os_id "${OS_NAME}")"

    if [ -n "${OS_ID}" ]
    then
        skip "${OS_NAME} already exists. ID=${OS_ID}"
        echo "${OS_ID}"
        return
    fi

    info "Creating ${OS_NAME}"

    PAYLOAD="$(
        jq -n \
        --arg NAME "${OS_NAME}" \
        --arg MAJOR "${OS_MAJOR}" \
        --arg MINOR "${OS_MINOR}" \
        --arg FAMILY "Redhat" \
        --argjson ARCH_ID "${ARCH_ID:-null}" \
        --argjson MEDIA_ID "${MEDIA_ID:-null}" \
        --argjson PTABLE_ID "${PTABLE_ID:-null}" \
        '{
            operatingsystem: {
                name: $NAME,
                major: $MAJOR,
                family: $FAMILY,
                architecture_ids: [$ARCH_ID],
                media_ids: [$MEDIA_ID],
                ptable_ids: [$PTABLE_ID]
            }
        }
        | if $MINOR != "" then
              .operatingsystem.minor = $MINOR
          else
              .
          end'
    )"

    api_post "${API}/operatingsystems" "${PAYLOAD}"

    if api_success
    then
        OS_ID="$(
            echo "${API_RESPONSE}" |
            jq -r '.id // empty'
        )"

        ok "${OS_NAME} created. ID=${OS_ID}"
    else
        show_api_error "POST" "${API}/operatingsystems"
        record_failure "${OS_NAME}"
        OS_ID=""
    fi

    echo "${OS_ID}"
}

###############################################################################
# Create Operating Systems
###############################################################################

header "Creating Operating Systems"

CENTOS_RAID_ID="$(
    create_os \
        "${CENTOS_RAID_OS}" \
        "7" \
        "" \
        "${CENTOS_MEDIA_ID}"
)"

CENTOS_SINGLE_ID="$(
    create_os \
        "${CENTOS_SINGLE_OS}" \
        "7" \
        "" \
        "${CENTOS_MEDIA_ID}"
)"

ROCKY8_RAID_ID="$(
    create_os \
        "${ROCKY8_RAID_OS}" \
        "8" \
        "10" \
        "${ROCKY8_MEDIA_ID}"
)"

ROCKY8_SINGLE_ID="$(
    create_os \
        "${ROCKY8_SINGLE_OS}" \
        "8" \
        "10" \
        "${ROCKY8_MEDIA_ID}"
)"

ROCKY92_RAID_ID="$(
    create_os \
        "${ROCKY92_RAID_OS}" \
        "9" \
        "2" \
        "${ROCKY92_MEDIA_ID}"
)"

ROCKY92_SINGLE_ID="$(
    create_os \
        "${ROCKY92_SINGLE_OS}" \
        "9" \
        "2" \
        "${ROCKY92_MEDIA_ID}"
)"

ROCKY98_RAID_ID="$(
    create_os \
        "${ROCKY98_RAID_OS}" \
        "9" \
        "8" \
        "${ROCKY98_MEDIA_ID}"
)"

ROCKY98_SINGLE_ID="$(
    create_os \
        "${ROCKY98_SINGLE_OS}" \
        "9" \
        "8" \
        "${ROCKY98_MEDIA_ID}"
)"

###############################################################################
# Operating System Verification
###############################################################################

header "Operating System Verification"

api_get "${API}/operatingsystems?per_page=all"

if api_success
then
    echo "${API_RESPONSE}" |
        jq -r '
            .results[]
            | select(
                .name == "CentOSLinux7-RAID" or
                .name == "CentOSLinux7-SingleDisk" or
                .name == "RockyLinux8.10-RAID" or
                .name == "RockyLinux8.10-SingleDisk" or
                .name == "RockyLinux9.2-RAID" or
                .name == "RockyLinux9.2-SingleDisk" or
                .name == "RockyLinux9.8-RAID" or
                .name == "RockyLinux9.8-SingleDisk"
            )
            |
            [
                .id,
                .name,
                .major,
                .minor,
                .family
            ] |
            @tsv
        ' |
        column -t -s $'\t'
else
    show_api_error "GET" "${API}/operatingsystems?per_page=all"
    record_failure "Operating system verification"
fi

###############################################################################
# Template Files
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

menuentry 'Install CentOS 7 RAID1' {
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

menuentry 'Install Rocky Linux 8.10 RAID1' {
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

menuentry 'Install Rocky Linux 9.2 RAID1' {
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

menuentry 'Install Rocky Linux 9.8 RAID1' {
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

PXEGRUB2_KIND_ID=""

api_get "${API}/provisioning_template_kinds?per_page=all"

if api_success
then
    PXEGRUB2_KIND_ID="$(
        echo "${API_RESPONSE}" |
        jq -r '
            .results[]
            | select(.name == "PXEGrub2")
            | .id
        ' |
        head -1
    )"
fi

if [ -z "${PXEGRUB2_KIND_ID}" ]
then
    error "PXEGrub2 template kind not found."

    if echo "${API_RESPONSE}" | jq empty >/dev/null 2>&1
    then
        echo "${API_RESPONSE}" |
            jq -r '.results[] | [.id,.name] | @tsv' |
            column -t -s $'\t'
    fi

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
    "/tmp/centos-raid.erb"
    "/tmp/centos-singledisk.erb"
    "/tmp/rocky8-raid.erb"
    "/tmp/rocky8-singledisk.erb"
    "/tmp/rocky92-raid.erb"
    "/tmp/rocky92-singledisk.erb"
    "/tmp/rocky98-raid.erb"
    "/tmp/rocky98-singledisk.erb"
)

###############################################################################
# Get Template ID
###############################################################################

get_template_id()
{
    TEMPLATE_NAME="$1"

    api_get "${API}/provisioning_templates?per_page=all"

    if ! api_success
    then
        echo ""
        return
    fi

    echo "${API_RESPONSE}" |
        jq -r --arg NAME "${TEMPLATE_NAME}" '
            .results[]
            | select(.name == $NAME)
            | .id
        ' |
        head -1
}

###############################################################################
# Create/Update PXEGrub2 Template
###############################################################################

create_template()
{
    TEMPLATE_NAME="$1"
    TEMPLATE_FILE="$2"

    section "Checking PXEGrub2 template : ${TEMPLATE_NAME}"

    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -n "${TEMPLATE_ID}" ]
    then
        skip "${TEMPLATE_NAME} already exists. ID=${TEMPLATE_ID}"

        echo "${TEMPLATE_ID}"
        return
    fi

    if [ ! -f "${TEMPLATE_FILE}" ]
    then
        error "Template file not found : ${TEMPLATE_FILE}"
        record_failure "${TEMPLATE_NAME}"
        echo ""
        return
    fi

    info "Creating ${TEMPLATE_NAME}"

    TEMPLATE_CONTENT="$(cat "${TEMPLATE_FILE}")"

    PAYLOAD="$(
        jq -n \
        --arg NAME "${TEMPLATE_NAME}" \
        --arg TEMPLATE "${TEMPLATE_CONTENT}" \
        --argjson KIND_ID "${PXEGRUB2_KIND_ID:-null}" \
        '{
            provisioning_template: {
                name: $NAME,
                template: $TEMPLATE,
                template_kind_id: $KIND_ID
            }
        }'
    )"

    api_post "${API}/provisioning_templates" "${PAYLOAD}"

    if api_success
    then
        TEMPLATE_ID="$(
            echo "${API_RESPONSE}" |
            jq -r '.id // empty'
        )"

        ok "${TEMPLATE_NAME} created. ID=${TEMPLATE_ID}"
    else
        show_api_error "POST" "${API}/provisioning_templates"
        record_failure "${TEMPLATE_NAME}"
        TEMPLATE_ID=""
    fi

    echo "${TEMPLATE_ID}"
}

###############################################################################
# Create All Templates
###############################################################################

header "Creating PXEGrub2 Templates"

declare -A TEMPLATE_ID_MAP

for INDEX in "${!TEMPLATE_NAMES[@]}"
do
    NAME="${TEMPLATE_NAMES[$INDEX]}"
    FILE="${TEMPLATE_FILES[$INDEX]}"

    TEMPLATE_ID_MAP["${NAME}"]="$(create_template "${NAME}" "${FILE}")"
done

###############################################################################
# Associate Template with Operating System
###############################################################################

is_template_associated()
{
    OS_ID="$1"
    TEMPLATE_NAME="$2"

    api_get "${API}/operatingsystems/${OS_ID}/provisioning_templates?per_page=all"

    if ! api_success
    then
        return 1
    fi

    echo "${API_RESPONSE}" |
        jq -e --arg NAME "${TEMPLATE_NAME}" '
            .results[]
            | select(.name == $NAME)
        ' >/dev/null 2>&1
}

associate_template()
{
    OS_NAME="$1"
    OS_ID="$2"
    TEMPLATE_NAME="$3"
    TEMPLATE_ID="$4"

    section "Associating:
OS       : ${OS_NAME}
Template : ${TEMPLATE_NAME}"

    if [ -z "${OS_ID}" ]
    then
        error "Operating System ID is empty."
        record_failure "${OS_NAME} association"
        return
    fi

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template ID is empty."
        record_failure "${OS_NAME} -> ${TEMPLATE_NAME}"
        return
    fi

    if is_template_associated "${OS_ID}" "${TEMPLATE_NAME}"
    then
        skip "Template already associated."
        return
    fi

    info "Associating template..."

    PAYLOAD="$(
        jq -n \
        --argjson TEMPLATE_ID "${TEMPLATE_ID}" \
        '{
            provisioning_template_id: $TEMPLATE_ID
        }'
    )"

    api_post \
        "${API}/operatingsystems/${OS_ID}/provisioning_templates" \
        "${PAYLOAD}"

    if api_success
    then
        ok "Template associated with ${OS_NAME}."
    else
        show_api_error \
            "POST" \
            "${API}/operatingsystems/${OS_ID}/provisioning_templates"

        record_failure "${OS_NAME} -> ${TEMPLATE_NAME}"
    fi
}

###############################################################################
# Associate All Templates
###############################################################################

header "Associating PXEGrub2 Templates"

associate_template \
    "${CENTOS_RAID_OS}" \
    "${CENTOS_RAID_ID}" \
    "PXEGrub2 CentOS UEFI RAID Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 CentOS UEFI RAID Kickstart"]}"

associate_template \
    "${CENTOS_SINGLE_OS}" \
    "${CENTOS_SINGLE_ID}" \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 CentOS UEFI SingleDisk Kickstart"]}"

associate_template \
    "${ROCKY8_RAID_OS}" \
    "${ROCKY8_RAID_ID}" \
    "PXEGrub2 Rocky8 UEFI RAID Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky8 UEFI RAID Kickstart"]}"

associate_template \
    "${ROCKY8_SINGLE_OS}" \
    "${ROCKY8_SINGLE_ID}" \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"]}"

associate_template \
    "${ROCKY92_RAID_OS}" \
    "${ROCKY92_RAID_ID}" \
    "PXEGrub2 Rocky9.2 UEFI RAID Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky9.2 UEFI RAID Kickstart"]}"

associate_template \
    "${ROCKY92_SINGLE_OS}" \
    "${ROCKY92_SINGLE_ID}" \
    "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"]}"

associate_template \
    "${ROCKY98_RAID_OS}" \
    "${ROCKY98_RAID_ID}" \
    "PXEGrub2 Rocky9.8 UEFI RAID Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky9.8 UEFI RAID Kickstart"]}"

associate_template \
    "${ROCKY98_SINGLE_OS}" \
    "${ROCKY98_SINGLE_ID}" \
    "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"]}"

###############################################################################
# Default Template Handling
#
# Foreman has one default-template combination per OS + template kind.
#
# If one already exists:
#
#   GET existing default
#   |
#   +-- same template -> SKIP
#   |
#   +-- different template -> PUT
#
# If none exists:
#
#   POST new default
#
# This avoids:
#
#   template_kind_id has already been taken
###############################################################################

get_default_template_for_kind()
{
    OS_ID="$1"
    KIND_ID="$2"

    api_get \
        "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"

    if ! api_success
    then
        return 1
    fi

    echo "${API_RESPONSE}" |
        jq -r \
        --argjson KIND_ID "${KIND_ID}" '
            .results[]
            | select(.template_kind_id == $KIND_ID)
            | [
                .id,
                .provisioning_template_id,
                .template_kind_id,
                .template_kind_name,
                .provisioning_template_name
            ]
            | @tsv
        ' |
        head -1
}

set_default_template()
{
    OS_NAME="$1"
    OS_ID="$2"
    TEMPLATE_NAME="$3"
    TEMPLATE_ID="$4"

    section "Setting PXEGrub2 Default:
OS       : ${OS_NAME}
Template : ${TEMPLATE_NAME}"

    if [ -z "${OS_ID}" ]
    then
        error "Operating System ID is empty."
        record_failure "${OS_NAME} default template"
        return
    fi

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template ID is empty."
        record_failure "${OS_NAME} default template"
        return
    fi

    if [ -z "${PXEGRUB2_KIND_ID}" ]
    then
        error "PXEGrub2 template kind ID is empty."
        record_failure "${OS_NAME} default template"
        return
    fi

    EXISTING_DEFAULT="$(
        get_default_template_for_kind \
            "${OS_ID}" \
            "${PXEGRUB2_KIND_ID}"
    )"

    if [ -n "${EXISTING_DEFAULT}" ]
    then

        DEFAULT_ID="$(echo "${EXISTING_DEFAULT}" | awk -F'\t' '{print $1}')"
        DEFAULT_TEMPLATE_ID="$(echo "${EXISTING_DEFAULT}" | awk -F'\t' '{print $2}')"
        DEFAULT_TEMPLATE_NAME="$(echo "${EXISTING_DEFAULT}" | awk -F'\t' '{print $5}')"

        if [ "${DEFAULT_TEMPLATE_ID}" = "${TEMPLATE_ID}" ]
        then
            skip "PXEGrub2 default already correct."
            return
        fi

        warn "Existing PXEGrub2 default found:"
        echo "  Default ID     : ${DEFAULT_ID}"
        echo "  Current Template: ${DEFAULT_TEMPLATE_NAME}"
        echo "  Current ID     : ${DEFAULT_TEMPLATE_ID}"

        info "Updating existing PXEGrub2 default..."

        PAYLOAD="$(
            jq -n \
            --argjson TEMPLATE_ID "${TEMPLATE_ID}" \
            --argjson KIND_ID "${PXEGRUB2_KIND_ID}" \
            '{
                os_default_template: {
                    provisioning_template_id: $TEMPLATE_ID,
                    template_kind_id: $KIND_ID
                }
            }'
        )"

        api_put \
            "${API}/operatingsystems/${OS_ID}/os_default_templates/${DEFAULT_ID}" \
            "${PAYLOAD}"

        if api_success
        then
            ok "PXEGrub2 default updated."
        else
            show_api_error \
                "PUT" \
                "${API}/operatingsystems/${OS_ID}/os_default_templates/${DEFAULT_ID}"

            record_failure "${OS_NAME} default template"
        fi

        return
    fi

    info "No PXEGrub2 default found. Creating one..."

    PAYLOAD="$(
        jq -n \
        --argjson TEMPLATE_ID "${TEMPLATE_ID}" \
        --argjson KIND_ID "${PXEGRUB2_KIND_ID}" \
        '{
            os_default_template: {
                provisioning_template_id: $TEMPLATE_ID,
                template_kind_id: $KIND_ID
            }
        }'
    )"

    api_post \
        "${API}/operatingsystems/${OS_ID}/os_default_templates" \
        "${PAYLOAD}"

    if api_success
    then
        DEFAULT_ID="$(
            echo "${API_RESPONSE}" |
            jq -r '.id // empty'
        )"

        ok "PXEGrub2 default created. ID=${DEFAULT_ID}"
    else
        show_api_error \
            "POST" \
            "${API}/operatingsystems/${OS_ID}/os_default_templates"

        record_failure "${OS_NAME} default template"
    fi
}

###############################################################################
# Set All PXEGrub2 Defaults
###############################################################################

header "Setting PXEGrub2 Default Templates"

set_default_template \
    "${CENTOS_RAID_OS}" \
    "${CENTOS_RAID_ID}" \
    "PXEGrub2 CentOS UEFI RAID Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 CentOS UEFI RAID Kickstart"]}"

set_default_template \
    "${CENTOS_SINGLE_OS}" \
    "${CENTOS_SINGLE_ID}" \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 CentOS UEFI SingleDisk Kickstart"]}"

set_default_template \
    "${ROCKY8_RAID_OS}" \
    "${ROCKY8_RAID_ID}" \
    "PXEGrub2 Rocky8 UEFI RAID Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky8 UEFI RAID Kickstart"]}"

set_default_template \
    "${ROCKY8_SINGLE_OS}" \
    "${ROCKY8_SINGLE_ID}" \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"]}"

set_default_template \
    "${ROCKY92_RAID_OS}" \
    "${ROCKY92_RAID_ID}" \
    "PXEGrub2 Rocky9.2 UEFI RAID Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky9.2 UEFI RAID Kickstart"]}"

set_default_template \
    "${ROCKY92_SINGLE_OS}" \
    "${ROCKY92_SINGLE_ID}" \
    "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"]}"

set_default_template \
    "${ROCKY98_RAID_OS}" \
    "${ROCKY98_RAID_ID}" \
    "PXEGrub2 Rocky9.8 UEFI RAID Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky9.8 UEFI RAID Kickstart"]}"

set_default_template \
    "${ROCKY98_SINGLE_OS}" \
    "${ROCKY98_SINGLE_ID}" \
    "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"]}"

###############################################################################
# Domain
###############################################################################

DOMAIN_ID=""

api_get "${API}/domains?per_page=all"

if api_success
then
    DOMAIN_ID="$(
        echo "${API_RESPONSE}" |
        jq -r '
            .results[]
            | select(.name == "vgs.com")
            | .id
        ' |
        head -1
    )"
fi

if [ -z "${DOMAIN_ID}" ]
then
    error "Domain vgs.com not found."
    record_failure "Domain vgs.com"
else
    ok "Domain found : vgs.com ID=${DOMAIN_ID}"
fi

###############################################################################
# Proxy IDs
###############################################################################

CENTOS_PROXY_ID=""

api_get "${API}/smart_proxies?per_page=all"

if api_success
then
    CENTOS_PROXY_ID="$(
        echo "${API_RESPONSE}" |
        jq -r '
            .results[]
            | select(.name == "cent-07-01.vgs.com")
            | .id
        ' |
        head -1
    )"

    ROCKY_PROXY_ID="$(
        echo "${API_RESPONSE}" |
        jq -r '
            .results[]
            | select(.name == "cent-07-02.vgs.com")
            | .id
        ' |
        head -1
    )"
fi

if [ -z "${CENTOS_PROXY_ID}" ]
then
    error "Smart Proxy cent-07-01.vgs.com not found."
    record_failure "cent-07-01.vgs.com proxy"
else
    ok "TFTP/DHCP proxy found : cent-07-01.vgs.com ID=${CENTOS_PROXY_ID}"
fi

if [ -z "${ROCKY_PROXY_ID}" ]
then
    error "Smart Proxy cent-07-02.vgs.com not found."
    record_failure "cent-07-02.vgs.com proxy"
else
    ok "TFTP/DHCP proxy found : cent-07-02.vgs.com ID=${ROCKY_PROXY_ID}"
fi

###############################################################################
# Subnet Definitions
###############################################################################

CENTOS_SUBNET_NAME="vgs-subnet-centos"
ROCKY_SUBNET_NAME="vgs-subnet-rockyos"

SUBNET_NETWORK="192.168.253.0"
SUBNET_MASK="255.255.255.0"
SUBNET_GATEWAY="192.168.253.2"
SUBNET_DNS="192.168.253.1"

###############################################################################
# Get Subnet ID
###############################################################################

get_subnet_id()
{
    SUBNET_NAME="$1"

    api_get "${API}/subnets?per_page=all"

    if ! api_success
    then
        echo ""
        return
    fi

    echo "${API_RESPONSE}" |
        jq -r --arg NAME "${SUBNET_NAME}" '
            .results[]
            | select(.name == $NAME)
            | .id
        ' |
        head -1
}

###############################################################################
# Create/Update Subnet
###############################################################################

create_subnet()
{
    SUBNET_NAME="$1"
    PROXY_ID="$2"

    section "Subnet       : ${SUBNET_NAME}
Network      : ${SUBNET_NETWORK}
Mask         : ${SUBNET_MASK}
Gateway      : ${SUBNET_GATEWAY}
DNS          : ${SUBNET_DNS}"

    SUBNET_ID="$(get_subnet_id "${SUBNET_NAME}")"

    PAYLOAD="$(
        jq -n \
        --arg NAME "${SUBNET_NAME}" \
        --arg NETWORK "${SUBNET_NETWORK}" \
        --arg MASK "${SUBNET_MASK}" \
        --arg GATEWAY "${SUBNET_GATEWAY}" \
        --arg DNS "${SUBNET_DNS}" \
        --argjson DOMAIN_ID "${DOMAIN_ID:-null}" \
        --argjson PROXY_ID "${PROXY_ID:-null}" \
        '{
            subnet: {
                name: $NAME,
                network: $NETWORK,
                mask: $MASK,
                gateway: $GATEWAY,
                dns_primary: $DNS,
                domain_ids: [$DOMAIN_ID],
                tftp_id: $PROXY_ID,
                dhcp_id: $PROXY_ID
            }
        }'
    )"

    if [ -n "${SUBNET_ID}" ]
    then

        skip "${SUBNET_NAME} already exists. ID=${SUBNET_ID}"

        api_put "${API}/subnets/${SUBNET_ID}" "${PAYLOAD}"

        if api_success
        then
            ok "${SUBNET_NAME} updated."
        else
            show_api_error "PUT" "${API}/subnets/${SUBNET_ID}"
            record_failure "${SUBNET_NAME} update"
        fi

    else

        info "Creating ${SUBNET_NAME}"

        api_post "${API}/subnets" "${PAYLOAD}"

        if api_success
        then
            SUBNET_ID="$(
                echo "${API_RESPONSE}" |
                jq -r '.id // empty'
            )"

            ok "${SUBNET_NAME} created. ID=${SUBNET_ID}"
        else
            show_api_error "POST" "${API}/subnets"
            record_failure "${SUBNET_NAME}"
        fi
    fi

    echo "${SUBNET_ID}"
}

###############################################################################
# Create PXE Subnets
###############################################################################

header "Creating PXE Subnets"

CENTOS_SUBNET_ID="$(
    create_subnet \
        "${CENTOS_SUBNET_NAME}" \
        "${CENTOS_PROXY_ID}"
)"

ROCKY_SUBNET_ID="$(
    create_subnet \
        "${ROCKY_SUBNET_NAME}" \
        "${ROCKY_PROXY_ID}"
)"

###############################################################################
# PXE Subnet Verification
###############################################################################

header "PXE Subnet Verification"

api_get "${API}/subnets?per_page=all"

if api_success
then
    echo "${API_RESPONSE}" |
        jq -r '
            .results[]
            | select(
                .name == "vgs-subnet-centos" or
                .name == "vgs-subnet-rockyos"
            )
            |
            [
                .id,
                .name,
                (.network + "/" + (
                    if .mask == "255.255.255.0"
                    then "24"
                    else .mask
                    end
                )),
                (.dhcp.name // "NONE"),
                (.tftp.name // "NONE")
            ] |
            @tsv
        ' |
        column -t -s $'\t'
else
    show_api_error "GET" "${API}/subnets?per_page=all"
    record_failure "PXE subnet verification"
fi

###############################################################################
# PXEGrub2 Template Verification
###############################################################################

header "PXEGrub2 Template Verification"

api_get "${API}/provisioning_templates?per_page=all"

if api_success
then

    for TEMPLATE_NAME in "${TEMPLATE_NAMES[@]}"
    do

        TEMPLATE_INFO="$(
            echo "${API_RESPONSE}" |
            jq -r \
            --arg NAME "${TEMPLATE_NAME}" '
                .results[]
                | select(.name == $NAME)
                | [
                    .id,
                    .name,
                    .template_kind_id,
                    .template_kind_name
                ] |
                @tsv
            ' |
            head -1
        )"

        if [ -n "${TEMPLATE_INFO}" ]
        then
            echo "${TEMPLATE_INFO}" |
                awk -F'\t' \
                '{printf "[OK] %-55s | ID=%s | kind_id=%s | kind=%s\n",$2,$1,$3,$4}'
        else
            error "${TEMPLATE_NAME} not found."
            record_failure "${TEMPLATE_NAME} verification"
        fi

    done

else
    show_api_error "GET" "${API}/provisioning_templates?per_page=all"
    record_failure "PXEGrub2 template verification"
fi

###############################################################################
# OS Template Mapping Verification
###############################################################################

header "OS Template Mapping Verification"

verify_mapping()
{
    OS_NAME="$1"
    OS_ID="$2"
    TEMPLATE_NAME="$3"

    if [ -z "${OS_ID}" ]
    then
        error "${OS_NAME} -> OS ID missing."
        record_failure "${OS_NAME} mapping"
        return
    fi

    api_get "${API}/operatingsystems/${OS_ID}/provisioning_templates?per_page=all"

    if ! api_success
    then
        show_api_error \
            "GET" \
            "${API}/operatingsystems/${OS_ID}/provisioning_templates"

        record_failure "${OS_NAME} mapping"
        return
    fi

    if echo "${API_RESPONSE}" |
        jq -e --arg NAME "${TEMPLATE_NAME}" '
            .results[]
            | select(.name == $NAME)
        ' >/dev/null 2>&1
    then
        ok "${OS_NAME} -> ${TEMPLATE_NAME}"
    else
        error "${OS_NAME} -> ${TEMPLATE_NAME} missing."
        record_failure "${OS_NAME} -> ${TEMPLATE_NAME}"
    fi
}

verify_mapping \
    "${CENTOS_RAID_OS}" \
    "${CENTOS_RAID_ID}" \
    "PXEGrub2 CentOS UEFI RAID Kickstart"

verify_mapping \
    "${CENTOS_SINGLE_OS}" \
    "${CENTOS_SINGLE_ID}" \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

verify_mapping \
    "${ROCKY8_RAID_OS}" \
    "${ROCKY8_RAID_ID}" \
    "PXEGrub2 Rocky8 UEFI RAID Kickstart"

verify_mapping \
    "${ROCKY8_SINGLE_OS}" \
    "${ROCKY8_SINGLE_ID}" \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

verify_mapping \
    "${ROCKY92_RAID_OS}" \
    "${ROCKY92_RAID_ID}" \
    "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

verify_mapping \
    "${ROCKY92_SINGLE_OS}" \
    "${ROCKY92_SINGLE_ID}" \
    "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

verify_mapping \
    "${ROCKY98_RAID_OS}" \
    "${ROCKY98_RAID_ID}" \
    "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

verify_mapping \
    "${ROCKY98_SINGLE_OS}" \
    "${ROCKY98_SINGLE_ID}" \
    "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

###############################################################################
# PXEGrub2 Default Verification
###############################################################################

header "PXEGrub2 Default Template Verification"

verify_default()
{
    OS_NAME="$1"
    OS_ID="$2"
    TEMPLATE_NAME="$3"
    TEMPLATE_ID="$4"

    if [ -z "${OS_ID}" ]
    then
        error "${OS_NAME} default template: OS ID missing."
        record_failure "${OS_NAME} default verification"
        return
    fi

    api_get \
        "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"

    if ! api_success
    then
        show_api_error \
            "GET" \
            "${API}/operatingsystems/${OS_ID}/os_default_templates"

        record_failure "${OS_NAME} default verification"
        return
    fi

    DEFAULT_TEMPLATE_ID="$(
        echo "${API_RESPONSE}" |
        jq -r \
        --argjson KIND_ID "${PXEGRUB2_KIND_ID}" '
            .results[]
            | select(.template_kind_id == $KIND_ID)
            | .provisioning_template_id
        ' |
        head -1
    )"

    DEFAULT_TEMPLATE_NAME="$(
        echo "${API_RESPONSE}" |
        jq -r \
        --argjson KIND_ID "${PXEGRUB2_KIND_ID}" '
            .results[]
            | select(.template_kind_id == $KIND_ID)
            | .provisioning_template_name
        ' |
        head -1
    )"

    if [ "${DEFAULT_TEMPLATE_ID}" = "${TEMPLATE_ID}" ]
    then
        ok "${OS_NAME} default -> ${TEMPLATE_NAME}"
    else
        error "${OS_NAME} default template incorrect."
        error "Expected : ${TEMPLATE_NAME}"
        error "Actual   : ${DEFAULT_TEMPLATE_NAME:-NONE}"
        record_failure "${OS_NAME} default verification"
    fi
}

verify_default \
    "${CENTOS_RAID_OS}" \
    "${CENTOS_RAID_ID}" \
    "PXEGrub2 CentOS UEFI RAID Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 CentOS UEFI RAID Kickstart"]}"

verify_default \
    "${CENTOS_SINGLE_OS}" \
    "${CENTOS_SINGLE_ID}" \
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 CentOS UEFI SingleDisk Kickstart"]}"

verify_default \
    "${ROCKY8_RAID_OS}" \
    "${ROCKY8_RAID_ID}" \
    "PXEGrub2 Rocky8 UEFI RAID Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky8 UEFI RAID Kickstart"]}"

verify_default \
    "${ROCKY8_SINGLE_OS}" \
    "${ROCKY8_SINGLE_ID}" \
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"]}"

verify_default \
    "${ROCKY92_RAID_OS}" \
    "${ROCKY92_RAID_ID}" \
    "PXEGrub2 Rocky9.2 UEFI RAID Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky9.2 UEFI RAID Kickstart"]}"

verify_default \
    "${ROCKY92_SINGLE_OS}" \
    "${ROCKY92_SINGLE_ID}" \
    "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"]}"

verify_default \
    "${ROCKY98_RAID_OS}" \
    "${ROCKY98_RAID_ID}" \
    "PXEGrub2 Rocky9.8 UEFI RAID Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky9.8 UEFI RAID Kickstart"]}"

verify_default \
    "${ROCKY98_SINGLE_OS}" \
    "${ROCKY98_SINGLE_ID}" \
    "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart" \
    "${TEMPLATE_ID_MAP["PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"]}"

###############################################################################
# Final Operating System Verification
###############################################################################

header "Final Operating System Verification"

verify_os()
{
    OS_NAME="$1"
    OS_ID="$2"

    section "OS : ${OS_NAME}
ID : ${OS_ID}"

    if [ -z "${OS_ID}" ]
    then
        error "OS ID missing."
        return
    fi

    api_get "${API}/operatingsystems/${OS_ID}"

    if ! api_success
    then
        show_api_error \
            "GET" \
            "${API}/operatingsystems/${OS_ID}"

        record_failure "${OS_NAME} final verification"
        return
    fi

    echo "${API_RESPONSE}" |
        jq -r '
            "Name          : \(.name)",
            "Title         : \(.title)",
            "Major         : \(.major)",
            "Minor         : \(.minor)",
            "Family        : \(.family)",
            "Architecture  : \([.architectures[].name] | join(", "))",
            "Media         : \([.media[].name] | join(", "))",
            "Ptable        : \([.ptables[].name] | join(", "))",
            "Templates     : \([.provisioning_templates[].name] | join(", "))"
        '
}

verify_os "${CENTOS_RAID_OS}" "${CENTOS_RAID_ID}"
verify_os "${CENTOS_SINGLE_OS}" "${CENTOS_SINGLE_ID}"

verify_os "${ROCKY8_RAID_OS}" "${ROCKY8_RAID_ID}"
verify_os "${ROCKY8_SINGLE_OS}" "${ROCKY8_SINGLE_ID}"

verify_os "${ROCKY92_RAID_OS}" "${ROCKY92_RAID_ID}"
verify_os "${ROCKY92_SINGLE_OS}" "${ROCKY92_SINGLE_ID}"

verify_os "${ROCKY98_RAID_OS}" "${ROCKY98_RAID_ID}"
verify_os "${ROCKY98_SINGLE_OS}" "${ROCKY98_SINGLE_ID}"

###############################################################################
# PXEGrub2 Templates
###############################################################################

header "PXEGrub2 Templates"

api_get "${API}/provisioning_templates?per_page=all"

if api_success
then
    echo "${API_RESPONSE}" |
        jq -r '
            .results[]
            | select(.template_kind_name == "PXEGrub2")
            |
            [
                .id,
                .name,
                .template_kind_name,
                .template_kind_id
            ] |
            @tsv
        ' |
        column -t -s $'\t'
else
    show_api_error \
        "GET" \
        "${API}/provisioning_templates?per_page=all"
fi

###############################################################################
# PXE Subnets
###############################################################################

header "PXE Subnets"

api_get "${API}/subnets?per_page=all"

if api_success
then
    echo "${API_RESPONSE}" |
        jq -r '
            .results[]
            | select(
                .name == "vgs-subnet-centos" or
                .name == "vgs-subnet-rockyos"
            )
            |
            [
                .id,
                .name,
                .network,
                .mask,
                (.dhcp.name // "NONE"),
                (.tftp.name // "NONE")
            ] |
            @tsv
        ' |
        column -t -s $'\t'
else
    show_api_error "GET" "${API}/subnets?per_page=all"
fi

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
echo "------------------------------------------------------------"
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  ${API}/status"
echo

echo "PXEGrub2 templates:"
echo "------------------------------------------------------------"
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/provisioning_templates?per_page=all' | jq"
echo

echo "Operating systems:"
echo "------------------------------------------------------------"
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/operatingsystems?per_page=all' | jq"
echo

echo "Subnets:"
echo "------------------------------------------------------------"
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/subnets?per_page=all' | jq"
echo

###############################################################################
# Expected Configuration
###############################################################################

header "Expected PXE Configuration"

cat <<'EOF'

Installation Media
|
+-- CentOS 7 Remote
|   +-- http://192.168.253.136/repo/centos/
|
+-- Rocky 8 Remote
|   +-- http://192.168.253.136/repo/rocky8/
|
+-- Rocky 9.2 Remote
|   +-- http://192.168.253.136/repo/rocky9.2/
|
+-- Rocky 9 Remote
    +-- http://192.168.253.136/repo/rocky9/


Operating Systems
|
+-- CentOSLinux7-RAID
|   +-- PXEGrub2 CentOS UEFI RAID Kickstart
|
+-- CentOSLinux7-SingleDisk
|   +-- PXEGrub2 CentOS UEFI SingleDisk Kickstart
|
+-- RockyLinux8.10-RAID
|   +-- PXEGrub2 Rocky8 UEFI RAID Kickstart
|
+-- RockyLinux8.10-SingleDisk
|   +-- PXEGrub2 Rocky8 UEFI SingleDisk Kickstart
|
+-- RockyLinux9.2-RAID
|   +-- PXEGrub2 Rocky9.2 UEFI RAID Kickstart
|
+-- RockyLinux9.2-SingleDisk
|   +-- PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart
|
+-- RockyLinux9.8-RAID
|   +-- PXEGrub2 Rocky9.8 UEFI RAID Kickstart
|
+-- RockyLinux9.8-SingleDisk
    +-- PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart


PXE Subnets
|
+-- vgs-subnet-centos
|   +-- 192.168.253.0/24
|   +-- DHCP = cent-07-01.vgs.com
|   +-- TFTP = cent-07-01.vgs.com
|
+-- vgs-subnet-rockyos
    +-- 192.168.253.0/24
    +-- DHCP = cent-07-02.vgs.com
    +-- TFTP = cent-07-02.vgs.com

EOF

###############################################################################
# Final Status
###############################################################################

header "01 - Foreman PXE Bootstrap API Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]
then

    ok "Foreman PXE Bootstrap completed successfully."
    echo
    ok "PAT authentication      : SUCCESS"
    ok "Installation Media     : SUCCESS"
    ok "Operating Systems      : SUCCESS"
    ok "PXEGrub2 Templates     : SUCCESS"
    ok "OS Template Mapping    : SUCCESS"
    ok "PXEGrub2 Defaults      : SUCCESS"
    ok "PXE Subnets            : SUCCESS"
    ok "Final Verification     : SUCCESS"

else

    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

    echo

    for STEP in "${FAILED_STEPS[@]}"
    do
        error "${STEP}"
    done

    echo
    warn "Review the errors above before using PXE provisioning."

fi

###############################################################################
# Exit
###############################################################################

if [ ${#FAILED_STEPS[@]} -eq 0 ]
then
    exit 0
else
    exit 1
fi
