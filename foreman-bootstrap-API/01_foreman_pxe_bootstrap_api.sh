#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap - REST API
#
# Foreman 3.2.1
#
# Creates / verifies:
#   - Installation Media
#   - Architectures / Partition Table
#   - Operating Systems
#   - PXEGrub2 provisioning templates
#   - OS/template associations
#   - PXEGrub2 default templates
#   - PXE subnets
#
# Important:
#   Existing resources are NOT deleted.
#   Existing PXEGrub2 defaults are updated instead of creating duplicates.
###############################################################################

###############################################################################
# CONFIGURATION
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
FOREMAN_USER="${FOREMAN_USER:-admin}"

if [ -z "${FOREMAN_TOKEN:-}" ]; then
    echo
    echo "[ERROR] FOREMAN_TOKEN is not set."
    echo
    echo "Set it first:"
    echo
    echo "export FOREMAN_TOKEN='YOUR_FOREMAN_TOKEN'"
    echo
    exit 1
fi

API="${FOREMAN_URL}/api"

ACCEPT_HEADER="Accept: application/json,version=2"
CONTENT_HEADER="Content-Type: application/json"

TMP_ROOT="/tmp/foreman-pxe-bootstrap"
TEMPLATE_DIR="${TMP_ROOT}/templates"

###############################################################################
# COMMAND PATHS
###############################################################################

CURL="$(command -v curl 2>/dev/null)"
JQ="$(command -v jq 2>/dev/null)"
CAT="$(command -v cat 2>/dev/null)"
HEAD="$(command -v head 2>/dev/null)"
GREP="$(command -v grep 2>/dev/null)"
AWK="$(command -v awk 2>/dev/null)"
SED="$(command -v sed 2>/dev/null)"
MKDIR="$(command -v mkdir 2>/dev/null)"
MKTEMP="$(command -v mktemp 2>/dev/null)"
RM="$(command -v rm 2>/dev/null)"
BASENAME="$(command -v basename 2>/dev/null)"
DATE="$(command -v date 2>/dev/null)"
WC="$(command -v wc 2>/dev/null)"

###############################################################################
# GLOBALS
###############################################################################

API_BODY=""
API_STATUS=""
API_HEADERS=""

ARCH_ID=""
PTABLE_ID=""
PXEGRUB2_KIND_ID=""

FAILURES=()

MEDIA_IDS=()
OS_IDS=()
TEMPLATE_IDS=()

###############################################################################
# OUTPUT FUNCTIONS
###############################################################################

section()
{
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

subsection()
{
    echo
    echo "------------------------------------------------------------"
    echo "$1"
    echo "------------------------------------------------------------"
}

info()
{
    echo "[INFO] $1"
}

ok()
{
    echo "[OK] $1"
}

skip()
{
    echo "[SKIP] $1"
}

warn()
{
    echo "[WARN] $1"
}

error()
{
    echo "[ERROR] $1"
}

record_failure()
{
    FAILURES+=("$1")
}

###############################################################################
# DEPENDENCY CHECK
###############################################################################

check_dependencies()
{
    section "Dependency Check"

    local failed=0
    local cmd
    local name

    for cmd in \
        "$CURL" \
        "$JQ" \
        "$CAT" \
        "$HEAD" \
        "$GREP" \
        "$AWK" \
        "$SED" \
        "$MKDIR" \
        "$MKTEMP" \
        "$RM" \
        "$BASENAME" \
        "$DATE" \
        "$WC"
    do

        if [ -n "$cmd" ] && [ -x "$cmd" ]; then
            name="$("$BASENAME" "$cmd")"
            ok "$name found: $cmd"
        else
            error "Required command not found: $cmd"
            failed=1
        fi

    done

    if [ "$failed" -ne 0 ]; then
        error "Dependency check failed."
        exit 1
    fi
}

###############################################################################
# TEMP DIRECTORY
###############################################################################

prepare_temp()
{
    "$RM" -rf "$TMP_ROOT"
    "$MKDIR" -p "$TMP_ROOT"

    if [ ! -d "$TMP_ROOT" ]; then
        error "Unable to create $TMP_ROOT"
        exit 1
    fi
}

###############################################################################
# JSON VALIDATION
###############################################################################

json_valid()
{
    local file="$1"

    if [ -z "$file" ] || [ ! -s "$file" ]; then
        return 1
    fi

    "$JQ" -e . "$file" >/dev/null 2>&1
}

###############################################################################
# API REQUEST
###############################################################################

api_request()
{
    local method="$1"
    local url="$2"
    local data="${3:-}"

    local body_file
    local header_file
    local curl_rc
    local curl_output

    body_file="$("$MKTEMP" "${TMP_ROOT}/body.XXXXXX")"
    header_file="$("$MKTEMP" "${TMP_ROOT}/header.XXXXXX")"

    if [ -z "$body_file" ] || [ -z "$header_file" ]; then
        error "Unable to create temporary API files."
        return 1
    fi

    if [ -n "$data" ]; then

        curl_output="$(
            "$CURL" \
                --silent \
                --show-error \
                --insecure \
                --request "$method" \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                --header "$ACCEPT_HEADER" \
                --header "$CONTENT_HEADER" \
                --data "$data" \
                --output "$body_file" \
                --dump-header "$header_file" \
                --write-out '%{http_code}' \
                "$url"
        )"

    else

        curl_output="$(
            "$CURL" \
                --silent \
                --show-error \
                --insecure \
                --request "$method" \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                --header "$ACCEPT_HEADER" \
                --output "$body_file" \
                --dump-header "$header_file" \
                --write-out '%{http_code}' \
                "$url"
        )"

    fi

    curl_rc=$?

    API_STATUS="$curl_output"
    API_BODY="$body_file"
    API_HEADERS="$header_file"

    if [ "$curl_rc" -ne 0 ]; then
        error "curl failed."
        error "Method : $method"
        error "URL    : $url"
        return 1
    fi

    if ! [[ "$API_STATUS" =~ ^[0-9]{3}$ ]]; then
        error "Invalid HTTP status: $API_STATUS"
        return 1
    fi

    return 0
}

