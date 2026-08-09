#!/bin/bash
###############################################################################
# 01 - Foreman PXE Bootstrap - REST API
#
# Foreman 3.2.1
# Katello compatible
#
# NO HAMMER
# Direct Foreman REST API using curl + jq
#
# Creates / verifies:
#
#   Installation Media
#   Operating Systems
#   PXEGrub2 Provisioning Templates
#   OS <-> Provisioning Template associations
#   PXEGrub2 OS default templates
#   Domains
#   Smart Proxies
#   PXE Subnets
#
# Supported:
#
#   CentOS 7
#   Rocky Linux 8.10
#   Rocky Linux 9.2
#   Rocky Linux 9.8
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

###############################################################################
# Configuration
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_TOKEN="${FOREMAN_TOKEN:-}"

if [ -z "${FOREMAN_TOKEN}" ]
then

    error "FOREMAN_TOKEN is not set."

    echo
    echo "Set the Foreman Personal Access Token:"
    echo
    echo "export FOREMAN_USER='admin'"
    echo "export FOREMAN_TOKEN='YOUR_TOKEN'"
    echo

    exit 1

fi

FOREMAN_INSECURE="${FOREMAN_INSECURE:-true}"

API="${FOREMAN_URL}/api"

###############################################################################
# Required Commands
###############################################################################

if ! command -v curl >/dev/null 2>&1
then
    error "curl is not installed."
    exit 1
fi

if ! command -v jq >/dev/null 2>&1
then
    error "jq is not installed."
    echo "Install with: dnf install -y jq"
    exit 1
fi

###############################################################################
# CURL SSL
###############################################################################

CURL_SSL=""

if [ "${FOREMAN_INSECURE}" = "true" ]
then
    CURL_SSL="-k"
fi

###############################################################################
# API Request
###############################################################################

api_request()
{
    METHOD="$1"
    URL="$2"
    DATA="${3:-}"

    RESPONSE_FILE="$(mktemp)"

    if [ -n "${DATA}" ]
    then

        HTTP_CODE="$(
            curl \
                -sS \
                ${CURL_SSL} \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                --request "${METHOD}" \
                --header "Accept: application/json,version=2" \
                --header "Content-Type: application/json" \
                --data "${DATA}" \
                --output "${RESPONSE_FILE}" \
                --write-out "%{http_code}" \
                "${URL}"
        )"

    else

        HTTP_CODE="$(
            curl \
                -sS \
                ${CURL_SSL} \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                --request "${METHOD}" \
                --header "Accept: application/json,version=2" \
                --header "Content-Type: application/json" \
                --output "${RESPONSE_FILE}" \
                --write-out "%{http_code}" \
                "${URL}"
        )"

    fi

    RESPONSE="$(cat "${RESPONSE_FILE}")"

    rm -f "${RESPONSE_FILE}"

    if [[ "${HTTP_CODE}" =~ ^2[0-9][0-9]$ ]]
    then

        echo "${RESPONSE}"
        return 0

    fi

    echo "${RESPONSE}" >&2

    error "API request failed."
    error "HTTP Status : ${HTTP_CODE}"
    error "Method      : ${METHOD}"
    error "URL         : ${URL}"

    return 1
}

###############################################################################
# API GET
###############################################################################

api_get()
{
    api_request GET "$1"
}

###############################################################################
# API POST
###############################################################################

api_post()
{
    api_request POST "$1" "$2"
}

###############################################################################
# API PUT
###############################################################################

api_put()
{
    api_request PUT "$1" "$2"
}

###############################################################################
# API DELETE
###############################################################################

api_delete()
{
    api_request DELETE "$1"
}

###############################################################################
# API Search
###############################################################################

api_search()
{
    RESOURCE="$1"
    SEARCH="$2"

    curl \
        -sS \
        ${CURL_SSL} \
        --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
        --header "Accept: application/json,version=2" \
        --get \
        --data-urlencode "search=${SEARCH}" \
        --data-urlencode "per_page=all" \
        "${API}/${RESOURCE}"
}

###############################################################################
# Foreman Header
###############################################################################

header "01 - Foreman PXE Bootstrap - REST API"

###############################################################################
# Authentication
###############################################################################

header "Foreman API Authentication Test"

info "Testing Foreman REST API..."

STATUS_RESPONSE="$(api_get "${API}/status")"

if [ $? -ne 0 ]
then

    error "Unable to access Foreman API."
    exit 1

fi

FOREMAN_VERSION="$(echo "${STATUS_RESPONSE}" | jq -r '.version // empty')"
API_VERSION="$(echo "${STATUS_RESPONSE}" | jq -r '.api_version // empty')"
API_STATUS="$(echo "${STATUS_RESPONSE}" | jq -r '.status // empty')"

if [ -n "${FOREMAN_VERSION}" ]
then

    ok "Foreman API authentication successful."

    echo "Foreman Version : ${FOREMAN_VERSION}"
    echo "API Version     : ${API_VERSION}"
    echo "API Status      : ${API_STATUS}"

else

    error "Unable to read Foreman API status."
    echo "${STATUS_RESPONSE}"

    exit 1

fi

###############################################################################
# Installation Media
###############################################################################

CENTOS_MEDIA="CentOS 7 Remote"
ROCKY8_MEDIA="Rocky 8 Remote"
ROCKY92_MEDIA="Rocky 9.2 Remote"
ROCKY98_MEDIA="Rocky 9 Remote"

