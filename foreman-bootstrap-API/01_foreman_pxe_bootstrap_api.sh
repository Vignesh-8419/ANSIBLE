#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap - REST API
#
# Foreman:
#   https://cent-07-01.vgs.com
#
# Authentication:
#   User  : admin
#   PAT   : FOREMAN_TOKEN environment variable
#
# This script is SAFE TO RE-RUN.
#
# Existing resources are detected and skipped.
# Existing resources are updated only where required.
# Nothing is deleted.
###############################################################################

set -u
set -o pipefail

###############################################################################
# CONFIGURATION
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
FOREMAN_USER="${FOREMAN_USER:-admin}"

# IMPORTANT:
# Export the PAT before running:
#
# export FOREMAN_TOKEN='YOUR_PAT_HERE'
#
FOREMAN_TOKEN="${FOREMAN_TOKEN:-}"

API="${FOREMAN_URL}/api"

ARCH_NAME="x86_64"
PARTITION_TABLE_NAME="Kickstart default"

TMP_DIR="/tmp/foreman-pxe-bootstrap"

###############################################################################
# COLORS
###############################################################################

RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
MAGENTA='\033[0;35m'

###############################################################################
# COMMAND PATHS
###############################################################################

CURL="$(command -v curl 2>/dev/null || true)"
JQ="$(command -v jq 2>/dev/null || true)"
CAT="$(command -v cat 2>/dev/null || true)"
HEAD="$(command -v head 2>/dev/null || true)"
GREP="$(command -v grep 2>/dev/null || true)"
AWK="$(command -v awk 2>/dev/null || true)"
SED="$(command -v sed 2>/dev/null || true)"
MKDIR="$(command -v mkdir 2>/dev/null || true)"
RM="$(command -v rm 2>/dev/null || true)"
PRINTF="$(command -v printf 2>/dev/null || true)"
DATE="$(command -v date 2>/dev/null || true)"

###############################################################################
# RESULT STATE
###############################################################################

FAILURES=0

API_STATUS=""
API_BODY=""

###############################################################################
# LOGGING
###############################################################################

