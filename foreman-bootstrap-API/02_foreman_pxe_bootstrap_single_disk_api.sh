#!/bin/bash
###############################################################################
# 02_foreman_pxe_bootstrap_single_disk_api.sh
#
# Foreman PXE Bootstrap - Single Disk
#
# REST API ONLY
# NO HAMMER
#
# Purpose:
#   Create / update Single Disk PXEGrub2 templates
#   Associate Single Disk templates with existing Operating Systems
#   Set Single Disk PXEGrub2 templates as OS defaults
#   Verify all Single Disk mappings
#
# Supported Operating Systems:
#   CentOSLinux7-SingleDisk
#   RockyLinux8.10-SingleDisk
#   RockyLinux9.2-SingleDisk
#   RockyLinux9.8-SingleDisk
#
# Supported TARGET_VERSION:
#   9.2
#   9.8
#
# Expected execution:
#
#   export FOREMAN_TOKEN='YOUR_FOREMAN_PASSWORD_OR_TOKEN'
#
#   TARGET_VERSION=9.2 ./02_foreman_pxe_bootstrap_single_disk_api.sh
#
#   TARGET_VERSION=9.8 ./02_foreman_pxe_bootstrap_single_disk_api.sh
#
###############################################################################

set +e
set -o pipefail

###############################################################################
# COLORS
###############################################################################

if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    WHITE='\033[1;37m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    MAGENTA=''
    WHITE=''
    BOLD=''
    RESET=''
fi

###############################################################################
# GLOBAL VARIABLES
###############################################################################

FAILURES=0

API_BODY=""
API_STATUS=""

TMP_DIR="/tmp/foreman-pxe-bootstrap"

###############################################################################
# LOGGING
###############################################################################

header()
{
    echo
    printf "${MAGENTA}${BOLD}============================================================${RESET}\n"
    printf "${MAGENTA}${BOLD}%s${RESET}\n" "$1"
    printf "${MAGENTA}${BOLD}============================================================${RESET}\n"
}

section()
{
    echo
    printf "${CYAN}${BOLD}============================================================${RESET}\n"
    printf "${CYAN}${BOLD}%s${RESET}\n" "$1"
    printf "${CYAN}${BOLD}============================================================${RESET}\n"
}

subsection()
{
    echo
    printf "${BLUE}------------------------------------------------------------${RESET}\n"
    printf "${BLUE}${BOLD}%s${RESET}\n" "$1"
    printf "${BLUE}------------------------------------------------------------${RESET}\n"
}

info()
{
    printf "${CYAN}[INFO]${RESET} %s\n" "$1"
}

ok()
{
    printf "${GREEN}[OK]${RESET} %s\n" "$1"
}

skip()
{
    printf "${BLUE}[SKIP]${RESET} %s\n" "$1"
}

warn()
{
    printf "${YELLOW}[WARN]${RESET} %s\n" "$1"
}

error()
{
    printf "${RED}[ERROR]${RESET} %s\n" "$1"
}

record_failure()
{
    FAILURES=$((FAILURES + 1))
}

###############################################################################
# CONFIGURATION
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_INSECURE="${FOREMAN_INSECURE:-true}"

###############################################################################
# FOREMAN TOKEN
###############################################################################

if [ -z "${FOREMAN_TOKEN:-}" ]; then

    error "FOREMAN_TOKEN is not set."

    echo
    echo "Set the Foreman password/token first:"
    echo
    echo "export FOREMAN_USER='admin'"
    echo "export FOREMAN_TOKEN='YOUR_PASSWORD_OR_TOKEN'"
    echo

    exit 1
fi

API="${FOREMAN_URL}/api"

###############################################################################
# TARGET VERSION
###############################################################################

TARGET_VERSION="${TARGET_VERSION:-9.8}"

###############################################################################
# EXISTING FOREMAN OPERATING SYSTEM NAMES
###############################################################################

CENTOS_SINGLE_OS="CentOSLinux7-SingleDisk"
ROCKY8_SINGLE_OS="RockyLinux8.10-SingleDisk"
ROCKY92_SINGLE_OS="RockyLinux9.2-SingleDisk"
ROCKY98_SINGLE_OS="RockyLinux9.8-SingleDisk"

###############################################################################
# SINGLE DISK TEMPLATE NAMES
###############################################################################

CENTOS_SINGLE_TEMPLATE="PXEGrub2 CentOS UEFI SingleDisk Kickstart"

ROCKY8_SINGLE_TEMPLATE="PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

ROCKY92_SINGLE_TEMPLATE="PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

ROCKY98_SINGLE_TEMPLATE="PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

###############################################################################
# TARGET VERSION CONFIGURATION
###############################################################################

ROCKY_OS=""
ROCKY_TEMPLATE=""
ROCKY_TEMPLATE_FILE=""
ROCKY_KERNEL=""
ROCKY_INITRD=""
ROCKY_REPO=""
ROCKY_KS=""

case "${TARGET_VERSION}" in

    9.2)

        ROCKY_OS="${ROCKY92_SINGLE_OS}"

        ROCKY_TEMPLATE="${ROCKY92_SINGLE_TEMPLATE}"

        ROCKY_TEMPLATE_FILE="${TMP_DIR}/rocky92-singledisk.erb"

        ROCKY_KERNEL="/rocky92/vmlinuz"

        ROCKY_INITRD="/rocky92/initrd.img"

        ROCKY_REPO="http://192.168.253.136/repo/rocky9.2/"

        ROCKY_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/Rocky9_2_Golden_SingleDisk_Minimal.cfg"

        ;;

    9.8)

        ROCKY_OS="${ROCKY98_SINGLE_OS}"

        ROCKY_TEMPLATE="${ROCKY98_SINGLE_TEMPLATE}"

        ROCKY_TEMPLATE_FILE="${TMP_DIR}/rocky98-singledisk.erb"

        ROCKY_KERNEL="/rocky9/vmlinuz"

        ROCKY_INITRD="/rocky9/initrd.img"

        ROCKY_REPO="http://192.168.253.136/repo/rocky9/"

        ROCKY_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/Rocky9_Golden_SingleDisk_Minimal.cfg"

        ;;

    *)

        error "Unsupported TARGET_VERSION=${TARGET_VERSION}"
        echo
        echo "Supported versions:"
        echo "  9.2"
        echo "  9.8"
        echo

        exit 1

        ;;

