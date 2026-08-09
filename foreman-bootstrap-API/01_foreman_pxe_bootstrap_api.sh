#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap - REST API
#
# Foreman 3.2.x
#
# Purpose:
#   - Installation Media
#   - Operating Systems
#   - PXEGrub2 Templates
#   - OS <-> PXEGrub2 associations
#   - PXEGrub2 default templates
#   - PXE Subnets
#
# Design:
#   - Fully idempotent
#   - Existing resources are SKIPPED
#   - Existing resources are never blindly POSTed
#   - Existing PXEGrub2 default is UPDATED when necessary
#   - Uses Personal Access Token
#
###############################################################################

set -u
set -o pipefail

###############################################################################
# Configuration
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
FOREMAN_API="${FOREMAN_URL}/api"

FOREMAN_USER="${FOREMAN_USER:-admin}"

# IMPORTANT:
# Do NOT put the PAT directly into the script.
#
# Before running:
#
# export FOREMAN_USER='admin'
# export FOREMAN_TOKEN='YOUR_PAT'
#
FOREMAN_TOKEN="${FOREMAN_TOKEN:-}"

WORK_DIR="/tmp/foreman-pxe-bootstrap"

###############################################################################
# Absolute command paths
###############################################################################

CURL="$(command -v curl 2>/dev/null || true)"
JQ="$(command -v jq 2>/dev/null || true)"
CAT="$(command -v cat 2>/dev/null || true)"
HEAD="$(command -v head 2>/dev/null || true)"
GREP="$(command -v grep 2>/dev/null || true)"
AWK="$(command -v awk 2>/dev/null || true)"
SED="$(command -v sed 2>/dev/null || true)"
MKDIR="$(command -v mkdir 2>/dev/null || true)"
MKTEMP="$(command -v mktemp 2>/dev/null || true)"
RM="$(command -v rm 2>/dev/null || true)"
DATE="$(command -v date 2>/dev/null || true)"
HOSTNAME="$(command -v hostname 2>/dev/null || true)"

###############################################################################
# Colors
###############################################################################

if [ -t 1 ]; then

    C_RESET=$'\033[0m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_MAGENTA=$'\033[35m'
    C_CYAN=$'\033[36m'
    C_WHITE=$'\033[37m'
    C_BOLD=$'\033[1m'

else

    C_RESET=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_MAGENTA=""
    C_CYAN=""
    C_WHITE=""
    C_BOLD=""

fi

###############################################################################
# Counters
###############################################################################

ERROR_COUNT=0
CREATED_COUNT=0
UPDATED_COUNT=0
SKIPPED_COUNT=0

###############################################################################
# API temporary files
###############################################################################

API_BODY_FILE=""
API_HEADERS_FILE=""
API_STATUS=""

###############################################################################
# Global IDs
###############################################################################

ARCH_ID=""
PTABLE_ID=""
PXEGRUB2_KIND_ID=""

###############################################################################
# Logging
###############################################################################

header()
{
    echo
    echo "${C_CYAN}${C_BOLD}============================================================${C_RESET}"
    echo "${C_CYAN}${C_BOLD}$1${C_RESET}"
    echo "${C_CYAN}${C_BOLD}============================================================${C_RESET}"
}

section()
{
    echo
    echo "${C_BLUE}${C_BOLD}------------------------------------------------------------${C_RESET}"
    echo "${C_BLUE}${C_BOLD}$1${C_RESET}"
    echo "${C_BLUE}${C_BOLD}------------------------------------------------------------${C_RESET}"
}

info()
{
    echo "${C_CYAN}[INFO]${C_RESET} $1"
}

ok()
{
    echo "${C_GREEN}[OK]${C_RESET} $1"
}

skip()
{
    echo "${C_YELLOW}[SKIP]${C_RESET} $1"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
}

warn()
{
    echo "${C_YELLOW}[WARN]${C_RESET} $1"
}

error()
{
    echo "${C_RED}[ERROR]${C_RESET} $1"
    ERROR_COUNT=$((ERROR_COUNT + 1))
}

created()
{
    echo "${C_GREEN}[CREATED]${C_RESET} $1"
    CREATED_COUNT=$((CREATED_COUNT + 1))
}

updated()
{
    echo "${C_MAGENTA}[UPDATED]${C_RESET} $1"
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
}

###############################################################################
# Failure tracking
###############################################################################

FAILURES=()

record_failure()
{
    FAILURES+=("$1")
}

###############################################################################
# Dependency check
###############################################################################

check_command()
{
    CMD_NAME="$1"
    CMD_PATH="$2"

    if [ -z "${CMD_PATH}" ]; then
        error "${CMD_NAME} not found."
        return 1
    fi

    ok "${CMD_NAME} found: ${CMD_PATH}"
    return 0
}

###############################################################################
# Cleanup
###############################################################################

cleanup()
{
    if [ -n "${API_BODY_FILE}" ] &&
       [ -f "${API_BODY_FILE}" ]; then
        "${RM}" -f "${API_BODY_FILE}"
    fi

    if [ -n "${API_HEADERS_FILE}" ] &&
       [ -f "${API_HEADERS_FILE}" ]; then
        "${RM}" -f "${API_HEADERS_FILE}"
    fi
}

trap cleanup EXIT

###############################################################################
# JSON validation
###############################################################################

json_valid()
{
    [ -s "${API_BODY_FILE}" ] &&
        "${JQ}" -e . "${API_BODY_FILE}" >/dev/null 2>&1
}

###############################################################################
# API request
#
# Usage:
#   api_request METHOD URL [JSON]
#
# Result:
#   API_STATUS
#   API_BODY_FILE
###############################################################################

api_request()
{
    METHOD="$1"
    URL="$2"
    JSON_DATA="${3:-}"

    API_BODY_FILE="$("${MKTEMP}")"
    API_HEADERS_FILE="$("${MKTEMP}")"

    if [ -n "${JSON_DATA}" ]; then

        "${CURL}" \
            --silent \
            --show-error \
            --insecure \
            --request "${METHOD}" \
            --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
            --header "Accept: application/json,version=2" \
            --header "Content-Type: application/json" \
            --data "${JSON_DATA}" \
            --output "${API_BODY_FILE}" \
            --dump-header "${API_HEADERS_FILE}" \
            --write-out "%{http_code}" \
            "${URL}" \
            > "${API_HEADERS_FILE}.status" 2>"${API_HEADERS_FILE}.curlerr"

    else

        "${CURL}" \
            --silent \
            --show-error \
            --insecure \
            --request "${METHOD}" \
            --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
            --header "Accept: application/json,version=2" \
            --output "${API_BODY_FILE}" \
            --dump-header "${API_HEADERS_FILE}" \
            --write-out "%{http_code}" \
            "${URL}" \
            > "${API_HEADERS_FILE}.status" 2>"${API_HEADERS_FILE}.curlerr"

    fi

    CURL_RC=$?

    if [ "${CURL_RC}" -ne 0 ]; then

        API_STATUS=""

        echo
        error "API request failed."
        error "curl return code : ${CURL_RC}"
        error "Method           : ${METHOD}"
        error "URL              : ${URL}"

        if [ -s "${API_HEADERS_FILE}.curlerr" ]; then
            "${CAT}" "${API_HEADERS_FILE}.curlerr"
        fi

        return 1
    fi

    API_STATUS="$("${CAT}" "${API_HEADERS_FILE}.status" 2>/dev/null)"

    if [ -z "${API_STATUS}" ]; then
        API_STATUS=""
    fi

    return 0
}

###############################################################################
# API error display
###############################################################################

show_api_error()
{
    echo

    if [ -s "${API_BODY_FILE}" ]; then

        if json_valid; then
            "${JQ}" . "${API_BODY_FILE}"
        else
            "${CAT}" "${API_BODY_FILE}"
        fi

    else

        echo "(empty API response)"

    fi
}

###############################################################################
# Verify API response
###############################################################################

api_success()
{
    [[ "${API_STATUS}" =~ ^2[0-9][0-9]$ ]]
}

###############################################################################
# Dependency check
###############################################################################

header "Dependency Check"

check_command "curl" "${CURL}" || exit 1
check_command "jq" "${JQ}" || exit 1
check_command "cat" "${CAT}" || exit 1
check_command "head" "${HEAD}" || exit 1
check_command "grep" "${GREP}" || exit 1
check_command "awk" "${AWK}" || exit 1
check_command "sed" "${SED}" || exit 1
check_command "mkdir" "${MKDIR}" || exit 1
check_command "mktemp" "${MKTEMP}" || exit 1

###############################################################################
# PAT check
###############################################################################

if [ -z "${FOREMAN_TOKEN}" ]; then

    error "FOREMAN_TOKEN is not set."

    echo
    echo "Set the PAT before running:"
    echo
    echo "  export FOREMAN_USER='admin'"
    echo "  export FOREMAN_TOKEN='YOUR_PERSONAL_ACCESS_TOKEN'"
    echo
    exit 1

fi

###############################################################################
# Create working directory
###############################################################################

"${MKDIR}" -p "${WORK_DIR}"

###############################################################################
# Foreman API authentication
###############################################################################

header "01 - Foreman PXE Bootstrap - REST API"

header "Foreman API Authentication Test"

info "Testing Foreman REST API..."

api_request \
    GET \
    "${FOREMAN_API}/status"

if ! api_success; then

    error "Foreman API authentication failed."
    error "HTTP Status : ${API_STATUS}"
    show_api_error
    exit 1

fi

if ! json_valid; then

    error "Foreman returned invalid JSON."
    show_api_error
    exit 1

fi

FOREMAN_VERSION="$(
    "${JQ}" -r '.version // empty' "${API_BODY_FILE}"
)"