CENTOS_MEDIA_URL="http://192.168.253.136/repo/centos/"
ROCKY8_MEDIA_URL="http://192.168.253.136/repo/rocky8/"
ROCKY92_MEDIA_URL="http://192.168.253.136/repo/rocky9.2/"
ROCKY98_MEDIA_URL="http://192.168.253.136/repo/rocky9/"

###############################################################################
# Operating Systems
###############################################################################

CENTOS_RAID_NAME="CentOSLinux7-RAID"
CENTOS_SINGLE_NAME="CentOSLinux7-SingleDisk"

ROCKY8_RAID_NAME="RockyLinux8.10-RAID"
ROCKY8_SINGLE_NAME="RockyLinux8.10-SingleDisk"

ROCKY92_RAID_NAME="RockyLinux9.2-RAID"
ROCKY92_SINGLE_NAME="RockyLinux9.2-SingleDisk"

ROCKY98_RAID_NAME="RockyLinux9.8-RAID"
ROCKY98_SINGLE_NAME="RockyLinux9.8-SingleDisk"

###############################################################################
# PXE Templates
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
# PXE Template Files
###############################################################################

CENTOS_RAID_FILE="/tmp/centos-raid.erb"
CENTOS_SINGLE_FILE="/tmp/centos-singledisk.erb"

ROCKY8_RAID_FILE="/tmp/rocky8-raid.erb"
ROCKY8_SINGLE_FILE="/tmp/rocky8-singledisk.erb"

ROCKY92_RAID_FILE="/tmp/rocky92-raid.erb"
ROCKY92_SINGLE_FILE="/tmp/rocky92-singledisk.erb"

ROCKY98_RAID_FILE="/tmp/rocky98-raid.erb"
ROCKY98_SINGLE_FILE="/tmp/rocky98-singledisk.erb"

###############################################################################
# PXE Network
###############################################################################

CENTOS_SUBNET_NAME="vgs-subnet-centos"
ROCKY_SUBNET_NAME="vgs-subnet-rockyos"

SUBNET_NETWORK="192.168.253.0"
SUBNET_MASK="255.255.255.0"
SUBNET_GATEWAY="192.168.253.2"
SUBNET_DNS="192.168.253.1"

CENTOS_PROXY="cent-07-01.vgs.com"
ROCKY_PROXY="cent-07-02.vgs.com"

DOMAIN_NAME="vgs.com"

###############################################################################
# Find Media ID
###############################################################################

find_media_id()
{
    NAME="$1"

    RESPONSE="$(
        api_search \
            "media" \
            "name=\"${NAME}\""
    )"

    echo "${RESPONSE}" |
        jq -r '.results[0].id // empty'
}

###############################################################################
# Create / Verify Media
###############################################################################

create_media()
{
    NAME="$1"
    URL="$2"

    echo
    info "Checking Installation Media : ${NAME}"

    MEDIA_ID="$(find_media_id "${NAME}")"

    if [ -n "${MEDIA_ID}" ]
    then

        skip "${NAME} already exists. ID=${MEDIA_ID}"

        CURRENT_PATH="$(
            api_get "${API}/media/${MEDIA_ID}" |
            jq -r '.path // empty'
        )"

        if [ "${CURRENT_PATH}" != "${URL}" ]
        then

            info "Updating media path..."

            JSON="$(
                jq -n \
                    --arg path "${URL}" \
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

            if echo "${RESPONSE}" | jq -e '.error' >/dev/null 2>&1
            then

                error "Failed updating ${NAME} path."
                record_failure "${NAME} media path"

            else

                ok "${NAME} path updated."

            fi

        else

            ok "${NAME} path verified."

        fi

        return 0

    fi

    info "Creating ${NAME}"

    JSON="$(
        jq -n \
            --arg name "${NAME}" \
            --arg path "${URL}" \
            '{
                medium: {
                    name: $name,
                    path: $path,
                    os_family: "Redhat"
                }
            }'
    )"

    RESPONSE="$(
        api_post \
            "${API}/media" \
            "${JSON}"
    )"

    MEDIA_ID="$(echo "${RESPONSE}" | jq -r '.id // empty')"

    if [ -n "${MEDIA_ID}" ]
    then

        ok "${NAME} created. ID=${MEDIA_ID}"

    else

        error "Failed creating ${NAME}."
        echo "${RESPONSE}"

        record_failure "${NAME}"

    fi
}

###############################################################################
# Create Installation Media
###############################################################################

header "Creating Installation Media"

create_media "${CENTOS_MEDIA}" "${CENTOS_MEDIA_URL}"
create_media "${ROCKY8_MEDIA}" "${ROCKY8_MEDIA_URL}"
create_media "${ROCKY92_MEDIA}" "${ROCKY92_MEDIA_URL}"
create_media "${ROCKY98_MEDIA}" "${ROCKY98_MEDIA_URL}"

###############################################################################
# Installation Media Verification
###############################################################################

header "Installation Media Verification"

MEDIA_LIST="$(
    api_get "${API}/media?per_page=all"
)"

if [ $? -eq 0 ]
then

    echo "${MEDIA_LIST}" |
        jq -r '
            .results[] |
            "\(.id) | \(.name) | \(.path)"
        '

else

    error "Unable to list installation media."
    record_failure "Installation Media Verification"

fi

###############################################################################
# Architecture
###############################################################################

