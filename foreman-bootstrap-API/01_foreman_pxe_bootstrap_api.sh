#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap - REST API
#
# Purpose:
#   Configure Foreman PXE provisioning using REST API only.
#
# Includes:
#   - PAT authentication
#   - Installation Media
#   - Operating Systems
#   - PXEGrub2 templates
#   - OS/template associations
#   - PXEGrub2 default templates
#   - PXE subnets
#   - Full verification
#
# Foreman:
#   cent-07-01.vgs.com
#   Version 3.2.1
#   API Version 2
#
# Supported:
#   CentOS 7
#   Rocky Linux 8.10
#   Rocky Linux 9.2
#   Rocky Linux 9.8
#
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
# Configuration
###############################################################################

FOREMAN_HOST="${FOREMAN_HOST:-cent-07-01.vgs.com}"
FOREMAN_URL="https://${FOREMAN_HOST}/api"

FOREMAN_USER="${FOREMAN_USER:-admin}"

#
# PAT supplied by user.
#
FOREMAN_TOKEN="${FOREMAN_TOKEN:-oUzg-aMfjcT3q_wZ8NRLfQ}"

#
# TLS
#
CURL_TLS="-k"

#
# API headers
#
API_ACCEPT="Accept: application/json,version=2"
API_CONTENT="Content-Type: application/json"

#
# Authentication
#
AUTH_USER="${FOREMAN_USER}:${FOREMAN_TOKEN}"

#
# Local working directory
#
WORKDIR="/tmp/foreman-pxe-bootstrap"

mkdir -p "${WORKDIR}"

###############################################################################
# Installation Media
###############################################################################

CENTOS_MEDIA="CentOS 7 Remote"
CENTOS_MEDIA_PATH="http://192.168.253.136/repo/centos/"

ROCKY8_MEDIA="Rocky 8 Remote"
ROCKY8_MEDIA_PATH="http://192.168.253.136/repo/rocky8/"

ROCKY92_MEDIA="Rocky 9.2 Remote"
ROCKY92_MEDIA_PATH="http://192.168.253.136/repo/rocky9.2/"

ROCKY98_MEDIA="Rocky 9 Remote"
ROCKY98_MEDIA_PATH="http://192.168.253.136/repo/rocky9/"

###############################################################################
# Operating Systems
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
# PXE Template Names
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
# Architecture / Ptable
###############################################################################

ARCH_NAME="x86_64"
PTABLE_NAME="Kickstart default"

ARCH_ID=""
PTABLE_ID=""
PXEGRUB2_KIND_ID=""

###############################################################################
# API Helpers
###############################################################################

api_get()
{
    local URL="$1"

    curl ${CURL_TLS} -sS \
        --user "${AUTH_USER}" \
        -H "${API_ACCEPT}" \
        "${URL}"
}

api_get_status()
{
    local URL="$1"

    curl ${CURL_TLS} -sS \
        -o /dev/null \
        -w "%{http_code}" \
        --user "${AUTH_USER}" \
        -H "${API_ACCEPT}" \
        "${URL}"
}

api_post()
{
    local URL="$1"
    local DATA="$2"

    curl ${CURL_TLS} -sS \
        --user "${AUTH_USER}" \
        -X POST \
        -H "${API_ACCEPT}" \
        -H "${API_CONTENT}" \
        -d "${DATA}" \
        "${URL}"
}

api_put()
{
    local URL="$1"
    local DATA="$2"

    curl ${CURL_TLS} -sS \
        --user "${AUTH_USER}" \
        -X PUT \
        -H "${API_ACCEPT}" \
        -H "${API_CONTENT}" \
        -d "${DATA}" \
        "${URL}"
}

###############################################################################
# Dependency Check
###############################################################################

header "01 - Foreman PXE Bootstrap - REST API"

header "Dependency Check"

if command -v curl >/dev/null 2>&1
then
    ok "curl found: $(command -v curl)"
else
    error "curl not found."
    exit 1
fi

if command -v jq >/dev/null 2>&1
then
    ok "jq found: $(command -v jq)"
else
    error "jq not found."
    exit 1
fi

###############################################################################
# Foreman API Authentication
###############################################################################

header "Foreman API Authentication Test"

info "Testing Foreman REST API..."

API_STATUS_JSON=$(api_get "${FOREMAN_URL}/status")

API_HTTP_STATUS=$(api_get_status "${FOREMAN_URL}/status")

if [ "${API_HTTP_STATUS}" = "200" ] &&
   echo "${API_STATUS_JSON}" | jq -e '.result == "ok"' >/dev/null 2>&1
then

    ok "Foreman API authentication successful."

    FOREMAN_VERSION=$(echo "${API_STATUS_JSON}" | jq -r '.version // empty')
    API_VERSION=$(echo "${API_STATUS_JSON}" | jq -r '.api_version // empty')

    echo "Foreman Version : ${FOREMAN_VERSION}"
    echo "API Version     : ${API_VERSION}"
    echo "API Status      : ${API_HTTP_STATUS}"

else

    error "Foreman API authentication failed."
    error "HTTP Status : ${API_HTTP_STATUS}"
    echo "${API_STATUS_JSON}"

    exit 1
fi

###############################################################################
# Find Architecture
###############################################################################

ARCH_JSON=$(api_get \
    "${FOREMAN_URL}/architectures?search=name%3D%22${ARCH_NAME}%22&per_page=all")

ARCH_ID=$(echo "${ARCH_JSON}" |
    jq -r '.results[]? | select(.name=="x86_64") | .id' |
    head -1)

if [ -n "${ARCH_ID}" ]
then
    ok "x86_64 architecture found. ID=${ARCH_ID}"