###############################################################################
# API SUCCESS
###############################################################################

api_success()
{
    [[ "$API_STATUS" =~ ^2[0-9][0-9]$ ]]
}

###############################################################################
# PRINT API ERROR
###############################################################################

print_api_error()
{
    error "API request failed."
    error "HTTP Status : ${API_STATUS}"
    error "Method      : ${1:-UNKNOWN}"
    error "URL         : ${2:-UNKNOWN}"

    if [ -n "$API_BODY" ] && [ -s "$API_BODY" ]; then
        "$JQ" . "$API_BODY" 2>/dev/null || "$CAT" "$API_BODY"
    fi
}

###############################################################################
# GET ID BY NAME
###############################################################################

get_id_by_name()
{
    local endpoint="$1"
    local name="$2"

    api_request GET "${API}${endpoint}?per_page=all" || return 1

    if ! api_success; then
        return 1
    fi

    if ! json_valid "$API_BODY"; then
        return 1
    fi

    "$JQ" -r \
        --arg NAME "$name" \
        '
        (.results // [])[]
        | select(.name == $NAME)
        | .id
        ' \
        "$API_BODY" |
        "$HEAD" -1
}

###############################################################################
# GET RESOURCE IDS
###############################################################################

get_os_id()
{
    get_id_by_name "/operatingsystems" "$1"
}

get_media_id()
{
    get_id_by_name "/media" "$1"
}

get_template_id()
{
    get_id_by_name "/provisioning_templates" "$1"
}

get_domain_id()
{
    get_id_by_name "/domains" "$1"
}

get_proxy_id()
{
    get_id_by_name "/smart_proxies" "$1"
}

###############################################################################
# API AUTHENTICATION TEST
###############################################################################

test_foreman_api()
{
    section "Foreman API Authentication Test"

    info "Testing Foreman REST API..."

    if ! api_request GET "${API}/status"; then
        print_api_error GET "${API}/status"
        exit 1
    fi

    if ! api_success; then
        print_api_error GET "${API}/status"
        exit 1
    fi

    if ! json_valid "$API_BODY"; then
        error "Foreman API returned invalid JSON."
        exit 1
    fi

    local version
    local api_version

    version="$("$JQ" -r '.version // "unknown"' "$API_BODY")"
    api_version="$("$JQ" -r '.api_version // "unknown"' "$API_BODY")"

    ok "Foreman API authentication successful."
    echo "Foreman Version : ${version}"
    echo "API Version     : ${api_version}"
    echo "API Status      : ${API_STATUS}"
}

###############################################################################
# FIND ARCHITECTURE
###############################################################################

find_architecture()
{
    section "Finding Architecture"

    ARCH_ID=""

    api_request GET "${API}/architectures?per_page=all"

    if ! api_success; then
        print_api_error GET "${API}/architectures?per_page=all"
        record_failure "Architecture lookup"
        return
    fi

    ARCH_ID="$(
        "$JQ" -r '
            (.results // [])[]
            | select(.name == "x86_64")
            | .id
        ' "$API_BODY" |
        "$HEAD" -1
    )"

    if [ -n "$ARCH_ID" ] && [ "$ARCH_ID" != "null" ]; then
        ok "x86_64 architecture found. ID=${ARCH_ID}"
    else
        error "x86_64 architecture not found."
        record_failure "x86_64 architecture"
    fi
}

###############################################################################
# FIND PARTITION TABLE
###############################################################################

find_partition_table()
{
    section "Finding Partition Table"

    PTABLE_ID=""

    api_request GET "${API}/ptables?per_page=all"

    if ! api_success; then
        print_api_error GET "${API}/ptables?per_page=all"
        record_failure "Partition table lookup"
        return
    fi

    PTABLE_ID="$(
        "$JQ" -r '
            (.results // [])[]
            | select(
                .name == "Kickstart default"
                or
                .name == "Kickstart default partition table"
            )
            | .id
        ' "$API_BODY" |
        "$HEAD" -1
    )"

    if [ -n "$PTABLE_ID" ] && [ "$PTABLE_ID" != "null" ]; then
        ok "Kickstart default partition table found. ID=${PTABLE_ID}"
    else
        error "Kickstart default partition table not found."
        record_failure "Kickstart partition table"
    fi
}

###############################################################################
# MEDIA DATA
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
# CREATE / VERIFY MEDIA
###############################################################################

create_or_verify_media()
{
    section "Creating / Verifying Installation Media"

    local i
    local name
    local path
    local id
    local json
    local existing_path

    for i in "${!MEDIA_NAMES[@]}"
    do

        name="${MEDIA_NAMES[$i]}"
        path="${MEDIA_PATHS[$i]}"

        subsection "Installation Media : ${name}"

        id="$(get_media_id "$name")"

        if [ -n "$id" ] && [ "$id" != "null" ]; then

            MEDIA_IDS[$i]="$id"

            skip "${name} already exists. ID=${id}"

            api_request GET "${API}/media/${id}"

            if api_success && json_valid "$API_BODY"; then

                existing_path="$("$JQ" -r '.path // ""' "$API_BODY")"

                if [ "$existing_path" = "$path" ]; then

                    ok "${name} path verified."

                else

                    warn "${name} exists with different path."
                    warn "Existing : ${existing_path}"
                    warn "Expected : ${path}"

                    json="$(
                        "$JQ" -n \
                            --arg name "$name" \
                            --arg path "$path" \
                            '{
                                medium: {
                                    name: $name,
                                    path: $path,
                                    os_family: "Redhat"
                                }
                            }'
                    )"

                    api_request PUT "${API}/media/${id}" "$json"

                    if api_success; then
                        ok "${name} path updated."
                    else
                        print_api_error PUT "${API}/media/${id}"
                        record_failure "${name} media update"
                    fi
                fi
            fi

            continue
        fi

        info "Creating ${name}"

        json="$(
            "$JQ" -n \
                --arg name "$name" \
                --arg path "$path" \
                '{
                    medium: {
                        name: $name,
                        path: $path,
                        os_family: "Redhat"
                    }
                }'
        )"

        api_request POST "${API}/media" "$json"

        if api_success && json_valid "$API_BODY"; then

            id="$("$JQ" -r '.id // empty' "$API_BODY")"

            if [ -n "$id" ]; then
                MEDIA_IDS[$i]="$id"
                ok "${name} created. ID=${id}"
            else
                error "${name} created but ID missing."
                record_failure "${name} media creation"
            fi

        else

            print_api_error POST "${API}/media"
            record_failure "${name} media creation"

        fi

    done
}