find_architecture_id()
{
    NAME="$1"

    RESPONSE="$(
        api_search \
            "architectures" \
            "name=\"${NAME}\""
    )"

    echo "${RESPONSE}" |
        jq -r '.results[0].id // empty'
}

ARCH_ID="$(find_architecture_id "x86_64")"

if [ -n "${ARCH_ID}" ]
then

    ok "x86_64 architecture found. ID=${ARCH_ID}"

else

    error "x86_64 architecture not found."
    record_failure "x86_64 architecture"

fi

###############################################################################
# Partition Table
###############################################################################

find_ptable_id()
{
    NAME="$1"

    RESPONSE="$(
        api_search \
            "ptables" \
            "name=\"${NAME}\""
    )"

    echo "${RESPONSE}" |
        jq -r '.results[0].id // empty'
}

PTABLE_ID="$(find_ptable_id "Kickstart default")"

if [ -n "${PTABLE_ID}" ]
then

    ok "Kickstart default partition table found. ID=${PTABLE_ID}"

else

    error "Kickstart default partition table not found."
    record_failure "Kickstart default partition table"

fi

###############################################################################
# Find OS
###############################################################################

find_os_id()
{
    NAME="$1"

    RESPONSE="$(
        api_search \
            "operatingsystems" \
            "name=\"${NAME}\""
    )"

    echo "${RESPONSE}" |
        jq -r '.results[0].id // empty'
}

###############################################################################
# Create OS
###############################################################################

create_os()
{
    OS_NAME="$1"
    MAJOR="$2"
    MINOR="$3"
    MEDIA_NAME="$4"

    echo
    info "Checking OS : ${OS_NAME}"

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -n "${OS_ID}" ]
    then

        skip "${OS_NAME} already exists. ID=${OS_ID}"
        return 0

    fi

    MEDIA_ID="$(find_media_id "${MEDIA_NAME}")"

    if [ -z "${MEDIA_ID}" ]
    then

        error "Media not found : ${MEDIA_NAME}"
        record_failure "${OS_NAME}"
        return 1

    fi

    if [ -z "${ARCH_ID}" ]
    then

        error "Architecture ID unavailable."
        record_failure "${OS_NAME}"
        return 1

    fi

    if [ -z "${PTABLE_ID}" ]
    then

        error "Partition table ID unavailable."
        record_failure "${OS_NAME}"
        return 1

    fi

    info "Creating ${OS_NAME}"

    JSON="$(
        jq -n \
            --arg name "${OS_NAME}" \
            --arg major "${MAJOR}" \
            --arg minor "${MINOR}" \
            --arg family "Redhat" \
            --argjson arch "${ARCH_ID}" \
            --argjson media "${MEDIA_ID}" \
            --argjson ptable "${PTABLE_ID}" \
            '{
                operatingsystem: {
                    name: $name,
                    major: $major,
                    minor: $minor,
                    family: $family,
                    architecture_ids: [$arch],
                    medium_ids: [$media],
                    ptable_ids: [$ptable]
                }
            }'
    )"

    RESPONSE="$(
        api_post \
            "${API}/operatingsystems" \
            "${JSON}"
    )"

    OS_ID="$(echo "${RESPONSE}" | jq -r '.id // empty')"

    if [ -n "${OS_ID}" ]
    then

        ok "${OS_NAME} created. ID=${OS_ID}"

    else

        error "Failed creating ${OS_NAME}."
        echo "${RESPONSE}"

        record_failure "${OS_NAME}"

    fi
}

###############################################################################
# Create Operating Systems
###############################################################################

header "Creating Operating Systems"

create_os "${CENTOS_RAID_NAME}" "7" "" "${CENTOS_MEDIA}"
create_os "${CENTOS_SINGLE_NAME}" "7" "" "${CENTOS_MEDIA}"

create_os "${ROCKY8_RAID_NAME}" "8" "10" "${ROCKY8_MEDIA}"
create_os "${ROCKY8_SINGLE_NAME}" "8" "10" "${ROCKY8_MEDIA}"

create_os "${ROCKY92_RAID_NAME}" "9" "2" "${ROCKY92_MEDIA}"
create_os "${ROCKY92_SINGLE_NAME}" "9" "2" "${ROCKY92_MEDIA}"

create_os "${ROCKY98_RAID_NAME}" "9" "8" "${ROCKY98_MEDIA}"
create_os "${ROCKY98_SINGLE_NAME}" "9" "8" "${ROCKY98_MEDIA}"

###############################################################################
# OS Verification
###############################################################################

header "Operating System Verification"

OS_LIST="$(
    api_get "${API}/operatingsystems?per_page=all"
)"

