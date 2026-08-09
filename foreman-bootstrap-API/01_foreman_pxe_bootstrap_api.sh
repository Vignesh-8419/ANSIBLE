#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap - REST API
#
# Foreman 3.2.x
#
# NO HAMMER
# REST API + curl + jq
#
# Features:
#   - PAT authentication
#   - Colored output
#   - Idempotent
#   - Existing resources are skipped
#   - Installation Media
#   - Operating Systems
#   - PXEGrub2 templates
#   - OS/template associations
#   - PXEGrub2 default templates
#   - PXE subnets
#   - Final verification
#
###############################################################################

set +e

###############################################################################
# GLOBAL
###############################################################################

FAILED_STEPS=()

###############################################################################
# COLORS
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

success()
{
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

header()
{
    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

subheader()
{
    echo
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
}

record_failure()
{
    FAILED_STEPS+=("$1")
}

###############################################################################
# CONFIGURATION
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
FOREMAN_USER="${FOREMAN_USER:-admin}"

# PAT MUST be supplied through environment.
#
# Example:
#
# export FOREMAN_USER='admin'
# export FOREMAN_TOKEN='YOUR_PAT'
#
FOREMAN_TOKEN="${FOREMAN_TOKEN:-}"

FOREMAN_INSECURE="${FOREMAN_INSECURE:-true}"

API="${FOREMAN_URL}/api"

###############################################################################
# REQUIRED COMMANDS
###############################################################################

header "Dependency Check"

REQUIRED_COMMANDS=(
    curl
    jq
    cat
    head
    grep
    awk
    sed
    mkdir
    mktemp
)

DEPENDENCY_FAILED=0

for CMD in "${REQUIRED_COMMANDS[@]}"
do
    CMD_PATH="$(command -v "${CMD}" 2>/dev/null)"

    if [ -n "${CMD_PATH}" ]
    then
        ok "${CMD} found: ${CMD_PATH}"
    else
        error "${CMD} not found."
        DEPENDENCY_FAILED=1
    fi
done

if [ "${DEPENDENCY_FAILED}" -ne 0 ]
then
    error "Required dependencies are missing."
    exit 1
fi

###############################################################################
# PAT CHECK
###############################################################################

if [ -z "${FOREMAN_TOKEN}" ]
then
    error "FOREMAN_TOKEN is not set."
    echo
    echo "Run:"
    echo
    echo "export FOREMAN_USER='admin'"
    echo "export FOREMAN_TOKEN='YOUR_FOREMAN_PAT'"
    echo
    exit 1
fi

###############################################################################
# CURL OPTIONS
#
# Use an array instead of an unquoted string.
# This prevents:
#
#   curl: no URL specified
#
###############################################################################

CURL_OPTIONS=(
    -sS
)

if [ "${FOREMAN_INSECURE}" = "true" ]
then
    CURL_OPTIONS+=(
        -k
    )
fi

###############################################################################
# TEMP DIRECTORY
###############################################################################

WORK_DIR="/tmp/foreman-pxe-bootstrap"

mkdir -p "${WORK_DIR}"

###############################################################################
# API REQUEST
###############################################################################

api_request()
{
    local METHOD="$1"
    local URL="$2"
    local DATA="${3:-}"

    local RESPONSE_FILE
    local HTTP_CODE
    local CURL_RC

    if [ -z "${URL}" ]
    then
        error "API URL is empty."
        return 1
    fi

    RESPONSE_FILE="$(mktemp "${WORK_DIR}/api-response.XXXXXX")"

    if [ -n "${DATA}" ]
    then

        HTTP_CODE="$(
            curl \
                "${CURL_OPTIONS[@]}" \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                --request "${METHOD}" \
                --header "Accept: application/json,version=2" \
                --header "Content-Type: application/json" \
                --data "${DATA}" \
                --output "${RESPONSE_FILE}" \
                --write-out "%{http_code}" \
                "${URL}"
        )"

        CURL_RC=$?

    else

        HTTP_CODE="$(
            curl \
                "${CURL_OPTIONS[@]}" \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                --request "${METHOD}" \
                --header "Accept: application/json,version=2" \
                --header "Content-Type: application/json" \
                --output "${RESPONSE_FILE}" \
                --write-out "%{http_code}" \
                "${URL}"
        )"

        CURL_RC=$?

    fi

    if [ "${CURL_RC}" -ne 0 ]
    then
        error "curl failed."
        error "Method : ${METHOD}"
        error "URL    : ${URL}"

        cat "${RESPONSE_FILE}" 2>/dev/null

        rm -f "${RESPONSE_FILE}"

        return 1
    fi

    RESPONSE="$(cat "${RESPONSE_FILE}" 2>/dev/null)"

    rm -f "${RESPONSE_FILE}"

    if [[ "${HTTP_CODE}" =~ ^2[0-9][0-9]$ ]]
    then
        printf '%s\n' "${RESPONSE}"
        return 0
    fi

    error "API request failed."
    error "HTTP Status : ${HTTP_CODE}"
    error "Method      : ${METHOD}"
    error "URL         : ${URL}"

    if [ -n "${RESPONSE}" ]
    then
        printf '%s\n' "${RESPONSE}"
    fi

    return 1
}

###############################################################################
# API SHORTCUTS
###############################################################################

api_get()
{
    api_request "GET" "$1"
}

api_post()
{
    api_request "POST" "$1" "$2"
}

api_put()
{
    api_request "PUT" "$1" "$2"
}

###############################################################################
# JSON VALIDATION
###############################################################################

is_json()
{
    printf '%s\n' "$1" | jq empty >/dev/null 2>&1
}

###############################################################################
# FOREMAN API AUTHENTICATION
###############################################################################

header "01 - Foreman PXE Bootstrap - REST API"

header "Foreman API Authentication Test"

info "Testing Foreman REST API..."

STATUS_RESPONSE="$(api_get "${API}/status")"

if [ $? -ne 0 ]
then
    error "Foreman API authentication failed."
    exit 1
fi

