#!/bin/bash

###############################################################################
# 01_foreman_pxe_bootstrap_api.sh
#
# Foreman 3.2.1
# REST API v2
#
# IMPORTANT:
#   - Idempotent
#   - Existing resources are skipped
#   - Existing OS/template associations are preserved
#   - PXEGrub2 kind is discovered from existing provisioning templates
#   - Does NOT depend on /api/template_kinds
###############################################################################

set +e

###############################################################################
# CONFIG
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_TOKEN="${FOREMAN_TOKEN:-}"

API="${FOREMAN_URL}/api"

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
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'

###############################################################################
# TRACKING
###############################################################################

FAILURES=()
WARNINGS=()

###############################################################################
# ARRAYS
###############################################################################

declare -A MEDIA_IDS
declare -A OS_IDS
declare -A TEMPLATE_IDS

###############################################################################
# OUTPUT FUNCTIONS
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
    WARNINGS+=("$1")
}

error()
{
    echo -e "${RED}[ERROR]${RESET} $1"
}

failure()
{
    FAILURES+=("$1")
}

###############################################################################
# DEPENDENCY CHECK
###############################################################################

header "Dependency Check"

for CMD in \
    curl \
    jq \
    cat \
    head \
    grep \
    awk \
    sed \
    mkdir \
    mktemp
do

    PATH_CMD="$(command -v "$CMD" 2>/dev/null)"

    if [ -n "$PATH_CMD" ]
    then
        ok "$CMD found: $PATH_CMD"
    else
        error "$CMD not found."
        failure "Missing command: $CMD"
    fi

done

if [ "${#FAILURES[@]}" -gt 0 ]
then
    exit 1
fi

###############################################################################
# TOKEN
###############################################################################

if [ -z "$FOREMAN_TOKEN" ]
then

    error "FOREMAN_TOKEN is not set."

    echo
    echo "Run:"
    echo
    echo "export FOREMAN_USER='admin'"
    echo "export FOREMAN_TOKEN='YOUR_CURRENT_PAT'"
    echo

    exit 1

fi

###############################################################################
# TEMP DIRECTORY
###############################################################################

mkdir -p "$TMP_DIR"

###############################################################################
# JSON CHECK
###############################################################################

is_json()
{
    echo "$1" | jq -e . >/dev/null 2>&1
}

###############################################################################
# API REQUEST
###############################################################################

api_request()
{
    METHOD="$1"
    URL="$2"
    DATA="${3:-}"

    RESPONSE_FILE="$(mktemp)"
    BODY_FILE="$(mktemp)"

    if [ "$METHOD" = "GET" ]
    then

        curl -ksS \
            --connect-timeout 15 \
            --max-time 120 \
            --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
            -H "Accept: application/json,version=2" \
            -H "Content-Type: application/json" \
            -o "$BODY_FILE" \
            -w "%{http_code}" \
            "$URL" > "$RESPONSE_FILE"

    else

        curl -ksS \
            --connect-timeout 15 \
            --max-time 120 \
            --user "${FOREMAN_USER}:${FOREMAN_TOKEN}" \
            -X "$METHOD" \
            -H "Accept: application/json,version=2" \
            -H "Content-Type: application/json" \
            -d "$DATA" \
            -o "$BODY_FILE" \
            -w "%{http_code}" \
            "$URL" > "$RESPONSE_FILE"

    fi

    CURL_RC=$?

    API_STATUS="$(cat "$RESPONSE_FILE" 2>/dev/null)"
    API_BODY="$(cat "$BODY_FILE" 2>/dev/null)"

    rm -f "$RESPONSE_FILE" "$BODY_FILE"

    if [ "$CURL_RC" -ne 0 ]
    then
        API_STATUS=""
        return 1
    fi

    return 0
}

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
# API ERROR
###############################################################################

api_error()
{
    error "HTTP Status : $API_STATUS"
    error "Method      : $1"
    error "URL         : $2"

    if [ -n "$API_BODY" ]
    then
        echo "$API_BODY" |
            jq . 2>/dev/null ||
            echo "$API_BODY"
    fi
}

###############################################################################
# FOREMAN API TEST
###############################################################################

header "Foreman API Authentication Test"

info "Testing Foreman REST API..."

api_get "${API}/status"

if [ "$API_STATUS" = "200" ] && is_json "$API_BODY"
then

    ok "Foreman API authentication successful."

    FOREMAN_VERSION="$(
        echo "$API_BODY" |
        jq -r '.version // empty'
    )"

    API_VERSION="$(
        echo "$API_BODY" |
        jq -r '.api_version // empty'
    )"

    echo "Foreman Version : $FOREMAN_VERSION"
    echo "API Version     : $API_VERSION"
    echo "API Status      : $API_STATUS"

else

    api_error GET "${API}/status"
    exit 1

fi

###############################################################################
# ARCHITECTURE
###############################################################################

header "Finding Architecture"

ARCH_ID=""

api_get "${API}/architectures?per_page=all"

if [ "$API_STATUS" = "200" ] && is_json "$API_BODY"
then

    ARCH_ID="$(
        echo "$API_BODY" |
        jq -r '
            .results[]?
            | select(.name == "x86_64")
            | .id
        ' |
        head -n 1
    )"

fi

if [ -n "$ARCH_ID" ]
then
    ok "x86_64 architecture found. ID=$ARCH_ID"
else
    error "x86_64 architecture not found."
    exit 1
fi

###############################################################################
# PTABLE
###############################################################################

header "Finding Partition Table"

PTABLE_ID=""

api_get "${API}/ptables?per_page=all"

if [ "$API_STATUS" = "200" ] && is_json "$API_BODY"
then

    PTABLE_ID="$(
        echo "$API_BODY" |
        jq -r '
            .results[]?
            | select(.name == "Kickstart default")
            | .id
        ' |
        head -n 1
    )"

fi

if [ -n "$PTABLE_ID" ]
then
    ok "Kickstart default partition table found. ID=$PTABLE_ID"
else
    error "Kickstart default partition table not found."
    exit 1
fi

###############################################################################
# MEDIA
###############################################################################