esac

###############################################################################
# REQUIRED COMMANDS
###############################################################################

CURL=""
JQ=""
CAT=""
HEAD=""
GREP=""
AWK=""
MKDIR=""
RM=""
MKTEMP=""
LS=""

check_command()
{
    local name="$1"
    local path

    path="$(command -v "$name" 2>/dev/null || true)"

    if [ -z "$path" ]; then
        error "$name not found."
        return 1
    fi

    printf "${GREEN}[OK]${RESET} %s found: %s\n" "$name" "$path"

    case "$name" in

        curl)
            CURL="$path"
            ;;

        jq)
            JQ="$path"
            ;;

        cat)
            CAT="$path"
            ;;

        head)
            HEAD="$path"
            ;;

        grep)
            GREP="$path"
            ;;

        awk)
            AWK="$path"
            ;;

        mkdir)
            MKDIR="$path"
            ;;

        rm)
            RM="$path"
            ;;

        mktemp)
            MKTEMP="$path"
            ;;

        ls)
            LS="$path"
            ;;

    esac

    return 0
}

check_dependencies()
{
    section "Dependency Check"

    check_command curl   || exit 1
    check_command jq     || exit 1
    check_command cat    || exit 1
    check_command head   || exit 1
    check_command grep   || exit 1
    check_command awk    || exit 1
    check_command mkdir  || exit 1
    check_command rm     || exit 1
    check_command mktemp || exit 1
    check_command ls     || exit 1
}

###############################################################################
# JSON VALIDATION
###############################################################################

json_valid()
{
    printf '%s\n' "$1" |
        "$JQ" empty >/dev/null 2>&1
}

###############################################################################
# FOREMAN API REQUEST
###############################################################################

api_request()
{
    local method="$1"
    local url="$2"
    local payload="${3:-}"

    local body_file
    local response

    body_file="$("$MKTEMP")"

    if [ -n "$payload" ]; then

        response="$(
            "$CURL" \
                -ksS \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                -H 'Accept: application/json,version=2' \
                -H 'Content-Type: application/json' \
                -X "$method" \
                -d "$payload" \
                -o "$body_file" \
                -w '%{http_code}' \
                "$url" \
                2>&1
        )"

    else

        response="$(
            "$CURL" \
                -ksS \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                -H 'Accept: application/json,version=2' \
                -H 'Content-Type: application/json' \
                -X "$method" \
                -o "$body_file" \
                -w '%{http_code}' \
                "$url" \
                2>&1
        )"

    fi

    API_STATUS="$response"
    API_BODY=""

    if [ -f "$body_file" ]; then
        API_BODY="$("$CAT" "$body_file" 2>/dev/null || true)"
    fi

    "$RM" -f "$body_file" >/dev/null 2>&1 || true

    if ! printf '%s' "$API_STATUS" |
        "$GREP" -Eq '^[0-9]{3}$'
    then
        API_BODY="$response"
        API_STATUS=""
        return 1
    fi

    if printf '%s' "$API_STATUS" |
        "$GREP" -Eq '^2[0-9][0-9]$'
    then
        return 0
    fi

    return 1
}

###############################################################################
# API ERROR
###############################################################################

print_api_error()
{
    local method="$1"
    local url="$2"

    error "API request failed."
    error "HTTP Status : ${API_STATUS}"
    error "Method      : ${method}"
    error "URL         : ${url}"

    echo

    if json_valid "$API_BODY"; then
        printf '%s\n' "$API_BODY" | "$JQ" .
    else
        printf '%s\n' "$API_BODY"
    fi

    echo
}

###############################################################################
# EXACT NAME LOOKUP
###############################################################################

find_id_by_name()
{
    local endpoint="$1"
    local name="$2"

    API_BODY=""

    if ! api_request GET "${API}/${endpoint}?per_page=all"; then
        return 1
    fi

    if ! json_valid "$API_BODY"; then
        return 1
    fi

    printf '%s\n' "$API_BODY" |
        "$JQ" -r \
            --arg NAME "$name" \
            '
            (.results // [])[]
            | select(.name == $NAME)
            | .id
            ' |
        "$HEAD" -1
}

###############################################################################
# FOREMAN API TEST
###############################################################################

test_api()
{
    section "Foreman API Authentication Test"

    info "Testing Foreman REST API..."

    if ! api_request GET "${API}/status"; then

        print_api_error GET "${API}/status"

        error "Foreman API authentication failed."

        exit 1

    fi

    local version
    local api_version

    version="$(
        printf '%s\n' "$API_BODY" |
            "$JQ" -r '.version // empty'
    )"

    api_version="$(
        printf '%s\n' "$API_BODY" |
            "$JQ" -r '.api_version // empty'
    )"

    ok "Foreman API authentication successful."

    printf "${WHITE}Foreman Version :${RESET} %s\n" "$version"
    printf "${WHITE}API Version     :${RESET} %s\n" "$api_version"
    printf "${WHITE}API Status      :${RESET} %s\n" "$API_STATUS"
}

###############################################################################
# FIND PXEGRUB2 TEMPLATE KIND
###############################################################################

