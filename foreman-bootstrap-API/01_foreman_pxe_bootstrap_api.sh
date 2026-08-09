#!/bin/bash
###############################################################################
# 01 - Foreman PXE Bootstrap - REST API VERSION
#
# Direct Foreman REST API
# NO HAMMER
#
# Requirements:
#   - curl
#   - jq
#
###############################################################################

set +e

###############################################################################
# Global Variables
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
# Logging Functions
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

header "01 - Foreman PXE Bootstrap - REST API"

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_TOKEN="${FOREMAN_TOKEN:-}"

if [ -z "${FOREMAN_TOKEN}" ]
then
    error "FOREMAN_TOKEN is not set."
    echo
    echo "Set the Foreman Personal Access Token first:"
    echo
    echo "export FOREMAN_USER='admin'"
    echo "export FOREMAN_TOKEN='YOUR_NEW_FOREMAN_PAT'"
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
    echo
    echo "dnf install -y jq"
    echo
    exit 1
fi

###############################################################################
# CURL SSL Options
###############################################################################

CURL_SSL=""

if [ "${FOREMAN_INSECURE}" = "true" ]
then
    CURL_SSL="-k"
fi

###############################################################################
# API Helper
###############################################################################

api_request()
{
    METHOD="$1"
    URL="$2"
    DATA="${3:-}"

    RESPONSE_FILE="$(mktemp)"

    if [ -n "${DATA}" ]
    then

        HTTP_CODE=$(
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
        )

    else

        HTTP_CODE=$(
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
        )

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

api_get()
{
    api_request GET "$1"
}

api_post()
{
    api_request POST "$1" "$2"
}

api_put()
{
    api_request PUT "$1" "$2"
}

###############################################################################
# Foreman API Authentication Test
###############################################################################

header "Foreman API Authentication Test"

info "Testing Foreman REST API..."

STATUS_RESPONSE="$(api_get "${API}/status")"

if [ $? -ne 0 ]
then
    error "Foreman API authentication failed."
    exit 1
fi

FOREMAN_VERSION="$(echo "${STATUS_RESPONSE}" | jq -r '.version // empty')"
API_VERSION="$(echo "${STATUS_RESPONSE}" | jq -r '.api_version // empty')"
RESULT="$(echo "${STATUS_RESPONSE}" | jq -r '.result // empty')"
STATUS="$(echo "${STATUS_RESPONSE}" | jq -r '.status // empty')"

if [ "${RESULT}" = "ok" ] && [ "${STATUS}" = "200" ] && [ -n "${FOREMAN_VERSION}" ]
then
    ok "Foreman API authentication successful."
    echo "Foreman Version : ${FOREMAN_VERSION}"
    echo "API Version     : ${API_VERSION}"
    echo "API Status      : ${STATUS}"
else
    error "Unable to read Foreman API status."
    echo "Response: ${STATUS_RESPONSE}"
    exit 1
fi

###############################################################################
# Installation Media
###############################################################################

CENTOS_MEDIA="CentOS 7 Remote"
ROCKY8_MEDIA="Rocky 8 Remote"
ROCKY92_MEDIA="Rocky 9.2 Remote"
ROCKY98_MEDIA="Rocky 9 Remote"

###############################################################################
# Installation Media URLs
###############################################################################

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
# PXE Subnet Configuration
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
# Generic API Search Helper
###############################################################################
#
# Search syntax:
#
#   /api/resource?search=name="something"
#
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
# Find Installation Media
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
# Create Installation Media
###############################################################################

create_media()
{
    NAME="$1"
    URL="$2"

    info "Checking Installation Media : ${NAME}"

    MEDIA_ID="$(find_media_id "${NAME}")"

    if [ -n "${MEDIA_ID}" ]
    then

        skip "${NAME} already exists. ID=${MEDIA_ID}"

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

    if [ $? -eq 0 ]
    then

        MEDIA_ID="$(echo "${RESPONSE}" | jq -r '.id // empty')"

        ok "${NAME} created. ID=${MEDIA_ID}"

    else

        error "Failed creating ${NAME}"

        record_failure "${NAME}"

    fi

    echo
}

###############################################################################
# Create Installation Media
###############################################################################

header "Creating Installation Media"

create_media \
    "${CENTOS_MEDIA}" \
    "${CENTOS_MEDIA_URL}"

create_media \
    "${ROCKY8_MEDIA}" \
    "${ROCKY8_MEDIA_URL}"

create_media \
    "${ROCKY92_MEDIA}" \
    "${ROCKY92_MEDIA_URL}"

create_media \
    "${ROCKY98_MEDIA}" \
    "${ROCKY98_MEDIA_URL}"

###############################################################################
# Installation Media Verification
###############################################################################

header "Installation Media Verification"

MEDIA_LIST="$(api_get "${API}/media?per_page=all")"

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
# Find Architecture
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

###############################################################################
# Find Partition Table
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

###############################################################################
# Find Operating System
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
# Create Operating System
###############################################################################

create_os()
{
    OS_NAME="$1"
    MAJOR="$2"
    MINOR="$3"
    MEDIA_NAME="$4"

    info "Checking OS : ${OS_NAME}"

    ###########################################################################
    # Existing OS
    ###########################################################################

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -n "${OS_ID}" ]
    then

        skip "${OS_NAME} already exists. ID=${OS_ID}"

        echo

        return 0

    fi

    ###########################################################################
    # Find Media
    ###########################################################################

    MEDIA_ID="$(find_media_id "${MEDIA_NAME}")"

    if [ -z "${MEDIA_ID}" ]
    then

        error "Media not found : ${MEDIA_NAME}"

        record_failure "${OS_NAME}"

        echo

        return

    fi

    ###########################################################################
    # Find x86_64 Architecture
    ###########################################################################

    ARCH_ID="$(find_architecture_id "x86_64")"

    if [ -z "${ARCH_ID}" ]
    then

        error "Architecture not found : x86_64"

        record_failure "${OS_NAME}"

        echo

        return

    fi

    ###########################################################################
    # Find Kickstart Default Partition Table
    ###########################################################################

    PTABLE_ID="$(find_ptable_id "Kickstart default")"

    if [ -z "${PTABLE_ID}" ]
    then

        error "Partition table not found : Kickstart default"

        record_failure "${OS_NAME}"

        echo

        return

    fi

    ###########################################################################
    # Create OS
    ###########################################################################

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

    if [ $? -eq 0 ]
    then

        OS_ID="$(echo "${RESPONSE}" | jq -r '.id // empty')"

        ok "${OS_NAME} created. ID=${OS_ID}"

    else

        error "Failed creating ${OS_NAME}"

        record_failure "${OS_NAME}"

    fi

    echo
}