echo "${OS_LIST}" |
    jq -r '
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
            (.minor // ""),
            (.family // "")
        ] |
        @tsv
    ' |
while IFS=$'\t' read -r ID NAME MAJOR MINOR FAMILY
do

    if [ -n "${MINOR}" ]
    then
        VERSION="${MAJOR}.${MINOR}"
    else
        VERSION="${MAJOR}"
    fi

    printf "%s | %s | %s | %s\n" \
        "${ID}" \
        "${NAME}" \
        "${VERSION}" \
        "${FAMILY}"

done

###############################################################################
# Generate PXEGrub2 Template Files
###############################################################################

header "Generating PXEGrub2 Template Files"

###############################################################################
# CentOS RAID
###############################################################################

cat > "${CENTOS_RAID_FILE}" <<'EOF'
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
# CentOS Single Disk
###############################################################################

cat > "${CENTOS_SINGLE_FILE}" <<'EOF'
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

cat > "${ROCKY8_RAID_FILE}" <<'EOF'
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

cat > "${ROCKY8_SINGLE_FILE}" <<'EOF'
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

cat > "${ROCKY92_RAID_FILE}" <<'EOF'
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

cat > "${ROCKY92_SINGLE_FILE}" <<'EOF'
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

cat > "${ROCKY98_RAID_FILE}" <<'EOF'
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

cat > "${ROCKY98_SINGLE_FILE}" <<'EOF'
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
#
# IMPORTANT:
#
# Do NOT query:
#
#   /api/provisioning_template_kinds
#
# Instead use an existing provisioning template such as:
#
#   Kickstart default PXEGrub2
#
# and read its template_kind_id.
#
###############################################################################

header "Finding PXEGrub2 Template Kind"

find_template_id()
{
    TEMPLATE_NAME="$1"

    RESPONSE="$(
        api_search \
            "provisioning_templates" \
            "name=\"${TEMPLATE_NAME}\""
    )"

    echo "${RESPONSE}" |
        jq -r '.results[0].id // empty'
}

###############################################################################
# Find Existing PXEGrub2 Template
###############################################################################

PXEGRUB2_EXISTING_ID=""

for DEFAULT_TEMPLATE in \
    "Kickstart default PXEGrub2" \
    "PXEGrub2 default local boot" \
    "PXEGrub2 global default"
do

    PXEGRUB2_EXISTING_ID="$(find_template_id "${DEFAULT_TEMPLATE}")"

    if [ -n "${PXEGRUB2_EXISTING_ID}" ]
    then
        break
    fi

done

###############################################################################
# Read Template Kind ID
###############################################################################

TEMPLATE_KIND_ID=""

if [ -n "${PXEGRUB2_EXISTING_ID}" ]
then

    TEMPLATE_KIND_RESPONSE="$(
        api_get \
            "${API}/provisioning_templates/${PXEGRUB2_EXISTING_ID}"
    )"

    TEMPLATE_KIND_ID="$(
        echo "${TEMPLATE_KIND_RESPONSE}" |
        jq -r '.template_kind_id // empty'
    )"

fi

###############################################################################
# Fallback Search
###############################################################################

if [ -z "${TEMPLATE_KIND_ID}" ]
then

    TEMPLATE_KIND_ID="$(
        api_get \
            "${API}/provisioning_templates?per_page=all" |
        jq -r '
            .results[] |
            select(
                .template_kind_name == "PXEGrub2" or
                .kind == "PXEGrub2"
            ) |
            .template_kind_id
        ' |
        grep -E '^[0-9]+$' |
        head -1
    )"

fi

###############################################################################
# Verify Kind
###############################################################################

if [[ "${TEMPLATE_KIND_ID}" =~ ^[0-9]+$ ]]
then

    ok "PXEGrub2 template kind found. ID=${TEMPLATE_KIND_ID}"

else

    error "PXEGrub2 template kind not found."

    record_failure "PXEGrub2 template kind"

fi

###############################################################################
# Create / Find Provisioning Template
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

    if [ -z "${TEMPLATE_KIND_ID}" ]
    then

        error "Cannot create ${TEMPLATE_NAME}: PXEGrub2 template kind unavailable."

        record_failure "${TEMPLATE_NAME}"

        return 1

    fi

    if [ ! -f "${TEMPLATE_FILE}" ]
    then

        error "Template file not found : ${TEMPLATE_FILE}"

        record_failure "${TEMPLATE_NAME}"

        return 1

    fi

    info "Creating ${TEMPLATE_NAME}"

    TEMPLATE_CONTENT="$(cat "${TEMPLATE_FILE}")"

    JSON="$(
        jq -n \
            --arg name "${TEMPLATE_NAME}" \
            --arg template "${TEMPLATE_CONTENT}" \
            --argjson kind_id "${TEMPLATE_KIND_ID}" \
            '{
                provisioning_template: {
                    name: $name,
                    template: $template,
                    template_kind_id: $kind_id
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

        error "Failed creating ${TEMPLATE_NAME}."

        echo "${RESPONSE}"

        record_failure "${TEMPLATE_NAME}"

    fi
}

###############################################################################
# Create All PXEGrub2 Templates
###############################################################################

header "Creating PXEGrub2 Templates"

create_template \
    "${CENTOS_RAID_TEMPLATE}" \
    "${CENTOS_RAID_FILE}"

create_template \
    "${CENTOS_SINGLE_TEMPLATE}" \
    "${CENTOS_SINGLE_FILE}"

create_template \
    "${ROCKY8_RAID_TEMPLATE}" \
    "${ROCKY8_RAID_FILE}"

create_template \
    "${ROCKY8_SINGLE_TEMPLATE}" \
    "${ROCKY8_SINGLE_FILE}"

create_template \
    "${ROCKY92_RAID_TEMPLATE}" \
    "${ROCKY92_RAID_FILE}"

create_template \
    "${ROCKY92_SINGLE_TEMPLATE}" \
    "${ROCKY92_SINGLE_FILE}"

create_template \
    "${ROCKY98_RAID_TEMPLATE}" \
    "${ROCKY98_RAID_FILE}"

create_template \
    "${ROCKY98_SINGLE_TEMPLATE}" \
    "${ROCKY98_SINGLE_FILE}"

###############################################################################
# Associate OS With Template
###############################################################################