find_pxegrub2_kind()
{
    section "Finding Existing PXEGrub2 Template Kind"

    local kind_id=""

    ###########################################################################
    # First search existing provisioning templates
    ###########################################################################

    if api_request GET \
        "${API}/provisioning_templates?per_page=all"
    then

        kind_id="$(
            printf '%s\n' "$API_BODY" |
                "$JQ" -r '
                (.results // [])[]
                | select(
                    .template_kind_name == "PXEGrub2"
                    or
                    .template_kind == "PXEGrub2"
                )
                | .template_kind_id
                ' |
                "$HEAD" -1
        )"

    fi

    ###########################################################################
    # If not found, search template kinds
    ###########################################################################

    if [ -z "$kind_id" ] || [ "$kind_id" = "null" ]; then

        if api_request GET \
            "${API}/provisioning_template_kinds?per_page=all"
        then

            kind_id="$(
                printf '%s\n' "$API_BODY" |
                    "$JQ" -r '
                    (.results // [])[]
                    | select(.name == "PXEGrub2")
                    | .id
                    ' |
                    "$HEAD" -1
            )"

        fi

    fi

    if [ -n "$kind_id" ] &&
       [ "$kind_id" != "null" ]
    then

        PXEGRUB2_KIND_ID="$kind_id"

        ok "PXEGrub2 template kind found."

        echo "PXEGrub2 Template Kind ID : ${PXEGRUB2_KIND_ID}"

        return 0

    fi

    error "PXEGrub2 template kind not found."

    record_failure "PXEGrub2 template kind"

    return 1
}

###############################################################################
# CREATE / UPDATE TEMPLATE
###############################################################################

create_or_update_template()
{
    local name="$1"
    local filename="$2"

    local template_id=""
    local template_text=""
    local json=""

    subsection "PXEGrub2 Template : ${name}"

    if [ ! -f "${TMP_DIR}/${filename}" ]; then

        error "Template file missing: ${filename}"

        record_failure "${name} file"

        return 1

    fi

    template_text="$("$CAT" "${TMP_DIR}/${filename}")"

    template_id="$(
        find_id_by_name provisioning_templates "$name" || true
    )"

    ###########################################################################
    # UPDATE EXISTING TEMPLATE
    ###########################################################################

    if [ -n "$template_id" ] &&
       [ "$template_id" != "null" ]
    then

        skip "${name} already exists. ID=${template_id}"

        json="$(
            "$JQ" -n \
                --arg template "$template_text" \
                --argjson kind "$PXEGRUB2_KIND_ID" \
                '{
                    provisioning_template: {
                        template: $template,
                        template_kind_id: $kind
                    }
                }'
        )"

        if api_request PUT \
            "${API}/provisioning_templates/${template_id}" \
            "$json"
        then

            ok "${name} updated."

        else

            print_api_error \
                PUT \
                "${API}/provisioning_templates/${template_id}"

            record_failure "${name} update"

        fi

        return 0

    fi

    ###########################################################################
    # CREATE TEMPLATE
    ###########################################################################

    info "Creating ${name}"

    json="$(
        "$JQ" -n \
            --arg name "$name" \
            --arg template "$template_text" \
            --argjson kind "$PXEGRUB2_KIND_ID" \
            '{
                provisioning_template: {
                    name: $name,
                    template: $template,
                    template_kind_id: $kind
                }
            }'
    )"

    if api_request POST \
        "${API}/provisioning_templates" \
        "$json"
    then

        template_id="$(
            printf '%s\n' "$API_BODY" |
                "$JQ" -r '.id // empty'
        )"

        ok "${name} created. ID=${template_id}"

        return 0

    fi

    ###########################################################################
    # 422 = POSSIBLY ALREADY EXISTS
    ###########################################################################

    if [ "$API_STATUS" = "422" ]; then

        template_id="$(
            find_id_by_name provisioning_templates "$name" || true
        )"

        if [ -n "$template_id" ]; then

            skip "${name} already exists. Recovered ID=${template_id}"

            return 0

        fi

    fi

    print_api_error \
        POST \
        "${API}/provisioning_templates"

    record_failure "${name} creation"

    return 1
}

###############################################################################
# CENTOS 7 SINGLE DISK TEMPLATE
###############################################################################

generate_centos_single_template()
{
    info "Generating CentOS 7 Single Disk template..."

    "$CAT" > "${TMP_DIR}/centos-singledisk.erb" <<'EOF_CENTOS_SINGLE'
<%#
name: PXEGrub2 CentOS UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- CentOSLinux
%>
set default=0
set timeout=5

menuentry 'Install CentOS 7 Single Disk' {
    linuxefi /centos/vmlinuz inst.stage2=http://192.168.253.136/repo/centos/ inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/CentOS7_Golden_SingleDisk_Minimal.cfg inst.text inst.ks.device=bootif BOOTIF=01-${net_default_mac} hostname=<%= @host.name %>
    initrdefi /centos/initrd.img
}
EOF_CENTOS_SINGLE

    if [ $? -eq 0 ]; then
        ok "CentOS Single Disk template generated."
    else
        error "CentOS Single Disk template generation failed."
        record_failure "CentOS SingleDisk template generation"
    fi
}

###############################################################################
# ROCKY 8 SINGLE DISK TEMPLATE
###############################################################################

generate_rocky8_single_template()
{
    info "Generating Rocky Linux 8 Single Disk template..."

    "$CAT" > "${TMP_DIR}/rocky8-singledisk.erb" <<'EOF_ROCKY8_SINGLE'
<%#
name: PXEGrub2 Rocky8 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5

menuentry 'Install Rocky Linux 8.10 Single Disk' {
    linuxefi /rocky8/vmlinuz inst.stage2=http://192.168.253.136/repo/rocky8/ inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/Rocky8_Golden_SingleDisk_Minimal.cfg inst.text inst.ks.device=bootif BOOTIF=01-${net_default_mac} hostname=<%= @host.name %>
    initrdefi /rocky8/initrd.img
}
EOF_ROCKY8_SINGLE

    if [ $? -eq 0 ]; then
        ok "Rocky Linux 8 Single Disk template generated."
    else
        error "Rocky Linux 8 Single Disk template generation failed."
        record_failure "Rocky8 SingleDisk template generation"
    fi
}

###############################################################################
# ROCKY 9.2 SINGLE DISK TEMPLATE
###############################################################################