###############################################################################
# Create Operating Systems
###############################################################################

header "Creating Operating Systems"

create_os \
    "${CENTOS_RAID_NAME}" \
    "7" \
    "" \
    "${CENTOS_MEDIA}"

create_os \
    "${CENTOS_SINGLE_NAME}" \
    "7" \
    "" \
    "${CENTOS_MEDIA}"

create_os \
    "${ROCKY8_RAID_NAME}" \
    "8" \
    "10" \
    "${ROCKY8_MEDIA}"

create_os \
    "${ROCKY8_SINGLE_NAME}" \
    "8" \
    "10" \
    "${ROCKY8_MEDIA}"

create_os \
    "${ROCKY92_RAID_NAME}" \
    "9" \
    "2" \
    "${ROCKY92_MEDIA}"

create_os \
    "${ROCKY92_SINGLE_NAME}" \
    "9" \
    "2" \
    "${ROCKY92_MEDIA}"

create_os \
    "${ROCKY98_RAID_NAME}" \
    "9" \
    "8" \
    "${ROCKY98_MEDIA}"

create_os \
    "${ROCKY98_SINGLE_NAME}" \
    "9" \
    "8" \
    "${ROCKY98_MEDIA}"

###############################################################################
# Operating System Verification
###############################################################################

header "Operating System Verification"

OS_LIST="$(api_get "${API}/operatingsystems?per_page=all")"