else
    error "x86_64 architecture not found."
    record_failure "x86_64 architecture"
fi

###############################################################################
# Find Kickstart Default Partition Table
###############################################################################

PTABLE_JSON=$(api_get \
    "${FOREMAN_URL}/ptables?search=name%3D%22Kickstart%20default%22&per_page=all")

PTABLE_ID=$(echo "${PTABLE_JSON}" |
    jq -r '.results[]? |
        select(.name=="Kickstart default") |
        .id' |
    head -1)

if [ -n "${PTABLE_ID}" ]
then
    ok "Kickstart default partition table found. ID=${PTABLE_ID}"
else
    error "Kickstart default partition table not found."
    record_failure "Kickstart default partition table"
fi

###############################################################################
# Installation Media Function
###############################################################################

get_media_id()
{
    local NAME="$1"

    api_get \
        "${FOREMAN_URL}/media?search=name%3D%22${NAME}%22&per_page=all" |
        jq -r --arg NAME "${NAME}" \
        '.results[]? | select(.name==$NAME) | .id' |
        head -1
}

create_or_update_media()
{
    local NAME="$1"
    local PATH="$2"

    local MEDIA_ID
    local CURRENT_PATH
    local DATA
    local RESPONSE
    local HTTP_STATUS

    section "Installation Media : ${NAME}"

    MEDIA_ID=$(get_media_id "${NAME}")

    if [ -n "${MEDIA_ID}" ]
    then

        skip "${NAME} already exists. ID=${MEDIA_ID}"

        CURRENT_PATH=$(api_get \
            "${FOREMAN_URL}/media/${MEDIA_ID}" |
            jq -r '.path // empty')

        if [ "${CURRENT_PATH}" = "${PATH}" ]
        then

            ok "${NAME} path verified."

        else

            warn "${NAME} path mismatch."
            info "Updating media path..."

            DATA=$(jq -n \
                --arg path "${PATH}" \
                '{medium:{path:$path}}')

            HTTP_STATUS=$(curl ${CURL_TLS} -sS \
                -o "${WORKDIR}/media-update.json" \
                -w "%{http_code}" \
                --user "${AUTH_USER}" \
                -X PUT \
                -H "${API_ACCEPT}" \
                -H "${API_CONTENT}" \
                -d "${DATA}" \
                "${FOREMAN_URL}/media/${MEDIA_ID}")

            RESPONSE=$(cat "${WORKDIR}/media-update.json")

            if [[ "${HTTP_STATUS}" =~ ^2 ]]
            then
                ok "${NAME} path updated."
            else
                error "${NAME} path update failed."
                echo "${RESPONSE}"
                record_failure "${NAME} media path"
            fi
        fi

    else

        info "Creating ${NAME}"

        DATA=$(jq -n \
            --arg name "${NAME}" \
            --arg path "${PATH}" \
            '{
                medium:{
                    name:$name,
                    path:$path
                }
            }')

        HTTP_STATUS=$(curl ${CURL_TLS} -sS \
            -o "${WORKDIR}/media-create.json" \
            -w "%{http_code}" \
            --user "${AUTH_USER}" \
            -X POST \
            -H "${API_ACCEPT}" \
            -H "${API_CONTENT}" \
            -d "${DATA}" \
            "${FOREMAN_URL}/media")

        RESPONSE=$(cat "${WORKDIR}/media-create.json")

        if [[ "${HTTP_STATUS}" =~ ^2 ]]
        then

            MEDIA_ID=$(echo "${RESPONSE}" |
                jq -r '.id // empty')

            ok "${NAME} created. ID=${MEDIA_ID}"

        else

            error "${NAME} creation failed."
            echo "${RESPONSE}"

            record_failure "${NAME} media creation"
        fi
    fi
}

###############################################################################
# Create Installation Media
###############################################################################

header "Creating Installation Media"

create_or_update_media \
    "${CENTOS_MEDIA}" \
    "${CENTOS_MEDIA_PATH}"

create_or_update_media \
    "${ROCKY8_MEDIA}" \
    "${ROCKY8_MEDIA_PATH}"

create_or_update_media \
    "${ROCKY92_MEDIA}" \
    "${ROCKY92_MEDIA_PATH}"

create_or_update_media \
    "${ROCKY98_MEDIA}" \
    "${ROCKY98_MEDIA_PATH}"

###############################################################################
# Installation Media Verification
###############################################################################

header "Installation Media Verification"

api_get "${FOREMAN_URL}/media?per_page=all" |
    jq -r '
        .results[] |
        [
            .id,
            .name,
            .path
        ] |
        @tsv
    ' 2>/dev/null

###############################################################################
# OS Helper
###############################################################################

get_os_id()
{
    local NAME="$1"

    api_get \
        "${FOREMAN_URL}/operatingsystems?search=name%3D%22${NAME}%22&per_page=all" |
        jq -r --arg NAME "${NAME}" \
        '.results[]? |
        select(.name==$NAME) |
        .id' |
        head -1
}

###############################################################################
# OS Create / Update
###############################################################################