API_VERSION="$(
    "${JQ}" -r '.api_version // empty' "${API_BODY_FILE}"
)"

ok "Foreman API authentication successful."
echo "Foreman Version : ${FOREMAN_VERSION}"
echo "API Version     : ${API_VERSION}"
echo "API Status      : ${API_STATUS}"

###############################################################################
# Architecture
###############################################################################

api_request \
    GET \
    "${FOREMAN_API}/architectures?per_page=all"

if ! api_success || ! json_valid; then

    error "Unable to query architectures."
    show_api_error
    exit 1

fi

ARCH_ID="$(
    "${JQ}" -r '
        .results[]
        | select(.name == "x86_64")
        | .id
    ' "${API_BODY_FILE}" |
    "${HEAD}" -1
)"

if [ -z "${ARCH_ID}" ] ||
   [ "${ARCH_ID}" = "null" ]; then

    error "x86_64 architecture not found."
    exit 1

fi

ok "x86_64 architecture found. ID=${ARCH_ID}"

###############################################################################
# Partition table
###############################################################################

api_request \
    GET \
    "${FOREMAN_API}/ptables?per_page=all"

if ! api_success || ! json_valid; then

    error "Unable to query partition tables."
    show_api_error
    exit 1

fi

PTABLE_ID="$(
    "${JQ}" -r '
        .results[]
        | select(.name == "Kickstart default")
        | .id
    ' "${API_BODY_FILE}" |
    "${HEAD}" -1
)"

if [ -z "${PTABLE_ID}" ] ||
   [ "${PTABLE_ID}" = "null" ]; then

    error "Kickstart default partition table not found."
    exit 1

fi

ok "Kickstart default partition table found. ID=${PTABLE_ID}"

###############################################################################
# Installation Media definitions
###############################################################################

MEDIA_NAMES=(
    "CentOS 7 Remote"
    "Rocky 8 Remote"
    "Rocky 9.2 Remote"
    "Rocky 9 Remote"
)

MEDIA_PATHS=(
    "http://192.168.253.136/repo/centos/"
    "http://192.168.253.136/repo/rocky8/"
    "http://192.168.253.136/repo/rocky9.2/"
    "http://192.168.253.136/repo/rocky9/"
)

###############################################################################
# Get media by exact name
###############################################################################

get_media_id_by_name()
{
    NAME="$1"

    api_request \
        GET \
        "${FOREMAN_API}/media?per_page=all"

    if ! api_success || ! json_valid; then
        return 1
    fi

    "${JQ}" -r \
        --arg NAME "${NAME}" \
        '
        .results[]
        | select(.name == $NAME)
        | .id
        ' "${API_BODY_FILE}" |
        "${HEAD}" -1
}

###############################################################################
# Get media by exact path
###############################################################################

get_media_id_by_path()
{
    PATH_VALUE="$1"

    api_request \
        GET \
        "${FOREMAN_API}/media?per_page=all"

    if ! api_success || ! json_valid; then
        return 1
    fi

    "${JQ}" -r \
        --arg PATH_VALUE "${PATH_VALUE}" \
        '
        .results[]
        | select(.path == $PATH_VALUE)
        | .id
        ' "${API_BODY_FILE}" |
        "${HEAD}" -1
}

###############################################################################
# Installation media
###############################################################################