header()
{
    echo
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${WHITE}$1${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
}

section()
{
    echo
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${WHITE}$1${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
}

subsection()
{
    echo
    echo -e "${BLUE}------------------------------------------------------------${RESET}"
    echo -e "${WHITE}$1${RESET}"
    echo -e "${BLUE}------------------------------------------------------------${RESET}"
}

info()
{
    echo -e "${BLUE}[INFO]${RESET} $1"
}

ok()
{
    echo -e "${GREEN}[OK]${RESET} $1"
}

skip()
{
    echo -e "${YELLOW}[SKIP]${RESET} $1"
}

warn()
{
    echo -e "${YELLOW}[WARN]${RESET} $1"
}

error()
{
    echo -e "${RED}[ERROR]${RESET} $1"
}

record_failure()
{
    FAILURES=$((FAILURES + 1))
}

###############################################################################
# DEPENDENCY CHECK
###############################################################################

check_dependencies()
{
    section "Dependency Check"

    local missing=0

    if [ -n "$CURL" ]; then
        ok "curl found: $CURL"
    else
        error "curl not found"
        missing=1
    fi

    if [ -n "$JQ" ]; then
        ok "jq found: $JQ"
    else
        error "jq not found"
        missing=1
    fi

    if [ -n "$CAT" ]; then
        ok "cat found: $CAT"
    else
        error "cat not found"
        missing=1
    fi

    if [ -n "$HEAD" ]; then
        ok "head found: $HEAD"
    else
        error "head not found"
        missing=1
    fi

    if [ -n "$GREP" ]; then
        ok "grep found: $GREP"
    else
        error "grep not found"
        missing=1
    fi

    if [ -n "$AWK" ]; then
        ok "awk found: $AWK"
    else
        error "awk not found"
        missing=1
    fi

    if [ -n "$SED" ]; then
        ok "sed found: $SED"
    else
        error "sed not found"
        missing=1
    fi

    if [ -n "$MKDIR" ]; then
        ok "mkdir found: $MKDIR"
    else
        error "mkdir not found"
        missing=1
    fi

    if [ -z "$FOREMAN_TOKEN" ]; then
        error "FOREMAN_TOKEN is not set."
        echo
        echo "Run:"
        echo
        echo "export FOREMAN_TOKEN='YOUR_PAT_HERE'"
        echo
        exit 1
    fi

    if [ "$missing" -ne 0 ]; then
        error "Required dependencies are missing."
        exit 1
    fi
}

###############################################################################
# JSON VALIDATION
###############################################################################

json_valid()
{
    local data="$1"

    printf '%s\n' "$data" |
        "$JQ" empty >/dev/null 2>&1
}

###############################################################################
# API REQUEST
#
# Usage:
#   api_request GET URL
#   api_request POST URL JSON
#   api_request PUT URL JSON
###############################################################################

api_request()
{
    local method="$1"
    local url="$2"
    local payload="${3:-}"

    API_STATUS=""
    API_BODY=""

    local response
    local body_file
    local status

    body_file="$(mktemp /tmp/foreman-api-body.XXXXXX 2>/dev/null)"

    if [ -z "$body_file" ]; then
        error "Unable to create temporary API response file."
        return 1
    fi

    if [ "$method" = "GET" ]; then

        response="$(
            "$CURL" \
                -ksS \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                -H 'Accept: application/json,version=2' \
                -H 'Content-Type: application/json' \
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
                -d "$payload" \
                -o "$body_file" \
                -w '%{http_code}' \
                "$url" \
                2>&1
        )"

    fi

    status="$response"

    if [ -f "$body_file" ]; then
        API_BODY="$("$CAT" "$body_file" 2>/dev/null)"
    fi

    "$RM" -f "$body_file" 2>/dev/null || true

    if [[ "$status" =~ ^[0-9]{3}$ ]]; then
        API_STATUS="$status"
    else
        API_STATUS=""
        API_BODY="$response"
        return 1
    fi

    if [[ "$API_STATUS =~ ^2[0-9][0-9]$ ]]; then
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
}

###############################################################################
# EXACT NAME LOOKUP
#
# IMPORTANT:
# We deliberately do NOT use:
#
#   ?search=<name>
#
# because the earlier script failed to reliably find existing resources.
#
# Instead:
#
#   GET all
#   exact jq .name comparison
###############################################################################

find_id_by_name()
{
    local endpoint="$1"
    local name="$2"

    api_request GET "${API}/${endpoint}?per_page=all" || return 1

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

    echo "Foreman Version : ${version}"
    echo "API Version     : ${api_version}"
    echo "API Status      : ${API_STATUS}"
}

###############################################################################
# ARCHITECTURE
###############################################################################

ARCH_ID=""

find_architecture()
{
    section "Finding Architecture"

    ARCH_ID="$(find_id_by_name architectures "$ARCH_NAME" || true)"

    if [ -n "$ARCH_ID" ]; then
        ok "${ARCH_NAME} architecture found. ID=${ARCH_ID}"
    else
        error "${ARCH_NAME} architecture not found."
        record_failure "Architecture"
    fi
}

###############################################################################
# PARTITION TABLE
###############################################################################

PARTITION_TABLE_ID=""

find_partition_table()
{
    section "Finding Partition Table"

    PARTITION_TABLE_ID="$(
        find_id_by_name ptables "$PARTITION_TABLE_NAME" || true
    )"

    if [ -n "$PARTITION_TABLE_ID" ]; then
        ok "${PARTITION_TABLE_NAME} partition table found. ID=${PARTITION_TABLE_ID}"
    else
        error "${PARTITION_TABLE_NAME} partition table not found."
        record_failure "Partition table"
    fi
}

###############################################################################
# INSTALLATION MEDIA
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

MEDIA_IDS=()

create_or_verify_media()
{
    section "Creating / Verifying Installation Media"

    local i
    local name
    local path
    local id
    local json
    local current_path

    MEDIA_IDS=()

    for i in "${!MEDIA_NAMES[@]}"
    do
        name="${MEDIA_NAMES[$i]}"
        path="${MEDIA_PATHS[$i]}"

        subsection "Installation Media : ${name}"

        #######################################################################
        # EXACT LOOKUP
        #######################################################################

        id="$(find_id_by_name media "$name" || true)"

        if [ -n "$id" ] && [ "$id" != "null" ]; then

            MEDIA_IDS[$i]="$id"

            skip "${name} already exists. ID=${id}"

            ###################################################################
            # Verify path
            ###################################################################

            if api_request GET "${API}/media/${id}"; then

                current_path="$(
                    printf '%s\n' "$API_BODY" |
                    "$JQ" -r '.path // empty'
                )"

                if [ "$current_path" = "$path" ]; then

                    ok "${name} path verified."

                else

                    warn "${name} path differs."
                    echo "Existing : ${current_path}"
                    echo "Expected : ${path}"

                    json="$(
                        "$JQ" -n \
                            --arg path "$path" \
                            '{
                                medium: {
                                    path: $path
                                }
                            }'
                    )"

                    if api_request PUT "${API}/media/${id}" "$json"; then
                        ok "${name} path updated."
                    else
                        print_api_error PUT "${API}/media/${id}"
                        record_failure "${name} media update"
                    fi
                fi

            else

                warn "Unable to verify ${name}."

            fi

            continue
        fi

        #######################################################################
        # CREATE
        #######################################################################

        info "Creating ${name}"

        json="$(
            "$JQ" -n \
                --arg name "$name" \
                --arg path "$path" \
                '{
                    medium: {
                        name: $name,
                        path: $path
                    }
                }'
        )"

        if api_request POST "${API}/media" "$json"; then

            id="$(
                printf '%s\n' "$API_BODY" |
                "$JQ" -r '.id // empty'
            )"

            MEDIA_IDS[$i]="$id"

            ok "${name} created. ID=${id}"

        else

            ###################################################################
            # If Foreman returns 422, perform exact lookup again.
            ###################################################################

            if [ "$API_STATUS" = "422" ]; then

                id="$(find_id_by_name media "$name" || true)"

                if [ -n "$id" ]; then

                    MEDIA_IDS[$i]="$id"

                    skip "${name} already exists. Recovered ID=${id}"

                else

                    print_api_error POST "${API}/media"
                    record_failure "${name} media creation"

                fi

            else

                print_api_error POST "${API}/media"
                record_failure "${name} media creation"

            fi
        fi
    done
}

###############################################################################
# MEDIA VERIFICATION
###############################################################################