generate_rocky92_single_template()
{
    info "Generating Rocky Linux 9.2 Single Disk template..."

    "$CAT" > "${TMP_DIR}/rocky92-singledisk.erb" <<'EOF_ROCKY92_SINGLE'
<%#
name: PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5

menuentry 'Install Rocky Linux 9.2 Single Disk' {
    linuxefi /rocky92/vmlinuz ip=dhcp BOOTIF=01-${net_default_mac} inst.repo=http://192.168.253.136/repo/rocky9.2/ inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/Rocky9_2_Golden_SingleDisk_Minimal.cfg inst.text inst.ks.device=bootif hostname=<%= @host.name %>
    initrdefi /rocky92/initrd.img
}
EOF_ROCKY92_SINGLE

    if [ $? -eq 0 ]; then
        ok "Rocky Linux 9.2 Single Disk template generated."
    else
        error "Rocky Linux 9.2 Single Disk template generation failed."
        record_failure "Rocky9.2 SingleDisk template generation"
    fi
}

###############################################################################
# ROCKY 9.8 SINGLE DISK TEMPLATE
###############################################################################

generate_rocky98_single_template()
{
    info "Generating Rocky Linux 9.8 Single Disk template..."

    "$CAT" > "${TMP_DIR}/rocky98-singledisk.erb" <<'EOF_ROCKY98_SINGLE'
<%#
name: PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5

menuentry 'Install Rocky Linux 9.8 Single Disk' {
    linuxefi /rocky9/vmlinuz ip=dhcp BOOTIF=01-${net_default_mac} inst.repo=http://192.168.253.136/repo/rocky9/ inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/Rocky9_Golden_SingleDisk_Minimal.cfg inst.text inst.ks.device=bootif hostname=<%= @host.name %>
    initrdefi /rocky9/initrd.img
}
EOF_ROCKY98_SINGLE

    if [ $? -eq 0 ]; then
        ok "Rocky Linux 9.8 Single Disk template generated."
    else
        error "Rocky Linux 9.8 Single Disk template generation failed."
        record_failure "Rocky9.8 SingleDisk template generation"
    fi
}

###############################################################################
# GENERATE ALL SINGLE DISK TEMPLATES
###############################################################################

generate_templates()
{
    section "Generating Single Disk PXEGrub2 Template Files"

    "$MKDIR" -p "$TMP_DIR"

    generate_centos_single_template

    generate_rocky8_single_template

    generate_rocky92_single_template

    generate_rocky98_single_template

    echo

    "$LS" -lh \
        "${TMP_DIR}/centos-singledisk.erb" \
        "${TMP_DIR}/rocky8-singledisk.erb" \
        "${TMP_DIR}/rocky92-singledisk.erb" \
        "${TMP_DIR}/rocky98-singledisk.erb" \
        2>/dev/null

    echo
}

###############################################################################
# IMPORT / UPDATE ALL SINGLE DISK TEMPLATES
###############################################################################

create_single_disk_templates()
{
    section "Creating / Verifying Single Disk PXEGrub2 Templates"

    create_or_update_template \
        "${CENTOS_SINGLE_TEMPLATE}" \
        "centos-singledisk.erb"

    create_or_update_template \
        "${ROCKY8_SINGLE_TEMPLATE}" \
        "rocky8-singledisk.erb"

    create_or_update_template \
        "${ROCKY92_SINGLE_TEMPLATE}" \
        "rocky92-singledisk.erb"

    create_or_update_template \
        "${ROCKY98_SINGLE_TEMPLATE}" \
        "rocky98-singledisk.erb"
}

###############################################################################
# GET OPERATING SYSTEM ID
###############################################################################

get_os_id()
{
    local os_name="$1"

    find_id_by_name operatingsystems "$os_name" || true
}

###############################################################################
# GET TEMPLATE ID
###############################################################################

get_template_id()
{
    local template_name="$1"

    find_id_by_name provisioning_templates "$template_name" || true
}

###############################################################################
# ASSOCIATE TEMPLATE WITH OS
###############################################################################

associate_template()
{
    local os_name="$1"
    local template_name="$2"

    local os_id=""
    local template_id=""
    local json=""

    subsection "OS Template Association"

    echo "OS       : ${os_name}"
    echo "Template : ${template_name}"

    ###########################################################################
    # FIND OS
    ###########################################################################

    os_id="$(get_os_id "${os_name}")"

    if [ -z "$os_id" ]; then

        error "Operating System not found : ${os_name}"

        record_failure "${os_name} OS lookup"

        return 1

    fi

    ok "Operating System found. ID=${os_id}"

    ###########################################################################
    # FIND TEMPLATE
    ###########################################################################

    template_id="$(get_template_id "${template_name}")"

    if [ -z "$template_id" ]; then

        error "Provisioning template not found : ${template_name}"

        record_failure "${template_name} template lookup"

        return 1

    fi

    ok "Template found. ID=${template_id}"

    ###########################################################################
    # CHECK EXISTING ASSOCIATION
    ###########################################################################

    if api_request GET \
        "${API}/operatingsystems/${os_id}/provisioning_templates?per_page=all"
    then

        if printf '%s\n' "$API_BODY" |
            "$JQ" -e \
                --argjson ID "$template_id" \
                '
                (.results // [])
                | any(.[]; .id == $ID)
                ' >/dev/null 2>&1
        then

            skip "${os_name} already associated with ${template_name}."

            return 0

        fi

    fi

    ###########################################################################
    # CREATE ASSOCIATION
    ###########################################################################

    json="$(
        "$JQ" -n \
            --argjson id "$template_id" \
            '{
                provisioning_template_id: $id
            }'
    )"

    info "Associating template..."

    if api_request POST \
        "${API}/operatingsystems/${os_id}/provisioning_templates" \
        "$json"
    then

        ok "${os_name} associated with ${template_name}."

        return 0

    fi

    ###########################################################################
    # 422 MAY MEAN ASSOCIATION ALREADY EXISTS
    ###########################################################################

    if [ "$API_STATUS" = "422" ]; then

        if api_request GET \
            "${API}/operatingsystems/${os_id}/provisioning_templates?per_page=all"
        then

            if printf '%s\n' "$API_BODY" |
                "$JQ" -e \
                    --argjson ID "$template_id" \
                    '
                    (.results // [])
                    | any(.[]; .id == $ID)
                    ' >/dev/null 2>&1
            then

                skip "${os_name} association already exists."

                return 0

            fi

        fi

    fi

    print_api_error \
        POST \
        "${API}/operatingsystems/${os_id}/provisioning_templates"

    record_failure "${os_name} -> ${template_name} association"

    return 1
}