create_or_update_media()
{
    MEDIA_NAME="$1"
    MEDIA_PATH="$2"

    section "Installation Media : ${MEDIA_NAME}"

    ###########################################################################
    # First lookup by name
    ###########################################################################

    MEDIA_ID="$(get_media_id_by_name "${MEDIA_NAME}")"

    ###########################################################################
    # If not found by name, lookup by path
    ###########################################################################

    if [ -z "${MEDIA_ID}" ] ||
       [ "${MEDIA_ID}" = "null" ]; then

        MEDIA_ID="$(get_media_id_by_path "${MEDIA_PATH}")"

        if [ -n "${MEDIA_ID}" ] &&
           [ "${MEDIA_ID}" != "null" ]; then

            skip "Installation media already exists by path. ID=${MEDIA_ID}"

            api_request \
                GET \
                "${FOREMAN_API}/media/${MEDIA_ID}"

            if api_success && json_valid; then

                EXISTING_NAME="$(
                    "${JQ}" -r '.name // empty' "${API_BODY_FILE}"
                )"

                EXISTING_PATH="$(
                    "${JQ}" -r '.path // empty' "${API_BODY_FILE}"
                )"

                echo "Existing Name : ${EXISTING_NAME}"
                echo "Existing Path : ${EXISTING_PATH}"

            fi

            return 0

        fi

    fi

    ###########################################################################
    # Already exists by name
    ###########################################################################

    if [ -n "${MEDIA_ID}" ] &&
       [ "${MEDIA_ID}" != "null" ]; then

        skip "${MEDIA_NAME} already exists. ID=${MEDIA_ID}"

        api_request \
            GET \
            "${FOREMAN_API}/media/${MEDIA_ID}"

        if api_success && json_valid; then

            EXISTING_PATH="$(
                "${JQ}" -r '.path // empty' "${API_BODY_FILE}"
            )"

            echo "Existing Path : ${EXISTING_PATH}"

            if [ "${EXISTING_PATH}" = "${MEDIA_PATH}" ]; then

                ok "${MEDIA_NAME} path verified."

            else

                warn "${MEDIA_NAME} path differs."
                echo "Existing : ${EXISTING_PATH}"
                echo "Expected : ${MEDIA_PATH}"

                MEDIA_JSON="$(
                    "${JQ}" -n \
                        --arg PATH_VALUE "${MEDIA_PATH}" \
                        '{
                            medium: {
                                path: $PATH_VALUE
                            }
                        }'
                )"

                api_request \
                    PUT \
                    "${FOREMAN_API}/media/${MEDIA_ID}" \
                    "${MEDIA_JSON}"

                if api_success; then

                    updated "${MEDIA_NAME} path updated."

                else

                    error "${MEDIA_NAME} path update failed."
                    show_api_error
                    record_failure "${MEDIA_NAME} media update"

                fi

            fi

        fi

        return 0
    fi

    ###########################################################################
    # Create
    ###########################################################################

    info "Creating ${MEDIA_NAME}"

    MEDIA_JSON="$(
        "${JQ}" -n \
            --arg NAME "${MEDIA_NAME}" \
            --arg PATH_VALUE "${MEDIA_PATH}" \
            '{
                medium: {
                    name: $NAME,
                    path: $PATH_VALUE,
                    os_family: "Redhat"
                }
            }'
    )"

    api_request \
        POST \
        "${FOREMAN_API}/media" \
        "${MEDIA_JSON}"

    if api_success && json_valid; then

        MEDIA_ID="$(
            "${JQ}" -r '.id // empty' "${API_BODY_FILE}"
        )"

        created "${MEDIA_NAME} created. ID=${MEDIA_ID}"

    else

        #######################################################################
        # Race-safe retry:
        # Another process may have created it between GET and POST.
        #######################################################################

        if "${JQ}" -e '
            .error.errors.name? and
            .error.errors.path?
        ' "${API_BODY_FILE}" >/dev/null 2>&1; then

            MEDIA_ID="$(get_media_id_by_name "${MEDIA_NAME}")"

            if [ -n "${MEDIA_ID}" ] &&
               [ "${MEDIA_ID}" != "null" ]; then

                skip "${MEDIA_NAME} already exists. ID=${MEDIA_ID}"
                return 0

            fi

        fi

        error "${MEDIA_NAME} creation failed."
        show_api_error
        record_failure "${MEDIA_NAME} media creation"

    fi
}

###############################################################################
# Create all media
###############################################################################

header "Creating Installation Media"

for INDEX in "${!MEDIA_NAMES[@]}"; do

    create_or_update_media \
        "${MEDIA_NAMES[$INDEX]}" \
        "${MEDIA_PATHS[$INDEX]}"

done

###############################################################################
# Media verification
###############################################################################

header "Installation Media Verification"

api_request \
    GET \
    "${FOREMAN_API}/media?per_page=all"

if api_success && json_valid; then

    "${JQ}" -r '
        .results[]
        | [
            .id,
            .name,
            .path
          ]
        | @tsv
    ' "${API_BODY_FILE}"

else

    error "Unable to verify installation media."
    show_api_error

fi

###############################################################################
# Operating system definitions
###############################################################################

OS_NAMES=(
    "CentOSLinux7-RAID"
    "CentOSLinux7-SingleDisk"
    "RockyLinux8.10-RAID"
    "RockyLinux8.10-SingleDisk"
    "RockyLinux9.2-RAID"
    "RockyLinux9.2-SingleDisk"
    "RockyLinux9.8-RAID"
    "RockyLinux9.8-SingleDisk"
)

OS_MAJORS=(
    "7"
    "7"
    "8"
    "8"
    "9"
    "9"
    "9"
    "9"
)

OS_MINORS=(
    ""
    ""
    "10"
    "10"
    "2"
    "2"
    "8"
    "8"
)

OS_MEDIA=(
    "CentOS 7 Remote"
    "CentOS 7 Remote"
    "Rocky 8 Remote"
    "Rocky 8 Remote"
    "Rocky 9.2 Remote"
    "Rocky 9.2 Remote"
    "Rocky 9 Remote"
    "Rocky 9 Remote"
)

###############################################################################
# Get OS ID
###############################################################################

get_os_id()
{
    NAME="$1"

    api_request \
        GET \
        "${FOREMAN_API}/operatingsystems?per_page=all"

    if ! api_success || ! json_valid; then
        return 1
    fi

    "${JQ}" -r \
        --arg NAME "${NAME}" \
        '
        .results[]
        | select(.name == $NAME)
        | .id
        ' "${API_BODY_FILE}" |
        "${HEAD}" -1
}

###############################################################################
# Get media ID
###############################################################################

get_media_id()
{
    NAME="$1"

    get_media_id_by_name "${NAME}"
}

###############################################################################
# Create OS
###############################################################################