associate_template()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    echo
    echo "------------------------------------------------------------"
    echo "Associating:"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"
    echo "------------------------------------------------------------"

    ###########################################################################
    # Find OS
    ###########################################################################

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then

        error "Operating System not found : ${OS_NAME}"

        record_failure "${OS_NAME} association"

        return 1

    fi

    ###########################################################################
    # Find Template
    ###########################################################################

    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then

        error "Template not found : ${TEMPLATE_NAME}"

        record_failure "${TEMPLATE_NAME} association"

        return 1

    fi

    ###########################################################################
    # Check Existing Association
    ###########################################################################

    ASSOCIATION_RESPONSE="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}/provisioning_templates?per_page=all"
    )"

    ALREADY_ASSOCIATED="$(
        echo "${ASSOCIATION_RESPONSE}" |
        jq -r \
            --arg name "${TEMPLATE_NAME}" \
            '.results[]? |
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
    # Get Existing OS Template IDs
    ###########################################################################

    EXISTING_TEMPLATE_IDS="$(
        echo "${ASSOCIATION_RESPONSE}" |
        jq -c '
            [
                .results[]?.id
            ] |
            map(select(. != null))
        '
    )"

    if [ -z "${EXISTING_TEMPLATE_IDS}" ]
    then
        EXISTING_TEMPLATE_IDS="[]"
    fi

    ###########################################################################
    # Append Template ID
    ###########################################################################

    NEW_TEMPLATE_IDS="$(
        echo "${EXISTING_TEMPLATE_IDS}" |
        jq -c \
            --argjson template_id "${TEMPLATE_ID}" \
            '. + [$template_id] | unique'
    )"

    ###########################################################################
    # Update OS
    ###########################################################################

    JSON="$(
        jq -n \
            --argjson ids "${NEW_TEMPLATE_IDS}" \
            '{
                operatingsystem: {
                    provisioning_template_ids: $ids
                }
            }'
    )"

    RESPONSE="$(
        api_put \
            "${API}/operatingsystems/${OS_ID}" \
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
    "${CENTOS_RAID_NAME}" \
    "${CENTOS_RAID_TEMPLATE}"

associate_template \
    "${CENTOS_SINGLE_NAME}" \
    "${CENTOS_SINGLE_TEMPLATE}"

associate_template \
    "${ROCKY8_RAID_NAME}" \
    "${ROCKY8_RAID_TEMPLATE}"

associate_template \
    "${ROCKY8_SINGLE_NAME}" \
    "${ROCKY8_SINGLE_TEMPLATE}"

associate_template \
    "${ROCKY92_RAID_NAME}" \
    "${ROCKY92_RAID_TEMPLATE}"

associate_template \
    "${ROCKY92_SINGLE_NAME}" \
    "${ROCKY92_SINGLE_TEMPLATE}"

associate_template \
    "${ROCKY98_RAID_NAME}" \
    "${ROCKY98_RAID_TEMPLATE}"

associate_template \
    "${ROCKY98_SINGLE_NAME}" \
    "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# Find Existing PXEGrub2 Default Record
###############################################################################

find_pxegrub2_default_id()
{
    OS_ID="$1"

    RESPONSE="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    )"

    echo "${RESPONSE}" |
        jq -r \
            --argjson kind_id "${TEMPLATE_KIND_ID}" \
            '.results[]? |
             select(.template_kind_id == $kind_id) |
             .id' |
        head -1
}

###############################################################################
# Set PXEGrub2 Default
#
# IMPORTANT:
#
# Every OS can already have a PXEGrub2 default record.
#
# Therefore:
#
#   Existing record -> PUT/update it
#
# Do NOT POST a second record.
#
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
    # Find Existing PXEGrub2 Default
    ###########################################################################

    DEFAULT_ID="$(
        find_pxegrub2_default_id "${OS_ID}"
    )"

    ###########################################################################
    # Existing Default -> UPDATE
    ###########################################################################

    if [ -n "${DEFAULT_ID}" ]
    then

        info "Existing PXEGrub2 default found. ID=${DEFAULT_ID}"

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

        UPDATED_ID="$(
            echo "${RESPONSE}" |
            jq -r '.id // empty'
        )"

        if [ -n "${UPDATED_ID}" ]
        then

            ok "PXEGrub2 default updated. ID=${UPDATED_ID}"

        else

            error "Failed updating PXEGrub2 default."

            echo "${RESPONSE}"

            record_failure "${OS_NAME} default template"

        fi

        return 0

    fi

    ###########################################################################
    # No Existing Default -> CREATE
    ###########################################################################

    info "No PXEGrub2 default found. Creating one..."

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

    DEFAULT_ID="$(
        echo "${RESPONSE}" |
        jq -r '.id // empty'
    )"

    if [ -n "${DEFAULT_ID}" ]
    then

        ok "PXEGrub2 default created. ID=${DEFAULT_ID}"

    else

        error "Failed creating PXEGrub2 default."

        echo "${RESPONSE}"

        record_failure "${OS_NAME} default template"

    fi
}

###############################################################################
# Set All PXEGrub2 Defaults
###############################################################################

header "Setting PXEGrub2 Default Templates"

set_pxegrub2_default \
    "${CENTOS_RAID_NAME}" \
    "${CENTOS_RAID_TEMPLATE}"

set_pxegrub2_default \
    "${CENTOS_SINGLE_NAME}" \
    "${CENTOS_SINGLE_TEMPLATE}"