###############################################################################
# SET PXEGRUB2 DEFAULT TEMPLATE
###############################################################################

set_pxe_default()
{
    local os_name="$1"
    local template_name="$2"

    local os_id=""
    local template_id=""
    local existing_id=""
    local existing_template=""
    local existing_kind=""
    local json=""

    subsection "PXEGrub2 Default Template"

    echo "OS       : ${os_name}"
    echo "Template : ${template_name}"

    ###########################################################################
    # FIND OS
    ###########################################################################

    os_id="$(get_os_id "${os_name}")"

    if [ -z "$os_id" ]; then

        error "Operating System not found : ${os_name}"

        record_failure "${os_name} default lookup"

        return 1

    fi

    ok "Operating System ID : ${os_id}"

    ###########################################################################
    # FIND TEMPLATE
    ###########################################################################

    template_id="$(get_template_id "${template_name}")"

    if [ -z "$template_id" ]; then

        error "Template not found : ${template_name}"

        record_failure "${template_name} default lookup"

        return 1

    fi

    ok "Template ID : ${template_id}"

    ###########################################################################
    # READ EXISTING DEFAULTS
    ###########################################################################

    if ! api_request GET \
        "${API}/operatingsystems/${os_id}/os_default_templates?per_page=all"
    then

        print_api_error \
            GET \
            "${API}/operatingsystems/${os_id}/os_default_templates"

        record_failure "${os_name} default lookup"

        return 1

    fi

    ###########################################################################
    # FIND EXISTING PXEGRUB2 DEFAULT
    ###########################################################################

    existing_id="$(
        printf '%s\n' "$API_BODY" |
            "$JQ" -r \
                --argjson KIND "$PXEGRUB2_KIND_ID" \
                '
                (.results // [])
                | .[]
                | select(
                    (.template_kind_id == $KIND)
                    or
                    (.template_kind_name == "PXEGrub2")
                )
                | .id
                ' |
            "$HEAD" -1
    )"

    ###########################################################################
    # EXISTING DEFAULT FOUND
    ###########################################################################

    if [ -n "$existing_id" ] &&
       [ "$existing_id" != "null" ]
    then

        existing_template="$(
            printf '%s\n' "$API_BODY" |
                "$JQ" -r \
                    --argjson ID "$existing_id" \
                    '
                    (.results // [])
                    | .[]
                    | select(.id == $ID)
                    | .provisioning_template_id
                    '
        )"

        existing_kind="$(
            printf '%s\n' "$API_BODY" |
                "$JQ" -r \
                    --argjson ID "$existing_id" \
                    '
                    (.results // [])
                    | .[]
                    | select(.id == $ID)
                    | .template_kind_id
                    '
        )"

        #######################################################################
        # ALREADY CORRECT
        #######################################################################

        if [ "$existing_template" = "$template_id" ] &&
           [ "$existing_kind" = "$PXEGRUB2_KIND_ID" ]
        then

            skip "PXEGrub2 default already correct. ID=${existing_id}"

            return 0

        fi

        #######################################################################
        # UPDATE EXISTING DEFAULT
        #######################################################################

        json="$(
            "$JQ" -n \
                --argjson template "$template_id" \
                --argjson kind "$PXEGRUB2_KIND_ID" \
                '{
                    os_default_template: {
                        provisioning_template_id: $template,
                        template_kind_id: $kind
                    }
                }'
        )"

        info "Updating existing PXEGrub2 default..."

        if api_request PUT \
            "${API}/operatingsystems/${os_id}/os_default_templates/${existing_id}" \
            "$json"
        then

            ok "PXEGrub2 default updated. ID=${existing_id}"

            return 0

        fi

        print_api_error \
            PUT \
            "${API}/operatingsystems/${os_id}/os_default_templates/${existing_id}"

        record_failure "${os_name} default update"

        return 1

    fi

    ###########################################################################
    # CREATE NEW DEFAULT
    ###########################################################################

    json="$(
        "$JQ" -n \
            --argjson template "$template_id" \
            --argjson kind "$PXEGRUB2_KIND_ID" \
            '{
                os_default_template: {
                    provisioning_template_id: $template,
                    template_kind_id: $kind
                }
            }'
    )"

    info "Creating PXEGrub2 default..."

    if api_request POST \
        "${API}/operatingsystems/${os_id}/os_default_templates" \
        "$json"
    then

        existing_id="$(
            printf '%s\n' "$API_BODY" |
                "$JQ" -r '.id // empty'
        )"

        ok "PXEGrub2 default created. ID=${existing_id}"

        return 0

    fi

###############################################################################
# 422 = DEFAULT ALREADY EXISTS
###############################################################################

if [ "$API_STATUS" = "422" ]; then

    ###########################################################################
    # Foreman 3.2.1 returns:
    #
    # {
    #   "errors": {
    #     "template_kind_id": [
    #       "has already been taken"
    #     ]
    #   }
    # }
    #
    # This means the PXEGrub2 default already exists.
    # Treat it as SKIP, not ERROR.
    ###########################################################################

    if printf '%s\n' "$API_BODY" |
        "$GREP" -qi "has already been taken"
    then

        skip "PXEGrub2 default already exists for ${os_name}. Nothing to change."

        return 0
    fi

fi

}
###############################################################################
# ASSOCIATE ALL SINGLE DISK TEMPLATES
###############################################################################

