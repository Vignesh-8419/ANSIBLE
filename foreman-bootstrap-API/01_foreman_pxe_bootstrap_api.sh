cat > 01_foreman_pxe_bootstrap_api.sh <<'EOF'
#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap - REST API
#
# Foreman 3.2.1
#
# Idempotent:
#   - Existing media        -> SKIP
#   - Existing OS           -> SKIP
#   - Existing templates    -> SKIP
#   - Existing associations -> SKIP
#   - Existing subnet       -> UPDATE/OK
#   - Existing defaults     -> SKIP/UPDATE
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
FOREMAN_TOKEN="${FOREMAN_TOKEN:-}"

WORK_DIR="/tmp/foreman-pxe-bootstrap"

###############################################################################
# Commands
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
LS="$(command -v ls 2>/dev/null || true)"

###############################################################################
# Colors
###############################################################################

if [ -t 1 ]; then
    RED=$'\033[31m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    BLUE=$'\033[34m'
    MAGENTA=$'\033[35m'
    CYAN=$'\033[36m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
    BOLD=""
    RESET=""
fi

###############################################################################
# Counters
###############################################################################

CREATED_COUNT=0
UPDATED_COUNT=0
SKIPPED_COUNT=0
ERROR_COUNT=0

FAILURES=()

###############################################################################
# API temporary files
###############################################################################

API_BODY_FILE=""
API_HEADERS_FILE=""
API_STATUS=""

###############################################################################
# Logging
###############################################################################

header()
{
    echo
    echo "${CYAN}${BOLD}============================================================${RESET}"
    echo "${CYAN}${BOLD}$1${RESET}"
    echo "${CYAN}${BOLD}============================================================${RESET}"
}

section()
{
    echo
    echo "${BLUE}${BOLD}------------------------------------------------------------${RESET}"
    echo "${BLUE}${BOLD}$1${RESET}"
    echo "${BLUE}${BOLD}------------------------------------------------------------${RESET}"
}

info()
{
    echo "${CYAN}[INFO]${RESET} $1"
}

ok()
{
    echo "${GREEN}[OK]${RESET} $1"
}

skip()
{
    echo "${YELLOW}[SKIP]${RESET} $1"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
}

warn()
{
    echo "${YELLOW}[WARN]${RESET} $1"
}

created()
{
    echo "${GREEN}[CREATED]${RESET} $1"
    CREATED_COUNT=$((CREATED_COUNT + 1))
}

updated()
{
    echo "${MAGENTA}[UPDATED]${RESET} $1"
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
}

error()
{
    echo "${RED}[ERROR]${RESET} $1"
    ERROR_COUNT=$((ERROR_COUNT + 1))
}

record_failure()
{
    FAILURES+=("$1")
}

###############################################################################
# Cleanup
###############################################################################

cleanup()
{
    [ -n "${API_BODY_FILE}" ] &&
        [ -f "${API_BODY_FILE}" ] &&
        "${RM}" -f "${API_BODY_FILE}"

    [ -n "${API_HEADERS_FILE}" ] &&
        [ -f "${API_HEADERS_FILE}" ] &&
        "${RM}" -f "${API_HEADERS_FILE}"
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
# IMPORTANT:
# The response body is always preserved in API_BODY_FILE.
###############################################################################

api_request()
{
    METHOD="$1"
    URL="$2"
    DATA="${3:-}"

    API_BODY_FILE="$("${MKTEMP}")"
    API_HEADERS_FILE="$("${MKTEMP}")"

    if [ -n "${DATA}" ]; then

        CURL_OUTPUT="$(
            "${CURL}" \
                --silent \
                --show-error \
                --insecure \
                --request "${METHOD}" \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                --header "Accept: application/json,version=2" \
                --header "Content-Type: application/json" \
                --data "${DATA}" \
                --output "${API_BODY_FILE}" \
                --dump-header "${API_HEADERS_FILE}" \
                --write-out "%{http_code}" \
                "${URL}" \
                2>"${API_HEADERS_FILE}.curlerr"
        )"

    else

        CURL_OUTPUT="$(
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
                2>"${API_HEADERS_FILE}.curlerr"
        )"

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

    API_STATUS="${CURL_OUTPUT}"

    return 0
}