set_pxegrub2_default \
    "${ROCKY8_RAID_NAME}" \
    "${ROCKY8_RAID_TEMPLATE}"

set_pxegrub2_default \
    "${ROCKY8_SINGLE_NAME}" \
    "${ROCKY8_SINGLE_TEMPLATE}"

set_pxegrub2_default \
    "${ROCKY92_RAID_NAME}" \
    "${ROCKY92_RAID_TEMPLATE}"

set_pxegrub2_default \
    "${ROCKY92_SINGLE_NAME}" \
    "${ROCKY92_SINGLE_TEMPLATE}"

set_pxegrub2_default \
    "${ROCKY98_RAID_NAME}" \
    "${ROCKY98_RAID_TEMPLATE}"

set_pxegrub2_default \
    "${ROCKY98_SINGLE_NAME}" \
    "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# Find Domain
###############################################################################

find_domain_id()
{
    DOMAIN="$1"

    RESPONSE="$(
        api_search \
            "domains" \
            "name=\"${DOMAIN}\""
    )"

    echo "${RESPONSE}" |
        jq -r '.results[0].id // empty'
}

###############################################################################
# Find Smart Proxy
###############################################################################

find_proxy_id()
{
    PROXY_NAME="$1"
    FEATURE="$2"

    RESPONSE="$(
        api_search \
            "smart_proxies" \
            "feature=${FEATURE}"
    )"

    echo "${RESPONSE}" |
        jq -r \
            --arg name "${PROXY_NAME}" \
            '.results[]? |
             select(.name == $name) |
             .id' |
        head -1
}

###############################################################################
# Create / Update Subnet
###############################################################################

create_subnet()
{
    SUBNET_NAME="$1"
    NETWORK="$2"
    MASK="$3"
    GATEWAY="$4"
    DNS="$5"
    TFTP_PROXY="$6"
    DHCP_PROXY="$7"

    echo
    echo "------------------------------------------------------------"
    echo "Subnet       : ${SUBNET_NAME}"
    echo "Network      : ${NETWORK}"
    echo "Mask         : ${MASK}"
    echo "Gateway      : ${GATEWAY}"
    echo "DNS          : ${DNS}"
    echo "TFTP Proxy   : ${TFTP_PROXY}"
    echo "DHCP Proxy   : ${DHCP_PROXY}"
    echo "------------------------------------------------------------"

    info "Checking Subnet : ${SUBNET_NAME}"

    ###########################################################################
    # Existing Subnet
    ###########################################################################

    SUBNET_RESPONSE="$(
        api_search \
            "subnets" \
            "name=\"${SUBNET_NAME}\""
    )"

    SUBNET_ID="$(
        echo "${SUBNET_RESPONSE}" |
        jq -r '.results[0].id // empty'
    )"

    ###########################################################################
    # Domain
    ###########################################################################

    DOMAIN_ID="$(find_domain_id "${DOMAIN_NAME}")"

    if [ -n "${DOMAIN_ID}" ]
    then

        ok "Domain found : ${DOMAIN_NAME} ID=${DOMAIN_ID}"

    else

        warn "Domain not found : ${DOMAIN_NAME}"

    fi

    ###########################################################################
    # TFTP Proxy
    ###########################################################################

    TFTP_ID="$(
        find_proxy_id \
            "${TFTP_PROXY}" \
            "TFTP"
    )"

    if [ -n "${TFTP_ID}" ]
    then

        ok "TFTP proxy found : ${TFTP_PROXY} ID=${TFTP_ID}"

    else

        warn "TFTP proxy not found : ${TFTP_PROXY}"

    fi

    ###########################################################################
    # DHCP Proxy
    ###########################################################################

    DHCP_ID="$(
        find_proxy_id \
            "${DHCP_PROXY}" \
            "DHCP"
    )"

    if [ -n "${DHCP_ID}" ]
    then

        ok "DHCP proxy found : ${DHCP_PROXY} ID=${DHCP_ID}"

    else

        warn "DHCP proxy not found : ${DHCP_PROXY}"

    fi

    ###########################################################################
    # JSON
    ###########################################################################

    JSON="$(
        jq -n \
            --arg name "${SUBNET_NAME}" \
            --arg network "${NETWORK}" \
            --arg mask "${MASK}" \
            --arg gateway "${GATEWAY}" \
            --arg dns "${DNS}" \
            --argjson domain_id "${DOMAIN_ID:-null}" \
            --argjson tftp_id "${TFTP_ID:-null}" \
            --argjson dhcp_id "${DHCP_ID:-null}" \
            '{
                subnet: {
                    name: $name,
                    network_type: "IPv4",
                    network: $network,
                    mask: $mask,
                    gateway: $gateway,
                    dns_primary: $dns,
                    boot_mode: "DHCP",
                    ipam: "DHCP",
                    domain_ids:
                        (if $domain_id == null then [] else [$domain_id] end),
                    tftp_id: $tftp_id,
                    dhcp_id: $dhcp_id
                }
            }'
    )"

    ###########################################################################
    # Existing -> Update
    ###########################################################################

    if [ -n "${SUBNET_ID}" ]
    then

        skip "${SUBNET_NAME} already exists. ID=${SUBNET_ID}"

        RESPONSE="$(
            api_put \
                "${API}/subnets/${SUBNET_ID}" \
                "${JSON}"
        )"

        UPDATED_ID="$(
            echo "${RESPONSE}" |
            jq -r '.id // empty'
        )"

        if [ -n "${UPDATED_ID}" ]
        then

            ok "${SUBNET_NAME} updated."

        else

            error "Failed updating ${SUBNET_NAME}."

            echo "${RESPONSE}"

            record_failure "${SUBNET_NAME}"

        fi

        return 0

    fi

    ###########################################################################
    # Create
    ###########################################################################

    info "Creating ${SUBNET_NAME}"

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

        ok "${SUBNET_NAME} created. ID=${SUBNET_ID}"

    else

        error "Failed creating ${SUBNET_NAME}."

        echo "${RESPONSE}"

        record_failure "${SUBNET_NAME}"

    fi
}