if ! is_json "${STATUS_RESPONSE}"
then
    error "Foreman API returned invalid JSON."
    echo "${STATUS_RESPONSE}"
    exit 1
fi

FOREMAN_VERSION="$(
    echo "${STATUS_RESPONSE}" |
    jq -r '.version // .foreman_version // empty'
)

API_VERSION="$(
    echo "${STATUS_RESPONSE}" |
    jq -r '.api_version // empty'
)

API_STATUS="$(
    echo "${STATUS_RESPONSE}" |
    jq -r '.status // empty'
)

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
# INSTALLATION MEDIA
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
# OPERATING SYSTEMS
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
# PXE TEMPLATE NAMES
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
# TEMPLATE KIND
###############################################################################

PXE_TEMPLATE_KIND="PXEGrub2"

###############################################################################
# SUBNET CONFIGURATION
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
# RESOURCE CACHE
###############################################################################

MEDIA_ID=""
ARCH_ID=""
PTABLE_ID=""
PXE_KIND_ID=""

###############################################################################
# FIND MEDIA
#
# IMPORTANT:
# Do NOT use fragile search=name syntax.
#
# Read the full list and select exact name/path.
###############################################################################

find_media_id()
{
    local NAME="$1"

    local RESPONSE
    local ID

    RESPONSE="$(api_get "${API}/media?per_page=all")"

    if [ $? -ne 0 ]
    then
        return 1
    fi

    if ! is_json "${RESPONSE}"
    then
        return 1
    fi

    ID="$(
        echo "${RESPONSE}" |
        jq -r \
            --arg name "${NAME}" \
            '.results[] |
             select(.name == $name) |
             .id' |
        head -n 1
    )"

    printf '%s\n' "${ID}"

    return 0
}

###############################################################################
# FIND MEDIA BY PATH
###############################################################################

find_media_id_by_path()
{
    local PATH_VALUE="$1"

    local RESPONSE
    local ID

    RESPONSE="$(api_get "${API}/media?per_page=all")"

    if [ $? -ne 0 ]
    then
        return 1
    fi

    if ! is_json "${RESPONSE}"
    then
        return 1
    fi

    ID="$(
        echo "${RESPONSE}" |
        jq -r \
            --arg path "${PATH_VALUE}" \
            '.results[] |
             select(.path == $path) |
             .id' |
        head -n 1
    )"

    printf '%s\n' "${ID}"
}

###############################################################################
# CREATE MEDIA
###############################################################################

create_media()
{
    local NAME="$1"
    local PATH_VALUE="$2"

    local MEDIA_ID_LOCAL
    local JSON
    local RESPONSE

    subheader "Installation Media : ${NAME}"

    MEDIA_ID_LOCAL="$(find_media_id "${NAME}")"

    if [ -n "${MEDIA_ID_LOCAL}" ]
    then
        skip "${NAME} already exists. ID=${MEDIA_ID_LOCAL}"
        return 0
    fi

    MEDIA_ID_LOCAL="$(find_media_id_by_path "${PATH_VALUE}")"

    if [ -n "${MEDIA_ID_LOCAL}" ]
    then
        skip "Path already exists for ${NAME}. Existing ID=${MEDIA_ID_LOCAL}"
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
                    path: $path,
                    os_family: "Redhat"
                }
            }'
    )"

    RESPONSE="$(api_post "${API}/media" "${JSON}")"

    if [ $? -eq 0 ]
    then
        MEDIA_ID_LOCAL="$(
            echo "${RESPONSE}" |
            jq -r '.id // empty'
        )"

        ok "${NAME} created. ID=${MEDIA_ID_LOCAL}"
    else

        # Race-condition protection:
        # Another existing object may have appeared between GET and POST.

        MEDIA_ID_LOCAL="$(find_media_id "${NAME}")"

        if [ -n "${MEDIA_ID_LOCAL}" ]
        then
            skip "${NAME} already exists. ID=${MEDIA_ID_LOCAL}"
            return 0
        fi

        error "${NAME} creation failed."
        record_failure "${NAME}"
    fi
}

###############################################################################
# CREATE MEDIA
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
# MEDIA VERIFICATION
###############################################################################

header "Installation Media Verification"

MEDIA_LIST="$(api_get "${API}/media?per_page=all")"

if [ $? -eq 0 ] && is_json "${MEDIA_LIST}"
then
    echo "${MEDIA_LIST}" |
    jq -r '
        .results[] |
        "\(.id)\t\(.name)\t\(.path)"
    '
else
    error "Unable to verify installation media."
    record_failure "Installation Media Verification"
fi

###############################################################################
# FIND ARCHITECTURE
###############################################################################

find_architecture_id()
{
    local NAME="$1"

    local RESPONSE
    local ID

    RESPONSE="$(api_get "${API}/architectures?per_page=all")"

    if [ $? -ne 0 ]
    then
        return 1
    fi

    ID="$(
        echo "${RESPONSE}" |
        jq -r \
            --arg name "${NAME}" \
            '.results[] |
             select(.name == $name) |
             .id' |
        head -n 1
    )"

    printf '%s\n' "${ID}"
}

###############################################################################
# FIND PARTITION TABLE
###############################################################################

find_ptable_id()
{
    local NAME="$1"

    local RESPONSE
    local ID

    RESPONSE="$(api_get "${API}/ptables?per_page=all")"

    if [ $? -ne 0 ]
    then
        return 1
    fi

    ID="$(
        echo "${RESPONSE}" |
        jq -r \
            --arg name "${NAME}" \
            '.results[] |
             select(.name == $name) |
             .id' |
        head -n 1
    )"

    printf '%s\n' "${ID}"
}

###############################################################################
# CACHE ARCHITECTURE
###############################################################################

ARCH_ID="$(find_architecture_id "x86_64")"

if [ -n "${ARCH_ID}" ]
then
    ok "x86_64 architecture found. ID=${ARCH_ID}"
else
    error "x86_64 architecture not found."
    record_failure "x86_64 architecture"
fi

###############################################################################
# CACHE PARTITION TABLE
###############################################################################