###############################################################################
# Show API error
###############################################################################

show_api_error()
{
    echo

    if [ ! -s "${API_BODY_FILE}" ]; then
        echo "(empty API response)"
        return
    fi

    if json_valid; then
        "${JQ}" . "${API_BODY_FILE}"
    else
        "${CAT}" "${API_BODY_FILE}"
    fi
}

###############################################################################
# API success
###############################################################################

api_success()
{
    [[ "${API_STATUS}" =~ ^2[0-9][0-9]$ ]]
}

###############################################################################
# Dependencies
###############################################################################

header "Dependency Check"

for CMD_PAIR in \
    "curl:${CURL}" \
    "jq:${JQ}" \
    "cat:${CAT}" \
    "head:${HEAD}" \
    "grep:${GREP}" \
    "awk:${AWK}" \
    "sed:${SED}" \
    "mkdir:${MKDIR}" \
    "mktemp:${MKTEMP}"
do

    CMD_NAME="${CMD_PAIR%%:*}"
    CMD_PATH="${CMD_PAIR#*:}"

    if [ -z "${CMD_PATH}" ]; then
        error "${CMD_NAME} not found."
        exit 1
    fi

    ok "${CMD_NAME} found: ${CMD_PATH}"

done

###############################################################################
# PAT
###############################################################################

if [ -z "${FOREMAN_TOKEN}" ]; then

    error "FOREMAN_TOKEN is not set."

    echo
    echo "Run:"
    echo
    echo "  export FOREMAN_USER='admin'"
    echo "  export FOREMAN_TOKEN='YOUR_PAT'"
    echo

    exit 1
fi

###############################################################################
# Working directory
###############################################################################

"${MKDIR}" -p "${WORK_DIR}"

###############################################################################
# Header
###############################################################################

header "01 - Foreman PXE Bootstrap - REST API"

###############################################################################
# Authentication
###############################################################################

header "Foreman API Authentication Test"

info "Testing Foreman REST API..."

api_request GET "${FOREMAN_API}/status"

if ! api_success || ! json_valid; then

    error "Foreman API authentication failed."
    error "HTTP Status : ${API_STATUS}"
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

api_request GET "${FOREMAN_API}/architectures?per_page=all"

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

if [ -z "${ARCH_ID}" ] || [ "${ARCH_ID}" = "null" ]; then
    error "x86_64 architecture not found."
    exit 1
fi

ok "x86_64 architecture found. ID=${ARCH_ID}"

###############################################################################
# Partition table
###############################################################################

api_request GET "${FOREMAN_API}/ptables?per_page=all"

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

if [ -z "${PTABLE_ID}" ] || [ "${PTABLE_ID}" = "null" ]; then
    error "Kickstart default partition table not found."
    exit 1
fi

ok "Kickstart default partition table found. ID=${PTABLE_ID}"

###############################################################################
# Media definitions
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
# Get media ID
###############################################################################

get_media_id()
{
    NAME="$1"

    api_request GET "${FOREMAN_API}/media?per_page=all"

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
# Create/update media
###############################################################################

create_media()
{
    NAME="$1"
    PATH_VALUE="$2"

    section "Installation Media : ${NAME}"

    MEDIA_ID="$(get_media_id "${NAME}")"

    if [ -n "${MEDIA_ID}" ] && [ "${MEDIA_ID}" != "null" ]; then

        skip "${NAME} already exists. ID=${MEDIA_ID}"

        api_request GET "${FOREMAN_API}/media/${MEDIA_ID}"

        if api_success && json_valid; then

            EXISTING_PATH="$(
                "${JQ}" -r '.path // empty' "${API_BODY_FILE}"
            )"

            echo "Existing Path : ${EXISTING_PATH}"

            if [ "${EXISTING_PATH}" = "${PATH_VALUE}" ]; then
                ok "${NAME} path verified."
            else
                warn "${NAME} path differs."
            fi

        fi

        return 0
    fi

    info "Creating ${NAME}"

    JSON="$(
        "${JQ}" -n \
            --arg NAME "${NAME}" \
            --arg PATH "${PATH_VALUE}" \
            '{
                medium: {
                    name: $NAME,
                    path: $PATH,
                    os_family: "Redhat"
                }
            }'
    )"

    api_request POST "${FOREMAN_API}/media" "${JSON}"

    if api_success && json_valid; then

        MEDIA_ID="$(
            "${JQ}" -r '.id // empty' "${API_BODY_FILE}"
        )"

        created "${NAME} created. ID=${MEDIA_ID}"

    else

        ERROR_BODY="$("${CAT}" "${API_BODY_FILE}")"

        EXISTING_ID="$(get_media_id "${NAME}")"

        if [ -n "${EXISTING_ID}" ] &&
           [ "${EXISTING_ID}" != "null" ]; then

            skip "${NAME} already exists. ID=${EXISTING_ID}"
            return 0
        fi

        error "${NAME} creation failed."
        echo "${ERROR_BODY}"

        record_failure "${NAME} media"

    fi
}