###############################################################################
# Create PXE Subnets
###############################################################################

header "Creating PXE Subnets"

create_subnet \
    "${CENTOS_SUBNET_NAME}" \
    "${SUBNET_NETWORK}" \
    "${SUBNET_MASK}" \
    "${SUBNET_GATEWAY}" \
    "${SUBNET_DNS}" \
    "${CENTOS_PROXY}" \
    "${CENTOS_PROXY}"

create_subnet \
    "${ROCKY_SUBNET_NAME}" \
    "${SUBNET_NETWORK}" \
    "${SUBNET_MASK}" \
    "${SUBNET_GATEWAY}" \
    "${SUBNET_DNS}" \
    "${ROCKY_PROXY}" \
    "${ROCKY_PROXY}"

###############################################################################
# PXE Subnet Verification
###############################################################################

header "PXE Subnet Verification"

SUBNET_LIST="$(
    api_get \
        "${API}/subnets?per_page=all"
)"

if [ $? -eq 0 ]
then

    echo "${SUBNET_LIST}" |
        jq -r '
            .results[] |
            select(
                .name == "vgs-subnet-centos" or
                .name == "vgs-subnet-rockyos"
            ) |
            "\(.id) | \(.name) | \(.network_address)/\(.cidr) | DHCP=\(.dhcp_name // "-") | TFTP=\(.tftp_name // "-")"
        '

else

    error "Unable to list subnets."

    record_failure "Subnet Verification"

fi

###############################################################################
# PXEGrub2 Template Verification
###############################################################################

header "PXEGrub2 Template Verification"

verify_template()
{
    TEMPLATE_NAME="$1"

    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then

        error "${TEMPLATE_NAME} not found."

        record_failure "${TEMPLATE_NAME}"

        return

    fi

    RESPONSE="$(
        api_get \
            "${API}/provisioning_templates/${TEMPLATE_ID}"
    )"

    KIND_NAME="$(
        echo "${RESPONSE}" |
        jq -r '.template_kind_name // empty'
    )"

    KIND_ID="$(
        echo "${RESPONSE}" |
        jq -r '.template_kind_id // empty'
    )"

    if [ "${KIND_NAME}" = "PXEGrub2" ]
    then

        ok "${TEMPLATE_NAME} | ID=${TEMPLATE_ID} | kind=${KIND_NAME} | kind_id=${KIND_ID}"

    else

        error "${TEMPLATE_NAME} has incorrect template kind."

        record_failure "${TEMPLATE_NAME} kind"

    fi
}

verify_template "${CENTOS_RAID_TEMPLATE}"
verify_template "${CENTOS_SINGLE_TEMPLATE}"

verify_template "${ROCKY8_RAID_TEMPLATE}"
verify_template "${ROCKY8_SINGLE_TEMPLATE}"

verify_template "${ROCKY92_RAID_TEMPLATE}"
verify_template "${ROCKY92_SINGLE_TEMPLATE}"

verify_template "${ROCKY98_RAID_TEMPLATE}"
verify_template "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# OS Template Mapping Verification
###############################################################################

header "OS Template Mapping Verification"

verify_os_template()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then

        error "${OS_NAME} not found."

        record_failure "${OS_NAME}"

        return

    fi

    RESPONSE="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}/provisioning_templates?per_page=all"
    )"

    MATCH="$(
        echo "${RESPONSE}" |
        jq -r \
            --arg name "${TEMPLATE_NAME}" \
            '.results[]? |
             select(.name == $name) |
             .name' |
        head -1
    )"

    if [ "${MATCH}" = "${TEMPLATE_NAME}" ]
    then

        ok "${OS_NAME} -> ${TEMPLATE_NAME}"

    else

        error "${OS_NAME} -> ${TEMPLATE_NAME} mapping missing."

        record_failure "${OS_NAME} mapping"

    fi
}

verify_os_template "${CENTOS_RAID_NAME}" "${CENTOS_RAID_TEMPLATE}"
verify_os_template "${CENTOS_SINGLE_NAME}" "${CENTOS_SINGLE_TEMPLATE}"

verify_os_template "${ROCKY8_RAID_NAME}" "${ROCKY8_RAID_TEMPLATE}"
verify_os_template "${ROCKY8_SINGLE_NAME}" "${ROCKY8_SINGLE_TEMPLATE}"

verify_os_template "${ROCKY92_RAID_NAME}" "${ROCKY92_RAID_TEMPLATE}"
verify_os_template "${ROCKY92_SINGLE_NAME}" "${ROCKY92_SINGLE_TEMPLATE}"

verify_os_template "${ROCKY98_RAID_NAME}" "${ROCKY98_RAID_TEMPLATE}"
verify_os_template "${ROCKY98_SINGLE_NAME}" "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# PXEGrub2 Default Verification
###############################################################################

