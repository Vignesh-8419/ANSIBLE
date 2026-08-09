#!/bin/bash
###############################################################################
# 03 - Foreman Hostgroup Bootstrap - RAID - REST API
#
# Purpose:
#   Create and configure RAID Hostgroups through Foreman REST API.
#
# Hostgroups:
#   CentOSLinux7-RAID
#   RockyLinux8.10-RAID
#   RockyLinux9.2-RAID
#   RockyLinux9.8-RAID
#
# Dependencies:
#   01_foreman_pxe_bootstrap_api.sh
#   02_foreman_pxe_bootstrap_single_disk_api.sh
#
# Supported:
#   TARGET_VERSION=9.2
#   TARGET_VERSION=9.8
#   TARGET_VERSION=ALL
#
# Foreman:
#   API Version 2
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

###############################################################################
# Script Header
###############################################################################

header "03 - Foreman Hostgroup Bootstrap - RAID - REST API"

###############################################################################
# Dependencies
###############################################################################

header "Dependency Check"

REQUIRED_COMMANDS=(
    curl
    jq
    cat
    head
    grep
    awk
    mkdir
    rm
    mktemp
    ls
)

for CMD in "${REQUIRED_COMMANDS[@]}"
do
    CMD_PATH=$(command -v "${CMD}" 2>/dev/null)

    if [ -n "${CMD_PATH}" ]
    then
        ok "${CMD} found: ${CMD_PATH}"
    else
        error "${CMD} not found."
        record_failure "Dependency: ${CMD}"
    fi
done