PTABLE_ID="$(find_ptable_id "Kickstart default")"

if [ -n "${PTABLE_ID}" ]
then
    ok "Kickstart default partition table found. ID=${PTABLE_ID}"
else
    error "Kickstart default partition table not found."
    record_failure "Kickstart default partition table"
fi

###############################################################################
# FIND OS
###############################################################################

find_os_id()
{
    local NAME="$1"

    local RESPONSE
    local ID

    RESPONSE="$(api_get "${API}/operatingsystems?per_page=all")"

    if [ $? -ne 0 ]
    then
        return 1
    fi

    if ! is_json "${RESPONSE}"
    then
        return 1
    fi

    ID="$(
        echo "${RESPONSE}" |
        jq -r \
            --arg name "${NAME}" \
            '.results[] |
             select(.name == $name) |
             .id' |
        head -n 1
    )"

    printf '%s\n' "${ID}"
}

###############################################################################
# CREATE OS
###############################################################################

create_os()
{
    local OS_NAME="$1"
    local MAJOR="$2"
    local MINOR="$3"
    local MEDIA_NAME="$4"

    local OS_ID
    local MEDIA_ID_LOCAL
    local JSON
    local RESPONSE

    subheader "Operating System : ${OS_NAME}"

    ###########################################################################
    # EXISTING OS
    ###########################################################################

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -n "${OS_ID}" ]
    then
        skip "${OS_NAME} already exists. ID=${OS_ID}"
        return 0
    fi

    ###########################################################################
    # MEDIA
    ###########################################################################

    MEDIA_ID_LOCAL="$(find_media_id "${MEDIA_NAME}")"

    if [ -z "${MEDIA_ID_LOCAL}" ]
    then
        error "Installation media not found : ${MEDIA_NAME}"
        record_failure "${OS_NAME}"
        return 1
    fi

    ###########################################################################
    # DEPENDENCIES
    ###########################################################################

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

    ###########################################################################
    # CREATE
    ###########################################################################

    info "Creating ${OS_NAME}"

    JSON="$(
        jq -n \
            --arg name "${OS_NAME}" \
            --arg major "${MAJOR}" \
            --arg minor "${MINOR}" \
            --arg family "Redhat" \
            --argjson architecture_id "${ARCH_ID}" \
            --argjson media_id "${MEDIA_ID_LOCAL}" \
            --argjson ptable_id "${PTABLE_ID}" \
            '{
                operatingsystem: {
                    name: $name,
                    major: $major,
                    minor: $minor,
                    family: $family,
                    architecture_ids: [$architecture_id],
                    medium_ids: [$media_id],
                    ptable_ids: [$ptable_id]
                }
            }'
    )"

    RESPONSE="$(api_post "${API}/operatingsystems" "${JSON}")"

    if [ $? -eq 0 ]
    then

        OS_ID="$(
            echo "${RESPONSE}" |
            jq -r '.id // empty'
        )"

        ok "${OS_NAME} created. ID=${OS_ID}"

    else

        # Existing object protection.

        OS_ID="$(find_os_id "${OS_NAME}")"

        if [ -n "${OS_ID}" ]
        then
            skip "${OS_NAME} already exists. ID=${OS_ID}"
            return 0
        fi

        error "${OS_NAME} creation failed."
        record_failure "${OS_NAME}"
    fi
}

###############################################################################
# CREATE ALL OS
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
# OS VERIFICATION
###############################################################################

header "Operating System Verification"

OS_LIST="$(api_get "${API}/operatingsystems?per_page=all")"

if [ $? -eq 0 ] && is_json "${OS_LIST}"
then

    echo "${OS_LIST}" |
    jq -r '
        .results[] |
        "\(.id)\t\(.name)\t\(.major)\t\(.minor // "")\t\(.family)"
    '

else

    error "Unable to list operating systems."
    record_failure "Operating System Verification"

fi

###############################################################################
# TEMPLATE DIRECTORY
###############################################################################

TEMPLATE_DIR="${WORK_DIR}/templates"

mkdir -p "${TEMPLATE_DIR}"

###############################################################################
# TEMPLATE CONTENT GENERATOR
###############################################################################

generate_template()
{
    local FILE="$1"
    local TITLE="$2"
    local REPO="$3"

    cat > "${FILE}" <<EOF
set timeout=10

menuentry '${TITLE}' {

    linuxefi <%= @kernel %> \\
        inst.repo=${REPO} \\
        inst.ks=<%= foreman_url('provision') %>

    initrdefi <%= @initrd %>
}
EOF
}

###############################################################################
# GENERATE 8 TEMPLATE FILES
###############################################################################

header "Generating PXEGrub2 Template Files"

generate_template \
    "${TEMPLATE_DIR}/centos-raid.erb" \
    "CentOS 7 RAID" \
    "${CENTOS_MEDIA_URL}"

generate_template \
    "${TEMPLATE_DIR}/centos-singledisk.erb" \
    "CentOS 7 SingleDisk" \
    "${CENTOS_MEDIA_URL}"

generate_template \
    "${TEMPLATE_DIR}/rocky8-raid.erb" \
    "Rocky Linux 8.10 RAID" \
    "${ROCKY8_MEDIA_URL}"

generate_template \
    "${TEMPLATE_DIR}/rocky8-singledisk.erb" \
    "Rocky Linux 8.10 SingleDisk" \
    "${ROCKY8_MEDIA_URL}"

generate_template \
    "${TEMPLATE_DIR}/rocky92-raid.erb" \
    "Rocky Linux 9.2 RAID" \
    "${ROCKY92_MEDIA_URL}"

generate_template \
    "${TEMPLATE_DIR}/rocky92-singledisk.erb" \
    "Rocky Linux 9.2 SingleDisk" \
    "${ROCKY92_MEDIA_URL}"

generate_template \
    "${TEMPLATE_DIR}/rocky98-raid.erb" \
    "Rocky Linux 9.8 RAID" \
    "${ROCKY98_MEDIA_URL}"

