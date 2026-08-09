#!/bin/bash
###############################################################################
# 01_foreman_pxe_bootstrap_api.sh
#
# Foreman PXE Bootstrap using REST API
#
# Tested design target:
#   Foreman 3.2.x
#
# Creates / verifies:
#   - Installation Media
#   - Architectures
#   - Partition Table
#   - Operating Systems
#   - PXEGrub2 provisioning templates
#   - OS <-> PXEGrub2 associations
#   - PXEGrub2 default templates
#   - PXE subnets
#
# IMPORTANT:
#   Existing objects are detected by EXACT NAME.
#   Existing objects are updated where appropriate.
#
###############################################################################

###############################################################################
# TERMINAL COLORS
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

set -u
set -o pipefail

###############################################################################
# CONFIGURATION
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
FOREMAN_USER="${FOREMAN_USER:-admin}"

if [ -z "${FOREMAN_TOKEN:-}" ]; then
    echo "[ERROR] FOREMAN_TOKEN is not set."
    echo
    echo "Run:"
    echo "  export FOREMAN_TOKEN='your-password-or-token'"
    echo
    exit 1
fi

API="${FOREMAN_URL}/api"

ARCH_NAME="x86_64"
PARTITION_TABLE_NAME="Kickstart default"
DOMAIN_NAME="vgs.com"

###############################################################################
# MEDIA
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

###############################################################################
# OPERATING SYSTEMS
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
# PXE TEMPLATE NAMES
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

###############################################################################
# SUBNETS
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
# RUNTIME
###############################################################################

TMP_DIR="/tmp/foreman-pxe-bootstrap"
mkdir -p "$TMP_DIR"

API_BODY=""
API_STATUS=""
FAILURES=0

ARCH_ID=""
PARTITION_TABLE_ID=""
DOMAIN_ID=""
PXEGRUB2_KIND_ID=""

###############################################################################
# LOGGING FUNCTIONS
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
# DEPENDENCY CHECK
###############################################################################

CURL=""
JQ=""
CAT=""
HEAD=""
GREP=""
AWK=""
SED=""
MKDIR=""
RM=""
MKTEMP=""
TR=""
PRINTF=""
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
    printf -v "${name^^}" '%s' "$path"

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
    check_command sed    || exit 1
    check_command mkdir  || exit 1
    check_command rm     || exit 1
    check_command mktemp || exit 1
    check_command tr     || exit 1
    check_command printf || exit 1
    check_command ls     || exit 1
}

###############################################################################
# JSON VALIDATION
###############################################################################

json_valid()
{
    printf '%s\n' "$1" | "$JQ" empty >/dev/null 2>&1
}

###############################################################################
# API REQUEST
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

    if ! printf '%s' "$API_STATUS" | "$GREP" -Eq '^[0-9]{3}$'; then
        API_BODY="$response"
        API_STATUS=""
        return 1
    fi

    if printf '%s' "$API_STATUS" | "$GREP" -Eq '^2[0-9][0-9]$'; then
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

    printf "${WHITE}Foreman Version :${RESET} %s\n" "${version}"
    printf "${WHITE}API Version     :${RESET} %s\n" "${api_version}"
    printf "${WHITE}API Status      :${RESET} %s\n" "${API_STATUS}"
}

###############################################################################
# ARCHITECTURE
###############################################################################

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
        record_failure "Partition Table"
    fi
}

###############################################################################
# INSTALLATION MEDIA
###############################################################################

