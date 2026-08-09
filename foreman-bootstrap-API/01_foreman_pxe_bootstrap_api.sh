#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap - REST API
#
# Foreman 3.2.1
# REST API only
# NO HAMMER
#
# Existing resources are preserved.
#
# Creates / verifies:
#   1. Installation Media
#   2. Operating Systems
#   3. PXEGrub2 Templates
#   4. OS -> PXEGrub2 Template associations
#   5. PXEGrub2 Default Templates
#   6. PXE Subnets
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
NC='\033[0m'

###############################################################################
# OUTPUT FUNCTIONS
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

API="${FOREMAN_URL}/api"

CURL_SSL="-k"

###############################################################################
# REQUIRED COMMANDS
###############################################################################

section "Dependency Check"

for CMD in curl jq cat head grep awk sed mkdir mktemp
do
    if command -v "${CMD}" >/dev/null 2>&1
    then
        ok "${CMD} found: $(command -v "${CMD}")"
    else
        error "${CMD} not found."
        record_failure "Dependency ${CMD}"
    fi
done

if [ ${#FAILURES[@]} -ne 0 ]
then
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
# API VARIABLES
###############################################################################

API_STATUS=""
API_BODY=""
API_METHOD=""
API_URL=""

###############################################################################
# JSON VALIDATION
###############################################################################

is_json()
{
    echo "$1" | jq -e . >/dev/null 2>&1
}

###############################################################################
# API REQUEST
#
# --globoff is important because Foreman URLs contain [] in some requests.
###############################################################################

api_request()
{
    local METHOD="$1"
    local URL="$2"
    local DATA="${3:-}"

    local BODY_FILE
    local HEADER_FILE
    local CURL_RC

    API_METHOD="${METHOD}"
    API_URL="${URL}"
    API_STATUS=""
    API_BODY=""

    BODY_FILE="$(mktemp)"
    HEADER_FILE="$(mktemp)"

    if [ -n "${DATA}" ]
    then
        curl \
            --globoff \
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
            "${URL}" > "${BODY_FILE}.code" 2>/dev/null

        CURL_RC=$?
    else
        curl \
            --globoff \
            -sS \
            ${CURL_SSL} \
            --request "${METHOD}" \
            --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
            --header "Accept: application/json,version=2" \
            --header "Content-Type: application/json" \
            --output "${BODY_FILE}" \
            --dump-header "${HEADER_FILE}" \
            --write-out "%{http_code}" \
            "${URL}" > "${BODY_FILE}.code" 2>/dev/null

        CURL_RC=$?
    fi

    if [ ${CURL_RC} -ne 0 ]
    then
        API_STATUS=""
        API_BODY="$(cat "${BODY_FILE}" 2>/dev/null)"
        rm -f "${BODY_FILE}" "${HEADER_FILE}" "${BODY_FILE}.code"
        return 1
    fi

    API_STATUS="$(cat "${BODY_FILE}.code")"
    API_BODY="$(cat "${BODY_FILE}")"

    rm -f "${BODY_FILE}" "${HEADER_FILE}" "${BODY_FILE}.code"

    [[ "${API_STATUS}" =~ ^2[0-9][0-9]$ ]]
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
# FOREMAN API TEST
###############################################################################

section "01 - Foreman PXE Bootstrap - REST API"

section "Foreman API Authentication Test"

info "Testing Foreman REST API..."

if api_request GET "${API}/status"
then

    ok "Foreman API authentication successful."

    FOREMAN_VERSION="$(
        echo "${API_BODY}" |
        jq -r '.version // empty'
    )"

    API_VERSION="$(
        echo "${API_BODY}" |
        jq -r '.api_version // empty'
    )"

    echo "Foreman Version : ${FOREMAN_VERSION}"
    echo "API Version     : ${API_VERSION}"
    echo "API Status      : ${API_STATUS}"

else

    show_api_error
    exit 1

fi

###############################################################################
# MEDIA CONFIGURATION
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
# OS CONFIGURATION
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
# TEMPLATE CONFIGURATION
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
# SUBNET CONFIGURATION
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
# MEDIA LOOKUP
###############################################################################

find_media_id()
{
    local NAME="$1"

    api_request GET "${API}/media?per_page=all" || return 1

    echo "${API_BODY}" |
    jq -r \
        --arg NAME "${NAME}" \
        '.results[]? | select(.name == $NAME) | .id' |
    head -1
}

###############################################################################
# CREATE / VERIFY MEDIA
###############################################################################

create_media()
{
    local NAME="$1"
    local PATH="$2"

    local ID
    local JSON

    subsection "Installation Media : ${NAME}"

    ID="$(find_media_id "${NAME}")"

    if [ -n "${ID}" ]
    then
        skip "${NAME} already exists. ID=${ID}"
        return 0
    fi

    JSON="$(
        jq -n \
            --arg NAME "${NAME}" \
            --arg PATH "${PATH}" \
            '{
                medium: {
                    name: $NAME,
                    path: $PATH,
                    os_family: "Redhat"
                }
            }'
    )"

    info "Creating ${NAME}"

    if api_request POST "${API}/media" "${JSON}"
    then

        ID="$(echo "${API_BODY}" | jq -r '.id // empty')"
        ok "${NAME} created. ID=${ID}"

    else

        if [ "${API_STATUS}" = "422" ]
        then
            ID="$(find_media_id "${NAME}")"

            if [ -n "${ID}" ]
            then
                skip "${NAME} already exists. ID=${ID}"
                return 0
            fi
        fi

        show_api_error
        record_failure "${NAME} creation"

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