###############################################################################
# Create media
###############################################################################

header "Creating Installation Media"

for INDEX in "${!MEDIA_NAMES[@]}"; do

    create_media \
        "${MEDIA_NAMES[$INDEX]}" \
        "${MEDIA_PATHS[$INDEX]}"

done

###############################################################################
# Media verification
###############################################################################

header "Installation Media Verification"

api_request GET "${FOREMAN_API}/media?per_page=all"

if api_success && json_valid; then

    "${JQ}" -r '
        .results[]
        | [.id,.name,.path]
        | @tsv
    ' "${API_BODY_FILE}"

else

    error "Unable to verify installation media."
    show_api_error

fi

###############################################################################
# OS definitions
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

    api_request GET "${FOREMAN_API}/operatingsystems?per_page=all"

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
# Create OS
###############################################################################

create_os()
{
    NAME="$1"
    MAJOR="$2"
    MINOR="$3"
    MEDIA_NAME="$4"

    section "Operating System : ${NAME}"

    OS_ID="$(get_os_id "${NAME}")"

    if [ -n "${OS_ID}" ] && [ "${OS_ID}" != "null" ]; then
        skip "${NAME} already exists. ID=${OS_ID}"
        return 0
    fi

    MEDIA_ID="$(get_media_id "${MEDIA_NAME}")"

    if [ -z "${MEDIA_ID}" ] || [ "${MEDIA_ID}" = "null" ]; then

        error "Installation media not found : ${MEDIA_NAME}"
        record_failure "${NAME} media"
        return 1

    fi

    if [ -n "${MINOR}" ]; then

        JSON="$(
            "${JQ}" -n \
                --arg NAME "${NAME}" \
                --arg MAJOR "${MAJOR}" \
                --arg MINOR "${MINOR}" \
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

        JSON="$(
            "${JQ}" -n \
                --arg NAME "${NAME}" \
                --arg MAJOR "${MAJOR}" \
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

    info "Creating ${NAME}"

    api_request POST "${FOREMAN_API}/operatingsystems" "${JSON}"

    if api_success && json_valid; then

        OS_ID="$(
            "${JQ}" -r '.id // empty' "${API_BODY_FILE}"
        )"

        created "${NAME} created. ID=${OS_ID}"

    else

        ERROR_BODY="$("${CAT}" "${API_BODY_FILE}")"

        EXISTING_ID="$(get_os_id "${NAME}")"

        if [ -n "${EXISTING_ID}" ] &&
           [ "${EXISTING_ID}" != "null" ]; then

            skip "${NAME} already exists. ID=${EXISTING_ID}"
            return 0

        fi

        error "${NAME} creation failed."
        echo "${ERROR_BODY}"

        record_failure "${NAME} OS"

    fi
}

###############################################################################
# Create OS
###############################################################################

header "Creating Operating Systems"

for INDEX in "${!OS_NAMES[@]}"; do

    create_os \
        "${OS_NAMES[$INDEX]}" \
        "${OS_MAJORS[$INDEX]}" \
        "${OS_MINORS[$INDEX]}" \
        "${OS_MEDIA[$INDEX]}"

done

###############################################################################
# OS verification
###############################################################################

header "Operating System Verification"