find_media()
{
    NAME="$1"

    MEDIA_ID=""

    api_get "${API}/media?per_page=all"

    if [ "$API_STATUS" != "200" ] || ! is_json "$API_BODY"
    then
        return 1
    fi

    MEDIA_ID="$(
        echo "$API_BODY" |
        jq -r --arg NAME "$NAME" '
            .results[]?
            | select(.name == $NAME)
            | .id
        ' |
        head -n 1
    )"

    [ -n "$MEDIA_ID" ] &&
    [ "$MEDIA_ID" != "null" ]
}

ensure_media()
{
    NAME="$1"
    PATH_VALUE="$2"

    section "Installation Media : $NAME"

    if find_media "$NAME"
    then

        skip "$NAME already exists. ID=$MEDIA_ID"

        MEDIA_IDS["$NAME"]="$MEDIA_ID"

        return 0

    fi

    info "Creating $NAME"

    PAYLOAD="$(
        jq -n \
            --arg NAME "$NAME" \
            --arg PATH "$PATH_VALUE" \
            '{
                medium: {
                    name: $NAME,
                    path: $PATH,
                    os_family: "Redhat"
                }
            }'
    )"

    api_post "${API}/media" "$PAYLOAD"

    if [ "$API_STATUS" = "201" ] ||
       [ "$API_STATUS" = "200" ]
    then

        MEDIA_ID="$(
            echo "$API_BODY" |
            jq -r '.id // empty'
        )"

        if [ -n "$MEDIA_ID" ]
        then

            ok "$NAME created. ID=$MEDIA_ID"

            MEDIA_IDS["$NAME"]="$MEDIA_ID"

            return 0

        fi

    fi

    if [ "$API_STATUS" = "422" ]
    then

        if find_media "$NAME"
        then

            skip "$NAME already exists. ID=$MEDIA_ID"

            MEDIA_IDS["$NAME"]="$MEDIA_ID"

            return 0

        fi

    fi

    api_error POST "${API}/media"

    failure "$NAME media"

    return 1
}

header "Creating / Verifying Installation Media"

ensure_media \
    "CentOS 7 Remote" \
    "http://192.168.253.136/repo/centos/"

ensure_media \
    "Rocky 8 Remote" \
    "http://192.168.253.136/repo/rocky8/"

ensure_media \
    "Rocky 9.2 Remote" \
    "http://192.168.253.136/repo/rocky9.2/"

ensure_media \
    "Rocky 9 Remote" \
    "http://192.168.253.136/repo/rocky9/"

###############################################################################
# MEDIA VERIFICATION
###############################################################################

header "Installation Media Verification"

api_get "${API}/media?per_page=all"

if [ "$API_STATUS" = "200" ] && is_json "$API_BODY"
then

    echo "$API_BODY" |
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

    api_error GET "${API}/media?per_page=all"

fi

###############################################################################
# OPERATING SYSTEM
###############################################################################

find_os()
{
    NAME="$1"

    OS_ID=""

    api_get "${API}/operatingsystems?per_page=all"

    if [ "$API_STATUS" != "200" ] || ! is_json "$API_BODY"
    then
        return 1
    fi

    OS_ID="$(
        echo "$API_BODY" |
        jq -r --arg NAME "$NAME" '
            .results[]?
            | select(.name == $NAME)
            | .id
        ' |
        head -n 1
    )"

    [ -n "$OS_ID" ] &&
    [ "$OS_ID" != "null" ]
}

ensure_os()
{
    NAME="$1"
    MAJOR="$2"
    MINOR="$3"
    MEDIA_NAME="$4"

    section "Operating System : $NAME"

    if find_os "$NAME"
    then

        skip "$NAME already exists. ID=$OS_ID"

        OS_IDS["$NAME"]="$OS_ID"

        return 0

    fi

    MEDIA_ID="${MEDIA_IDS[$MEDIA_NAME]}"

    if [ -z "$MEDIA_ID" ]
    then

        error "Media unavailable: $MEDIA_NAME"

        failure "$NAME media"

        return 1

    fi

    info "Creating $NAME"

    PAYLOAD="$(
        jq -n \
            --arg NAME "$NAME" \
            --arg MAJOR "$MAJOR" \
            --arg MINOR "$MINOR" \
            --argjson MEDIA_ID "$MEDIA_ID" \
            --argjson ARCH_ID "$ARCH_ID" \
            --argjson PTABLE_ID "$PTABLE_ID" \
            '{
                operatingsystem: {
                    name: $NAME,
                    major: $MAJOR,
                    minor: $MINOR,
                    family: "Redhat",
                    media: [
                        {id: $MEDIA_ID}
                    ],
                    architectures: [
                        {id: $ARCH_ID}
                    ],
                    ptables: [
                        {id: $PTABLE_ID}
                    ]
                }
            }'
    )"

    api_post "${API}/operatingsystems" "$PAYLOAD"

    if [ "$API_STATUS" = "201" ] ||
       [ "$API_STATUS" = "200" ]
    then

        OS_ID="$(
            echo "$API_BODY" |
            jq -r '.id // empty'
        )"

        if [ -n "$OS_ID" ]
        then

            ok "$NAME created. ID=$OS_ID"

            OS_IDS["$NAME"]="$OS_ID"

            return 0

        fi

    fi

    if [ "$API_STATUS" = "422" ]
    then

        if find_os "$NAME"
        then

            skip "$NAME already exists. ID=$OS_ID"

            OS_IDS["$NAME"]="$OS_ID"

            return 0

        fi

    fi

    api_error POST "${API}/operatingsystems"

    failure "$NAME OS"

    return 1
}

###############################################################################
# OS
###############################################################################

header "Creating / Verifying Operating Systems"

ensure_os \
    "CentOSLinux7-RAID" \
    "7" \
    "" \
    "CentOS 7 Remote"

ensure_os \
    "CentOSLinux7-SingleDisk" \
    "7" \
    "" \
    "CentOS 7 Remote"

ensure_os \
    "RockyLinux8.10-RAID" \
    "8" \
    "10" \
    "Rocky 8 Remote"

ensure_os \
    "RockyLinux8.10-SingleDisk" \
    "8" \
    "10" \
    "Rocky 8 Remote"