create_or_update_os()
{
    OS_NAME="$1"
    OS_MAJOR="$2"
    OS_MINOR="$3"
    MEDIA_NAME="$4"

    section "Operating System : ${OS_NAME}"

    ###########################################################################
    # Existing OS
    ###########################################################################

    OS_ID="$(get_os_id "${OS_NAME}")"

    if [ -n "${OS_ID}" ] &&
       [ "${OS_ID}" != "null" ]; then

        skip "${OS_NAME} already exists. ID=${OS_ID}"

        return 0
    fi

    ###########################################################################
    # Media
    ###########################################################################

    MEDIA_ID="$(get_media_id "${MEDIA_NAME}")"

    if [ -z "${MEDIA_ID}" ] ||
       [ "${MEDIA_ID}" = "null" ]; then

        error "Installation media not found : ${MEDIA_NAME}"
        record_failure "${OS_NAME} media"
        return 1

    fi

    ###########################################################################
    # Create
    ###########################################################################

    info "Creating ${OS_NAME}"

    if [ -n "${OS_MINOR}" ]; then

        OS_JSON="$(
            "${JQ}" -n \
                --arg NAME "${OS_NAME}" \
                --arg MAJOR "${OS_MAJOR}" \
                --arg MINOR "${OS_MINOR}" \
                --argjson ARCH "${ARCH_ID}" \
                --argjson MEDIA "${MEDIA_ID}" \
                --argjson PTABLE "${PTABLE_ID}" \
                '{
                    operatingsystem: {
                        name: $NAME,
                        major: $MAJOR,
                        minor: $MINOR,
                        family: "Redhat",
                        architecture_ids: [$ARCH],
                        medium_ids: [$MEDIA],
                        ptable_ids: [$PTABLE]
                    }
                }'
        )"

    else

        OS_JSON="$(
            "${JQ}" -n \
                --arg NAME "${OS_NAME}" \
                --arg MAJOR "${OS_MAJOR}" \
                --argjson ARCH "${ARCH_ID}" \
                --argjson MEDIA "${MEDIA_ID}" \
                --argjson PTABLE "${PTABLE_ID}" \
                '{
                    operatingsystem: {
                        name: $NAME,
                        major: $MAJOR,
                        family: "Redhat",
                        architecture_ids: [$ARCH],
                        medium_ids: [$MEDIA],
                        ptable_ids: [$PTABLE]
                    }
                }'
        )"

    fi

    api_request \
        POST \
        "${FOREMAN_API}/operatingsystems" \
        "${OS_JSON}"

    if api_success && json_valid; then

        OS_ID="$(
            "${JQ}" -r '.id // empty' "${API_BODY_FILE}"
        )"

        created "${OS_NAME} created. ID=${OS_ID}"

    else

        #######################################################################
        # Race-safe retry
        #######################################################################

        EXISTING_ID="$(get_os_id "${OS_NAME}")"

        if [ -n "${EXISTING_ID}" ] &&
           [ "${EXISTING_ID}" != "null" ]; then

            skip "${OS_NAME} already exists. ID=${EXISTING_ID}"
            return 0

        fi

        error "${OS_NAME} creation failed."
        show_api_error
        record_failure "${OS_NAME} creation"

    fi
}

###############################################################################
# Create all OSes
###############################################################################

header "Creating Operating Systems"

for INDEX in "${!OS_NAMES[@]}"; do

    create_or_update_os \
        "${OS_NAMES[$INDEX]}" \
        "${OS_MAJORS[$INDEX]}" \
        "${OS_MINORS[$INDEX]}" \
        "${OS_MEDIA[$INDEX]}"

done

###############################################################################
# OS verification
###############################################################################

header "Operating System Verification"

api_request \
    GET \
    "${FOREMAN_API}/operatingsystems?per_page=all"

if api_success && json_valid; then

    "${JQ}" -r '
        .results[]
        | [
            .id,
            .name,
            (.major // ""),
            (.minor // ""),
            (.family // "")
          ]
        | @tsv
    ' "${API_BODY_FILE}"

else

    error "Unable to verify operating systems."
    show_api_error

fi

###############################################################################
# PXEGrub2 template files
###############################################################################

header "Generating PXEGrub2 Template Files"

"${MKDIR}" -p "${WORK_DIR}"

###############################################################################
# Common PXEGrub2 template
#
# Foreman provides @kernel and @initrd when rendering PXE templates.
# foreman_url('provision') supplies the host-specific Kickstart URL.
###############################################################################

create_pxe_template()
{
    FILE="$1"
    TITLE="$2"

    "${CAT}" > "${FILE}" <<EOF
set default=0
set timeout=10

menuentry '${TITLE}' {
    linuxefi <%= @kernel %> <%= pxe_kernel_options %> inst.ks=<%= foreman_url('provision') %>
    initrdefi <%= @initrd %>
}
EOF
}

create_pxe_template \
    "${WORK_DIR}/centos-raid.erb" \
    "CentOS 7 RAID Kickstart"

create_pxe_template \
    "${WORK_DIR}/centos-singledisk.erb" \
    "CentOS 7 SingleDisk Kickstart"

create_pxe_template \
    "${WORK_DIR}/rocky8-raid.erb" \
    "Rocky 8 RAID Kickstart"

create_pxe_template \
    "${WORK_DIR}/rocky8-singledisk.erb" \
    "Rocky 8 SingleDisk Kickstart"

create_pxe_template \
    "${WORK_DIR}/rocky92-raid.erb" \
    "Rocky 9.2 RAID Kickstart"

create_pxe_template \
    "${WORK_DIR}/rocky92-singledisk.erb" \
    "Rocky 9.2 SingleDisk Kickstart"

create_pxe_template \
    "${WORK_DIR}/rocky98-raid.erb" \
    "Rocky 9.8 RAID Kickstart"

create_pxe_template \
    "${WORK_DIR}/rocky98-singledisk.erb" \
    "Rocky 9.8 SingleDisk Kickstart"

ok "All 8 PXEGrub2 template files generated."

###############################################################################
# Template definitions
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
# OS -> template mapping
###############################################################################

MAP_OS=(
    "CentOSLinux7-RAID"
    "CentOSLinux7-SingleDisk"
    "RockyLinux8.10-RAID"
    "RockyLinux8.10-SingleDisk"
    "RockyLinux9.2-RAID"
    "RockyLinux9.2-SingleDisk"
    "RockyLinux9.8-RAID"
    "RockyLinux9.8-SingleDisk"
)

MAP_TEMPLATE=(
    "PXEGrub2 CentOS UEFI RAID Kickstart"
    "PXEGrub2 CentOS UEFI SingleDisk Kickstart"
    "PXEGrub2 Rocky8 UEFI RAID Kickstart"
    "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"
    "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"
    "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"
    "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"
    "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"
)

###############################################################################
# Find PXEGrub2 template kind
#
# IMPORTANT:
# Your Foreman 3.2 installation returned:
#
# /api/template_kinds
# results: []
#
# Therefore we don't depend on that endpoint.
#
# Existing provisioning templates already contain:
#
# template_kind_id
# template_kind_name
#
# We obtain PXEGrub2 kind from an existing PXEGrub2 provisioning template.
###############################################################################

header "Finding PXEGrub2 Template Kind"

info "Detecting PXEGrub2 template kind from provisioning templates..."

api_request \
    GET \
    "${FOREMAN_API}/provisioning_templates?per_page=all"

if ! api_success || ! json_valid; then

    error "Unable to query provisioning templates."
    show_api_error
    exit 1

fi

PXEGRUB2_KIND_ID="$(
    "${JQ}" -r '
        .results[]
        | select(.template_kind_name == "PXEGrub2")
        | .template_kind_id
    ' "${API_BODY_FILE}" |
    "${HEAD}" -1
)"

###############################################################################
# Fallback using PXEGrub2 global default
###############################################################################

if [ -z "${PXEGRUB2_KIND_ID}" ] ||
   [ "${PXEGRUB2_KIND_ID}" = "null" ]; then

    PXEGRUB2_KIND_ID="$(
        "${JQ}" -r '
            .results[]
            | select(.name == "PXEGrub2 global default")
            | .template_kind_id
        ' "${API_BODY_FILE}" |
        "${HEAD}" -1
    )"

fi

###############################################################################
# Fallback using template kind field
###############################################################################

if [ -z "${PXEGRUB2_KIND_ID}" ] ||
   [ "${PXEGRUB2_KIND_ID}" = "null" ]; then

    PXEGRUB2_KIND_ID="$(
        "${JQ}" -r '
            .results[]
            | select(.template_kind_name | ascii_downcase == "pxegrub2")
            | .template_kind_id
        ' "${API_BODY_FILE}" |
        "${HEAD}" -1
    )"

