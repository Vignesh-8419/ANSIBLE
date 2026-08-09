#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap - REST API
#
# Foreman 3.x
# Direct REST API
# NO HAMMER
#
# Features:
#   - PAT authentication
#   - Idempotent installation media
#   - Idempotent operating systems
#   - PXEGrub2 template detection
#   - PXEGrub2 template creation/update
#   - OS/template association
#   - PXEGrub2 default template creation/update
#   - PXE subnet creation/update
#   - Final verification
#
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

section()
{
    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

subsection()
{
    echo
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
}

###############################################################################
# FAILURE TRACKING
###############################################################################

FAILURES=()

record_failure()
{
    FAILURES+=("$1")
}

###############################################################################
# CONFIGURATION
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_TOKEN="${FOREMAN_TOKEN:-}"

FOREMAN_INSECURE="${FOREMAN_INSECURE:-true}"

API="${FOREMAN_URL}/api"

###############################################################################
# REQUIRED PAT
###############################################################################

if [ -z "${FOREMAN_TOKEN}" ]
then
    error "FOREMAN_TOKEN is not set."
    echo
    echo "Set your Personal Access Token:"
    echo
    echo "export FOREMAN_USER='admin'"
    echo "export FOREMAN_TOKEN='YOUR_FOREMAN_PAT'"
    echo
    exit 1
fi

###############################################################################
# DEPENDENCY CHECK
###############################################################################

section "Dependency Check"

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

for CMD in "${REQUIRED_COMMANDS[@]}"
do
    if command -v "${CMD}" >/dev/null 2>&1
    then
        ok "${CMD} found: $(command -v "${CMD}")"
    else
        error "${CMD} not found."
        record_failure "Dependency: ${CMD}"
    fi
done

if [ ${#FAILURES[@]} -ne 0 ]
then
    error "Required dependencies are missing."
    exit 1
fi

###############################################################################
# SSL
###############################################################################

CURL_SSL=""

if [ "${FOREMAN_INSECURE}" = "true" ]
then
    CURL_SSL="-k"
fi

###############################################################################
# API RESPONSE VARIABLES
###############################################################################

API_STATUS=""
API_BODY=""
API_METHOD=""
API_URL=""

###############################################################################
# JSON CHECK
###############################################################################

is_json()
{
    local DATA="$1"

    echo "${DATA}" | jq -e . >/dev/null 2>&1

    return $?
}

###############################################################################
# API REQUEST
#
# Result:
#   API_STATUS
#   API_BODY
###############################################################################

api_request()
{
    local METHOD="$1"
    local URL="$2"
    local DATA="${3:-}"

    local BODY_FILE
    local HEADER_FILE
    local CURL_OUTPUT
    local CURL_RC

    API_METHOD="${METHOD}"
    API_URL="${URL}"
    API_STATUS=""
    API_BODY=""

    BODY_FILE="$(mktemp)"
    HEADER_FILE="$(mktemp)"

    if [ -n "${DATA}" ]
    then

        CURL_OUTPUT="$(
            curl \
                -sS \
                ${CURL_SSL} \
                --request "${METHOD}" \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                --header "Accept: application/json,version=2" \
                --header "Content-Type: application/json" \
                --data "${DATA}" \
                --output "${BODY_FILE}" \
                --dump-header "${HEADER_FILE}" \
                --write-out "%{http_code}" \
                "${URL}" 2>&1
        )"

    else

        CURL_OUTPUT="$(
            curl \
                -sS \
                ${CURL_SSL} \
                --request "${METHOD}" \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                --header "Accept: application/json,version=2" \
                --header "Content-Type: application/json" \
                --output "${BODY_FILE}" \
                --dump-header "${HEADER_FILE}" \
                --write-out "%{http_code}" \
                "${URL}" 2>&1
        )"

    fi

    CURL_RC=$?

    if [ ${CURL_RC} -ne 0 ]
    then
        API_STATUS=""
        API_BODY=""

        rm -f "${BODY_FILE}" "${HEADER_FILE}"

        error "curl failed."
        error "Method : ${METHOD}"
        error "URL    : ${URL}"
        error "curl   : ${CURL_OUTPUT}"

        return 1
    fi

    API_STATUS="${CURL_OUTPUT}"
    API_BODY="$(cat "${BODY_FILE}")"

    rm -f "${BODY_FILE}" "${HEADER_FILE}"

    if [[ "${API_STATUS}" =~ ^2[0-9][0-9]$ ]]
    then
        return 0
    fi

    return 1
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

    if [ -n "${API_BODY}" ]
    then
        echo "${API_BODY}" | jq . 2>/dev/null || echo "${API_BODY}"
    fi
}

###############################################################################
# API WRAPPERS
###############################################################################

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
# SEARCH
###############################################################################

api_search()
{
    local RESOURCE="$1"
    local SEARCH="$2"

    api_request \
        GET \
        "${API}/${RESOURCE}?search=$(printf '%s' "${SEARCH}" | sed 's/ /%20/g' | sed 's/"/%22/g')&per_page=all"
}

###############################################################################
# AUTHENTICATION TEST
###############################################################################

section "01 - Foreman PXE Bootstrap - REST API"

section "Foreman API Authentication Test"

info "Testing Foreman REST API..."

if api_get "${API}/status"
then

    if ! is_json "${API_BODY}"
    then
        error "Foreman returned invalid JSON."
        exit 1
    fi

    FOREMAN_VERSION="$(
        echo "${API_BODY}" |
        jq -r '.version // .foreman_version // empty'
    )"

    API_VERSION="$(
        echo "${API_BODY}" |
        jq -r '.api_version // empty'
    )"

    STATUS_CODE="$(
        echo "${API_BODY}" |
        jq -r '.status // empty'
    )"

    ok "Foreman API authentication successful."

    echo "Foreman Version : ${FOREMAN_VERSION}"
    echo "API Version     : ${API_VERSION}"
    echo "API Status      : ${STATUS_CODE:-${API_STATUS}}"

else

    show_api_error
    error "Foreman API authentication failed."
    exit 1

fi

###############################################################################
# INSTALLATION MEDIA CONFIGURATION
###############################################################################