create_or_update_os()
{
    local NAME="$1"
    local MAJOR="$2"
    local MINOR="$3"
    local MEDIA_NAME="$4"

    local OS_ID
    local MEDIA_ID
    local DATA
    local HTTP_STATUS

    section "Operating System : ${NAME}"

    MEDIA_ID=$(get_media_id "${MEDIA_NAME}")

    if [ -z "${MEDIA_ID}" ]
    then
        error "Installation media not found : ${MEDIA_NAME}"
        record_failure "${NAME} media"
        return
    fi

    OS_ID=$(get_os_id "${NAME}")

    if [ -n "${OS_ID}" ]
    then

        skip "${NAME} already exists. ID=${OS_ID}"

        DATA=$(jq -n \
            --arg major "${MAJOR}" \
            --arg minor "${MINOR}" \
            --argjson arch "${ARCH_ID}" \
            --argjson media "${MEDIA_ID}" \
            --argjson ptable "${PTABLE_ID}" \
            '{
                operatingsystem:{
                    major:$major,
                    minor:$minor,
                    architecture_ids:[$arch],
                    medium_ids:[$media],
                    ptables:[$ptable]
                }
            }')

        HTTP_STATUS=$(curl ${CURL_TLS} -sS \
            -o "${WORKDIR}/os-update.json" \
            -w "%{http_code}" \
            --user "${AUTH_USER}" \
            -X PUT \
            -H "${API_ACCEPT}" \
            -H "${API_CONTENT}" \
            -d "${DATA}" \
            "${FOREMAN_URL}/operatingsystems/${OS_ID}")

        if [[ "${HTTP_STATUS}" =~ ^2 ]]
        then
            ok "${NAME} updated."
        else
            error "${NAME} update failed. HTTP=${HTTP_STATUS}"
            cat "${WORKDIR}/os-update.json"
            record_failure "${NAME} update"
        fi

    else

        info "Creating ${NAME}"

        DATA=$(jq -n \
            --arg name "${NAME}" \
            --arg major "${MAJOR}" \
            --arg minor "${MINOR}" \
            --arg family "Redhat" \
            --argjson arch "${ARCH_ID}" \
            --argjson media "${MEDIA_ID}" \
            --argjson ptable "${PTABLE_ID}" \
            '{
                operatingsystem:{
                    name:$name,
                    major:$major,
                    minor:$minor,
                    family:$family,
                    architecture_ids:[$arch],
                    medium_ids:[$media],
                    ptables:[$ptable]
                }
            }')

        HTTP_STATUS=$(curl ${CURL_TLS} -sS \
            -o "${WORKDIR}/os-create.json" \
            -w "%{http_code}" \
            --user "${AUTH_USER}" \
            -X POST \
            -H "${API_ACCEPT}" \
            -H "${API_CONTENT}" \
            -d "${DATA}" \
            "${FOREMAN_URL}/operatingsystems")

        if [[ "${HTTP_STATUS}" =~ ^2 ]]
        then

            OS_ID=$(cat "${WORKDIR}/os-create.json" |
                jq -r '.id // empty')

            ok "${NAME} created. ID=${OS_ID}"

        else

            error "${NAME} creation failed. HTTP=${HTTP_STATUS}"
            cat "${WORKDIR}/os-create.json"

            record_failure "${NAME} creation"
        fi
    fi
}

###############################################################################
# Create Operating Systems
###############################################################################

header "Creating Operating Systems"

create_or_update_os \
    "${CENTOS_RAID_OS}" \
    "7" \
    "" \
    "${CENTOS_MEDIA}"

create_or_update_os \
    "${CENTOS_SINGLE_OS}" \
    "7" \
    "" \
    "${CENTOS_MEDIA}"

create_or_update_os \
    "${ROCKY8_RAID_OS}" \
    "8" \
    "10" \
    "${ROCKY8_MEDIA}"

create_or_update_os \
    "${ROCKY8_SINGLE_OS}" \
    "8" \
    "10" \
    "${ROCKY8_MEDIA}"

create_or_update_os \
    "${ROCKY92_RAID_OS}" \
    "9" \
    "2" \
    "${ROCKY92_MEDIA}"

create_or_update_os \
    "${ROCKY92_SINGLE_OS}" \
    "9" \
    "2" \
    "${ROCKY92_MEDIA}"

create_or_update_os \
    "${ROCKY98_RAID_OS}" \
    "9" \
    "8" \
    "${ROCKY98_MEDIA}"

create_or_update_os \
    "${ROCKY98_SINGLE_OS}" \
    "9" \
    "8" \
    "${ROCKY98_MEDIA}"

###############################################################################
# Operating System Verification
###############################################################################

header "Operating System Verification"

printf "%-5s %-38s %-5s %-5s %-10s\n" \
    "ID" "NAME" "MAJOR" "MINOR" "FAMILY"

api_get "${FOREMAN_URL}/operatingsystems?per_page=all" |
    jq -r '
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
    ' 2>/dev/null

###############################################################################
# Generate PXEGrub2 Templates
###############################################################################

header "Generating PXEGrub2 Template Files"

cat > "${WORKDIR}/centos-raid.erb" <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI RAID Kickstart
kind: PXEGrub2
oses:
- CentOSLinux
%>
set default=0
set timeout=5

menuentry 'Install CentOS 7 RAID' {
    linuxefi /centos/vmlinuz ip=dhcp inst.stage2=http://192.168.253.136/repo/centos/ inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/CentOS7_Golden_RAID_Minimal.cfg inst.text inst.ks.device=bootif BOOTIF=01-${net_default_mac} hostname=<%= @host.name %>
    initrdefi /centos/initrd.img
}
EOF

cat > "${WORKDIR}/centos-singledisk.erb" <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- CentOSLinux
%>
set default=0
set timeout=5

menuentry 'Install CentOS 7 Single Disk' {
    linuxefi /centos/vmlinuz ip=dhcp inst.stage2=http://192.168.253.136/repo/centos/ inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/CentOS7_Golden_SingleDisk_Minimal.cfg inst.text inst.ks.device=bootif BOOTIF=01-${net_default_mac} hostname=<%= @host.name %>
    initrdefi /centos/initrd.img
}
EOF