fi

if [ -z "${PXEGRUB2_KIND_ID}" ] ||
   [ "${PXEGRUB2_KIND_ID}" = "null" ]; then

    error "PXEGrub2 template kind not found."

    echo
    echo "Existing provisioning templates:"
    "${JQ}" -r '
        .results[]
        | [
            .id,
            .name,
            (.template_kind_id // ""),
            (.template_kind_name // "")
          ]
        | @tsv
    ' "${API_BODY_FILE}"

    record_failure "PXEGrub2 template kind"
    exit 1

fi

ok "PXEGrub2 template kind found. ID=${PXEGRUB2_KIND_ID}"

###############################################################################
# Get provisioning template ID by exact name
###############################################################################

get_template_id()
{
    TEMPLATE_NAME="$1"

    api_request \
        GET \
        "${FOREMAN_API}/provisioning_templates?per_page=all"

    if ! api_success || ! json_valid; then
        return 1
    fi

    "${JQ}" -r \
        --arg NAME "${TEMPLATE_NAME}" \
        '
        .results[]
        | select(.name == $NAME)
        | .id
        ' "${API_BODY_FILE}" |
        "${HEAD}" -1
}

###############################################################################
# Create PXEGrub2 template
###############################################################################

create_or_update_template()
{
    TEMPLATE_NAME="$1"
    TEMPLATE_FILE="$2"

    section "PXEGrub2 template : ${TEMPLATE_NAME}"

    ###########################################################################
    # Existing template
    ###########################################################################

    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -n "${TEMPLATE_ID}" ] &&
       [ "${TEMPLATE_ID}" != "null" ]; then

        skip "${TEMPLATE_NAME} already exists. ID=${TEMPLATE_ID}"

        return 0
    fi

    ###########################################################################
    # Kind required
    ###########################################################################

    if [ -z "${PXEGRUB2_KIND_ID}" ]; then

        error "PXEGrub2 kind ID unavailable."
        record_failure "${TEMPLATE_NAME} kind"
        return 1

    fi

    ###########################################################################
    # File
    ###########################################################################

    if [ ! -f "${TEMPLATE_FILE}" ]; then

        error "Template file missing : ${TEMPLATE_FILE}"
        record_failure "${TEMPLATE_NAME} file"
        return 1

    fi

    TEMPLATE_CONTENT="$(
        "${CAT}" "${TEMPLATE_FILE}"
    )"

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
        "${FOREMAN_API}/provisioning_templates" \
        "${TEMPLATE_JSON}"

    if api_success && json_valid; then

        TEMPLATE_ID="$(
            "${JQ}" -r '.id // empty' "${API_BODY_FILE}"
        )"

        created "${TEMPLATE_NAME} created. ID=${TEMPLATE_ID}"

    else

        #######################################################################
        # If another run created it, detect it.
        #######################################################################

        EXISTING_TEMPLATE_ID="$(
            get_template_id "${TEMPLATE_NAME}"
        )"

        if [ -n "${EXISTING_TEMPLATE_ID}" ] &&
           [ "${EXISTING_TEMPLATE_ID}" != "null" ]; then

            skip "${TEMPLATE_NAME} already exists. ID=${EXISTING_TEMPLATE_ID}"
            return 0

        fi

        error "${TEMPLATE_NAME} creation failed."
        show_api_error
        record_failure "${TEMPLATE_NAME} creation"

    fi
}

###############################################################################
# Create all PXEGrub2 templates
###############################################################################

header "Creating PXEGrub2 Templates"

for INDEX in "${!TEMPLATE_NAMES[@]}"; do

    create_or_update_template \
        "${TEMPLATE_NAMES[$INDEX]}" \
        "${TEMPLATE_FILES[$INDEX]}"

done

###############################################################################
# Associate template with OS
#
# We update the OS provisioning_template_ids array.
#
# This preserves all existing associations.
###############################################################################