api_request GET "${FOREMAN_API}/operatingsystems?per_page=all"

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
# PXE template files
###############################################################################

header "Generating PXEGrub2 Template Files"

"${MKDIR}" -p "${WORK_DIR}"

create_template_file()
{
    FILE="$1"
    TITLE="$2"

    "${CAT}" > "${FILE}" <<TEMPLATE
set default=0
set timeout=10

menuentry '${TITLE}' {
    linuxefi <%= @kernel %> <%= pxe_kernel_options %> inst.ks=<%= foreman_url('provision') %>
    initrdefi <%= @initrd %>
}
TEMPLATE
}

create_template_file \
    "${WORK_DIR}/centos-raid.erb" \
    "CentOS 7 RAID Kickstart"

create_template_file \
    "${WORK_DIR}/centos-singledisk.erb" \
    "CentOS 7 SingleDisk Kickstart"

create_template_file \
    "${WORK_DIR}/rocky8-raid.erb" \
    "Rocky 8 RAID Kickstart"

create_template_file \
    "${WORK_DIR}/rocky8-singledisk.erb" \
    "Rocky 8 SingleDisk Kickstart"

create_template_file \
    "${WORK_DIR}/rocky92-raid.erb" \
    "Rocky 9.2 RAID Kickstart"

create_template_file \
    "${WORK_DIR}/rocky92-singledisk.erb" \
    "Rocky 9.2 SingleDisk Kickstart"

create_template_file \
    "${WORK_DIR}/rocky98-raid.erb" \
    "Rocky 9.8 RAID Kickstart"

create_template_file \
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
# Find PXEGrub2 kind
###############################################################################

header "Finding PXEGrub2 Template Kind"

info "Detecting PXEGrub2 template kind from provisioning templates..."

api_request GET "${FOREMAN_API}/provisioning_templates?per_page=all"

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

if [ -z "${PXEGRUB2_KIND_ID}" ] ||
   [ "${PXEGRUB2_KIND_ID}" = "null" ]; then

    error "PXEGrub2 template kind not found."
    exit 1

fi

ok "PXEGrub2 template kind found. ID=${PXEGRUB2_KIND_ID}"

###############################################################################
# Get provisioning template ID
###############################################################################

get_template_id()
{
    NAME="$1"

    api_request GET "${FOREMAN_API}/provisioning_templates?per_page=all"

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
# Create PXE template
###############################################################################

create_template()
{
    NAME="$1"
    FILE="$2"

    section "PXEGrub2 template : ${NAME}"

    TEMPLATE_ID="$(get_template_id "${NAME}")"

    if [ -n "${TEMPLATE_ID}" ] &&
       [ "${TEMPLATE_ID}" != "null" ]; then

        skip "${NAME} already exists. ID=${TEMPLATE_ID}"
        return 0

    fi

    CONTENT="$("${CAT}" "${FILE}")"

    JSON="$(
        "${JQ}" -n \
            --arg NAME "${NAME}" \
            --arg TEMPLATE "${CONTENT}" \
            --argjson KIND "${PXEGRUB2_KIND_ID}" \
            '{
                provisioning_template: {
                    name: $NAME,
                    template: $TEMPLATE,
                    template_kind_id: $KIND
                }
            }'
    )"

    info "Creating ${NAME}"

    api_request \
        POST \
        "${FOREMAN_API}/provisioning_templates" \
        "${JSON}"

    if api_success && json_valid; then

        TEMPLATE_ID="$(
            "${JQ}" -r '.id // empty' "${API_BODY_FILE}"
        )"

        created "${NAME} created. ID=${TEMPLATE_ID}"

    else

        ERROR_BODY="$("${CAT}" "${API_BODY_FILE}")"

        EXISTING_ID="$(get_template_id "${NAME}")"

        if [ -n "${EXISTING_ID}" ] &&
           [ "${EXISTING_ID}" != "null" ]; then

            skip "${NAME} already exists. ID=${EXISTING_ID}"
            return 0

        fi

        error "${NAME} creation failed."
        echo "${ERROR_BODY}"

        record_failure "${NAME} template"

    fi
}

###############################################################################
# Create templates
###############################################################################