generate_template \
    "${TEMPLATE_DIR}/rocky98-singledisk.erb" \
    "Rocky Linux 9.8 SingleDisk" \
    "${ROCKY98_MEDIA_URL}"

ok "All 8 PXEGrub2 template files generated."

###############################################################################
# FIND TEMPLATE KIND
###############################################################################

find_template_kind_id()
{
    local KIND_NAME="$1"

    local RESPONSE
    local ID

    RESPONSE="$(api_get "${API}/template_kinds?per_page=all")"

    if [ $? -ne 0 ]
    then
        return 1
    fi

    if ! is_json "${RESPONSE}"
    then
        return 1
    fi

    ID="$(
        echo "${RESPONSE}" |
        jq -r \
            --arg name "${KIND_NAME}" \
            '.results[] |
             select(.name == $name) |
             .id' |
        head -n 1
    )"

    printf '%s\n' "${ID}"
}

###############################################################################
# GET PXEGRUB2 KIND
###############################################################################

header "Finding PXEGrub2 Template Kind"

PXE_KIND_ID="$(find_template_kind_id "${PXE_TEMPLATE_KIND}")"

if [ -n "${PXE_KIND_ID}" ]
then

    ok "PXEGrub2 template kind found. ID=${PXE_KIND_ID}"

else

    warn "PXEGrub2 template kind is not available in Foreman."
    warn "PXEGrub2 template creation/association/default sections will be skipped."

fi

###############################################################################
# FIND TEMPLATE
###############################################################################

find_template_id()
{
    local NAME="$1"

    local RESPONSE
    local ID

    RESPONSE="$(api_get "${API}/provisioning_templates?per_page=all")"

    if [ $? -ne 0 ]
    then
        return 1
    fi

    if ! is_json "${RESPONSE}"
    then
        return 1
    fi

    ID="$(
        echo "${RESPONSE}" |
        jq -r \
            --arg name "${NAME}" \
            '.results[] |
             select(.name == $name) |
             .id' |
        head -n 1
    )"

    printf '%s\n' "${ID}"
}

###############################################################################
# GET TEMPLATE
###############################################################################

get_template()
{
    local TEMPLATE_ID="$1"

    api_get \
        "${API}/provisioning_templates/${TEMPLATE_ID}"
}

###############################################################################
# CREATE PXE TEMPLATE
###############################################################################

create_pxe_template()
{
    local NAME="$1"
    local FILE="$2"

    local TEMPLATE_ID
    local TEMPLATE_CONTENT
    local JSON
    local RESPONSE

    subheader "PXEGrub2 Template : ${NAME}"

    ###########################################################################
    # KIND NOT AVAILABLE
    ###########################################################################

    if [ -z "${PXE_KIND_ID}" ]
    then
        skip "PXEGrub2 template kind unavailable. Skipping ${NAME}."
        return 0
    fi

    ###########################################################################
    # EXISTING TEMPLATE
    ###########################################################################

    TEMPLATE_ID="$(find_template_id "${NAME}")"

    if [ -n "${TEMPLATE_ID}" ]
    then
        skip "${NAME} already exists. ID=${TEMPLATE_ID}"
        return 0
    fi

    ###########################################################################
    # READ FILE
    ###########################################################################

    if [ ! -f "${FILE}" ]
    then
        error "Template file not found : ${FILE}"
        record_failure "${NAME}"
        return 1
    fi

    TEMPLATE_CONTENT="$(cat "${FILE}")"

    ###########################################################################
    # CREATE JSON
    ###########################################################################

    JSON="$(
        jq -n \
            --arg name "${NAME}" \
            --arg template "${TEMPLATE_CONTENT}" \
            --argjson kind "${PXE_KIND_ID}" \
            '{
                provisioning_template: {
                    name: $name,
                    template: $template,
                    template_kind_id: $kind
                }
            }'
    )"

    ###########################################################################
    # CREATE
    ###########################################################################

    info "Creating ${NAME}"

    RESPONSE="$(api_post "${API}/provisioning_templates" "${JSON}")"

    if [ $? -eq 0 ]
    then

        TEMPLATE_ID="$(
            echo "${RESPONSE}" |
            jq -r '.id // empty'
        )"

        ok "${NAME} created. ID=${TEMPLATE_ID}"

    else

        #######################################################################
        # Existing protection
        #######################################################################

        TEMPLATE_ID="$(find_template_id "${NAME}")"

        if [ -n "${TEMPLATE_ID}" ]
        then
            skip "${NAME} already exists. ID=${TEMPLATE_ID}"
            return 0
        fi

        error "${NAME} creation failed."
        record_failure "${NAME}"

    fi
}

###############################################################################
# CREATE ALL PXE TEMPLATES
###############################################################################

header "Creating PXEGrub2 Templates"

create_pxe_template \
    "${CENTOS_RAID_TEMPLATE}" \
    "${TEMPLATE_DIR}/centos-raid.erb"

create_pxe_template \
    "${CENTOS_SINGLE_TEMPLATE}" \
    "${TEMPLATE_DIR}/centos-singledisk.erb"

create_pxe_template \
    "${ROCKY8_RAID_TEMPLATE}" \
    "${TEMPLATE_DIR}/rocky8-raid.erb"

create_pxe_template \
    "${ROCKY8_SINGLE_TEMPLATE}" \
    "${TEMPLATE_DIR}/rocky8-singledisk.erb"

create_pxe_template \
    "${ROCKY92_RAID_TEMPLATE}" \
    "${TEMPLATE_DIR}/rocky92-raid.erb"

create_pxe_template \
    "${ROCKY92_SINGLE_TEMPLATE}" \
    "${TEMPLATE_DIR}/rocky92-singledisk.erb"

create_pxe_template \
    "${ROCKY98_RAID_TEMPLATE}" \
    "${TEMPLATE_DIR}/rocky98-raid.erb"

create_pxe_template \
    "${ROCKY98_SINGLE_TEMPLATE}" \
    "${TEMPLATE_DIR}/rocky98-singledisk.erb"