header "PXEGrub2 Default Template Verification"

verify_default_template()
{
    OS_NAME="$1"
    EXPECTED_TEMPLATE="$2"

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then

        error "OS not found : ${OS_NAME}"

        record_failure "${OS_NAME} default"

        return

    fi

    RESPONSE="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    )"

    MATCH="$(
        echo "${RESPONSE}" |
        jq -r \
            --arg name "${EXPECTED_TEMPLATE}" \
            --argjson kind_id "${TEMPLATE_KIND_ID}" \
            '.results[]? |
             select(
                 .template_kind_id == $kind_id and
                 .provisioning_template_name == $name
             ) |
             .provisioning_template_name' |
        head -1
    )"

    if [ "${MATCH}" = "${EXPECTED_TEMPLATE}" ]
    then

        ok "${OS_NAME} default -> ${EXPECTED_TEMPLATE}"

    else

        error "${OS_NAME} default template is incorrect."

        record_failure "${OS_NAME} default"

    fi
}

verify_default_template \
    "${CENTOS_RAID_NAME}" \
    "${CENTOS_RAID_TEMPLATE}"

verify_default_template \
    "${CENTOS_SINGLE_NAME}" \
    "${CENTOS_SINGLE_TEMPLATE}"

verify_default_template \
    "${ROCKY8_RAID_NAME}" \
    "${ROCKY8_RAID_TEMPLATE}"

verify_default_template \
    "${ROCKY8_SINGLE_NAME}" \
    "${ROCKY8_SINGLE_TEMPLATE}"

verify_default_template \
    "${ROCKY92_RAID_NAME}" \
    "${ROCKY92_RAID_TEMPLATE}"

verify_default_template \
    "${ROCKY92_SINGLE_NAME}" \
    "${ROCKY92_SINGLE_TEMPLATE}"

verify_default_template \
    "${ROCKY98_RAID_NAME}" \
    "${ROCKY98_RAID_TEMPLATE}"

verify_default_template \
    "${ROCKY98_SINGLE_NAME}" \
    "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# Final OS Verification
###############################################################################

header "Final Operating System Verification"

for OS_NAME in \
    "${CENTOS_RAID_NAME}" \
    "${CENTOS_SINGLE_NAME}" \
    "${ROCKY8_RAID_NAME}" \
    "${ROCKY8_SINGLE_NAME}" \
    "${ROCKY92_RAID_NAME}" \
    "${ROCKY92_SINGLE_NAME}" \
    "${ROCKY98_RAID_NAME}" \
    "${ROCKY98_SINGLE_NAME}"
do

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then

        error "OS not found : ${OS_NAME}"

        record_failure "${OS_NAME}"

        continue

    fi

    OS_RESPONSE="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}"
    )"

    echo
    echo "------------------------------------------------------------"
    echo "OS : ${OS_NAME}"
    echo "ID : ${OS_ID}"
    echo "------------------------------------------------------------"

    echo "${OS_RESPONSE}" |
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

TEMPLATE_LIST="$(
    api_get \
        "${API}/provisioning_templates?per_page=all"
)"

echo "${TEMPLATE_LIST}" |
    jq -r '
        .results[] |
        select(.template_kind_name == "PXEGrub2") |
        "\(.id) | \(.name) | kind=\(.template_kind_name) | kind_id=\(.template_kind_id)"
    '

###############################################################################
# PXE Subnets
###############################################################################

header "PXE Subnets"

SUBNET_LIST="$(
    api_get \
        "${API}/subnets?per_page=all"
)"

echo "${SUBNET_LIST}" |
    jq -r '
        .results[] |
        select(
            .name == "vgs-subnet-centos" or
            .name == "vgs-subnet-rockyos"
        ) |
        "\(.id) | \(.name) | \(.network_address)/\(.cidr) | DHCP=\(.dhcp_name // "-") | TFTP=\(.tftp_name // "-")"
    '

###############################################################################
# Generated Files
###############################################################################

header "Generated PXE Template Files"

ls -lh \
    "${CENTOS_RAID_FILE}" \
    "${CENTOS_SINGLE_FILE}" \
    "${ROCKY8_RAID_FILE}" \
    "${ROCKY8_SINGLE_FILE}" \
    "${ROCKY92_RAID_FILE}" \
    "${ROCKY92_SINGLE_FILE}" \
    "${ROCKY98_RAID_FILE}" \
    "${ROCKY98_SINGLE_FILE}"

###############################################################################
# Completion
###############################################################################

header "01 - Foreman PXE Bootstrap API Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]
then

    ok "PXE Bootstrap API completed successfully."

else

    warn "Completed with ${#FAILED_STEPS[@]} failure(s)."

    echo

    for ITEM in "${FAILED_STEPS[@]}"
    do

        error "${ITEM}"

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

echo
echo "Manual API Verification:"
echo "------------------------------------------------------------"

echo
echo "Foreman status:"
echo

echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  ${API}/status"

echo
echo "PXEGrub2 templates:"
echo

echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/provisioning_templates?per_page=all' | jq"

echo
echo "Operating systems:"
echo

echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/operatingsystems?per_page=all' | jq"

echo
echo "Subnets:"
echo

echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/subnets?per_page=all' | jq"

echo
echo "PXEGrub2 defaults:"
echo

echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/operatingsystems/2/os_default_templates?per_page=all' | jq"

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