CENTOS_MEDIA="CentOS 7 Remote"
CENTOS_MEDIA_URL="http://192.168.253.136/repo/centos/"

ROCKY8_MEDIA="Rocky 8 Remote"
ROCKY8_MEDIA_URL="http://192.168.253.136/repo/rocky8/"

ROCKY92_MEDIA="Rocky 9.2 Remote"
ROCKY92_MEDIA_URL="http://192.168.253.136/repo/rocky9.2/"

ROCKY98_MEDIA="Rocky 9 Remote"
ROCKY98_MEDIA_URL="http://192.168.253.136/repo/rocky9/"

###############################################################################
# OPERATING SYSTEM CONFIGURATION
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
# PXE TEMPLATE CONFIGURATION
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
# PXE SUBNET CONFIGURATION
###############################################################################

CENTOS_SUBNET_NAME="vgs-subnet-centos"
ROCKY_SUBNET_NAME="vgs-subnet-rockyos"

SUBNET_NETWORK="192.168.253.0"
SUBNET_MASK="255.255.255.0"
SUBNET_GATEWAY="192.168.253.2"
SUBNET_DNS="192.168.253.1"

DOMAIN_NAME="vgs.com"

CENTOS_PROXY="cent-07-01.vgs.com"
ROCKY_PROXY="cent-07-02.vgs.com"

###############################################################################
# FIND MEDIA
###############################################################################

find_media_id()
{
    local MEDIA_NAME="$1"
    local RESPONSE

    if ! api_get "${API}/media?per_page=all"
    then
        return 1
    fi

    RESPONSE="${API_BODY}"

    echo "${RESPONSE}" |
    jq -r \
        --arg NAME "${MEDIA_NAME}" \
        '
        .results[]?
        | select(.name == $NAME)
        | .id
        ' |
    head -n 1
}

###############################################################################
# CREATE / VERIFY MEDIA
###############################################################################

create_media()
{
    local MEDIA_NAME="$1"
    local MEDIA_URL="$2"

    local MEDIA_ID
    local JSON

    subsection "Installation Media : ${MEDIA_NAME}"

    MEDIA_ID="$(find_media_id "${MEDIA_NAME}")"

    if [ -n "${MEDIA_ID}" ]
    then
        skip "${MEDIA_NAME} already exists. ID=${MEDIA_ID}"
        return 0
    fi

    info "Creating ${MEDIA_NAME}"

    JSON="$(
        jq -n \
            --arg NAME "${MEDIA_NAME}" \
            --arg PATH "${MEDIA_URL}" \
            '{
                medium: {
                    name: $NAME,
                    path: $PATH,
                    os_family: "Redhat"
                }
            }'
    )"

    if api_post "${API}/media" "${JSON}"
    then

        MEDIA_ID="$(
            echo "${API_BODY}" |
            jq -r '.id // empty'
        )"

        ok "${MEDIA_NAME} created. ID=${MEDIA_ID}"

    else

        if [ "${API_STATUS}" = "422" ]
        then

            MEDIA_ID="$(find_media_id "${MEDIA_NAME}")"

            if [ -n "${MEDIA_ID}" ]
            then
                skip "${MEDIA_NAME} already exists. ID=${MEDIA_ID}"
                return 0
            fi
        fi

        show_api_error
        record_failure "${MEDIA_NAME} creation"
        return 1

    fi
}

###############################################################################
# MEDIA
###############################################################################

section "Creating / Verifying Installation Media"

create_media "${CENTOS_MEDIA}" "${CENTOS_MEDIA_URL}"
create_media "${ROCKY8_MEDIA}" "${ROCKY8_MEDIA_URL}"
create_media "${ROCKY92_MEDIA}" "${ROCKY92_MEDIA_URL}"
create_media "${ROCKY98_MEDIA}" "${ROCKY98_MEDIA_URL}"

###############################################################################
# MEDIA VERIFICATION
###############################################################################

section "Installation Media Verification"

if api_get "${API}/media?per_page=all"
then

    echo "${API_BODY}" |
    jq -r '
        .results[]? |
        [
            .id,
            .name,
            .path
        ] |
        @tsv
    '

else

    show_api_error
    record_failure "Installation Media Verification"

fi

###############################################################################
# ARCHITECTURE
###############################################################################

section "Finding Architecture"

ARCH_ID=""

if api_get "${API}/architectures?per_page=all"
then

    ARCH_ID="$(
        echo "${API_BODY}" |
        jq -r '
            .results[]?
            | select(.name == "x86_64")
            | .id
        ' |
        head -n 1
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
# PARTITION TABLE
###############################################################################

section "Finding Partition Table"

PTABLE_ID=""

if api_get "${API}/ptables?per_page=all"
then

    PTABLE_ID="$(
        echo "${API_BODY}" |
        jq -r '
            .results[]?
            | select(.name == "Kickstart default")
            | .id
        ' |
        head -n 1
    )"

fi

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
    local OS_NAME="$1"

    if ! api_get "${API}/operatingsystems?per_page=all"
    then
        return 1
    fi

    echo "${API_BODY}" |
    jq -r \
        --arg NAME "${OS_NAME}" \
        '
        .results[]?
        | select(.name == $NAME)
        | .id
        ' |
    head -n 1
}

###############################################################################
# CREATE / VERIFY OS
###############################################################################