cat > "${WORKDIR}/rocky8-raid.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI RAID Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5

menuentry 'Install Rocky Linux 8.10 RAID' {
    linuxefi /rocky8/vmlinuz ip=dhcp inst.repo=http://192.168.253.136/repo/rocky8/ inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/Rocky8_Golden_RAID_Minimal.cfg inst.text inst.ks.device=bootif BOOTIF=01-${net_default_mac} hostname=<%= @host.name %>
    initrdefi /rocky8/initrd.img
}
EOF

cat > "${WORKDIR}/rocky8-singledisk.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5

menuentry 'Install Rocky Linux 8.10 Single Disk' {
    linuxefi /rocky8/vmlinuz ip=dhcp inst.repo=http://192.168.253.136/repo/rocky8/ inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/Rocky8_Golden_SingleDisk_Minimal.cfg inst.text inst.ks.device=bootif BOOTIF=01-${net_default_mac} hostname=<%= @host.name %>
    initrdefi /rocky8/initrd.img
}
EOF

cat > "${WORKDIR}/rocky92-raid.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky9.2 UEFI RAID Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5

menuentry 'Install Rocky Linux 9.2 RAID' {
    linuxefi /rocky92/vmlinuz ip=dhcp inst.repo=http://192.168.253.136/repo/rocky9.2/ inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/Rocky9_2_Golden_RAID_Minimal.cfg inst.text inst.ks.device=bootif BOOTIF=01-${net_default_mac} hostname=<%= @host.name %>
    initrdefi /rocky92/initrd.img
}
EOF

cat > "${WORKDIR}/rocky92-singledisk.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5

menuentry 'Install Rocky Linux 9.2 Single Disk' {
    linuxefi /rocky92/vmlinuz ip=dhcp inst.repo=http://192.168.253.136/repo/rocky9.2/ inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/Rocky9_2_Golden_SingleDisk_Minimal.cfg inst.text inst.ks.device=bootif BOOTIF=01-${net_default_mac} hostname=<%= @host.name %>
    initrdefi /rocky92/initrd.img
}
EOF

cat > "${WORKDIR}/rocky98-raid.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky9.8 UEFI RAID Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5

menuentry 'Install Rocky Linux 9.8 RAID' {
    linuxefi /rocky9/vmlinuz ip=dhcp inst.repo=http://192.168.253.136/repo/rocky9/ inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/Rocky9_Golden_RAID_Minimal.cfg inst.text inst.ks.device=bootif BOOTIF=01-${net_default_mac} hostname=<%= @host.name %>
    initrdefi /rocky9/initrd.img
}
EOF

cat > "${WORKDIR}/rocky98-singledisk.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5

menuentry 'Install Rocky Linux 9.8 Single Disk' {
    linuxefi /rocky9/vmlinuz ip=dhcp inst.repo=http://192.168.253.136/repo/rocky9/ inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/Rocky9_Golden_SingleDisk_Minimal.cfg inst.text inst.ks.device=bootif BOOTIF=01-${net_default_mac} hostname=<%= @host.name %>
    initrdefi /rocky9/initrd.img
}
EOF

ok "All 8 PXEGrub2 template files generated."