associate_template_with_os()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    section "Associating:"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"

    ###########################################################################
    # OS
    ###########################################################################

    OS_ID="$(get_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ] ||
       [ "${OS_ID}" = "null" ]; then

        error "Operating System not found : ${OS_NAME}"
        record_failure "${OS_NAME} association"
        return 1

    fi

    ###########################################################################
    # Template
    ###########################################################################

    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ] ||
       [ "${TEMPLATE_ID}" = "null" ]; then

        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${OS_NAME} association"
        return 1

    fi

    ###########################################################################
    # Get current OS details
    ###########################################################################

    api_request \
        GET \
        "${FOREMAN_API}/operatingsystems/${OS_ID}"

    if ! api_success || ! json_valid; then

        error "Unable to read OS : ${OS_NAME}"
        show_api_error
        record_failure "${OS_NAME} association lookup"
        return 1

    fi

    ###########################################################################
    # Check current association
    ###########################################################################

    ASSOCIATED="$(
        "${JQ}" -r \
            --argjson TEMPLATE_ID "${TEMPLATE_ID}" \
            '
            [
                (.provisioning_templates // [])[]
                | .id
            ]
            | map(select(. == $TEMPLATE_ID))
            | length
            ' "${API_BODY_FILE}"
    )"

    if [ "${ASSOCIATED}" = "1" ]; then

        skip "${TEMPLATE_NAME} already associated."

        return 0

    fi

    ###########################################################################
    # Preserve all current provisioning templates
    ###########################################################################

    CURRENT_TEMPLATE_IDS="$(
        "${JQ}" -c '
            [
                (.provisioning_templates // [])[]
                | .id
            ]
            | unique
        ' "${API_BODY_FILE}"
    )"

    if [ -z "${CURRENT_TEMPLATE_IDS}" ] ||
       [ "${CURRENT_TEMPLATE_IDS}" = "null" ]; then

        CURRENT_TEMPLATE_IDS="[]"

    fi

    NEW_TEMPLATE_IDS="$(
        "${JQ}" -c \
            --argjson TEMPLATE_ID "${TEMPLATE_ID}" \
            '
            . + [$TEMPLATE_ID] | unique
            ' <<< "${CURRENT_TEMPLATE_IDS}"
    )"

    ###########################################################################
    # Update OS
    ###########################################################################

    OS_JSON="$(
        "${JQ}" -n \
            --argjson IDS "${NEW_TEMPLATE_IDS}" \
            '{
                operatingsystem: {
                    provisioning_template_ids: $IDS
                }
            }'
    )"

    api_request \
        PUT \
        "${FOREMAN_API}/operatingsystems/${OS_ID}" \
        "${OS_JSON}"

    if api_success; then

        updated "${TEMPLATE_NAME} associated with ${OS_NAME}."

    else

        error "Failed associating ${TEMPLATE_NAME} with ${OS_NAME}."
        show_api_error
        record_failure "${OS_NAME} association"

    fi
}

###############################################################################
# Associate all templates
###############################################################################

header "Associating PXEGrub2 Templates"

for INDEX in "${!MAP_OS[@]}"; do

    associate_template_with_os \
        "${MAP_OS[$INDEX]}" \
        "${MAP_TEMPLATE[$INDEX]}"

done

###############################################################################
# PXEGrub2 default template
#
# Existing default:
#   SKIP
#
# Existing PXEGrub2 default with different template:
#   UPDATE
#
# No duplicate POST.
###############################################################################

set_pxegrub2_default()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    section "Setting PXEGrub2 Default:"

    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"

    ###########################################################################
    # OS ID
    ###########################################################################

    OS_ID="$(get_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ] ||
       [ "${OS_ID}" = "null" ]; then

        error "Operating System not found : ${OS_NAME}"
        record_failure "${OS_NAME} default"
        return 1

    fi

    ###########################################################################
    # Template ID
    ###########################################################################

    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ] ||
       [ "${TEMPLATE_ID}" = "null" ]; then

        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${OS_NAME} default"
        return 1

    fi

    ###########################################################################
    # Existing defaults
    ###########################################################################

    api_request \
        GET \
        "${FOREMAN_API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"

    if ! api_success || ! json_valid; then

        error "Unable to query OS default templates."
        show_api_error
        record_failure "${OS_NAME} default lookup"
        return 1

    fi

    ###########################################################################
    # Existing PXEGrub2 row
    ###########################################################################

    DEFAULT_ROW="$(
        "${JQ}" -c \
            --argjson KIND "${PXEGRUB2_KIND_ID}" \
            '
            [
                .results[]
                | select(.template_kind_id == $KIND)
            ]
            | .[0] // empty
            ' "${API_BODY_FILE}"
    )"

    ###########################################################################
    # Existing PXEGrub2 default
    ###########################################################################

    if [ -n "${DEFAULT_ROW}" ]; then

        DEFAULT_ID="$(
            "${JQ}" -r '.id' <<< "${DEFAULT_ROW}"
        )"

        DEFAULT_TEMPLATE_ID="$(
            "${JQ}" -r '.provisioning_template_id' <<< "${DEFAULT_ROW}"
        )"

        DEFAULT_TEMPLATE_NAME="$(
            "${JQ}" -r '.provisioning_template_name' <<< "${DEFAULT_ROW}"
        )"

        #######################################################################
        # Already correct
        #######################################################################

        if [ "${DEFAULT_TEMPLATE_ID}" = "${TEMPLATE_ID}" ]; then

            skip "PXEGrub2 default already correct: ${DEFAULT_TEMPLATE_NAME}"

            return 0

        fi

        #######################################################################
        # Existing row but wrong template -> UPDATE
        #######################################################################

        info "Existing PXEGrub2 default found."
        echo "Existing Template : ${DEFAULT_TEMPLATE_NAME}"
        echo "Requested Template: ${TEMPLATE_NAME}"
        echo "Default Row ID    : ${DEFAULT_ID}"

        DEFAULT_JSON="$(
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
            "${FOREMAN_API}/operatingsystems/${OS_ID}/os_default_templates/${DEFAULT_ID}" \
            "${DEFAULT_JSON}"

        if api_success; then

            updated "PXEGrub2 default changed to ${TEMPLATE_NAME}."

        else

            error "Failed updating PXEGrub2 default."
            show_api_error
            record_failure "${OS_NAME} default update"

        fi

        return 0
    fi

    ###########################################################################
    # No PXEGrub2 default -> create
    ###########################################################################

    info "No PXEGrub2 default found. Creating one..."

    DEFAULT_JSON="$(
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
        "${FOREMAN_API}/operatingsystems/${OS_ID}/os_default_templates" \
        "${DEFAULT_JSON}"

    if api_success; then

        created "PXEGrub2 default created for ${OS_NAME}."

    else

        #######################################################################
        # Race-safe retry / duplicate handling
        #######################################################################

        api_request \
            GET \
            "${FOREMAN_API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"

        if api_success && json_valid; then

            EXISTING_DEFAULT_ID="$(
                "${JQ}" -r \
                    --argjson KIND "${PXEGRUB2_KIND_ID}" \
                    --argjson TEMPLATE "${TEMPLATE_ID}" \
                    '
                    .results[]
                    | select(
                        .template_kind_id == $KIND and
                        .provisioning_template_id == $TEMPLATE
                    )
                    | .id
                    ' "${API_BODY_FILE}" |
                    "${HEAD}" -1
            )"

            if [ -n "${EXISTING_DEFAULT_ID}" ] &&
               [ "${EXISTING_DEFAULT_ID}" != "null" ]; then

                skip "PXEGrub2 default already exists. ID=${EXISTING_DEFAULT_ID}"
                return 0

            fi

        fi

        error "Failed creating PXEGrub2 default."
        show_api_error
        record_failure "${OS_NAME} default creation"

    fi
}