create_or_verify_media()
{
    section "Creating / Verifying Installation Media"

    MEDIA_IDS=()

    local i
    local name
    local path
    local id
    local current_path
    local json

    for i in "${!MEDIA_NAMES[@]}"
    do

        name="${MEDIA_NAMES[$i]}"
        path="${MEDIA_PATHS[$i]}"

        subsection "Installation Media : ${name}"

        id="$(find_id_by_name media "$name" || true)"

        if [ -n "$id" ] && [ "$id" != "null" ]; then

            MEDIA_IDS[$i]="$id"

            skip "${name} already exists. ID=${id}"

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
                warn "Unable to inspect ${name}."
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

        if api_request POST "${API}/media" "$json"; then

            id="$(
                printf '%s\n' "$API_BODY" |
                    "$JQ" -r '.id // empty'
            )"

            MEDIA_IDS[$i]="$id"

            ok "${name} created. ID=${id}"

        else

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

    if ! api_request GET "${API}/media?per_page=all"; then
        print_api_error GET "${API}/media?per_page=all"
        return
    fi

    printf '%s\n' "$API_BODY" |
        "$JQ" -r '
        (.results // [])[]
        | [.id,.name,.path]
        | @tsv
        '
}

###############################################################################
# OPERATING SYSTEM
###############################################################################

get_media_id()
{
    local name="$1"

    find_id_by_name media "$name" || true
}

create_or_verify_os()
{
    section "Creating / Verifying Operating Systems"

    OS_IDS=()

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
        media_name="${OS_MEDIA_NAMES[$i]}"

        subsection "Operating System : ${name}"

        os_id="$(find_id_by_name operatingsystems "$name" || true)"

        if [ -n "$os_id" ] && [ "$os_id" != "null" ]; then

            OS_IDS[$i]="$os_id"

            skip "${name} already exists. ID=${os_id}"

            continue
        fi

        media_id="$(get_media_id "$media_name")"

        if [ -z "$media_id" ]; then
            error "Media not found: ${media_name}"
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
                    --argjson media "$media_id" \
                    --argjson pt "$PARTITION_TABLE_ID" \
                    '{
                        operatingsystem: {
                            name: $name,
                            major: $major,
                            minor: $minor,
                            family: "Redhat",
                            architecture_ids: [$arch],
                            medium_ids: [$media],
                            ptable_ids: [$pt]
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
                            medium_ids: [$media],
                            ptable_ids: [$pt]
                        }
                    }'
            )"

        fi

        info "Creating ${name}"

        if api_request POST "${API}/operatingsystems" "$json"; then

            os_id="$(
                printf '%s\n' "$API_BODY" |
                    "$JQ" -r '.id // empty'
            )"

            OS_IDS[$i]="$os_id"

            ok "${name} created. ID=${os_id}"

        else

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

    if ! api_request GET "${API}/operatingsystems?per_page=all"; then
        print_api_error GET "${API}/operatingsystems?per_page=all"
        return
    fi

    printf '%s\n' "$API_BODY" |
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
        '
}

###############################################################################
# Select Rocky Version
###############################################################################

case "${TARGET_VERSION}" in

    9.2)
        ROCKY_OS="RockyLinux9.2-SingleDisk"
        ROCKY_TEMPLATE="PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"
        ROCKY_TEMPLATE_FILE="/tmp/rocky92-singledisk.erb"
        ROCKY_KERNEL="/rocky92/vmlinuz"
        ROCKY_INITRD="/rocky92/initrd.img"
        ROCKY_REPO="http://192.168.253.136/repo/rocky9.2/"
        ROCKY_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/Rocky9_2_Golden_SingleDisk_Minimal.cfg"
        ;;

    9.8)
        ROCKY_OS="RockyLinux9.8-SingleDisk"
        ROCKY_TEMPLATE="PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"
        ROCKY_TEMPLATE_FILE="/tmp/rocky98-singledisk.erb"
        ROCKY_KERNEL="/rocky9/vmlinuz"
        ROCKY_INITRD="/rocky9/initrd.img"
        ROCKY_REPO="http://192.168.253.136/repo/rocky9/"
        ROCKY_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/Rocky9_Golden_SingleDisk_Minimal.cfg"
        ;;

    *)
        error "Unsupported TARGET_VERSION=${TARGET_VERSION}"
        exit 1
        ;;

esac

###############################################################################
# PXE TEMPLATE FILE GENERATION
###############################################################################