###############################################################################
# ASSOCIATE TEMPLATE WITH OS
###############################################################################

associate_os_template()
{
    local OS_ID="$1"
    local TEMPLATE_ID="$2"
    local TEMPLATE_NAME="$3"

    local TEMPLATE_RESPONSE
    local EXISTING_IDS
    local NEW_IDS
    local JSON
    local RESPONSE

    info "Checking association : ${TEMPLATE_NAME}"

    TEMPLATE_RESPONSE="$(
        get_template "${TEMPLATE_ID}"
    )"

    if [ $? -ne 0 ]
    then
        error "Unable to read template : ${TEMPLATE_NAME}"
        record_failure "${TEMPLATE_NAME}"
        return 1
    fi

    EXISTING_IDS="$(
        echo "${TEMPLATE_RESPONSE}" |
        jq -c '
            [
                .operatingsystems[]?.id
            ] |
            map(select(. != null)) |
            unique
        '
    )"

    if [ -z "${EXISTING_IDS}" ]
    then
        EXISTING_IDS="[]"
    fi

    if echo "${EXISTING_IDS}" |
        jq -e \
            --argjson os_id "${OS_ID}" \
            'index($os_id) != null' \
            >/dev/null 2>&1
    then

        skip "Template already associated."
        return 0

    fi

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
        ok "Template associated."
    else
        error "Failed associating ${TEMPLATE_NAME}."
        record_failure "${TEMPLATE_NAME}"
    fi
}

###############################################################################
# ATTACH TEMPLATE
###############################################################################

attach_template()
{
    local OS_NAME="$1"
    local TEMPLATE_NAME="$2"

    local OS_ID
    local TEMPLATE_ID

    subheader "Associating:"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"

    ###########################################################################
    # KIND UNAVAILABLE
    ###########################################################################

    if [ -z "${PXE_KIND_ID}" ]
    then
        skip "PXEGrub2 kind unavailable. Skipping association."
        return 0
    fi

    ###########################################################################
    # OS
    ###########################################################################

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then
        error "OS not found : ${OS_NAME}"
        record_failure "${OS_NAME}"
        return 1
    fi

    ###########################################################################
    # TEMPLATE
    ###########################################################################

    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${TEMPLATE_NAME}"
        return 1
    fi

    ###########################################################################
    # ASSOCIATE
    ###########################################################################

    associate_os_template \
        "${OS_ID}" \
        "${TEMPLATE_ID}" \
        "${TEMPLATE_NAME}"
}

###############################################################################
# TEMPLATE ASSOCIATIONS
###############################################################################

header "Associating PXEGrub2 Templates"

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
# FIND DEFAULT TEMPLATE
###############################################################################

find_default_template()
{
    local OS_ID="$1"
    local TEMPLATE_ID="$2"

    local RESPONSE

    RESPONSE="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    )"

    if [ $? -ne 0 ]
    then
        return 1
    fi

    if ! is_json "${RESPONSE}"
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
# SET DEFAULT TEMPLATE
###############################################################################

set_default_template()
{
    local OS_ID="$1"
    local TEMPLATE_ID="$2"
    local TEMPLATE_NAME="$3"

    local TEMPLATE_RESPONSE
    local TEMPLATE_KIND_ID
    local DEFAULT_ID
    local JSON
    local RESPONSE

    subheader "Setting PXEGrub2 Default:"
    echo "OS       : ${OS_ID}"
    echo "Template : ${TEMPLATE_NAME}"

    ###########################################################################
    # KIND
    ###########################################################################

    if [ -z "${PXE_KIND_ID}" ]
    then
        skip "PXEGrub2 kind unavailable. Skipping default template."
        return 0
    fi

    ###########################################################################
    # TEMPLATE
    ###########################################################################

    TEMPLATE_RESPONSE="$(
        get_template "${TEMPLATE_ID}"
    )"

    if [ $? -ne 0 ]
    then
        error "Unable to read template : ${TEMPLATE_NAME}"
        record_failure "${TEMPLATE_NAME}"
        return 1
    fi

    TEMPLATE_KIND_ID="$(
        echo "${TEMPLATE_RESPONSE}" |
        jq -r '.template_kind_id // empty'
    )"

    if [ -z "${TEMPLATE_KIND_ID}" ]
    then
        TEMPLATE_KIND_ID="${PXE_KIND_ID}"
    fi

    ###########################################################################
    # CHECK EXISTING EXACT DEFAULT
    ###########################################################################

    DEFAULT_ID="$(
        find_default_template \
            "${OS_ID}" \
            "${TEMPLATE_ID}"
    )"

    if [ -n "${DEFAULT_ID}" ]
    then
        skip "Default template already assigned. ID=${DEFAULT_ID}"
        return 0
    fi

    ###########################################################################
    # IMPORTANT:
    #
    # Foreman permits only one default combination per template kind.
    #
    # Therefore, before POST, find any existing PXEGrub2 default for this OS.
    ###########################################################################

    ALL_DEFAULTS="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    )"

    if [ $? -eq 0 ] && is_json "${ALL_DEFAULTS}"
    then

        EXISTING_KIND_DEFAULT_ID="$(
            echo "${ALL_DEFAULTS}" |
            jq -r \
                --argjson kind "${TEMPLATE_KIND_ID}" \
                '.results[] |
                 select(.template_kind_id == $kind) |
                 .id' |
            head -n 1
        )"

        if [ -n "${EXISTING_KIND_DEFAULT_ID}" ]
        then

            EXISTING_DEFAULT_NAME="$(
                echo "${ALL_DEFAULTS}" |
                jq -r \
                    --argjson kind "${TEMPLATE_KIND_ID}" \
                    '.results[] |
                     select(.template_kind_id == $kind) |
                     .provisioning_template_name' |
                head -n 1
            )"

            ###################################################################
            # If same template, already done.
            ###################################################################

            if [ "${EXISTING_DEFAULT_NAME}" = "${TEMPLATE_NAME}" ]
            then
                skip "PXEGrub2 default already points to ${TEMPLATE_NAME}."
                return 0
            fi

            ###################################################################
            # Existing PXEGrub2 default:
            #
            # DO NOT POST another one.
            #
            # Update the existing combination.
            ###################################################################

            info "Existing PXEGrub2 default found:"
            echo "       ${EXISTING_DEFAULT_NAME}"
            info "Updating it to:"
            echo "       ${TEMPLATE_NAME}"

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
                    "${API}/operatingsystems/${OS_ID}/os_default_templates/${EXISTING_KIND_DEFAULT_ID}" \
                    "${JSON}"
            )"

            if [ $? -eq 0 ]
            then
                ok "PXEGrub2 default updated."
            else
                error "Failed updating PXEGrub2 default."
                record_failure "${TEMPLATE_NAME}"
            fi

            return 0
        fi
    fi

    ###########################################################################
    # NO EXISTING DEFAULT
    ###########################################################################

    info "No PXEGrub2 default found. Creating one..."

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

        ok "PXEGrub2 default created. ID=${DEFAULT_ID}"

    else

        #######################################################################
        # Race-condition / already-existing protection.
        #######################################################################

        DEFAULT_ID="$(
            find_default_template \
                "${OS_ID}" \
                "${TEMPLATE_ID}"
        )"

        if [ -n "${DEFAULT_ID}" ]
        then
            skip "PXEGrub2 default already exists. ID=${DEFAULT_ID}"
            return 0
        fi

        error "Failed creating PXEGrub2 default."
        record_failure "${TEMPLATE_NAME}"

    fi
}