header "Creating PXEGrub2 Templates"

for INDEX in "${!TEMPLATE_NAMES[@]}"; do

    create_template \
        "${TEMPLATE_NAMES[$INDEX]}" \
        "${TEMPLATE_FILES[$INDEX]}"

done

###############################################################################
# Mapping
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
# Associate template
###############################################################################

associate_template()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    section "Associating:"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"

    OS_ID="$(get_os_id "${OS_NAME}")"
    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -z "${OS_ID}" ] || [ "${OS_ID}" = "null" ]; then
        error "Operating System not found : ${OS_NAME}"
        record_failure "${OS_NAME} association"
        return
    fi

    if [ -z "${TEMPLATE_ID}" ] || [ "${TEMPLATE_ID}" = "null" ]; then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${OS_NAME} association"
        return
    fi

    api_request GET "${FOREMAN_API}/operatingsystems/${OS_ID}"

    if ! api_success || ! json_valid; then
        error "Unable to read ${OS_NAME}"
        show_api_error
        record_failure "${OS_NAME} association"
        return
    fi

    FOUND="$(
        "${JQ}" -r \
            --argjson ID "${TEMPLATE_ID}" \
            '
            [
                (.provisioning_templates // [])[]
                | .id
            ]
            | map(select(. == $ID))
            | length
            ' "${API_BODY_FILE}"
    )"

    if [ "${FOUND}" = "1" ]; then
        skip "${TEMPLATE_NAME} already associated."
        return
    fi

    IDS="$(
        "${JQ}" -c '
            [
                (.provisioning_templates // [])[]
                | .id
            ]
            | unique
        ' "${API_BODY_FILE}"
    )"

    NEW_IDS="$(
        "${JQ}" -c \
            --argjson ID "${TEMPLATE_ID}" \
            '. + [$ID] | unique' <<< "${IDS}"
    )"

    JSON="$(
        "${JQ}" -n \
            --argjson IDS "${NEW_IDS}" \
            '{
                operatingsystem: {
                    provisioning_template_ids: $IDS
                }
            }'
    )"

    api_request \
        PUT \
        "${FOREMAN_API}/operatingsystems/${OS_ID}" \
        "${JSON}"

    if api_success; then
        updated "${TEMPLATE_NAME} associated with ${OS_NAME}."
    else
        error "Failed associating ${TEMPLATE_NAME}."
        show_api_error
        record_failure "${OS_NAME} association"
    fi
}

###############################################################################
# Associations
###############################################################################

header "Associating PXEGrub2 Templates"

for INDEX in "${!MAP_OS[@]}"; do

    associate_template \
        "${MAP_OS[$INDEX]}" \
        "${MAP_TEMPLATE[$INDEX]}"

done

###############################################################################
# IMPORTANT:
# PXEGrub2 DEFAULT FIX
#
# We preserve the POST response BEFORE doing any follow-up GET.
#
# Foreman 3.2:
# POST /api/operatingsystems/:id/os_default_templates
#
# Body:
# {
#   "os_default_template": {
#     "provisioning_template_id": TEMPLATE_ID,
#     "template_kind_id": PXEGRUB2_KIND_ID
#   }
# }
#
###############################################################################

