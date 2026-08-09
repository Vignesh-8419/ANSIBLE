#!/bin/bash
###############################################################################
# 01_foreman_pxe_bootstrap_api.sh
#
# Foreman PXE Bootstrap - REST API only
#
# Foreman:
#   https://cent-07-01.vgs.com
#
# User:
#   admin
#
# Authentication:
#   Personal Access Token
#
# Creates / verifies:
#   - Installation Media
#   - Architectures
#   - Partition Table
#   - Operating Systems
#   - PXEGrub2 Provisioning Templates
#   - OS <-> PXEGrub2 associations
#   - OS default PXEGrub2 templates
#   - PXE Subnets
#
# No Hammer CLI required.
###############################################################################

set -u
set -o pipefail

###############################################################################
# CONFIGURATION
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
FOREMAN_API="${FOREMAN_URL}/api"

FOREMAN_USER="${FOREMAN_USER:-admin}"

# PAT supplied by user.
# You can override it safely with:
#
#   export FOREMAN_TOKEN='NEW_TOKEN'
#
FOREMAN_TOKEN="${FOREMAN_TOKEN:-'oUzg-aMfjcT3q_wZ8NRLfQ'}"

API_VERSION="2"

REPO_SERVER="192.168.253.136"

CENTOS_REPO="${CENTOS_REPO:-http://${REPO_SERVER}/repo/centos/}"
ROCKY8_REPO="${ROCKY8_REPO:-http://${REPO_SERVER}/repo/rocky8/}"
ROCKY92_REPO="${ROCKY92_REPO:-http://${REPO_SERVER}/repo/rocky9.2/}"
ROCKY98_REPO="${ROCKY98_REPO:-http://${REPO_SERVER}/repo/rocky9/}"

CENTOS_SUBNET_NAME="vgs-subnet-centos"
ROCKY_SUBNET_NAME="vgs-subnet-rockyos"

NETWORK="192.168.253.0"
MASK="255.255.255.0"
GATEWAY="192.168.253.2"
DNS_PRIMARY="192.168.253.1"

CENTOS_PROXY="cent-07-01.vgs.com"
ROCKY_PROXY="cent-07-02.vgs.com"

TMP_DIR="/tmp/foreman-pxe-bootstrap"

###############################################################################
# COLORS
###############################################################################

RED=""
GREEN=""
YELLOW=""
BLUE=""
RESET=""

###############################################################################
# RESULT VARIABLES
###############################################################################

RESULT_ID=""
RESULT_STATUS=""
RESULT_BODY=""

ARCH_ID=""
PTABLE_ID=""
PXEGRUB2_KIND_ID=""

CENTOS_MEDIA_ID=""
ROCKY8_MEDIA_ID=""
ROCKY92_MEDIA_ID=""
ROCKY98_MEDIA_ID=""

CENTOS_RAID_ID=""
CENTOS_SINGLE_ID=""
ROCKY8_RAID_ID=""
ROCKY8_SINGLE_ID=""
ROCKY92_RAID_ID=""
ROCKY92_SINGLE_ID=""
ROCKY98_RAID_ID=""
ROCKY98_SINGLE_ID=""

TEMPLATE_CENTOS_RAID_ID=""
TEMPLATE_CENTOS_SINGLE_ID=""
TEMPLATE_ROCKY8_RAID_ID=""
TEMPLATE_ROCKY8_SINGLE_ID=""
TEMPLATE_ROCKY92_RAID_ID=""
TEMPLATE_ROCKY92_SINGLE_ID=""
TEMPLATE_ROCKY98_RAID_ID=""
TEMPLATE_ROCKY98_SINGLE_ID=""

FAILURES=0

###############################################################################
# LOGGING
###############################################################################

info()
{
    echo "[INFO] $*"
}

ok()
{
    echo "[OK] $*"
}

skip()
{
    echo "[SKIP] $*"
}

warn()
{
    echo "[WARN] $*"
}

error()
{
    echo "[ERROR] $*" >&2
    FAILURES=$((FAILURES + 1))
}

section()
{
    echo
    echo "============================================================"
    echo "$*"
    echo "============================================================"
}

subsection()
{
    echo
    echo "------------------------------------------------------------"
    echo "$*"
    echo "------------------------------------------------------------"
}

###############################################################################
# DEPENDENCY CHECK
###############################################################################

check_dependencies()
{
    section "Dependency Check"

    if ! command -v curl >/dev/null 2>&1; then
        error "curl not found."
        exit 1
    fi

    ok "curl found: $(command -v curl)"

    if ! command -v jq >/dev/null 2>&1; then
        error "jq not found."
        exit 1
    fi

    ok "jq found: $(command -v jq)"
}

###############################################################################
# DIRECTORY
###############################################################################

prepare_directories()
{
    mkdir -p "$TMP_DIR"

    if [ ! -d "$TMP_DIR" ]; then
        error "Unable to create $TMP_DIR"
        exit 1
    fi
}

###############################################################################
# API REQUEST
#
# IMPORTANT:
#   This function ONLY sets RESULT_* variables.
#   It does NOT print normal log messages to stdout.
#
# This prevents:
#
#   ID="$(api_call ...)"
#
# from accidentally capturing log output.
###############################################################################

api_call()
{
    local method="$1"
    local endpoint="$2"
    local payload="${3:-}"

    local tmp_body
    local http_code
    local curl_rc

    tmp_body="$(mktemp "${TMP_DIR}/api.XXXXXX")"

    RESULT_BODY=""
    RESULT_STATUS=""
    RESULT_ID=""

    if [ "$method" = "GET" ]; then

        http_code="$(
            curl \
                -k \
                -sS \
                --globoff \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                -H "Accept: application/json,version=${API_VERSION}" \
                -H "Content-Type: application/json" \
                -o "$tmp_body" \
                -w "%{http_code}" \
                "${FOREMAN_API}${endpoint}"
        )"

        curl_rc=$?

    else

        http_code="$(
            curl \
                -k \
                -sS \
                --globoff \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                -H "Accept: application/json,version=${API_VERSION}" \
                -H "Content-Type: application/json" \
                -X "$method" \
                --data "$payload" \
                -o "$tmp_body" \
                -w "%{http_code}" \
                "${FOREMAN_API}${endpoint}"
        )"

        curl_rc=$?

    fi

    RESULT_STATUS="$http_code"

    if [ "$curl_rc" -ne 0 ]; then
        RESULT_BODY="$(cat "$tmp_body" 2>/dev/null || true)"
        rm -f "$tmp_body"
        return 1
    fi

    RESULT_BODY="$(cat "$tmp_body")"

    rm -f "$tmp_body"

    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        RESULT_ID="$(echo "$RESULT_BODY" | jq -r '.id // empty' 2>/dev/null || true)"
        return 0
    fi

    return 1
}