###############################################################################
# SET ALL DEFAULTS
###############################################################################

header "Setting PXEGrub2 Default Templates"

set_default_for_os()
{
    local OS_NAME="$1"
    local TEMPLATE_NAME="$2"

    local OS_ID
    local TEMPLATE_ID

    subheader "Setting PXEGrub2 Default:"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"

    if [ -z "${PXE_KIND_ID}" ]
    then
        skip "PXEGrub2 kind unavailable. Skipping."
        return 0
    fi

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then
        error "OS not found : ${OS_NAME}"
        record_failure "${OS_NAME}"
        return 1
    fi

    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${TEMPLATE_NAME}"
        return 1
    fi

    set_default_template \
        "${OS_ID}" \
        "${TEMPLATE_ID}" \
        "${TEMPLATE_NAME}"
}

set_default_for_os \
    "${CENTOS_RAID_NAME}" \
    "${CENTOS_RAID_TEMPLATE}"

set_default_for_os \
    "${CENTOS_SINGLE_NAME}" \
    "${CENTOS_SINGLE_TEMPLATE}"

set_default_for_os \
    "${ROCKY8_RAID_NAME}" \
    "${ROCKY8_RAID_TEMPLATE}"

set_default_for_os \
    "${ROCKY8_SINGLE_NAME}" \
    "${ROCKY8_SINGLE_TEMPLATE}"

set_default_for_os \
    "${ROCKY92_RAID_NAME}" \
    "${ROCKY92_RAID_TEMPLATE}"

set_default_for_os \
    "${ROCKY92_SINGLE_NAME}" \
    "${ROCKY92_SINGLE_TEMPLATE}"

set_default_for_os \
    "${ROCKY98_RAID_NAME}" \
    "${ROCKY98_RAID_TEMPLATE}"

set_default_for_os \
    "${ROCKY98_SINGLE_NAME}" \
    "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# FIND DOMAIN
###############################################################################

find_domain_id()
{
    local NAME="$1"

    local RESPONSE
    local ID

    RESPONSE="$(api_get "${API}/domains?per_page=all")"

    if [ $? -ne 0 ]
    then
        return 1
    fi

    ID="$(
        echo "${RESPONSE}" |
        jq -r \
            --arg name "${NAME}" \
            '.results[] |
             select(.name == $name) |
             .id' |
        head -n 1
    )"

    printf '%s\n' "${ID}"
}

###############################################################################
# FIND SMART PROXY
###############################################################################

find_proxy_id()
{
    local PROXY_NAME="$1"

    local RESPONSE
    local ID

    RESPONSE="$(api_get "${API}/smart_proxies?per_page=all")"

    if [ $? -ne 0 ]
    then
        return 1
    fi

    if ! is_json "${RESPONSE}"
    then
        return 1
    fi

    ID="$(
        echo "${RESPONSE}" |
        jq -r \
            --arg name "${PROXY_NAME}" \
            '.results[] |
             select(.name == $name) |
             .id' |
        head -n 1
    )"

    printf '%s\n' "${ID}"
}

###############################################################################
# FIND PROXY FEATURE
###############################################################################

proxy_has_feature()
{
    local PROXY_ID="$1"
    local FEATURE="$2"

    local RESPONSE

    RESPONSE="$(
        api_get \
            "${API}/smart_proxies/${PROXY_ID}"
    )"

    if [ $? -ne 0 ]
    then
        return 1
    fi

    echo "${RESPONSE}" |
    jq -e \
        --arg feature "${FEATURE}" \
        '.features[]?.name == $feature' \
        >/dev/null 2>&1
}

###############################################################################
# FIND SUBNET
###############################################################################

find_subnet_id()
{
    local NAME="$1"

    local RESPONSE
    local ID

    RESPONSE="$(api_get "${API}/subnets?per_page=all")"

    if [ $? -ne 0 ]
    then
        return 1
    fi

    ID="$(
        echo "${RESPONSE}" |
        jq -r \
            --arg name "${NAME}" \
            '.results[] |
             select(.name == $name) |
             .id' |
        head -n 1
    )"

    printf '%s\n' "${ID}"
}

###############################################################################
# CREATE / UPDATE SUBNET
###############################################################################