generate_templates()
{
    section "Generating PXEGrub2 Template Files"

    "$MKDIR" -p "$TMP_DIR"

    ############################################################################
    # CentOS 7 Single Disk Template
    ############################################################################

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
    linuxefi /centos/vmlinuz \
        inst.stage2=http://192.168.253.136/repo/centos/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/CentOS7_Golden_SingleDisk_Minimal.cfg \
        inst.text \
        inst.ks.device=bootif \
        BOOTIF=01-${net_default_mac} \
        hostname=<%= @host.name %>

    initrdefi /centos/initrd.img
}
EOF_CENTOS_SINGLE

    ok "CentOS Single Disk template generated."

    ############################################################################
    # Rocky Linux 8 Single Disk Template
    ############################################################################

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
    linuxefi /rocky8/vmlinuz \
        inst.stage2=http://192.168.253.136/repo/rocky8/ \
        inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/Rocky8_Golden_SingleDisk_Minimal.cfg \
        inst.text \
        inst.ks.device=bootif \
        BOOTIF=01-${net_default_mac} \
        hostname=<%= @host.name %>

    initrdefi /rocky8/initrd.img
}
EOF_ROCKY8_SINGLE

    ok "Rocky Linux 8 Single Disk template generated."

    ############################################################################
    # Rocky Linux 9 Single Disk Template
    ############################################################################

    info "Generating ${ROCKY_TEMPLATE}..."

    "$CAT" > "${ROCKY_TEMPLATE_FILE}" <<EOF_ROCKY9_SINGLE
<%#
name: ${ROCKY_TEMPLATE}
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5

menuentry 'Install ${ROCKY_OS} Single Disk' {
    linuxefi ${ROCKY_KERNEL} \
        ip=dhcp \
        BOOTIF=01-\${net_default_mac} \
        inst.repo=${ROCKY_REPO} \
        inst.ks=${ROCKY_KS} \
        inst.text \
        inst.ks.device=bootif \
        hostname=<%= @host.name %>

    initrdefi ${ROCKY_INITRD}
}
EOF_ROCKY9_SINGLE

    ok "${ROCKY_TEMPLATE} generated."

    ############################################################################
    # CentOS 7 RAID Template
    ############################################################################

    "$CAT" > "${TMP_DIR}/centos-raid.erb" <<'EOF_CENTOS_RAID'
set default=0
set timeout=10

menuentry 'CentOS 7 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz \
        inst.stage2=<%= @host.operatingsystem.medium.path %> \
        inst.ks=<%= foreman_url("provision") %> \
        ksdevice=bootif

    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF_CENTOS_RAID

    ############################################################################
    # Rocky Linux 8 RAID Template
    ############################################################################

    "$CAT" > "${TMP_DIR}/rocky8-raid.erb" <<'EOF_ROCKY8_RAID'
set default=0
set timeout=10

menuentry 'Rocky Linux 8 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz \
        inst.stage2=<%= @host.operatingsystem.medium.path %> \
        inst.ks=<%= foreman_url("provision") %> \
        ksdevice=bootif

    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF_ROCKY8_RAID

    ############################################################################
    # Rocky Linux 9.2 RAID Template
    ############################################################################

    "$CAT" > "${TMP_DIR}/rocky92-raid.erb" <<'EOF_ROCKY92_RAID'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.2 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz \
        inst.stage2=<%= @host.operatingsystem.medium.path %> \
        inst.ks=<%= foreman_url("provision") %> \
        ksdevice=bootif

    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF_ROCKY92_RAID

    ############################################################################
    # Rocky Linux 9.8 RAID Template
    ############################################################################

    "$CAT" > "${TMP_DIR}/rocky98-raid.erb" <<'EOF_ROCKY98_RAID'
set default=0
set timeout=10