create_os()
{
    local OS_NAME="$1"
    local MAJOR="$2"
    local MINOR="$3"
    local MEDIA_NAME="$4"

    local OS_ID
    local MEDIA_ID
    local JSON

    subsection "Operating System : ${OS_NAME}"

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -n "${OS_ID}" ]
    then
        skip "${OS_NAME} already exists. ID=${OS_ID}"
        return 0
    fi

    MEDIA_ID="$(find_media_id "${MEDIA_NAME}")"

    if [ -z "${MEDIA_ID}" ]
    then
        error "Installation media not found : ${MEDIA_NAME}"
        record_failure "${OS_NAME} media"
        return 1
    fi

    if [ -z "${ARCH_ID}" ]
    then
        error "Architecture ID unavailable."
        record_failure "${OS_NAME} architecture"
        return 1
    fi

    if [ -z "${PTABLE_ID}" ]
    then
        error "Partition table ID unavailable."
        record_failure "${OS_NAME} partition table"
        return 1
    fi

    info "Creating ${OS_NAME}"

    JSON="$(
        jq -n \
            --arg NAME "${OS_NAME}" \
            --arg MAJOR "${MAJOR}" \
            --arg MINOR "${MINOR}" \
            --arg FAMILY "Redhat" \
            --argjson ARCH "${ARCH_ID}" \
            --argjson MEDIA "${MEDIA_ID}" \
            --argjson PTABLE "${PTABLE_ID}" \
            '{
                operatingsystem: {
                    name: $NAME,
                    major: $MAJOR,
                    minor: $MINOR,
                    family: $FAMILY,
                    architecture_ids: [$ARCH],
                    medium_ids: [$MEDIA],
                    ptable_ids: [$PTABLE]
                }
            }'
    )"

    if api_post "${API}/operatingsystems" "${JSON}"
    then

        OS_ID="$(
            echo "${API_BODY}" |
            jq -r '.id // empty'
        )"

        ok "${OS_NAME} created. ID=${OS_ID}"

    else

        if [ "${API_STATUS}" = "422" ]
        then

            OS_ID="$(find_os_id "${OS_NAME}")"

            if [ -n "${OS_ID}" ]
            then
                skip "${OS_NAME} already exists. ID=${OS_ID}"
                return 0
            fi
        fi

        show_api_error
        record_failure "${OS_NAME} creation"
        return 1

    fi
}

###############################################################################
# OPERATING SYSTEMS
###############################################################################

section "Creating / Verifying Operating Systems"

create_os "${CENTOS_RAID_NAME}" "7" "" "${CENTOS_MEDIA}"
create_os "${CENTOS_SINGLE_NAME}" "7" "" "${CENTOS_MEDIA}"

create_os "${ROCKY8_RAID_NAME}" "8" "10" "${ROCKY8_MEDIA}"
create_os "${ROCKY8_SINGLE_NAME}" "8" "10" "${ROCKY8_MEDIA}"

create_os "${ROCKY92_RAID_NAME}" "9" "2" "${ROCKY92_MEDIA}"
create_os "${ROCKY92_SINGLE_NAME}" "9" "2" "${ROCKY92_MEDIA}"

create_os "${ROCKY98_RAID_NAME}" "9" "8" "${ROCKY98_MEDIA}"
create_os "${ROCKY98_SINGLE_NAME}" "9" "8" "${ROCKY98_MEDIA}"

###############################################################################
# OS VERIFICATION
###############################################################################

section "Operating System Verification"