verify_media()
{
    section "Installation Media Verification"

    api_request GET "${API}/media?per_page=all" || {
        print_api_error GET "${API}/media?per_page=all"
        return
    }

    printf '%s\n' "$API_BODY" |
        "$JQ" -r '
        (.results // [])[]
        | [.id,.name,.path]
        | @tsv
        '
}

###############################################################################
# OPERATING SYSTEM CONFIGURATION
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

OS_MAJOR=(
    "7"
    "7"
    "8"
    "8"
    "9"
    "9"
    "9"
    "9"
)

OS_MINOR=(
    ""
    ""
    "10"
    "10"
    "2"
    "2"
    "8"
    "8"
)

OS_MEDIA_NAMES=(
    "CentOS 7 Remote"
    "CentOS 7 Remote"
    "Rocky 8 Remote"
    "Rocky 8 Remote"
    "Rocky 9.2 Remote"
    "Rocky 9.2 Remote"
    "Rocky 9 Remote"
    "Rocky 9 Remote"
)

OS_IDS=()

###############################################################################
# MEDIA ID FOR OS
###############################################################################

get_media_id_for_name()
{
    local name="$1"
    local id

    id="$(find_id_by_name media "$name" || true)"

    if [ -n "$id" ]; then
        echo "$id"
        return 0
    fi

    return 1
}

###############################################################################
# CREATE / VERIFY OPERATING SYSTEM
###############################################################################

create_or_verify_os()
{
    section "Creating / Verifying Operating Systems"

    local i
    local name
    local major
    local minor
    local media_name
    local media_id
    local os_id
    local json

    OS_IDS=()

    for i in "${!OS_NAMES[@]}"
    do
        name="${OS_NAMES[$i]}"
        major="${OS_MAJOR[$i]}"
        minor="${OS_MINOR[$i]}"
        media_name="${OS_MEDIA_NAMES[$i]}"

        subsection "Operating System : ${name}"

        os_id="$(find_id_by_name operatingsystems "$name" || true)"

        #######################################################################
        # EXISTING OS
        #######################################################################

        if [ -n "$os_id" ] && [ "$os_id" != "null" ]; then

            OS_IDS[$i]="$os_id"

            skip "${name} already exists. ID=${os_id}"

            continue
        fi

        #######################################################################
        # MEDIA
        #######################################################################

        media_id="$(get_media_id_for_name "$media_name" || true)"

        if [ -z "$media_id" ]; then

            error "Installation media not found : ${media_name}"
            record_failure "${name} media"

            OS_IDS[$i]=""

            continue
        fi

        #######################################################################
        # CREATE OS
        #######################################################################

        info "Creating ${name}"

        if [ -n "$minor" ]; then

            json="$(
                "$JQ" -n \
                    --arg name "$name" \
                    --arg major "$major" \
                    --arg minor "$minor" \
                    --argjson arch "$ARCH_ID" \
                    --argjson media "$media_id" \
                    --argjson pt "$PARTITION_TABLE_ID" \
                    '{
                        operatingsystem: {
                            name: $name,
                            major: $major,
                            minor: $minor,
                            family: "Redhat",
                            architecture_ids: [$arch],
                            media_ids: [$media],
                            ptables: [$pt]
                        }
                    }'
            )"

        else

            json="$(
                "$JQ" -n \
                    --arg name "$name" \
                    --arg major "$major" \
                    --argjson arch "$ARCH_ID" \
                    --argjson media "$media_id" \
                    --argjson pt "$PARTITION_TABLE_ID" \
                    '{
                        operatingsystem: {
                            name: $name,
                            major: $major,
                            family: "Redhat",
                            architecture_ids: [$arch],
                            media_ids: [$media],
                            ptables: [$pt]
                        }
                    }'
            )"

        fi

        if api_request POST "${API}/operatingsystems" "$json"; then

            os_id="$(
                printf '%s\n' "$API_BODY" |
                "$JQ" -r '.id // empty'
            )"

            OS_IDS[$i]="$os_id"

            ok "${name} created. ID=${os_id}"

        else

            ###################################################################
            # 422 = somebody already created it / stale lookup.
            ###################################################################

            if [ "$API_STATUS" = "422" ]; then

                os_id="$(find_id_by_name operatingsystems "$name" || true)"

                if [ -n "$os_id" ]; then

                    OS_IDS[$i]="$os_id"

                    skip "${name} already exists. Recovered ID=${os_id}"

                else

                    print_api_error POST "${API}/operatingsystems"
                    record_failure "${name} creation"

                fi

            else

                print_api_error POST "${API}/operatingsystems"
                record_failure "${name} creation"

            fi
        fi
    done
}

###############################################################################
# OS VERIFICATION
###############################################################################