###############################################################################
# MEDIA VERIFICATION
###############################################################################

verify_media()
{
    section "Installation Media Verification"

    api_request GET "${API}/media?per_page=all"

    if ! api_success || ! json_valid "$API_BODY"; then
        print_api_error GET "${API}/media?per_page=all"
        record_failure "Media verification"
        return
    fi

    "$JQ" -r '
        (.results // [])[]
        | [
            .id,
            .name,
            .path
          ]
        | @tsv
    ' "$API_BODY"
}

###############################################################################
# OPERATING SYSTEM DATA
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

OS_MEDIA_NAME=(
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
# CREATE / VERIFY OS
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

    for i in "${!OS_NAMES[@]}"
    do

        name="${OS_NAMES[$i]}"
        major="${OS_MAJOR[$i]}"
        minor="${OS_MINOR[$i]}"
        media_name="${OS_MEDIA_NAME[$i]}"

        subsection "Operating System : ${name}"

        os_id="$(get_os_id "$name")"

        if [ -n "$os_id" ] && [ "$os_id" != "null" ]; then

            OS_IDS[$i]="$os_id"

            skip "${name} already exists. ID=${os_id}"

            media_id="$(get_media_id "$media_name")"

            if [ -z "$media_id" ] || [ "$media_id" = "null" ]; then
                error "Media ${media_name} not found."
                record_failure "${name} media association"
                continue
            fi

            json="$(
                "$JQ" -n \
                    --argjson arch "$ARCH_ID" \
                    --argjson medium "$media_id" \
                    --argjson ptable "$PTABLE_ID" \
                    '{
                        operatingsystem: {
                            architecture_ids: [$arch],
                            medium_ids: [$medium],
                            ptable_ids: [$ptable]
                        }
                    }'
            )"

            api_request PUT "${API}/operatingsystems/${os_id}" "$json"

            if api_success; then
                ok "${name} associations verified."
            else
                print_api_error PUT "${API}/operatingsystems/${os_id}"
                record_failure "${name} association update"
            fi

            continue
        fi

        info "Creating ${name}"

        media_id="$(get_media_id "$media_name")"

        if [ -z "$media_id" ] || [ "$media_id" = "null" ]; then
            error "Media ${media_name} not found."
            record_failure "${name} media"
            continue
        fi

        if [ -n "$minor" ]; then

            json="$(
                "$JQ" -n \
                    --arg name "$name" \
                    --arg major "$major" \
                    --arg minor "$minor" \
                    --argjson arch "$ARCH_ID" \
                    --argjson medium "$media_id" \
                    --argjson ptable "$PTABLE_ID" \
                    '{
                        operatingsystem: {
                            name: $name,
                            major: $major,
                            minor: $minor,
                            family: "Redhat",
                            password_hash: "SHA256",
                            architecture_ids: [$arch],
                            medium_ids: [$medium],
                            ptable_ids: [$ptable]
                        }
                    }'
            )"

        else

            json="$(
                "$JQ" -n \
                    --arg name "$name" \
                    --arg major "$major" \
                    --argjson arch "$ARCH_ID" \
                    --argjson medium "$media_id" \
                    --argjson ptable "$PTABLE_ID" \
                    '{
                        operatingsystem: {
                            name: $name,
                            major: $major,
                            family: "Redhat",
                            password_hash: "SHA256",
                            architecture_ids: [$arch],
                            medium_ids: [$medium],
                            ptable_ids: [$ptable]
                        }
                    }'
            )"

        fi

        api_request POST "${API}/operatingsystems" "$json"

        if api_success && json_valid "$API_BODY"; then

            os_id="$("$JQ" -r '.id // empty' "$API_BODY")"

            if [ -n "$os_id" ]; then
                OS_IDS[$i]="$os_id"
                ok "${name} created. ID=${os_id}"
            else
                error "${name} created but ID missing."
                record_failure "${name} OS creation"
            fi

        else

            print_api_error POST "${API}/operatingsystems"
            record_failure "${name} OS creation"

        fi

    done
}

###############################################################################
# OS VERIFICATION
###############################################################################