###############################################################################
# JSON VALIDATION
###############################################################################

json_valid()
{
    echo "$1" | jq empty >/dev/null 2>&1
}

###############################################################################
# FOREMAN API AUTHENTICATION
###############################################################################

test_api()
{
    section "Foreman API Authentication Test"

    info "Testing Foreman REST API..."

    api_call GET "/status"

    if [ "$RESULT_STATUS" != "200" ]; then
        error "Foreman API authentication failed."
        echo "$RESULT_BODY"
        exit 1
    fi

    if ! json_valid "$RESULT_BODY"; then
        error "Foreman returned invalid JSON."
        echo "$RESULT_BODY"
        exit 1
    fi

    local result
    result="$(echo "$RESULT_BODY" | jq -r '.result // empty')"

    if [ "$result" != "ok" ]; then
        error "Foreman API authentication failed."
        echo "$RESULT_BODY"
        exit 1
    fi

    ok "Foreman API authentication successful."

    echo "Foreman Version : $(echo "$RESULT_BODY" | jq -r '.version // .foreman_version // "unknown"')"
    echo "API Version     : $(echo "$RESULT_BODY" | jq -r '.api_version // "unknown"')"
    echo "API Status      : $(echo "$RESULT_BODY" | jq -r '.status // "unknown"')"
}

###############################################################################
# GET ALL COLLECTION
###############################################################################

get_collection()
{
    local endpoint="$1"

    api_call GET "${endpoint}?per_page=all"

    if [ "$RESULT_STATUS" != "200" ]; then
        return 1
    fi

    if ! json_valid "$RESULT_BODY"; then
        return 1
    fi

    return 0
}

###############################################################################
# FIND ARCHITECTURE
###############################################################################

find_architecture()
{
    get_collection "/architectures"

    if [ "$RESULT_STATUS" != "200" ]; then
        error "Unable to query architectures."
        return 1
    fi

    ARCH_ID="$(
        echo "$RESULT_BODY" |
        jq -r '
            .results[]
            | select(.name == "x86_64")
            | .id
        ' |
        head -n 1
    )"

    if [ -z "$ARCH_ID" ] || [ "$ARCH_ID" = "null" ]; then
        error "x86_64 architecture not found."
        return 1
    fi

    ok "x86_64 architecture found. ID=$ARCH_ID"
}

###############################################################################
# FIND PARTITION TABLE
###############################################################################

find_ptable()
{
    get_collection "/ptables"

    if [ "$RESULT_STATUS" != "200" ]; then
        error "Unable to query partition tables."
        return 1
    fi

    PTABLE_ID="$(
        echo "$RESULT_BODY" |
        jq -r '
            .results[]
            | select(.name == "Kickstart default")
            | .id
        ' |
        head -n 1
    )"

    if [ -z "$PTABLE_ID" ] || [ "$PTABLE_ID" = "null" ]; then
        error "Kickstart default partition table not found."
        return 1
    fi

    ok "Kickstart default partition table found. ID=$PTABLE_ID"
}

###############################################################################
# INSTALLATION MEDIA
###############################################################################

find_media_id()
{
    local name="$1"

    get_collection "/media"

    if [ "$RESULT_STATUS" != "200" ]; then
        return 1
    fi

    echo "$RESULT_BODY" |
        jq -r --arg name "$name" '
            .results[]
            | select(.name == $name)
            | .id
        ' |
        head -n 1
}

create_or_update_media()
{
    local name="$1"
    local path="$2"
    local variable_name="$3"

    subsection "Installation Media : $name"

    local media_id
    media_id="$(find_media_id "$name")"

    if [ -n "$media_id" ] && [ "$media_id" != "null" ]; then

        skip "$name already exists. ID=$media_id"

        local payload
        payload="$(
            jq -n \
                --arg name "$name" \
                --arg path "$path" \
                '{
                    medium: {
                        name: $name,
                        path: $path
                    }
                }'
        )"

        api_call PUT "/media/${media_id}" "$payload"

        if [[ "$RESULT_STATUS" =~ ^2[0-9][0-9]$ ]]; then
            ok "$name path verified."
        else
            error "Unable to update $name."
        fi

    else

        info "Creating $name..."

        local payload
        payload="$(
            jq -n \
                --arg name "$name" \
                --arg path "$path" \
                '{
                    medium: {
                        name: $name,
                        path: $path,
                        media_type: "url"
                    }
                }'
        )"

        api_call POST "/media" "$payload"

        if [[ "$RESULT_STATUS" =~ ^2[0-9][0-9]$ ]]; then
            media_id="$RESULT_ID"
            ok "$name created. ID=$media_id"
        else
            error "Unable to create $name."
            echo "$RESULT_BODY"
            return 1
        fi

    fi

    eval "$variable_name='$media_id'"
}

verify_media()
{
    section "Installation Media Verification"

    get_collection "/media"

    if [ "$RESULT_STATUS" != "200" ]; then
        error "Unable to list installation media."
        return 1
    fi

    echo "$RESULT_BODY" |
        jq -r '
            .results[]
            | [
                .id,
                .name,
                .path
              ]
            | @tsv
        ' |
        sort -k2
}

###############################################################################
# OPERATING SYSTEM
###############################################################################

find_os_id()
{
    local name="$1"

    get_collection "/operatingsystems"

    if [ "$RESULT_STATUS" != "200" ]; then
        return 1
    fi

    echo "$RESULT_BODY" |
        jq -r --arg name "$name" '
            .results[]
            | select(.name == $name)
            | .id
        ' |
        head -n 1
}