if api_get "${API}/operatingsystems?per_page=all"
then

    printf "%-5s %-35s %-7s %-7s %-10s\n" \
        "ID" "NAME" "MAJOR" "MINOR" "FAMILY"

    echo "${API_BODY}" |
    jq -r '
        .results[]?
        | [
            .id,
            .name,
            .major,
            (.minor // ""),
            (.family // "")
        ]
        | @tsv
    '

else

    show_api_error
    record_failure "Operating System Verification"

fi

###############################################################################
# TEMPLATE DIRECTORY
###############################################################################

TEMPLATE_DIR="/tmp/foreman-pxe-bootstrap"

mkdir -p "${TEMPLATE_DIR}"

###############################################################################
# GENERATE TEMPLATE
#
# Existing templates are NOT overwritten blindly.
# If missing, these are created.
###############################################################################

generate_templates()
{
    section "Generating PXEGrub2 Template Files"

    cat > "${TEMPLATE_DIR}/centos-raid.erb" <<'EOF'
set default=0
set timeout=10

menuentry 'CentOS 7 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF

    cat > "${TEMPLATE_DIR}/centos-singledisk.erb" <<'EOF'
set default=0
set timeout=10

menuentry 'CentOS 7 SingleDisk' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF

    cat > "${TEMPLATE_DIR}/rocky8-raid.erb" <<'EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 8 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF

    cat > "${TEMPLATE_DIR}/rocky8-singledisk.erb" <<'EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 8 SingleDisk' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF

    cat > "${TEMPLATE_DIR}/rocky92-raid.erb" <<'EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.2 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF

    cat > "${TEMPLATE_DIR}/rocky92-singledisk.erb" <<'EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.2 SingleDisk' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF

    cat > "${TEMPLATE_DIR}/rocky98-raid.erb" <<'EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.8 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF

    cat > "${TEMPLATE_DIR}/rocky98-singledisk.erb" <<'EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.8 SingleDisk' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF

    ok "All 8 PXEGrub2 template files generated."

    ls -l "${TEMPLATE_DIR}"/*.erb

}

generate_templates

###############################################################################
# FIND PXEGRUB2 TEMPLATE KIND
###############################################################################

section "Finding Existing PXEGrub2 Template Kind"

PXEGRUB2_KIND_ID=""

if api_get "${API}/provisioning_templates?per_page=all"
then

    PXEGRUB2_KIND_ID="$(
        echo "${API_BODY}" |
        jq -r '
            .results[]?
            | select(.template_kind_name == "PXEGrub2")
            | .template_kind_id
        ' |
        head -n 1
    )"

fi

if [ -n "${PXEGRUB2_KIND_ID}" ]
then

    ok "PXEGrub2 template kind found."
    echo "PXEGrub2 Template Kind ID : ${PXEGRUB2_KIND_ID}"

else

    error "PXEGrub2 template kind not found."
    record_failure "PXEGrub2 template kind"

fi

###############################################################################
# FIND TEMPLATE
###############################################################################

find_template_id()
{
    local TEMPLATE_NAME="$1"

    if ! api_get "${API}/provisioning_templates?per_page=all"
    then
        return 1
    fi

    echo "${API_BODY}" |
    jq -r \
        --arg NAME "${TEMPLATE_NAME}" \
        '
        .results[]?
        | select(.name == $NAME)
        | .id
        ' |
    head -n 1
}

###############################################################################
# CREATE / UPDATE PXE TEMPLATE
###############################################################################

create_or_update_template()
{
    local TEMPLATE_NAME="$1"
    local TEMPLATE_FILE="$2"

    local TEMPLATE_ID
    local TEMPLATE_TEXT
    local JSON

    subsection "PXEGrub2 Template : ${TEMPLATE_NAME}"

    if [ -z "${PXEGRUB2_KIND_ID}" ]
    then
        error "PXEGrub2 kind ID unavailable."
        record_failure "${TEMPLATE_NAME} kind"
        return 1
    fi

    if [ ! -f "${TEMPLATE_FILE}" ]
    then
        error "Template file missing : ${TEMPLATE_FILE}"
        record_failure "${TEMPLATE_NAME} file"
        return 1
    fi

    TEMPLATE_TEXT="$(cat "${TEMPLATE_FILE}")"

    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    JSON="$(
        jq -n \
            --arg NAME "${TEMPLATE_NAME}" \
            --arg TEMPLATE "${TEMPLATE_TEXT}" \
            --argjson KIND "${PXEGRUB2_KIND_ID}" \
            '{
                provisioning_template: {
                    name: $NAME,
                    template: $TEMPLATE,
                    template_kind_id: $KIND
                }
            }'
    )"

    if [ -n "${TEMPLATE_ID}" ]
    then

        skip "${TEMPLATE_NAME} already exists. ID=${TEMPLATE_ID}"

        if api_put \
            "${API}/provisioning_templates/${TEMPLATE_ID}" \
            "${JSON}"
        then

            ok "${TEMPLATE_NAME} updated."

        else

            show_api_error
            record_failure "${TEMPLATE_NAME} update"
            return 1

        fi

    else

        info "Creating ${TEMPLATE_NAME}"

        if api_post \
            "${API}/provisioning_templates" \
            "${JSON}"
        then

            TEMPLATE_ID="$(
                echo "${API_BODY}" |
                jq -r '.id // empty'
            )"

            ok "${TEMPLATE_NAME} created. ID=${TEMPLATE_ID}"

        else

            if [ "${API_STATUS}" = "422" ]
            then

                TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

                if [ -n "${TEMPLATE_ID}" ]
                then
                    skip "${TEMPLATE_NAME} already exists. ID=${TEMPLATE_ID}"
                    return 0
                fi

            fi

            show_api_error
            record_failure "${TEMPLATE_NAME} creation"
            return 1

        fi

    fi
}

###############################################################################
# PXE TEMPLATE CREATION
###############################################################################

section "Creating / Verifying PXEGrub2 Templates"

if [ -n "${PXEGRUB2_KIND_ID}" ]
then

    create_or_update_template \
        "${CENTOS_RAID_TEMPLATE}" \
        "${TEMPLATE_DIR}/centos-raid.erb"

    create_or_update_template \
        "${CENTOS_SINGLE_TEMPLATE}" \
        "${TEMPLATE_DIR}/centos-singledisk.erb"

    create_or_update_template \
        "${ROCKY8_RAID_TEMPLATE}" \
        "${TEMPLATE_DIR}/rocky8-raid.erb"

    create_or_update_template \
        "${ROCKY8_SINGLE_TEMPLATE}" \
        "${TEMPLATE_DIR}/rocky8-singledisk.erb"

    create_or_update_template \
        "${ROCKY92_RAID_TEMPLATE}" \
        "${TEMPLATE_DIR}/rocky92-raid.erb"

    create_or_update_template \
        "${ROCKY92_SINGLE_TEMPLATE}" \
        "${TEMPLATE_DIR}/rocky92-singledisk.erb"

    create_or_update_template \
        "${ROCKY98_RAID_TEMPLATE}" \
        "${TEMPLATE_DIR}/rocky98-raid.erb"

    create_or_update_template \
        "${ROCKY98_SINGLE_TEMPLATE}" \
        "${TEMPLATE_DIR}/rocky98-singledisk.erb"

else

    warn "Skipping PXEGrub2 template creation because kind is unavailable."

fi

###############################################################################
# ASSOCIATE OS / TEMPLATE
###############################################################################

associate_os_template()
{
    local OS_NAME="$1"
    local TEMPLATE_NAME="$2"

    local OS_ID
    local TEMPLATE_ID
    local TEMPLATE_RESPONSE
    local EXISTING_IDS
    local NEW_IDS
    local JSON

    subsection "OS Template Association"

    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then
        error "OS not found : ${OS_NAME}"
        record_failure "${OS_NAME} association"
        return 1
    fi

    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${TEMPLATE_NAME} association"
        return 1
    fi

    if ! api_get "${API}/provisioning_templates/${TEMPLATE_ID}"
    then
        show_api_error
        record_failure "${TEMPLATE_NAME} read"
        return 1
    fi

    TEMPLATE_RESPONSE="${API_BODY}"

    EXISTING_IDS="$(
        echo "${TEMPLATE_RESPONSE}" |
        jq -c '
            [
                .operatingsystems[]?.id
            ] |
            unique
        '
    )"

    NEW_IDS="$(
        echo "${EXISTING_IDS}" |
        jq -c \
            --argjson OS_ID "${OS_ID}" \
            '. + [$OS_ID] | unique'
    )"

    if echo "${EXISTING_IDS}" |
        jq -e \
            --argjson OS_ID "${OS_ID}" \
            'index($OS_ID) != null' >/dev/null
    then

        skip "${OS_NAME} already associated with ${TEMPLATE_NAME}."

        return 0

    fi

    JSON="$(
        jq -n \
            --argjson IDS "${NEW_IDS}" \
            '{
                provisioning_template: {
                    operatingsystem_ids: $IDS
                }
            }'
    )"

    if api_put \
        "${API}/provisioning_templates/${TEMPLATE_ID}" \
        "${JSON}"
    then

        ok "${OS_NAME} associated with ${TEMPLATE_NAME}."

    else

        show_api_error
        record_failure "${OS_NAME} association"
        return 1

    fi
}

###############################################################################
# ASSOCIATE ALL
###############################################################################

section "Associating PXEGrub2 Templates"

if [ -n "${PXEGRUB2_KIND_ID}" ]
then

    associate_os_template "${CENTOS_RAID_NAME}" "${CENTOS_RAID_TEMPLATE}"
    associate_os_template "${CENTOS_SINGLE_NAME}" "${CENTOS_SINGLE_TEMPLATE}"

    associate_os_template "${ROCKY8_RAID_NAME}" "${ROCKY8_RAID_TEMPLATE}"
    associate_os_template "${ROCKY8_SINGLE_NAME}" "${ROCKY8_SINGLE_TEMPLATE}"

    associate_os_template "${ROCKY92_RAID_NAME}" "${ROCKY92_RAID_TEMPLATE}"
    associate_os_template "${ROCKY92_SINGLE_NAME}" "${ROCKY92_SINGLE_TEMPLATE}"

    associate_os_template "${ROCKY98_RAID_NAME}" "${ROCKY98_RAID_TEMPLATE}"
    associate_os_template "${ROCKY98_SINGLE_NAME}" "${ROCKY98_SINGLE_TEMPLATE}"

else

    warn "Skipping PXEGrub2 associations because kind is unavailable."

fi

###############################################################################
# SET PXEGRUB2 DEFAULT
#
# IMPORTANT:
# If a PXEGrub2 default already exists for the OS, UPDATE it.
#
# This fixes:
#   template_kind_id has already been taken
#
###############################################################################

set_pxe_default()
{
    local OS_NAME="$1"
    local TEMPLATE_NAME="$2"

    local OS_ID
    local TEMPLATE_ID
    local DEFAULT_RESPONSE
    local EXISTING_ID
    local EXISTING_TEMPLATE_ID
    local JSON

    subsection "PXEGrub2 Default Template"

    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"
    echo "Kind ID  : ${PXEGRUB2_KIND_ID}"

    OS_ID="$(find_os_id "${OS_NAME}")"

    if [ -z "${OS_ID}" ]
    then
        error "OS not found : ${OS_NAME}"
        record_failure "${OS_NAME} default"
        return 1
    fi

    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found : ${TEMPLATE_NAME}"
        record_failure "${TEMPLATE_NAME} default"
        return 1
    fi

    if ! api_get \
        "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    then
        show_api_error
        record_failure "${OS_NAME} default lookup"
        return 1
    fi

    DEFAULT_RESPONSE="${API_BODY}"

    EXISTING_ID="$(
        echo "${DEFAULT_RESPONSE}" |
        jq -r \
            --argjson KIND "${PXEGRUB2_KIND_ID}" \
            '
            .results[]?
            | select(.template_kind_id == $KIND)
            | .id
            ' |
        head -n 1
    )"

    EXISTING_TEMPLATE_ID=""

    if [ -n "${EXISTING_ID}" ]
    then

        EXISTING_TEMPLATE_ID="$(
            echo "${DEFAULT_RESPONSE}" |
            jq -r \
                --argjson KIND "${PXEGRUB2_KIND_ID}" \
                --argjson TEMPLATE "${TEMPLATE_ID}" \
                '
                .results[]?
                | select(
                    .template_kind_id == $KIND
                )
                | .provisioning_template_id
                ' |
            head -n 1
        )"

        if [ "${EXISTING_TEMPLATE_ID}" = "${TEMPLATE_ID}" ]
        then

            skip "PXEGrub2 default already correct. ID=${EXISTING_ID}"
            return 0

        fi

        info "Existing PXEGrub2 default found. Updating ID=${EXISTING_ID}"

        JSON="$(
            jq -n \
                --argjson TEMPLATE "${TEMPLATE_ID}" \
                --argjson KIND "${PXEGRUB2_KIND_ID}" \
                '{
                    os_default_template: {
                        provisioning_template_id: $TEMPLATE,
                        template_kind_id: $KIND
                    }
                }'
        )"

        if api_put \
            "${API}/operatingsystems/${OS_ID}/os_default_templates/${EXISTING_ID}" \
            "${JSON}"
        then

            ok "PXEGrub2 default updated. ID=${EXISTING_ID}"

        else

            show_api_error
            record_failure "${OS_NAME} default update"
            return 1

        fi

        return 0

    fi

    ###########################################################################
    # No PXEGrub2 default exists
    ###########################################################################

    info "No PXEGrub2 default found. Creating one..."

    JSON="$(
        jq -n \
            --argjson TEMPLATE "${TEMPLATE_ID}" \
            --argjson KIND "${PXEGRUB2_KIND_ID}" \
            '{
                os_default_template: {
                    provisioning_template_id: $TEMPLATE,
                    template_kind_id: $KIND
                }
            }'
    )"

    if api_post \
        "${API}/operatingsystems/${OS_ID}/os_default_templates" \
        "${JSON}"
    then

        EXISTING_ID="$(
            echo "${API_BODY}" |
            jq -r '.id // empty'
        )"

        ok "PXEGrub2 default created. ID=${EXISTING_ID}"

    else

        #######################################################################
        # Race / already-created case
        #######################################################################

        if [ "${API_STATUS}" = "422" ]
        then

            if api_get \
                "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
            then

                EXISTING_ID="$(
                    echo "${API_BODY}" |
                    jq -r \
                        --argjson KIND "${PXEGRUB2_KIND_ID}" \
                        '
                        .results[]?
                        | select(.template_kind_id == $KIND)
                        | .id
                        ' |
                    head -n 1
                )"

                if [ -n "${EXISTING_ID}" ]
                then

                    info "PXEGrub2 default exists now. Updating ID=${EXISTING_ID}"

                    if api_put \
                        "${API}/operatingsystems/${OS_ID}/os_default_templates/${EXISTING_ID}" \
                        "${JSON}"
                    then

                        ok "PXEGrub2 default corrected. ID=${EXISTING_ID}"
                        return 0

                    fi

                fi

            fi

        fi

        show_api_error
        record_failure "${OS_NAME} default creation"
        return 1

    fi
}

###############################################################################
# DEFAULTS
###############################################################################

section "Setting PXEGrub2 Default Templates"

if [ -n "${PXEGRUB2_KIND_ID}" ]
then

    set_pxe_default "${CENTOS_RAID_NAME}" "${CENTOS_RAID_TEMPLATE}"
    set_pxe_default "${CENTOS_SINGLE_NAME}" "${CENTOS_SINGLE_TEMPLATE}"

    set_pxe_default "${ROCKY8_RAID_NAME}" "${ROCKY8_RAID_TEMPLATE}"
    set_pxe_default "${ROCKY8_SINGLE_NAME}" "${ROCKY8_SINGLE_TEMPLATE}"

    set_pxe_default "${ROCKY92_RAID_NAME}" "${ROCKY92_RAID_TEMPLATE}"
    set_pxe_default "${ROCKY92_SINGLE_NAME}" "${ROCKY92_SINGLE_TEMPLATE}"

    set_pxe_default "${ROCKY98_RAID_NAME}" "${ROCKY98_RAID_TEMPLATE}"
    set_pxe_default "${ROCKY98_SINGLE_NAME}" "${ROCKY98_SINGLE_TEMPLATE}"

else

    warn "Skipping PXEGrub2 defaults because kind is unavailable."

fi

###############################################################################
# FIND DOMAIN
###############################################################################

find_domain_id()
{
    local DOMAIN_NAME_ARG="$1"

    if ! api_get "${API}/domains?per_page=all"
    then
        return 1
    fi

    echo "${API_BODY}" |
    jq -r \
        --arg NAME "${DOMAIN_NAME_ARG}" \
        '
        .results[]?
        | select(.name == $NAME)
        | .id
        ' |
    head -n 1
}

###############################################################################
# FIND PROXY
###############################################################################

find_proxy_id()
{
    local PROXY_NAME_ARG="$1"
    local FEATURE_ARG="$2"

    if ! api_get "${API}/smart_proxies?per_page=all"
    then
        return 1
    fi

    echo "${API_BODY}" |
    jq -r \
        --arg NAME "${PROXY_NAME_ARG}" \
        --arg FEATURE "${FEATURE_ARG}" \
        '
        .results[]?
        | select(.name == $NAME)
        | select(
            (
                (.features // [])
                | map(.name)
                | index($FEATURE)
            ) != null
        )
        | .id
        ' |
    head -n 1
}

###############################################################################
# FALLBACK PROXY FIND
#
# Some Foreman API versions expose feature names differently.
###############################################################################

find_proxy_id_fallback()
{
    local PROXY_NAME_ARG="$1"

    if ! api_get "${API}/smart_proxies?per_page=all"
    then
        return 1
    fi

    echo "${API_BODY}" |
    jq -r \
        --arg NAME "${PROXY_NAME_ARG}" \
        '
        .results[]?
        | select(.name == $NAME)
        | .id
        ' |
    head -n 1
}

###############################################################################
# CREATE / UPDATE SUBNET
###############################################################################

create_subnet()
{
    local SUBNET_NAME_ARG="$1"
    local NETWORK_ARG="$2"
    local MASK_ARG="$3"
    local GATEWAY_ARG="$4"
    local DNS_ARG="$5"
    local TFTP_PROXY_ARG="$6"
    local DHCP_PROXY_ARG="$7"

    local SUBNET_ID=""
    local DOMAIN_ID=""
    local TFTP_ID=""
    local DHCP_ID=""
    local JSON

    subsection "Subnet : ${SUBNET_NAME_ARG}"

    echo "Network      : ${NETWORK_ARG}"
    echo "Mask         : ${MASK_ARG}"
    echo "Gateway      : ${GATEWAY_ARG}"
    echo "DNS          : ${DNS_ARG}"
    echo "TFTP Proxy   : ${TFTP_PROXY_ARG}"
    echo "DHCP Proxy   : ${DHCP_PROXY_ARG}"

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
    # TFTP
    ###########################################################################

    TFTP_ID="$(find_proxy_id "${TFTP_PROXY_ARG}" "TFTP")"

    if [ -z "${TFTP_ID}" ]
    then
        TFTP_ID="$(find_proxy_id_fallback "${TFTP_PROXY_ARG}")"
    fi

    if [ -n "${TFTP_ID}" ]
    then
        ok "TFTP proxy found : ${TFTP_PROXY_ARG} ID=${TFTP_ID}"
    else
        error "TFTP proxy not found : ${TFTP_PROXY_ARG}"
        record_failure "${SUBNET_NAME_ARG} TFTP"
        return 1
    fi

    ###########################################################################
    # DHCP
    ###########################################################################

    DHCP_ID="$(find_proxy_id "${DHCP_PROXY_ARG}" "DHCP")"

    if [ -z "${DHCP_ID}" ]
    then
        DHCP_ID="$(find_proxy_id_fallback "${DHCP_PROXY_ARG}")"
    fi

    if [ -n "${DHCP_ID}" ]
    then
        ok "DHCP proxy found : ${DHCP_PROXY_ARG} ID=${DHCP_ID}"
    else
        error "DHCP proxy not found : ${DHCP_PROXY_ARG}"
        record_failure "${SUBNET_NAME_ARG} DHCP"
        return 1
    fi

    ###########################################################################
    # FIND EXISTING SUBNET
    ###########################################################################

    if ! api_get "${API}/subnets?per_page=all"
    then
        show_api_error
        record_failure "${SUBNET_NAME_ARG} lookup"
        return 1
    fi

    SUBNET_ID="$(
        echo "${API_BODY}" |
        jq -r \
            --arg NAME "${SUBNET_NAME_ARG}" \
            '
            .results[]?
            | select(.name == $NAME)
            | .id
            ' |
        head -n 1
    )"

    ###########################################################################
    # PAYLOAD
    ###########################################################################

    JSON="$(
        jq -n \
            --arg NAME "${SUBNET_NAME_ARG}" \
            --arg NETWORK "${NETWORK_ARG}" \
            --arg MASK "${MASK_ARG}" \
            --arg GATEWAY "${GATEWAY_ARG}" \
            --arg DNS "${DNS_ARG}" \
            --argjson DOMAIN "${DOMAIN_ID:-null}" \
            --argjson TFTP "${TFTP_ID:-null}" \
            --argjson DHCP "${DHCP_ID:-null}" \
            '{
                subnet: {
                    name: $NAME,
                    network_type: "IPv4",
                    network: $NETWORK,
                    mask: $MASK,
                    gateway: $GATEWAY,
                    dns_primary: $DNS,
                    boot_mode: "DHCP",
                    ipam: "DHCP",
                    domain_ids:
                        (if $DOMAIN == null then [] else [$DOMAIN] end),
                    tftp_id: $TFTP,
                    dhcp_id: $DHCP
                }
            }'
    )"

    ###########################################################################
    # UPDATE EXISTING
    ###########################################################################

    if [ -n "${SUBNET_ID}" ]
    then

        skip "${SUBNET_NAME_ARG} already exists. ID=${SUBNET_ID}"

        if api_put \
            "${API}/subnets/${SUBNET_ID}" \
            "${JSON}"
        then

            ok "${SUBNET_NAME_ARG} updated."

        else

            show_api_error
            record_failure "${SUBNET_NAME_ARG} update"
            return 1

        fi

        return 0

    fi

    ###########################################################################
    # CREATE
    ###########################################################################

    info "Creating ${SUBNET_NAME_ARG}"

    if api_post \
        "${API}/subnets" \
        "${JSON}"
    then

        SUBNET_ID="$(
            echo "${API_BODY}" |
            jq -r '.id // empty'
        )"

        ok "${SUBNET_NAME_ARG} created. ID=${SUBNET_ID}"

    else

        #######################################################################
        # If another process created it, re-read and update.
        #######################################################################

        if [ "${API_STATUS}" = "422" ]
        then

            if api_get "${API}/subnets?per_page=all"
            then

                SUBNET_ID="$(
                    echo "${API_BODY}" |
                    jq -r \
                        --arg NAME "${SUBNET_NAME_ARG}" \
                        '
                        .results[]?
                        | select(.name == $NAME)
                        | .id
                        ' |
                    head -n 1
                )"

                if [ -n "${SUBNET_ID}" ]
                then

                    skip "${SUBNET_NAME_ARG} already exists. ID=${SUBNET_ID}"

                    if api_put \
                        "${API}/subnets/${SUBNET_ID}" \
                        "${JSON}"
                    then

                        ok "${SUBNET_NAME_ARG} updated."
                        return 0

                    fi

                fi

            fi

        fi

        show_api_error
        record_failure "${SUBNET_NAME_ARG} creation"
        return 1

    fi
}

###############################################################################
# SUBNETS
###############################################################################

section "Creating / Verifying PXE Subnets"

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

section "PXE Subnet Verification"

if api_get "${API}/subnets?per_page=all"
then

    echo "${API_BODY}" |
    jq -r '
        .results[]?
        | [
            .id,
            .name,
            (.network_address // .network // ""),
            (.mask // ""),
            (.tftp_name // "-"),
            (.dhcp_name // "-")
        ]
        | @tsv
    '

else

    show_api_error
    record_failure "PXE Subnet Verification"

fi

###############################################################################
# PXE TEMPLATE VERIFICATION
###############################################################################

section "PXEGrub2 Template Verification"

if api_get "${API}/provisioning_templates?per_page=all"
then

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

        TEMPLATE_ID="$(
            echo "${API_BODY}" |
            jq -r \
                --arg NAME "${TEMPLATE_NAME}" \
                '
                .results[]?
                | select(.name == $NAME)
                | .id
                ' |
            head -n 1
        )"

        TEMPLATE_KIND="$(
            echo "${API_BODY}" |
            jq -r \
                --arg NAME "${TEMPLATE_NAME}" \
                '
                .results[]?
                | select(.name == $NAME)
                | .template_kind_name
                ' |
            head -n 1
        )"

        TEMPLATE_KIND_VALUE="$(
            echo "${API_BODY}" |
            jq -r \
                --arg NAME "${TEMPLATE_NAME}" \
                '
                .results[]?
                | select(.name == $NAME)
                | .template_kind_id
                ' |
            head -n 1
        )"

        if [ -n "${TEMPLATE_ID}" ] &&
           [ "${TEMPLATE_KIND}" = "PXEGrub2" ] &&
           [ "${TEMPLATE_KIND_VALUE}" = "${PXEGRUB2_KIND_ID}" ]
        then

            ok "${TEMPLATE_NAME} | ID=${TEMPLATE_ID} | kind=${TEMPLATE_KIND} | kind_id=${TEMPLATE_KIND_VALUE}"

        else

            error "${TEMPLATE_NAME} verification failed."
            record_failure "${TEMPLATE_NAME} verification"

        fi

    done

else

    show_api_error
    record_failure "PXEGrub2 Template Verification"

fi

###############################################################################
# OS TEMPLATE ASSOCIATION VERIFICATION
###############################################################################

section "OS Template Mapping Verification"

verify_os_template()
{
    local OS_NAME_ARG="$1"
    local TEMPLATE_NAME_ARG="$2"

    local OS_ID
    local TEMPLATE_ID
    local MATCH

    OS_ID="$(find_os_id "${OS_NAME_ARG}")"
    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME_ARG}")"

    if [ -z "${OS_ID}" ]
    then
        error "${OS_NAME_ARG} OS not found."
        record_failure "${OS_NAME_ARG} mapping"
        return
    fi

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "${TEMPLATE_NAME_ARG} template not found."
        record_failure "${TEMPLATE_NAME_ARG} mapping"
        return
    fi

    if ! api_get \
        "${API}/operatingsystems/${OS_ID}/provisioning_templates?per_page=all"
    then
        show_api_error
        record_failure "${OS_NAME_ARG} mapping"
        return
    fi

    MATCH="$(
        echo "${API_BODY}" |
        jq -r \
            --argjson ID "${TEMPLATE_ID}" \
            '
            .results[]?
            | select(.id == $ID)
            | .name
            ' |
        head -n 1
    )"

    if [ "${MATCH}" = "${TEMPLATE_NAME_ARG}" ]
    then

        ok "${OS_NAME_ARG} -> ${TEMPLATE_NAME_ARG}"

    else

        error "${OS_NAME_ARG} -> ${TEMPLATE_NAME_ARG}"
        record_failure "${OS_NAME_ARG} mapping"

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
# DEFAULT VERIFICATION
###############################################################################

section "PXEGrub2 Default Verification"

verify_pxe_default()
{
    local OS_NAME_ARG="$1"
    local TEMPLATE_NAME_ARG="$2"

    local OS_ID
    local TEMPLATE_ID
    local MATCH

    OS_ID="$(find_os_id "${OS_NAME_ARG}")"
    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME_ARG}")"

    if [ -z "${OS_ID}" ] || [ -z "${TEMPLATE_ID}" ]
    then
        error "${OS_NAME_ARG} default verification failed."
        record_failure "${OS_NAME_ARG} default verification"
        return
    fi

    if ! api_get \
        "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    then
        show_api_error
        record_failure "${OS_NAME_ARG} default verification"
        return
    fi

    MATCH="$(
        echo "${API_BODY}" |
        jq -r \
            --argjson KIND "${PXEGRUB2_KIND_ID}" \
            --argjson TEMPLATE "${TEMPLATE_ID}" \
            '
            .results[]?
            | select(
                .template_kind_id == $KIND
                and
                .provisioning_template_id == $TEMPLATE
            )
            | .id
            ' |
        head -n 1
    )"

    if [ -n "${MATCH}" ]
    then

        ok "${OS_NAME_ARG} PXEGrub2 default: ID=${MATCH} template=${TEMPLATE_ID} kind=${PXEGRUB2_KIND_ID}"

    else

        error "${OS_NAME_ARG} PXEGrub2 default incorrect/missing."
        record_failure "${OS_NAME_ARG} default verification"

    fi
}

verify_pxe_default "${CENTOS_RAID_NAME}" "${CENTOS_RAID_TEMPLATE}"
verify_pxe_default "${CENTOS_SINGLE_NAME}" "${CENTOS_SINGLE_TEMPLATE}"

verify_pxe_default "${ROCKY8_RAID_NAME}" "${ROCKY8_RAID_TEMPLATE}"
verify_pxe_default "${ROCKY8_SINGLE_NAME}" "${ROCKY8_SINGLE_TEMPLATE}"

verify_pxe_default "${ROCKY92_RAID_NAME}" "${ROCKY92_RAID_TEMPLATE}"
verify_pxe_default "${ROCKY92_SINGLE_NAME}" "${ROCKY92_SINGLE_TEMPLATE}"

verify_pxe_default "${ROCKY98_RAID_NAME}" "${ROCKY98_RAID_TEMPLATE}"
verify_pxe_default "${ROCKY98_SINGLE_NAME}" "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# FINAL OS VERIFICATION
###############################################################################

section "Final Operating System Verification"

verify_os_final()
{
    local OS_NAME_ARG="$1"
    local OS_ID

    OS_ID="$(find_os_id "${OS_NAME_ARG}")"

    if [ -z "${OS_ID}" ]
    then
        error "OS not found : ${OS_NAME_ARG}"
        record_failure "${OS_NAME_ARG} final verification"
        return
    fi

    if ! api_get "${API}/operatingsystems/${OS_ID}"
    then
        show_api_error
        record_failure "${OS_NAME_ARG} final verification"
        return
    fi

    echo
    echo "------------------------------------------------------------"
    echo "OS : ${OS_NAME_ARG}"
    echo "ID : ${OS_ID}"
    echo "------------------------------------------------------------"

    echo "${API_BODY}" |
    jq -r '
        "Name          : \(.name)",
        "Title         : \(.title // "")",
        "Major         : \(.major // "")",
        "Minor         : \(.minor // "")",
        "Family        : \(.family // "")",
        "Architecture  : ((.architectures // []) | map(.name) | join(", "))",
        "Media         : ((.media // []) | map(.name) | join(", "))",
        "Ptable        : ((.ptables // []) | map(.name) | join(", "))",
        "Templates     : ((.provisioning_templates // []) | map(.name) | join(", "))"
    '
}

verify_os_final "${CENTOS_RAID_NAME}"
verify_os_final "${CENTOS_SINGLE_NAME}"

verify_os_final "${ROCKY8_RAID_NAME}"
verify_os_final "${ROCKY8_SINGLE_NAME}"

verify_os_final "${ROCKY92_RAID_NAME}"
verify_os_final "${ROCKY92_SINGLE_NAME}"

verify_os_final "${ROCKY98_RAID_NAME}"
verify_os_final "${ROCKY98_SINGLE_NAME}"

###############################################################################
# GENERATED FILES
###############################################################################

section "Generated PXE Files"

ls -l "${TEMPLATE_DIR}"/*.erb

###############################################################################
# FINAL SUMMARY
###############################################################################

section "01 - Foreman PXE Bootstrap API Completed"

if [ ${#FAILURES[@]} -eq 0 ]
then

    ok "Completed successfully with 0 failures."

else

    error "Completed with ${#FAILURES[@]} failure(s)."

    echo
    echo "Failures:"
    echo "------------------------------------------------------------"

    for FAILURE in "${FAILURES[@]}"
    do
        error "${FAILURE}"
    done

fi

###############################################################################
# AUTHENTICATION INFORMATION
###############################################################################

echo
echo "============================================================"
echo "Authentication"
echo "============================================================"
echo "Method        : Foreman REST API"
echo "Username      : ${FOREMAN_USER}"
echo "Authentication: Personal Access Token"
echo "Hammer        : NOT USED"
echo "curl          : USED"
echo "API           : ${API}"
echo "============================================================"

###############################################################################
# MANUAL VERIFICATION
###############################################################################

echo
echo "Manual API Verification:"
echo "------------------------------------------------------------"

echo
echo "1. Foreman status:"
echo
echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/status' | jq"

echo
echo "2. PXEGrub2 templates:"
echo
echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/provisioning_templates?per_page=all' | \\"
echo "  jq -r '.results[]? | select(.template_kind_name==\"PXEGrub2\") | [.id,.name,.template_kind_id,.template_kind_name] | @tsv'"

echo
echo "3. OS PXEGrub2 mappings:"
echo
echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/operatingsystems/2/provisioning_templates?per_page=all' | \\"
echo "  jq -r '.results[]? | select(.template_kind_name==\"PXEGrub2\") | [.id,.name,.template_kind_id] | @tsv'"

echo
echo "4. OS 2 PXEGrub2 defaults:"
echo
echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/operatingsystems/2/os_default_templates?per_page=all' | jq"

echo
echo "5. PXE subnets:"
echo
echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/subnets?per_page=all' | jq"

###############################################################################
# EXIT
###############################################################################

if [ ${#FAILURES[@]} -eq 0 ]
then
    exit 0
else
    exit 1
fi