associate_single_disk_templates()
{
    section "Associating Single Disk PXEGrub2 Templates"

    ###########################################################################
    # CENTOS 7
    ###########################################################################

    associate_template \
        "${CENTOS_SINGLE_OS}" \
        "${CENTOS_SINGLE_TEMPLATE}"

    ###########################################################################
    # ROCKY 8.10
    ###########################################################################

    associate_template \
        "${ROCKY8_SINGLE_OS}" \
        "${ROCKY8_SINGLE_TEMPLATE}"

    ###########################################################################
    # ROCKY 9.2
    ###########################################################################

    associate_template \
        "${ROCKY92_SINGLE_OS}" \
        "${ROCKY92_SINGLE_TEMPLATE}"

    ###########################################################################
    # ROCKY 9.8
    ###########################################################################

    associate_template \
        "${ROCKY98_SINGLE_OS}" \
        "${ROCKY98_SINGLE_TEMPLATE}"
}

###############################################################################
# SET ALL SINGLE DISK PXEGRUB2 DEFAULTS
###############################################################################

set_single_disk_defaults()
{
    section "Setting Single Disk PXEGrub2 Defaults"

    ###########################################################################
    # CENTOS 7
    ###########################################################################

    set_pxe_default \
        "${CENTOS_SINGLE_OS}" \
        "${CENTOS_SINGLE_TEMPLATE}"

    ###########################################################################
    # ROCKY 8.10
    ###########################################################################

    set_pxe_default \
        "${ROCKY8_SINGLE_OS}" \
        "${ROCKY8_SINGLE_TEMPLATE}"

    ###########################################################################
    # ROCKY 9.2
    ###########################################################################

    set_pxe_default \
        "${ROCKY92_SINGLE_OS}" \
        "${ROCKY92_SINGLE_TEMPLATE}"

    ###########################################################################
    # ROCKY 9.8
    ###########################################################################

    set_pxe_default \
        "${ROCKY98_SINGLE_OS}" \
        "${ROCKY98_SINGLE_TEMPLATE}"
}

###############################################################################
# VERIFY TEMPLATE ASSOCIATION
###############################################################################

verify_template_association()
{
    local os_name="$1"
    local expected_template="$2"

    local os_id=""
    local template_id=""
    local match=""

    echo
    echo "------------------------------------------------------------"
    echo "OS       : ${os_name}"
    echo "Expected : ${expected_template}"
    echo "------------------------------------------------------------"

    os_id="$(get_os_id "${os_name}")"

    if [ -z "$os_id" ]; then

        error "Operating System not found : ${os_name}"

        record_failure "${os_name} verification"

        return

    fi

    template_id="$(get_template_id "${expected_template}")"

    if [ -z "$template_id" ]; then

        error "Template not found : ${expected_template}"

        record_failure "${expected_template} verification"

        return

    fi

    if ! api_request GET \
        "${API}/operatingsystems/${os_id}/provisioning_templates?per_page=all"
    then

        print_api_error \
            GET \
            "${API}/operatingsystems/${os_id}/provisioning_templates"

        record_failure "${os_name} association verification"

        return

    fi

    match="$(
        printf '%s\n' "$API_BODY" |
            "$JQ" -r \
                --argjson ID "$template_id" \
                '
                (.results // [])
                | .[]
                | select(.id == $ID)
                | .name
                ' |
            "$HEAD" -1
    )"

    if [ -n "$match" ]; then

        ok "Template mapping correct."

    else

        error "Template mapping missing."

        record_failure "${os_name} -> ${expected_template}"

    fi
}

###############################################################################
# VERIFY PXEGRUB2 DEFAULT
###############################################################################

verify_pxe_default()
{
    local os_name="$1"
    local expected_template="$2"

    local os_id=""
    local os_json=""
    local default_json=""
    local default_id=""
    local default_template_id=""
    local default_template_name=""

    echo
    info "PXEGrub2 Default Verification"
    echo "------------------------------------------------------------"
    echo "OS       : ${os_name}"
    echo "Expected : ${expected_template}"
    echo "------------------------------------------------------------"

    ###########################################################################
    # FIND OPERATING SYSTEM ID
    ###########################################################################

    os_id="$(get_os_id "${os_name}")"

    if [ -z "${os_id}" ] || [ "${os_id}" = "null" ]; then
        error "Operating System not found : ${os_name}"
        record_failure "${os_name} PXEGrub2 default verification"
        return 1
    fi

    ok "Operating System ID : ${os_id}"

    ###########################################################################
    # READ COMPLETE OPERATING SYSTEM OBJECT
    ###########################################################################

    if ! api_request GET \
        "${API}/operatingsystems/${os_id}"
    then

        print_api_error \
            GET \
            "${API}/operatingsystems/${os_id}"

        record_failure "${os_name} PXEGrub2 default verification"

        return 1
    fi

    os_json="${API_BODY}"

    ###########################################################################
    # FIND PXEGRUB2 DEFAULT
    #
    # PXEGrub2 template kind ID = 4
    ###########################################################################

    default_json="$(
        printf '%s\n' "${os_json}" |
            "$JQ" -c \
                --argjson KIND "$PXEGRUB2_KIND_ID" \
                '
                (.os_default_templates // [])
                | .[]
                | select(
                    (.template_kind_id == $KIND)
                    or
                    (.template_kind_name == "PXEGrub2")
                )
                ' |
            "$HEAD" -1
    )"

    ###########################################################################
    # DEFAULT NOT FOUND
    ###########################################################################

    if [ -z "${default_json}" ]; then
        error "PXEGrub2 default mapping missing."
        record_failure "${os_name} -> ${expected_template}"
        return 1
    fi

    ###########################################################################
    # EXTRACT DEFAULT INFORMATION
    ###########################################################################

    default_id="$(
        printf '%s\n' "${default_json}" |
            "$JQ" -r '.id // empty'
    )"

    default_template_id="$(
        printf '%s\n' "${default_json}" |
            "$JQ" -r '.provisioning_template_id // empty'
    )"

    default_template_name="$(
        printf '%s\n' "${default_json}" |
            "$JQ" -r '.provisioning_template_name // empty'
    )"

    echo "Default ID          : ${default_id}"
    echo "Template ID         : ${default_template_id}"
    echo "Template Name       : ${default_template_name}"

    ###########################################################################
    # VERIFY EXACT TEMPLATE
    ###########################################################################

    if [ "${default_template_name}" = "${expected_template}" ]; then

        ok "PXEGrub2 default mapping correct."

        return 0
    fi

    ###########################################################################
    # WRONG DEFAULT
    ###########################################################################

    error "PXEGrub2 default mapping points to wrong template."
    error "Expected : ${expected_template}"
    error "Actual   : ${default_template_name}"

    record_failure "${os_name} -> ${expected_template}"

    return 1
}