ensure_os \
    "RockyLinux9.2-RAID" \
    "9" \
    "2" \
    "Rocky 9.2 Remote"

ensure_os \
    "RockyLinux9.2-SingleDisk" \
    "9" \
    "2" \
    "Rocky 9.2 Remote"

ensure_os \
    "RockyLinux9.8-RAID" \
    "9" \
    "8" \
    "Rocky 9 Remote"

ensure_os \
    "RockyLinux9.8-SingleDisk" \
    "9" \
    "8" \
    "Rocky 9 Remote"

###############################################################################
# OS VERIFICATION
###############################################################################

header "Operating System Verification"

api_get "${API}/operatingsystems?per_page=all"

if [ "$API_STATUS" = "200" ] && is_json "$API_BODY"
then

    echo "$API_BODY" |
    jq -r '
        .results[]?
        | select(
            .name == "CentOSLinux7-RAID"
            or .name == "CentOSLinux7-SingleDisk"
            or .name == "RockyLinux8.10-RAID"
            or .name == "RockyLinux8.10-SingleDisk"
            or .name == "RockyLinux9.2-RAID"
            or .name == "RockyLinux9.2-SingleDisk"
            or .name == "RockyLinux9.8-RAID"
            or .name == "RockyLinux9.8-SingleDisk"
        )
        | [
            .id,
            .name,
            .major,
            .minor,
            .family
        ]
        | @tsv
    '

fi

###############################################################################
# PXEGRUB2 KIND
#
# IMPORTANT:
#
# Do NOT use:
#
#   /api/template_kinds
#
# On this Foreman 3.2 installation that endpoint is not returning the
# built-in PXEGrub2 kind.
#
# Instead find an EXISTING provisioning template whose
# template_kind_name == PXEGrub2.
#
# Your current OS output already proves that:
#
#   Kickstart default PXEGrub2
#
# exists.
###############################################################################

header "Finding Existing PXEGrub2 Template Kind"

TEMPLATE_KIND_ID=""

api_get "${API}/provisioning_templates?per_page=all"

if [ "$API_STATUS" = "200" ] && is_json "$API_BODY"
then

    TEMPLATE_KIND_ID="$(
        echo "$API_BODY" |
        jq -r '
            .results[]?
            | select(.template_kind_name == "PXEGrub2")
            | .template_kind_id
        ' |
        head -n 1
    )"

fi

###############################################################################
# FALLBACK: FIND BY TEMPLATE NAME
###############################################################################

if [ -z "$TEMPLATE_KIND_ID" ]
then

    TEMPLATE_KIND_ID="$(
        echo "$API_BODY" |
        jq -r '
            .results[]?
            | select(.name == "Kickstart default PXEGrub2")
            | .template_kind_id
        ' |
        head -n 1
    )"

fi

###############################################################################
# RESULT
###############################################################################

if [ -n "$TEMPLATE_KIND_ID" ] &&
   [ "$TEMPLATE_KIND_ID" != "null" ]
then

    ok "PXEGrub2 template kind found from existing provisioning template."
    echo "PXEGrub2 Template Kind ID : $TEMPLATE_KIND_ID"