if [ ${#FAILED_STEPS[@]} -ne 0 ]
then
    error "Required dependencies are missing."
    exit 1
fi

###############################################################################
# Foreman Configuration
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
FOREMAN_USER="${FOREMAN_USER:-admin}"

#
# Prefer environment variable.
# If FOREMAN_PASSWORD is not supplied, use existing lab password.
#
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"

API_VERSION="${API_VERSION:-2}"

###############################################################################
# Global Configuration
###############################################################################

DOMAIN_NAME="${DOMAIN_NAME:-vgs.com}"

LOCATION_NAME="${LOCATION_NAME:-Default Location}"

ORGANIZATION_NAME="${ORGANIZATION_NAME:-Default Organization}"

CENTOS_SUBNET_NAME="${CENTOS_SUBNET_NAME:-vgs-subnet-centos}"

ROCKY_SUBNET_NAME="${ROCKY_SUBNET_NAME:-vgs-subnet-rockyos}"

ARCHITECTURE_NAME="${ARCHITECTURE_NAME:-x86_64}"

PARTITION_TABLE_NAME="${PARTITION_TABLE_NAME:-Kickstart default}"

PXE_LOADER="${PXE_LOADER:-Grub2 UEFI}"

TARGET_VERSION="${TARGET_VERSION:-ALL}"

###############################################################################
# API Temporary Directory
###############################################################################

TMP_DIR="/tmp/foreman-hostgroup-bootstrap"

mkdir -p "${TMP_DIR}"

###############################################################################
# Display Configuration
###############################################################################

echo
echo "Foreman URL    : ${FOREMAN_URL}"
echo "API Version    : ${API_VERSION}"
echo "Target Version : ${TARGET_VERSION}"
echo

###############################################################################
# API Headers
###############################################################################

API_ACCEPT="Accept: application/json,version=${API_VERSION}"
API_CONTENT_TYPE="Content-Type: application/json"

###############################################################################
# API Helper
###############################################################################

API_RESPONSE_FILE=""

api_request()
{
    METHOD="$1"
    ENDPOINT="$2"
    DATA="$3"

    API_RESPONSE_FILE=$(mktemp "${TMP_DIR}/api-response.XXXXXX")

    if [ "${METHOD}" = "GET" ]
    then

        HTTP_STATUS=$(
            curl -ksS \
                --user "${FOREMAN_USER}:${FOREMAN_PASSWORD}" \
                -H "${API_ACCEPT}" \
                -o "${API_RESPONSE_FILE}" \
                -w "%{http_code}" \
                "${FOREMAN_URL}${ENDPOINT}"
        )

    else

        HTTP_STATUS=$(
            curl -ksS \
                --user "${FOREMAN_USER}:${FOREMAN_PASSWORD}" \
                -H "${API_ACCEPT}" \
                -H "${API_CONTENT_TYPE}" \
                -X "${METHOD}" \
                -d "${DATA}" \
                -o "${API_RESPONSE_FILE}" \
                -w "%{http_code}" \
                "${FOREMAN_URL}${ENDPOINT}"
        )

    fi

    API_BODY=$(cat "${API_RESPONSE_FILE}")

    return 0
}

###############################################################################
# API GET Helper
###############################################################################

api_get()
{
    ENDPOINT="$1"

    api_request "GET" "${ENDPOINT}" ""

    if [[ "${HTTP_STATUS}" =~ ^2[0-9][0-9]$ ]]
    then
        cat "${API_RESPONSE_FILE}"
        return 0
    fi

    return 1
}

###############################################################################
# API POST Helper
###############################################################################

api_post()
{
    ENDPOINT="$1"
    DATA="$2"

    api_request "POST" "${ENDPOINT}" "${DATA}"

    if [[ "${HTTP_STATUS}" =~ ^2[0-9][0-9]$ ]]
    then
        cat "${API_RESPONSE_FILE}"
        return 0
    fi

    return 1
}

###############################################################################
# API PUT Helper
###############################################################################

api_put()
{
    ENDPOINT="$1"
    DATA="$2"

    api_request "PUT" "${ENDPOINT}" "${DATA}"

    if [[ "${HTTP_STATUS}" =~ ^2[0-9][0-9]$ ]]
    then
        cat "${API_RESPONSE_FILE}"
        return 0
    fi

    return 1
}

###############################################################################
# API Error Display
###############################################################################

show_api_error()
{
    METHOD="$1"
    ENDPOINT="$2"

    error "API request failed."
    error "HTTP Status : ${HTTP_STATUS}"
    error "Method      : ${METHOD}"
    error "URL         : ${FOREMAN_URL}${ENDPOINT}"

    if echo "${API_BODY}" | jq . >/dev/null 2>&1
    then
        echo "${API_BODY}" | jq
    else
        echo "${API_BODY}"
    fi
}

###############################################################################
# Foreman API Authentication
###############################################################################

header "Foreman API Authentication Test"

info "Testing Foreman REST API..."

api_request "GET" "/api/status" ""

if [[ "${HTTP_STATUS}" =~ ^2[0-9][0-9]$ ]]
then

    FOREMAN_VERSION=$(
        echo "${API_BODY}" |
        jq -r '.version // empty'
    )

    FOREMAN_API_VERSION=$(
        echo "${API_BODY}" |
        jq -r '.api_version // empty'
    )

    ok "Foreman API authentication successful."

    echo "Foreman Version : ${FOREMAN_VERSION}"
    echo "API Version     : ${FOREMAN_API_VERSION}"
    echo "API Status      : ${HTTP_STATUS}"

else

    show_api_error "GET" "/api/status"
    record_failure "Foreman API authentication"
    exit 1
fi

###############################################################################
# Generic Named Resource ID Lookup
###############################################################################

get_named_id()
{
    ENDPOINT="$1"
    NAME="$2"

    RESPONSE=$(
        api_get "${ENDPOINT}"
    )

    if [ $? -ne 0 ]
    then
        return 1
    fi

    echo "${RESPONSE}" |
    jq -r --arg NAME "${NAME}" '
        .results[]?
        | select(
            (.name // "") == $NAME
            or
            (.title // "") == $NAME
        )
        | .id
    ' |
    head -1
}

###############################################################################
# OS ID Lookup
###############################################################################

get_os_id()
{
    OS_NAME="$1"

    RESPONSE=$(
        api_get "/api/operatingsystems?per_page=all"
    )

    if [ $? -ne 0 ]
    then
        return 1
    fi

    echo "${RESPONSE}" |
    jq -r --arg NAME "${OS_NAME}" '
        .results[]
        | select(.name == $NAME)
        | .id
    ' |
    head -1
}

###############################################################################
# Template ID Lookup
###############################################################################

get_template_id()
{
    TEMPLATE_NAME="$1"

    RESPONSE=$(
        api_get "/api/provisioning_templates?per_page=all"
    )

    if [ $? -ne 0 ]
    then
        return 1
    fi

    echo "${RESPONSE}" |
    jq -r --arg NAME "${TEMPLATE_NAME}" '
        .results[]
        | select(.name == $NAME)
        | .id
    ' |
    head -1
}

###############################################################################
# Template Kind ID Lookup
#
# We derive template_kind_id from provisioning_templates because
# 02_foreman_pxe_bootstrap_single_disk_api.sh already uses this successfully.
###############################################################################

get_template_kind_id()
{
    KIND_NAME="$1"

    RESPONSE=$(
        api_get \
            "/api/provisioning_templates?per_page=all"
    )

    if [ $? -ne 0 ]
    then
        return 1
    fi

    echo "${RESPONSE}" |
    jq -r --arg KIND "${KIND_NAME}" '
        .results[]?
        | select(.template_kind_name == $KIND)
        | .template_kind_id
    ' |
    sort -n |
    uniq |
    head -1
}

###############################################################################
# Hostgroup ID Lookup
###############################################################################

get_hostgroup_id()
{
    HOSTGROUP_NAME="$1"

    RESPONSE=$(
        api_get "/api/hostgroups?per_page=all"
    )

    if [ $? -ne 0 ]
    then
        return 1
    fi

    echo "${RESPONSE}" |
    jq -r --arg NAME "${HOSTGROUP_NAME}" '
        .results[]
        | select(.name == $NAME)
        | .id
    ' |
    head -1
}

###############################################################################
# Organization ID Lookup
###############################################################################

get_organization_id()
{
    NAME="$1"

    RESPONSE=$(
        api_get "/api/organizations/1"
    )

    if [ $? -ne 0 ]
    then
        return 1
    fi

    echo "${RESPONSE}" |
    jq -r --arg NAME "${NAME}" '
        select(.name == $NAME) |
        .id
    ' |
    head -1
}


###############################################################################
# Location ID Lookup
###############################################################################

get_location_id()
{
    NAME="$1"

    RESPONSE=$(
        api_get "/api/organizations/1"
    )

    if [ $? -ne 0 ]
    then
        return 1
    fi

    echo "${RESPONSE}" |
    jq -r --arg NAME "${NAME}" '
        .locations[]? |
        select(.name == $NAME) |
        .id
    ' |
    head -1
}

###############################################################################
# Resolve Required IDs
###############################################################################

header "Resolving Foreman Resource IDs"

info "Finding Organization : ${ORGANIZATION_NAME}"

ORGANIZATION_ID=$(
    get_organization_id "${ORGANIZATION_NAME}"
)

if [ -n "${ORGANIZATION_ID}" ]
then
    ok "Organization ID : ${ORGANIZATION_ID}"
else
    error "Organization not found : ${ORGANIZATION_NAME}"
    record_failure "Organization: ${ORGANIZATION_NAME}"
fi

###############################################################################

info "Finding Location : ${LOCATION_NAME}"

LOCATION_ID=$(
    get_location_id "${LOCATION_NAME}"
)

if [ -n "${LOCATION_ID}" ]
then
    ok "Location ID : ${LOCATION_ID}"
else
    error "Location not found : ${LOCATION_NAME}"
    record_failure "Location: ${LOCATION_NAME}"
fi

###############################################################################

info "Finding Architecture : ${ARCHITECTURE_NAME}"

ARCHITECTURE_ID=$(
    get_named_id \
        "/api/architectures?per_page=all" \
        "${ARCHITECTURE_NAME}"
)

if [ -n "${ARCHITECTURE_ID}" ]
then
    ok "Architecture ID : ${ARCHITECTURE_ID}"
else
    error "Architecture not found : ${ARCHITECTURE_NAME}"
    record_failure "Architecture: ${ARCHITECTURE_NAME}"
fi

###############################################################################

info "Finding Partition Table : ${PARTITION_TABLE_NAME}"

PTABLE_ID=$(
    get_named_id \
        "/api/ptables?per_page=all" \
        "${PARTITION_TABLE_NAME}"
)

if [ -n "${PTABLE_ID}" ]
then
    ok "Partition Table ID : ${PTABLE_ID}"
else
    error "Partition table not found : ${PARTITION_TABLE_NAME}"
    record_failure "Partition Table: ${PARTITION_TABLE_NAME}"
fi

###############################################################################

info "Finding PXEGrub2 Template Kind"

PXEGRUB2_KIND_ID=$(
    get_template_kind_id "PXEGrub2"
)

if [ -n "${PXEGRUB2_KIND_ID}" ]
then
    ok "PXEGrub2 Template Kind ID : ${PXEGRUB2_KIND_ID}"
else
    error "PXEGrub2 template kind not found."
    record_failure "PXEGrub2 Template Kind"
fi

###############################################################################
# Subnet Lookup
###############################################################################

info "Finding CentOS Subnet : ${CENTOS_SUBNET_NAME}"

CENTOS_SUBNET_ID=$(
    get_named_id \
        "/api/subnets?per_page=all" \
        "${CENTOS_SUBNET_NAME}"
)

if [ -n "${CENTOS_SUBNET_ID}" ]
then
    ok "CentOS Subnet ID : ${CENTOS_SUBNET_ID}"
else
    error "CentOS subnet not found : ${CENTOS_SUBNET_NAME}"
    record_failure "CentOS Subnet: ${CENTOS_SUBNET_NAME}"
fi

###############################################################################

info "Finding Rocky Subnet : ${ROCKY_SUBNET_NAME}"

ROCKY_SUBNET_ID=$(
    get_named_id \
        "/api/subnets?per_page=all" \
        "${ROCKY_SUBNET_NAME}"
)

if [ -n "${ROCKY_SUBNET_ID}" ]
then
    ok "Rocky Subnet ID : ${ROCKY_SUBNET_ID}"
else
    error "Rocky subnet not found : ${ROCKY_SUBNET_NAME}"
    record_failure "Rocky Subnet: ${ROCKY_SUBNET_NAME}"
fi

###############################################################################
# Stop if Base Resources Missing
###############################################################################

if [ ${#FAILED_STEPS[@]} -ne 0 ]
then

    header "Resource Resolution Failed"

    warn "Required Foreman resources could not be resolved."

    for STEP in "${FAILED_STEPS[@]}"
    do
        error "${STEP}"
    done

    exit 1
fi

###############################################################################
# OS Configuration
###############################################################################

CENTOS_RAID_OS="CentOSLinux7-RAID"

ROCKY8_RAID_OS="RockyLinux8.10-RAID"

ROCKY92_RAID_OS="RockyLinux9.2-RAID"

ROCKY98_RAID_OS="RockyLinux9.8-RAID"

###############################################################################
# PXE Template Configuration
###############################################################################

CENTOS_RAID_TEMPLATE="PXEGrub2 CentOS UEFI RAID Kickstart"

ROCKY8_RAID_TEMPLATE="PXEGrub2 Rocky8 UEFI RAID Kickstart"

ROCKY92_RAID_TEMPLATE="PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

ROCKY98_RAID_TEMPLATE="PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

###############################################################################
# Media Configuration
###############################################################################

CENTOS_MEDIA="CentOS 7 Remote"

ROCKY8_MEDIA="Rocky 8 Remote"

ROCKY92_MEDIA="Rocky 9.2 Remote"

ROCKY98_MEDIA="Rocky 9 Remote"

###############################################################################
# Resolve Media IDs
###############################################################################

header "Resolving Installation Media"

info "Finding Media : ${CENTOS_MEDIA}"

CENTOS_MEDIA_ID=$(
    get_named_id \
        "/api/media?per_page=all" \
        "${CENTOS_MEDIA}"
)

if [ -n "${CENTOS_MEDIA_ID}" ]
then
    ok "CentOS Media ID : ${CENTOS_MEDIA_ID}"
else
    error "Media not found : ${CENTOS_MEDIA}"
    record_failure "Media: ${CENTOS_MEDIA}"
fi

###############################################################################

info "Finding Media : ${ROCKY8_MEDIA}"

ROCKY8_MEDIA_ID=$(
    get_named_id \
        "/api/media?per_page=all" \
        "${ROCKY8_MEDIA}"
)

if [ -n "${ROCKY8_MEDIA_ID}" ]
then
    ok "Rocky 8 Media ID : ${ROCKY8_MEDIA_ID}"
else
    error "Media not found : ${ROCKY8_MEDIA}"
    record_failure "Media: ${ROCKY8_MEDIA}"
fi

###############################################################################

info "Finding Media : ${ROCKY92_MEDIA}"

ROCKY92_MEDIA_ID=$(
    get_named_id \
        "/api/media?per_page=all" \
        "${ROCKY92_MEDIA}"
)

if [ -n "${ROCKY92_MEDIA_ID}" ]
then
    ok "Rocky 9.2 Media ID : ${ROCKY92_MEDIA_ID}"
else
    error "Media not found : ${ROCKY92_MEDIA}"
    record_failure "Media: ${ROCKY92_MEDIA}"
fi

###############################################################################

info "Finding Media : ${ROCKY98_MEDIA}"

ROCKY98_MEDIA_ID=$(
    get_named_id \
        "/api/media?per_page=all" \
        "${ROCKY98_MEDIA}"
)

if [ -n "${ROCKY98_MEDIA_ID}" ]
then
    ok "Rocky 9.8 Media ID : ${ROCKY98_MEDIA_ID}"
else
    error "Media not found : ${ROCKY98_MEDIA}"
    record_failure "Media: ${ROCKY98_MEDIA}"
fi

###############################################################################
# Check Media Resolution
###############################################################################

if [ ${#FAILED_STEPS[@]} -ne 0 ]
then

    header "Media Resolution Failed"

    for STEP in "${FAILED_STEPS[@]}"
    do
        error "${STEP}"
    done

    exit 1
fi

###############################################################################
# Target Version Selection
###############################################################################

case "${TARGET_VERSION}" in

    9.2)

        RAID_OS_LIST=(
            "${CENTOS_RAID_OS}"
            "${ROCKY8_RAID_OS}"
            "${ROCKY92_RAID_OS}"
        )

        RAID_HOSTGROUP_LIST=(
            "CentOSLinux7-RAID"
            "RockyLinux8.10-RAID"
            "RockyLinux9.2-RAID"
        )

        ;;

    9.8)

        RAID_OS_LIST=(
            "${CENTOS_RAID_OS}"
            "${ROCKY8_RAID_OS}"
            "${ROCKY98_RAID_OS}"
        )

        RAID_HOSTGROUP_LIST=(
            "CentOSLinux7-RAID"
            "RockyLinux8.10-RAID"
            "RockyLinux9.8-RAID"
        )

        ;;

    ALL)

        RAID_OS_LIST=(
            "${CENTOS_RAID_OS}"
            "${ROCKY8_RAID_OS}"
            "${ROCKY92_RAID_OS}"
            "${ROCKY98_RAID_OS}"
        )

        RAID_HOSTGROUP_LIST=(
            "CentOSLinux7-RAID"
            "RockyLinux8.10-RAID"
            "RockyLinux9.2-RAID"
            "RockyLinux9.8-RAID"
        )

        ;;

    *)

        error "Unsupported TARGET_VERSION=${TARGET_VERSION}"
        error "Supported values: 9.2 | 9.8 | ALL"
        exit 1

        ;;

esac

###############################################################################
# Display Selected Configuration
###############################################################################

header "Selected RAID Configuration"

echo
echo "TARGET_VERSION : ${TARGET_VERSION}"
echo

for HG in "${RAID_HOSTGROUP_LIST[@]}"
do
    echo "Hostgroup : ${HG}"
done

echo

###############################################################################
# Hostgroup Create Function
###############################################################################

create_hostgroup()
{
    HOSTGROUP_NAME="$1"
    SUBNET_ID="$2"
    OS_NAME="$3"
    MEDIA_ID="$4"

    echo
    echo "------------------------------------------------------------"
    echo "Hostgroup : ${HOSTGROUP_NAME}"
    echo "OS        : ${OS_NAME}"
    echo "Subnet    : ${SUBNET_ID}"
    echo "Media     : ${MEDIA_ID}"
    echo "------------------------------------------------------------"

    ###########################################################################
    # Check Existing Hostgroup
    ###########################################################################

    EXISTING_HG_ID=$(
        get_hostgroup_id "${HOSTGROUP_NAME}"
    )

    if [ -n "${EXISTING_HG_ID}" ]
    then

        skip "${HOSTGROUP_NAME} already exists. ID=${EXISTING_HG_ID}"

        return 0
    fi

    ###########################################################################
    # Get OS ID
    ###########################################################################

    OS_ID=$(
        get_os_id "${OS_NAME}"
    )

    if [ -z "${OS_ID}" ]
    then

        error "Operating System not found : ${OS_NAME}"

        record_failure "${HOSTGROUP_NAME} -> OS"

        return 1
    fi

    ok "Operating System ID : ${OS_ID}"

    ###########################################################################
    # Create Hostgroup JSON
    ###########################################################################

    PAYLOAD=$(
        jq -n \
            --arg NAME "${HOSTGROUP_NAME}" \
            --argjson ORG "${ORGANIZATION_ID}" \
            --argjson LOC "${LOCATION_ID}" \
            --argjson SUBNET "${SUBNET_ID}" \
            --argjson DOMAIN "${DOMAIN_ID}" \
            --argjson OS "${OS_ID}" \
            --argjson ARCH "${ARCHITECTURE_ID}" \
            --argjson MEDIA "${MEDIA_ID}" \
            --argjson PTABLE "${PTABLE_ID}" \
            --arg PXE "${PXE_LOADER}" \
            '{
                hostgroup: {
                    name: $NAME,
                    organization_id: $ORG,
                    location_id: $LOC,
                    subnet_id: $SUBNET,
                    domain_id: $DOMAIN,
                    operatingsystem_id: $OS,
                    architecture_id: $ARCH,
                    medium_id: $MEDIA,
                    ptable_id: $PTABLE,
                    pxe_loader: $PXE
                }
            }'
    )

    ###########################################################################
    # Create Hostgroup
    ###########################################################################

    info "Creating ${HOSTGROUP_NAME}..."

    api_post \
        "/api/hostgroups" \
        "${PAYLOAD}" >/dev/null

    if [[ "${HTTP_STATUS}" =~ ^2[0-9][0-9]$ ]]
    then

        CREATED_ID=$(
            echo "${API_BODY}" |
            jq -r '.id // empty'
        )

        ok "${HOSTGROUP_NAME} created. ID=${CREATED_ID}"

    else

        show_api_error \
            "POST" \
            "/api/hostgroups"

        record_failure "${HOSTGROUP_NAME}"

        return 1
    fi

    echo
}

###############################################################################
# Resolve Domain ID
###############################################################################

header "Resolving Domain"

DOMAIN_ID=$(
    get_named_id \
        "/api/domains?per_page=all" \
        "${DOMAIN_NAME}"
)

if [ -n "${DOMAIN_ID}" ]
then

    ok "Domain ID : ${DOMAIN_ID}"

else

    error "Domain not found : ${DOMAIN_NAME}"

    record_failure "Domain: ${DOMAIN_NAME}"

fi

###############################################################################
# Create Hostgroups
###############################################################################

header "[1/5] Creating RAID Hostgroups"

###############################################################################
# CentOS 7
###############################################################################

create_hostgroup \
    "CentOSLinux7-RAID" \
    "${CENTOS_SUBNET_ID}" \
    "${CENTOS_RAID_OS}" \
    "${CENTOS_MEDIA_ID}"

###############################################################################
# Rocky 8.10
###############################################################################

create_hostgroup \
    "RockyLinux8.10-RAID" \
    "${ROCKY_SUBNET_ID}" \
    "${ROCKY8_RAID_OS}" \
    "${ROCKY8_MEDIA_ID}"

###############################################################################
# Rocky 9.2
###############################################################################

if [ "${TARGET_VERSION}" = "9.2" ] || [ "${TARGET_VERSION}" = "ALL" ]
then

    create_hostgroup \
        "RockyLinux9.2-RAID" \
        "${ROCKY_SUBNET_ID}" \
        "${ROCKY92_RAID_OS}" \
        "${ROCKY92_MEDIA_ID}"

fi

###############################################################################
# Rocky 9.8
###############################################################################

if [ "${TARGET_VERSION}" = "9.8" ] || [ "${TARGET_VERSION}" = "ALL" ]
then

    create_hostgroup \
        "RockyLinux9.8-RAID" \
        "${ROCKY_SUBNET_ID}" \
        "${ROCKY98_RAID_OS}" \
        "${ROCKY98_MEDIA_ID}"

fi

###############################################################################
# Verify OS Exists
###############################################################################

verify_os_exists()
{
    OS_NAME="$1"

    OS_ID=$(
        get_os_id "${OS_NAME}"
    )

    if [ -n "${OS_ID}" ]
    then

        ok "${OS_NAME} exists. ID=${OS_ID}"

        return 0

    else

        error "${OS_NAME} not found."

        record_failure "${OS_NAME}"

        return 1
    fi
}

###############################################################################
# Template Association Function
###############################################################################

associate_template()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    echo
    echo "------------------------------------------------------------"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"
    echo "------------------------------------------------------------"

    ###########################################################################
    # Get OS ID
    ###########################################################################

    OS_ID=$(
        get_os_id "${OS_NAME}"
    )

    if [ -z "${OS_ID}" ]
    then

        error "Operating System not found : ${OS_NAME}"

        record_failure "${OS_NAME}"

        return 1
    fi

    ok "Operating System ID : ${OS_ID}"

    ###########################################################################
    # Get Template ID
    ###########################################################################

    TEMPLATE_ID=$(
        get_template_id "${TEMPLATE_NAME}"
    )

    if [ -z "${TEMPLATE_ID}" ]
    then

        error "Provisioning template not found : ${TEMPLATE_NAME}"

        record_failure "${TEMPLATE_NAME}"

        return 1
    fi

    ok "Template ID : ${TEMPLATE_ID}"

    ###########################################################################
    # Get Existing OS
    ###########################################################################

    OS_RESPONSE=$(
        api_get "/api/operatingsystems/${OS_ID}"
    )

    if [ $? -ne 0 ]
    then

        show_api_error \
            "GET" \
            "/api/operatingsystems/${OS_ID}"

        record_failure "${OS_NAME} lookup"

        return 1
    fi

    ###########################################################################
    # Check Existing Association
    ###########################################################################

    EXISTING_TEMPLATE=$(
        echo "${OS_RESPONSE}" |
        jq -r \
            --argjson ID "${TEMPLATE_ID}" '
            .provisioning_templates[]
            | select(.id == $ID)
            | .id
        ' |
        head -1
    )

    if [ -n "${EXISTING_TEMPLATE}" ]
    then

        skip "${TEMPLATE_NAME} already associated."

        return 0
    fi

    ###########################################################################
    # Preserve Existing Template IDs
    ###########################################################################

    TEMPLATE_IDS_JSON=$(
        echo "${OS_RESPONSE}" |
        jq -c '
            [
                .provisioning_templates[]?.id
            ]
        '
    )

    NEW_TEMPLATE_IDS=$(
        echo "${TEMPLATE_IDS_JSON}" |
        jq -c \
            --argjson NEW_ID "${TEMPLATE_ID}" '
            . + [$NEW_ID] | unique
        '
    )

    ###########################################################################
    # Update OS Template Association
    ###########################################################################

    PAYLOAD=$(
        jq -n \
            --argjson IDS "${NEW_TEMPLATE_IDS}" '
            {
                operatingsystem: {
                    provisioning_template_ids: $IDS
                }
            }
        '
    )

    info "Associating template through REST API..."

    api_put \
        "/api/operatingsystems/${OS_ID}" \
        "${PAYLOAD}" >/dev/null

    if [[ "${HTTP_STATUS}" =~ ^2[0-9][0-9]$ ]]
    then

        ok "${TEMPLATE_NAME} associated."

    else

        show_api_error \
            "PUT" \
            "/api/operatingsystems/${OS_ID}"

        record_failure "${OS_NAME} -> ${TEMPLATE_NAME}"

        return 1
    fi
}

###############################################################################
# [2/5] RAID Template Association
###############################################################################

header "[2/5] Associating RAID PXE Templates"

###############################################################################
# CentOS
###############################################################################

associate_template \
    "${CENTOS_RAID_OS}" \
    "${CENTOS_RAID_TEMPLATE}"

###############################################################################
# Rocky 8
###############################################################################

associate_template \
    "${ROCKY8_RAID_OS}" \
    "${ROCKY8_RAID_TEMPLATE}"

###############################################################################
# Rocky 9.2
###############################################################################

if [ "${TARGET_VERSION}" = "9.2" ] || [ "${TARGET_VERSION}" = "ALL" ]
then

    associate_template \
        "${ROCKY92_RAID_OS}" \
        "${ROCKY92_RAID_TEMPLATE}"

fi

###############################################################################
# Rocky 9.8
###############################################################################

if [ "${TARGET_VERSION}" = "9.8" ] || [ "${TARGET_VERSION}" = "ALL" ]
then

    associate_template \
        "${ROCKY98_RAID_OS}" \
        "${ROCKY98_RAID_TEMPLATE}"

fi

###############################################################################
# Set Default PXEGrub2 Function
###############################################################################

set_default_template()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    echo
    echo "------------------------------------------------------------"
    echo "PXEGrub2 Default Template"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"
    echo "------------------------------------------------------------"

    ###########################################################################
    # OS ID
    ###########################################################################

    OS_ID=$(
        get_os_id "${OS_NAME}"
    )

    if [ -z "${OS_ID}" ]
    then

        error "Operating System not found : ${OS_NAME}"

        record_failure "${OS_NAME}"

        return 1
    fi

    ok "Operating System ID : ${OS_ID}"

    ###########################################################################
    # Template ID
    ###########################################################################

    TEMPLATE_ID=$(
        get_template_id "${TEMPLATE_NAME}"
    )

    if [ -z "${TEMPLATE_ID}" ]
    then

        error "Template not found : ${TEMPLATE_NAME}"

        record_failure "${TEMPLATE_NAME}"

        return 1
    fi

    ok "Template ID : ${TEMPLATE_ID}"

    ###########################################################################
    # Template Kind
    ###########################################################################

    KIND_ID="${PXEGRUB2_KIND_ID}"

    ok "PXEGrub2 Template Kind ID : ${KIND_ID}"

    ###########################################################################
    # Existing Defaults
    ###########################################################################

    DEFAULT_RESPONSE=$(
        api_get \
            "/api/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    )

    if [ $? -ne 0 ]
    then

        show_api_error \
            "GET" \
            "/api/operatingsystems/${OS_ID}/os_default_templates"

        record_failure "${OS_NAME} default lookup"

        return 1
    fi

    ###########################################################################
    # Find PXEGrub2 Default
    ###########################################################################

    DEFAULT_ID=$(
        echo "${DEFAULT_RESPONSE}" |
        jq -r \
            --argjson KIND "${KIND_ID}" '
            .results[]
            | select(.template_kind_id == $KIND)
            | .id
        ' |
        head -1
    )

    EXISTING_DEFAULT_TEMPLATE_ID=$(
        echo "${DEFAULT_RESPONSE}" |
        jq -r \
            --argjson KIND "${KIND_ID}" '
            .results[]
            | select(.template_kind_id == $KIND)
            | .provisioning_template_id
        ' |
        head -1
    )

    ###########################################################################
    # Correct Default Already Exists
    ###########################################################################

    if [ -n "${DEFAULT_ID}" ] &&
       [ "${EXISTING_DEFAULT_TEMPLATE_ID}" = "${TEMPLATE_ID}" ]
    then

        skip "PXEGrub2 default already exists for ${OS_NAME}. Nothing to change."

        return 0
    fi

    ###########################################################################
    # Existing PXEGrub2 Default But Wrong Template
    ###########################################################################

    if [ -n "${DEFAULT_ID}" ]
    then

        warn "PXEGrub2 default exists with another template."
        info "Updating existing default instead of creating duplicate."

        PAYLOAD=$(
            jq -n \
                --argjson TEMPLATE "${TEMPLATE_ID}" \
                --argjson KIND "${KIND_ID}" '
                {
                    os_default_template: {
                        provisioning_template_id: $TEMPLATE,
                        template_kind_id: $KIND
                    }
                }
            '
        )

        api_put \
            "/api/operatingsystems/${OS_ID}/os_default_templates/${DEFAULT_ID}" \
            "${PAYLOAD}" >/dev/null

        if [[ "${HTTP_STATUS}" =~ ^2[0-9][0-9]$ ]]
        then

            ok "PXEGrub2 default updated."
            return 0

        else

            show_api_error \
                "PUT" \
                "/api/operatingsystems/${OS_ID}/os_default_templates/${DEFAULT_ID}"

            record_failure "${OS_NAME} default update"

            return 1
        fi
    fi

    ###########################################################################
    # Create New Default
    ###########################################################################

    info "Creating PXEGrub2 default..."

    PAYLOAD=$(
        jq -n \
            --argjson TEMPLATE "${TEMPLATE_ID}" \
            --argjson KIND "${KIND_ID}" '
            {
                os_default_template: {
                    provisioning_template_id: $TEMPLATE,
                    template_kind_id: $KIND
                }
            }
        '
    )

    api_post \
        "/api/operatingsystems/${OS_ID}/os_default_templates" \
        "${PAYLOAD}" >/dev/null

    if [[ "${HTTP_STATUS}" =~ ^2[0-9][0-9]$ ]]
    then

        CREATED_DEFAULT_ID=$(
            echo "${API_BODY}" |
            jq -r '.id // empty'
        )

        ok "PXEGrub2 default created. ID=${CREATED_DEFAULT_ID}"

    else

        #
        # Defensive handling:
        # If Foreman says template_kind_id is already taken,
        # re-read and update rather than reporting a failure.
        #
        if echo "${API_BODY}" |
            grep -q "template_kind_id.*already been taken"
        then

            warn "PXEGrub2 default already exists. Re-checking."

            DEFAULT_RESPONSE=$(
                api_get \
                    "/api/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
            )

            DEFAULT_ID=$(
                echo "${DEFAULT_RESPONSE}" |
                jq -r \
                    --argjson KIND "${KIND_ID}" '
                    .results[]
                    | select(.template_kind_id == $KIND)
                    | .id
                ' |
                head -1
            )

            if [ -n "${DEFAULT_ID}" ]
            then

                PAYLOAD=$(
                    jq -n \
                        --argjson TEMPLATE "${TEMPLATE_ID}" \
                        --argjson KIND "${KIND_ID}" '
                        {
                            os_default_template: {
                                provisioning_template_id: $TEMPLATE,
                                template_kind_id: $KIND
                            }
                        }
                    '
                )

                api_put \
                    "/api/operatingsystems/${OS_ID}/os_default_templates/${DEFAULT_ID}" \
                    "${PAYLOAD}" >/dev/null

                if [[ "${HTTP_STATUS}" =~ ^2[0-9][0-9]$ ]]
                then

                    ok "Existing PXEGrub2 default verified/updated."

                else

                    show_api_error \
                        "PUT" \
                        "/api/operatingsystems/${OS_ID}/os_default_templates/${DEFAULT_ID}"

                    record_failure "${OS_NAME} default"

                fi

            else

                show_api_error \
                    "POST" \
                    "/api/operatingsystems/${OS_ID}/os_default_templates"

                record_failure "${OS_NAME} default"

            fi

        else

            show_api_error \
                "POST" \
                "/api/operatingsystems/${OS_ID}/os_default_templates"

            record_failure "${OS_NAME} default"

        fi
    fi

    echo
}

###############################################################################
# [3/5] Set RAID PXEGrub2 Defaults
###############################################################################

header "[3/5] Setting RAID PXEGrub2 Defaults"

###############################################################################
# CentOS
###############################################################################

set_default_template \
    "${CENTOS_RAID_OS}" \
    "${CENTOS_RAID_TEMPLATE}"

###############################################################################
# Rocky 8
###############################################################################

set_default_template \
    "${ROCKY8_RAID_OS}" \
    "${ROCKY8_RAID_TEMPLATE}"

###############################################################################
# Rocky 9.2
###############################################################################

if [ "${TARGET_VERSION}" = "9.2" ] || [ "${TARGET_VERSION}" = "ALL" ]
then

    set_default_template \
        "${ROCKY92_RAID_OS}" \
        "${ROCKY92_RAID_TEMPLATE}"

fi

###############################################################################
# Rocky 9.8
###############################################################################

if [ "${TARGET_VERSION}" = "9.8" ] || [ "${TARGET_VERSION}" = "ALL" ]
then

    set_default_template \
        "${ROCKY98_RAID_OS}" \
        "${ROCKY98_RAID_TEMPLATE}"

fi

###############################################################################
# Hostgroup Verification
###############################################################################

verify_hostgroup()
{
    HOSTGROUP_NAME="$1"

    echo
    echo "------------------------------------------------------------"
    echo "Hostgroup : ${HOSTGROUP_NAME}"
    echo "------------------------------------------------------------"

    HG_RESPONSE=$(
        api_get \
            "/api/hostgroups?search=name%3D%22${HOSTGROUP_NAME}%22"
    )

    if [ $? -ne 0 ]
    then

        show_api_error \
            "GET" \
            "/api/hostgroups"

        error "${HOSTGROUP_NAME} verification failed."

        record_failure "${HOSTGROUP_NAME} verification"

        return 1
    fi

    HG_ID=$(
        echo "${HG_RESPONSE}" |
        jq -r '.results[0].id // empty'
    )

    if [ -n "${HG_ID}" ]
    then

        ok "${HOSTGROUP_NAME} exists. ID=${HG_ID}"

    else

        error "${HOSTGROUP_NAME} not found."

        record_failure "${HOSTGROUP_NAME}"

    fi
}

###############################################################################
# Template Association Verification
###############################################################################

verify_template_mapping()
{
    OS_NAME="$1"
    EXPECTED_TEMPLATE="$2"

    echo
    echo "------------------------------------------------------------"
    echo "OS       : ${OS_NAME}"
    echo "Expected : ${EXPECTED_TEMPLATE}"
    echo "------------------------------------------------------------"

    OS_ID=$(
        get_os_id "${OS_NAME}"
    )

    if [ -z "${OS_ID}" ]
    then

        error "Operating System not found : ${OS_NAME}"

        record_failure "${OS_NAME}"

        return 1
    fi

    TEMPLATE_ID=$(
        get_template_id "${EXPECTED_TEMPLATE}"
    )

    if [ -z "${TEMPLATE_ID}" ]
    then

        error "Template not found : ${EXPECTED_TEMPLATE}"

        record_failure "${EXPECTED_TEMPLATE}"

        return 1
    fi

    OS_RESPONSE=$(
        api_get \
            "/api/operatingsystems/${OS_ID}"
    )

    if [ $? -ne 0 ]
    then

        show_api_error \
            "GET" \
            "/api/operatingsystems/${OS_ID}"

        record_failure "${OS_NAME} template verification"

        return 1
    fi

    MATCH=$(
        echo "${OS_RESPONSE}" |
        jq -r \
            --argjson TEMPLATE "${TEMPLATE_ID}" '
            .provisioning_templates[]
            | select(.id == $TEMPLATE)
            | .id
        ' |
        head -1
    )

    if [ -n "${MATCH}" ]
    then

        ok "Template mapping correct."

    else

        error "Template mapping missing."

        record_failure "${OS_NAME} -> ${EXPECTED_TEMPLATE}"

    fi
}

###############################################################################
# Default Template Verification
###############################################################################

verify_default_template()
{
    OS_NAME="$1"
    EXPECTED_TEMPLATE="$2"

    echo
    echo "------------------------------------------------------------"
    echo "OS       : ${OS_NAME}"
    echo "Expected : ${EXPECTED_TEMPLATE}"
    echo "------------------------------------------------------------"

    OS_ID=$(
        get_os_id "${OS_NAME}"
    )

    if [ -z "${OS_ID}" ]
    then

        error "Operating System not found : ${OS_NAME}"

        record_failure "${OS_NAME}"

        return 1
    fi

    TEMPLATE_ID=$(
        get_template_id "${EXPECTED_TEMPLATE}"
    )

    if [ -z "${TEMPLATE_ID}" ]
    then

        error "Template not found : ${EXPECTED_TEMPLATE}"

        record_failure "${EXPECTED_TEMPLATE}"

        return 1
    fi

    DEFAULT_RESPONSE=$(
        api_get \
            "/api/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    )

    if [ $? -ne 0 ]
    then

        show_api_error \
            "GET" \
            "/api/operatingsystems/${OS_ID}/os_default_templates"

        record_failure "${OS_NAME} default verification"

        return 1
    fi

    DEFAULT_ID=$(
        echo "${DEFAULT_RESPONSE}" |
        jq -r \
            --argjson KIND "${PXEGRUB2_KIND_ID}" '
            .results[]
            | select(.template_kind_id == $KIND)
            | .id
        ' |
        head -1
    )

    DEFAULT_TEMPLATE_ID=$(
        echo "${DEFAULT_RESPONSE}" |
        jq -r \
            --argjson KIND "${PXEGRUB2_KIND_ID}" '
            .results[]
            | select(.template_kind_id == $KIND)
            | .provisioning_template_id
        ' |
        head -1
    )

    DEFAULT_TEMPLATE_NAME=$(
        echo "${DEFAULT_RESPONSE}" |
        jq -r \
            --argjson KIND "${PXEGRUB2_KIND_ID}" '
            .results[]
            | select(.template_kind_id == $KIND)
            | .provisioning_template_name
        ' |
        head -1
    )

    if [ -n "${DEFAULT_ID}" ] &&
       [ "${DEFAULT_TEMPLATE_ID}" = "${TEMPLATE_ID}" ]
    then

        echo "Default ID    : ${DEFAULT_ID}"
        echo "Template ID   : ${DEFAULT_TEMPLATE_ID}"
        echo "Template Name : ${DEFAULT_TEMPLATE_NAME}"

        ok "PXEGrub2 default mapping correct."

    else

        error "PXEGrub2 default mapping missing or incorrect."

        record_failure "${OS_NAME} default"

    fi
}

###############################################################################
# [4/5] Verification
###############################################################################

header "[4/5] RAID Hostgroup Verification"

###############################################################################
# CentOS
###############################################################################

verify_hostgroup \
    "CentOSLinux7-RAID"

###############################################################################
# Rocky 8
###############################################################################

verify_hostgroup \
    "RockyLinux8.10-RAID"

###############################################################################
# Rocky 9.2
###############################################################################

if [ "${TARGET_VERSION}" = "9.2" ] || [ "${TARGET_VERSION}" = "ALL" ]
then

    verify_hostgroup \
        "RockyLinux9.2-RAID"

fi

###############################################################################
# Rocky 9.8
###############################################################################

if [ "${TARGET_VERSION}" = "9.8" ] || [ "${TARGET_VERSION}" = "ALL" ]
then

    verify_hostgroup \
        "RockyLinux9.8-RAID"

fi

###############################################################################
# Template Mapping Verification
###############################################################################

header "RAID Template Mapping Verification"

verify_template_mapping \
    "${CENTOS_RAID_OS}" \
    "${CENTOS_RAID_TEMPLATE}"

verify_template_mapping \
    "${ROCKY8_RAID_OS}" \
    "${ROCKY8_RAID_TEMPLATE}"

if [ "${TARGET_VERSION}" = "9.2" ] || [ "${TARGET_VERSION}" = "ALL" ]
then

    verify_template_mapping \
        "${ROCKY92_RAID_OS}" \
        "${ROCKY92_RAID_TEMPLATE}"

fi

if [ "${TARGET_VERSION}" = "9.8" ] || [ "${TARGET_VERSION}" = "ALL" ]
then

    verify_template_mapping \
        "${ROCKY98_RAID_OS}" \
        "${ROCKY98_RAID_TEMPLATE}"

fi

###############################################################################
# Default Verification
###############################################################################

header "RAID PXEGrub2 Default Verification"

verify_default_template \
    "${CENTOS_RAID_OS}" \
    "${CENTOS_RAID_TEMPLATE}"

verify_default_template \
    "${ROCKY8_RAID_OS}" \
    "${ROCKY8_RAID_TEMPLATE}"

if [ "${TARGET_VERSION}" = "9.2" ] || [ "${TARGET_VERSION}" = "ALL" ]
then

    verify_default_template \
        "${ROCKY92_RAID_OS}" \
        "${ROCKY92_RAID_TEMPLATE}"

fi

if [ "${TARGET_VERSION}" = "9.8" ] || [ "${TARGET_VERSION}" = "ALL" ]
then

    verify_default_template \
        "${ROCKY98_RAID_OS}" \
        "${ROCKY98_RAID_TEMPLATE}"

fi

###############################################################################
# [5/5] Final API Verification
###############################################################################

header "[5/5] Final RAID Configuration Verification"

###############################################################################
# Hostgroups
###############################################################################

header "RAID Hostgroups"

HOSTGROUP_RESPONSE=$(
    api_get \
        "/api/hostgroups?per_page=all"
)

if [ $? -eq 0 ]
then

    echo "${HOSTGROUP_RESPONSE}" |
    jq -r '
        .results[]
        | [
            .id,
            .name,
            (.operatingsystem_name // "-"),
            (.subnet_name // "-"),
            (.medium_name // "-"),
            (.pxe_loader // "-")
        ]
        | @tsv
    ' |
    grep -E \
        "CentOSLinux7-RAID|RockyLinux8.10-RAID|RockyLinux9.2-RAID|RockyLinux9.8-RAID"

else

    show_api_error \
        "GET" \
        "/api/hostgroups"

    record_failure "Final Hostgroup Verification"
fi

echo

###############################################################################
# RAID Operating Systems
###############################################################################

header "RAID Operating Systems"

OS_RESPONSE=$(
    api_get \
        "/api/operatingsystems?per_page=all"
)

if [ $? -eq 0 ]
then

    echo "${OS_RESPONSE}" |
    jq -r '
        .results[]
        | [
            .id,
            .name,
            (.major // ""),
            (.minor // ""),
            (.family // "")
        ]
        | @tsv
    ' |
    grep -E \
        "CentOSLinux7-RAID|RockyLinux8.10-RAID|RockyLinux9.2-RAID|RockyLinux9.8-RAID"

else

    show_api_error \
        "GET" \
        "/api/operatingsystems"

    record_failure "Final OS Verification"
fi

echo

###############################################################################
# RAID Templates
###############################################################################

header "RAID PXEGrub2 Templates"

TEMPLATE_RESPONSE=$(
    api_get \
        "/api/provisioning_templates?per_page=all"
)

if [ $? -eq 0 ]
then

    echo "${TEMPLATE_RESPONSE}" |
    jq -r '
        .results[]
        | select(.template_kind_name == "PXEGrub2")
        | [
            .id,
            .name,
            .template_kind_id,
            .template_kind_name
        ]
        | @tsv
    ' |
    grep "RAID"

else

    show_api_error \
        "GET" \
        "/api/provisioning_templates"

    record_failure "Final Template Verification"
fi

echo

###############################################################################
# Final Configuration Summary
###############################################################################

header "RAID Configuration Summary"

cat <<EOF

Target Version:
${TARGET_VERSION}

Hostgroups:

CentOSLinux7-RAID
 |
 +-- OS       : CentOSLinux7-RAID
 +-- PXE      : PXEGrub2 CentOS UEFI RAID Kickstart
 +-- Media    : CentOS 7 Remote
 +-- Subnet   : ${CENTOS_SUBNET_NAME}
 +-- PXE Loader: ${PXE_LOADER}

RockyLinux8.10-RAID
 |
 +-- OS       : RockyLinux8.10-RAID
 +-- PXE      : PXEGrub2 Rocky8 UEFI RAID Kickstart
 +-- Media    : Rocky 8 Remote
 +-- Subnet   : ${ROCKY_SUBNET_NAME}
 +-- PXE Loader: ${PXE_LOADER}

RockyLinux9.2-RAID
 |
 +-- OS       : RockyLinux9.2-RAID
 +-- PXE      : PXEGrub2 Rocky9.2 UEFI RAID Kickstart
 +-- Media    : Rocky 9.2 Remote
 +-- Subnet   : ${ROCKY_SUBNET_NAME}
 +-- PXE Loader: ${PXE_LOADER}

RockyLinux9.8-RAID
 |
 +-- OS       : RockyLinux9.8-RAID
 +-- PXE      : PXEGrub2 Rocky9.8 UEFI RAID Kickstart
 +-- Media    : Rocky 9 Remote
 +-- Subnet   : ${ROCKY_SUBNET_NAME}
 +-- PXE Loader: ${PXE_LOADER}


Disk Layout:

RAID1
 |
 +-- EFI
 |
 +-- RAID /boot
 |
 +-- RAID LVM
      |
      +-- /
      +-- swap
      +-- /home

EOF

###############################################################################
# Final Status
###############################################################################

header "03 - Foreman RAID Hostgroup Bootstrap Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]
then

    ok "RAID Hostgroup Bootstrap completed successfully."

else

    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

    for STEP in "${FAILED_STEPS[@]}"
    do
        error "${STEP}"
    done

fi

###############################################################################
# Manual Verification Commands
###############################################################################

header "Manual Verification Commands"

echo
echo "1. Foreman API Status"
echo "------------------------------------------------------------"
echo 'curl -ksS --user "admin:$FOREMAN_PASSWORD" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  \"${FOREMAN_URL}/api/status\" | jq"

echo
echo "2. RAID Hostgroups"
echo "------------------------------------------------------------"
echo 'curl -ksS --user "admin:$FOREMAN_PASSWORD" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  \"${FOREMAN_URL}/api/hostgroups?per_page=all\" | jq"

echo
echo "3. RAID Operating Systems"
echo "------------------------------------------------------------"
echo 'curl -ksS --user "admin:$FOREMAN_PASSWORD" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  \"${FOREMAN_URL}/api/operatingsystems?per_page=all\" | jq -r \\"
echo "  '.results[] | [.id,.name,.major,.minor,.family] | @tsv'"

echo
echo "4. RAID PXEGrub2 Templates"
echo "------------------------------------------------------------"
echo 'curl -ksS --user "admin:$FOREMAN_PASSWORD" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  \"${FOREMAN_URL}/api/provisioning_templates?per_page=all\" | jq -r \\"
echo "  '.results[] | select(.template_kind_name==\"PXEGrub2\") | [.id,.name,.template_kind_id,.template_kind_name] | @tsv'"

echo
echo "5. CentOS RAID OS"
echo "------------------------------------------------------------"
echo 'curl -ksS --user "admin:$FOREMAN_PASSWORD" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  \"${FOREMAN_URL}/api/operatingsystems?per_page=all\" | jq -r \\"
echo "  '.results[] | select(.name==\"CentOSLinux7-RAID\")'"

echo
echo "6. Rocky 8.10 RAID OS"
echo "------------------------------------------------------------"
echo 'curl -ksS --user "admin:$FOREMAN_PASSWORD" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  \"${FOREMAN_URL}/api/operatingsystems?per_page=all\" | jq -r \\"
echo "  '.results[] | select(.name==\"RockyLinux8.10-RAID\")'"

echo
echo "7. Rocky 9.2 RAID OS"
echo "------------------------------------------------------------"
echo 'curl -ksS --user "admin:$FOREMAN_PASSWORD" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  \"${FOREMAN_URL}/api/operatingsystems?per_page=all\" | jq -r \\"
echo "  '.results[] | select(.name==\"RockyLinux9.2-RAID\")'"

echo
echo "8. Rocky 9.8 RAID OS"
echo "------------------------------------------------------------"
echo 'curl -ksS --user "admin:$FOREMAN_PASSWORD" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  \"${FOREMAN_URL}/api/operatingsystems?per_page=all\" | jq -r \\"
echo "  '.results[] | select(.name==\"RockyLinux9.8-RAID\")'"

echo
echo "9. PXEGrub2 Defaults"
echo "------------------------------------------------------------"
echo 'curl -ksS --user "admin:$FOREMAN_PASSWORD" \'
echo "  -H 'Accept: application/json,version=2' \\"
echo "  \"${FOREMAN_URL}/api/operatingsystems/${CENTOS_RAID_OS}/os_default_templates?per_page=all\" | jq"

###############################################################################
# Cleanup
###############################################################################

rm -f "${TMP_DIR}"/api-response.* 2>/dev/null

###############################################################################
# Exit
###############################################################################

if [ ${#FAILED_STEPS[@]} -eq 0 ]
then
    exit 0
else
    exit 1
fi