ls -lh "${WORKDIR}"/*.erb

###############################################################################
# Find PXEGrub2 Template Kind
###############################################################################

header "Finding PXEGrub2 Template Kind"

TEMPLATE_KIND_JSON=$(api_get \
    "${FOREMAN_URL}/template_kinds?per_page=all")

PXEGRUB2_KIND_ID=$(echo "${TEMPLATE_KIND_JSON}" |
    jq -r '
        .results[]? |
        select(.name=="PXEGrub2") |
        .id
    ' |
    head -1)

if [ -n "${PXEGRUB2_KIND_ID}" ]
then
    ok "PXEGrub2 template kind found. ID=${PXEGRUB2_KIND_ID}"
else
    error "PXEGrub2 template kind not found."
    echo "${TEMPLATE_KIND_JSON}"
    record_failure "PXEGrub2 template kind"
fi

###############################################################################
# Get Provisioning Template ID
###############################################################################

get_template_id()
{
    local NAME="$1"

    api_get \
        "${FOREMAN_URL}/provisioning_templates?search=name%3D%22${NAME}%22&per_page=all" |
        jq -r --arg NAME "${NAME}" \
        '.results[]? |
        select(.name==$NAME) |
        .id' |
        head -1
}

###############################################################################
# Create / Update PXEGrub2 Template
###############################################################################

create_or_update_template()
{
    local NAME="$1"
    local FILE="$2"

    local TEMPLATE_ID
    local TEMPLATE_CONTENT
    local DATA
    local HTTP_STATUS

    section "PXEGrub2 template : ${NAME}"

    TEMPLATE_ID=$(get_template_id "${NAME}")

    TEMPLATE_CONTENT=$(cat "${FILE}")

    if [ -n "${TEMPLATE_ID}" ]
    then

        skip "${NAME} already exists. ID=${TEMPLATE_ID}"

        DATA=$(jq -n \
            --arg template "${TEMPLATE_CONTENT}" \
            --argjson kind "${PXEGRUB2_KIND_ID}" \
            --arg name "${NAME}" \
            '{
                provisioning_template:{
                    name:$name,
                    template:$template,
                    template_kind_id:$kind
                }
            }')

        HTTP_STATUS=$(curl ${CURL_TLS} -sS \
            -o "${WORKDIR}/template-update.json" \
            -w "%{http_code}" \
            --user "${AUTH_USER}" \
            -X PUT \
            -H "${API_ACCEPT}" \
            -H "${API_CONTENT}" \
            -d "${DATA}" \
            "${FOREMAN_URL}/provisioning_templates/${TEMPLATE_ID}")

        if [[ "${HTTP_STATUS}" =~ ^2 ]]
        then
            ok "${NAME} updated."
        else
            error "${NAME} update failed. HTTP=${HTTP_STATUS}"
            cat "${WORKDIR}/template-update.json"
            record_failure "${NAME} template update"
        fi

    else

        info "Creating ${NAME}"

        DATA=$(jq -n \
            --arg template "${TEMPLATE_CONTENT}" \
            --argjson kind "${PXEGRUB2_KIND_ID}" \
            --arg name "${NAME}" \
            '{
                provisioning_template:{
                    name:$name,
                    template:$template,
                    template_kind_id:$kind
                }
            }')

        HTTP_STATUS=$(curl ${CURL_TLS} -sS \
            -o "${WORKDIR}/template-create.json" \
            -w "%{http_code}" \
            --user "${AUTH_USER}" \
            -X POST \
            -H "${API_ACCEPT}" \
            -H "${API_CONTENT}" \
            -d "${DATA}" \
            "${FOREMAN_URL}/provisioning_templates")

        if [[ "${HTTP_STATUS}" =~ ^2 ]]
        then

            TEMPLATE_ID=$(cat "${WORKDIR}/template-create.json" |
                jq -r '.id // empty')

            ok "${NAME} created. ID=${TEMPLATE_ID}"

        else

            error "${NAME} creation failed. HTTP=${HTTP_STATUS}"
            cat "${WORKDIR}/template-create.json"

            record_failure "${NAME} template creation"
        fi
    fi
}

###############################################################################
# Create PXEGrub2 Templates
###############################################################################

header "Creating PXEGrub2 Templates"

create_or_update_template \
    "${CENTOS_RAID_TEMPLATE}" \
    "${WORKDIR}/centos-raid.erb"

create_or_update_template \
    "${CENTOS_SINGLE_TEMPLATE}" \
    "${WORKDIR}/centos-singledisk.erb"

create_or_update_template \
    "${ROCKY8_RAID_TEMPLATE}" \
    "${WORKDIR}/rocky8-raid.erb"

create_or_update_template \
    "${ROCKY8_SINGLE_TEMPLATE}" \
    "${WORKDIR}/rocky8-singledisk.erb"

create_or_update_template \
    "${ROCKY92_RAID_TEMPLATE}" \
    "${WORKDIR}/rocky92-raid.erb"

create_or_update_template \
    "${ROCKY92_SINGLE_TEMPLATE}" \
    "${WORKDIR}/rocky92-singledisk.erb"

create_or_update_template \
    "${ROCKY98_RAID_TEMPLATE}" \
    "${WORKDIR}/rocky98-raid.erb"

create_or_update_template \
    "${ROCKY98_SINGLE_TEMPLATE}" \
    "${WORKDIR}/rocky98-singledisk.erb"

###############################################################################
# Associate Template with OS
###############################################################################

associate_template()
{
    local OS_NAME="$1"
    local TEMPLATE_NAME="$2"

    local OS_ID
    local TEMPLATE_ID
    local OS_JSON
    local DATA
    local HTTP_STATUS

    section "Associating:"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"

    OS_ID=$(get_os_id "${OS_NAME}")

    if [ -z "${OS_ID}" ]
    then
        error "Operating System not found : ${OS_NAME}"
        record_failure "${OS_NAME} OS"
        return
    fi

    TEMPLATE_ID=$(get_template_id "${TEMPLATE_NAME}")

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${TEMPLATE_NAME}"
        return
    fi

    OS_JSON=$(api_get \
        "${FOREMAN_URL}/operatingsystems/${OS_ID}")

    if echo "${OS_JSON}" |
        jq -e --arg NAME "${TEMPLATE_NAME}" '
            .provisioning_templates[]? |
            select(.name==$NAME)
        ' >/dev/null 2>&1
    then

        skip "Template already associated."

    else

        DATA=$(jq -n \
            --argjson template "${TEMPLATE_ID}" \
            '{
                provisioning_template_ids: [$template]
            }')

        HTTP_STATUS=$(curl ${CURL_TLS} -sS \
            -o "${WORKDIR}/os-template.json" \
            -w "%{http_code}" \
            --user "${AUTH_USER}" \
            -X PUT \
            -H "${API_ACCEPT}" \
            -H "${API_CONTENT}" \
            -d "${DATA}" \
            "${FOREMAN_URL}/operatingsystems/${OS_ID}")

        if [[ "${HTTP_STATUS}" =~ ^2 ]]
        then
            ok "Template associated with ${OS_NAME}."
        else
            error "Failed to associate template."
            error "HTTP Status : ${HTTP_STATUS}"
            cat "${WORKDIR}/os-template.json"
            record_failure "${OS_NAME} -> ${TEMPLATE_NAME}"
        fi
    fi
}

###############################################################################
# Associate Templates
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
# Get Existing OS Default Template
###############################################################################

get_os_default_template_id()
{
    local OS_ID="$1"

    api_get \
        "${FOREMAN_URL}/operatingsystems/${OS_ID}/os_default_templates?per_page=all" |
        jq -r --argjson KIND "${PXEGRUB2_KIND_ID}" '
            .results[]? |
            select(.template_kind_id==$KIND) |
            .id
        ' |
        head -1
}

###############################################################################
# Set PXEGrub2 Default Template
###############################################################################

set_pxegrub2_default()
{
    local OS_NAME="$1"
    local TEMPLATE_NAME="$2"

    local OS_ID
    local TEMPLATE_ID
    local DEFAULT_ID
    local DATA
    local HTTP_STATUS

    section "Setting PXEGrub2 Default:"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"

    OS_ID=$(get_os_id "${OS_NAME}")

    if [ -z "${OS_ID}" ]
    then
        error "Operating System not found : ${OS_NAME}"
        record_failure "${OS_NAME} default template"
        return
    fi

    TEMPLATE_ID=$(get_template_id "${TEMPLATE_NAME}")

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${TEMPLATE_NAME} default"
        return
    fi

    DEFAULT_ID=$(get_os_default_template_id "${OS_ID}")

    if [ -n "${DEFAULT_ID}" ]
    then

        info "Existing PXEGrub2 default found. ID=${DEFAULT_ID}"
        info "Updating default template..."

        DATA=$(jq -n \
            --argjson template "${TEMPLATE_ID}" \
            --argjson kind "${PXEGRUB2_KIND_ID}" \
            '{
                os_default_template:{
                    provisioning_template_id:$template,
                    template_kind_id:$kind
                }
            }')

        HTTP_STATUS=$(curl ${CURL_TLS} -sS \
            -o "${WORKDIR}/default-update.json" \
            -w "%{http_code}" \
            --user "${AUTH_USER}" \
            -X PUT \
            -H "${API_ACCEPT}" \
            -H "${API_CONTENT}" \
            -d "${DATA}" \
            "${FOREMAN_URL}/operatingsystems/${OS_ID}/os_default_templates/${DEFAULT_ID}")

        if [[ "${HTTP_STATUS}" =~ ^2 ]]
        then
            ok "PXEGrub2 default updated."
        else
            error "Failed updating PXEGrub2 default."
            error "HTTP Status : ${HTTP_STATUS}"
            cat "${WORKDIR}/default-update.json"
            record_failure "${OS_NAME} default template"
        fi

    else

        info "No PXEGrub2 default found. Creating one..."

        DATA=$(jq -n \
            --argjson template "${TEMPLATE_ID}" \
            --argjson kind "${PXEGRUB2_KIND_ID}" \
            '{
                os_default_template:{
                    provisioning_template_id:$template,
                    template_kind_id:$kind
                }
            }')

        HTTP_STATUS=$(curl ${CURL_TLS} -sS \
            -o "${WORKDIR}/default-create.json" \
            -w "%{http_code}" \
            --user "${AUTH_USER}" \
            -X POST \
            -H "${API_ACCEPT}" \
            -H "${API_CONTENT}" \
            -d "${DATA}" \
            "${FOREMAN_URL}/operatingsystems/${OS_ID}/os_default_templates")

        if [[ "${HTTP_STATUS}" =~ ^2 ]]
        then
            ok "PXEGrub2 default created."
        else
            error "Failed creating PXEGrub2 default."
            error "HTTP Status : ${HTTP_STATUS}"
            cat "${WORKDIR}/default-create.json"
            record_failure "${OS_NAME} default template"
        fi
    fi
}

###############################################################################
# Set Default Templates
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
# Domain / Proxy Functions
###############################################################################

get_domain_id()
{
    local NAME="$1"

    api_get \
        "${FOREMAN_URL}/domains?search=name%3D%22${NAME}%22&per_page=all" |
        jq -r --arg NAME "${NAME}" '
            .results[]? |
            select(.name==$NAME) |
            .id
        ' |
        head -1
}

get_proxy_id()
{
    local NAME="$1"

    api_get \
        "${FOREMAN_URL}/smart_proxies?search=name%3D%22${NAME}%22&per_page=all" |
        jq -r --arg NAME "${NAME}" '
            .results[]? |
            select(.name==$NAME) |
            .id
        ' |
        head -1
}

###############################################################################
# Create / Update Subnet
###############################################################################

create_or_update_subnet()
{
    local NAME="$1"
    local NETWORK="$2"
    local MASK="$3"
    local GATEWAY="$4"
    local DNS="$5"
    local DOMAIN_NAME="$6"
    local TFTP_PROXY_NAME="$7"
    local DHCP_PROXY_NAME="$8"

    local SUBNET_ID
    local DOMAIN_ID
    local TFTP_PROXY_ID
    local DHCP_PROXY_ID
    local DATA
    local HTTP_STATUS

    section "Subnet : ${NAME}"

    echo "Network      : ${NETWORK}"
    echo "Mask         : ${MASK}"
    echo "Gateway      : ${GATEWAY}"
    echo "DNS          : ${DNS}"
    echo "TFTP Proxy   : ${TFTP_PROXY_NAME}"
    echo "DHCP Proxy   : ${DHCP_PROXY_NAME}"

    DOMAIN_ID=$(get_domain_id "${DOMAIN_NAME}")

    if [ -n "${DOMAIN_ID}" ]
    then
        ok "Domain found : ${DOMAIN_NAME} ID=${DOMAIN_ID}"
    else
        error "Domain not found : ${DOMAIN_NAME}"
        record_failure "${NAME} domain"
        return
    fi

    TFTP_PROXY_ID=$(get_proxy_id "${TFTP_PROXY_NAME}")

    if [ -n "${TFTP_PROXY_ID}" ]
    then
        ok "TFTP/DHCP proxy found : ${TFTP_PROXY_NAME} ID=${TFTP_PROXY_ID}"
    else
        error "TFTP proxy not found : ${TFTP_PROXY_NAME}"
        record_failure "${NAME} TFTP proxy"
        return
    fi

    DHCP_PROXY_ID=$(get_proxy_id "${DHCP_PROXY_NAME}")

    if [ -n "${DHCP_PROXY_ID}" ]
    then
        ok "TFTP/DHCP proxy found : ${DHCP_PROXY_NAME} ID=${DHCP_PROXY_ID}"
    else
        error "DHCP proxy not found : ${DHCP_PROXY_NAME}"
        record_failure "${NAME} DHCP proxy"
        return
    fi

    SUBNET_ID=$(
        api_get \
            "${FOREMAN_URL}/subnets?search=name%3D%22${NAME}%22&per_page=all" |
            jq -r --arg NAME "${NAME}" '
                .results[]? |
                select(.name==$NAME) |
                .id
            ' |
            head -1
    )

    DATA=$(jq -n \
        --arg name "${NAME}" \
        --arg network "${NETWORK}" \
        --arg mask "${MASK}" \
        --arg gateway "${GATEWAY}" \
        --arg dns "${DNS}" \
        --argjson domain "${DOMAIN_ID}" \
        --argjson tftp "${TFTP_PROXY_ID}" \
        --argjson dhcp "${DHCP_PROXY_ID}" \
        '{
            subnet:{
                name:$name,
                network:$network,
                mask:$mask,
                gateway:$gateway,
                dns_primary:$dns,
                domain_ids:[$domain],
                tftp_id:$tftp,
                dhcp_id:$dhcp
            }
        }')

    if [ -n "${SUBNET_ID}" ]
    then

        skip "${NAME} already exists. ID=${SUBNET_ID}"

        HTTP_STATUS=$(curl ${CURL_TLS} -sS \
            -o "${WORKDIR}/subnet-update.json" \
            -w "%{http_code}" \
            --user "${AUTH_USER}" \
            -X PUT \
            -H "${API_ACCEPT}" \
            -H "${API_CONTENT}" \
            -d "${DATA}" \
            "${FOREMAN_URL}/subnets/${SUBNET_ID}")

        if [[ "${HTTP_STATUS}" =~ ^2 ]]
        then
            ok "${NAME} updated."
        else
            error "${NAME} update failed. HTTP=${HTTP_STATUS}"
            cat "${WORKDIR}/subnet-update.json"
            record_failure "${NAME} subnet update"
        fi

    else

        info "Creating ${NAME}"

        HTTP_STATUS=$(curl ${CURL_TLS} -sS \
            -o "${WORKDIR}/subnet-create.json" \
            -w "%{http_code}" \
            --user "${AUTH_USER}" \
            -X POST \
            -H "${API_ACCEPT}" \
            -H "${API_CONTENT}" \
            -d "${DATA}" \
            "${FOREMAN_URL}/subnets")

        if [[ "${HTTP_STATUS}" =~ ^2 ]]
        then

            SUBNET_ID=$(cat "${WORKDIR}/subnet-create.json" |
                jq -r '.id // empty')

            ok "${NAME} created. ID=${SUBNET_ID}"

        else

            error "${NAME} creation failed. HTTP=${HTTP_STATUS}"
            cat "${WORKDIR}/subnet-create.json"

            record_failure "${NAME} subnet creation"
        fi
    fi
}

###############################################################################
# Create PXE Subnets
###############################################################################

header "Creating PXE Subnets"

create_or_update_subnet \
    "vgs-subnet-centos" \
    "192.168.253.0" \
    "255.255.255.0" \
    "192.168.253.2" \
    "192.168.253.1" \
    "vgs.com" \
    "cent-07-01.vgs.com" \
    "cent-07-01.vgs.com"

create_or_update_subnet \
    "vgs-subnet-rockyos" \
    "192.168.253.0" \
    "255.255.255.0" \
    "192.168.253.2" \
    "192.168.253.1" \
    "vgs.com" \
    "cent-07-02.vgs.com" \
    "cent-07-02.vgs.com"

###############################################################################
# PXE Subnet Verification
###############################################################################

header "PXE Subnet Verification"

api_get "${FOREMAN_URL}/subnets?per_page=all" |
    jq -r '
        .results[] |
        select(
            .name=="vgs-subnet-centos" or
            .name=="vgs-subnet-rockyos"
        ) |
        [
            .id,
            .name,
            (.network + "/" + .mask),
            (.dhcp.name // "-"),
            (.tftp.name // "-")
        ] |
        @tsv
    ' 2>/dev/null

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

    TEMPLATE_JSON=$(api_get \
        "${FOREMAN_URL}/provisioning_templates?search=name%3D%22${TEMPLATE_NAME}%22&per_page=all")

    TEMPLATE_ID=$(echo "${TEMPLATE_JSON}" |
        jq -r --arg NAME "${TEMPLATE_NAME}" '
            .results[]? |
            select(.name==$NAME) |
            .id
        ' |
        head -1)

    KIND_ID=$(echo "${TEMPLATE_JSON}" |
        jq -r --arg NAME "${TEMPLATE_NAME}" '
            .results[]? |
            select(.name==$NAME) |
            .template_kind_id
        ' |
        head -1)

    KIND_NAME=$(echo "${TEMPLATE_JSON}" |
        jq -r --arg NAME "${TEMPLATE_NAME}" '
            .results[]? |
            select(.name==$NAME) |
            .template_kind_name
        ' |
        head -1)

    if [ -n "${TEMPLATE_ID}" ] &&
       [ "${KIND_ID}" = "${PXEGRUB2_KIND_ID}" ] &&
       [ "${KIND_NAME}" = "PXEGrub2" ]
    then

        ok "${TEMPLATE_NAME} | ID=${TEMPLATE_ID} | kind_id=${KIND_ID} | kind=${KIND_NAME}"

    else

        error "${TEMPLATE_NAME} verification failed."
        record_failure "${TEMPLATE_NAME} verification"

    fi
done

###############################################################################
# OS Template Mapping Verification
###############################################################################

header "OS Template Mapping Verification"

verify_os_template()
{
    local OS_NAME="$1"
    local TEMPLATE_NAME="$2"

    local OS_ID
    local OS_JSON

    OS_ID=$(get_os_id "${OS_NAME}")

    OS_JSON=$(api_get \
        "${FOREMAN_URL}/operatingsystems/${OS_ID}")

    if echo "${OS_JSON}" |
        jq -e --arg NAME "${TEMPLATE_NAME}" '
            .provisioning_templates[]? |
            select(.name==$NAME)
        ' >/dev/null 2>&1
    then

        ok "${OS_NAME} -> ${TEMPLATE_NAME}"

    else

        error "${OS_NAME} -> ${TEMPLATE_NAME}"
        record_failure "${OS_NAME} template mapping"
    fi
}

verify_os_template \
    "${CENTOS_RAID_OS}" \
    "${CENTOS_RAID_TEMPLATE}"

verify_os_template \
    "${CENTOS_SINGLE_OS}" \
    "${CENTOS_SINGLE_TEMPLATE}"

verify_os_template \
    "${ROCKY8_RAID_OS}" \
    "${ROCKY8_RAID_TEMPLATE}"

verify_os_template \
    "${ROCKY8_SINGLE_OS}" \
    "${ROCKY8_SINGLE_TEMPLATE}"

verify_os_template \
    "${ROCKY92_RAID_OS}" \
    "${ROCKY92_RAID_TEMPLATE}"

verify_os_template \
    "${ROCKY92_SINGLE_OS}" \
    "${ROCKY92_SINGLE_TEMPLATE}"

verify_os_template \
    "${ROCKY98_RAID_OS}" \
    "${ROCKY98_RAID_TEMPLATE}"

verify_os_template \
    "${ROCKY98_SINGLE_OS}" \
    "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# PXEGrub2 Default Verification
###############################################################################

header "PXEGrub2 Default Template Verification"

verify_default_template()
{
    local OS_NAME="$1"
    local TEMPLATE_NAME="$2"

    local OS_ID
    local DEFAULT_JSON
    local DEFAULT_TEMPLATE

    OS_ID=$(get_os_id "${OS_NAME}")

    DEFAULT_JSON=$(api_get \
        "${FOREMAN_URL}/operatingsystems/${OS_ID}/os_default_templates?per_page=all")

    DEFAULT_TEMPLATE=$(echo "${DEFAULT_JSON}" |
        jq -r --arg NAME "${TEMPLATE_NAME}" '
            .results[]? |
            select(
                .template_kind_name=="PXEGrub2" and
                .provisioning_template_name==$NAME
            ) |
            .provisioning_template_name
        ' |
        head -1)

    if [ "${DEFAULT_TEMPLATE}" = "${TEMPLATE_NAME}" ]
    then

        ok "${OS_NAME} default template verified."

    else

        error "${OS_NAME} default template missing."
        record_failure "${OS_NAME} default template"

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

show_os()
{
    local OS_NAME="$1"

    local OS_ID
    local OS_JSON

    OS_ID=$(get_os_id "${OS_NAME}")

    echo
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${WHITE}OS : ${OS_NAME}${NC}"
    echo -e "${BLUE}ID : ${OS_ID}${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"

    OS_JSON=$(api_get \
        "${FOREMAN_URL}/operatingsystems/${OS_ID}")

    echo "${OS_JSON}" |
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

show_os "${CENTOS_RAID_OS}"
show_os "${CENTOS_SINGLE_OS}"

show_os "${ROCKY8_RAID_OS}"
show_os "${ROCKY8_SINGLE_OS}"

show_os "${ROCKY92_RAID_OS}"
show_os "${ROCKY92_SINGLE_OS}"

show_os "${ROCKY98_RAID_OS}"
show_os "${ROCKY98_SINGLE_OS}"

###############################################################################
# Generated Template Files
###############################################################################

header "Generated PXE Template Files"

ls -lh "${WORKDIR}"/*.erb

###############################################################################
# Manual API Verification
###############################################################################

header "Manual API Verification"

echo
echo "Foreman status:"
echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  https://${FOREMAN_HOST}/api/status"

echo
echo "PXEGrub2 templates:"
echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  'https://${FOREMAN_HOST}/api/provisioning_templates?per_page=all' | jq"

echo
echo "Operating systems:"
echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  'https://${FOREMAN_HOST}/api/operatingsystems?per_page=all' | jq"

echo
echo "Subnets:"
echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  'https://${FOREMAN_HOST}/api/subnets?per_page=all' | jq"

###############################################################################
# Authentication Information
###############################################################################

header "Authentication"

echo
echo "------------------------------------------------------------"
echo "Method        : Foreman REST API"
echo "Username      : ${FOREMAN_USER}"
echo "Authentication: Personal Access Token"
echo "Hammer        : NOT USED"
echo "curl          : USED"
echo "API           : ${FOREMAN_URL}"
echo "------------------------------------------------------------"

###############################################################################
# Final Status
###############################################################################

header "01 - Foreman PXE Bootstrap API Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]
then

    ok "Completed successfully with 0 failures."

    exit 0

else

    warn "Completed with ${#FAILED_STEPS[@]} failure(s)."

    echo

    for STEP in "${FAILED_STEPS[@]}"
    do
        error "${STEP}"
    done

    exit 1
fi