else

    error "Could not discover PXEGrub2 template_kind_id."

    echo
    echo "Existing provisioning template kinds:"
    echo

    echo "$API_BODY" |
    jq -r '
        .results[]? |
        [
            .id,
            .name,
            (.template_kind_id // ""),
            (.template_kind_name // "")
        ] |
        @tsv
    '

    failure "PXEGrub2 template kind"

    TEMPLATE_KIND_ID=""

fi

###############################################################################
# TEMPLATE FILES
###############################################################################

header "Generating PXEGrub2 Template Files"

mkdir -p "$TMP_DIR"

###############################################################################
# CENTOS RAID
###############################################################################

cat > "$TMP_DIR/centos-raid.erb" <<'EOF'
set timeout=5
set default=0

menuentry 'Install CentOS 7 - RAID1' {
    linuxefi http://192.168.253.136/tftpboot/centos7/vmlinuz inst.repo=http://192.168.253.136/repo/centos/ inst.ks=<%= foreman_url %>/unattended/provision
    initrdefi http://192.168.253.136/tftpboot/centos7/initrd.img
}
EOF

###############################################################################
# CENTOS SINGLE DISK
###############################################################################

cat > "$TMP_DIR/centos-singledisk.erb" <<'EOF'
set timeout=5
set default=0

menuentry 'Install CentOS 7 - Single Disk' {
    linuxefi http://192.168.253.136/tftpboot/centos7/vmlinuz inst.repo=http://192.168.253.136/repo/centos/ inst.ks=<%= foreman_url %>/unattended/provision
    initrdefi http://192.168.253.136/tftpboot/centos7/initrd.img
}
EOF

###############################################################################
# ROCKY 8 RAID
###############################################################################

cat > "$TMP_DIR/rocky8-raid.erb" <<'EOF'
set timeout=5
set default=0

menuentry 'Install Rocky Linux 8.10 - RAID1' {
    linuxefi http://192.168.253.136/tftpboot/rocky8/vmlinuz inst.repo=http://192.168.253.136/repo/rocky8/ inst.ks=<%= foreman_url %>/unattended/provision
    initrdefi http://192.168.253.136/tftpboot/rocky8/initrd.img
}
EOF

###############################################################################
# ROCKY 8 SINGLE DISK
###############################################################################

cat > "$TMP_DIR/rocky8-singledisk.erb" <<'EOF'
set timeout=5
set default=0

menuentry 'Install Rocky Linux 8.10 - Single Disk' {
    linuxefi http://192.168.253.136/tftpboot/rocky8/vmlinuz inst.repo=http://192.168.253.136/repo/rocky8/ inst.ks=<%= foreman_url %>/unattended/provision
    initrdefi http://192.168.253.136/tftpboot/rocky8/initrd.img
}
EOF

###############################################################################
# ROCKY 9.2 RAID
###############################################################################

cat > "$TMP_DIR/rocky92-raid.erb" <<'EOF'
set timeout=5
set default=0

menuentry 'Install Rocky Linux 9.2 - RAID1' {
    linuxefi http://192.168.253.136/tftpboot/rocky92/vmlinuz inst.repo=http://192.168.253.136/repo/rocky9.2/ inst.ks=<%= foreman_url %>/unattended/provision
    initrdefi http://192.168.253.136/tftpboot/rocky92/initrd.img
}
EOF

###############################################################################
# ROCKY 9.2 SINGLE DISK
###############################################################################

cat > "$TMP_DIR/rocky92-singledisk.erb" <<'EOF'
set timeout=5
set default=0

menuentry 'Install Rocky Linux 9.2 - Single Disk' {
    linuxefi http://192.168.253.136/tftpboot/rocky92/vmlinuz inst.repo=http://192.168.253.136/repo/rocky9.2/ inst.ks=<%= foreman_url %>/unattended/provision
    initrdefi http://192.168.253.136/tftpboot/rocky92/initrd.img
}
EOF

###############################################################################
# ROCKY 9.8 RAID
###############################################################################

cat > "$TMP_DIR/rocky98-raid.erb" <<'EOF'
set timeout=5
set default=0

menuentry 'Install Rocky Linux 9.8 - RAID1' {
    linuxefi http://192.168.253.136/tftpboot/rocky9/vmlinuz inst.repo=http://192.168.253.136/repo/rocky9/ inst.ks=<%= foreman_url %>/unattended/provision
    initrdefi http://192.168.253.136/tftpboot/rocky9/initrd.img
}
EOF

###############################################################################
# ROCKY 9.8 SINGLE DISK
###############################################################################

cat > "$TMP_DIR/rocky98-singledisk.erb" <<'EOF'
set timeout=5
set default=0

menuentry 'Install Rocky Linux 9.8 - Single Disk' {
    linuxefi http://192.168.253.136/tftpboot/rocky9/vmlinuz inst.repo=http://192.168.253.136/repo/rocky9/ inst.ks=<%= foreman_url %>/unattended/provision
    initrdefi http://192.168.253.136/tftpboot/rocky9/initrd.img
}
EOF

ok "All 8 PXEGrub2 template files generated."

###############################################################################
# FIND PROVISIONING TEMPLATE
###############################################################################

find_template()
{
    NAME="$1"

    TEMPLATE_ID=""

    api_get "${API}/provisioning_templates?per_page=all"

    if [ "$API_STATUS" != "200" ] ||
       ! is_json "$API_BODY"
    then
        return 1
    fi

    TEMPLATE_ID="$(
        echo "$API_BODY" |
        jq -r --arg NAME "$NAME" '
            .results[]?
            | select(.name == $NAME)
            | .id
        ' |
        head -n 1
    )"

    [ -n "$TEMPLATE_ID" ] &&
    [ "$TEMPLATE_ID" != "null" ]
}

###############################################################################
# CREATE TEMPLATE
###############################################################################

ensure_template()
{
    NAME="$1"
    FILE="$2"

    section "PXEGrub2 Template : $NAME"

    ###########################################################################
    # Existing template
    ###########################################################################

    if find_template "$NAME"
    then

        skip "$NAME already exists. ID=$TEMPLATE_ID"

        TEMPLATE_IDS["$NAME"]="$TEMPLATE_ID"

        #######################################################################
        # Verify kind
        #######################################################################

        api_get "${API}/provisioning_templates/${TEMPLATE_ID}"

        if [ "$API_STATUS" = "200" ] && is_json "$API_BODY"
        then

            EXISTING_KIND="$(
                echo "$API_BODY" |
                jq -r '.template_kind_name // empty'
            )"

            EXISTING_KIND_ID="$(
                echo "$API_BODY" |
                jq -r '.template_kind_id // empty'
            )"

            if [ "$EXISTING_KIND" = "PXEGrub2" ]
            then
                ok "$NAME has template kind PXEGrub2."
            else
                warn "$NAME exists but kind is '$EXISTING_KIND'."
            fi

            if [ -n "$EXISTING_KIND_ID" ]
            then
                ok "$NAME template_kind_id=$EXISTING_KIND_ID"
            fi

        fi

        return 0

    fi

    ###########################################################################
    # Kind required
    ###########################################################################

    if [ -z "$TEMPLATE_KIND_ID" ]
    then

        error "PXEGrub2 template kind ID unavailable."

        failure "$NAME template kind"

        return 1

    fi

    ###########################################################################
    # File
    ###########################################################################

    if [ ! -f "$FILE" ]
    then

        error "Template file not found: $FILE"

        failure "$NAME file"

        return 1

    fi

    TEMPLATE_CONTENT="$(cat "$FILE")"

    ###########################################################################
    # CREATE
    ###########################################################################

    info "Creating $NAME"

    PAYLOAD="$(
        jq -n \
            --arg NAME "$NAME" \
            --arg TEMPLATE "$TEMPLATE_CONTENT" \
            --argjson KIND_ID "$TEMPLATE_KIND_ID" \
            '{
                provisioning_template: {
                    name: $NAME,
                    template: $TEMPLATE,
                    template_kind_id: $KIND_ID
                }
            }'
    )"

    api_post "${API}/provisioning_templates" "$PAYLOAD"

    if [ "$API_STATUS" = "201" ] ||
       [ "$API_STATUS" = "200" ]
    then

        TEMPLATE_ID="$(
            echo "$API_BODY" |
            jq -r '.id // empty'
        )"

        if [ -n "$TEMPLATE_ID" ]
        then

            ok "$NAME created. ID=$TEMPLATE_ID"

            TEMPLATE_IDS["$NAME"]="$TEMPLATE_ID"

            return 0

        fi

    fi

    ###########################################################################
    # Already exists
    ###########################################################################

    if [ "$API_STATUS" = "422" ]
    then

        if find_template "$NAME"
        then

            skip "$NAME already exists. ID=$TEMPLATE_ID"

            TEMPLATE_IDS["$NAME"]="$TEMPLATE_ID"

            return 0

        fi

    fi

    api_error POST "${API}/provisioning_templates"

    failure "$NAME"

    return 1
}

###############################################################################
# CREATE TEMPLATES
###############################################################################