set_pxe_default()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    section "Setting PXEGrub2 Default:"
    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"

    OS_ID="$(get_os_id "${OS_NAME}")"
    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -z "${OS_ID}" ] || [ "${OS_ID}" = "null" ]; then

        error "Operating System not found : ${OS_NAME}"
        record_failure "${OS_NAME} default"
        return

    fi

    if [ -z "${TEMPLATE_ID}" ] || [ "${TEMPLATE_ID}" = "null" ]; then

        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${OS_NAME} default"
        return

    fi

    ###########################################################################
    # Read current defaults
    ###########################################################################

    api_request \
        GET \
        "${FOREMAN_API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"

    if ! api_success || ! json_valid; then

        error "Unable to query defaults for ${OS_NAME}."
        show_api_error
        record_failure "${OS_NAME} default lookup"
        return

    fi

    ###########################################################################
    # Find PXEGrub2 default
    ###########################################################################

    DEFAULT_ROW="$(
        "${JQ}" -c \
            --argjson KIND "${PXEGRUB2_KIND_ID}" \
            '
            .results[]
            | select(.template_kind_id == $KIND)
            ' "${API_BODY_FILE}" |
            "${HEAD}" -1
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
            "${JQ}" -r '.provisioning_template_name // ""' <<< "${DEFAULT_ROW}"
        )"

        #######################################################################
        # Already correct
        #######################################################################

        if [ "${DEFAULT_TEMPLATE_ID}" = "${TEMPLATE_ID}" ]; then

            skip "PXEGrub2 default already correct: ${DEFAULT_TEMPLATE_NAME}"
            return

        fi

        #######################################################################
        # Existing but wrong -> UPDATE
        #######################################################################

        info "Existing PXEGrub2 default found."
        echo "Existing : ${DEFAULT_TEMPLATE_NAME}"
        echo "Requested: ${TEMPLATE_NAME}"

        JSON="$(
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
            "${JSON}"

        if api_success; then

            updated "PXEGrub2 default updated -> ${TEMPLATE_NAME}"

        else

            error "PXEGrub2 default update failed."
            error "HTTP Status : ${API_STATUS}"
            show_api_error

            record_failure "${OS_NAME} default update"

        fi

        return
    fi

    ###########################################################################
    # No PXEGrub2 default
    ###########################################################################

    info "No PXEGrub2 default found. Creating one..."

    JSON="$(
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

    ###########################################################################
    # DEBUG - show exact request
    ###########################################################################

    echo
    echo "${CYAN}POST URL:${RESET}"
    echo "${FOREMAN_API}/operatingsystems/${OS_ID}/os_default_templates"

    echo
    echo "${CYAN}POST BODY:${RESET}"
    echo "${JSON}" | "${JQ}" .

    ###########################################################################
    # POST
    ###########################################################################

    api_request \
        POST \
        "${FOREMAN_API}/operatingsystems/${OS_ID}/os_default_templates" \
        "${JSON}"

    ###########################################################################
    # IMPORTANT:
    # Save the POST response BEFORE doing ANY other API request.
    ###########################################################################

    POST_STATUS="${API_STATUS}"
    POST_BODY="$("${CAT}" "${API_BODY_FILE}")"

    ###########################################################################
    # Success
    ###########################################################################

    if [[ "${POST_STATUS}" =~ ^2[0-9][0-9]$ ]]; then

        created "PXEGrub2 default created for ${OS_NAME}."

        return

    fi

    ###########################################################################
    # Actual POST error
    ###########################################################################

    error "PXEGrub2 default creation failed."
    error "HTTP Status : ${POST_STATUS}"

    echo
    echo "${RED}Actual POST response:${RESET}"

    if echo "${POST_BODY}" | "${JQ}" . >/dev/null 2>&1; then
        echo "${POST_BODY}" | "${JQ}" .
    else
        echo "${POST_BODY}"
    fi

    ###########################################################################
    # Retry lookup AFTER preserving actual error
    ###########################################################################

    api_request \
        GET \
        "${FOREMAN_API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"

    if api_success && json_valid; then

        EXISTING_ID="$(
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

        if [ -n "${EXISTING_ID}" ] &&
           [ "${EXISTING_ID}" != "null" ]; then

            skip "PXEGrub2 default appeared during request. ID=${EXISTING_ID}"
            return

        fi

    fi

    record_failure "${OS_NAME} default creation"
}

###############################################################################
# Set defaults
###############################################################################

header "Setting PXEGrub2 Default Templates"

for INDEX in "${!MAP_OS[@]}"; do

    set_pxe_default \
        "${MAP_OS[$INDEX]}" \
        "${MAP_TEMPLATE[$INDEX]}"

done

###############################################################################
# Domain lookup
###############################################################################