###############################################################################
# VERIFY ALL SINGLE DISK MAPPINGS
###############################################################################

verify_single_disk_mappings()
{
    section "Single Disk Template Association Verification"

    verify_template_association \
        "${CENTOS_SINGLE_OS}" \
        "${CENTOS_SINGLE_TEMPLATE}"

    verify_template_association \
        "${ROCKY8_SINGLE_OS}" \
        "${ROCKY8_SINGLE_TEMPLATE}"

    verify_template_association \
        "${ROCKY92_SINGLE_OS}" \
        "${ROCKY92_SINGLE_TEMPLATE}"

    verify_template_association \
        "${ROCKY98_SINGLE_OS}" \
        "${ROCKY98_SINGLE_TEMPLATE}"
}

###############################################################################
# VERIFY ALL SINGLE DISK DEFAULTS
###############################################################################

verify_single_disk_defaults()
{
    section "Single Disk PXEGrub2 Default Verification"

    verify_pxe_default \
        "${CENTOS_SINGLE_OS}" \
        "${CENTOS_SINGLE_TEMPLATE}"

    verify_pxe_default \
        "${ROCKY8_SINGLE_OS}" \
        "${ROCKY8_SINGLE_TEMPLATE}"

    verify_pxe_default \
        "${ROCKY92_SINGLE_OS}" \
        "${ROCKY92_SINGLE_TEMPLATE}"

    verify_pxe_default \
        "${ROCKY98_SINGLE_OS}" \
        "${ROCKY98_SINGLE_TEMPLATE}"
}

###############################################################################
# VERIFY GENERATED FILES
###############################################################################

verify_generated_files()
{
    section "Generated Single Disk PXE Files"

    "$LS" -lh \
        "${TMP_DIR}/centos-singledisk.erb" \
        "${TMP_DIR}/rocky8-singledisk.erb" \
        "${TMP_DIR}/rocky92-singledisk.erb" \
        "${TMP_DIR}/rocky98-singledisk.erb" \
        2>/dev/null

    echo

    for file in \
        "${TMP_DIR}/centos-singledisk.erb" \
        "${TMP_DIR}/rocky8-singledisk.erb" \
        "${TMP_DIR}/rocky92-singledisk.erb" \
        "${TMP_DIR}/rocky98-singledisk.erb"
    do

        if [ ! -f "$file" ]; then

            error "$(basename "$file") missing."

            record_failure "$(basename "$file")"

            continue

        fi

        if "$GREP" -q 'linuxefi' "$file" &&
           "$GREP" -q 'initrdefi' "$file" &&
           "$GREP" -q 'inst.ks=' "$file"
        then

            ok "$(basename "$file") looks valid."

        else

            error "$(basename "$file") content validation failed."

            record_failure "$(basename "$file") validation"

        fi

    done
}

###############################################################################
# VERIFY SINGLE DISK OPERATING SYSTEMS
###############################################################################