header "Creating / Verifying PXEGrub2 Templates"

if [ -n "$TEMPLATE_KIND_ID" ]
then

    ensure_template \
        "PXEGrub2 CentOS UEFI RAID Kickstart" \
        "$TMP_DIR/centos-raid.erb"

    ensure_template \
        "PXEGrub2 CentOS UEFI SingleDisk Kickstart" \
        "$TMP_DIR/centos-singledisk.erb"

    ensure_template \
        "PXEGrub2 Rocky8 UEFI RAID Kickstart" \
        "$TMP_DIR/rocky8-raid.erb"

    ensure_template \
        "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" \
        "$TMP_DIR/rocky8-singledisk.erb"

    ensure_template \
        "PXEGrub2 Rocky9.2 UEFI RAID Kickstart" \
        "$TMP_DIR/rocky92-raid.erb"

    ensure_template \
        "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart" \
        "$TMP_DIR/rocky92-singledisk.erb"

    ensure_template \
        "PXEGrub2 Rocky9.8 UEFI RAID Kickstart" \
        "$TMP_DIR/rocky98-raid.erb"

    ensure_template \
        "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart" \
        "$TMP_DIR/rocky98-singledisk.erb"

else

    warn "PXEGrub2 templates skipped because kind ID could not be discovered."

fi

###############################################################################
# ASSOCIATE TEMPLATE WITH OS
###############################################################################

associate_template()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    section "OS Template Association"

    OS_ID="${OS_IDS[$OS_NAME]}"
    TEMPLATE_ID="${TEMPLATE_IDS[$TEMPLATE_NAME]}"

    echo "OS       : $OS_NAME"
    echo "OS ID    : $OS_ID"
    echo "Template : $TEMPLATE_NAME"
    echo "Template ID : $TEMPLATE_ID"

    if [ -z "$OS_ID" ]
    then

        error "OS ID unavailable."

        failure "$OS_NAME association"

        return 1

    fi

    if [ -z "$TEMPLATE_ID" ]
    then

        error "Template ID unavailable."

        failure "$TEMPLATE_NAME association"

        return 1

    fi

    ###########################################################################
    # Get current associations
    ###########################################################################

    api_get "${API}/operatingsystems/${OS_ID}/provisioning_templates"

    if [ "$API_STATUS" != "200" ] ||
       ! is_json "$API_BODY"
    then

        api_error GET \
            "${API}/operatingsystems/${OS_ID}/provisioning_templates"

        failure "$OS_NAME association lookup"

        return 1

    fi

    FOUND="$(
        echo "$API_BODY" |
        jq -r --argjson ID "$TEMPLATE_ID" '
            .results[]?
            | select(.id == $ID)
            | .id
        ' |
        head -n 1
    )"

    if [ "$FOUND" = "$TEMPLATE_ID" ]
    then

        skip "$OS_NAME already associated with $TEMPLATE_NAME."

        return 0

    fi

    ###########################################################################
    # Get ALL existing template IDs
    ###########################################################################

    CURRENT_IDS="$(
        echo "$API_BODY" |
        jq -r '.results[]?.id' |
        awk 'NF'
    )"

    TEMPLATE_LIST="[]"

    while read -r ID
    do

        [ -z "$ID" ] && continue

        TEMPLATE_LIST="$(
            echo "$TEMPLATE_LIST" |
            jq --argjson ID "$ID" '. + [{id:$ID}]'
        )"

    done <<< "$CURRENT_IDS"

    ###########################################################################
    # Add new template
    ###########################################################################

    TEMPLATE_LIST="$(
        echo "$TEMPLATE_LIST" |
        jq --argjson ID "$TEMPLATE_ID" '
            . + [{id:$ID}]
            | unique_by(.id)
        '
    )"

    ###########################################################################
    # UPDATE OS
    ###########################################################################

    PAYLOAD="$(
        jq -n \
            --argjson LIST "$TEMPLATE_LIST" \
            '{
                operatingsystem: {
                    provisioning_templates: $LIST
                }
            }'
    )"

    api_put "${API}/operatingsystems/${OS_ID}" "$PAYLOAD"

    if [ "$API_STATUS" = "200" ]
    then

        ok "$OS_NAME associated with $TEMPLATE_NAME."

        return 0

    fi

    api_error PUT "${API}/operatingsystems/${OS_ID}"

    failure "$OS_NAME association"

    return 1
}

###############################################################################
# ASSOCIATIONS
###############################################################################

header "Associating PXEGrub2 Templates"

if [ -n "$TEMPLATE_KIND_ID" ]
then

    associate_template \
        "CentOSLinux7-RAID" \
        "PXEGrub2 CentOS UEFI RAID Kickstart"

    associate_template \
        "CentOSLinux7-SingleDisk" \
        "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

    associate_template \
        "RockyLinux8.10-RAID" \
        "PXEGrub2 Rocky8 UEFI RAID Kickstart"

    associate_template \
        "RockyLinux8.10-SingleDisk" \
        "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

    associate_template \
        "RockyLinux9.2-RAID" \
        "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

    associate_template \
        "RockyLinux9.2-SingleDisk" \
        "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

    associate_template \
        "RockyLinux9.8-RAID" \
        "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

    associate_template \
        "RockyLinux9.8-SingleDisk" \
        "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

else

    warn "Skipping associations because PXEGrub2 kind is unavailable."

fi

###############################################################################
# DEFAULT TEMPLATE
###############################################################################

find_default_template()
{
    OS_ID="$1"

    DEFAULT_ID=""

    api_get "${API}/operatingsystems/${OS_ID}/os_default_templates"

    if [ "$API_STATUS" != "200" ] ||
       ! is_json "$API_BODY"
    then
        return 1
    fi

    DEFAULT_ID="$(
        echo "$API_BODY" |
        jq -r --argjson KIND "$TEMPLATE_KIND_ID" '
            .results[]?
            | select(.template_kind_id == $KIND)
            | .id
        ' |
        head -n 1
    )"

    [ -n "$DEFAULT_ID" ] &&
    [ "$DEFAULT_ID" != "null" ]
}