if api_request GET "${API}/media?per_page=all"
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
    record_failure "Media verification"

fi

###############################################################################
# ARCHITECTURE
###############################################################################

section "Finding Architecture"

ARCH_ID=""

if api_request GET "${API}/architectures?per_page=all"
then

    ARCH_ID="$(
        echo "${API_BODY}" |
        jq -r '
            .results[]?
            | select(.name == "x86_64")
            | .id
        ' |
        head -1
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
# PTABLE
###############################################################################

section "Finding Partition Table"

PTABLE_ID=""

if api_request GET "${API}/ptables?per_page=all"
then

    PTABLE_ID="$(
        echo "${API_BODY}" |
        jq -r '
            .results[]?
            | select(.name == "Kickstart default")
            | .id
        ' |
        head -1
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
# OS LOOKUP
###############################################################################

find_os_id()
{
    local NAME="$1"

    api_request GET "${API}/operatingsystems?per_page=all" || return 1

    echo "${API_BODY}" |
    jq -r \
        --arg NAME "${NAME}" \
        '.results[]? | select(.name == $NAME) | .id' |
    head -1
}

###############################################################################
# CREATE / VERIFY OS
###############################################################################

create_os()
{
    local NAME="$1"
    local MAJOR="$2"
    local MINOR="$3"
    local MEDIA_NAME="$4"

    local ID
    local MEDIA_ID
    local JSON

    subsection "Operating System : ${NAME}"

    ID="$(find_os_id "${NAME}")"

    if [ -n "${ID}" ]
    then
        skip "${NAME} already exists. ID=${ID}"
        return 0
    fi

    MEDIA_ID="$(find_media_id "${MEDIA_NAME}")"

    if [ -z "${MEDIA_ID}" ]
    then
        error "Media not found : ${MEDIA_NAME}"
        record_failure "${NAME} media"
        return 1
    fi

    JSON="$(
        jq -n \
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

    info "Creating ${NAME}"

    if api_request POST "${API}/operatingsystems" "${JSON}"
    then

        ID="$(echo "${API_BODY}" | jq -r '.id // empty')"
        ok "${NAME} created. ID=${ID}"

    else

        if [ "${API_STATUS}" = "422" ]
        then
            ID="$(find_os_id "${NAME}")"

            if [ -n "${ID}" ]
            then
                skip "${NAME} already exists. ID=${ID}"
                return 0
            fi
        fi

        show_api_error
        record_failure "${NAME} creation"

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

if api_request GET "${API}/operatingsystems?per_page=all"
then

    printf "%-5s %-35s %-7s %-7s %-10s\n" \
        "ID" "NAME" "MAJOR" "MINOR" "FAMILY"

    echo "${API_BODY}" |
    jq -r '
        .results[]? |
        [
            .id,
            .name,
            (.major // ""),
            (.minor // ""),
            (.family // "")
        ] |
        @tsv
    '

else

    show_api_error
    record_failure "OS verification"

fi

###############################################################################
# PXE TEMPLATE DIRECTORY
###############################################################################

TEMPLATE_DIR="/tmp/foreman-pxe-bootstrap"

mkdir -p "${TEMPLATE_DIR}"

###############################################################################
# GENERATE PXEGRUB2 FILES
#
# IMPORTANT:
# All heredocs are complete and quoted.
# Foreman ERB syntax is therefore NOT interpreted by Bash.
###############################################################################

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

###############################################################################
# VERIFY TEMPLATE FILES
###############################################################################

TEMPLATE_COUNT=0

for FILE in \
    centos-raid.erb \
    centos-singledisk.erb \
    rocky8-raid.erb \
    rocky8-singledisk.erb \
    rocky92-raid.erb \
    rocky92-singledisk.erb \
    rocky98-raid.erb \
    rocky98-singledisk.erb
do

    if [ -s "${TEMPLATE_DIR}/${FILE}" ]
    then
        TEMPLATE_COUNT=$((TEMPLATE_COUNT + 1))
    else
        error "Template file missing/empty: ${FILE}"
        record_failure "Generated ${FILE}"
    fi

done

if [ "${TEMPLATE_COUNT}" -eq 8 ]
then
    ok "All 8 PXEGrub2 template files generated."
else
    error "Only ${TEMPLATE_COUNT}/8 PXEGrub2 files generated."
fi

ls -l "${TEMPLATE_DIR}"/*.erb

###############################################################################
# FIND PXEGRUB2 KIND
###############################################################################

section "Finding Existing PXEGrub2 Template Kind"

PXEGRUB2_KIND_ID=""

if api_request GET "${API}/provisioning_templates?per_page=all"
then

    PXEGRUB2_KIND_ID="$(
        echo "${API_BODY}" |
        jq -r '
            .results[]?
            | select(.template_kind_name == "PXEGrub2")
            | .template_kind_id
        ' |
        head -1
    "

    if [ -z "${PXEGRUB2_KIND_ID}" ]
    then
        PXEGRUB2_KIND_ID="$(
            echo "${API_BODY}" |
            jq -r '
                .results[]?
                | select(.name | startswith("PXEGrub2 "))
                | .template_kind_id
            ' |
            head -1
        )"
    fi

fi

if [ -n "${PXEGRUB2_KIND_ID}" ]
then
    ok "PXEGrub2 template kind found. ID=${PXEGRUB2_KIND_ID}"
else
    error "PXEGrub2 template kind not found."
    record_failure "PXEGrub2 template kind"
fi

###############################################################################
# FIND PROVISIONING TEMPLATE
###############################################################################

find_template_id()
{
    local NAME="$1"

    api_request GET "${API}/provisioning_templates?per_page=all" || return 1

    echo "${API_BODY}" |
    jq -r \
        --arg NAME "${NAME}" \
        '.results[]? | select(.name == $NAME) | .id' |
    head -1
}

###############################################################################
# CREATE / VERIFY PXEGRUB2 TEMPLATE
###############################################################################

create_template()
{
    local NAME="$1"
    local FILE="$2"

    local ID
    local TEXT
    local JSON

    subsection "PXEGrub2 Template : ${NAME}"

    ID="$(find_template_id "${NAME}")"

    if [ -n "${ID}" ]
    then
        skip "${NAME} already exists. ID=${ID}"
        return 0
    fi

    if [ ! -s "${FILE}" ]
    then
        error "Template file missing: ${FILE}"
        record_failure "${NAME} file"
        return 1
    fi

    TEXT="$(cat "${FILE}")"

    JSON="$(
        jq -n \
            --arg NAME "${NAME}" \
            --arg TEXT "${TEXT}" \
            --argjson KIND "${PXEGRUB2_KIND_ID}" \
            '{
                provisioning_template: {
                    name: $NAME,
                    template: $TEXT,
                    template_kind_id: $KIND
                }
            }'
    )"

    info "Creating ${NAME}"

    if api_request POST "${API}/provisioning_templates" "${JSON}"
    then

        ID="$(echo "${API_BODY}" | jq -r '.id // empty')"
        ok "${NAME} created. ID=${ID}"

    else

        if [ "${API_STATUS}" = "422" ]
        then
            ID="$(find_template_id "${NAME}")"

            if [ -n "${ID}" ]
            then
                skip "${NAME} already exists. ID=${ID}"
                return 0
            fi
        fi

        show_api_error
        record_failure "${NAME} creation"

    fi
}

###############################################################################
# CREATE PXEGRUB2 TEMPLATES
###############################################################################

section "Creating / Verifying PXEGrub2 Templates"

if [ -n "${PXEGRUB2_KIND_ID}" ]
then

    create_template \
        "${CENTOS_RAID_TEMPLATE}" \
        "${TEMPLATE_DIR}/centos-raid.erb"

    create_template \
        "${CENTOS_SINGLE_TEMPLATE}" \
        "${TEMPLATE_DIR}/centos-singledisk.erb"

    create_template \
        "${ROCKY8_RAID_TEMPLATE}" \
        "${TEMPLATE_DIR}/rocky8-raid.erb"

    create_template \
        "${ROCKY8_SINGLE_TEMPLATE}" \
        "${TEMPLATE_DIR}/rocky8-singledisk.erb"

    create_template \
        "${ROCKY92_RAID_TEMPLATE}" \
        "${TEMPLATE_DIR}/rocky92-raid.erb"

    create_template \
        "${ROCKY92_SINGLE_TEMPLATE}" \
        "${TEMPLATE_DIR}/rocky92-singledisk.erb"

    create_template \
        "${ROCKY98_RAID_TEMPLATE}" \
        "${TEMPLATE_DIR}/rocky98-raid.erb"

    create_template \
        "${ROCKY98_SINGLE_TEMPLATE}" \
        "${TEMPLATE_DIR}/rocky98-singledisk.erb"

else

    warn "Skipping PXEGrub2 template creation because kind is unavailable."

fi

###############################################################################
# OS -> TEMPLATE ASSOCIATION
###############################################################################

associate_template()
{
    local OS_NAME="$1"
    local TEMPLATE_NAME="$2"

    local OS_ID
    local TEMPLATE_ID
    local JSON

    subsection "Associating PXEGrub2 Template"

    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"

    OS_ID="$(find_os_id "${OS_NAME}")"
    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -z "${OS_ID}" ]
    then
        error "OS not found: ${OS_NAME}"
        record_failure "${OS_NAME} association"
        return 1
    fi

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found: ${TEMPLATE_NAME}"
        record_failure "${TEMPLATE_NAME} association"
        return 1
    fi

    ###########################################################################
    # Check existing association
    ###########################################################################

    if api_request GET \
        "${API}/operatingsystems/${OS_ID}/provisioning_templates?per_page=all"
    then

        if echo "${API_BODY}" |
            jq -e \
                --argjson ID "${TEMPLATE_ID}" \
                '.results[]? | select(.id == $ID)' >/dev/null
        then

            skip "${OS_NAME} already associated with ${TEMPLATE_NAME}"
            return 0

        fi

    fi

    ###########################################################################
    # Add association
    ###########################################################################

    JSON="$(
        jq -n \
            --argjson TEMPLATE "${TEMPLATE_ID}" \
            '{
                provisioning_template_id: $TEMPLATE
            }'
    )"

    info "Adding association..."

    if api_request POST \
        "${API}/operatingsystems/${OS_ID}/provisioning_templates" \
        "${JSON}"
    then

        ok "${OS_NAME} -> ${TEMPLATE_NAME}"

    else

        #######################################################################
        # 422 can mean it was already associated.
        #######################################################################

        if [ "${API_STATUS}" = "422" ]
        then

            if api_request GET \
                "${API}/operatingsystems/${OS_ID}/provisioning_templates?per_page=all"
            then

                if echo "${API_BODY}" |
                    jq -e \
                        --argjson ID "${TEMPLATE_ID}" \
                        '.results[]? | select(.id == $ID)' >/dev/null
                then

                    skip "${OS_NAME} already associated with ${TEMPLATE_NAME}"
                    return 0

                fi

            fi

        fi

        show_api_error
        record_failure "${OS_NAME} association"

    fi
}

###############################################################################
# ASSOCIATIONS
###############################################################################

section "Associating PXEGrub2 Templates"

if [ -n "${PXEGRUB2_KIND_ID}" ]
then

    associate_template "${CENTOS_RAID_NAME}" "${CENTOS_RAID_TEMPLATE}"
    associate_template "${CENTOS_SINGLE_NAME}" "${CENTOS_SINGLE_TEMPLATE}"

    associate_template "${ROCKY8_RAID_NAME}" "${ROCKY8_RAID_TEMPLATE}"
    associate_template "${ROCKY8_SINGLE_NAME}" "${ROCKY8_SINGLE_TEMPLATE}"

    associate_template "${ROCKY92_RAID_NAME}" "${ROCKY92_RAID_TEMPLATE}"
    associate_template "${ROCKY92_SINGLE_NAME}" "${ROCKY92_SINGLE_TEMPLATE}"

    associate_template "${ROCKY98_RAID_NAME}" "${ROCKY98_RAID_TEMPLATE}"
    associate_template "${ROCKY98_SINGLE_NAME}" "${ROCKY98_SINGLE_TEMPLATE}"

else

    warn "Skipping associations because PXEGrub2 kind is unavailable."

fi

###############################################################################
# SET PXEGRUB2 DEFAULT
###############################################################################

set_default_template()
{
    local OS_NAME="$1"
    local TEMPLATE_NAME="$2"

    local OS_ID
    local TEMPLATE_ID
    local EXISTING_ID
    local EXISTING_TEMPLATE_ID
    local JSON

    subsection "PXEGrub2 Default"

    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE_NAME}"
    echo "Kind ID  : ${PXEGRUB2_KIND_ID}"

    OS_ID="$(find_os_id "${OS_NAME}")"
    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -z "${OS_ID}" ]
    then
        error "OS not found: ${OS_NAME}"
        record_failure "${OS_NAME} default"
        return 1
    fi

    if [ -z "${TEMPLATE_ID}" ]
    then
        error "Template not found: ${TEMPLATE_NAME}"
        record_failure "${TEMPLATE_NAME} default"
        return 1
    fi

    ###########################################################################
    # Get existing defaults
    ###########################################################################

    if ! api_request GET \
        "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    then
        show_api_error
        record_failure "${OS_NAME} default lookup"
        return 1
    fi

    ###########################################################################
    # Existing PXEGrub2 default
    ###########################################################################

    EXISTING_ID="$(
        echo "${API_BODY}" |
        jq -r \
            --argjson KIND "${PXEGRUB2_KIND_ID}" \
            '
            .results[]?
            | select(.template_kind_id == $KIND)
            | .id
            ' |
        head -1
    )"

    if [ -n "${EXISTING_ID}" ]
    then

        EXISTING_TEMPLATE_ID="$(
            echo "${API_BODY}" |
            jq -r \
                --argjson KIND "${PXEGRUB2_KIND_ID}" \
                '
                .results[]?
                | select(.template_kind_id == $KIND)
                | .provisioning_template_id
                ' |
            head -1
        )"

        if [ "${EXISTING_TEMPLATE_ID}" = "${TEMPLATE_ID}" ]
        then

            skip "${OS_NAME} PXEGrub2 default already correct. ID=${EXISTING_ID}"
            return 0

        fi

        #######################################################################
        # Existing default is wrong -> update it.
        #######################################################################

        info "Existing PXEGrub2 default found. ID=${EXISTING_ID}"
        info "Updating default template..."

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

        if api_request PUT \
            "${API}/operatingsystems/${OS_ID}/os_default_templates/${EXISTING_ID}" \
            "${JSON}"
        then

            ok "${OS_NAME} PXEGrub2 default updated. ID=${EXISTING_ID}"

        else

            show_api_error
            record_failure "${OS_NAME} default update"

        fi

        return 0

    fi

    ###########################################################################
    # No existing PXEGrub2 default -> create
    ###########################################################################

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

    info "Creating PXEGrub2 default..."

    if api_request POST \
        "${API}/operatingsystems/${OS_ID}/os_default_templates" \
        "${JSON}"
    then

        EXISTING_ID="$(echo "${API_BODY}" | jq -r '.id // empty')"
        ok "${OS_NAME} PXEGrub2 default created. ID=${EXISTING_ID}"

    else

        #######################################################################
        # If Foreman says template_kind_id is already taken, re-read.
        #######################################################################

        if [ "${API_STATUS}" = "422" ]
        then

            if api_request GET \
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
                    head -1
                )"

                if [ -n "${EXISTING_ID}" ]
                then

                    info "Existing PXEGrub2 default discovered. ID=${EXISTING_ID}"
                    info "Updating it instead of creating another."

                    if api_request PUT \
                        "${API}/operatingsystems/${OS_ID}/os_default_templates/${EXISTING_ID}" \
                        "${JSON}"
                    then

                        ok "${OS_NAME} PXEGrub2 default corrected. ID=${EXISTING_ID}"
                        return 0

                    fi

                fi

            fi

        fi

        show_api_error
        record_failure "${OS_NAME} default creation"

    fi
}

###############################################################################
# DEFAULT TEMPLATES
###############################################################################

section "Setting PXEGrub2 Default Templates"

if [ -n "${PXEGRUB2_KIND_ID}" ]
then

    set_default_template \
        "${CENTOS_RAID_NAME}" \
        "${CENTOS_RAID_TEMPLATE}"

    set_default_template \
        "${CENTOS_SINGLE_NAME}" \
        "${CENTOS_SINGLE_TEMPLATE}"

    set_default_template \
        "${ROCKY8_RAID_NAME}" \
        "${ROCKY8_RAID_TEMPLATE}"

    set_default_template \
        "${ROCKY8_SINGLE_NAME}" \
        "${ROCKY8_SINGLE_TEMPLATE}"

    set_default_template \
        "${ROCKY92_RAID_NAME}" \
        "${ROCKY92_RAID_TEMPLATE}"

    set_default_template \
        "${ROCKY92_SINGLE_NAME}" \
        "${ROCKY92_SINGLE_TEMPLATE}"

    set_default_template \
        "${ROCKY98_RAID_NAME}" \
        "${ROCKY98_RAID_TEMPLATE}"

    set_default_template \
        "${ROCKY98_SINGLE_NAME}" \
        "${ROCKY98_SINGLE_TEMPLATE}"

else

    warn "Skipping defaults because PXEGrub2 kind is unavailable."

fi

###############################################################################
# DOMAIN LOOKUP
###############################################################################

find_domain_id()
{
    local NAME="$1"

    api_request GET "${API}/domains?per_page=all" || return 1

    echo "${API_BODY}" |
    jq -r \
        --arg NAME "${NAME}" \
        '.results[]? | select(.name == $NAME) | .id' |
    head -1
}

###############################################################################
# SMART PROXY LOOKUP
###############################################################################

find_proxy_id()
{
    local NAME="$1"

    api_request GET "${API}/smart_proxies?per_page=all" || return 1

    echo "${API_BODY}" |
    jq -r \
        --arg NAME "${NAME}" \
        '.results[]? | select(.name == $NAME) | .id' |
    head -1
}

###############################################################################
# SUBNET LOOKUP
###############################################################################

find_subnet_id()
{
    local NAME="$1"

    api_request GET "${API}/subnets?per_page=all" || return 1

    echo "${API_BODY}" |
    jq -r \
        --arg NAME "${NAME}" \
        '.results[]? | select(.name == $NAME) | .id' |
    head -1
}

###############################################################################
# CREATE / VERIFY SUBNET
###############################################################################

create_subnet()
{
    local NAME="$1"
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

    subsection "Subnet : ${NAME}"

    echo "Network      : ${NETWORK}"
    echo "Mask         : ${MASK}"
    echo "Gateway      : ${GATEWAY}"
    echo "DNS          : ${DNS}"
    echo "TFTP Proxy   : ${TFTP_PROXY}"
    echo "DHCP Proxy   : ${DHCP_PROXY}"

    DOMAIN_ID="$(find_domain_id "${DOMAIN_NAME}")"

    if [ -n "${DOMAIN_ID}" ]
    then
        ok "Domain found : ${DOMAIN_NAME} ID=${DOMAIN_ID}"
    else
        warn "Domain not found : ${DOMAIN_NAME}"
    fi

    TFTP_ID="$(find_proxy_id "${TFTP_PROXY}")"

    if [ -n "${TFTP_ID}" ]
    then
        ok "TFTP proxy found : ${TFTP_PROXY} ID=${TFTP_ID}"
    else
        error "TFTP proxy not found : ${TFTP_PROXY}"
        record_failure "${NAME} TFTP proxy"
        return 1
    fi

    DHCP_ID="$(find_proxy_id "${DHCP_PROXY}")"

    if [ -n "${DHCP_ID}" ]
    then
        ok "DHCP proxy found : ${DHCP_PROXY} ID=${DHCP_ID}"
    else
        error "DHCP proxy not found : ${DHCP_PROXY}"
        record_failure "${NAME} DHCP proxy"
        return 1
    fi

    SUBNET_ID="$(find_subnet_id "${NAME}")"

    JSON="$(
        jq -n \
            --arg NAME "${NAME}" \
            --arg NETWORK "${NETWORK}" \
            --arg MASK "${MASK}" \
            --arg GATEWAY "${GATEWAY}" \
            --arg DNS "${DNS}" \
            --argjson DOMAIN "${DOMAIN_ID:-null}" \
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
                    domain_ids:
                        (if $DOMAIN == null then [] else [$DOMAIN] end),
                    tftp_id: $TFTP,
                    dhcp_id: $DHCP
                }
            }'
    )"

    if [ -n "${SUBNET_ID}" ]
    then

        skip "${NAME} already exists. ID=${SUBNET_ID}"

        if api_request PUT \
            "${API}/subnets/${SUBNET_ID}" \
            "${JSON}"
        then
            ok "${NAME} updated."
        else
            show_api_error
            record_failure "${NAME} update"
        fi

        return 0

    fi

    info "Creating ${NAME}"

    if api_request POST "${API}/subnets" "${JSON}"
    then

        SUBNET_ID="$(echo "${API_BODY}" | jq -r '.id // empty')"
        ok "${NAME} created. ID=${SUBNET_ID}"

    else

        if [ "${API_STATUS}" = "422" ]
        then

            SUBNET_ID="$(find_subnet_id "${NAME}")"

            if [ -n "${SUBNET_ID}" ]
            then
                skip "${NAME} already exists. ID=${SUBNET_ID}"
                return 0
            fi

        fi

        show_api_error
        record_failure "${NAME} creation"

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
# TEMPLATE VERIFICATION
###############################################################################

section "PXEGrub2 Template Verification"

if api_request GET "${API}/provisioning_templates?per_page=all"
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
                '.results[]? | select(.name == $NAME) | .id' |
            head -1
        )"

        TEMPLATE_KIND="$(
            echo "${API_BODY}" |
            jq -r \
                --arg NAME "${TEMPLATE_NAME}" \
                '.results[]? | select(.name == $NAME) | .template_kind_id' |
            head -1
        )"

        if [ -n "${TEMPLATE_ID}" ] &&
           [ "${TEMPLATE_KIND}" = "${PXEGRUB2_KIND_ID}" ]
        then

            ok "${TEMPLATE_NAME} | ID=${TEMPLATE_ID} | kind_id=${TEMPLATE_KIND}"

        else

            error "${TEMPLATE_NAME} verification failed."
            record_failure "${TEMPLATE_NAME} verification"

        fi

    done

else

    show_api_error
    record_failure "PXE template verification"

fi

###############################################################################
# OS/TEMPLATE MAPPING VERIFICATION
###############################################################################

section "OS Template Mapping Verification"

verify_mapping()
{
    local OS_NAME="$1"
    local TEMPLATE_NAME="$2"

    local OS_ID
    local TEMPLATE_ID

    OS_ID="$(find_os_id "${OS_NAME}")"
    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -z "${OS_ID}" ] || [ -z "${TEMPLATE_ID}" ]
    then
        error "${OS_NAME} -> ${TEMPLATE_NAME}"
        record_failure "${OS_NAME} mapping verification"
        return
    fi

    if api_request GET \
        "${API}/operatingsystems/${OS_ID}/provisioning_templates?per_page=all"
    then

        if echo "${API_BODY}" |
            jq -e \
                --argjson ID "${TEMPLATE_ID}" \
                '.results[]? | select(.id == $ID)' >/dev/null
        then

            ok "${OS_NAME} -> ${TEMPLATE_NAME}"

        else

            error "${OS_NAME} -> ${TEMPLATE_NAME}"
            record_failure "${OS_NAME} mapping verification"

        fi

    else

        show_api_error
        record_failure "${OS_NAME} mapping verification"

    fi
}

verify_mapping "${CENTOS_RAID_NAME}" "${CENTOS_RAID_TEMPLATE}"
verify_mapping "${CENTOS_SINGLE_NAME}" "${CENTOS_SINGLE_TEMPLATE}"

verify_mapping "${ROCKY8_RAID_NAME}" "${ROCKY8_RAID_TEMPLATE}"
verify_mapping "${ROCKY8_SINGLE_NAME}" "${ROCKY8_SINGLE_TEMPLATE}"

verify_mapping "${ROCKY92_RAID_NAME}" "${ROCKY92_RAID_TEMPLATE}"
verify_mapping "${ROCKY92_SINGLE_NAME}" "${ROCKY92_SINGLE_TEMPLATE}"

verify_mapping "${ROCKY98_RAID_NAME}" "${ROCKY98_RAID_TEMPLATE}"
verify_mapping "${ROCKY98_SINGLE_NAME}" "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# DEFAULT VERIFICATION
###############################################################################

section "PXEGrub2 Default Template Verification"

verify_default()
{
    local OS_NAME="$1"
    local TEMPLATE_NAME="$2"

    local OS_ID
    local TEMPLATE_ID
    local DEFAULT_ID

    OS_ID="$(find_os_id "${OS_NAME}")"
    TEMPLATE_ID="$(find_template_id "${TEMPLATE_NAME}")"

    if [ -z "${OS_ID}" ] || [ -z "${TEMPLATE_ID}" ]
    then
        error "${OS_NAME} PXEGrub2 default verification failed."
        record_failure "${OS_NAME} default verification"
        return
    fi

    if ! api_request GET \
        "${API}/operatingsystems/${OS_ID}/os_default_templates?per_page=all"
    then
        show_api_error
        record_failure "${OS_NAME} default verification"
        return
    fi

    DEFAULT_ID="$(
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
        head -1
    )"

    if [ -n "${DEFAULT_ID}" ]
    then
        ok "${OS_NAME} PXEGrub2 default correct. ID=${DEFAULT_ID}"
    else
        error "${OS_NAME} PXEGrub2 default incorrect/missing."
        record_failure "${OS_NAME} default verification"
    fi
}

verify_default "${CENTOS_RAID_NAME}" "${CENTOS_RAID_TEMPLATE}"
verify_default "${CENTOS_SINGLE_NAME}" "${CENTOS_SINGLE_TEMPLATE}"

verify_default "${ROCKY8_RAID_NAME}" "${ROCKY8_RAID_TEMPLATE}"
verify_default "${ROCKY8_SINGLE_NAME}" "${ROCKY8_SINGLE_TEMPLATE}"

verify_default "${ROCKY92_RAID_NAME}" "${ROCKY92_RAID_TEMPLATE}"
verify_default "${ROCKY92_SINGLE_NAME}" "${ROCKY92_SINGLE_TEMPLATE}"

verify_default "${ROCKY98_RAID_NAME}" "${ROCKY98_RAID_TEMPLATE}"
verify_default "${ROCKY98_SINGLE_NAME}" "${ROCKY98_SINGLE_TEMPLATE}"

###############################################################################
# SUBNET VERIFICATION
###############################################################################

section "PXE Subnet Verification"

if api_request GET "${API}/subnets?per_page=all"
then

    echo "${API_BODY}" |
    jq -r '
        .results[]? |
        [
            .id,
            .name,
            (.network // ""),
            (.mask // ""),
            (.gateway // ""),
            (.dns_primary // ""),
            (.tftp_name // ""),
            (.dhcp_name // "")
        ] |
        @tsv
    '

else

    show_api_error
    record_failure "Subnet verification"

fi

###############################################################################
# FINAL SUMMARY
###############################################################################

section "01 - Foreman PXE Bootstrap API Completed"

if [ ${#FAILURES[@]} -eq 0 ]
then

    echo -e "${GREEN}"
    echo "============================================================"
    echo "BOOTSTRAP COMPLETED SUCCESSFULLY"
    echo "============================================================"
    echo -e "${NC}"

    ok "Completed successfully with 0 failures."

else

    echo -e "${RED}"
    echo "============================================================"
    echo "BOOTSTRAP COMPLETED WITH ERRORS"
    echo "============================================================"
    echo -e "${NC}"

    error "Failure count : ${#FAILURES[@]}"

    echo
    echo "Failures:"
    echo "------------------------------------------------------------"

    for FAILURE in "${FAILURES[@]}"
    do
        error "${FAILURE}"
    done

fi

###############################################################################
# EXPECTED CONFIGURATION
###############################################################################

echo
echo "Expected PXE configuration:"
echo "------------------------------------------------------------"

echo "Installation Media:"
echo "  CentOS 7 Remote      -> ${CENTOS_MEDIA_URL}"
echo "  Rocky 8 Remote       -> ${ROCKY8_MEDIA_URL}"
echo "  Rocky 9.2 Remote     -> ${ROCKY92_MEDIA_URL}"
echo "  Rocky 9 Remote       -> ${ROCKY98_MEDIA_URL}"

echo
echo "Operating Systems:"
echo "  ${CENTOS_RAID_NAME}"
echo "  ${CENTOS_SINGLE_NAME}"
echo "  ${ROCKY8_RAID_NAME}"
echo "  ${ROCKY8_SINGLE_NAME}"
echo "  ${ROCKY92_RAID_NAME}"
echo "  ${ROCKY92_SINGLE_NAME}"
echo "  ${ROCKY98_RAID_NAME}"
echo "  ${ROCKY98_SINGLE_NAME}"

echo
echo "PXEGrub2 Templates:"
echo "  ${CENTOS_RAID_TEMPLATE}"
echo "  ${CENTOS_SINGLE_TEMPLATE}"
echo "  ${ROCKY8_RAID_TEMPLATE}"
echo "  ${ROCKY8_SINGLE_TEMPLATE}"
echo "  ${ROCKY92_RAID_TEMPLATE}"
echo "  ${ROCKY92_SINGLE_TEMPLATE}"
echo "  ${ROCKY98_RAID_TEMPLATE}"
echo "  ${ROCKY98_SINGLE_TEMPLATE}"

echo
echo "Generated files:"
ls -lh "${TEMPLATE_DIR}"/*.erb 2>/dev/null

echo
echo "Authentication:"
echo "  Method : REST API"
echo "  User   : ${FOREMAN_USER}"
echo "  Hammer : NOT USED"
echo "  API    : ${API}"

###############################################################################
# EXIT
###############################################################################

if [ ${#FAILURES[@]} -eq 0 ]
then
    exit 0
else
    exit 1
fi