verify_operating_systems()
{
    section "Single Disk Operating System Verification"

    if ! api_request GET \
        "${API}/operatingsystems?per_page=all"
    then

        print_api_error \
            GET \
            "${API}/operatingsystems?per_page=all"

        record_failure "Operating System verification"

        return

    fi

    printf '%s\n' "$API_BODY" |
        "$JQ" -r \
            --arg C7 "$CENTOS_SINGLE_OS" \
            --arg R8 "$ROCKY8_SINGLE_OS" \
            --arg R92 "$ROCKY92_SINGLE_OS" \
            --arg R98 "$ROCKY98_SINGLE_OS" \
            '
            (.results // [])[]
            | select(
                .name == $C7
                or
                .name == $R8
                or
                .name == $R92
                or
                .name == $R98
            )
            | [
                .id,
                .name,
                (.major // ""),
                (.minor // ""),
                (.family // "")
            ]
            | @tsv
            '
}

###############################################################################
# VERIFY SINGLE DISK TEMPLATES
###############################################################################

verify_templates()
{
    section "Single Disk PXEGrub2 Template Verification"

    if ! api_request GET \
        "${API}/provisioning_templates?per_page=all"
    then

        print_api_error \
            GET \
            "${API}/provisioning_templates?per_page=all"

        record_failure "Template verification"

        return

    fi

    printf '%s\n' "$API_BODY" |
        "$JQ" -r \
            --arg C7 "$CENTOS_SINGLE_TEMPLATE" \
            --arg R8 "$ROCKY8_SINGLE_TEMPLATE" \
            --arg R92 "$ROCKY92_SINGLE_TEMPLATE" \
            --arg R98 "$ROCKY98_SINGLE_TEMPLATE" \
            '
            (.results // [])[]
            | select(
                .name == $C7
                or
                .name == $R8
                or
                .name == $R92
                or
                .name == $R98
            )
            | [
                .id,
                .name,
                (.template_kind_id // ""),
                (.template_kind_name // "")
            ]
            | @tsv
            '
}

###############################################################################
# SELECTED CONFIGURATION
###############################################################################

selected_configuration()
{
    section "Selected Single Disk Configuration"

    echo
    echo "TARGET_VERSION : ${TARGET_VERSION}"
    echo
    echo "Operating System : ${ROCKY_OS}"
    echo "PXE Template     : ${ROCKY_TEMPLATE}"
    echo "Template File    : ${ROCKY_TEMPLATE_FILE}"
    echo "Kernel           : ${ROCKY_KERNEL}"
    echo "Initrd           : ${ROCKY_INITRD}"
    echo "Repository       : ${ROCKY_REPO}"
    echo "Kickstart        : ${ROCKY_KS}"
    echo
}

###############################################################################
# MANUAL VERIFICATION COMMANDS
###############################################################################

manual_verification()
{
    section "Manual Verification Commands"

    echo
    echo "1. Foreman API Status:"
    echo
    echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/status' | jq"

    echo
    echo "2. Single Disk Operating Systems:"
    echo
    echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/operatingsystems?per_page=all' | jq -r '.results[] | [.id,.name,.major,.minor,.family] | @tsv'"

    echo
    echo "3. Single Disk PXEGrub2 Templates:"
    echo
    echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/provisioning_templates?per_page=all' | jq -r '.results[] | select(.template_kind_name==\"PXEGrub2\") | [.id,.name,.template_kind_id,.template_kind_name] | @tsv'"

    echo
    echo "4. CentOS 7 Single Disk Association:"
    echo
    echo "OS_ID=\$(curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/operatingsystems?per_page=all' | jq -r '.results[] | select(.name==\"${CENTOS_SINGLE_OS}\") | .id')"
    echo
    echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/operatingsystems/\${OS_ID}/provisioning_templates?per_page=all' | jq"

    echo
    echo "5. Rocky Linux 8.10 Single Disk Association:"
    echo
    echo "OS_ID=\$(curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/operatingsystems?per_page=all' | jq -r '.results[] | select(.name==\"${ROCKY8_SINGLE_OS}\") | .id')"
    echo
    echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/operatingsystems/\${OS_ID}/provisioning_templates?per_page=all' | jq"

    echo
    echo "6. Rocky Linux 9.2 Single Disk Association:"
    echo
    echo "OS_ID=\$(curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/operatingsystems?per_page=all' | jq -r '.results[] | select(.name==\"${ROCKY92_SINGLE_OS}\") | .id')"
    echo
    echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/operatingsystems/\${OS_ID}/provisioning_templates?per_page=all' | jq"

    echo
    echo "7. Rocky Linux 9.8 Single Disk Association:"
    echo
    echo "OS_ID=\$(curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/operatingsystems?per_page=all' | jq -r '.results[] | select(.name==\"${ROCKY98_SINGLE_OS}\") | .id')"
    echo
    echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/operatingsystems/\${OS_ID}/provisioning_templates?per_page=all' | jq"

    echo
    echo "8. Generated PXE files:"
    echo
    echo "ls -lh ${TMP_DIR}/*singledisk.erb"

    echo
}

###############################################################################
# MAIN
###############################################################################

main()
{
    check_dependencies

    header "02 - Foreman PXE Bootstrap - Single Disk - REST API"

    echo
    echo "Foreman URL   : ${FOREMAN_URL}"
    echo "API Version   : 2"
    echo "Target Version: ${TARGET_VERSION}"
    echo

    ###########################################################################
    # API
    ###########################################################################

    test_api

    ###########################################################################
    # TARGET CONFIGURATION
    ###########################################################################

    selected_configuration

    ###########################################################################
    # TEMPLATE KIND
    ###########################################################################

    if ! find_pxegrub2_kind; then

        error "Cannot continue without PXEGrub2 template kind."

        exit 1

    fi

    ###########################################################################
    # GENERATE TEMPLATES
    ###########################################################################

    section "[1/5] Generating Single Disk PXE Templates"

    generate_templates

    ###########################################################################
    # CREATE / UPDATE TEMPLATES
    ###########################################################################

    section "[2/5] Creating / Verifying Single Disk PXE Templates"

    create_single_disk_templates

    ###########################################################################
    # ASSOCIATE TEMPLATES
    ###########################################################################

    section "[3/5] Associating Single Disk Templates"

    associate_single_disk_templates

    ###########################################################################
    # SET DEFAULTS
    ###########################################################################

    section "[4/5] Setting Single Disk PXEGrub2 Defaults"

    set_single_disk_defaults

    ###########################################################################
    # VERIFICATION
    ###########################################################################

    section "[5/5] Verification"

    verify_templates

    verify_operating_systems

    verify_single_disk_mappings

    verify_single_disk_defaults

    verify_generated_files

    ###########################################################################
    # FINAL STATUS
    ###########################################################################

    header "02 - Foreman PXE Bootstrap (Single Disk) Completed"

    if [ "$FAILURES" -eq 0 ]; then

        ok "Single Disk PXE Bootstrap completed successfully."

    else

        error "Bootstrap completed with ${FAILURES} failure(s)."

        warn "Review the errors shown above before provisioning."

    fi

    ###########################################################################
    # MANUAL VERIFICATION
    ###########################################################################

    manual_verification

    ###########################################################################
    # FINAL CONFIGURATION
    ###########################################################################

    section "Expected Single Disk Configuration"

    cat <<EOF

Operating Systems:

${CENTOS_SINGLE_OS}
 |
 +-- ${CENTOS_SINGLE_TEMPLATE}

${ROCKY8_SINGLE_OS}
 |
 +-- ${ROCKY8_SINGLE_TEMPLATE}

${ROCKY92_SINGLE_OS}
 |
 +-- ${ROCKY92_SINGLE_TEMPLATE}

${ROCKY98_SINGLE_OS}
 |
 +-- ${ROCKY98_SINGLE_TEMPLATE}

Selected Rocky Version:
 |
 +-- TARGET_VERSION=${TARGET_VERSION}
 |
 +-- ${ROCKY_OS}
 |
 +-- ${ROCKY_TEMPLATE}
 |
 +-- ${ROCKY_REPO}
 |
 +-- ${ROCKY_KS}

Single Disk Layout:
 |
 +-- EFI
 |
 +-- /boot
 |
 +-- LVM
      |
      +-- /
      +-- swap
      +-- /home

EOF

    ###########################################################################
    # EXIT
    ###########################################################################

    if [ "$FAILURES" -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

###############################################################################
# RUN
###############################################################################

main "$@"