set_default_template()
{
    OS_NAME="$1"
    TEMPLATE_NAME="$2"

    section "PXEGrub2 Default Template"

    OS_ID="${OS_IDS[$OS_NAME]}"
    TEMPLATE_ID="${TEMPLATE_IDS[$TEMPLATE_NAME]}"

    echo "OS       : $OS_NAME"
    echo "OS ID    : $OS_ID"
    echo "Template : $TEMPLATE_NAME"
    echo "Template ID : $TEMPLATE_ID"
    echo "Kind ID   : $TEMPLATE_KIND_ID"

    if [ -z "$OS_ID" ] ||
       [ -z "$TEMPLATE_ID" ] ||
       [ -z "$TEMPLATE_KIND_ID" ]
    then

        error "Required ID missing."

        failure "$OS_NAME default"

        return 1

    fi

    ###########################################################################
    # Existing default
    ###########################################################################

    if find_default_template "$OS_ID"
    then

        #######################################################################
        # Check current template
        #######################################################################

        CURRENT_TEMPLATE_ID="$(
            echo "$API_BODY" |
            jq -r \
                --argjson KIND "$TEMPLATE_KIND_ID" \
                --argjson OSID "$OS_ID" '
                    .results[]?
                    | select(
                        .template_kind_id == $KIND
                        and
                        .operatingsystem_id == $OSID
                    )
                    | .provisioning_template_id
                ' |
            head -n 1
        )"

        if [ "$CURRENT_TEMPLATE_ID" = "$TEMPLATE_ID" ]
        then

            skip "PXEGrub2 default already correct. ID=$DEFAULT_ID"

            return 0

        fi

        #######################################################################
        # UPDATE
        #######################################################################

        info "Existing PXEGrub2 default found. Updating..."

        PAYLOAD="$(
            jq -n \
                --argjson TEMPLATE_ID "$TEMPLATE_ID" \
                --argjson KIND_ID "$TEMPLATE_KIND_ID" \
                '{
                    os_default_template: {
                        provisioning_template_id: $TEMPLATE_ID,
                        template_kind_id: $KIND_ID
                    }
                }'
        )"

        api_put \
            "${API}/operatingsystems/${OS_ID}/os_default_templates/${DEFAULT_ID}" \
            "$PAYLOAD"

        if [ "$API_STATUS" = "200" ]
        then

            ok "PXEGrub2 default updated."

            return 0

        fi

        api_error PUT \
            "${API}/operatingsystems/${OS_ID}/os_default_templates/${DEFAULT_ID}"

        failure "$OS_NAME default"

        return 1

    fi

    ###########################################################################
    # CREATE
    ###########################################################################

    info "No PXEGrub2 default found. Creating..."

    PAYLOAD="$(
        jq -n \
            --argjson TEMPLATE_ID "$TEMPLATE_ID" \
            --argjson KIND_ID "$TEMPLATE_KIND_ID" \
            '{
                os_default_template: {
                    provisioning_template_id: $TEMPLATE_ID,
                    template_kind_id: $KIND_ID
                }
            }'
    )"

    api_post \
        "${API}/operatingsystems/${OS_ID}/os_default_templates" \
        "$PAYLOAD"

    if [ "$API_STATUS" = "201" ] ||
       [ "$API_STATUS" = "200" ]
    then

        ok "PXEGrub2 default created."

        return 0

    fi

    ###########################################################################
    # Duplicate race / existing default
    ###########################################################################

    if [ "$API_STATUS" = "422" ]
    then

        if find_default_template "$OS_ID"
        then

            info "PXEGrub2 default already exists. Updating..."

            PAYLOAD="$(
                jq -n \
                    --argjson TEMPLATE_ID "$TEMPLATE_ID" \
                    --argjson KIND_ID "$TEMPLATE_KIND_ID" \
                    '{
                        os_default_template: {
                            provisioning_template_id: $TEMPLATE_ID,
                            template_kind_id: $KIND_ID
                        }
                    }'
            )"

            api_put \
                "${API}/operatingsystems/${OS_ID}/os_default_templates/${DEFAULT_ID}" \
                "$PAYLOAD"

            if [ "$API_STATUS" = "200" ]
            then

                ok "PXEGrub2 default updated."

                return 0

            fi

        fi

    fi

    api_error POST \
        "${API}/operatingsystems/${OS_ID}/os_default_templates"

    failure "$OS_NAME default"

    return 1
}

###############################################################################
# DEFAULTS
###############################################################################

header "Setting PXEGrub2 Default Templates"

if [ -n "$TEMPLATE_KIND_ID" ]
then

    set_default_template \
        "CentOSLinux7-RAID" \
        "PXEGrub2 CentOS UEFI RAID Kickstart"

    set_default_template \
        "CentOSLinux7-SingleDisk" \
        "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

    set_default_template \
        "RockyLinux8.10-RAID" \
        "PXEGrub2 Rocky8 UEFI RAID Kickstart"

    set_default_template \
        "RockyLinux8.10-SingleDisk" \
        "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

    set_default_template \
        "RockyLinux9.2-RAID" \
        "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

    set_default_template \
        "RockyLinux9.2-SingleDisk" \
        "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

    set_default_template \
        "RockyLinux9.8-RAID" \
        "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

    set_default_template \
        "RockyLinux9.8-SingleDisk" \
        "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

else

    warn "Skipping defaults because PXEGrub2 kind is unavailable."

fi

###############################################################################
# DOMAIN
###############################################################################

find_domain()
{
    NAME="$1"

    DOMAIN_ID=""

    api_get "${API}/domains?per_page=all"

    if [ "$API_STATUS" != "200" ] ||
       ! is_json "$API_BODY"
    then
        return 1
    fi

    DOMAIN_ID="$(
        echo "$API_BODY" |
        jq -r --arg NAME "$NAME" '
            .results[]?
            | select(.name == $NAME)
            | .id
        ' |
        head -n 1
    )"

    [ -n "$DOMAIN_ID" ] &&
    [ "$DOMAIN_ID" != "null" ]
}

###############################################################################
# SMART PROXY
###############################################################################