get_domain_id()
{
    NAME="$1"

    api_request GET "${FOREMAN_API}/domains?per_page=all"

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
# Smart proxy lookup
###############################################################################

get_proxy_id()
{
    NAME="$1"

    api_request GET "${FOREMAN_API}/smart_proxies?per_page=all"

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
# Subnet lookup
###############################################################################

get_subnet_id()
{
    NAME="$1"

    api_request GET "${FOREMAN_API}/subnets?per_page=all"

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
# Create/update subnet
###############################################################################

create_subnet()
{
    NAME="$1"
    NETWORK="$2"
    MASK="$3"
    GATEWAY="$4"
    DNS="$5"
    TFTP_NAME="$6"
    DHCP_NAME="$7"

    section "Subnet : ${NAME}"

    echo "Network      : ${NETWORK}"
    echo "Mask         : ${MASK}"
    echo "Gateway      : ${GATEWAY}"
    echo "DNS          : ${DNS}"
    echo "TFTP Proxy   : ${TFTP_NAME}"
    echo "DHCP Proxy   : ${DHCP_NAME}"

    DOMAIN_ID="$(get_domain_id "vgs.com")"

    if [ -z "${DOMAIN_ID}" ]; then
        error "Domain not found : vgs.com"
        record_failure "${NAME} domain"
        return
    fi

    ok "Domain found : vgs.com ID=${DOMAIN_ID}"

    TFTP_ID="$(get_proxy_id "${TFTP_NAME}")"

    if [ -z "${TFTP_ID}" ]; then
        error "TFTP proxy not found : ${TFTP_NAME}"
        record_failure "${NAME} TFTP"
        return
    fi

    ok "TFTP proxy found : ${TFTP_NAME} ID=${TFTP_ID}"

    DHCP_ID="$(get_proxy_id "${DHCP_NAME}")"

    if [ -z "${DHCP_ID}" ]; then
        error "DHCP proxy not found : ${DHCP_NAME}"
        record_failure "${NAME} DHCP"
        return
    fi

    ok "DHCP proxy found : ${DHCP_NAME} ID=${DHCP_ID}"

    SUBNET_ID="$(get_subnet_id "${NAME}")"

    JSON="$(
        "${JQ}" -n \
            --arg NAME "${NAME}" \
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

    if [ -n "${SUBNET_ID}" ] &&
       [ "${SUBNET_ID}" != "null" ]; then

        skip "${NAME} already exists. ID=${SUBNET_ID}"

        api_request \
            PUT \
            "${FOREMAN_API}/subnets/${SUBNET_ID}" \
            "${JSON}"

        if api_success; then
            ok "${NAME} updated."
        else
            error "${NAME} update failed."
            show_api_error
        fi

        return
    fi

    info "Creating ${NAME}"

    api_request \
        POST \
        "${FOREMAN_API}/subnets" \
        "${JSON}"

    if api_success && json_valid; then

        SUBNET_ID="$(
            "${JQ}" -r '.id // empty' "${API_BODY_FILE}"
        )"

        created "${NAME} created. ID=${SUBNET_ID}"

    else

        error "${NAME} creation failed."
        show_api_error
        record_failure "${NAME} subnet"

    fi
}

###############################################################################
# Subnets
###############################################################################

header "Creating PXE Subnets"

create_subnet \
    "vgs-subnet-centos" \
    "192.168.253.0" \
    "255.255.255.0" \
    "192.168.253.2" \
    "192.168.253.1" \
    "cent-07-01.vgs.com" \
    "cent-07-01.vgs.com"

create_subnet \
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

api_request GET "${FOREMAN_API}/subnets?per_page=all"

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
# Template verification
###############################################################################

header "PXEGrub2 Template Verification"

api_request GET "${FOREMAN_API}/provisioning_templates?per_page=all"

if api_success && json_valid; then

    for TEMPLATE_NAME in "${TEMPLATE_NAMES[@]}"; do

        ROW="$(
            "${JQ}" -c \
                --arg NAME "${TEMPLATE_NAME}" \
                '
                .results[]
                | select(.name == $NAME)
                ' "${API_BODY_FILE}" |
                "${HEAD}" -1
        )"

        if [ -n "${ROW}" ]; then

            ID="$("${JQ}" -r '.id' <<< "${ROW}")"
            KIND="$("${JQ}" -r '.template_kind_name // ""' <<< "${ROW}")"
            KIND_ID="$("${JQ}" -r '.template_kind_id // ""' <<< "${ROW}")"

            ok "${TEMPLATE_NAME} | ID=${ID} | kind=${KIND} | kind_id=${KIND_ID}"

        else

            error "${TEMPLATE_NAME} verification failed."

        fi

    done

else

    error "Unable to verify templates."
    show_api_error

fi

###############################################################################
# Association verification
###############################################################################

header "OS Template Mapping Verification"

for INDEX in "${!MAP_OS[@]}"; do

    OS_NAME="${MAP_OS[$INDEX]}"
    TEMPLATE_NAME="${MAP_TEMPLATE[$INDEX]}"

    OS_ID="$(get_os_id "${OS_NAME}")"
    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -z "${OS_ID}" ] || [ -z "${TEMPLATE_ID}" ]; then

        error "${OS_NAME} -> ${TEMPLATE_NAME}"
        continue

    fi

    api_request GET "${FOREMAN_API}/operatingsystems/${OS_ID}"

    if ! api_success || ! json_valid; then
        error "Unable to verify ${OS_NAME}"
        continue
    fi

    FOUND="$(
        "${JQ}" -r \
            --argjson ID "${TEMPLATE_ID}" \
            '
            [
                (.provisioning_templates // [])[]
                | .id
            ]
            | map(select(. == $ID))
            | length
            ' "${API_BODY_FILE}"
    )"

    if [ "${FOUND}" = "1" ]; then
        ok "${OS_NAME} -> ${TEMPLATE_NAME}"
    else
        error "${OS_NAME} -> ${TEMPLATE_NAME} association missing."
    fi