verify_operating_systems()
{
    section "Operating System Verification"

    api_request GET "${API}/operatingsystems?per_page=all" || {
        print_api_error GET "${API}/operatingsystems?per_page=all"
        return
    }

    printf '%s\n' "$API_BODY" |
        "$JQ" -r '
        [
            (.results // [])[]
            | select(.family == "Redhat")
            | [.id,.name,.major,.minor,.family]
        ][]
        | @tsv
        '
}

###############################################################################
# PXE TEMPLATE CONTENT
#
# IMPORTANT:
# These are generated using printf rather than a quoted heredoc.
# This avoids the previous "bad substitution" and unexpected EOF problems.
###############################################################################

TEMPLATE_DIR="${TMP_DIR}"

generate_templates()
{
    section "Generating PXEGrub2 Template Files"

    "$MKDIR" -p "$TEMPLATE_DIR"

    ###########################################################################
    # CENTOS RAID
    ###########################################################################

    "$CAT" > "${TEMPLATE_DIR}/centos-raid.erb" <<'EOF_CENTOS_RAID'
set default=0
set timeout=10

menuentry 'CentOS 7 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF_CENTOS_RAID

    ###########################################################################
    # CENTOS SINGLE DISK
    ###########################################################################

    "$CAT" > "${TEMPLATE_DIR}/centos-singledisk.erb" <<'EOF_CENTOS_SINGLE'
set default=0
set timeout=10

menuentry 'CentOS 7 SingleDisk' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF_CENTOS_SINGLE

    ###########################################################################
    # ROCKY 8 RAID
    ###########################################################################

    "$CAT" > "${TEMPLATE_DIR}/rocky8-raid.erb" <<'EOF_ROCKY8_RAID'
set default=0
set timeout=10

menuentry 'Rocky Linux 8 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF_ROCKY8_RAID

    ###########################################################################
    # ROCKY 8 SINGLE DISK
    ###########################################################################

    "$CAT" > "${TEMPLATE_DIR}/rocky8-singledisk.erb" <<'EOF_ROCKY8_SINGLE'
set default=0
set timeout=10

menuentry 'Rocky Linux 8 SingleDisk' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF_ROCKY8_SINGLE

    ###########################################################################
    # ROCKY 9.2 RAID
    ###########################################################################

    "$CAT" > "${TEMPLATE_DIR}/rocky92-raid.erb" <<'EOF_ROCKY92_RAID'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.2 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF_ROCKY92_RAID

    ###########################################################################
    # ROCKY 9.2 SINGLE DISK
    ###########################################################################

    "$CAT" > "${TEMPLATE_DIR}/rocky92-singledisk.erb" <<'EOF_ROCKY92_SINGLE'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.2 SingleDisk' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF_ROCKY92_SINGLE

    ###########################################################################
    # ROCKY 9.8 RAID
    ###########################################################################

    "$CAT" > "${TEMPLATE_DIR}/rocky98-raid.erb" <<'EOF_ROCKY98_RAID'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.8 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF_ROCKY98_RAID

    ###########################################################################
    # ROCKY 9.8 SINGLE DISK
    ###########################################################################

    "$CAT" > "${TEMPLATE_DIR}/rocky98-singledisk.erb" <<'EOF_ROCKY98_SINGLE'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.8 SingleDisk' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF_ROCKY98_SINGLE

    ok "All 8 PXEGrub2 template files generated."

    ls -l "$TEMPLATE_DIR"/*.erb
}

###############################################################################
# TEMPLATE CONFIGURATION
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
    "centos-raid.erb"
    "centos-singledisk.erb"
    "rocky8-raid.erb"
    "rocky8-singledisk.erb"
    "rocky92-raid.erb"
    "rocky92-singledisk.erb"
    "rocky98-raid.erb"
    "rocky98-singledisk.erb"
)

TEMPLATE_IDS=()

PXEGRUB2_KIND_ID=""

###############################################################################
# FIND PXEGRUB2 TEMPLATE KIND
###############################################################################

find_pxegrub2_kind()
{
    section "Finding Existing PXEGrub2 Template Kind"

    local kind_id

    ###########################################################################
    # First inspect provisioning templates that already have PXEGrub2.
    ###########################################################################

    api_request GET \
        "${API}/provisioning_templates?per_page=all" || {
        print_api_error GET "${API}/provisioning_templates?per_page=all"
        return 1
    }

    kind_id="$(
        printf '%s\n' "$API_BODY" |
        "$JQ" -r '
        (.results // [])[]
        | select(.template_kind_name == "PXEGrub2")
        | .template_kind_id
        ' |
        "$HEAD" -1
    )"

    ###########################################################################
    # Fallback: template kind endpoint.
    ###########################################################################

    if [ -z "$kind_id" ] || [ "$kind_id" = "null" ]; then

        api_request GET \
            "${API}/provisioning_template_kinds?per_page=all" || true

        if json_valid "$API_BODY"; then

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

    if [ -n "$kind_id" ] && [ "$kind_id" != "null" ]; then

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
# CREATE / UPDATE PROVISIONING TEMPLATE
###############################################################################

create_or_update_template()
{
    local name="$1"
    local filename="$2"

    local template_id
    local template_text
    local json

    subsection "PXEGrub2 Template : ${name}"

    if [ ! -f "${TEMPLATE_DIR}/${filename}" ]; then
        error "Template file missing: ${filename}"
        record_failure "${name} file"
        return
    fi

    template_text="$("$CAT" "${TEMPLATE_DIR}/${filename}")"

    template_id="$(
        find_id_by_name provisioning_templates "$name" || true
    )"

    ###########################################################################
    # EXISTING TEMPLATE
    ###########################################################################

    if [ -n "$template_id" ] && [ "$template_id" != "null" ]; then

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
            "$json"; then

            ok "${name} updated."

        else

            print_api_error \
                PUT \
                "${API}/provisioning_templates/${template_id}"

            record_failure "${name} update"
        fi

        TEMPLATE_IDS+=("$template_id")

        return
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
        "$json"; then

        template_id="$(
            printf '%s\n' "$API_BODY" |
            "$JQ" -r '.id // empty'
        )"

        TEMPLATE_IDS+=("$template_id")

        ok "${name} created. ID=${template_id}"

    else

        if [ "$API_STATUS" = "422" ]; then

            template_id="$(
                find_id_by_name provisioning_templates "$name" || true
            )"

            if [ -n "$template_id" ]; then

                TEMPLATE_IDS+=("$template_id")

                skip "${name} already exists. Recovered ID=${template_id}"

            else

                print_api_error \
                    POST \
                    "${API}/provisioning_templates"

                record_failure "${name} creation"
            fi

        else

            print_api_error \
                POST \
                "${API}/provisioning_templates"

            record_failure "${name} creation"
        fi
    fi
}

###############################################################################
# CREATE / VERIFY ALL TEMPLATES
###############################################################################

create_or_verify_templates()
{
    section "Creating / Verifying PXEGrub2 Templates"

    TEMPLATE_IDS=()

    local i

    if [ -z "$PXEGRUB2_KIND_ID" ]; then
        error "PXEGrub2 kind ID unavailable."
        record_failure "PXEGrub2 templates"
        return
    fi

    for i in "${!TEMPLATE_NAMES[@]}"
    do
        create_or_update_template \
            "${TEMPLATE_NAMES[$i]}" \
            "${TEMPLATE_FILES[$i]}"
    done
}

###############################################################################
# GET TEMPLATE ID
###############################################################################

get_template_id()
{
    local name="$1"

    find_id_by_name provisioning_templates "$name" || true
}

###############################################################################
# ASSOCIATE TEMPLATE WITH OS
###############################################################################

associate_template()
{
    local os_name="$1"
    local os_id="$2"
    local template_name="$3"
    local template_id="$4"

    local json

    subsection "OS Template Association"

    echo "OS       : ${os_name}"
    echo "OS ID    : ${os_id}"
    echo "Template : ${template_name}"
    echo "Template ID : ${template_id}"

    ###########################################################################
    # Check existing association
    ###########################################################################

    if api_request GET \
        "${API}/operatingsystems/${os_id}/provisioning_templates"; then

        if printf '%s\n' "$API_BODY" |
            "$JQ" -e \
                --argjson ID "$template_id" \
                '
                (.results // [])
                | any(.[]; .id == $ID)
                ' >/dev/null 2>&1
        then

            skip "${os_name} already associated with ${template_name}."
            return
        fi

    fi

    ###########################################################################
    # Create association
    ###########################################################################

    json="$(
        "$JQ" -n \
            --argjson id "$template_id" \
            '{
                provisioning_template_id: $id
            }'
    )"

    if api_request POST \
        "${API}/operatingsystems/${os_id}/provisioning_templates" \
        "$json"; then

        ok "${os_name} associated with ${template_name}."

        return
    fi

    ###########################################################################
    # Some Foreman versions use PUT for this relationship.
    ###########################################################################

    if [ "$API_STATUS" = "422" ] || [ "$API_STATUS" = "409" ]; then

        json="$(
            "$JQ" -n \
                --argjson id "$template_id" \
                '{
                    provisioning_template_id: $id
                }'
        )"

        if api_request PUT \
            "${API}/operatingsystems/${os_id}/provisioning_templates/${template_id}" \
            "$json"; then

            ok "${os_name} associated with ${template_name}."
            return
        fi
    fi

    ###########################################################################
    # If it is already associated, treat as SKIP.
    ###########################################################################

    if [ "$API_STATUS" = "422" ]; then

        if api_request GET \
            "${API}/operatingsystems/${os_id}/provisioning_templates"; then

            if printf '%s\n' "$API_BODY" |
                "$JQ" -e \
                    --argjson ID "$template_id" \
                    '
                    (.results // [])
                    | any(.[]; .id == $ID)
                    ' >/dev/null 2>&1
            then

                skip "${os_name} already associated with ${template_name}."
                return
            fi
        fi
    fi

    print_api_error \
        POST \
        "${API}/operatingsystems/${os_id}/provisioning_templates"

    record_failure "${os_name} association"
}

###############################################################################
# ASSOCIATE ALL OS TEMPLATES
###############################################################################

associate_all_templates()
{
    section "Associating PXEGrub2 Templates"

    local i
    local os_name
    local os_id
    local template_name
    local template_id

    for i in "${!OS_NAMES[@]}"
    do
        os_name="${OS_NAMES[$i]}"
        os_id="${OS_IDS[$i]:-}"
        template_name="${TEMPLATE_NAMES[$i]}"

        subsection "Associating:"

        echo "OS       : ${os_name}"
        echo "Template : ${template_name}"

        if [ -z "$os_id" ]; then
            error "OS ID unavailable : ${os_name}"
            record_failure "${os_name} association"
            continue
        fi

        template_id="$(get_template_id "$template_name")"

        if [ -z "$template_id" ]; then
            error "Template not found : ${template_name}"
            record_failure "${template_name} association"
            continue
        fi

        associate_template \
            "$os_name" \
            "$os_id" \
            "$template_name" \
            "$template_id"
    done
}

###############################################################################
# PXE DEFAULT TEMPLATE
###############################################################################

set_pxe_default()
{
    local os_name="$1"
    local os_id="$2"
    local template_name="$3"
    local template_id="$4"

    local json
    local existing_id
    local existing_template
    local existing_kind

    subsection "PXEGrub2 Default Template"

    echo "OS       : ${os_name}"
    echo "OS ID    : ${os_id}"
    echo "Template : ${template_name}"
    echo "Template ID : ${template_id}"
    echo "Kind ID   : ${PXEGRUB2_KIND_ID}"

    ###########################################################################
    # Existing defaults
    ###########################################################################

    if api_request GET \
        "${API}/operatingsystems/${os_id}/os_default_templates"; then

        existing_id="$(
            printf '%s\n' "$API_BODY" |
            "$JQ" -r \
                --argjson KIND "$PXEGRUB2_KIND_ID" \
                --argjson TEMPLATE "$template_id" \
                '
                (.results // [])
                | .[]
                | select(
                    (.template_kind_id == $KIND)
                    or
                    (.template_kind_name == "PXEGrub2")
                )
                | select(.provisioning_template_id == $TEMPLATE)
                | .id
                ' |
            "$HEAD" -1
        )"

        if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then

            skip "PXEGrub2 default already correct. ID=${existing_id}"
            return
        fi

        #######################################################################
        # Find existing PXEGrub2 default even if template differs.
        #######################################################################

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
    fi

    ###########################################################################
    # Update existing default
    ###########################################################################

    if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then

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

        if api_request PUT \
            "${API}/operatingsystems/${os_id}/os_default_templates/${existing_id}" \
            "$json"; then

            ok "PXEGrub2 default updated. ID=${existing_id}"

        else

            print_api_error \
                PUT \
                "${API}/operatingsystems/${os_id}/os_default_templates/${existing_id}"

            record_failure "${os_name} default update"
        fi

        return
    fi

    ###########################################################################
    # Create default
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

    if api_request POST \
        "${API}/operatingsystems/${os_id}/os_default_templates" \
        "$json"; then

        existing_id="$(
            printf '%s\n' "$API_BODY" |
            "$JQ" -r '.id // empty'
        )"

        ok "PXEGrub2 default created. ID=${existing_id}"

    else

        #######################################################################
        # Race / duplicate protection.
        #######################################################################

        if [ "$API_STATUS" = "422" ]; then

            if api_request GET \
                "${API}/operatingsystems/${os_id}/os_default_templates"; then

                existing_id="$(
                    printf '%s\n' "$API_BODY" |
                    "$JQ" -r \
                        --argjson TEMPLATE "$template_id" \
                        --argjson KIND "$PXEGRUB2_KIND_ID" \
                        '
                        (.results // [])
                        | .[]
                        | select(
                            .provisioning_template_id == $TEMPLATE
                            and
                            .template_kind_id == $KIND
                        )
                        | .id
                        ' |
                    "$HEAD" -1
                )"

                if [ -n "$existing_id" ]; then

                    skip "PXEGrub2 default already exists. ID=${existing_id}"
                    return
                fi
            fi
        fi

        print_api_error \
            POST \
            "${API}/operatingsystems/${os_id}/os_default_templates"

        record_failure "${os_name} default"
    fi
}

###############################################################################
# SET ALL DEFAULTS
###############################################################################

set_all_pxe_defaults()
{
    section "Setting PXEGrub2 Default Templates"

    local i
    local os_name
    local os_id
    local template_name
    local template_id

    for i in "${!OS_NAMES[@]}"
    do
        os_name="${OS_NAMES[$i]}"
        os_id="${OS_IDS[$i]:-}"
        template_name="${TEMPLATE_NAMES[$i]}"

        if [ -z "$os_id" ]; then
            error "OS ID unavailable : ${os_name}"
            record_failure "${os_name} default"
            continue
        fi

        template_id="$(get_template_id "$template_name")"

        if [ -z "$template_id" ]; then
            error "Template not found : ${template_name}"
            record_failure "${template_name} default"
            continue
        fi

        set_pxe_default \
            "$os_name" \
            "$os_id" \
            "$template_name" \
            "$template_id"
    done
}

###############################################################################
# SUBNET CONFIGURATION
###############################################################################

SUBNET_NAMES=(
    "vgs-subnet-centos"
    "vgs-subnet-rockyos"
)

SUBNET_NETWORKS=(
    "192.168.253.0"
    "192.168.253.0"
)

SUBNET_MASKS=(
    "255.255.255.0"
    "255.255.255.0"
)

SUBNET_GATEWAYS=(
    "192.168.253.2"
    "192.168.253.2"
)

SUBNET_DNS=(
    "192.168.253.1"
    "192.168.253.1"
)

SUBNET_TFTP_PROXIES=(
    "cent-07-01.vgs.com"
    "cent-07-02.vgs.com"
)

SUBNET_DHCP_PROXIES=(
    "cent-07-01.vgs.com"
    "cent-07-02.vgs.com"
)

###############################################################################
# DOMAIN ID
###############################################################################

DOMAIN_ID=""

find_domain()
{
    DOMAIN_ID="$(find_id_by_name domains "vgs.com" || true)"

    if [ -n "$DOMAIN_ID" ]; then
        ok "Domain found : vgs.com ID=${DOMAIN_ID}"
    else
        error "Domain not found : vgs.com"
        record_failure "Domain"
    fi
}

###############################################################################
# SMART PROXY ID
###############################################################################

get_smart_proxy_id()
{
    local name="$1"

    find_id_by_name smart_proxies "$name" || true
}

###############################################################################
# CREATE / UPDATE SUBNET
###############################################################################

create_or_update_subnet()
{
    local i="$1"

    local name
    local network
    local mask
    local gateway
    local dns
    local tftp_name
    local dhcp_name

    local subnet_id
    local tftp_id
    local dhcp_id

    local json

    name="${SUBNET_NAMES[$i]}"
    network="${SUBNET_NETWORKS[$i]}"
    mask="${SUBNET_MASKS[$i]}"
    gateway="${SUBNET_GATEWAYS[$i]}"
    dns="${SUBNET_DNS[$i]}"
    tftp_name="${SUBNET_TFTP_PROXIES[$i]}"
    dhcp_name="${SUBNET_DHCP_PROXIES[$i]}"

    subsection "Subnet : ${name}"

    echo "Network      : ${network}"
    echo "Mask         : ${mask}"
    echo "Gateway      : ${gateway}"
    echo "DNS          : ${dns}"
    echo "TFTP Proxy   : ${tftp_name}"
    echo "DHCP Proxy   : ${dhcp_name}"

    ###########################################################################
    # Domain
    ###########################################################################

    if [ -z "$DOMAIN_ID" ]; then
        find_domain
    fi

    if [ -z "$DOMAIN_ID" ]; then
        error "Domain ID unavailable."
        record_failure "${name} domain"
        return
    fi

    ###########################################################################
    # TFTP proxy
    ###########################################################################

    tftp_id="$(get_smart_proxy_id "$tftp_name")"

    if [ -n "$tftp_id" ]; then
        ok "TFTP proxy found : ${tftp_name} ID=${tftp_id}"
    else
        error "TFTP proxy not found : ${tftp_name}"
        record_failure "${name} TFTP proxy"
        return
    fi

    ###########################################################################
    # DHCP proxy
    ###########################################################################

    dhcp_id="$(get_smart_proxy_id "$dhcp_name")"

    if [ -n "$dhcp_id" ]; then
        ok "DHCP proxy found : ${dhcp_name} ID=${dhcp_id}"
    else
        error "DHCP proxy not found : ${dhcp_name}"
        record_failure "${name} DHCP proxy"
        return
    fi

    ###########################################################################
    # Existing subnet
    ###########################################################################

    subnet_id="$(find_id_by_name subnets "$name" || true)"

    json="$(
        "$JQ" -n \
            --arg name "$name" \
            --arg network "$network" \
            --arg mask "$mask" \
            --arg gateway "$gateway" \
            --arg dns "$dns" \
            --argjson domain "$DOMAIN_ID" \
            --argjson tftp "$tftp_id" \
            --argjson dhcp "$dhcp_id" \
            '{
                subnet: {
                    name: $name,
                    network: $network,
                    mask: $mask,
                    gateway: $gateway,
                    dns_primary: $dns,
                    domain_ids: [$domain],
                    tftp_id: $tftp,
                    dhcp_id: $dhcp
                }
            }'
    )"

    ###########################################################################
    # UPDATE
    ###########################################################################

    if [ -n "$subnet_id" ]; then

        skip "${name} already exists. ID=${subnet_id}"

        if api_request PUT \
            "${API}/subnets/${subnet_id}" \
            "$json"; then

            ok "${name} updated."

        else

            print_api_error PUT "${API}/subnets/${subnet_id}"
            record_failure "${name} update"
        fi

        return
    fi

    ###########################################################################
    # CREATE
    ###########################################################################

    info "Creating ${name}"

    if api_request POST "${API}/subnets" "$json"; then

        subnet_id="$(
            printf '%s\n' "$API_BODY" |
            "$JQ" -r '.id // empty'
        )"

        ok "${name} created. ID=${subnet_id}"

    else

        if [ "$API_STATUS" = "422" ]; then

            subnet_id="$(find_id_by_name subnets "$name" || true)"

            if [ -n "$subnet_id" ]; then

                skip "${name} already exists. Recovered ID=${subnet_id}"

            else

                print_api_error POST "${API}/subnets"
                record_failure "${name} creation"
            fi

        else

            print_api_error POST "${API}/subnets"
            record_failure "${name} creation"

        fi
    fi
}

###############################################################################
# CREATE ALL SUBNETS
###############################################################################

create_subnets()
{
    section "Creating / Verifying PXE Subnets"

    find_domain

    local i

    for i in "${!SUBNET_NAMES[@]}"
    do
        create_or_update_subnet "$i"
    done
}

###############################################################################
# SUBNET VERIFICATION
###############################################################################

verify_subnets()
{
    section "PXE Subnet Verification"

    api_request GET "${API}/subnets?per_page=all" || {
        print_api_error GET "${API}/subnets?per_page=all"
        return
    }

    printf '%s\n' "$API_BODY" |
        "$JQ" -r '
        (.results // [])[]
        | select(.name == "vgs-subnet-centos"
                 or .name == "vgs-subnet-rockyos")
        | [
            .id,
            .name,
            (.network // ""),
            (.mask // ""),
            (.tftp_proxy.name // ""),
            (.dhcp_proxy.name // "")
          ]
        | @tsv
        '
}

###############################################################################
# PXE TEMPLATE VERIFICATION
###############################################################################

verify_templates()
{
    section "PXEGrub2 Template Verification"

    api_request GET \
        "${API}/provisioning_templates?per_page=all" || {
        print_api_error GET \
            "${API}/provisioning_templates?per_page=all"
        return
    }

    printf '%s\n' "$API_BODY" |
        "$JQ" -r '
        (.results // [])[]
        | select(.template_kind_name == "PXEGrub2")
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
# OS TEMPLATE ASSOCIATION VERIFICATION
###############################################################################

verify_os_associations()
{
    section "OS PXEGrub2 Association Verification"

    local i
    local os_name
    local os_id

    for i in "${!OS_NAMES[@]}"
    do
        os_name="${OS_NAMES[$i]}"
        os_id="${OS_IDS[$i]:-}"

        if [ -z "$os_id" ]; then
            continue
        fi

        echo
        echo -e "${WHITE}${os_name} (ID=${os_id})${RESET}"

        if api_request GET \
            "${API}/operatingsystems/${os_id}/provisioning_templates"; then

            printf '%s\n' "$API_BODY" |
                "$JQ" -r '
                (.results // [])[]
                | select(.template_kind_name == "PXEGrub2")
                | [
                    .id,
                    .name,
                    (.template_kind_id // ""),
                    (.template_kind_name // "")
                  ]
                | @tsv
                '
        else

            warn "Unable to query associations for ${os_name}."

        fi
    done
}

###############################################################################
# PXE DEFAULT VERIFICATION
###############################################################################

verify_defaults()
{
    section "PXEGrub2 Default Verification"

    local i
    local os_name
    local os_id
    local default_data
    local result

    for i in "${!OS_NAMES[@]}"
    do
        os_name="${OS_NAMES[$i]}"
        os_id="${OS_IDS[$i]:-}"

        if [ -z "$os_id" ]; then
            continue
        fi

        if ! api_request GET \
            "${API}/operatingsystems/${os_id}/os_default_templates"; then

            error "${os_name} default query failed."
            continue
        fi

        result="$(
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
                | [
                    .id,
                    (.provisioning_template_id // ""),
                    (.template_kind_id // "")
                ]
                | @tsv
                ' |
            "$HEAD" -1
        )"

        if [ -n "$result" ]; then
            ok "${os_name} PXEGrub2 default: ${result}"
        else
            error "${os_name} PXEGrub2 default not found."
            record_failure "${os_name} default verification"
        fi
    done
}

###############################################################################
# FINAL OS VERIFICATION
###############################################################################

final_os_verification()
{
    section "Final Operating System Verification"

    api_request GET "${API}/operatingsystems?per_page=all" || {
        print_api_error GET "${API}/operatingsystems?per_page=all"
        return
    }

    ###########################################################################
    # IMPORTANT:
    # (.results // []) prevents:
    #
    # jq: Cannot iterate over null
    #
    ###########################################################################

    printf '%s\n' "$API_BODY" |
        "$JQ" -r '
        (.results // [])
        | .[]
        | [
            .id,
            .name,
            (.major // ""),
            (.minor // ""),
            (.family // ""),
            ((.media // [])
                | map(.name)
                | join(", "))
          ]
        | @tsv
        '
}

###############################################################################
# CLEANUP
###############################################################################

cleanup()
{
    :
}

###############################################################################
# MAIN
###############################################################################

main()
{
    check_dependencies

    header "01 - Foreman PXE Bootstrap - REST API"

    test_api

    ###########################################################################
    # MEDIA
    ###########################################################################

    create_or_verify_media
    verify_media

    ###########################################################################
    # ARCH / PTABLE
    ###########################################################################

    find_architecture
    find_partition_table

    if [ -z "$ARCH_ID" ]; then
        error "Cannot continue without architecture."
        exit 1
    fi

    if [ -z "$PARTITION_TABLE_ID" ]; then
        error "Cannot continue without partition table."
        exit 1
    fi

    ###########################################################################
    # OPERATING SYSTEMS
    ###########################################################################

    create_or_verify_os
    verify_operating_systems

    ###########################################################################
    # PXE TEMPLATE FILES
    ###########################################################################

    generate_templates

    ###########################################################################
    # PXEGRUB2 KIND
    ###########################################################################

    if ! find_pxegrub2_kind; then
        error "Cannot continue with PXEGrub2 templates."
        exit 1
    fi

    ###########################################################################
    # TEMPLATES
    ###########################################################################

    create_or_verify_templates

    ###########################################################################
    # ASSOCIATIONS
    ###########################################################################

    associate_all_templates

    ###########################################################################
    # DEFAULTS
    ###########################################################################

    set_all_pxe_defaults

    ###########################################################################
    # SUBNETS
    ###########################################################################

    create_subnets
    verify_subnets

    ###########################################################################
    # VERIFICATION
    ###########################################################################

    verify_templates
    verify_os_associations
    verify_defaults
    final_os_verification

    ###########################################################################
    # FILES
    ###########################################################################

    section "Generated PXE Files"

    ls -lh "${TEMPLATE_DIR}"/*.erb 2>/dev/null || true

    ###########################################################################
    # SUMMARY
    ###########################################################################

    section "01 - Foreman PXE Bootstrap API Completed"

    if [ "$FAILURES" -eq 0 ]; then

        ok "Completed successfully with no failures."

    else

        error "Completed with ${FAILURES} failure(s)."

    fi

    ###########################################################################
    # MANUAL VERIFICATION
    ###########################################################################

    section "Manual Verification Commands"

    echo
    echo "1. Foreman API:"
    echo
    echo 'curl -ksS --user "admin:${FOREMAN_TOKEN}" \'
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/status' | jq"

    echo
    echo "2. Installation Media:"
    echo
    echo 'curl -ksS --user "admin:${FOREMAN_TOKEN}" \'
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/media?per_page=all' | \\"
    echo "  jq -r '.results[] | [.id,.name,.path] | @tsv'"

    echo
    echo "3. Existing PXEGrub2 kind:"
    echo
    echo 'curl -ksS --user "admin:${FOREMAN_TOKEN}" \'
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/provisioning_templates?per_page=all' | \\"
    echo "  jq -r '.results[] | select(.template_kind_name==\"PXEGrub2\") | [.id,.name,.template_kind_id,.template_kind_name] | @tsv'"

    echo
    echo "4. PXE subnets:"
    echo
    echo 'curl -ksS --user "admin:${FOREMAN_TOKEN}" \'
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/subnets?per_page=all' | jq"

    echo
    echo "5. Generated PXE files:"
    echo
    echo "ls -lh ${TEMPLATE_DIR}/*.erb"

    echo
    echo -e "${CYAN}============================================================${RESET}"
}

###############################################################################
# RUN
###############################################################################

main "$@"