create_or_update_os()
{
    local name="$1"
    local major="$2"
    local minor="$3"
    local family="$4"
    local media_id="$5"

    subsection "Operating System : $name"

    local os_id
    os_id="$(find_os_id "$name")"

    local payload

    if [ -n "$os_id" ] && [ "$os_id" != "null" ]; then

        skip "$name already exists. ID=$os_id"

        #
        # Get current OS object.
        #
        api_call GET "/operatingsystems/${os_id}"

        if [ "$RESULT_STATUS" != "200" ]; then
            error "Unable to read OS $name."
            return 1
        fi

        #
        # Preserve existing associations and add required ones.
        #
        payload="$(
            echo "$RESULT_BODY" |
            jq \
                --argjson arch "$ARCH_ID" \
                --argjson media "$media_id" \
                --argjson ptable "$PTABLE_ID" '
                {
                    operatingsystem: {
                        architecture_ids:
                            ((.architectures // [])
                            | map(.id)
                            + [$arch]
                            | unique),

                        medium_ids:
                            ((.media // [])
                            | map(.id)
                            + [$media]
                            | unique),

                        ptable_ids:
                            ((.ptables // [])
                            | map(.id)
                            + [$ptable]
                            | unique)
                    }
                }
                '
        )"

        api_call PUT "/operatingsystems/${os_id}" "$payload"

        if [[ "$RESULT_STATUS" =~ ^2[0-9][0-9]$ ]]; then
            ok "$name updated."
        else
            error "Unable to update $name."
            echo "$RESULT_BODY"
            return 1
        fi

    else

        info "Creating $name..."

        #
        # IMPORTANT:
        # major/minor are JSON strings.
        #
        payload="$(
            jq -n \
                --arg name "$name" \
                --arg major "$major" \
                --arg minor "$minor" \
                --arg family "$family" \
                --argjson arch "$ARCH_ID" \
                --argjson media "$media_id" \
                --argjson ptable "$PTABLE_ID" '
                {
                    operatingsystem: {
                        name: $name,
                        major: $major,
                        minor: $minor,
                        family: $family,
                        architecture_ids: [$arch],
                        medium_ids: [$media],
                        ptable_ids: [$ptable]
                    }
                }
                '
        )"

        api_call POST "/operatingsystems" "$payload"

        if [[ "$RESULT_STATUS" =~ ^2[0-9][0-9]$ ]]; then
            os_id="$RESULT_ID"
            ok "$name created. ID=$os_id"
        else
            error "Unable to create $name."
            echo "$RESULT_BODY"
            return 1
        fi

    fi

    case "$name" in

        CentOSLinux7-RAID)
            CENTOS_RAID_ID="$os_id"
            ;;

        CentOSLinux7-SingleDisk)
            CENTOS_SINGLE_ID="$os_id"
            ;;

        RockyLinux8.10-RAID)
            ROCKY8_RAID_ID="$os_id"
            ;;

        RockyLinux8.10-SingleDisk)
            ROCKY8_SINGLE_ID="$os_id"
            ;;

        RockyLinux9.2-RAID)
            ROCKY92_RAID_ID="$os_id"
            ;;

        RockyLinux9.2-SingleDisk)
            ROCKY92_SINGLE_ID="$os_id"
            ;;

        RockyLinux9.8-RAID)
            ROCKY98_RAID_ID="$os_id"
            ;;

        RockyLinux9.8-SingleDisk)
            ROCKY98_SINGLE_ID="$os_id"
            ;;

    esac
}