create_subnet()
{
    local SUBNET_NAME="$1"
    local NETWORK="$2"
    local MASK="$3"
    local GATEWAY="$4"
    local DNS="$5"
    local TFTP_PROXY="$6"
    local DHCP_PROXY="$7"

    local SUBNET_ID
    local DOMAIN_ID
    local TFTP_ID
    local DHCP_ID

    local JSON
    local RESPONSE

    subheader "Subnet : ${SUBNET_NAME}"

    echo "Network      : ${NETWORK}"
    echo "Mask         : ${MASK}"
    echo "Gateway      : ${GATEWAY}"
    echo "DNS          : ${DNS}"
    echo "TFTP Proxy   : ${TFTP_PROXY}"
    echo "DHCP Proxy   : ${DHCP_PROXY}"

    ###########################################################################
    # EXISTING SUBNET
    ###########################################################################

    SUBNET_ID="$(find_subnet_id "${SUBNET_NAME}")"

    ###########################################################################
    # DOMAIN
    ###########################################################################

    DOMAIN_ID="$(find_domain_id "${DOMAIN_NAME}")"

    if [ -n "${DOMAIN_ID}" ]
    then
        ok "Domain found : ${DOMAIN_NAME} ID=${DOMAIN_ID}"
    else
        warn "Domain not found : ${DOMAIN_NAME}"
    fi

    ###########################################################################
    # TFTP PROXY
    ###########################################################################

    TFTP_ID="$(find_proxy_id "${TFTP_PROXY}")"

    if [ -n "${TFTP_ID}" ]
    then
        ok "TFTP proxy found : ${TFTP_PROXY} ID=${TFTP_ID}"

        if proxy_has_feature "${TFTP_ID}" "TFTP"
        then
            ok "${TFTP_PROXY} has TFTP feature."
        else
            warn "${TFTP_PROXY} does not advertise TFTP feature."
        fi

    else
        warn "TFTP proxy not found : ${TFTP_PROXY}"
    fi

    ###########################################################################
    # DHCP PROXY
    ###########################################################################

    DHCP_ID="$(find_proxy_id "${DHCP_PROXY}")"

    if [ -n "${DHCP_ID}" ]
    then
        ok "DHCP proxy found : ${DHCP_PROXY} ID=${DHCP_ID}"

        if proxy_has_feature "${DHCP_ID}" "DHCP"
        then
            ok "${DHCP_PROXY} has DHCP feature."
        else
            warn "${DHCP_PROXY} does not advertise DHCP feature."
        fi

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
    # UPDATE EXISTING
    ###########################################################################

    if [ -n "${SUBNET_ID}" ]
    then

        skip "${SUBNET_NAME} already exists. ID=${SUBNET_ID}"

        info "Updating existing subnet..."

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

        return 0
    fi

    ###########################################################################
    # CREATE
    ###########################################################################

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

        #######################################################################
        # Existing protection.
        #######################################################################

        SUBNET_ID="$(find_subnet_id "${SUBNET_NAME}")"

        if [ -n "${SUBNET_ID}" ]
        then
            skip "${SUBNET_NAME} already exists. ID=${SUBNET_ID}"
            return 0
        fi

        error "Failed creating ${SUBNET_NAME}."
        record_failure "${SUBNET_NAME}"
    fi
}

###############################################################################
# CREATE SUBNETS
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
# SUBNET VERIFICATION
###############################################################################

header "PXE Subnet Verification"

SUBNET_LIST="$(api_get "${API}/subnets?per_page=all")"

if [ $? -eq 0 ] && is_json "${SUBNET_LIST}"
then

    echo "${SUBNET_LIST}" |
    jq -r '
        .results[] |
        select(
            .name == "vgs-subnet-centos"
            or
            .name == "vgs-subnet-rockyos"
        ) |
        "\(.id)\t\(.name)\t\(.network_address)/\(.mask)\tDHCP=\(.dhcp_name // "-")\tTFTP=\(.tftp_name // "-")"
    '

else

    error "Unable to verify PXE subnets."
    record_failure "PXE Subnet Verification"

fi

###############################################################################
# VERIFY TEMPLATE ASSOCIATION
###############################################################################

verify_template_mapping()
{
    local OS_NAME="$1"
    local TEMPLATE_NAME="$2"

    local OS_ID
    local TEMPLATE_ID
    local RESPONSE
    local MATCH

    subheader "OS Template Mapping"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"

    if [ -z "${PXE_KIND_ID}" ]
    then
        skip "PXEGrub2 kind unavailable. Skipping verification."
        return 0
    fi

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then
        error "OS not found : ${OS_NAME}"
        record_failure "${OS_NAME}"
        return 1
    fi

    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${TEMPLATE_NAME}"
        return 1
    fi

    RESPONSE="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}/provisioning_templates?per_page=all"
    )"

    if [ $? -ne 0 ]
    then
        error "Unable to read OS template mappings."
        record_failure "${OS_NAME}"
        return 1
    fi

    MATCH="$(
        echo "${RESPONSE}" |
        jq -r \
            --argjson template_id "${TEMPLATE_ID}" \
            '.results[] |
             select(.id == $template_id) |
             .name' |
        head -n 1
    )"

    if [ -n "${MATCH}" ]
    then
        ok "${OS_NAME} -> ${TEMPLATE_NAME}"
    else
        error "Template mapping missing."
        record_failure "${OS_NAME}"
    fi
}

###############################################################################
# TEMPLATE MAPPING VERIFICATION
###############################################################################

header "OS Template Mapping Verification"

verify_template_mapping \
    "${CENTOS_RAID_NAME}" \
    "${CENTOS_RAID_TEMPLATE}"

verify_template_mapping \
    "${CENTOS_SINGLE_NAME}" \
    "${CENTOS_SINGLE_TEMPLATE}"

verify_template_mapping \
    "${ROCKY8_RAID_NAME}" \
    "${ROCKY8_RAID_TEMPLATE}"

verify_template_mapping \
    "${ROCKY8_SINGLE_NAME}" \
    "${ROCKY8_SINGLE_TEMPLATE}"

verify_template_mapping \
    "${ROCKY92_RAID_NAME}" \
    "${ROCKY92_RAID_TEMPLATE}"

verify_template_mapping \
    "${ROCKY92_SINGLE_NAME}" \
    "${ROCKY92_SINGLE_TEMPLATE}"