menuentry 'Rocky Linux 9.8 RAID' {
    linuxefi <%= @host.url %>/boot/vmlinuz \
        inst.stage2=<%= @host.operatingsystem.medium.path %> \
        inst.ks=<%= foreman_url("provision") %> \
        ksdevice=bootif

    initrdefi <%= @host.url %>/boot/initrd.img
}
EOF_ROCKY98_RAID

    ############################################################################
    # Verification
    ############################################################################

    ok "All 8 PXEGrub2 template files generated."

    "$LS" -lh "${TMP_DIR}"/*.erb
}
###############################################################################
# FIND PXEGRUB2 KIND
###############################################################################

find_pxegrub2_kind()
{
    section "Finding Existing PXEGrub2 Template Kind"

    local kind_id=""

    if api_request GET "${API}/provisioning_templates?per_page=all"; then

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

    if [ -z "$kind_id" ] || [ "$kind_id" = "null" ]; then

        if api_request GET "${API}/provisioning_template_kinds?per_page=all"; then

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

        return
    fi

    template_text="$("$CAT" "${TMP_DIR}/${filename}")"

    template_id="$(
        find_id_by_name provisioning_templates "$name" || true
    )"

    ###########################################################################
    # UPDATE EXISTING
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
    # CREATE
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

    if api_request POST "${API}/provisioning_templates" "$json"; then

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

                print_api_error POST "${API}/provisioning_templates"

                record_failure "${name} creation"

            fi

        else

            print_api_error POST "${API}/provisioning_templates"

            record_failure "${name} creation"

        fi
    fi
}

###############################################################################
# CREATE ALL TEMPLATES
###############################################################################

create_or_verify_templates()
{
    section "Creating / Verifying PXEGrub2 Templates"

    TEMPLATE_IDS=()

    local i

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

    echo "OS          : ${os_name}"
    echo "OS ID       : ${os_id}"
    echo "Template    : ${template_name}"
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

            return 0

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

        return 0
    fi

    ###########################################################################
    # Foreman may return 422 because association already exists.
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

                skip "${os_name} association already exists."

                return 0

            fi
        fi
    fi

    print_api_error \
        POST \
        "${API}/operatingsystems/${os_id}/provisioning_templates"

    record_failure "${os_name} template association"

    return 1
}

###############################################################################
# ASSOCIATE ALL
###############################################################################

associate_all_templates()
{
    section "Associating PXEGrub2 Templates"

    local i
    local os_id
    local template_id

    for i in "${!OS_NAMES[@]}"
    do

        os_id="${OS_IDS[$i]:-}"

        if [ -z "$os_id" ]; then

            error "OS ID unavailable: ${OS_NAMES[$i]}"

            record_failure "${OS_NAMES[$i]} association"

            continue
        fi

        template_id="$(
            get_template_id "${TEMPLATE_NAMES[$i]}"
        )"

        if [ -z "$template_id" ]; then

            error "Template ID unavailable: ${TEMPLATE_NAMES[$i]}"

            record_failure "${TEMPLATE_NAMES[$i]} association"

            continue
        fi

        associate_template \
            "${OS_NAMES[$i]}" \
            "$os_id" \
            "${TEMPLATE_NAMES[$i]}" \
            "$template_id"

    done
}

###############################################################################
# SET PXE DEFAULT
###############################################################################

set_pxe_default()
{
    local os_name="$1"
    local os_id="$2"
    local template_name="$3"
    local template_id="$4"

    local existing_id=""
    local existing_template=""
    local existing_kind=""
    local json

    subsection "PXEGrub2 Default Template"

    printf "${WHITE}OS          :${RESET} %s\n" "${os_name}"
    printf "${WHITE}OS ID       :${RESET} %s\n" "${os_id}"
    printf "${WHITE}Template    :${RESET} %s\n" "${template_name}"
    printf "${WHITE}Template ID :${RESET} %s\n" "${template_id}"
    printf "${WHITE}Kind ID     :${RESET} %s\n" "${PXEGRUB2_KIND_ID}"

    ###########################################################################
    # Read current defaults
    ###########################################################################

    if ! api_request GET \
        "${API}/operatingsystems/${os_id}/os_default_templates"; then

        print_api_error \
            GET \
            "${API}/operatingsystems/${os_id}/os_default_templates"

        record_failure "${os_name} default lookup"

        return
    fi

    ###########################################################################
    # Find PXEGrub2 default
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
    # Existing PXEGrub2 default
    ###########################################################################

    if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then

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

        if [ "$existing_template" = "$template_id" ] &&
           [ "$existing_kind" = "$PXEGRUB2_KIND_ID" ]; then

            skip "PXEGrub2 default already correct. ID=${existing_id}"

            return 0
        fi

        #######################################################################
        # Update existing PXEGrub2 default
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

        if api_request PUT \
            "${API}/operatingsystems/${os_id}/os_default_templates/${existing_id}" \
            "$json"; then

            ok "PXEGrub2 default updated. ID=${existing_id}"

            return 0

        else

            print_api_error \
                PUT \
                "${API}/operatingsystems/${os_id}/os_default_templates/${existing_id}"

            record_failure "${os_name} default update"

            return 1
        fi
    fi

    ###########################################################################
    # No PXEGrub2 default exists -> create
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

        if [ "$API_STATUS" = "422" ]; then

            ###################################################################
            # Re-read and see whether another process already created it.
            ###################################################################

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

                if [ -n "$existing_id" ] &&
                   [ "$existing_id" != "null" ]; then

                    skip "PXEGrub2 default already exists. ID=${existing_id}"

                    return 0
                fi
            fi
        fi

        print_api_error \
            POST \
            "${API}/operatingsystems/${os_id}/os_default_templates"

        record_failure "${os_name} default creation"

        return 1
    fi
}

###############################################################################
# SET ALL DEFAULTS
###############################################################################

set_all_pxe_defaults()
{
    section "Setting PXEGrub2 Default Templates"

    local i
    local os_id
    local template_id

    for i in "${!OS_NAMES[@]}"
    do

        os_id="${OS_IDS[$i]:-}"

        if [ -z "$os_id" ]; then

            error "OS ID unavailable: ${OS_NAMES[$i]}"

            record_failure "${OS_NAMES[$i]} default"

            continue
        fi

        template_id="$(
            get_template_id "${TEMPLATE_NAMES[$i]}"
        )"

        if [ -z "$template_id" ]; then

            error "Template ID unavailable: ${TEMPLATE_NAMES[$i]}"

            record_failure "${TEMPLATE_NAMES[$i]} default"

            continue
        fi

        set_pxe_default \
            "${OS_NAMES[$i]}" \
            "$os_id" \
            "${TEMPLATE_NAMES[$i]}" \
            "$template_id"

    done
}

###############################################################################
# DOMAIN
###############################################################################

find_domain()
{
    DOMAIN_ID="$(
        find_id_by_name domains "$DOMAIN_NAME" || true
    )"

    if [ -n "$DOMAIN_ID" ]; then

        ok "Domain found : ${DOMAIN_NAME} ID=${DOMAIN_ID}"

    else

        error "Domain not found : ${DOMAIN_NAME}"

        record_failure "Domain"

    fi
}

###############################################################################
# SMART PROXY
###############################################################################

get_smart_proxy_id()
{
    local name="$1"

    find_id_by_name smart_proxies "$name" || true
}

###############################################################################
# SUBNET
###############################################################################

create_or_update_subnet()
{
    local i="$1"

    local name="${SUBNET_NAMES[$i]}"
    local network="${SUBNET_NETWORKS[$i]}"
    local mask="${SUBNET_MASKS[$i]}"
    local gateway="${SUBNET_GATEWAYS[$i]}"
    local dns="${SUBNET_DNS[$i]}"
    local tftp_name="${SUBNET_TFTP_PROXIES[$i]}"
    local dhcp_name="${SUBNET_DHCP_PROXIES[$i]}"

    local subnet_id=""
    local tftp_id=""
    local dhcp_id=""
    local json

    subsection "Subnet : ${name}"

    printf "${WHITE}Network    :${RESET} %s\n" "${network}"
    printf "${WHITE}Mask       :${RESET} %s\n" "${mask}"
    printf "${WHITE}Gateway    :${RESET} %s\n" "${gateway}"
    printf "${WHITE}DNS        :${RESET} %s\n" "${dns}"
    printf "${WHITE}TFTP Proxy :${RESET} %s\n" "${tftp_name}"
    printf "${WHITE}DHCP Proxy :${RESET} %s\n" "${dhcp_name}"

    if [ -z "$DOMAIN_ID" ]; then
        find_domain
    fi

    if [ -z "$DOMAIN_ID" ]; then

        error "Domain ID unavailable."

        record_failure "${name} domain"

        return
    fi

    tftp_id="$(get_smart_proxy_id "$tftp_name")"

    if [ -z "$tftp_id" ]; then

        error "TFTP proxy not found: ${tftp_name}"

        record_failure "${name} TFTP"

        return
    fi

    ok "TFTP proxy found : ${tftp_name} ID=${tftp_id}"

    dhcp_id="$(get_smart_proxy_id "$dhcp_name")"

    if [ -z "$dhcp_id" ]; then

        error "DHCP proxy not found: ${dhcp_name}"

        record_failure "${name} DHCP"

        return
    fi

    ok "DHCP proxy found : ${dhcp_name} ID=${dhcp_id}"

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
            --argjson domain "$DOMAIN_ID" \
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
                    domain_ids: [$domain],
                    tftp_id: $tftp,
                    dhcp_id: $dhcp,
                    boot_mode: "DHCP"
                }
            }'
    )"

    ###########################################################################
    # Existing subnet
    ###########################################################################

    subnet_id="$(find_id_by_name subnets "$name" || true)"

    if [ -n "$subnet_id" ]; then

        skip "${name} already exists. ID=${subnet_id}"

        if api_request PUT \
            "${API}/subnets/${subnet_id}" \
            "$json"; then

            ok "${name} updated."

        else

            print_api_error \
                PUT \
                "${API}/subnets/${subnet_id}"

            record_failure "${name} update"

        fi

        return
    fi

    ###########################################################################
    # Create subnet
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
# CREATE SUBNETS
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
# VERIFY SUBNETS
###############################################################################

verify_subnets()
{
    section "PXE Subnet Verification"

    if ! api_request GET "${API}/subnets?per_page=all"; then

        print_api_error GET "${API}/subnets?per_page=all"

        return
    fi

    printf '%s\n' "$API_BODY" |
        "$JQ" -r '
        (.results // [])[]
        | select(
            .name == "vgs-subnet-centos"
            or
            .name == "vgs-subnet-rockyos"
        )
        | [
            .id,
            .name,
            (.network // ""),
            (.mask // ""),
            (.tftp_name // ""),
            (.dhcp_name // "")
        ]
        | @tsv
        '
}

###############################################################################
# VERIFY PXE TEMPLATES
###############################################################################

verify_templates()
{
    section "PXEGrub2 Template Verification"

    if ! api_request GET "${API}/provisioning_templates?per_page=all"; then

        print_api_error GET "${API}/provisioning_templates?per_page=all"

        return
    fi

    printf '%s\n' "$API_BODY" |
        "$JQ" -r '
        (.results // [])[]
        | select(
            .template_kind_name == "PXEGrub2"
            or
            .template_kind == "PXEGrub2"
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
# VERIFY OS ASSOCIATIONS
###############################################################################

verify_os_associations()
{
    section "OS PXEGrub2 Association Verification"

    local i
    local os_id

    for i in "${!OS_NAMES[@]}"
    do

        os_id="${OS_IDS[$i]:-}"

        if [ -z "$os_id" ]; then
            continue
        fi

        echo

        printf "${WHITE}%s (ID=%s)${RESET}\n" \
            "${OS_NAMES[$i]}" \
            "${os_id}"

        if api_request GET \
            "${API}/operatingsystems/${os_id}/provisioning_templates"; then

            printf '%s\n' "$API_BODY" |
                "$JQ" -r '
                (.results // [])[]
                | select(
                    .template_kind_name == "PXEGrub2"
                    or
                    .template_kind == "PXEGrub2"
                )
                | [
                    .id,
                    .name,
                    (.template_kind_id // ""),
                    (.template_kind_name // "")
                ]
                | @tsv
                '

        else

            warn "Unable to query associations for ${OS_NAMES[$i]}."

        fi

    done
}

###############################################################################
# VERIFY DEFAULTS
###############################################################################

verify_defaults()
{
    section "PXEGrub2 Default Verification"

    local i
    local os_id
    local result

    for i in "${!OS_NAMES[@]}"
    do

        os_id="${OS_IDS[$i]:-}"

        if [ -z "$os_id" ]; then
            continue
        fi

        if ! api_request GET \
            "${API}/operatingsystems/${os_id}/os_default_templates"; then

            error "${OS_NAMES[$i]} default query failed."

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
                        (.template_kind_id // ""),
                        (.template_kind_name // "")
                    ]
                    | @tsv
                    ' |
                "$HEAD" -1
        )"

        if [ -n "$result" ]; then

            ok "${OS_NAMES[$i]} PXEGrub2 default: ${result}"

        else

            error "${OS_NAMES[$i]} PXEGrub2 default not found."

            record_failure "${OS_NAMES[$i]} default verification"

        fi

    done
}

###############################################################################
# FINAL OPERATING SYSTEM VERIFICATION
###############################################################################

final_os_verification()
{
    section "Final Operating System Verification"

    if ! api_request GET "${API}/operatingsystems?per_page=all"; then

        print_api_error GET "${API}/operatingsystems?per_page=all"

        return
    fi

    printf '%s\n' "$API_BODY" |
        "$JQ" -r '
        (.results // [])[]
        | [
            .id,
            .name,
            (.major // ""),
            (.minor // ""),
            (.family // ""),
            (
                (.media // [])
                | map(.name)
                | join(", ")
            )
        ]
        | @tsv
        '
}
###############################################################################
# VERIFY GENERATED PXE FILES
###############################################################################

verify_generated_files()
{
    section "Generated PXE Files"

    local files=(
        "centos-raid.erb"
        "centos-singledisk.erb"
        "rocky8-raid.erb"
        "rocky8-singledisk.erb"
        "rocky92-raid.erb"
        "rocky92-singledisk.erb"
        "rocky98-raid.erb"
        "rocky98-singledisk.erb"
    )

    local file
    local full
    local errors

    errors=0

    "$LS" -lh "${TMP_DIR}"/*.erb 2>/dev/null || true

    for file in "${files[@]}"
    do

        full="${TMP_DIR}/${file}"

        if [ ! -f "$full" ]; then

            error "${file} missing."

            errors=$((errors + 1))

            continue
        fi

        if [ ! -s "$full" ]; then

            error "${file} is empty."

            errors=$((errors + 1))

            continue
        fi

        if "$GREP" -q "menuentry" "$full" &&
           "$GREP" -q "linuxefi" "$full" &&
           "$GREP" -q "initrdefi" "$full"; then

            ok "${file} looks valid."

        else

            error "${file} validation failed."

            errors=$((errors + 1))

        fi

    done

    if [ "$errors" -gt 0 ]; then

        error "${errors} generated PXE file(s) failed validation."

        record_failure "Generated PXE files"

        return 1
    fi

    return 0
}


###############################################################################
# REBUILD PXE
###############################################################################

rebuild_pxe()
{
    section "Rebuilding PXE Configuration"

    local json='{"provisioning_template":{}}'

    info "Requesting Foreman PXE rebuild..."

    if api_request POST \
        "${API}/provisioning_templates/build_pxe_default" \
        "$json"; then

        ok "Foreman PXE default build request completed."

    else

        warn "Foreman PXE default build request failed."

        print_api_error \
            POST \
            "${API}/provisioning_templates/build_pxe_default"

        warn "PXE rebuild is an additional deployment step."
        warn "Existing PXE templates and subnet configuration were preserved."
    fi
}

###############################################################################
# FINAL SUMMARY
###############################################################################

final_summary()
{
    section "01 - Foreman PXE Bootstrap API Completed"

    if [ "${FAILURES:-0}" -eq 0 ]; then

        printf "\n"
        ok "Completed successfully with no failures."

    else

        printf "\n"
        error "Completed with ${FAILURES} failure(s)."

        printf "\n"
        warn "Review the errors shown above before provisioning."

    fi
}


###############################################################################
# MANUAL VERIFICATION COMMANDS
###############################################################################

manual_verification()
{
    section "Manual Verification Commands"

    cat <<'EOF'

1. Foreman API:

curl -ksS --user "admin:$FOREMAN_TOKEN" \
  -H 'Accept: application/json,version=2' \
  'https://cent-07-01.vgs.com/api/status' | jq


2. Installation Media:

curl -ksS --user "admin:$FOREMAN_TOKEN" \
  -H 'Accept: application/json,version=2' \
  'https://cent-07-01.vgs.com/api/media?per_page=all' |
  jq -r '.results[] | [.id,.name,.path] | @tsv'


3. PXEGrub2 Templates:

curl -ksS --user "admin:$FOREMAN_TOKEN" \
  -H 'Accept: application/json,version=2' \
  'https://cent-07-01.vgs.com/api/provisioning_templates?per_page=all' |
  jq -r '
    (.results // [])[]
    | select(
        .template_kind_name == "PXEGrub2"
        or
        .template_kind == "PXEGrub2"
      )
    | [.id,.name,.template_kind_id,.template_kind_name]
    | @tsv
  '


4. OS 2 PXEGrub2 associations:

curl -ksS --user "admin:$FOREMAN_TOKEN" \
  -H 'Accept: application/json,version=2' \
  'https://cent-07-01.vgs.com/api/operatingsystems/2/provisioning_templates' |
  jq


5. OS 2 PXEGrub2 defaults:

curl -ksS --user "admin:$FOREMAN_TOKEN" \
  -H 'Accept: application/json,version=2' \
  'https://cent-07-01.vgs.com/api/operatingsystems/2/os_default_templates' |
  jq


6. PXE Subnets:

curl -ksS --user "admin:$FOREMAN_TOKEN" \
  -H 'Accept: application/json,version=2' \
  'https://cent-07-01.vgs.com/api/subnets?per_page=all' |
  jq


7. Generated template files:

ls -lh /tmp/foreman-pxe-bootstrap/*.erb

EOF
}


###############################################################################
# MAIN
###############################################################################

main()
{
    check_dependencies

    header "01 - Foreman PXE Bootstrap - REST API"

    ###########################################################################
    # FOREMAN API
    ###########################################################################

    test_api

    ###########################################################################
    # INSTALLATION MEDIA
    ###########################################################################

    create_or_verify_media
    verify_media

    ###########################################################################
    # ARCHITECTURE / PARTITION TABLE
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
    # PXEGRUB2 TEMPLATE KIND
    ###########################################################################

    if ! find_pxegrub2_kind; then
        error "Cannot continue with PXEGrub2 template kind."
        exit 1
    fi

    if [ -z "$PXEGRUB2_KIND_ID" ]; then
        error "PXEGrub2 template kind ID is empty."
        exit 1
    fi

    ###########################################################################
    # CREATE / UPDATE PXEGRUB2 TEMPLATES
    ###########################################################################

    create_or_verify_templates

    ###########################################################################
    # ASSOCIATE TEMPLATES WITH OPERATING SYSTEMS
    ###########################################################################

    associate_all_templates

    ###########################################################################
    # SET PXEGRUB2 DEFAULTS
    ###########################################################################

    set_all_pxe_defaults

    ###########################################################################
    # CREATE / VERIFY PXE SUBNETS
    ###########################################################################

    create_subnets

    ###########################################################################
    # VERIFICATION
    ###########################################################################

    verify_subnets

    verify_templates

    verify_os_associations

    verify_defaults

    final_os_verification

    verify_generated_files

    ###########################################################################
    # REBUILD PXE
    ###########################################################################

    rebuild_pxe

    ###########################################################################
    # FINAL SUMMARY
    ###########################################################################

    final_summary
}

###############################################################################
# RUN
###############################################################################

main
exit $?