if [ $? -eq 0 ]
then

    echo "${OS_LIST}" |
        jq -r '
            .results[] |
            "\(.id) | \(.name) | \(.major).\(.minor // "") | \(.family)"
        '

else

    error "Unable to list operating systems."

    record_failure "Operating System Verification"

fi

###############################################################################
# Find Provisioning Template
###############################################################################

find_template_id()
{
    NAME="$1"

    RESPONSE="$(
        api_search \
            "provisioning_templates" \
            "name=\"${NAME}\""
    )"

    echo "${RESPONSE}" |
        jq -r '.results[0].id // empty'
}

###############################################################################
# Get Provisioning Template
###############################################################################

get_template()
{
    TEMPLATE_ID="$1"

    api_get \
        "${API}/provisioning_templates/${TEMPLATE_ID}"
}

###############################################################################
# Associate OS with Provisioning Template
###############################################################################
#
# Foreman's API exposes provisioning_template[operatingsystem_ids].
#
# We preserve existing OS associations and add the requested OS.
#
###############################################################################

associate_os_template()
{
    OS_ID="$1"
    TEMPLATE_ID="$2"
    TEMPLATE_NAME="$3"

    info "Associating OS ID ${OS_ID} with template : ${TEMPLATE_NAME}"

    TEMPLATE_RESPONSE="$(get_template "${TEMPLATE_ID}")"

    if [ $? -ne 0 ]
    then

        error "Unable to read template : ${TEMPLATE_NAME}"

        record_failure "${TEMPLATE_NAME}"

        return

    fi

    EXISTING_IDS="$(
        echo "${TEMPLATE_RESPONSE}" |
        jq -c '[.operatingsystems[]?.id] | unique'
    )"

    NEW_IDS="$(
        echo "${EXISTING_IDS}" |
        jq -c \
            --argjson os_id "${OS_ID}" \
            '. + [$os_id] | unique'
    )"

    JSON="$(
        jq -n \
        --argjson ids "${NEW_IDS}" \
        '{
            provisioning_template: {
                operatingsystem_ids: $ids
            }
        }'
    )"

    RESPONSE="$(
        api_put \
            "${API}/provisioning_templates/${TEMPLATE_ID}" \
            "${JSON}"
    )"

    if [ $? -eq 0 ]
    then

        ok "OS associated with ${TEMPLATE_NAME}."

    else

        error "Failed associating OS with ${TEMPLATE_NAME}"

        record_failure "${TEMPLATE_NAME}"

    fi
}

###############################################################################
# Find Existing OS Default Template Combination
###############################################################################

find_os_default_template()
{
    OS_ID="$1"
    TEMPLATE_ID="$2"

    RESPONSE="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    )"

    if [ $? -ne 0 ]
    then
        return 1
    fi

    echo "${RESPONSE}" |
        jq -r \
            --argjson template_id "${TEMPLATE_ID}" \
            '.results[] |
             select(.provisioning_template_id == $template_id) |
             .id' |
        head -n 1
}

###############################################################################
# Set PXEGrub2 Default Template
###############################################################################
#
# Foreman API:
#
# POST /api/operatingsystems/:id/os_default_templates
#
# with:
#
# {
#   "os_default_template": {
#       "provisioning_template_id": ...,
#       "template_kind_id": ...
#   }
# }
#
###############################################################################

