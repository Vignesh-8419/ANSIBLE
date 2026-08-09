```bash
#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap - REST API
#
# Foreman 3.2.x / Katello
#
# Creates / verifies:
#   1. Installation Media
#   2. Operating Systems
#   3. PXEGrub2 provisioning templates
#   4. OS <-> PXEGrub2 associations
#   5. PXEGrub2 OS default templates
#   6. PXE subnets
#   7. Final verification
#
# IMPORTANT:
#   - Existing resources are NOT duplicated.
#   - Existing PXEGrub2 defaults are UPDATED.
#   - API response is preserved before recovery requests.
#   - No mktemp/rm temporary API files are required.
###############################################################################

set -u

###############################################################################
# CONFIGURATION
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
FOREMAN_USER="${FOREMAN_USER:-admin}"

# PAT
#
# Preferred:
#   export FOREMAN_TOKEN='YOUR_PAT'
#
# Or put the PAT below.
#
FOREMAN_TOKEN="${FOREMAN_TOKEN:-YOUR_PAT_HERE}"

API="${FOREMAN_URL}/api"

API_VERSION="2"

###############################################################################
# Repository URLs
###############################################################################

CENTOS7_URL="http://192.168.253.136/repo/centos/"
ROCKY8_URL="http://192.168.253.136/repo/rocky8/"
ROCKY92_URL="http://192.168.253.136/repo/rocky9.2/"
ROCKY98_URL="http://192.168.253.136/repo/rocky9/"

###############################################################################
# PXE subnet configuration
###############################################################################

CENTOS_SUBNET_NAME="vgs-subnet-centos"
CENTOS_NETWORK="192.168.253.0"
CENTOS_MASK="255.255.255.0"
CENTOS_GATEWAY="192.168.253.2"
CENTOS_DNS="192.168.253.1"
CENTOS_TFTP_PROXY="cent-07-01.vgs.com"
CENTOS_DHCP_PROXY="cent-07-01.vgs.com"

ROCKY_SUBNET_NAME="vgs-subnet-rockyos"
ROCKY_NETWORK="192.168.253.0"
ROCKY_MASK="255.255.255.0"
ROCKY_GATEWAY="192.168.253.2"
ROCKY_DNS="192.168.253.1"
ROCKY_TFTP_PROXY="cent-07-02.vgs.com"
ROCKY_DHCP_PROXY="cent-07-02.vgs.com"

DOMAIN_NAME="vgs.com"

###############################################################################
# Working directory
###############################################################################

TEMPLATE_DIR="/tmp/foreman-pxe-bootstrap"

mkdir -p "$TEMPLATE_DIR"

###############################################################################
# Required commands
###############################################################################

CURL="$(command -v curl 2>/dev/null || true)"
JQ="$(command -v jq 2>/dev/null || true)"
CAT="$(command -v cat 2>/dev/null || true)"
HEAD="$(command -v head 2>/dev/null || true)"
GREP="$(command -v grep 2>/dev/null || true)"
AWK="$(command -v awk 2>/dev/null || true)"
SED="$(command -v sed 2>/dev/null || true)"
MKDIR="$(command -v mkdir 2>/dev/null || true)"

###############################################################################
# COLORS
###############################################################################

if [ -t 1 ]; then
    C_RESET=$'\033[0m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
    C_BOLD=$'\033[1m'
else
    C_RESET=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_CYAN=""
    C_BOLD=""
fi

###############################################################################
# STATUS
###############################################################################

FAILURES=0

API_STATUS=""
API_BODY=""

ARCH_ID=""
PTABLE_ID=""
PXEGRUB2_KIND_ID=""

###############################################################################
# ARRAYS
###############################################################################

declare -a MEDIA_NAMES=()
declare -a MEDIA_PATHS=()

declare -a OS_NAMES=()
declare -a OS_MAJOR=()
declare -a OS_MINOR=()
declare -a OS_MEDIA=()
declare -a OS_IDS=()
declare -a TEMPLATE_NAMES=()
declare -a TEMPLATE_FILES=()
declare -a TEMPLATE_IDS=()

###############################################################################
# LOGGING
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
    echo "${C_CYAN}[INFO]${C_RESET} $*"
}

ok()
{
    echo "${C_GREEN}[OK]${C_RESET} $*"
}

skip()
{
    echo "${C_YELLOW}[SKIP]${C_RESET} $*"
}

warn()
{
    echo "${C_YELLOW}[WARN]${C_RESET} $*"
}

error()
{
    echo "${C_RED}[ERROR]${C_RESET} $*"
}

record_failure()
{
    FAILURES=$((FAILURES + 1))
}

###############################################################################
# COMMAND CHECK
###############################################################################

check_dependencies()
{
    section "Dependency Check"

    local failed=0
    local cmd
    local path

    for cmd in curl jq cat head grep awk sed mkdir
    do
        path="$(command -v "$cmd" 2>/dev/null || true)"

        if [ -n "$path" ]; then
            ok "$cmd found: $path"
        else
            error "$cmd not found"
            failed=1
        fi
    done

    if [ "$failed" -ne 0 ]; then
        exit 1
    fi
}

###############################################################################
# TOKEN CHECK
###############################################################################

check_token()
{
    if [ -z "${FOREMAN_TOKEN:-}" ] ||
       [ "${FOREMAN_TOKEN}" = "YOUR_PAT_HERE" ]; then

        error "FOREMAN_TOKEN is not configured."

        echo
        echo "Set it with:"
        echo
        echo "export FOREMAN_TOKEN='YOUR_PAT_HERE'"
        echo
        exit 1
    fi
}

###############################################################################
# API REQUEST
#
# Usage:
#   api_request GET URL
#   api_request POST URL JSON
#   api_request PUT URL JSON
#
# API_STATUS and API_BODY are always replaced with THIS request.
###############################################################################

api_request()
{
    local method="$1"
    local url="$2"
    local json="${3:-}"

    API_STATUS=""
    API_BODY=""

    if [ "$method" = "GET" ]; then

        API_BODY="$(
            "$CURL" -ksS \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                -H "Accept: application/json,version=${API_VERSION}" \
                -w $'\n__HTTP_STATUS__%{http_code}' \
                "$url" 2>&1
        )"

    else

        API_BODY="$(
            "$CURL" -ksS \
                --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
                -H "Accept: application/json,version=${API_VERSION}" \
                -H "Content-Type: application/json" \
                -X "$method" \
                -d "$json" \
                -w $'\n__HTTP_STATUS__%{http_code}' \
                "$url" 2>&1
        )"

    fi

    API_STATUS="$(
        printf '%s\n' "$API_BODY" |
        "$SED" -n 's/^__HTTP_STATUS__//p' |
        "$HEAD" -1
    )"

    API_BODY="$(
        printf '%s\n' "$API_BODY" |
        "$SED" '/^__HTTP_STATUS__/d'
    )"
}

###############################################################################
# API SUCCESS
###############################################################################

api_success()
{
    [[ "${API_STATUS:-}" =~ ^2[0-9][0-9]$ ]]
}

###############################################################################
# JSON VALIDATION
###############################################################################

json_valid()
{
    local data="${1:-}"

    [ -n "$data" ] || return 1

    printf '%s\n' "$data" |
        "$JQ" empty >/dev/null 2>&1
}

###############################################################################
# API ERROR
###############################################################################

print_api_error()
{
    local method="${1:-UNKNOWN}"
    local url="${2:-UNKNOWN}"

    error "API request failed."
    error "HTTP Status : ${API_STATUS:-UNKNOWN}"
    error "Method      : ${method}"
    error "URL         : ${url}"

    if [ -n "${API_BODY:-}" ]; then
        echo
        printf '%s\n' "$API_BODY" |
            "$JQ" . 2>/dev/null ||
            printf '%s\n' "$API_BODY"
    fi
}

###############################################################################
# FIND ID BY NAME
###############################################################################

find_id_by_name()
{
    local endpoint="$1"
    local name="$2"

    api_request GET "${API}/${endpoint}?search=${name}&per_page=all"

    if ! api_success || ! json_valid "$API_BODY"; then
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
# FIND ARCHITECTURE
###############################################################################

find_architecture()
{
    section "Finding Architecture"

    api_request GET "${API}/architectures?per_page=all"

    if ! api_success || ! json_valid "$API_BODY"; then
        print_api_error GET "${API}/architectures?per_page=all"
        exit 1
    fi

    ARCH_ID="$(
        printf '%s\n' "$API_BODY" |
        "$JQ" -r '
            (.results // [])[]
            | select(
                (.name == "x86_64")
                or
                (.name == "x86-64")
            )
            | .id
        ' |
        "$HEAD" -1
    )"

    if [ -z "$ARCH_ID" ] || [ "$ARCH_ID" = "null" ]; then
        error "x86_64 architecture not found."
        exit 1
    fi

    ok "x86_64 architecture found. ID=${ARCH_ID}"
}

###############################################################################
# FIND PARTITION TABLE
###############################################################################

find_partition_table()
{
    section "Finding Partition Table"

    api_request GET "${API}/ptables?per_page=all"

    if ! api_success || ! json_valid "$API_BODY"; then
        print_api_error GET "${API}/ptables?per_page=all"
        exit 1
    fi

    PTABLE_ID="$(
        printf '%s\n' "$API_BODY" |
        "$JQ" -r '
            (.results // [])[]
            | select(
                (.name == "Kickstart default")
                or
                (.name == "Kickstart default partition table")
            )
            | .id
        ' |
        "$HEAD" -1
    )"

    if [ -z "$PTABLE_ID" ] || [ "$PTABLE_ID" = "null" ]; then
        error "Kickstart default partition table not found."
        exit 1
    fi

    ok "Kickstart default partition table found. ID=${PTABLE_ID}"
}

###############################################################################
# MEDIA ARRAYS
###############################################################################

load_media_configuration()
{
    MEDIA_NAMES=(
        "CentOS 7 Remote"
        "Rocky 8 Remote"
        "Rocky 9.2 Remote"
        "Rocky 9 Remote"
    )

    MEDIA_PATHS=(
        "$CENTOS7_URL"
        "$ROCKY8_URL"
        "$ROCKY92_URL"
        "$ROCKY98_URL"
    )
}

###############################################################################
# CREATE / VERIFY MEDIA
###############################################################################

create_media()
{
    section "Creating / Verifying Installation Media"

    local i
    local name
    local path
    local id
    local json

    for i in "${!MEDIA_NAMES[@]}"
    do
        name="${MEDIA_NAMES[$i]}"
        path="${MEDIA_PATHS[$i]}"

        subsection "Installation Media : ${name}"

        id="$(find_id_by_name media "$name" || true)"

        if [ -n "$id" ] && [ "$id" != "null" ]; then

            skip "${name} already exists. ID=${id}"

            api_request GET "${API}/media/${id}"

            if api_success && json_valid "$API_BODY"; then

                current_path="$(
                    printf '%s\n' "$API_BODY" |
                    "$JQ" -r '.path // empty'
                )"

                if [ "$current_path" != "$path" ]; then

                    warn "${name} path differs."
                    info "Updating path to ${path}"

                    json="$(
                        "$JQ" -n \
                            --arg path "$path" \
                            '{
                                medium: {
                                    path: $path
                                }
                            }'
                    )"

                    api_request PUT \
                        "${API}/media/${id}" \
                        "$json"

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
                        path: $path
                    }
                }'
        )"

        api_request POST "${API}/media" "$json"

        if api_success; then

            id="$(
                printf '%s\n' "$API_BODY" |
                "$JQ" -r '.id // empty'
            )"

            ok "${name} created. ID=${id}"

        else

            # If it was created concurrently, re-read it.
            id="$(find_id_by_name media "$name" || true)"

            if [ -n "$id" ]; then
                skip "${name} already exists after POST. ID=${id}"
            else
                print_api_error POST "${API}/media"
                record_failure "${name} media creation"
            fi
        fi
    done
}

###############################################################################
# VERIFY MEDIA
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

    printf '%s\n' "$API_BODY" |
        "$JQ" -r '
        (.results // [])[]
        | [
            .id,
            .name,
            .path
        ]
        | @tsv
        '
}

###############################################################################
# OS CONFIGURATION
###############################################################################

load_os_configuration()
{
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

    OS_IDS=()
    TEMPLATE_IDS=()
}

###############################################################################
# CREATE / VERIFY OPERATING SYSTEMS
###############################################################################

create_operating_systems()
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
        media_name="${OS_MEDIA[$i]}"

        subsection "Operating System : ${name}"

        media_id="$(find_id_by_name media "$media_name" || true)"

        if [ -z "$media_id" ]; then
            error "Installation media not found : ${media_name}"
            record_failure "${name} media lookup"
            OS_IDS+=("")
            continue
        fi

        os_id="$(find_id_by_name operatingsystems "$name" || true)"

        if [ -n "$os_id" ] && [ "$os_id" != "null" ]; then

            skip "${name} already exists. ID=${os_id}"

            OS_IDS+=("$os_id")

            # Ensure media / architecture / partition table.
            json="$(
                "$JQ" -n \
                    --argjson major "$major" \
                    --arg minor "$minor" \
                    --argjson media "$media_id" \
                    --argjson arch "$ARCH_ID" \
                    --argjson ptable "$PTABLE_ID" \
                    '{
                        operatingsystem: {
                            major: ($major | tostring),
                            minor: $minor,
                            family: "Redhat",
                            media_ids: [$media],
                            architecture_ids: [$arch],
                            ptables: [$ptable]
                        }
                    }'
            )"

            api_request PUT \
                "${API}/operatingsystems/${os_id}" \
                "$json"

            if api_success; then
                ok "${name} associations verified."
            else
                warn "${name} association update returned HTTP ${API_STATUS}"
                print_api_error PUT "${API}/operatingsystems/${os_id}"
            fi

            continue
        fi

        info "Creating ${name}"

        json="$(
            "$JQ" -n \
                --arg name "$name" \
                --arg major "$major" \
                --arg minor "$minor" \
                --argjson media "$media_id" \
                --argjson arch "$ARCH_ID" \
                --argjson ptable "$PTABLE_ID" \
                '{
                    operatingsystem: {
                        name: $name,
                        major: $major,
                        minor: $minor,
                        family: "Redhat",
                        media_ids: [$media],
                        architecture_ids: [$arch],
                        ptables: [$ptable]
                    }
                }'
        )"

        api_request POST \
            "${API}/operatingsystems" \
            "$json"

        if api_success; then

            os_id="$(
                printf '%s\n' "$API_BODY" |
                "$JQ" -r '.id // empty'
            )"

            ok "${name} created. ID=${os_id}"
            OS_IDS+=("$os_id")

        else

            os_id="$(find_id_by_name operatingsystems "$name" || true)"

            if [ -n "$os_id" ]; then
                skip "${name} already exists after POST. ID=${os_id}"
                OS_IDS+=("$os_id")
            else
                print_api_error POST "${API}/operatingsystems"
                record_failure "${name} OS creation"
                OS_IDS+=("")
            fi
        fi
    done
}

###############################################################################
# VERIFY OS
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

    printf '%s\n' "$API_BODY" |
        "$JQ" -r '
        (.results // [])[]
        | [
            .id,
            .name,
            .major,
            .minor,
            .family
        ]
        | @tsv
        '
}

###############################################################################
# PXEGRUB2 TEMPLATE CONTENT
###############################################################################

template_content()
{
    local key="$1"

    case "$key" in

        centos-raid)
cat <<'EOF'
set default=0
set timeout=10

menuentry 'CentOS Linux 7 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF
            ;;

        centos-singledisk)
cat <<'EOF'
set default=0
set timeout=10

menuentry 'CentOS Linux 7 SingleDisk' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF
            ;;

        rocky8-raid)
cat <<'EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 8 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF
            ;;

        rocky8-singledisk)
cat <<'EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 8 SingleDisk' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF
            ;;

        rocky92-raid)
cat <<'EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.2 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF
            ;;

        rocky92-singledisk)
cat <<'EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.2 SingleDisk' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF
            ;;

        rocky98-raid)
cat <<'EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.8 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF
            ;;

        rocky98-singledisk)
cat <<'EOF'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.8 SingleDisk' {
    linuxefi <%= @host.url %>/boot/vmlinuz inst.stage2=<%= @host.operatingsystem.medium.path %> inst.ks=<%= foreman_url("provision") %> ksdevice=bootif
    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF
            ;;

        *)
            error "Unknown template key: ${key}"
            return 1
            ;;
    esac
}

###############################################################################
# GENERATE TEMPLATE FILES
###############################################################################

generate_template_files()
{
    section "Generating PXEGrub2 Template Files"

    local i
    local file
    local key

    for i in "${!TEMPLATE_FILES[@]}"
    do
        file="${TEMPLATE_FILES[$i]}"

        case "$file" in
            centos-raid.erb)             key="centos-raid" ;;
            centos-singledisk.erb)       key="centos-singledisk" ;;
            rocky8-raid.erb)             key="rocky8-raid" ;;
            rocky8-singledisk.erb)       key="rocky8-singledisk" ;;
            rocky92-raid.erb)            key="rocky92-raid" ;;
            rocky92-singledisk.erb)      key="rocky92-singledisk" ;;
            rocky98-raid.erb)            key="rocky98-raid" ;;
            rocky98-singledisk.erb)      key="rocky98-singledisk" ;;
            *)
                error "Unknown template file ${file}"
                record_failure "Template generation"
                continue
                ;;
        esac

        template_content "$key" > "${TEMPLATE_DIR}/${file}"
    done

    ok "All 8 PXEGrub2 template files generated."

    ls -l "${TEMPLATE_DIR}"/*.erb
}

###############################################################################
# FIND PXEGRUB2 TEMPLATE KIND
###############################################################################

find_pxegrub2_kind()
{
    section "Finding Existing PXEGrub2 Template Kind"

    api_request GET \
        "${API}/provisioning_templates?per_page=all"

    if ! api_success || ! json_valid "$API_BODY"; then
        print_api_error GET \
            "${API}/provisioning_templates?per_page=all"
        exit 1
    fi

    PXEGRUB2_KIND_ID="$(
        printf '%s\n' "$API_BODY" |
        "$JQ" -r '
            (.results // [])[]
            | select(
                (.template_kind_name == "PXEGrub2")
                or
                (.template_kind.name == "PXEGrub2")
            )
            | .template_kind_id
        ' |
        "$HEAD" -1
    )"

    if [ -z "$PXEGRUB2_KIND_ID" ] ||
       [ "$PXEGRUB2_KIND_ID" = "null" ]; then

        error "PXEGrub2 template kind not found."
        exit 1
    fi

    ok "PXEGrub2 template kind found."
    echo "PXEGrub2 Template Kind ID : ${PXEGRUB2_KIND_ID}"
}

###############################################################################
# FIND TEMPLATE BY NAME
###############################################################################

get_template_id()
{
    local name="$1"

    api_request GET \
        "${API}/provisioning_templates?per_page=all"

    if ! api_success || ! json_valid "$API_BODY"; then
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
# CREATE / VERIFY PROVISIONING TEMPLATES
###############################################################################

create_pxe_templates()
{
    section "Creating / Verifying PXEGrub2 Templates"

    local i
    local name
    local file
    local template
    local id
    local json

    TEMPLATE_IDS=()

    for i in "${!TEMPLATE_NAMES[@]}"
    do
        name="${TEMPLATE_NAMES[$i]}"
        file="${TEMPLATE_FILES[$i]}"

        subsection "PXEGrub2 Template : ${name}"

        template="$(
            "$CAT" "${TEMPLATE_DIR}/${file}"
        )"

        id="$(get_template_id "$name" || true)"

        if [ -n "$id" ] && [ "$id" != "null" ]; then

            skip "${name} already exists. ID=${id}"

            json="$(
                "$JQ" -n \
                    --arg template "$template" \
                    --argjson kind "$PXEGRUB2_KIND_ID" \
                    '{
                        provisioning_template: {
                            template: $template,
                            template_kind_id: $kind
                        }
                    }'
            )"

            api_request PUT \
                "${API}/provisioning_templates/${id}" \
                "$json"

            if api_success; then
                ok "${name} updated."
            else
                print_api_error PUT \
                    "${API}/provisioning_templates/${id}"
                record_failure "${name} template update"
            fi

            TEMPLATE_IDS+=("$id")
            continue
        fi

        info "Creating ${name}"

        json="$(
            "$JQ" -n \
                --arg name "$name" \
                --arg template "$template" \
                --argjson kind "$PXEGRUB2_KIND_ID" \
                '{
                    provisioning_template: {
                        name: $name,
                        template: $template,
                        template_kind_id: $kind
                    }
                }'
        )"

        api_request POST \
            "${API}/provisioning_templates" \
            "$json"

        if api_success; then

            id="$(
                printf '%s\n' "$API_BODY" |
                "$JQ" -r '.id // empty'
            )"

            ok "${name} created. ID=${id}"
            TEMPLATE_IDS+=("$id")

        else

            id="$(get_template_id "$name" || true)"

            if [ -n "$id" ]; then
                skip "${name} already exists after POST. ID=${id}"
                TEMPLATE_IDS+=("$id")
            else
                print_api_error POST \
                    "${API}/provisioning_templates"
                record_failure "${name} template creation"
                TEMPLATE_IDS+=("")
            fi
        fi
    done
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
    local exists

    subsection "OS Template Association"

    echo "OS       : ${os_name}"
    echo "OS ID    : ${os_id}"
    echo "Template : ${template_name}"
    echo "Template ID : ${template_id}"

    api_request GET \
        "${API}/operatingsystems/${os_id}/provisioning_templates?per_page=all"

    if api_success && json_valid "$API_BODY"; then

        exists="$(
            printf '%s\n' "$API_BODY" |
            "$JQ" -r \
                --argjson ID "$template_id" \
                '
                (.results // [])[]
                | select(.id == $ID)
                | .id
                ' |
            "$HEAD" -1
        )"

        if [ "$exists" = "$template_id" ]; then
            skip "${os_name} already associated with ${template_name}."
            return
        fi
    fi

    info "Associating ${template_name} with ${os_name}."

    json="$(
        "$JQ" -n \
            --argjson template "$template_id" \
            '{
                provisioning_template_ids: [$template]
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
}

###############################################################################
# ASSOCIATE ALL TEMPLATES
###############################################################################

associate_all_templates()
{
    section "Associating PXEGrub2 Templates"

    local i

    for i in "${!OS_NAMES[@]}"
    do

        if [ -z "${OS_IDS[$i]:-}" ]; then
            error "${OS_NAMES[$i]} has no OS ID."
            record_failure "${OS_NAMES[$i]} association"
            continue
        fi

        if [ -z "${TEMPLATE_IDS[$i]:-}" ]; then
            error "${TEMPLATE_NAMES[$i]} has no template ID."
            record_failure "${TEMPLATE_NAMES[$i]} association"
            continue
        fi

        associate_template \
            "${OS_NAMES[$i]}" \
            "${OS_IDS[$i]}" \
            "${TEMPLATE_NAMES[$i]}" \
            "${TEMPLATE_IDS[$i]}"

    done
}

###############################################################################
# SET PXEGRUB2 DEFAULT
#
# IMPORTANT FIX:
#
# Foreman allows only one default template combination per OS/template kind.
#
# Therefore:
#
#   Existing PXEGrub2 default -> UPDATE it.
#   No PXEGrub2 default       -> CREATE it.
#
# We DO NOT blindly POST.
###############################################################################

set_pxe_default()
{
    local os_name="$1"
    local os_id="$2"
    local template_name="$3"
    local template_id="$4"

    local row
    local default_id
    local current_template_id
    local json

    subsection "PXEGrub2 Default Template"

    echo "OS       : ${os_name}"
    echo "OS ID    : ${os_id}"
    echo "Template : ${template_name}"
    echo "Template ID : ${template_id}"
    echo "Kind ID   : ${PXEGRUB2_KIND_ID}"

    ###########################################################################
    # READ ALL DEFAULTS
    ###########################################################################

    api_request GET \
        "${API}/operatingsystems/${os_id}/os_default_templates?per_page=all"

    if ! api_success || ! json_valid "$API_BODY"; then

        print_api_error GET \
            "${API}/operatingsystems/${os_id}/os_default_templates?per_page=all"

        record_failure "${os_name} default lookup"
        return
    fi

    ###########################################################################
    # IMPORTANT:
    #
    # Filter by template_kind_id.
    #
    # Do NOT depend only on template_kind_name.
    ###########################################################################

    row="$(
        printf '%s\n' "$API_BODY" |
        "$JQ" -c \
            --arg KIND "$PXEGRUB2_KIND_ID" \
            '
            (.results // [])[]
            | select(
                ((.template_kind_id // "") | tostring) == $KIND
            )
            ' |
        "$HEAD" -1
    )"

    ###########################################################################
    # EXISTING PXEGRUB2 DEFAULT
    ###########################################################################

    if [ -n "$row" ]; then

        default_id="$(
            printf '%s\n' "$row" |
            "$JQ" -r '.id // empty'
        )"

        current_template_id="$(
            printf '%s\n' "$row" |
            "$JQ" -r '.provisioning_template_id // empty'
        )"

        echo "Existing Default ID  : ${default_id}"
        echo "Existing Template ID : ${current_template_id}"

        #######################################################################
        # Already correct
        #######################################################################

        if [ "$current_template_id" = "$template_id" ]; then

            skip "PXEGrub2 default already correct. ID=${default_id}"
            return
        fi

        #######################################################################
        # Existing default belongs to another template.
        #
        # UPDATE instead of POST.
        #######################################################################

        info "Existing PXEGrub2 default found."
        info "Updating it to ${template_name}."

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

    ###########################################################################
    # NO PXEGRUB2 DEFAULT
    ###########################################################################

    info "No PXEGrub2 default exists."
    info "Creating PXEGrub2 default."

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

    api_request POST \
        "${API}/operatingsystems/${os_id}/os_default_templates" \
        "$json"

    ###########################################################################
    # SAVE POST RESPONSE BEFORE ANY MORE API REQUESTS.
    #
    # This fixes the previous bug where a later GET changed API_STATUS to 200.
    ###########################################################################

    local post_status="$API_STATUS"
    local post_body="$API_BODY"

    if [[ "$post_status" =~ ^2[0-9][0-9]$ ]]; then

        default_id="$(
            printf '%s\n' "$post_body" |
            "$JQ" -r '.id // empty' 2>/dev/null
        )"

        if [ -n "$default_id" ]; then
            ok "PXEGrub2 default created. ID=${default_id}"
        else
            ok "PXEGrub2 default created."
        fi

        return
    fi

    ###########################################################################
    # POST FAILED.
    ###########################################################################

    error "PXEGrub2 default creation failed."
    error "HTTP Status : ${post_status}"
    error "Method      : POST"
    error "URL         : ${API}/operatingsystems/${os_id}/os_default_templates"

    echo
    echo "Foreman POST response:"
    echo "------------------------------------------------------------"

    printf '%s\n' "$post_body" |
        "$JQ" . 2>/dev/null ||
        printf '%s\n' "$post_body"

    echo "------------------------------------------------------------"

    ###########################################################################
    # Recovery:
    #
    # A concurrent request or Foreman transaction may have created it.
    ###########################################################################

    api_request GET \
        "${API}/operatingsystems/${os_id}/os_default_templates?per_page=all"

    if api_success && json_valid "$API_BODY"; then

        row="$(
            printf '%s\n' "$API_BODY" |
            "$JQ" -c \
                --arg KIND "$PXEGRUB2_KIND_ID" \
                '
                (.results // [])[]
                | select(
                    ((.template_kind_id // "") | tostring) == $KIND
                )
                ' |
            "$HEAD" -1
        )"

        if [ -n "$row" ]; then

            default_id="$(
                printf '%s\n' "$row" |
                "$JQ" -r '.id // empty'
            )"

            current_template_id="$(
                printf '%s\n' "$row" |
                "$JQ" -r '.provisioning_template_id // empty'
            )"

            if [ "$current_template_id" = "$template_id" ]; then

                ok "PXEGrub2 default found after recovery. ID=${default_id}"
                return
            fi

            info "Existing PXEGrub2 default found after POST failure."
            info "Updating existing default ID=${default_id}."

            api_request PUT \
                "${API}/operatingsystems/${os_id}/os_default_templates/${default_id}" \
                "$json"

            if api_success; then

                ok "PXEGrub2 default recovered and updated. ID=${default_id}"
                return

            else

                print_api_error PUT \
                    "${API}/operatingsystems/${os_id}/os_default_templates/${default_id}"

            fi
        fi
    fi

    record_failure "${os_name} default creation"
}

###############################################################################
# SET ALL DEFAULTS
###############################################################################

set_all_pxe_defaults()
{
    section "Setting PXEGrub2 Default Templates"

    local i

    for i in "${!OS_NAMES[@]}"
    do

        if [ -z "${OS_IDS[$i]:-}" ]; then
            error "${OS_NAMES[$i]} has no OS ID."
            record_failure "${OS_NAMES[$i]} default"
            continue
        fi

        if [ -z "${TEMPLATE_IDS[$i]:-}" ]; then
            error "${TEMPLATE_NAMES[$i]} has no template ID."
            record_failure "${TEMPLATE_NAMES[$i]} default"
            continue
        fi

        set_pxe_default \
            "${OS_NAMES[$i]}" \
            "${OS_IDS[$i]}" \
            "${TEMPLATE_NAMES[$i]}" \
            "${TEMPLATE_IDS[$i]}"

    done
}

###############################################################################
# VERIFY PXE TEMPLATE ASSOCIATIONS
###############################################################################

verify_pxe_associations()
{
    section "OS PXEGrub2 Association Verification"

    local i
    local os_name
    local os_id

    for i in "${!OS_NAMES[@]}"
    do

        os_name="${OS_NAMES[$i]}"
        os_id="${OS_IDS[$i]}"

        echo
        echo "${C_BOLD}${os_name} (ID=${os_id})${C_RESET}"

        api_request GET \
            "${API}/operatingsystems/${os_id}/provisioning_templates?per_page=all"

        if ! api_success || ! json_valid "$API_BODY"; then
            error "${os_name}: association lookup failed."
            record_failure "${os_name} association verification"
            continue
        fi

        printf '%s\n' "$API_BODY" |
            "$JQ" -r '
            (.results // [])[]
            | select(
                (.template_kind_name == "PXEGrub2")
                or
                (.template_kind.name == "PXEGrub2")
            )
            | [
                .id,
                .name,
                (.template_kind_id // ""),
                (.template_kind_name // "")
            ]
            | @tsv
            '
    done
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
    local template_id
    local expected_template
    local row
    local default_id
    local actual_template_id

    for i in "${!OS_NAMES[@]}"
    do

        os_name="${OS_NAMES[$i]}"
        os_id="${OS_IDS[$i]}"
        template_id="${TEMPLATE_IDS[$i]}"
        expected_template="${TEMPLATE_NAMES[$i]}"

        api_request GET \
            "${API}/operatingsystems/${os_id}/os_default_templates?per_page=all"

        if ! api_success || ! json_valid "$API_BODY"; then
            error "${os_name}: unable to read defaults."
            record_failure "${os_name} default verification"
            continue
        fi

        row="$(
            printf '%s\n' "$API_BODY" |
            "$JQ" -c \
                --arg KIND "$PXEGRUB2_KIND_ID" \
                '
                (.results // [])[]
                | select(
                    ((.template_kind_id // "") | tostring) == $KIND
                )
                ' |
            "$HEAD" -1
        )"

        if [ -z "$row" ]; then
            error "${os_name}: PXEGrub2 default missing."
            record_failure "${os_name} default verification"
            continue
        fi

        default_id="$(
            printf '%s\n' "$row" |
            "$JQ" -r '.id // empty'
        )"

        actual_template_id="$(
            printf '%s\n' "$row" |
            "$JQ" -r '.provisioning_template_id // empty'
        )"

        if [ "$actual_template_id" = "$template_id" ]; then

            ok "${os_name} PXEGrub2 default: ID=${default_id} Template=${expected_template}"

        else

            error "${os_name} PXEGrub2 default points to template ID=${actual_template_id}, expected ${template_id}."
            record_failure "${os_name} default mismatch"
        fi

    done
}

###############################################################################
# FIND DOMAIN
###############################################################################

get_domain_id()
{
    local name="$1"

    api_request GET "${API}/domains?per_page=all"

    if ! api_success || ! json_valid "$API_BODY"; then
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
# FIND SMART PROXY
###############################################################################

get_proxy_id()
{
    local name="$1"
    local feature="$2"

    api_request GET \
        "${API}/smart_proxies?search=name%3D${name}&per_page=all"

    if ! api_success || ! json_valid "$API_BODY"; then
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
# CREATE / VERIFY SUBNET
###############################################################################

create_subnet()
{
    local name="$1"
    local network="$2"
    local mask="$3"
    local gateway="$4"
    local dns="$5"
    local tftp_proxy="$6"
    local dhcp_proxy="$7"

    local subnet_id
    local domain_id
    local tftp_id
    local dhcp_id
    local json

    subsection "Subnet : ${name}"

    echo "Network      : ${network}"
    echo "Mask         : ${mask}"
    echo "Gateway      : ${gateway}"
    echo "DNS          : ${dns}"
    echo "TFTP Proxy   : ${tftp_proxy}"
    echo "DHCP Proxy   : ${dhcp_proxy}"

    domain_id="$(get_domain_id "$DOMAIN_NAME" || true)"

    if [ -z "$domain_id" ]; then
        error "Domain not found: ${DOMAIN_NAME}"
        record_failure "${name} domain"
        return
    fi

    ok "Domain found : ${DOMAIN_NAME} ID=${domain_id}"

    tftp_id="$(get_proxy_id "$tftp_proxy" tftp || true)"

    if [ -z "$tftp_id" ]; then
        error "TFTP proxy not found: ${tftp_proxy}"
        record_failure "${name} TFTP proxy"
        return
    fi

    ok "TFTP proxy found : ${tftp_proxy} ID=${tftp_id}"

    dhcp_id="$(get_proxy_id "$dhcp_proxy" dhcp || true)"

    if [ -z "$dhcp_id" ]; then
        error "DHCP proxy not found: ${dhcp_proxy}"
        record_failure "${name} DHCP proxy"
        return
    fi

    ok "DHCP proxy found : ${dhcp_proxy} ID=${dhcp_id}"

    ###########################################################################
    # Find subnet
    ###########################################################################

    api_request GET "${API}/subnets?per_page=all"

    if ! api_success || ! json_valid "$API_BODY"; then
        print_api_error GET "${API}/subnets?per_page=all"
        record_failure "${name} subnet lookup"
        return
    fi

    subnet_id="$(
        printf '%s\n' "$API_BODY" |
        "$JQ" -r \
            --arg NAME "$name" \
            '
            (.results // [])[]
            | select(.name == $NAME)
            | .id
            ' |
        "$HEAD" -1
    )"

    ###########################################################################
    # Build subnet JSON
    ###########################################################################

    json="$(
        "$JQ" -n \
            --arg name "$name" \
            --arg network "$network" \
            --arg mask "$mask" \
            --arg gateway "$gateway" \
            --arg dns "$dns" \
            --argjson domain "$domain_id" \
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
    # CREATE
    ###########################################################################

    if [ -z "$subnet_id" ]; then

        info "Creating ${name}"

        api_request POST \
            "${API}/subnets" \
            "$json"

        if api_success; then

            subnet_id="$(
                printf '%s\n' "$API_BODY" |
                "$JQ" -r '.id // empty'
            )"

            ok "${name} created. ID=${subnet_id}"

        else

            # Re-read in case another request created it.
            api_request GET "${API}/subnets?per_page=all"

            subnet_id="$(
                printf '%s\n' "$API_BODY" |
                "$JQ" -r \
                    --arg NAME "$name" \
                    '
                    (.results // [])[]
                    | select(.name == $NAME)
                    | .id
                    ' |
                "$HEAD" -1
            )"

            if [ -n "$subnet_id" ]; then
                skip "${name} already exists after POST. ID=${subnet_id}"
            else
                print_api_error POST "${API}/subnets"
                record_failure "${name} subnet creation"
                return
            fi
        fi

    else

        skip "${name} already exists. ID=${subnet_id}"

        #######################################################################
        # UPDATE existing subnet
        #######################################################################

        api_request PUT \
            "${API}/subnets/${subnet_id}" \
            "$json"

        if api_success; then
            ok "${name} updated."
        else
            print_api_error PUT "${API}/subnets/${subnet_id}"
            record_failure "${name} subnet update"
        fi
    fi
}

###############################################################################
# CREATE ALL SUBNETS
###############################################################################

create_all_subnets()
{
    section "Creating / Verifying PXE Subnets"

    create_subnet \
        "$CENTOS_SUBNET_NAME" \
        "$CENTOS_NETWORK" \
        "$CENTOS_MASK" \
        "$CENTOS_GATEWAY" \
        "$CENTOS_DNS" \
        "$CENTOS_TFTP_PROXY" \
        "$CENTOS_DHCP_PROXY"

    create_subnet \
        "$ROCKY_SUBNET_NAME" \
        "$ROCKY_NETWORK" \
        "$ROCKY_MASK" \
        "$ROCKY_GATEWAY" \
        "$ROCKY_DNS" \
        "$ROCKY_TFTP_PROXY" \
        "$ROCKY_DHCP_PROXY"
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

    printf '%s\n' "$API_BODY" |
        "$JQ" -r '
        (.results // [])[]
        | [
            .id,
            .name,
            .network,
            .mask,
            (.tftp_name // ""),
            (.dhcp_name // "")
        ]
        | @tsv
        '
}

###############################################################################
# VERIFY TEMPLATE KIND
###############################################################################

verify_template_kind()
{
    section "PXEGrub2 Template Verification"

    api_request GET \
        "${API}/provisioning_templates?per_page=all"

    if ! api_success || ! json_valid "$API_BODY"; then
        print_api_error GET \
            "${API}/provisioning_templates?per_page=all"
        record_failure "PXEGrub2 template verification"
        return
    fi

    printf '%s\n' "$API_BODY" |
        "$JQ" -r '
        (.results // [])[]
        | select(
            (.template_kind_name == "PXEGrub2")
            or
            (.template_kind.name == "PXEGrub2")
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
# FINAL OS VERIFICATION
###############################################################################

final_os_verification()
{
    section "Final Operating System Verification"

    local i
    local os_name
    local os_id
    local template_name
    local template_id

    for i in "${!OS_NAMES[@]}"
    do

        os_name="${OS_NAMES[$i]}"
        os_id="${OS_IDS[$i]}"
        template_name="${TEMPLATE_NAMES[$i]}"
        template_id="${TEMPLATE_IDS[$i]}"

        if [ -z "$os_id" ]; then
            error "${os_name}: OS ID missing."
            record_failure "${os_name} final verification"
            continue
        fi

        if [ -z "$template_id" ]; then
            error "${os_name}: template ID missing."
            record_failure "${os_name} final verification"
            continue
        fi

        echo
        echo "${C_BOLD}${os_name}${C_RESET}"
        echo "  OS ID       : ${os_id}"
        echo "  PXE Template: ${template_name}"
        echo "  Template ID : ${template_id}"

        api_request GET \
            "${API}/operatingsystems/${os_id}/os_default_templates?per_page=all"

        if ! api_success || ! json_valid "$API_BODY"; then
            error "${os_name}: default lookup failed."
            record_failure "${os_name} final verification"
            continue
        fi

        row="$(
            printf '%s\n' "$API_BODY" |
            "$JQ" -r \
                --arg KIND "$PXEGRUB2_KIND_ID" \
                --arg TEMPLATE "$template_id" \
                '
                (.results // [])[]
                | select(
                    ((.template_kind_id // "") | tostring) == $KIND
                )
                | select(
                    ((.provisioning_template_id // "") | tostring) == $TEMPLATE
                )
                | [
                    .id,
                    .provisioning_template_id,
                    .template_kind_id,
                    .template_kind_name
                ]
                | @tsv
                ' |
            "$HEAD" -1
        )"

        if [ -n "$row" ]; then
            ok "${os_name}: PXEGrub2 default verified."
        else
            error "${os_name}: PXEGrub2 default verification failed."
            record_failure "${os_name} final verification"
        fi
    done
}

###############################################################################
# MAIN
###############################################################################

main()
{
    check_dependencies
    check_token

    section "01 - Foreman PXE Bootstrap - REST API"

    ###########################################################################
    # API AUTHENTICATION
    ###########################################################################

    section "Foreman API Authentication Test"

    info "Testing Foreman REST API..."

    api_request GET "${API}/status"

    if ! api_success; then
        print_api_error GET "${API}/status"
        exit 1
    fi

    if ! json_valid "$API_BODY"; then
        error "Foreman API returned invalid JSON."
        exit 1
    fi

    ok "Foreman API authentication successful."

    echo "Foreman Version : $(
        printf '%s\n' "$API_BODY" |
        "$JQ" -r '.version // "unknown"'
    )"

    echo "API Version     : $(
        printf '%s\n' "$API_BODY" |
        "$JQ" -r '.api_version // "unknown"'
    )"

    echo "API Status      : ${API_STATUS}"

    ###########################################################################
    # MEDIA
    ###########################################################################

    load_media_configuration
    create_media
    verify_media

    ###########################################################################
    # ARCH / PTABLE
    ###########################################################################

    find_architecture
    find_partition_table

    ###########################################################################
    # OPERATING SYSTEMS
    ###########################################################################

    load_os_configuration
    create_operating_systems
    verify_operating_systems

    ###########################################################################
    # PXE FILES
    ###########################################################################

    generate_template_files

    ###########################################################################
    # PXEGRUB2 KIND
    ###########################################################################

    find_pxegrub2_kind

    ###########################################################################
    # PXE TEMPLATES
    ###########################################################################

    create_pxe_templates

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

    create_all_subnets
    verify_subnets

    ###########################################################################
    # VERIFICATION
    ###########################################################################

    verify_template_kind
    verify_pxe_associations
    verify_pxe_defaults
    final_os_verification

    ###########################################################################
    # GENERATED FILES
    ###########################################################################

    section "Generated PXE Files"

    ls -lh "${TEMPLATE_DIR}"/*.erb

    ###########################################################################
    # FINAL
    ###########################################################################

    section "01 - Foreman PXE Bootstrap API Completed"

    if [ "$FAILURES" -eq 0 ]; then

        ok "Completed successfully with no failures."

    else

        error "Completed with ${FAILURES} failure(s)."
        exit 1
    fi

    ###########################################################################
    # MANUAL VERIFICATION
    ###########################################################################

    section "Manual Verification Commands"

    echo
    echo "1. Foreman API:"
    echo
    echo "curl -ksS --user \"admin:\${FOREMAN_TOKEN}\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/status' | jq"

    echo
    echo "2. PXEGrub2 template kind:"
    echo
    echo "curl -ksS --user \"admin:\${FOREMAN_TOKEN}\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/provisioning_templates?per_page=all' | \\"
    echo "  jq -r '.results[] | select(.template_kind_name==\"PXEGrub2\") | [.id,.name,.template_kind_id,.template_kind_name] | @tsv'"

    echo
    echo "3. OS 2 PXEGrub2 associations:"
    echo
    echo "curl -ksS --user \"admin:\${FOREMAN_TOKEN}\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/operatingsystems/2/provisioning_templates?per_page=all' | \\"
    echo "  jq -r '.results[] | select(.template_kind_name==\"PXEGrub2\") | [.id,.name,.template_kind_id] | @tsv'"

    echo
    echo "4. OS 2 defaults:"
    echo
    echo "curl -ksS --user \"admin:\${FOREMAN_TOKEN}\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/operatingsystems/2/os_default_templates?per_page=all' | jq"

    echo
    echo "5. PXE subnets:"
    echo
    echo "curl -ksS --user \"admin:\${FOREMAN_TOKEN}\" \\"
    echo "  -H 'Accept: application/json,version=2' \\"
    echo "  '${API}/subnets?per_page=all' | jq"
}

main "$@"
```