###############################################################################
# Set all defaults
###############################################################################

header "Setting PXEGrub2 Default Templates"

for INDEX in "${!MAP_OS[@]}"; do

    set_pxegrub2_default \
        "${MAP_OS[$INDEX]}" \
        "${MAP_TEMPLATE[$INDEX]}"

done

###############################################################################
# Domain lookup
###############################################################################

get_domain_id()
{
    DOMAIN_NAME="$1"

    api_request \
        GET \
        "${FOREMAN_API}/domains?per_page=all"

    if ! api_success || ! json_valid; then
        return 1
    fi

    "${JQ}" -r \
        --arg NAME "${DOMAIN_NAME}" \
        '
        .results[]
        | select(.name == $NAME)
        | .id
        ' "${API_BODY_FILE}" |
        "${HEAD}" -1
}

###############################################################################
# Smart proxy lookup
###############################################################################

get_proxy_id()
{
    PROXY_NAME="$1"

    api_request \
        GET \
        "${FOREMAN_API}/smart_proxies?per_page=all"

    if ! api_success || ! json_valid; then
        return 1
    fi

    "${JQ}" -r \
        --arg NAME "${PROXY_NAME}" \
        '
        .results[]
        | select(.name == $NAME)
        | .id
        ' "${API_BODY_FILE}" |
        "${HEAD}" -1
}

###############################################################################
# Subnet lookup
###############################################################################

get_subnet_id()
{
    SUBNET_NAME="$1"

    api_request \
        GET \
        "${FOREMAN_API}/subnets?per_page=all"

    if ! api_success || ! json_valid; then
        return 1
    fi

    "${JQ}" -r \
        --arg NAME "${SUBNET_NAME}" \
        '
        .results[]
        | select(.name == $NAME)
        | .id
        ' "${API_BODY_FILE}" |
        "${HEAD}" -1
}

###############################################################################
# Create/update subnet
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

    ###########################################################################
    # Domain
    ###########################################################################

    DOMAIN_ID="$(get_domain_id "vgs.com")"

    if [ -z "${DOMAIN_ID}" ] ||
       [ "${DOMAIN_ID}" = "null" ]; then

        error "Domain not found : vgs.com"
        record_failure "${SUBNET_NAME} domain"
        return 1

    fi

    ok "Domain found : vgs.com ID=${DOMAIN_ID}"

    ###########################################################################
    # TFTP proxy
    ###########################################################################

    TFTP_ID="$(get_proxy_id "${TFTP_PROXY_NAME}")"

    if [ -z "${TFTP_ID}" ] ||
       [ "${TFTP_ID}" = "null" ]; then

        error "TFTP proxy not found : ${TFTP_PROXY_NAME}"
        record_failure "${SUBNET_NAME} TFTP"
        return 1

    fi

    ok "TFTP proxy found : ${TFTP_PROXY_NAME} ID=${TFTP_ID}"

    ###########################################################################
    # DHCP proxy
    ###########################################################################

    DHCP_ID="$(get_proxy_id "${DHCP_PROXY_NAME}")"

    if [ -z "${DHCP_ID}" ] ||
       [ "${DHCP_ID}" = "null" ]; then

        error "DHCP proxy not found : ${DHCP_PROXY_NAME}"
        record_failure "${SUBNET_NAME} DHCP"
        return 1

    fi

    ok "DHCP proxy found : ${DHCP_PROXY_NAME} ID=${DHCP_ID}"

    ###########################################################################
    # Existing subnet
    ###########################################################################

    SUBNET_ID="$(get_subnet_id "${SUBNET_NAME}")"

    ###########################################################################
    # JSON
    ###########################################################################

    SUBNET_JSON="$(
        "${JQ}" -n \
            --arg NAME "${SUBNET_NAME}" \
            --arg NETWORK "${NETWORK}" \
            --arg MASK "${MASK}" \
            --arg GATEWAY "${GATEWAY}" \
            --arg DNS "${DNS}" \
            --argjson DOMAIN "${DOMAIN_ID}" \
            --argjson TFTP "${TFTP_ID}" \
            --argjson DHCP "${DHCP_ID}" \
            '{
                subnet: {
                    name: $NAME,
                    network_type: "IPv4",
                    network: $NETWORK,
                    mask: $MASK,
                    gateway: $GATEWAY,
                    dns_primary: $DNS,
                    domain_ids: [$DOMAIN],
                    tftp_id: $TFTP,
                    dhcp_id: $DHCP,
                    boot_mode: "DHCP"
                }
            }'
    )"

    ###########################################################################
    # Update existing
    ###########################################################################

    if [ -n "${SUBNET_ID}" ] &&
       [ "${SUBNET_ID}" != "null" ]; then

        skip "${SUBNET_NAME} already exists. ID=${SUBNET_ID}"

        api_request \
            PUT \
            "${FOREMAN_API}/subnets/${SUBNET_ID}" \
            "${SUBNET_JSON}"

        if api_success; then

            ok "${SUBNET_NAME} updated."

        else

            error "${SUBNET_NAME} update failed."
            show_api_error
            record_failure "${SUBNET_NAME} update"

        fi

        return 0
    fi

    ###########################################################################
    # Create
    ###########################################################################

    info "Creating ${SUBNET_NAME}"

    api_request \
        POST \
        "${FOREMAN_API}/subnets" \
        "${SUBNET_JSON}"

    if api_success && json_valid; then

        SUBNET_ID="$(
            "${JQ}" -r '.id // empty' "${API_BODY_FILE}"
        )"

        created "${SUBNET_NAME} created. ID=${SUBNET_ID}"

    else

        #######################################################################
        # Race-safe lookup
        #######################################################################

        EXISTING_SUBNET_ID="$(get_subnet_id "${SUBNET_NAME}")"

        if [ -n "${EXISTING_SUBNET_ID}" ] &&
           [ "${EXISTING_SUBNET_ID}" != "null" ]; then

            skip "${SUBNET_NAME} already exists. ID=${EXISTING_SUBNET_ID}"
            return 0

        fi

        error "${SUBNET_NAME} creation failed."
        show_api_error
        record_failure "${SUBNET_NAME} creation"

    fi
}