set_default_template()
{
    OS_ID="$1"
    TEMPLATE_ID="$2"
    TEMPLATE_NAME="$3"

    info "Setting default template : ${TEMPLATE_NAME}"

    ###########################################################################
    # Read template to obtain template_kind_id
    ###########################################################################

    TEMPLATE_RESPONSE="$(get_template "${TEMPLATE_ID}")"

    if [ $? -ne 0 ]
    then

        error "Unable to read template : ${TEMPLATE_NAME}"

        record_failure "${TEMPLATE_NAME}"

        return

    fi

    TEMPLATE_KIND_ID="$(
        echo "${TEMPLATE_RESPONSE}" |
        jq -r '.template_kind_id // empty'
    )"

    if [ -z "${TEMPLATE_KIND_ID}" ]
    then

        error "Template kind ID not found : ${TEMPLATE_NAME}"

        record_failure "${TEMPLATE_NAME}"

        return

    fi

    ###########################################################################
    # Check Existing Default
    ###########################################################################

    DEFAULT_ID="$(
        find_os_default_template \
            "${OS_ID}" \
            "${TEMPLATE_ID}"
    )"

    if [ -n "${DEFAULT_ID}" ]
    then

        skip "Default template already assigned : ${TEMPLATE_NAME}"

        return

    fi

    ###########################################################################
    # Create Default Template Combination
    ###########################################################################

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

    if [ $? -eq 0 ]
    then

        DEFAULT_ID="$(
            echo "${RESPONSE}" |
            jq -r '.id // empty'
        )"

        ok "Default template assigned. ID=${DEFAULT_ID}"

    else

        error "Failed assigning default template : ${TEMPLATE_NAME}"

        record_failure "${TEMPLATE_NAME}"

    fi
}

###############################################################################
# Attach Template
###############################################################################

attach_template()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    echo
    echo "------------------------------------------------------------"
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

        record_failure "${OS_NAME}"

        return

    fi

    ok "Found OS ID : ${OS_ID}"

    ###########################################################################
    # Find Template
    ###########################################################################

    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then

        error "Template not found : ${TEMPLATE_NAME}"

        record_failure "${TEMPLATE_NAME}"

        return

    fi

    ok "Found Template ID : ${TEMPLATE_ID}"

    ###########################################################################
    # Associate OS with Template
    ###########################################################################

    associate_os_template \
        "${OS_ID}" \
        "${TEMPLATE_ID}" \
        "${TEMPLATE_NAME}"

    ###########################################################################
    # Set Default Template
    ###########################################################################

    set_default_template \
        "${OS_ID}" \
        "${TEMPLATE_ID}" \
        "${TEMPLATE_NAME}"
}

###############################################################################
# Template Mapping
###############################################################################

header "Assigning PXEGrub2 Templates"

attach_template \
    "${CENTOS_RAID_NAME}" \
    "${CENTOS_RAID_TEMPLATE}"

attach_template \
    "${CENTOS_SINGLE_NAME}" \
    "${CENTOS_SINGLE_TEMPLATE}"

attach_template \
    "${ROCKY8_RAID_NAME}" \
    "${ROCKY8_RAID_TEMPLATE}"

attach_template \
    "${ROCKY8_SINGLE_NAME}" \
    "${ROCKY8_SINGLE_TEMPLATE}"

attach_template \
    "${ROCKY92_RAID_NAME}" \
    "${ROCKY92_RAID_TEMPLATE}"

attach_template \
    "${ROCKY92_SINGLE_NAME}" \
    "${ROCKY92_SINGLE_TEMPLATE}"

attach_template \
    "${ROCKY98_RAID_NAME}" \
    "${ROCKY98_RAID_TEMPLATE}"

attach_template \
    "${ROCKY98_SINGLE_NAME}" \
    "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# Verify Template Mapping
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

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then

        error "OS not found : ${OS_NAME}"

        record_failure "${OS_NAME}"

        return

    fi

    TEMPLATE_ID="$(find_template_id "${EXPECTED}")"

    if [ -z "${TEMPLATE_ID}" ]
    then

        error "Template not found : ${EXPECTED}"

        record_failure "${EXPECTED}"

        return

    fi

    OS_TEMPLATE_RESPONSE="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}/provisioning_templates?per_page=all"
    )"

    if [ $? -ne 0 ]
    then

        error "Unable to retrieve OS template mapping."

        record_failure "${OS_NAME}"

        return

    fi

    MATCH="$(
        echo "${OS_TEMPLATE_RESPONSE}" |
        jq -r \
            --argjson template_id "${TEMPLATE_ID}" \
            '.results[] |
             select(.id == $template_id) |
             .name' |
        head -n 1
    )"

    if [ -n "${MATCH}" ]
    then

        ok "Template mapping correct."

    else

        error "Template mapping missing."

        record_failure "${OS_NAME}"

    fi
}

verify_template \
    "${CENTOS_RAID_NAME}" \
    "${CENTOS_RAID_TEMPLATE}"