verify_os()
{
    section "Operating System Verification"

    get_collection "/operatingsystems"

    if [ "$RESULT_STATUS" != "200" ]; then
        error "Unable to list operating systems."
        return 1
    fi

    printf "%-4s %-32s %-5s %-5s %-10s\n" \
        "ID" "NAME" "MAJOR" "MINOR" "FAMILY"

    echo "$RESULT_BODY" |
        jq -r '
            .results[]
            | select(
                .name == "CentOSLinux7-RAID" or
                .name == "CentOSLinux7-SingleDisk" or
                .name == "RockyLinux8.10-RAID" or
                .name == "RockyLinux8.10-SingleDisk" or
                .name == "RockyLinux9.2-RAID" or
                .name == "RockyLinux9.2-SingleDisk" or
                .name == "RockyLinux9.8-RAID" or
                .name == "RockyLinux9.8-SingleDisk"
              )
            | [
                .id,
                .name,
                .major,
                (.minor // ""),
                (.family // "")
              ]
            | @tsv
        ' |
        while IFS=$'\t' read -r id name major minor family; do
            printf "%-4s %-32s %-5s %-5s %-10s\n" \
                "$id" "$name" "$major" "$minor" "$family"
        done
}

###############################################################################
# PXEGRUB2 TEMPLATE CONTENT
###############################################################################

generate_template_files()
{
    section "Generating PXEGrub2 Template Files"

    mkdir -p "$TMP_DIR"

    cat > "${TMP_DIR}/centos-raid.erb" <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI RAID Kickstart
kind: PXEGrub2
oses:
- CentOSLinux7-RAID
-%>
menuentry '<%= @host.shortname %> - CentOS 7 RAID' {
    linuxefi <%= @kernel %> ks=<%= foreman_url('provision') %> ksdevice=bootif network kssendmac
    initrdefi <%= @initrd %>
}
EOF

    cat > "${TMP_DIR}/centos-singledisk.erb" <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- CentOSLinux7-SingleDisk
-%>
menuentry '<%= @host.shortname %> - CentOS 7 SingleDisk' {
    linuxefi <%= @kernel %> ks=<%= foreman_url('provision') %> ksdevice=bootif network kssendmac
    initrdefi <%= @initrd %>
}
EOF

    cat > "${TMP_DIR}/rocky8-raid.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI RAID Kickstart
kind: PXEGrub2
oses:
- RockyLinux8.10-RAID
-%>
menuentry '<%= @host.shortname %> - Rocky Linux 8 RAID' {
    linuxefi <%= @kernel %> inst.ks=<%= foreman_url('provision') %> inst.ks.sendmac
    initrdefi <%= @initrd %>
}
EOF

    cat > "${TMP_DIR}/rocky8-singledisk.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux8.10-SingleDisk
-%>
menuentry '<%= @host.shortname %> - Rocky Linux 8 SingleDisk' {
    linuxefi <%= @kernel %> inst.ks=<%= foreman_url('provision') %> inst.ks.sendmac
    initrdefi <%= @initrd %>
}
EOF

    cat > "${TMP_DIR}/rocky92-raid.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky9.2 UEFI RAID Kickstart
kind: PXEGrub2
oses:
- RockyLinux9.2-RAID
-%>
menuentry '<%= @host.shortname %> - Rocky Linux 9.2 RAID' {
    linuxefi <%= @kernel %> inst.ks=<%= foreman_url('provision') %> inst.ks.sendmac
    initrdefi <%= @initrd %>
}
EOF

    cat > "${TMP_DIR}/rocky92-singledisk.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux9.2-SingleDisk
-%>
menuentry '<%= @host.shortname %> - Rocky Linux 9.2 SingleDisk' {
    linuxefi <%= @kernel %> inst.ks=<%= foreman_url('provision') %> inst.ks.sendmac
    initrdefi <%= @initrd %>
}
EOF

    cat > "${TMP_DIR}/rocky98-raid.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky9.8 UEFI RAID Kickstart
kind: PXEGrub2
oses:
- RockyLinux9.8-RAID
-%>
menuentry '<%= @host.shortname %> - Rocky Linux 9.8 RAID' {
    linuxefi <%= @kernel %> inst.ks=<%= foreman_url('provision') %> inst.ks.sendmac
    initrdefi <%= @initrd %>
}
EOF

    cat > "${TMP_DIR}/rocky98-singledisk.erb" <<'EOF'
<%#
name: PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux9.8-SingleDisk
-%>
menuentry '<%= @host.shortname %> - Rocky Linux 9.8 SingleDisk' {
    linuxefi <%= @kernel %> inst.ks=<%= foreman_url('provision') %> inst.ks.sendmac
    initrdefi <%= @initrd %>
}
EOF

    chmod 644 "${TMP_DIR}"/*.erb

    ok "All 8 PXEGrub2 template files generated."

    ls -lh "${TMP_DIR}"/*.erb
}

###############################################################################
# FIND PXEGRUB2 TEMPLATE KIND
###############################################################################

find_pxegrub2_kind()
{
    section "Finding PXEGrub2 Template Kind"

    get_collection "/provisioning_templates"

    if [ "$RESULT_STATUS" != "200" ]; then
        error "Unable to query provisioning templates."
        return 1
    fi

    PXEGRUB2_KIND_ID="$(
        echo "$RESULT_BODY" |
        jq -r '
            .results[]
            | select(.template_kind_name == "PXEGrub2")
            | .template_kind_id
        ' |
        grep -E '^[0-9]+$' |
        sort -n |
        head -n 1
    )"

    #
    # Fallback: some Foreman versions expose the kind via a template
    # whose name contains PXEGrub2 but may not expose template_kind_name
    # consistently.
    #
    if [ -z "$PXEGRUB2_KIND_ID" ]; then

        PXEGRUB2_KIND_ID="$(
            echo "$RESULT_BODY" |
            jq -r '
                .results[]
                | select(.name | test("PXEGrub2"))
                | .template_kind_id
            ' |
            grep -E '^[0-9]+$' |
            sort -n |
            head -n 1
        )"

    fi

    if ! [[ "$PXEGRUB2_KIND_ID" =~ ^[0-9]+$ ]]; then
        error "PXEGrub2 template kind not found."
        return 1
    fi

    ok "PXEGrub2 template kind found. ID=$PXEGRUB2_KIND_ID"
}

###############################################################################
# FIND TEMPLATE
###############################################################################

find_template_id()
{
    local name="$1"

    get_collection "/provisioning_templates"

    if [ "$RESULT_STATUS" != "200" ]; then
        return 1
    fi

    echo "$RESULT_BODY" |
        jq -r --arg name "$name" '
            .results[]
            | select(.name == $name)
            | .id
        ' |
        head -n 1
}

###############################################################################
# CREATE OR UPDATE TEMPLATE
###############################################################################

create_or_update_template()
{
    local name="$1"
    local file="$2"

    subsection "PXEGrub2 template : $name"

    local template_id
    template_id="$(find_template_id "$name")"

    local template_content
    template_content="$(cat "$file")"

    local payload

    if [ -n "$template_id" ] && [ "$template_id" != "null" ]; then

        skip "$name already exists. ID=$template_id"

        payload="$(
            jq -n \
                --arg name "$name" \
                --arg template "$template_content" \
                --argjson kind "$PXEGRUB2_KIND_ID" '
                {
                    provisioning_template: {
                        name: $name,
                        template: $template,
                        template_kind_id: $kind
                    }
                }
                '
        )"

        api_call PUT "/provisioning_templates/${template_id}" "$payload"

        if [[ "$RESULT_STATUS" =~ ^2[0-9][0-9]$ ]]; then
            ok "$name updated."
        else
            error "Unable to update $name."
            echo "$RESULT_BODY"
            return 1
        fi

    else

        info "Creating $name..."

        payload="$(
            jq -n \
                --arg name "$name" \
                --arg template "$template_content" \
                --argjson kind "$PXEGRUB2_KIND_ID" '
                {
                    provisioning_template: {
                        name: $name,
                        template: $template,
                        snippet: false,
                        locked: false,
                        template_kind_id: $kind
                    }
                }
                '
        )"

        api_call POST "/provisioning_templates" "$payload"

        if [[ "$RESULT_STATUS" =~ ^2[0-9][0-9]$ ]]; then
            template_id="$RESULT_ID"
            ok "$name created. ID=$template_id"
        else
            error "Unable to create $name."
            echo "$RESULT_BODY"
            return 1
        fi

    fi

    case "$name" in

        "PXEGrub2 CentOS UEFI RAID Kickstart")
            TEMPLATE_CENTOS_RAID_ID="$template_id"
            ;;

        "PXEGrub2 CentOS UEFI SingleDisk Kickstart")
            TEMPLATE_CENTOS_SINGLE_ID="$template_id"
            ;;

        "PXEGrub2 Rocky8 UEFI RAID Kickstart")
            TEMPLATE_ROCKY8_RAID_ID="$template_id"
            ;;

        "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart")
            TEMPLATE_ROCKY8_SINGLE_ID="$template_id"
            ;;

        "PXEGrub2 Rocky9.2 UEFI RAID Kickstart")
            TEMPLATE_ROCKY92_RAID_ID="$template_id"
            ;;

        "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart")
            TEMPLATE_ROCKY92_SINGLE_ID="$template_id"
            ;;

        "PXEGrub2 Rocky9.8 UEFI RAID Kickstart")
            TEMPLATE_ROCKY98_RAID_ID="$template_id"
            ;;

        "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart")
            TEMPLATE_ROCKY98_SINGLE_ID="$template_id"
            ;;

    esac
}

###############################################################################
# ASSOCIATE TEMPLATE WITH OS
#
# We update the provisioning template's operatingsystem_ids.
#
# Existing associations are preserved.
###############################################################################

associate_template()
{
    local os_name="$1"
    local os_id="$2"
    local template_name="$3"
    local template_id="$4"

    subsection "Associating:"
    echo "OS       : $os_name"
    echo "Template : $template_name"

    if [ -z "$os_id" ] || ! [[ "$os_id" =~ ^[0-9]+$ ]]; then
        error "Invalid OS ID for $os_name: $os_id"
        return 1
    fi

    if [ -z "$template_id" ] || ! [[ "$template_id" =~ ^[0-9]+$ ]]; then
        error "Invalid template ID for $template_name: $template_id"
        return 1
    fi

    #
    # Read template.
    #
    api_call GET "/provisioning_templates/${template_id}"

    if [ "$RESULT_STATUS" != "200" ]; then
        error "Unable to read template $template_name."
        return 1
    fi

    local already_associated
    already_associated="$(
        echo "$RESULT_BODY" |
        jq -r --argjson os "$os_id" '
            [
                .operatingsystems[]?
                | select(.id == $os)
            ]
            | length
        '
    )"

    if [ "$already_associated" = "1" ]; then
        skip "Template already associated."
        return 0
    fi

    info "Associating template..."

    local os_ids

    os_ids="$(
        echo "$RESULT_BODY" |
        jq \
            --argjson os "$os_id" '
            [
                (.operatingsystems // [])[]
                | .id
            ]
            + [$os]
            | unique
            '
    )"

    local payload

    payload="$(
        jq -n \
            --argjson ids "$os_ids" '
            {
                provisioning_template: {
                    operatingsystem_ids: $ids
                }
            }
            '
    )"

    api_call PUT "/provisioning_templates/${template_id}" "$payload"

    if [[ "$RESULT_STATUS" =~ ^2[0-9][0-9]$ ]]; then
        ok "Template associated with $os_name."
    else
        error "Failed associating $template_name with $os_name."
        echo "$RESULT_BODY"
        return 1
    fi
}

###############################################################################
# DEFAULT PXEGRUB2 TEMPLATE
#
# Foreman allows only one default template per template kind for an OS.
#
# Therefore:
#
#   GET existing defaults
#   ↓
#   find PXEGrub2
#   ↓
#   PUT existing record
#   OR
#   POST if none exists
###############################################################################

set_default_template()
{
    local os_name="$1"
    local os_id="$2"
    local template_name="$3"
    local template_id="$4"

    subsection "Setting PXEGrub2 Default:"
    echo "OS       : $os_name"
    echo "Template : $template_name"

    if [ -z "$os_id" ] || ! [[ "$os_id" =~ ^[0-9]+$ ]]; then
        error "Invalid OS ID: $os_id"
        return 1
    fi

    if [ -z "$template_id" ] || ! [[ "$template_id" =~ ^[0-9]+$ ]]; then
        error "Invalid template ID: $template_id"
        return 1
    fi

    if [ -z "$PXEGRUB2_KIND_ID" ] || ! [[ "$PXEGRUB2_KIND_ID" =~ ^[0-9]+$ ]]; then
        error "PXEGrub2 template kind ID is empty."
        return 1
    fi

    api_call GET "/operatingsystems/${os_id}/os_default_templates"

    if [ "$RESULT_STATUS" != "200" ]; then
        error "Unable to query OS default templates."
        echo "$RESULT_BODY"
        return 1
    fi

    local existing_default_id

    existing_default_id="$(
        echo "$RESULT_BODY" |
        jq -r \
            --argjson kind "$PXEGRUB2_KIND_ID" '
            .results[]
            | select(.template_kind_id == $kind)
            | .id
        ' |
        head -n 1
    )"

    local payload

    payload="$(
        jq -n \
            --argjson template "$template_id" \
            --argjson kind "$PXEGRUB2_KIND_ID" '
            {
                os_default_template: {
                    provisioning_template_id: $template,
                    template_kind_id: $kind
                }
            }
            '
    )"

    if [ -n "$existing_default_id" ] &&
       [ "$existing_default_id" != "null" ]; then

        info "Existing PXEGrub2 default found. ID=$existing_default_id"
        info "Updating default template..."

        api_call PUT \
            "/operatingsystems/${os_id}/os_default_templates/${existing_default_id}" \
            "$payload"

        if [[ "$RESULT_STATUS" =~ ^2[0-9][0-9]$ ]]; then
            ok "PXEGrub2 default updated."
        else
            error "Failed updating PXEGrub2 default."
            echo "$RESULT_BODY"
            return 1
        fi

    else

        info "No PXEGrub2 default found. Creating one..."

        api_call POST \
            "/operatingsystems/${os_id}/os_default_templates" \
            "$payload"

        if [[ "$RESULT_STATUS" =~ ^2[0-9][0-9]$ ]]; then
            ok "PXEGrub2 default created."
        else
            error "Failed creating PXEGrub2 default."
            echo "$RESULT_BODY"
            return 1
        fi

    fi
}

###############################################################################
# PXE SUBNET
###############################################################################

find_domain_id()
{
    get_collection "/domains"

    if [ "$RESULT_STATUS" != "200" ]; then
        return 1
    fi

    echo "$RESULT_BODY" |
        jq -r '
            .results[]
            | select(.name == "vgs.com")
            | .id
        ' |
        head -n 1
}

find_proxy_id()
{
    local name="$1"

    get_collection "/smart_proxies"

    if [ "$RESULT_STATUS" != "200" ]; then
        return 1
    fi

    echo "$RESULT_BODY" |
        jq -r --arg name "$name" '
            .results[]
            | select(.name == $name)
            | .id
        ' |
        head -n 1
}

find_subnet_id()
{
    local name="$1"

    get_collection "/subnets"

    if [ "$RESULT_STATUS" != "200" ]; then
        return 1
    fi

    echo "$RESULT_BODY" |
        jq -r --arg name "$name" '
            .results[]
            | select(.name == $name)
            | .id
        ' |
        head -n 1
}

create_or_update_subnet()
{
    local name="$1"
    local tftp_proxy_name="$2"
    local dhcp_proxy_name="$3"

    subsection "Subnet : $name"

    echo "Network      : $NETWORK"
    echo "Mask         : $MASK"
    echo "Gateway      : $GATEWAY"
    echo "DNS          : $DNS_PRIMARY"
    echo "TFTP Proxy   : $tftp_proxy_name"
    echo "DHCP Proxy   : $dhcp_proxy_name"

    local domain_id
    local tftp_id
    local dhcp_id
    local subnet_id

    domain_id="$(find_domain_id)"

    if [ -z "$domain_id" ] || [ "$domain_id" = "null" ]; then
        error "Domain vgs.com not found."
        return 1
    fi

    ok "Domain found : vgs.com ID=$domain_id"

    tftp_id="$(find_proxy_id "$tftp_proxy_name")"

    if [ -z "$tftp_id" ] || [ "$tftp_id" = "null" ]; then
        error "TFTP proxy not found : $tftp_proxy_name"
        return 1
    fi

    ok "TFTP/DHCP proxy found : $tftp_proxy_name ID=$tftp_id"

    dhcp_id="$(find_proxy_id "$dhcp_proxy_name")"

    if [ -z "$dhcp_id" ] || [ "$dhcp_id" = "null" ]; then
        error "DHCP proxy not found : $dhcp_proxy_name"
        return 1
    fi

    ok "TFTP/DHCP proxy found : $dhcp_proxy_name ID=$dhcp_id"

    subnet_id="$(find_subnet_id "$name")"

    local payload

    payload="$(
        jq -n \
            --arg name "$name" \
            --arg network "$NETWORK" \
            --arg mask "$MASK" \
            --arg gateway "$GATEWAY" \
            --arg dns "$DNS_PRIMARY" \
            --argjson domain "$domain_id" \
            --argjson tftp "$tftp_id" \
            --argjson dhcp "$dhcp_id" '
            {
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
            }
            '
    )"

    if [ -n "$subnet_id" ] && [ "$subnet_id" != "null" ]; then

        skip "$name already exists. ID=$subnet_id"

        api_call PUT "/subnets/${subnet_id}" "$payload"

        if [[ "$RESULT_STATUS" =~ ^2[0-9][0-9]$ ]]; then
            ok "$name updated."
        else
            error "Unable to update $name."
            echo "$RESULT_BODY"
            return 1
        fi

    else

        info "Creating $name..."

        api_call POST "/subnets" "$payload"

        if [[ "$RESULT_STATUS" =~ ^2[0-9][0-9]$ ]]; then
            subnet_id="$RESULT_ID"
            ok "$name created. ID=$subnet_id"
        else
            error "Unable to create $name."
            echo "$RESULT_BODY"
            return 1
        fi

    fi
}

verify_subnets()
{
    section "PXE Subnet Verification"

    get_collection "/subnets"

    if [ "$RESULT_STATUS" != "200" ]; then
        error "Unable to list subnets."
        return 1
    fi

    echo "$RESULT_BODY" |
        jq -r '
            .results[]
            | select(
                .name == "vgs-subnet-centos" or
                .name == "vgs-subnet-rockyos"
              )
            | [
                .id,
                .name,
                (.network + "/" + ((.mask // "255.255.255.0") | tostring)),
                ((.dhcp.name // "-")),
                ((.tftp.name // "-"))
              ]
            | @tsv
        ' |
        while IFS=$'\t' read -r id name network dhcp tftp; do
            printf "%-4s %-25s %-18s DHCP=%-25s TFTP=%s\n" \
                "$id" "$name" "$network" "$dhcp" "$tftp"
        done
}

###############################################################################
# TEMPLATE VERIFICATION
###############################################################################

verify_templates()
{
    section "PXEGrub2 Template Verification"

    get_collection "/provisioning_templates"

    if [ "$RESULT_STATUS" != "200" ]; then
        error "Unable to list provisioning templates."
        return 1
    fi

    echo "$RESULT_BODY" |
        jq -r '
            .results[]
            | select(
                .name == "PXEGrub2 CentOS UEFI RAID Kickstart" or
                .name == "PXEGrub2 CentOS UEFI SingleDisk Kickstart" or
                .name == "PXEGrub2 Rocky8 UEFI RAID Kickstart" or
                .name == "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" or
                .name == "PXEGrub2 Rocky9.2 UEFI RAID Kickstart" or
                .name == "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart" or
                .name == "PXEGrub2 Rocky9.8 UEFI RAID Kickstart" or
                .name == "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"
              )
            | [
                .id,
                .name,
                (.template_kind_id // ""),
                (.template_kind_name // "")
              ]
            | @tsv
        ' |
        while IFS=$'\t' read -r id name kind_id kind_name; do
            printf "%-5s %-55s kind_id=%-5s kind=%s\n" \
                "$id" "$name" "$kind_id" "$kind_name"
        done
}

###############################################################################
# OS TEMPLATE MAPPING VERIFICATION
###############################################################################

verify_os_mapping()
{
    section "OS Template Mapping Verification"

    verify_os_mapping_one \
        "$CENTOS_RAID_ID" \
        "CentOSLinux7-RAID" \
        "$TEMPLATE_CENTOS_RAID_ID" \
        "PXEGrub2 CentOS UEFI RAID Kickstart"

    verify_os_mapping_one \
        "$CENTOS_SINGLE_ID" \
        "CentOSLinux7-SingleDisk" \
        "$TEMPLATE_CENTOS_SINGLE_ID" \
        "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

    verify_os_mapping_one \
        "$ROCKY8_RAID_ID" \
        "RockyLinux8.10-RAID" \
        "$TEMPLATE_ROCKY8_RAID_ID" \
        "PXEGrub2 Rocky8 UEFI RAID Kickstart"

    verify_os_mapping_one \
        "$ROCKY8_SINGLE_ID" \
        "RockyLinux8.10-SingleDisk" \
        "$TEMPLATE_ROCKY8_SINGLE_ID" \
        "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

    verify_os_mapping_one \
        "$ROCKY92_RAID_ID" \
        "RockyLinux9.2-RAID" \
        "$TEMPLATE_ROCKY92_RAID_ID" \
        "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

    verify_os_mapping_one \
        "$ROCKY92_SINGLE_ID" \
        "RockyLinux9.2-SingleDisk" \
        "$TEMPLATE_ROCKY92_SINGLE_ID" \
        "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

    verify_os_mapping_one \
        "$ROCKY98_RAID_ID" \
        "RockyLinux9.8-RAID" \
        "$TEMPLATE_ROCKY98_RAID_ID" \
        "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

    verify_os_mapping_one \
        "$ROCKY98_SINGLE_ID" \
        "RockyLinux9.8-SingleDisk" \
        "$TEMPLATE_ROCKY98_SINGLE_ID" \
        "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"
}

verify_os_mapping_one()
{
    local os_id="$1"
    local os_name="$2"
    local template_id="$3"
    local template_name="$4"

    api_call GET "/operatingsystems/${os_id}"

    if [ "$RESULT_STATUS" != "200" ]; then
        error "$os_name could not be read."
        return
    fi

    local count

    count="$(
        echo "$RESULT_BODY" |
        jq -r --argjson tid "$template_id" '
            [
                .provisioning_templates[]?
                | select(.id == $tid)
            ]
            | length
        '
    )"

    if [ "$count" = "1" ]; then
        ok "$os_name -> $template_name"
    else
        error "$os_name -> $template_name association missing."
    fi
}

###############################################################################
# DEFAULT TEMPLATE VERIFICATION
###############################################################################

verify_default_template()
{
    section "PXEGrub2 Default Template Verification"

    verify_default_one \
        "$CENTOS_RAID_ID" \
        "CentOSLinux7-RAID" \
        "$TEMPLATE_CENTOS_RAID_ID"

    verify_default_one \
        "$CENTOS_SINGLE_ID" \
        "CentOSLinux7-SingleDisk" \
        "$TEMPLATE_CENTOS_SINGLE_ID"

    verify_default_one \
        "$ROCKY8_RAID_ID" \
        "RockyLinux8.10-RAID" \
        "$TEMPLATE_ROCKY8_RAID_ID"

    verify_default_one \
        "$ROCKY8_SINGLE_ID" \
        "RockyLinux8.10-SingleDisk" \
        "$TEMPLATE_ROCKY8_SINGLE_ID"

    verify_default_one \
        "$ROCKY92_RAID_ID" \
        "RockyLinux9.2-RAID" \
        "$TEMPLATE_ROCKY92_RAID_ID"

    verify_default_one \
        "$ROCKY92_SINGLE_ID" \
        "RockyLinux9.2-SingleDisk" \
        "$TEMPLATE_ROCKY92_SINGLE_ID"

    verify_default_one \
        "$ROCKY98_RAID_ID" \
        "RockyLinux9.8-RAID" \
        "$TEMPLATE_ROCKY98_RAID_ID"

    verify_default_one \
        "$ROCKY98_SINGLE_ID" \
        "RockyLinux9.8-SingleDisk" \
        "$TEMPLATE_ROCKY98_SINGLE_ID"
}

verify_default_one()
{
    local os_id="$1"
    local os_name="$2"
    local expected_template_id="$3"

    api_call GET "/operatingsystems/${os_id}/os_default_templates"

    if [ "$RESULT_STATUS" != "200" ]; then
        error "$os_name default template query failed."
        return
    fi

    local actual_template_id

    actual_template_id="$(
        echo "$RESULT_BODY" |
        jq -r \
            --argjson kind "$PXEGRUB2_KIND_ID" '
            .results[]
            | select(.template_kind_id == $kind)
            | .provisioning_template_id
        ' |
        head -n 1
    )"

    if [ "$actual_template_id" = "$expected_template_id" ]; then
        ok "$os_name default template verified."
    else
        error "$os_name default template incorrect/missing."
        echo "       Expected : $expected_template_id"
        echo "       Actual   : ${actual_template_id:-<none>}"
    fi
}

###############################################################################
# FINAL OS VERIFICATION
###############################################################################

final_os_verification()
{
    section "Final Operating System Verification"

    final_os "$CENTOS_RAID_ID" "CentOSLinux7-RAID"
    final_os "$CENTOS_SINGLE_ID" "CentOSLinux7-SingleDisk"

    final_os "$ROCKY8_RAID_ID" "RockyLinux8.10-RAID"
    final_os "$ROCKY8_SINGLE_ID" "RockyLinux8.10-SingleDisk"

    final_os "$ROCKY92_RAID_ID" "RockyLinux9.2-RAID"
    final_os "$ROCKY92_SINGLE_ID" "RockyLinux9.2-SingleDisk"

    final_os "$ROCKY98_RAID_ID" "RockyLinux9.8-RAID"
    final_os "$ROCKY98_SINGLE_ID" "RockyLinux9.8-SingleDisk"
}

final_os()
{
    local os_id="$1"
    local os_name="$2"

    echo
    echo "------------------------------------------------------------"
    echo "OS : $os_name"
    echo "ID : $os_id"
    echo "------------------------------------------------------------"

    if [ -z "$os_id" ] || ! [[ "$os_id" =~ ^[0-9]+$ ]]; then
        error "$os_name has no valid ID."
        return
    fi

    api_call GET "/operatingsystems/${os_id}"

    if [ "$RESULT_STATUS" != "200" ]; then
        error "Unable to read $os_name."
        return
    fi

    echo "$RESULT_BODY" |
        jq -r '
            "Name          : \(.name)",
            "Title         : \(.title)",
            "Major         : \(.major)",
            "Minor         : \(.minor // "")",
            "Family        : \(.family // "")",
            "Architecture  : \((.architectures // []) | map(.name) | join(", "))",
            "Media         : \((.media // []) | map(.name) | join(", "))",
            "Ptable        : \((.ptables // []) | map(.name) | join(", "))",
            "Templates     : \((.provisioning_templates // []) | map(.name) | join(", "))"
        '
}

###############################################################################
# GENERATED FILE VERIFICATION
###############################################################################

verify_generated_files()
{
    section "Generated PXE Template Files"

    ls -lh "${TMP_DIR}"/*.erb
}

###############################################################################
# MANUAL API VERIFICATION
###############################################################################

manual_api_verification()
{
    section "Manual API Verification"

    echo
    echo "Foreman status:"
    echo
    echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  ${FOREMAN_URL}/api/status"

    echo
    echo "PXEGrub2 templates:"
    echo
    echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${FOREMAN_URL}/api/provisioning_templates?per_page=all' | jq"

    echo
    echo "Operating systems:"
    echo
    echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${FOREMAN_URL}/api/operatingsystems?per_page=all' | jq"

    echo
    echo "Subnets:"
    echo
    echo "curl -k --user \"admin:\$FOREMAN_TOKEN\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${FOREMAN_URL}/api/subnets?per_page=all' | jq"
}

###############################################################################
# MAIN
###############################################################################

main()
{
    section "01 - Foreman PXE Bootstrap - REST API"

    check_dependencies
    prepare_directories

    section "Foreman API Authentication Test"
    test_api

    find_architecture
    find_ptable

    ###########################################################################
    # INSTALLATION MEDIA
    ###########################################################################

    section "Creating Installation Media"

    create_or_update_media \
        "CentOS 7 Remote" \
        "$CENTOS_REPO" \
        CENTOS_MEDIA_ID

    create_or_update_media \
        "Rocky 8 Remote" \
        "$ROCKY8_REPO" \
        ROCKY8_MEDIA_ID

    create_or_update_media \
        "Rocky 9.2 Remote" \
        "$ROCKY92_REPO" \
        ROCKY92_MEDIA_ID

    create_or_update_media \
        "Rocky 9 Remote" \
        "$ROCKY98_REPO" \
        ROCKY98_MEDIA_ID

    verify_media

    ###########################################################################
    # OPERATING SYSTEMS
    ###########################################################################

    section "Creating Operating Systems"

    create_or_update_os \
        "CentOSLinux7-RAID" \
        "7" \
        "" \
        "Redhat" \
        "$CENTOS_MEDIA_ID"

    create_or_update_os \
        "CentOSLinux7-SingleDisk" \
        "7" \
        "" \
        "Redhat" \
        "$CENTOS_MEDIA_ID"

    create_or_update_os \
        "RockyLinux8.10-RAID" \
        "8" \
        "10" \
        "Redhat" \
        "$ROCKY8_MEDIA_ID"

    create_or_update_os \
        "RockyLinux8.10-SingleDisk" \
        "8" \
        "10" \
        "Redhat" \
        "$ROCKY8_MEDIA_ID"

    create_or_update_os \
        "RockyLinux9.2-RAID" \
        "9" \
        "2" \
        "Redhat" \
        "$ROCKY92_MEDIA_ID"

    create_or_update_os \
        "RockyLinux9.2-SingleDisk" \
        "9" \
        "2" \
        "Redhat" \
        "$ROCKY92_MEDIA_ID"

    create_or_update_os \
        "RockyLinux9.8-RAID" \
        "9" \
        "8" \
        "Redhat" \
        "$ROCKY98_MEDIA_ID"

    create_or_update_os \
        "RockyLinux9.8-SingleDisk" \
        "9" \
        "8" \
        "Redhat" \
        "$ROCKY98_MEDIA_ID"

    verify_os

    ###########################################################################
    # PXEGRUB2 TEMPLATES
    ###########################################################################

    generate_template_files

    find_pxegrub2_kind

    section "Creating PXEGrub2 Templates"

    create_or_update_template \
        "PXEGrub2 CentOS UEFI RAID Kickstart" \
        "${TMP_DIR}/centos-raid.erb"

    create_or_update_template \
        "PXEGrub2 CentOS UEFI SingleDisk Kickstart" \
        "${TMP_DIR}/centos-singledisk.erb"

    create_or_update_template \
        "PXEGrub2 Rocky8 UEFI RAID Kickstart" \
        "${TMP_DIR}/rocky8-raid.erb"

    create_or_update_template \
        "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" \
        "${TMP_DIR}/rocky8-singledisk.erb"

    create_or_update_template \
        "PXEGrub2 Rocky9.2 UEFI RAID Kickstart" \
        "${TMP_DIR}/rocky92-raid.erb"

    create_or_update_template \
        "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart" \
        "${TMP_DIR}/rocky92-singledisk.erb"

    create_or_update_template \
        "PXEGrub2 Rocky9.8 UEFI RAID Kickstart" \
        "${TMP_DIR}/rocky98-raid.erb"

    create_or_update_template \
        "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart" \
        "${TMP_DIR}/rocky98-singledisk.erb"

    ###########################################################################
    # ASSOCIATIONS
    ###########################################################################

    section "Associating PXEGrub2 Templates"

    associate_template \
        "CentOSLinux7-RAID" \
        "$CENTOS_RAID_ID" \
        "PXEGrub2 CentOS UEFI RAID Kickstart" \
        "$TEMPLATE_CENTOS_RAID_ID"

    associate_template \
        "CentOSLinux7-SingleDisk" \
        "$CENTOS_SINGLE_ID" \
        "PXEGrub2 CentOS UEFI SingleDisk Kickstart" \
        "$TEMPLATE_CENTOS_SINGLE_ID"

    associate_template \
        "RockyLinux8.10-RAID" \
        "$ROCKY8_RAID_ID" \
        "PXEGrub2 Rocky8 UEFI RAID Kickstart" \
        "$TEMPLATE_ROCKY8_RAID_ID"

    associate_template \
        "RockyLinux8.10-SingleDisk" \
        "$ROCKY8_SINGLE_ID" \
        "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" \
        "$TEMPLATE_ROCKY8_SINGLE_ID"

    associate_template \
        "RockyLinux9.2-RAID" \
        "$ROCKY92_RAID_ID" \
        "PXEGrub2 Rocky9.2 UEFI RAID Kickstart" \
        "$TEMPLATE_ROCKY92_RAID_ID"

    associate_template \
        "RockyLinux9.2-SingleDisk" \
        "$ROCKY92_SINGLE_ID" \
        "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart" \
        "$TEMPLATE_ROCKY92_SINGLE_ID"

    associate_template \
        "RockyLinux9.8-RAID" \
        "$ROCKY98_RAID_ID" \
        "PXEGrub2 Rocky9.8 UEFI RAID Kickstart" \
        "$TEMPLATE_ROCKY98_RAID_ID"

    associate_template \
        "RockyLinux9.8-SingleDisk" \
        "$ROCKY98_SINGLE_ID" \
        "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart" \
        "$TEMPLATE_ROCKY98_SINGLE_ID"

    ###########################################################################
    # DEFAULT PXEGRUB2 TEMPLATES
    ###########################################################################

    section "Setting PXEGrub2 Default Templates"

    set_default_template \
        "CentOSLinux7-RAID" \
        "$CENTOS_RAID_ID" \
        "PXEGrub2 CentOS UEFI RAID Kickstart" \
        "$TEMPLATE_CENTOS_RAID_ID"

    set_default_template \
        "CentOSLinux7-SingleDisk" \
        "$CENTOS_SINGLE_ID" \
        "PXEGrub2 CentOS UEFI SingleDisk Kickstart" \
        "$TEMPLATE_CENTOS_SINGLE_ID"

    set_default_template \
        "RockyLinux8.10-RAID" \
        "$ROCKY8_RAID_ID" \
        "PXEGrub2 Rocky8 UEFI RAID Kickstart" \
        "$TEMPLATE_ROCKY8_RAID_ID"

    set_default_template \
        "RockyLinux8.10-SingleDisk" \
        "$ROCKY8_SINGLE_ID" \
        "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" \
        "$TEMPLATE_ROCKY8_SINGLE_ID"

    set_default_template \
        "RockyLinux9.2-RAID" \
        "$ROCKY92_RAID_ID" \
        "PXEGrub2 Rocky9.2 UEFI RAID Kickstart" \
        "$TEMPLATE_ROCKY92_RAID_ID"

    set_default_template \
        "RockyLinux9.2-SingleDisk" \
        "$ROCKY92_SINGLE_ID" \
        "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart" \
        "$TEMPLATE_ROCKY92_SINGLE_ID"

    set_default_template \
        "RockyLinux9.8-RAID" \
        "$ROCKY98_RAID_ID" \
        "PXEGrub2 Rocky9.8 UEFI RAID Kickstart" \
        "$TEMPLATE_ROCKY98_RAID_ID"

    set_default_template \
        "RockyLinux9.8-SingleDisk" \
        "$ROCKY98_SINGLE_ID" \
        "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart" \
        "$TEMPLATE_ROCKY98_SINGLE_ID"

    ###########################################################################
    # SUBNETS
    ###########################################################################

    section "Creating PXE Subnets"

    create_or_update_subnet \
        "$CENTOS_SUBNET_NAME" \
        "$CENTOS_PROXY" \
        "$CENTOS_PROXY"

    create_or_update_subnet \
        "$ROCKY_SUBNET_NAME" \
        "$ROCKY_PROXY" \
        "$ROCKY_PROXY"

    ###########################################################################
    # VERIFICATION
    ###########################################################################

    verify_subnets

    verify_templates

    verify_os_mapping

    verify_default_template

    final_os_verification

    verify_generated_files

    ###########################################################################
    # MANUAL COMMANDS
    ###########################################################################

    manual_api_verification

    ###########################################################################
    # SUMMARY
    ###########################################################################

    section "01 - Foreman PXE Bootstrap API Completed"

    if [ "$FAILURES" -eq 0 ]; then
        ok "Completed successfully with 0 failures."
    else
        warn "Completed with ${FAILURES} failure(s)."
        exit 1
    fi
}

###############################################################################
# RUN
###############################################################################

main "$@"