###############################################################################
# Create/update PXE subnets
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
# Subnet verification
###############################################################################

header "PXE Subnet Verification"

api_request \
    GET \
    "${FOREMAN_API}/subnets?per_page=all"

if api_success && json_valid; then

    "${JQ}" -r '
        .results[]
        | [
            .id,
            .name,
            (
                if .cidr != null
                then (.network + "/" + (.cidr|tostring))
                else (.network + "/" + (.mask // ""))
                end
            ),
            (.dhcp_name // ""),
            (.tftp_name // "")
          ]
        | @tsv
    ' "${API_BODY_FILE}"

else

    error "Unable to verify subnets."
    show_api_error

fi

###############################################################################
# PXE template verification
###############################################################################

header "PXEGrub2 Template Verification"

api_request \
    GET \
    "${FOREMAN_API}/provisioning_templates?per_page=all"

if api_success && json_valid; then

    for TEMPLATE_NAME in "${TEMPLATE_NAMES[@]}"; do

        TEMPLATE_ROW="$(
            "${JQ}" -c \
                --arg NAME "${TEMPLATE_NAME}" \
                '
                .results[]
                | select(.name == $NAME)
                ' "${API_BODY_FILE}" |
                "${HEAD}" -1
        )"

        if [ -n "${TEMPLATE_ROW}" ]; then

            TEMPLATE_ID="$(
                "${JQ}" -r '.id' <<< "${TEMPLATE_ROW}"
            )"

            KIND_NAME="$(
                "${JQ}" -r '.template_kind_name // ""' <<< "${TEMPLATE_ROW}"
            )"

            KIND_ID="$(
                "${JQ}" -r '.template_kind_id // ""' <<< "${TEMPLATE_ROW}"
            )"

            ok "${TEMPLATE_NAME} | ID=${TEMPLATE_ID} | kind=${KIND_NAME} | kind_id=${KIND_ID}"

        else

            error "${TEMPLATE_NAME} verification failed."

        fi

    done

else

    error "Unable to verify PXEGrub2 templates."
    show_api_error

fi

###############################################################################
# OS template mapping verification
###############################################################################

header "OS Template Mapping Verification"

for INDEX in "${!MAP_OS[@]}"; do

    OS_NAME="${MAP_OS[$INDEX]}"
    TEMPLATE_NAME="${MAP_TEMPLATE[$INDEX]}"

    OS_ID="$(get_os_id "${OS_NAME}")"
    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -z "${OS_ID}" ] ||
       [ -z "${TEMPLATE_ID}" ]; then

        error "${OS_NAME} -> ${TEMPLATE_NAME}"

        continue

    fi

    api_request \
        GET \
        "${FOREMAN_API}/operatingsystems/${OS_ID}"

    if ! api_success || ! json_valid; then

        error "Unable to verify ${OS_NAME}."
        continue

    fi

    ASSOCIATED="$(
        "${JQ}" -r \
            --argjson TEMPLATE_ID "${TEMPLATE_ID}" \
            '
            [
                (.provisioning_templates // [])[]
                | .id
            ]
            | map(select(. == $TEMPLATE_ID))
            | length
            ' "${API_BODY_FILE}"
    )"

    if [ "${ASSOCIATED}" = "1" ]; then

        ok "${OS_NAME} -> ${TEMPLATE_NAME}"

    else

        error "${OS_NAME} -> ${TEMPLATE_NAME} association missing."

    fi

done

###############################################################################
# PXEGrub2 default verification
###############################################################################

header "PXEGrub2 Default Template Verification"

for INDEX in "${!MAP_OS[@]}"; do

    OS_NAME="${MAP_OS[$INDEX]}"
    TEMPLATE_NAME="${MAP_TEMPLATE[$INDEX]}"

    OS_ID="$(get_os_id "${OS_NAME}")"
    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -z "${OS_ID}" ] ||
       [ -z "${TEMPLATE_ID}" ]; then

        error "${OS_NAME} default verification skipped."
        continue

    fi

    api_request \
        GET \
        "${FOREMAN_API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"

    if ! api_success || ! json_valid; then

        error "${OS_NAME} default verification failed."
        continue

    fi

    DEFAULT_MATCH="$(
        "${JQ}" -r \
            --argjson KIND "${PXEGRUB2_KIND_ID}" \
            --argjson TEMPLATE "${TEMPLATE_ID}" \
            '
            [
                .results[]
                | select(
                    .template_kind_id == $KIND and
                    .provisioning_template_id == $TEMPLATE
                )
            ]
            | length
            ' "${API_BODY_FILE}"
    )"

    if [ "${DEFAULT_MATCH}" = "1" ]; then

        ok "${OS_NAME} PXEGrub2 default -> ${TEMPLATE_NAME}"

    else

        error "${OS_NAME} PXEGrub2 default incorrect/missing."

    fi

done

###############################################################################
# Generated files
###############################################################################

header "Generated PXE Template Files"

"${LS:-/bin/ls}" -lh "${WORK_DIR}"/*.erb 2>/dev/null || true

###############################################################################
# Final summary
###############################################################################

header "01 - Foreman PXE Bootstrap API Completed"

echo
echo "${C_GREEN}Created : ${CREATED_COUNT}${C_RESET}"
echo "${C_MAGENTA}Updated : ${UPDATED_COUNT}${C_RESET}"
echo "${C_YELLOW}Skipped : ${SKIPPED_COUNT}${C_RESET}"
echo "${C_RED}Errors  : ${ERROR_COUNT}${C_RESET}"

echo

if [ "${#FAILURES[@]}" -gt 0 ]; then

    echo "${C_RED}${C_BOLD}Failures:${C_RESET}"

    for FAILURE in "${FAILURES[@]}"; do
        echo "${C_RED}[ERROR]${C_RESET} ${FAILURE}"
    done

    echo

fi

if [ "${ERROR_COUNT}" -eq 0 ]; then

    echo "${C_GREEN}${C_BOLD}============================================================${C_RESET}"
    echo "${C_GREEN}${C_BOLD}BOOTSTRAP COMPLETED SUCCESSFULLY${C_RESET}"
    echo "${C_GREEN}${C_BOLD}============================================================${C_RESET}"

    exit 0

else

    echo "${C_YELLOW}${C_BOLD}============================================================${C_RESET}"
    echo "${C_YELLOW}${C_BOLD}BOOTSTRAP COMPLETED WITH ERRORS${C_RESET}"
    echo "${C_YELLOW}${C_BOLD}============================================================${C_RESET}"

    exit 1

fi