verify_template \
    "${CENTOS_SINGLE_NAME}" \
    "${CENTOS_SINGLE_TEMPLATE}"

verify_template \
    "${ROCKY8_RAID_NAME}" \
    "${ROCKY8_RAID_TEMPLATE}"

verify_template \
    "${ROCKY8_SINGLE_NAME}" \
    "${ROCKY8_SINGLE_TEMPLATE}"

verify_template \
    "${ROCKY92_RAID_NAME}" \
    "${ROCKY92_RAID_TEMPLATE}"

verify_template \
    "${ROCKY92_SINGLE_NAME}" \
    "${ROCKY92_SINGLE_TEMPLATE}"

verify_template \
    "${ROCKY98_RAID_NAME}" \
    "${ROCKY98_RAID_TEMPLATE}"

verify_template \
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
#
# We use:
#
#   search=feature=TFTP
#   search=feature=DHCP
#
# and then select the requested proxy name.
#
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
            '.results[] |
             select(.name == $name) |
             .id' |
        head -n 1
}

###############################################################################
# Create PXE Subnet
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
    # Check Existing Subnet
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
    # Find Domain
    ###########################################################################

    DOMAIN_ID="$(find_domain_id "${DOMAIN_NAME}")"

    if [ -z "${DOMAIN_ID}" ]
    then

        warn "Domain not found : ${DOMAIN_NAME}"

    else

        ok "Domain found : ${DOMAIN_NAME} ID=${DOMAIN_ID}"

    fi

    ###########################################################################
    # Find TFTP Proxy
    ###########################################################################

    TFTP_ID="$(
        find_proxy_id \
            "${TFTP_PROXY}" \
            "TFTP"
    )"

    if [ -z "${TFTP_ID}" ]
    then

        warn "TFTP proxy not found : ${TFTP_PROXY}"

    else

        ok "TFTP proxy found : ${TFTP_PROXY} ID=${TFTP_ID}"

    fi

    ###########################################################################
    # Find DHCP Proxy
    ###########################################################################

    DHCP_ID="$(
        find_proxy_id \
            "${DHCP_PROXY}" \
            "DHCP"
    )"

    if [ -z "${DHCP_ID}" ]
    then

        warn "DHCP proxy not found : ${DHCP_PROXY}"

    else

        ok "DHCP proxy found : ${DHCP_PROXY} ID=${DHCP_ID}"

    fi

    ###########################################################################
    # Existing Subnet
    ###########################################################################

    if [ -n "${SUBNET_ID}" ]
    then

        skip "${SUBNET_NAME} already exists. ID=${SUBNET_ID}"

        #######################################################################
        # Update Existing Subnet
        #######################################################################

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

        RESPONSE="$(
            api_put \
                "${API}/subnets/${SUBNET_ID}" \
                "${JSON}"
        )"

        if [ $? -eq 0 ]
        then
            ok "${SUBNET_NAME} updated."
        else
            error "Failed updating ${SUBNET_NAME}"
            record_failure "${SUBNET_NAME}"
        fi

        echo

        return 0

    fi

    ###########################################################################
    # Create New Subnet
    ###########################################################################

    info "Creating ${SUBNET_NAME}"

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
                domain_ids:
                    (if $domain_id == null then [] else [$domain_id] end),
                tftp_id: $tftp_id,
                dhcp_id: $dhcp_id
            }
        }'
    )"

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

        error "Failed creating ${SUBNET_NAME}"

        record_failure "${SUBNET_NAME}"

    fi

    echo
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
            "\(.id) | \(.name) | \(.network_address) | DHCP=\(.dhcp_name // "-") | TFTP=\(.tftp_name // "-")"
        '

else

    error "Unable to list subnets."

    record_failure "Subnet Verification"

fi

###############################################################################
# Operating System Final Verification
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

    if [ $? -ne 0 ]
    then

        error "Unable to read OS : ${OS_NAME}"

        record_failure "${OS_NAME}"

        continue

    fi

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
            "Minor         : \(.minor)",
            "Family        : \(.family)",
            "Architecture  : ([.architectures[].name] | join(", "))",
            "Media         : ([.media[].name] | join(", "))",
            "Ptable        : ([.ptables[].name] | join(", "))",
            "Templates     : ([.provisioning_templates[].name] | join(", "))"
        '