done

###############################################################################
# Default verification
###############################################################################

header "PXEGrub2 Default Template Verification"

for INDEX in "${!MAP_OS[@]}"; do

    OS_NAME="${MAP_OS[$INDEX]}"
    TEMPLATE_NAME="${MAP_TEMPLATE[$INDEX]}"

    OS_ID="$(get_os_id "${OS_NAME}")"
    TEMPLATE_ID="$(get_template_id "${TEMPLATE_NAME}")"

    if [ -z "${OS_ID}" ] || [ -z "${TEMPLATE_ID}" ]; then
        error "${OS_NAME} default verification skipped."
        continue
    fi

    api_request \
        GET \
        "${FOREMAN_API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"

    if ! api_success || ! json_valid; then

        error "${OS_NAME} default verification failed."
        show_api_error
        continue

    fi

    MATCH="$(
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

    if [ "${MATCH}" = "1" ]; then

        ok "${OS_NAME} PXEGrub2 default -> ${TEMPLATE_NAME}"

    else

        error "${OS_NAME} PXEGrub2 default incorrect/missing."

    fi

done

###############################################################################
# Files
###############################################################################

header "Generated PXE Template Files"

"${LS}" -lh "${WORK_DIR}"/*.erb 2>/dev/null || true

###############################################################################
# Summary
###############################################################################

header "01 - Foreman PXE Bootstrap API Completed"

echo
echo "${GREEN}Created : ${CREATED_COUNT}${RESET}"
echo "${MAGENTA}Updated : ${UPDATED_COUNT}${RESET}"
echo "${YELLOW}Skipped : ${SKIPPED_COUNT}${RESET}"
echo "${RED}Errors  : ${ERROR_COUNT}${RESET}"

if [ "${#FAILURES[@]}" -gt 0 ]; then

    echo
    echo "${RED}${BOLD}Failures:${RESET}"

    for FAILURE in "${FAILURES[@]}"; do
        echo "${RED}[ERROR]${RESET} ${FAILURE}"
    done

fi

echo

if [ "${ERROR_COUNT}" -eq 0 ]; then

    echo "${GREEN}${BOLD}============================================================${RESET}"
    echo "${GREEN}${BOLD}BOOTSTRAP COMPLETED SUCCESSFULLY${RESET}"
    echo "${GREEN}${BOLD}============================================================${RESET}"

    exit 0

else

    echo "${YELLOW}${BOLD}============================================================${RESET}"
    echo "${YELLOW}${BOLD}BOOTSTRAP COMPLETED WITH ERRORS${RESET}"
    echo "${YELLOW}${BOLD}============================================================${RESET}"

    exit 1

fi

EOF