find_proxy()
{
    NAME="$1"

    PROXY_ID=""

    api_get "${API}/smart_proxies?per_page=all"

    if [ "$API_STATUS" != "200" ] ||
       ! is_json "$API_BODY"
    then
        return 1
    fi

    PROXY_ID="$(
        echo "$API_BODY" |
        jq -r --arg NAME "$NAME" '
            .results[]?
            | select(.name == $NAME)
            | .id
        ' |
        head -n 1
    )"

    [ -n "$PROXY_ID" ] &&
    [ "$PROXY_ID" != "null" ]
}

###############################################################################
# SUBNET
###############################################################################

find_subnet()
{
    NAME="$1"

    SUBNET_ID=""

    api_get "${API}/subnets?per_page=all"

    if [ "$API_STATUS" != "200" ] ||
       ! is_json "$API_BODY"
    then
        return 1
    fi

    SUBNET_ID="$(
        echo "$API_BODY" |
        jq -r --arg NAME "$NAME" '
            .results[]?
            | select(.name == $NAME)
            | .id
        ' |
        head -n 1
    )"

    [ -n "$SUBNET_ID" ] &&
    [ "$SUBNET_ID" != "null" ]
}

ensure_subnet()
{
    NAME="$1"
    NETWORK="$2"
    MASK="$3"
    GATEWAY="$4"
    DNS="$5"
    TFTP_PROXY="$6"
    DHCP_PROXY="$7"

    section "Subnet : $NAME"

    echo "Network      : $NETWORK"
    echo "Mask         : $MASK"
    echo "Gateway      : $GATEWAY"
    echo "DNS          : $DNS"
    echo "TFTP Proxy   : $TFTP_PROXY"
    echo "DHCP Proxy   : $DHCP_PROXY"

    ###########################################################################
    # DOMAIN
    ###########################################################################

    DOMAIN_ID=""

    if find_domain "vgs.com"
    then
        ok "Domain found : vgs.com ID=$DOMAIN_ID"
    else
        warn "Domain vgs.com not found."
    fi

    ###########################################################################
    # TFTP
    ###########################################################################

    if find_proxy "$TFTP_PROXY"
    then

        TFTP_ID="$PROXY_ID"

        ok "TFTP proxy found : $TFTP_PROXY ID=$TFTP_ID"

    else

        error "TFTP proxy not found : $TFTP_PROXY"

        failure "$NAME TFTP proxy"

        return 1

    fi

    ###########################################################################
    # DHCP
    ###########################################################################

    if find_proxy "$DHCP_PROXY"
    then

        DHCP_ID="$PROXY_ID"

        ok "DHCP proxy found : $DHCP_PROXY ID=$DHCP_ID"

    else

        error "DHCP proxy not found : $DHCP_PROXY"

        failure "$NAME DHCP proxy"

        return 1

    fi

    ###########################################################################
    # EXISTING
    ###########################################################################

    if find_subnet "$NAME"
    then

        skip "$NAME already exists. ID=$SUBNET_ID"

    else

        info "Creating $NAME"

        PAYLOAD="$(
            jq -n \
                --arg NAME "$NAME" \
                --arg NETWORK "$NETWORK" \
                --arg MASK "$MASK" \
                --arg GATEWAY "$GATEWAY" \
                --arg DNS "$DNS" \
                --argjson TFTP "$TFTP_ID" \
                --argjson DHCP "$DHCP_ID" \
                '{
                    subnet: {
                        name: $NAME,
                        network: $NETWORK,
                        mask: $MASK,
                        gateway: $GATEWAY,
                        dns_primary: $DNS,
                        tftp_id: $TFTP,
                        dhcp_id: $DHCP
                    }
                }'
        )"

        api_post "${API}/subnets" "$PAYLOAD"

        if [ "$API_STATUS" = "201" ] ||
           [ "$API_STATUS" = "200" ]
        then

            ok "$NAME created."

            return 0

        fi

        if [ "$API_STATUS" = "422" ]
        then

            if find_subnet "$NAME"
            then
                skip "$NAME already exists. ID=$SUBNET_ID"
                return 0
            fi

        fi

        api_error POST "${API}/subnets"

        failure "$NAME subnet"

        return 1

    fi

    ###########################################################################
    # UPDATE EXISTING
    ###########################################################################

    PAYLOAD="$(
        jq -n \
            --arg NETWORK "$NETWORK" \
            --arg MASK "$MASK" \
            --arg GATEWAY "$GATEWAY" \
            --arg DNS "$DNS" \
            --argjson TFTP "$TFTP_ID" \
            --argjson DHCP "$DHCP_ID" \
            '{
                subnet: {
                    network: $NETWORK,
                    mask: $MASK,
                    gateway: $GATEWAY,
                    dns_primary: $DNS,
                    tftp_id: $TFTP,
                    dhcp_id: $DHCP
                }
            }'
    )"

    api_put "${API}/subnets/${SUBNET_ID}" "$PAYLOAD"

    if [ "$API_STATUS" = "200" ]
    then

        ok "$NAME updated."

    else

        warn "$NAME exists but update returned HTTP $API_STATUS."

    fi
}

###############################################################################
# SUBNETS
###############################################################################

header "Creating / Verifying PXE Subnets"

ensure_subnet \
    "vgs-subnet-centos" \
    "192.168.253.0" \
    "255.255.255.0" \
    "192.168.253.2" \
    "192.168.253.1" \
    "cent-07-01.vgs.com" \
    "cent-07-01.vgs.com"

ensure_subnet \
    "vgs-subnet-rockyos" \
    "192.168.253.0" \
    "255.255.255.0" \
    "192.168.253.2" \
    "192.168.253.1" \
    "cent-07-02.vgs.com" \
    "cent-07-02.vgs.com"

###############################################################################
# VERIFY TEMPLATES
###############################################################################

header "PXEGrub2 Template Verification"

api_get "${API}/provisioning_templates?per_page=all"

if [ "$API_STATUS" = "200" ] && is_json "$API_BODY"
then

    echo "$API_BODY" |
    jq -r '
        .results[]?
        | select(.template_kind_name == "PXEGrub2")
        | [
            .id,
            .name,
            .template_kind_id,
            .template_kind_name
        ]
        | @tsv
    '