verify_operating_systems()
{
    section "Operating System Verification"

    api_request GET "${API}/operatingsystems?per_page=all"

    if ! api_success || ! json_valid "$API_BODY"; then
        print_api_error GET "${API}/operatingsystems?per_page=all"
        record_failure "OS verification"
        return
    fi

    echo "ID    NAME                                MAJOR   MINOR   FAMILY"

    "$JQ" -r '
        (.results // [])[]
        | [
            .id,
            .name,
            (.major // ""),
            (.minor // ""),
            (.family // "")
          ]
        | @tsv
    ' "$API_BODY"
}

###############################################################################
# PXE TEMPLATE DATA
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

TEMPLATE_OS_INDEX=(
    0
    1
    2
    3
    4
    5
    6
    7
)

###############################################################################
# GENERATE PXE TEMPLATE FILES
###############################################################################

generate_template_files()
{
    section "Generating PXEGrub2 Template Files"

    "$RM" -rf "$TEMPLATE_DIR"
    "$MKDIR" -p "$TEMPLATE_DIR"

    "$CAT" > "${TEMPLATE_DIR}/centos-raid.erb" <<'TEMPLATE_EOF'
set default=0
set timeout=10

menuentry 'CentOS 7 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
TEMPLATE_EOF

    "$CAT" > "${TEMPLATE_DIR}/centos-singledisk.erb" <<'TEMPLATE_EOF'
set default=0
set timeout=10

menuentry 'CentOS 7 SingleDisk' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
TEMPLATE_EOF

    "$CAT" > "${TEMPLATE_DIR}/rocky8-raid.erb" <<'TEMPLATE_EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 8 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
TEMPLATE_EOF

    "$CAT" > "${TEMPLATE_DIR}/rocky8-singledisk.erb" <<'TEMPLATE_EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 8 SingleDisk' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
TEMPLATE_EOF

    "$CAT" > "${TEMPLATE_DIR}/rocky92-raid.erb" <<'TEMPLATE_EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.2 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
TEMPLATE_EOF

    "$CAT" > "${TEMPLATE_DIR}/rocky92-singledisk.erb" <<'TEMPLATE_EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.2 SingleDisk' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
TEMPLATE_EOF

    "$CAT" > "${TEMPLATE_DIR}/rocky98-raid.erb" <<'TEMPLATE_EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.8 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
TEMPLATE_EOF

    "$CAT" > "${TEMPLATE_DIR}/rocky98-singledisk.erb" <<'TEMPLATE_EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.8 SingleDisk' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
TEMPLATE_EOF

    local count

    count="$("$GREP" -l "menuentry" "${TEMPLATE_DIR}"/*.erb 2>/dev/null | "$WC" -l)"

    if [ "$count" -eq 8 ]; then
        ok "All 8 PXEGrub2 template files generated."
    else
        error "Expected 8 PXEGrub2 template files. Found ${count}."
        record_failure "PXE template generation"
    fi

    ls -l "${TEMPLATE_DIR}"/*.erb
}

###############################################################################
# FIND PXEGRUB2 TEMPLATE KIND
###############################################################################

find_pxegrub2_kind()
{
    section "Finding Existing PXEGrub2 Template Kind"

    PXEGRUB2_KIND_ID=""

    api_request GET "${API}/provisioning_templates?per_page=all"

    if ! api_success || ! json_valid "$API_BODY"; then
        print_api_error GET "${API}/provisioning_templates?per_page=all"
        record_failure "PXEGrub2 kind lookup"
        return
    fi

    PXEGRUB2_KIND_ID="$(
        "$JQ" -r '
            (.results // [])[]
            | select(.template_kind_name == "PXEGrub2")
            | .template_kind_id
        ' "$API_BODY" |
        "$HEAD" -1
    )"

    if [ -z "$PXEGRUB2_KIND_ID" ] || [ "$PXEGRUB2_KIND_ID" = "null" ]; then

        PXEGRUB2_KIND_ID="$(
            "$JQ" -r '
                (.results // [])[]
                | select(.name | startswith("PXEGrub2 "))
                | .template_kind_id
            ' "$API_BODY" |
            "$HEAD" -1
        )"

    fi

    if [ -n "$PXEGRUB2_KIND_ID" ] &&
       [ "$PXEGRUB2_KIND_ID" != "null" ]; then

        ok "PXEGrub2 template kind found."
        echo "PXEGrub2 Template Kind ID : ${PXEGRUB2_KIND_ID}"

    else

        error "PXEGrub2 template kind not found."
        record_failure "PXEGrub2 template kind"

    fi
}

###############################################################################
# CREATE / UPDATE PROVISIONING TEMPLATES
###############################################################################

create_or_update_templates()
{
    section "Creating / Verifying PXEGrub2 Templates"

    local i
    local name
    local file
    local template_id
    local template_text
    local json

    if [ -z "$PXEGRUB2_KIND_ID" ]; then
        error "PXEGrub2 template kind ID is empty."
        record_failure "PXEGrub2 templates"
        return
    fi

    for i in "${!TEMPLATE_NAMES[@]}"
    do

        name="${TEMPLATE_NAMES[$i]}"
        file="${TEMPLATE_FILES[$i]}"

        subsection "PXEGrub2 Template : ${name}"

        if [ ! -s "${TEMPLATE_DIR}/${file}" ]; then
            error "Template file missing: ${TEMPLATE_DIR}/${file}"
            record_failure "${name} template file"
            continue
        fi

        template_id="$(get_template_id "$name")"
        template_text="$("$CAT" "${TEMPLATE_DIR}/${file}")"

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

        if [ -n "$template_id" ] && [ "$template_id" != "null" ]; then

            TEMPLATE_IDS[$i]="$template_id"

            skip "${name} already exists. ID=${template_id}"

            api_request PUT \
                "${API}/provisioning_templates/${template_id}" \
                "$json"

            if api_success; then
                ok "${name} updated."
            else
                print_api_error PUT \
                    "${API}/provisioning_templates/${template_id}"
                record_failure "${name} template update"
            fi

        else

            info "Creating ${name}"

            api_request POST \
                "${API}/provisioning_templates" \
                "$json"

            if api_success && json_valid "$API_BODY"; then

                template_id="$("$JQ" -r '.id // empty' "$API_BODY")"

                if [ -n "$template_id" ]; then
                    TEMPLATE_IDS[$i]="$template_id"
                    ok "${name} created. ID=${template_id}"
                else
                    error "${name} created but ID missing."
                    record_failure "${name} template creation"
                fi

            else

                print_api_error POST \
                    "${API}/provisioning_templates"

                record_failure "${name} template creation"

            fi

        fi

    done
}

###############################################################################
# ASSOCIATE TEMPLATES WITH OS
###############################################################################

associate_templates_with_os()
{
    section "Associating PXEGrub2 Templates With Operating Systems"

    local i
    local os_index
    local os_name
    local os_id
    local template_name
    local template_id
    local existing_ids
    local ids_json
    local json

    for i in "${!TEMPLATE_NAMES[@]}"
    do

        template_name="${TEMPLATE_NAMES[$i]}"
        template_id="${TEMPLATE_IDS[$i]}"
        os_index="${TEMPLATE_OS_INDEX[$i]}"
        os_name="${OS_NAMES[$os_index]}"
        os_id="${OS_IDS[$os_index]}"

        subsection "OS Template Association"

        echo "OS          : ${os_name}"
        echo "OS ID       : ${os_id}"
        echo "Template    : ${template_name}"
        echo "Template ID : ${template_id}"

        if [ -z "$os_id" ] || [ "$os_id" = "null" ]; then
            error "OS ID missing."
            record_failure "${os_name} template association"
            continue
        fi

        if [ -z "$template_id" ] || [ "$template_id" = "null" ]; then
            error "Template ID missing."
            record_failure "${template_name} association"
            continue
        fi

        api_request GET "${API}/operatingsystems/${os_id}"

        if ! api_success || ! json_valid "$API_BODY"; then
            print_api_error GET "${API}/operatingsystems/${os_id}"
            record_failure "${os_name} OS read"
            continue
        fi

        existing_ids="$(
            "$JQ" -r '
                [
                    (.provisioning_templates // [])[]?.id
                ]
                | .[]
            ' "$API_BODY" 2>/dev/null
        )"

        ids_json="$(
            {
                printf '%s\n' "$existing_ids"
                printf '%s\n' "$template_id"
            } |
            "$AWK" 'NF && !seen[$0]++' |
            "$JQ" -R -s '
                split("\n")
                | map(select(length > 0))
                | map(tonumber)
            '
        )"

        json="$(
            "$JQ" -n \
                --argjson ids "$ids_json" \
                '{
                    operatingsystem: {
                        provisioning_template_ids: $ids
                    }
                }'
        )"

        api_request PUT \
            "${API}/operatingsystems/${os_id}" \
            "$json"

        if api_success; then
            ok "${os_name} associated with ${template_name}."
        else
            print_api_error PUT \
                "${API}/operatingsystems/${os_id}"
            record_failure "${os_name} template association"
        fi

    done
}

###############################################################################
# VERIFY OS TEMPLATE ASSOCIATIONS
###############################################################################

verify_os_template_associations()
{
    section "OS PXEGrub2 Association Verification"

    local i
    local os_id
    local os_name

    for i in "${!OS_NAMES[@]}"
    do

        os_name="${OS_NAMES[$i]}"
        os_id="${OS_IDS[$i]}"

        echo
        echo "${os_name} (ID=${os_id})"

        api_request GET \
            "${API}/operatingsystems/${os_id}/provisioning_templates?per_page=all"

        if ! api_success || ! json_valid "$API_BODY"; then
            print_api_error GET \
                "${API}/operatingsystems/${os_id}/provisioning_templates?per_page=all"
            record_failure "${os_name} association verification"
            continue
        fi

        "$JQ" -r '
            (.results // [])[]
            | select(.template_kind_name == "PXEGrub2")
            | [
                .id,
                .name,
                .template_kind_id,
                .template_kind_name
              ]
            | @tsv
        ' "$API_BODY"

    done
}

###############################################################################
# SET PXEGRUB2 DEFAULT
#
# IMPORTANT FIX:
#
# Foreman only permits ONE os_default_template for a given template_kind_id.
#
# We NEVER POST a second PXEGrub2 default if one already exists.
#
# If an existing PXEGrub2 default is found:
#   - correct template -> SKIP
#   - wrong template   -> PUT existing record
#
# If POST somehow returns "template_kind_id has already been taken",
# we immediately re-read the endpoint and update the existing record.
###############################################################################

set_pxe_default()
{
    local os_name="$1"
    local template_name="$2"

    local os_id
    local template_id
    local default_id
    local current_template_id
    local json
    local row

    subsection "PXEGrub2 Default Template"

    echo "OS       : ${os_name}"
    echo "Template : ${template_name}"

    os_id="$(get_os_id "$os_name")"
    template_id="$(get_template_id "$template_name")"

    if [ -z "$os_id" ] || [ "$os_id" = "null" ]; then
        error "OS not found: ${os_name}"
        record_failure "${os_name} default"
        return
    fi

    if [ -z "$template_id" ] || [ "$template_id" = "null" ]; then
        error "Template not found: ${template_name}"
        record_failure "${os_name} default"
        return
    fi

    echo "OS ID      : ${os_id}"
    echo "Template ID : ${template_id}"
    echo "Kind ID     : ${PXEGRUB2_KIND_ID}"

    api_request GET \
        "${API}/operatingsystems/${os_id}/os_default_templates?per_page=all"

    if ! api_success || ! json_valid "$API_BODY"; then
        print_api_error GET \
            "${API}/operatingsystems/${os_id}/os_default_templates?per_page=all"
        record_failure "${os_name} default lookup"
        return
    fi

    #
    # First find ANY default with this template kind.
    #
    # Compare as strings because different Foreman versions/API responses
    # may serialize IDs differently.
    #
    row="$(
        "$JQ" -c \
            --arg KIND "$PXEGRUB2_KIND_ID" \
            '
            (.results // [])[]
            | select(
                ((.template_kind_id // "") | tostring) == $KIND
            )
            ' \
            "$API_BODY" |
        "$HEAD" -1
    )"

    if [ -n "$row" ]; then

        default_id="$("$JQ" -r '.id // empty' <<< "$row")"
        current_template_id="$(
            "$JQ" -r '.provisioning_template_id // empty' <<< "$row"
        )"

        echo "Existing Default ID       : ${default_id}"
        echo "Existing Template ID      : ${current_template_id}"

        if [ "$current_template_id" = "$template_id" ]; then

            skip "PXEGrub2 default already correct. ID=${default_id}"
            return

        fi

        info "Existing PXEGrub2 default uses a different template."
        info "Updating existing default ID=${default_id}"

        json="$(
            "$JQ" -n \
                --argjson TEMPLATE "$template_id" \
                --argjson KIND "$PXEGRUB2_KIND_ID" \
                '{
                    os_default_template: {
                        provisioning_template_id: $TEMPLATE,
                        template_kind_id: $KIND
                    }
                }'
        )"

        api_request PUT \
            "${API}/operatingsystems/${os_id}/os_default_templates/${default_id}" \
            "$json"

        if api_success; then

            ok "PXEGrub2 default updated. ID=${default_id}"

        else

            print_api_error PUT \
                "${API}/operatingsystems/${os_id}/os_default_templates/${default_id}"

            record_failure "${os_name} default update"

        fi

        return
    fi

    #
    # No PXEGrub2 default exists.
    #
    info "No PXEGrub2 default exists. Creating one."

    json="$(
        "$JQ" -n \
            --argjson TEMPLATE "$template_id" \
            --argjson KIND "$PXEGRUB2_KIND_ID" \
            '{
                os_default_template: {
                    provisioning_template_id: $TEMPLATE,
                    template_kind_id: $KIND
                }
            }'
    )"

    api_request POST \
        "${API}/operatingsystems/${os_id}/os_default_templates" \
        "$json"

    if api_success; then

        default_id="$("$JQ" -r '.id // empty' "$API_BODY" 2>/dev/null)"

        if [ -n "$default_id" ]; then
            ok "PXEGrub2 default created. ID=${default_id}"
        else
            ok "PXEGrub2 default created."
        fi

        return
    fi

    #
    # Race/duplicate protection:
    # Foreman can return 422 if a default appeared between GET and POST.
    #
    warn "PXEGrub2 default creation returned HTTP ${API_STATUS}."
    warn "Re-reading defaults before declaring failure."

    api_request GET \
        "${API}/operatingsystems/${os_id}/os_default_templates?per_page=all"

    if api_success && json_valid "$API_BODY"; then

        row="$(
            "$JQ" -c \
                --arg KIND "$PXEGRUB2_KIND_ID" \
                '
                (.results // [])[]
                | select(
                    ((.template_kind_id // "") | tostring) == $KIND
                )
                ' \
                "$API_BODY" |
            "$HEAD" -1
        )"

        if [ -n "$row" ]; then

            default_id="$("$JQ" -r '.id // empty' <<< "$row")"

            info "Existing PXEGrub2 default found after POST failure."
            info "Updating ID=${default_id}"

            api_request PUT \
                "${API}/operatingsystems/${os_id}/os_default_templates/${default_id}" \
                "$json"

            if api_success; then
                ok "PXEGrub2 default recovered and updated. ID=${default_id}"
                return
            fi

        fi

    fi

    print_api_error POST \
        "${API}/operatingsystems/${os_id}/os_default_templates"

    record_failure "${os_name} default creation"
}

###############################################################################
# SET ALL PXE DEFAULTS
###############################################################################

set_all_pxe_defaults()
{
    section "Setting PXEGrub2 Default Templates"

    set_pxe_default \
        "CentOSLinux7-RAID" \
        "PXEGrub2 CentOS UEFI RAID Kickstart"

    set_pxe_default \
        "CentOSLinux7-SingleDisk" \
        "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

    set_pxe_default \
        "RockyLinux8.10-RAID" \
        "PXEGrub2 Rocky8 UEFI RAID Kickstart"

    set_pxe_default \
        "RockyLinux8.10-SingleDisk" \
        "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

    set_pxe_default \
        "RockyLinux9.2-RAID" \
        "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

    set_pxe_default \
        "RockyLinux9.2-SingleDisk" \
        "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

    set_pxe_default \
        "RockyLinux9.8-RAID" \
        "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

    set_pxe_default \
        "RockyLinux9.8-SingleDisk" \
        "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"
}

###############################################################################
# VERIFY PXE DEFAULTS
###############################################################################

verify_pxe_defaults()
{
    section "PXEGrub2 Default Verification"

    local i
    local os_name
    local os_id
    local row

    for i in "${!OS_NAMES[@]}"
    do

        os_name="${OS_NAMES[$i]}"
        os_id="${OS_IDS[$i]}"

        api_request GET \
            "${API}/operatingsystems/${os_id}/os_default_templates?per_page=all"

        if ! api_success || ! json_valid "$API_BODY"; then
            error "${os_name}: unable to read defaults."
            record_failure "${os_name} default verification"
            continue
        fi

        row="$(
            "$JQ" -r \
                --arg KIND "$PXEGRUB2_KIND_ID" \
                '
                (.results // [])[]
                | select(
                    ((.template_kind_id // "") | tostring) == $KIND
                )
                | [
                    .id,
                    .provisioning_template_id,
                    .template_kind_id
                  ]
                | @tsv
                ' \
                "$API_BODY" |
            "$HEAD" -1
        )"

        if [ -n "$row" ]; then
            ok "${os_name} PXEGrub2 default: ${row}"
        else
            error "${os_name} PXEGrub2 default missing."
            record_failure "${os_name} default missing"
        fi

    done
}

###############################################################################
# VERIFY PXEGRUB2 TEMPLATES
###############################################################################

verify_pxe_templates()
{
    section "PXEGrub2 Template Verification"

    api_request GET \
        "${API}/provisioning_templates?per_page=all"

    if ! api_success || ! json_valid "$API_BODY"; then
        print_api_error GET \
            "${API}/provisioning_templates?per_page=all"
        record_failure "PXE template verification"
        return
    fi

    "$JQ" -r \
        --arg KIND "$PXEGRUB2_KIND_ID" \
        '
        (.results // [])[]
        | select(
            ((.template_kind_id // "") | tostring) == $KIND
        )
        | [
            .id,
            .name,
            .template_kind_id,
            .template_kind_name
          ]
        | @tsv
        ' \
        "$API_BODY"
}

###############################################################################
# FINAL OS VERIFICATION
#
# FIX:
# Every possibly-null collection is converted to [] first.
###############################################################################

final_os_verification()
{
    section "Final Operating System Verification"

    local i
    local os_id
    local os_name

    for i in "${!OS_NAMES[@]}"
    do

        os_name="${OS_NAMES[$i]}"
        os_id="${OS_IDS[$i]}"

        echo
        echo "------------------------------------------------------------"
        echo "${os_name} (ID=${os_id})"
        echo "------------------------------------------------------------"

        api_request GET \
            "${API}/operatingsystems/${os_id}"

        if ! api_success || ! json_valid "$API_BODY"; then
            error "Unable to read ${os_name}."
            record_failure "${os_name} final verification"
            continue
        fi

        "$JQ" -r '
        {
            id: .id,
            name: .name,
            title: (.title // ""),
            major: (.major // ""),
            minor: (.minor // ""),
            family: (.family // ""),

            architectures:
                ((.architectures // [])
                | map(.name // "")
                | join(",")),

            media:
                ((.media // [])
                | map(.name // "")
                | join(",")),

            ptables:
                ((.ptables // [])
                | map(.name // "")
                | join(",")),

            pxegrub2_templates:
                ((.provisioning_templates // [])
                | map(
                    select(.template_kind_name == "PXEGrub2")
                    | (.name // "")
                  )
                | join(" | ")),

            pxegrub2_defaults:
                ((.os_default_templates // [])
                | map(
                    select(.template_kind_name == "PXEGrub2")
                    | (
                        .provisioning_template_name
                        // (.provisioning_template_id | tostring)
                        // ""
                      )
                  )
                | join(" | "))
        }
        | [
            .id,
            .name,
            .major,
            .minor,
            .family,
            .architectures,
            .media,
            .ptables,
            .pxegrub2_templates,
            .pxegrub2_defaults
        ]
        | @tsv
        ' "$API_BODY"

    done
}

###############################################################################
# SUBNET DATA
###############################################################################

SUBNET_NAMES=(
    "vgs-subnet-centos"
    "vgs-subnet-rockyos"
)

SUBNET_NETWORK="192.168.253.0"
SUBNET_MASK="255.255.255.0"
SUBNET_GATEWAY="192.168.253.2"
SUBNET_DNS="192.168.253.1"

SUBNET_TFTP_PROXY=(
    "cent-07-01.vgs.com"
    "cent-07-02.vgs.com"
)

SUBNET_DHCP_PROXY=(
    "cent-07-01.vgs.com"
    "cent-07-02.vgs.com"
)

###############################################################################
# CREATE / VERIFY SUBNETS
###############################################################################

create_or_verify_subnets()
{
    section "Creating / Verifying PXE Subnets"

    local i
    local name
    local tftp_name
    local dhcp_name
    local subnet_id
    local domain_id
    local tftp_id
    local dhcp_id
    local json

    domain_id="$(get_domain_id "vgs.com")"

    if [ -z "$domain_id" ] || [ "$domain_id" = "null" ]; then
        error "Domain vgs.com not found."
        record_failure "vgs.com domain"
        return
    fi

    ok "Domain found : vgs.com ID=${domain_id}"

    for i in "${!SUBNET_NAMES[@]}"
    do

        name="${SUBNET_NAMES[$i]}"
        tftp_name="${SUBNET_TFTP_PROXY[$i]}"
        dhcp_name="${SUBNET_DHCP_PROXY[$i]}"

        subsection "Subnet : ${name}"

        echo "Network      : ${SUBNET_NETWORK}"
        echo "Mask         : ${SUBNET_MASK}"
        echo "Gateway      : ${SUBNET_GATEWAY}"
        echo "DNS          : ${SUBNET_DNS}"
        echo "TFTP Proxy   : ${tftp_name}"
        echo "DHCP Proxy   : ${dhcp_name}"

        tftp_id="$(get_proxy_id "$tftp_name")"

        if [ -z "$tftp_id" ] || [ "$tftp_id" = "null" ]; then
            error "TFTP proxy not found: ${tftp_name}"
            record_failure "${name} TFTP proxy"
            continue
        fi

        ok "TFTP proxy found : ${tftp_name} ID=${tftp_id}"

        dhcp_id="$(get_proxy_id "$dhcp_name")"

        if [ -z "$dhcp_id" ] || [ "$dhcp_id" = "null" ]; then
            error "DHCP proxy not found: ${dhcp_name}"
            record_failure "${name} DHCP proxy"
            continue
        fi

        ok "DHCP proxy found : ${dhcp_name} ID=${dhcp_id}"

        subnet_id="$(get_id_by_name "/subnets" "$name")"

        json="$(
            "$JQ" -n \
                --arg name "$name" \
                --arg network "$SUBNET_NETWORK" \
                --arg mask "$SUBNET_MASK" \
                --arg gateway "$SUBNET_GATEWAY" \
                --arg dns "$SUBNET_DNS" \
                --argjson domain "$domain_id" \
                --argjson tftp "$tftp_id" \
                --argjson dhcp "$dhcp_id" \
                '{
                    subnet: {
                        name: $name,
                        network_type: "IPv4",
                        network: $network,
                        mask: $mask,
                        gateway: $gateway,
                        dns_primary: $dns,
                        ipam: "None",
                        boot_mode: "DHCP",
                        domain_ids: [$domain],
                        tftp_id: $tftp,
                        dhcp_id: $dhcp
                    }
                }'
        )"

        if [ -n "$subnet_id" ] && [ "$subnet_id" != "null" ]; then

            skip "${name} already exists. ID=${subnet_id}"

            api_request PUT \
                "${API}/subnets/${subnet_id}" \
                "$json"

            if api_success; then
                ok "${name} updated."
            else
                print_api_error PUT \
                    "${API}/subnets/${subnet_id}"
                record_failure "${name} subnet update"
            fi

        else

            info "Creating ${name}"

            api_request POST \
                "${API}/subnets" \
                "$json"

            if api_success && json_valid "$API_BODY"; then

                subnet_id="$("$JQ" -r '.id // empty' "$API_BODY")"

                ok "${name} created. ID=${subnet_id}"

            else

                print_api_error POST "${API}/subnets"
                record_failure "${name} subnet creation"

            fi

        fi

    done
}

###############################################################################
# VERIFY SUBNETS
###############################################################################

verify_subnets()
{
    section "PXE Subnet Verification"

    api_request GET "${API}/subnets?per_page=all"

    if ! api_success || ! json_valid "$API_BODY"; then
        print_api_error GET "${API}/subnets?per_page=all"
        record_failure "Subnet verification"
        return
    fi

    "$JQ" -r '
        (.results // [])[]
        | [
            .id,
            .name,
            .network,
            .mask,
            (.gateway // ""),
            (.dns_primary // ""),
            (.tftp_name // ""),
            (.dhcp_name // "")
          ]
        | @tsv
    ' "$API_BODY"
}

###############################################################################
# BUILD PXE DEFAULT
###############################################################################

build_pxe_default()
{
    section "Building PXE Default Menus"

    local json

    json='{
        "provisioning_template": {}
    }'

    api_request POST \
        "${API}/provisioning_templates/build_pxe_default" \
        "$json"

    if api_success; then

        ok "Foreman PXE default build request completed."

    else

        warn "PXE default build returned HTTP ${API_STATUS}."

        if [ -n "$API_BODY" ] && [ -s "$API_BODY" ]; then
            "$JQ" . "$API_BODY" 2>/dev/null || "$CAT" "$API_BODY"
        fi

        #
        # Older Foreman versions may not expose this endpoint.
        # Do not mark the complete bootstrap as failed.
        #

    fi
}

###############################################################################
# GENERATED FILE VERIFICATION
###############################################################################

verify_generated_files()
{
    section "Generated PXE Files"

    local file
    local failed=0

    for file in "${TEMPLATE_FILES[@]}"
    do

        if [ -s "${TEMPLATE_DIR}/${file}" ]; then
            ls -l "${TEMPLATE_DIR}/${file}"
        else
            error "Missing generated file: ${file}"
            failed=1
        fi

    done

    if [ "$failed" -eq 0 ]; then
        ok "All generated PXE files are present."
    else
        record_failure "Generated PXE files"
    fi
}

###############################################################################
# FINAL SUMMARY
###############################################################################

final_summary()
{
    section "01 - Foreman PXE Bootstrap - Final Summary"

    if [ "${#FAILURES[@]}" -eq 0 ]; then

        ok "Completed successfully with no failures."

    else

        error "Completed with ${#FAILURES[@]} failure(s)."

        echo
        echo "Failures:"
        echo "------------------------------------------------------------"

        local failure

        for failure in "${FAILURES[@]}"
        do
            echo " - ${failure}"
        done

        echo
        error "Review the failures above."

    fi

    echo
    echo "Foreman URL : ${FOREMAN_URL}"
    echo "API         : ${API}"
    echo "PXEGrub2 ID : ${PXEGRUB2_KIND_ID}"
    echo "Template Dir: ${TEMPLATE_DIR}"

    echo
    echo "============================================================"
    echo "Manual Verification Commands"
    echo "============================================================"

    echo
    echo "1. Foreman API:"
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
    echo "  jq -r '.results[] | select(.template_kind_name==\"PXEGrub2\") | [.id,.name,.template_kind_id,.template_kind_name] | @tsv'"

    echo
    echo "3. OS 2 provisioning templates:"
    echo
    echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/operatingsystems/2/provisioning_templates?per_page=all' | \\"
    echo "  jq -r '.results[] | [.id,.name,.template_kind_id,.template_kind_name] | @tsv'"

    echo
    echo "4. OS 2 PXEGrub2 default:"
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

    echo
    echo "============================================================"

    #
    # Return failure to shell if anything failed.
    #
    if [ "${#FAILURES[@]}" -ne 0 ]; then
        return 1
    fi

    return 0
}

###############################################################################
# CLEANUP
###############################################################################

cleanup()
{
    #
    # Keep generated templates for manual inspection.
    #
    return 0
}

trap cleanup EXIT

###############################################################################
# MAIN
###############################################################################

main()
{
    check_dependencies
    prepare_temp

    section "01 - Foreman PXE Bootstrap - REST API"

    test_foreman_api

    find_architecture
    find_partition_table

    if [ -z "$ARCH_ID" ] || [ -z "$PTABLE_ID" ]; then
        error "Required architecture/partition-table IDs are missing."
        final_summary || true
        exit 1
    fi

    create_or_verify_media
    verify_media

    create_or_verify_os
    verify_operating_systems

    generate_template_files

    find_pxegrub2_kind

    if [ -z "$PXEGRUB2_KIND_ID" ]; then
        error "Cannot continue without PXEGrub2 template kind."
        final_summary || true
        exit 1
    fi

    create_or_update_templates

    associate_templates_with_os

    verify_pxe_templates
    verify_os_template_associations

    set_all_pxe_defaults
    verify_pxe_defaults

    create_or_verify_subnets
    verify_subnets

    final_os_verification

    verify_generated_files

    build_pxe_default

    final_summary
}

###############################################################################
# RUN
###############################################################################

main
exit $?