verify_template_mapping \
    "${ROCKY98_RAID_NAME}" \
    "${ROCKY98_RAID_TEMPLATE}"

verify_template_mapping \
    "${ROCKY98_SINGLE_NAME}" \
    "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# VERIFY DEFAULT TEMPLATE
###############################################################################

verify_default_template()
{
    local OS_NAME="$1"
    local TEMPLATE_NAME="$2"

    local OS_ID
    local TEMPLATE_ID
    local RESPONSE
    local MATCH

    subheader "PXEGrub2 Default Verification"
    echo "OS       : ${OS_NAME}"
    echo "Expected : ${TEMPLATE_NAME}"

    if [ -z "${PXE_KIND_ID}" ]
    then
        skip "PXEGrub2 kind unavailable. Skipping verification."
        return 0
    fi

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then
        error "OS not found : ${OS_NAME}"
        record_failure "${OS_NAME}"
        return 1
    fi

    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${TEMPLATE_NAME}"
        return 1
    fi

    RESPONSE="$(
        api_get \
            "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    )"

    if [ $? -ne 0 ]
    then
        error "Unable to read default templates."
        record_failure "${OS_NAME}"
        return 1
    fi

    MATCH="$(
        echo "${RESPONSE}" |
        jq -r \
            --argjson template_id "${TEMPLATE_ID}" \
            '.results[] |
             select(.provisioning_template_id == $template_id) |
             .provisioning_template_name' |
        head -n 1
    )"

    if [ -n "${MATCH}" ]
    then
        ok "${TEMPLATE_NAME} is PXEGrub2 default."
    else
        error "${TEMPLATE_NAME} is not PXEGrub2 default."
        record_failure "${OS_NAME}"
    fi
}

###############################################################################
# DEFAULT VERIFICATION
###############################################################################

header "PXEGrub2 Default Template Verification"

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
# FINAL OS VERIFICATION
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
    echo -e "${WHITE}------------------------------------------------------------${NC}"
    echo -e "${WHITE}OS : ${OS_NAME}${NC}"
    echo -e "${WHITE}ID : ${OS_ID}${NC}"
    echo -e "${WHITE}------------------------------------------------------------${NC}"

    echo "${OS_RESPONSE}" |
    jq -r '
        "Name         : \(.name)",
        "Major        : \(.major)",
        "Minor        : \(.minor // "")",
        "Family       : \(.family)",
        "Architecture : ([.architectures[]?.name] | join(", "))",
        "Media        : ([.media[]?.name] | join(", "))",
        "Ptable       : ([.ptables[]?.name] | join(", "))"
    '

done

###############################################################################
# PXE TEMPLATE LIST
###############################################################################

header "PXEGrub2 Template Verification"

if [ -n "${PXE_KIND_ID}" ]
then

    TEMPLATE_LIST="$(
        api_get \
            "${API}/provisioning_templates?per_page=all"
    )"

    if [ $? -eq 0 ] && is_json "${TEMPLATE_LIST}"
    then

        echo "${TEMPLATE_LIST}" |
        jq -r \
            --arg kind "${PXE_TEMPLATE_KIND}" \
            '.results[] |
             select(.template_kind_name == $kind) |
             "\(.id)\t\(.name)\tkind=\(.template_kind_name)"'

    else

        warn "Unable to list PXEGrub2 templates."

    fi

else

    skip "PXEGrub2 template kind unavailable."

fi

###############################################################################
# PXE SUBNET FINAL CHECK
###############################################################################

header "PXE Subnet Final Verification"

SUBNET_LIST="$(
    api_get \
        "${API}/subnets?per_page=all"
)"

if [ $? -eq 0 ] && is_json "${SUBNET_LIST}"
then

    echo "${SUBNET_LIST}" |
    jq -r '
        .results[] |
        select(
            .name == "vgs-subnet-centos"
            or
            .name == "vgs-subnet-rockyos"
        ) |
        "\(.id)\t\(.name)\t\(.network_address)/\(.mask)\tDHCP=\(.dhcp_name // "-")\tTFTP=\(.tftp_name // "-")"
    '

else

    warn "Unable to list PXE subnets."

fi

###############################################################################
# SUMMARY
###############################################################################

header "01 - Foreman PXE Bootstrap API Completed"

if [ "${#FAILED_STEPS[@]}" -eq 0 ]
then

    success "PXE Bootstrap API completed successfully."

else

    warn "Completed with ${#FAILED_STEPS[@]} failure(s)."

    echo
    echo -e "${RED}Failed Steps:${NC}"

    for ITEM in "${FAILED_STEPS[@]}"
    do
        error "${ITEM}"
    done

fi

###############################################################################
# AUTHENTICATION INFORMATION
###############################################################################

echo
echo -e "${BLUE}------------------------------------------------------------${NC}"
echo -e "${WHITE}Authentication${NC}"
echo -e "${BLUE}------------------------------------------------------------${NC}"

echo "Method        : Foreman REST API"
echo "Username      : ${FOREMAN_USER}"
echo "Authentication: Personal Access Token"
echo "Hammer        : NOT USED"
echo "curl          : USED"
echo "API           : ${API}"

###############################################################################
# MANUAL API TEST COMMANDS
###############################################################################

echo
echo -e "${BLUE}------------------------------------------------------------${NC}"
echo -e "${WHITE}Manual API Verification${NC}"
echo -e "${BLUE}------------------------------------------------------------${NC}"

echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \"
echo "  ${API}/status"

echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \"
echo "  ${API}/media"

echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \"
echo "  ${API}/operatingsystems"

echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \"
echo "  ${API}/provisioning_templates"

echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \"
echo "  ${API}/template_kinds"

echo
echo 'curl -k --user "admin:$FOREMAN_TOKEN" \'
echo "  -H 'Accept: application/json,version=2' \"
echo "  ${API}/subnets"

###############################################################################
# EXIT
###############################################################################

if [ "${#FAILED_STEPS[@]}" -eq 0 ]
then
    exit 0
else
    exit 1
fi