else

    api_error GET "${API}/provisioning_templates?per_page=all"

fi

###############################################################################
# VERIFY OS ASSOCIATIONS
###############################################################################

header "OS PXEGrub2 Association Verification"

for OS_NAME in \
    "CentOSLinux7-RAID" \
    "CentOSLinux7-SingleDisk" \
    "RockyLinux8.10-RAID" \
    "RockyLinux8.10-SingleDisk" \
    "RockyLinux9.2-RAID" \
    "RockyLinux9.2-SingleDisk" \
    "RockyLinux9.8-RAID" \
    "RockyLinux9.8-SingleDisk"
do

    OS_ID="${OS_IDS[$OS_NAME]}"

    [ -z "$OS_ID" ] && continue

    echo
    echo -e "${WHITE}$OS_NAME (ID=$OS_ID)${RESET}"

    api_get "${API}/operatingsystems/${OS_ID}/provisioning_templates"

    if [ "$API_STATUS" = "200" ] && is_json "$API_BODY"
    then

        echo "$API_BODY" |
        jq -r '
            .results[]?
            | select(.template_kind_name == "PXEGrub2")
            | [
                .id,
                .name,
                .template_kind_id,
                .template_kind_name
            ]
            | @tsv
        '

    else

        error "Unable to verify $OS_NAME."

    fi

done

###############################################################################
# VERIFY DEFAULTS
###############################################################################

header "PXEGrub2 Default Verification"

if [ -n "$TEMPLATE_KIND_ID" ]
then

    for OS_NAME in \
        "CentOSLinux7-RAID" \
        "CentOSLinux7-SingleDisk" \
        "RockyLinux8.10-RAID" \
        "RockyLinux8.10-SingleDisk" \
        "RockyLinux9.2-RAID" \
        "RockyLinux9.2-SingleDisk" \
        "RockyLinux9.8-RAID" \
        "RockyLinux9.8-SingleDisk"
    do

        OS_ID="${OS_IDS[$OS_NAME]}"

        [ -z "$OS_ID" ] && continue

        api_get "${API}/operatingsystems/${OS_ID}/os_default_templates"

        if [ "$API_STATUS" = "200" ] && is_json "$API_BODY"
        then

            DEFAULT_INFO="$(
                echo "$API_BODY" |
                jq -r \
                    --argjson KIND "$TEMPLATE_KIND_ID" '
                    .results[]?
                    | select(.template_kind_id == $KIND)
                    | [
                        .id,
                        .provisioning_template_id,
                        .template_kind_id
                    ]
                    | @tsv
                ' |
                head -n 1
            )"

            if [ -n "$DEFAULT_INFO" ]
            then

                ok "$OS_NAME PXEGrub2 default: $DEFAULT_INFO"

            else

                warn "$OS_NAME has no PXEGrub2 default."

            fi

        else

            warn "$OS_NAME default lookup failed."

        fi

    done

fi

###############################################################################
# FINAL OS VERIFICATION
###############################################################################

header "Final Operating System Verification"

api_get "${API}/operatingsystems?per_page=all"

if [ "$API_STATUS" = "200" ] && is_json "$API_BODY"
then

    echo "$API_BODY" |
    jq -r '
        .results[]?
        | select(
            .name == "CentOSLinux7-RAID"
            or .name == "CentOSLinux7-SingleDisk"
            or .name == "RockyLinux8.10-RAID"
            or .name == "RockyLinux8.10-SingleDisk"
            or .name == "RockyLinux9.2-RAID"
            or .name == "RockyLinux9.2-SingleDisk"
            or .name == "RockyLinux9.8-RAID"
            or .name == "RockyLinux9.8-SingleDisk"
        )
        | [
            .id,
            .name,
            .major,
            .minor,
            (.media | map(.name) | join(", ")),
            (.provisioning_templates | map(.name) | join(", "))
        ]
        | @tsv
    '

fi

###############################################################################
# GENERATED FILES
###############################################################################

header "Generated PXE Files"

ls -lh "$TMP_DIR"/*.erb

###############################################################################
# FINAL SUMMARY
###############################################################################

header "01 - Foreman PXE Bootstrap API Completed"

if [ "${#FAILURES[@]}" -eq 0 ]
then

    echo -e "${GREEN}[OK] Completed successfully with no failures.${RESET}"

else

    echo -e "${RED}[WARN] Completed with ${#FAILURES[@]} failure(s).${RESET}"

    echo
    echo "Failures:"

    for ITEM in "${FAILURES[@]}"
    do
        echo -e "${RED}[ERROR]${RESET} $ITEM"
    done

fi

if [ "${#WARNINGS[@]}" -gt 0 ]
then

    echo
    echo "Warnings:"

    for ITEM in "${WARNINGS[@]}"
    do
        echo -e "${YELLOW}[WARN]${RESET} $ITEM"
    done

fi

###############################################################################
# MANUAL VERIFICATION
###############################################################################

echo
echo -e "${CYAN}============================================================${RESET}"
echo -e "${WHITE}Manual Verification Commands${RESET}"
echo -e "${CYAN}============================================================${RESET}"

echo
echo "1. Foreman API:"
echo
echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/status' | jq"

echo
echo "2. Existing PXEGrub2 kind:"
echo
echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/provisioning_templates?per_page=all' | \\"
echo "  jq -r '.results[] | select(.template_kind_name==\"PXEGrub2\") | [.id,.name,.template_kind_id,.template_kind_name] | @tsv'"

echo
echo "3. OS 2 PXEGrub2 templates:"
echo
echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/operatingsystems/2/provisioning_templates' | \\"
echo "  jq -r '.results[] | select(.template_kind_name==\"PXEGrub2\") | [.id,.name,.template_kind_id] | @tsv'"

echo
echo "4. OS 2 PXEGrub2 default:"
echo
echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/operatingsystems/2/os_default_templates' | jq"

echo
echo "5. PXE subnets:"
echo
echo "curl -ksS --user \"admin:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/subnets?per_page=all' | jq"

echo
echo "============================================================"
echo

exit 0