done

###############################################################################
# Final Template Verification
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

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then

        error "OS not found : ${OS_NAME}"

        record_failure "${OS_NAME}"

        return

    fi

    TEMPLATE_ID="$(find_template_id "${EXPECTED}")"

    if [ -z "${TEMPLATE_ID}" ]
    then

        error "Template not found : ${EXPECTED}"

        record_failure "${EXPECTED}"

        return

    fi

    DEFAULT_RESPONSE="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    )"

    if [ $? -ne 0 ]
    then

        error "Unable to read default templates."

        record_failure "${OS_NAME}"

        return

    fi

    MATCH="$(
        echo "${DEFAULT_RESPONSE}" |
        jq -r \
            --argjson template_id "${TEMPLATE_ID}" \
            '.results[] |
             select(.provisioning_template_id == $template_id) |
             .provisioning_template_name' |
        head -n 1
    )"

    if [ -n "${MATCH}" ]
    then

        ok "${EXPECTED} mapped as default template."

    else

        error "${EXPECTED} not mapped as default."

        record_failure "${OS_NAME}"

    fi
}

check_default_template \
    "${CENTOS_RAID_NAME}" \
    "${CENTOS_RAID_TEMPLATE}"

check_default_template \
    "${CENTOS_SINGLE_NAME}" \
    "${CENTOS_SINGLE_TEMPLATE}"

check_default_template \
    "${ROCKY8_RAID_NAME}" \
    "${ROCKY8_RAID_TEMPLATE}"

check_default_template \
    "${ROCKY8_SINGLE_NAME}" \
    "${ROCKY8_SINGLE_TEMPLATE}"

check_default_template \
    "${ROCKY92_RAID_NAME}" \
    "${ROCKY92_RAID_TEMPLATE}"

check_default_template \
    "${ROCKY92_SINGLE_NAME}" \
    "${ROCKY92_SINGLE_TEMPLATE}"

check_default_template \
    "${ROCKY98_RAID_NAME}" \
    "${ROCKY98_RAID_TEMPLATE}"

check_default_template \
    "${ROCKY98_SINGLE_NAME}" \
    "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# Final PXE Template List
###############################################################################

header "PXEGrub2 Templates"

TEMPLATE_LIST="$(
    api_search \
        "provisioning_templates" \
        "name~PXEGrub2"
)"

if [ $? -eq 0 ]
then

    echo "${TEMPLATE_LIST}" |
        jq -r '
            .results[] |
            "\(.id) | \(.name) | kind=\(.template_kind_name // "-")"
        '

else

    warn "Unable to list PXEGrub2 templates."

fi

###############################################################################
# Final Subnet List
###############################################################################

header "PXE Subnets"

SUBNET_LIST="$(
    api_get \
        "${API}/subnets?per_page=all"
)"

if [ $? -eq 0 ]
then

    echo "${SUBNET_LIST}" |
        jq -r '
            .results[] |
            select(.name == "vgs-subnet-centos" or .name == "vgs-subnet-rockyos") |
            "\(.id) | \(.name) | \(.network_address) | DHCP=\(.dhcp_name // "-") | TFTP=\(.tftp_name // "-")"
        '

else

    warn "Unable to list PXE subnets."

fi

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
# Authentication Reminder
###############################################################################

echo
echo "Authentication:"
echo "------------------------------------------------------------"
echo "Method       : Foreman REST API"
echo "Username     : ${FOREMAN_USER}"
echo "Authentication: Personal Access Token"
echo "Hammer       : NOT USED"
echo "curl         : USED"
echo "API          : ${API}"
echo "------------------------------------------------------------"

###############################################################################
# Manual API Verification
###############################################################################

echo
echo "Manual API Verification:"
echo "------------------------------------------------------------"

echo
echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  ${API}/status"

echo
echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  ${API}/operatingsystems"

echo
echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  ${API}/subnets"

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
