#!/bin/bash
###############################################################################
# 03 - Foreman Hostgroup Bootstrap (Single Disk) - REST API
#
# Creates / verifies:
#   CentOSLinux7-SingleDisk
#   RockyLinux8.10-SingleDisk
#   RockyLinux9.2-SingleDisk
#   RockyLinux9.8-SingleDisk
#
# No hammer dependency.
#
# Usage:
#   TARGET_VERSION=9.2 ./03_foreman_hostgroup_bootstrap_single_disk_api.sh
#   TARGET_VERSION=9.8 ./03_foreman_hostgroup_bootstrap_single_disk_api.sh
#   TARGET_VERSION=ALL ./03_foreman_hostgroup_bootstrap_single_disk_api.sh
###############################################################################

set +e

FAILED_STEPS=()

record_failure()
{
    FAILED_STEPS+=("$1")
}

###############################################################################
# Colors
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

###############################################################################
# Logging
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

header()
{
    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

subheader()
{
    echo
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
}

###############################################################################
# Configuration
###############################################################################

FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"
FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
API_VERSION=2

DOMAIN="vgs.com"
LOCATION="Default Location"
ORGANIZATION="Default Organization"

CENTOS_SUBNET="vgs-subnet-centos"
ROCKY_SUBNET="vgs-subnet-rockyos"

TARGET_VERSION="${TARGET_VERSION:-ALL}"

###############################################################################
# Operating Systems
###############################################################################

CENTOS_OS="CentOSLinux7-SingleDisk"
ROCKY8_OS="RockyLinux8.10-SingleDisk"
ROCKY92_OS="RockyLinux9.2-SingleDisk"
ROCKY98_OS="RockyLinux9.8-SingleDisk"

###############################################################################
# Installation Media
###############################################################################

CENTOS_MEDIA="CentOS 7 Remote"
ROCKY8_MEDIA="Rocky 8 Remote"
ROCKY92_MEDIA="Rocky 9.2 Remote"
ROCKY98_MEDIA="Rocky 9 Remote"

###############################################################################
# PXE Templates
###############################################################################

CENTOS_TEMPLATE="PXEGrub2 CentOS UEFI SingleDisk Kickstart"
ROCKY8_TEMPLATE="PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"
ROCKY92_TEMPLATE="PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"
ROCKY98_TEMPLATE="PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

###############################################################################
# Dependency Check
###############################################################################

header "Dependency Check"

for CMD in curl jq cat head grep awk mkdir rm mktemp ls
do
    P="$(command -v "$CMD" 2>/dev/null)"

    if [ -n "$P" ]
    then
        ok "$CMD found: $P"
    else
        error "$CMD not found."
        record_failure "Dependency: $CMD"
    fi
done

if [ ${#FAILED_STEPS[@]} -ne 0 ]
then
    exit 1
fi

###############################################################################
# Header
###############################################################################

header "03 - Foreman Single Disk Hostgroup Bootstrap - REST API"

echo "Foreman URL    : ${FOREMAN_URL}"
echo "API Version    : ${API_VERSION}"
echo "Target Version : ${TARGET_VERSION}"

###############################################################################
# API Temporary File
###############################################################################

BODY="$(mktemp)"

trap 'rm -f "$BODY"' EXIT

HTTP_STATUS=""

###############################################################################
# Generic API Request
###############################################################################

api_request()
{
    local METHOD="$1"
    local ENDPOINT="$2"
    local DATA="$3"

    : > "$BODY"

    if [ "$METHOD" = "GET" ]
    then

        HTTP_STATUS="$(
            curl -ksS \
                -o "$BODY" \
                -w '%{http_code}' \
                --user "${FOREMAN_USER}:${FOREMAN_PASSWORD}" \
                -H "Accept: application/json,version=${API_VERSION}" \
                -H 'Content-Type: application/json' \
                "${FOREMAN_URL}${ENDPOINT}"
        )"

    else

        HTTP_STATUS="$(
            curl -ksS \
                -o "$BODY" \
                -w '%{http_code}' \
                --user "${FOREMAN_USER}:${FOREMAN_PASSWORD}" \
                -H "Accept: application/json,version=${API_VERSION}" \
                -H 'Content-Type: application/json' \
                -X "$METHOD" \
                --data "$DATA" \
                "${FOREMAN_URL}${ENDPOINT}"
        )"

    fi

    cat "$BODY"
}

api_get()
{
    api_request GET "$1" ""
}

api_post()
{
    api_request POST "$1" "$2"
}

###############################################################################
# API Error
###############################################################################

show_api_error()
{
    error "API request failed."
    error "HTTP Status : ${HTTP_STATUS}"
    error "Method      : $1"
    error "URL         : ${FOREMAN_URL}$2"

    jq . "$BODY" 2>/dev/null || cat "$BODY"
}

###############################################################################
# Foreman API Authentication
###############################################################################

header "Foreman API Authentication Test"

info "Testing Foreman REST API..."

###############################################################################
# IMPORTANT:
# Do NOT use:
#
#     STATUS="$(api_get /api/status)"
#
# because command substitution runs api_get in a subshell and
# HTTP_STATUS will not be available in the parent shell.
###############################################################################

api_get /api/status >/dev/null

if [[ "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]]
then

    ok "Foreman API authentication successful."

    echo "Foreman Version : $(jq -r '.version // empty' "$BODY")"
    echo "API Version     : ${API_VERSION}"
    echo "API Status      : ${HTTP_STATUS}"

else

    show_api_error GET /api/status
    exit 1

fi

###############################################################################
# Collection Lookup
###############################################################################

lookup_from_collection()
{
    local ENDPOINT="$1"
    local NAME="$2"

    api_get "${ENDPOINT}?per_page=all" >/dev/null

    jq -r \
        --arg NAME "$NAME" \
        '
        (.results // [])[]
        | select(.name == $NAME)
        | .id
        ' "$BODY" |
        head -1
}

###############################################################################
# Organization Lookup
#
# Foreman 3.2.1 can return:
#
# total: 1
# results: []
#
# from /api/organizations
#
# Therefore fallback to /api/organizations/1.
###############################################################################

get_org_id()
{
    ID="$(lookup_from_collection \
        /api/organizations \
        "$ORGANIZATION")"

    if [ -z "$ID" ]
    then

        api_get /api/organizations/1 >/dev/null

        ID="$(
            jq -r \
                --arg NAME "$ORGANIZATION" \
                'select(.name==$NAME) | .id' \
                "$BODY"
        )"

    fi

    echo "$ID"
}

###############################################################################
# Location Lookup
#
# Location is available through organization response:
#
# /api/organizations/1
#
# locations:
#   id: 2
#   name: Default Location
###############################################################################

get_location_id()
{
    ID="$(lookup_from_collection \
        /api/locations \
        "$LOCATION")"

    if [ -z "$ID" ]
    then

        api_get /api/organizations/1 >/dev/null

        ID="$(
            jq -r \
                --arg NAME "$LOCATION" \
                '
                (.locations // [])[]
                | select(.name==$NAME)
                | .id
                ' "$BODY" |
                head -1
        )"

    fi

    echo "$ID"
}

###############################################################################
# Other Resource Lookups
###############################################################################

get_arch_id()
{
    lookup_from_collection \
        /api/architectures \
        "x86_64"
}

get_ptable_id()
{
    lookup_from_collection \
        /api/ptables \
        "Kickstart default"
}

get_kind_id()
{
    # Foreman 3.2.1 may return HTML for
    # /api/provisioning_template_kinds.
    # Use provisioning templates to resolve PXEGrub2 kind ID.

    api_get "/api/provisioning_templates?per_page=all" >/dev/null

    if [[ ! "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]]
    then
        return 1
    fi

    jq -r '
        (.results // [])
        | map(select(
            (.template_kind_name // "") == "PXEGrub2"
        ))
        | .[0]
        | .template_kind_id // empty
    ' "$BODY" |
    head -1
}

get_subnet_id()
{
    lookup_from_collection \
        /api/subnets \
        "$1"
}

get_domain_id()
{
    lookup_from_collection \
        /api/domains \
        "$DOMAIN"
}

get_media_id()
{
    lookup_from_collection \
        /api/media \
        "$1"
}

get_os_id()
{
    lookup_from_collection \
        /api/operatingsystems \
        "$1"
}

get_template_id()
{
    lookup_from_collection \
        /api/provisioning_templates \
        "$1"
}

get_hostgroup_id()
{
    lookup_from_collection \
        /api/hostgroups \
        "$1"
}

###############################################################################
# Resolve Foreman Resource IDs
###############################################################################

header "Resolving Foreman Resource IDs"

###############################################################################
# Organization
###############################################################################

info "Finding Organization : ${ORGANIZATION}"

ORG_ID="$(get_org_id)"

if [ -n "$ORG_ID" ]
then
    ok "Organization ID : $ORG_ID"
else
    error "Organization not found : $ORGANIZATION"
    record_failure "Organization"
fi

###############################################################################
# Location
###############################################################################

info "Finding Location : ${LOCATION}"

LOCATION_ID="$(get_location_id)"

if [ -n "$LOCATION_ID" ]
then
    ok "Location ID : $LOCATION_ID"
else
    error "Location not found : $LOCATION"
    record_failure "Location"
fi

###############################################################################
# Architecture
###############################################################################

info "Finding Architecture : x86_64"

ARCH_ID="$(get_arch_id)"

if [ -n "$ARCH_ID" ]
then
    ok "Architecture ID : $ARCH_ID"
else
    error "Architecture not found : x86_64"
    record_failure "Architecture"
fi

###############################################################################
# Partition Table
###############################################################################

info "Finding Partition Table : Kickstart default"

PTABLE_ID="$(get_ptable_id)"

if [ -n "$PTABLE_ID" ]
then
    ok "Partition Table ID : $PTABLE_ID"
else
    error "Partition Table not found : Kickstart default"
    record_failure "Partition Table"
fi

###############################################################################
# PXEGrub2 Template Kind
###############################################################################

info "Finding PXEGrub2 Template Kind"

KIND_ID="$(get_kind_id)"

if [ -n "$KIND_ID" ]
then
    ok "PXEGrub2 Template Kind ID : $KIND_ID"
else
    error "PXEGrub2 template kind not found."
    record_failure "PXEGrub2 Template Kind"
fi

###############################################################################
# CentOS Subnet
###############################################################################

info "Finding CentOS Subnet : ${CENTOS_SUBNET}"

CENTOS_SUBNET_ID="$(get_subnet_id "$CENTOS_SUBNET")"

if [ -n "$CENTOS_SUBNET_ID" ]
then
    ok "CentOS Subnet ID : $CENTOS_SUBNET_ID"
else
    error "CentOS subnet not found."
    record_failure "CentOS Subnet"
fi

###############################################################################
# Rocky Subnet
###############################################################################

info "Finding Rocky Subnet : ${ROCKY_SUBNET}"

ROCKY_SUBNET_ID="$(get_subnet_id "$ROCKY_SUBNET")"

if [ -n "$ROCKY_SUBNET_ID" ]
then
    ok "Rocky Subnet ID : $ROCKY_SUBNET_ID"
else
    error "Rocky subnet not found."
    record_failure "Rocky Subnet"
fi

###############################################################################
# Required Resource Check
###############################################################################

if [ ${#FAILED_STEPS[@]} -ne 0 ]
then

    warn "Required Foreman resources could not be resolved."

    printf '%s\n' "${FAILED_STEPS[@]}" |
        sed 's/^/[ERROR] /'

    exit 1

fi

###############################################################################
# Installation Media
###############################################################################

header "Resolving Installation Media"

CENTOS_MEDIA_ID="$(get_media_id "$CENTOS_MEDIA")"
ROCKY8_MEDIA_ID="$(get_media_id "$ROCKY8_MEDIA")"
ROCKY92_MEDIA_ID="$(get_media_id "$ROCKY92_MEDIA")"
ROCKY98_MEDIA_ID="$(get_media_id "$ROCKY98_MEDIA")"

###############################################################################
# CentOS Media
###############################################################################

if [ -n "$CENTOS_MEDIA_ID" ]
then
    ok "CentOS Media ID : $CENTOS_MEDIA_ID"
else
    error "CentOS Media not found : $CENTOS_MEDIA"
    record_failure "CentOS Media"
fi

###############################################################################
# Rocky 8 Media
###############################################################################

if [ -n "$ROCKY8_MEDIA_ID" ]
then
    ok "Rocky 8 Media ID : $ROCKY8_MEDIA_ID"
else
    error "Rocky 8 Media not found : $ROCKY8_MEDIA"
    record_failure "Rocky 8 Media"
fi

###############################################################################
# Rocky 9.2 Media
###############################################################################

if [ -n "$ROCKY92_MEDIA_ID" ]
then
    ok "Rocky 9.2 Media ID : $ROCKY92_MEDIA_ID"
else
    error "Rocky 9.2 Media not found : $ROCKY92_MEDIA"
    record_failure "Rocky 9.2 Media"
fi

###############################################################################
# Rocky 9.8 Media
###############################################################################

if [ -n "$ROCKY98_MEDIA_ID" ]
then
    ok "Rocky 9.8 Media ID : $ROCKY98_MEDIA_ID"
else
    error "Rocky 9.8 Media not found : $ROCKY98_MEDIA"
    record_failure "Rocky 9.8 Media"
fi

###############################################################################
# Domain
###############################################################################

info "Finding Domain : ${DOMAIN}"

DOMAIN_ID="$(get_domain_id)"

if [ -n "$DOMAIN_ID" ]
then
    ok "Domain ID : $DOMAIN_ID"
else
    error "Domain not found : $DOMAIN"
    record_failure "Domain"
fi

if [ ${#FAILED_STEPS[@]} -ne 0 ]
then
    exit 1
fi

###############################################################################
# Target Version Selection
###############################################################################

case "${TARGET_VERSION}" in

    9.2)

        ROCKY_HG=(
            "RockyLinux9.2-SingleDisk"
        )

        ROCKY_OS=(
            "RockyLinux9.2-SingleDisk"
        )

        ROCKY_MEDIA_LIST=(
            "${ROCKY92_MEDIA}"
        )

        ;;

    9.8)

        ROCKY_HG=(
            "RockyLinux9.8-SingleDisk"
        )

        ROCKY_OS=(
            "RockyLinux9.8-SingleDisk"
        )

        ROCKY_MEDIA_LIST=(
            "${ROCKY98_MEDIA}"
        )

        ;;

    ALL)

        ROCKY_HG=(
            "RockyLinux9.2-SingleDisk"
            "RockyLinux9.8-SingleDisk"
        )

        ROCKY_OS=(
            "RockyLinux9.2-SingleDisk"
            "RockyLinux9.8-SingleDisk"
        )

        ROCKY_MEDIA_LIST=(
            "${ROCKY92_MEDIA}"
            "${ROCKY98_MEDIA}"
        )

        ;;

    *)

        error "Unsupported TARGET_VERSION=${TARGET_VERSION}"

        echo
        echo "Supported values:"
        echo "  9.2"
        echo "  9.8"
        echo "  ALL"

        exit 1

        ;;

esac

###############################################################################
# Selected Configuration
###############################################################################

header "Selected Single Disk Configuration"

echo
echo "TARGET_VERSION : ${TARGET_VERSION}"
echo
echo "Hostgroup : ${CENTOS_OS}"
echo "Hostgroup : ${ROCKY8_OS}"

for HG in "${ROCKY_HG[@]}"
do
    echo "Hostgroup : ${HG}"
done

###############################################################################
# Create Single Disk Hostgroup
###############################################################################

create_hostgroup()
{
    local HOSTGROUP="$1"
    local SUBNET_ID="$2"
    local OS_NAME="$3"
    local MEDIA_ID="$4"

    subheader "Hostgroup : ${HOSTGROUP}"

    echo "OS        : ${OS_NAME}"
    echo "Subnet    : ${SUBNET_ID}"
    echo "Media     : ${MEDIA_ID}"

    echo

    ###########################################################################
    # Check Operating System
    ###########################################################################

    OS_ID="$(get_os_id "$OS_NAME")"

    if [ -z "$OS_ID" ]
    then
        error "Operating System not found : ${OS_NAME}"
        record_failure "${OS_NAME}"
        return 1
    fi

    ok "Operating System ID : ${OS_ID}"

    ###########################################################################
    # Check Existing Hostgroup
    ###########################################################################

    HOSTGROUP_ID="$(get_hostgroup_id "$HOSTGROUP")"

    if [ -n "$HOSTGROUP_ID" ]
    then
        skip "${HOSTGROUP} already exists. ID=${HOSTGROUP_ID}"
        return 0
    fi

    ###########################################################################
    # Create Hostgroup
    ###########################################################################

    info "Creating ${HOSTGROUP}..."

    PAYLOAD="$(
        jq -n \
        --arg name "$HOSTGROUP" \
        --arg org_id "$ORG_ID" \
        --arg location_id "$LOCATION_ID" \
        --arg subnet_id "$SUBNET_ID" \
        --arg domain_id "$DOMAIN_ID" \
        --arg os_id "$OS_ID" \
        --arg arch_id "$ARCH_ID" \
        --arg medium_id "$MEDIA_ID" \
        --arg ptable_id "$PTABLE_ID" \
        '
        {
            hostgroup: {
                name: $name,
                organization_id: ($org_id | tonumber),
                location_id: ($location_id | tonumber),
                subnet_id: ($subnet_id | tonumber),
                domain_id: ($domain_id | tonumber),
                operatingsystem_id: ($os_id | tonumber),
                architecture_id: ($arch_id | tonumber),
                medium_id: ($medium_id | tonumber),
                ptable_id: ($ptable_id | tonumber),
                root_pass: "password",
                pxe_loader: "Grub2 UEFI"
            }
        }
        '
    )"

    api_post "/api/hostgroups" "$PAYLOAD" >/dev/null

    if [[ "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]]
    then

        NEW_ID="$(
            jq -r '.id // empty' "$BODY"
        )"

        ok "${HOSTGROUP} created. ID=${NEW_ID}"

    elif [ "$HTTP_STATUS" = "422" ]
    then

        #######################################################################
        # Race-safe duplicate handling
        #######################################################################

        EXISTING_ID="$(get_hostgroup_id "$HOSTGROUP")"

        if [ -n "$EXISTING_ID" ]
        then
            skip "${HOSTGROUP} already exists. ID=${EXISTING_ID}"
        else
            show_api_error POST /api/hostgroups
            error "Failed creating ${HOSTGROUP}"
            record_failure "${HOSTGROUP}"
        fi

    else

        show_api_error POST /api/hostgroups
        error "Failed creating ${HOSTGROUP}"
        record_failure "${HOSTGROUP}"

    fi

    echo
}

###############################################################################
# Create Single Disk Hostgroups
###############################################################################

create_single_disk_hostgroups()
{
    header "[1/5] Creating Single Disk Hostgroups"

    ###########################################################################
    # CentOS 7
    ###########################################################################

    create_hostgroup \
        "CentOSLinux7-SingleDisk" \
        "${CENTOS_SUBNET_ID}" \
        "${CENTOS_OS}" \
        "${CENTOS_MEDIA_ID}"

    ###########################################################################
    # Rocky Linux 8.10
    ###########################################################################

    create_hostgroup \
        "RockyLinux8.10-SingleDisk" \
        "${ROCKY_SUBNET_ID}" \
        "${ROCKY8_OS}" \
        "${ROCKY8_MEDIA_ID}"

    ###########################################################################
    # Rocky Linux 9
    ###########################################################################

    for IDX in "${!ROCKY_HG[@]}"
    do

        create_hostgroup \
            "${ROCKY_HG[$IDX]}" \
            "${ROCKY_SUBNET_ID}" \
            "${ROCKY_OS[$IDX]}" \
            "$(
                case "${ROCKY_MEDIA_LIST[$IDX]}" in
                    "${ROCKY92_MEDIA}")
                        echo "${ROCKY92_MEDIA_ID}"
                        ;;
                    "${ROCKY98_MEDIA}")
                        echo "${ROCKY98_MEDIA_ID}"
                        ;;
                esac
            )"

    done
}

###############################################################################
# Resolve Template
###############################################################################

resolve_template()
{
    local TEMPLATE="$1"

    get_template_id "$TEMPLATE"
}

###############################################################################
# Check Existing OS Provisioning Template Association
###############################################################################

template_associated()
{
    local OS_ID="$1"
    local TEMPLATE_ID="$2"

    api_get \
        "/api/operatingsystems/${OS_ID}/provisioning_templates?per_page=all" \
        >/dev/null

    if [ "$HTTP_STATUS" -lt 200 ] || [ "$HTTP_STATUS" -ge 300 ]
    then
        return 2
    fi

    jq -e \
        --argjson TEMPLATE_ID "$TEMPLATE_ID" \
        '
        (.results // [])[]
        | select(.id == $TEMPLATE_ID)
        ' \
        "$BODY" >/dev/null 2>&1

    return $?
}

###############################################################################
# Associate PXE Template
###############################################################################

associate_template()
{
    local OS_NAME="$1"
    local TEMPLATE="$2"

    subheader "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE}"
    echo

    ###########################################################################
    # OS ID
    ###########################################################################

    OS_ID="$(get_os_id "$OS_NAME")"

    if [ -z "$OS_ID" ]
    then
        error "Operating System not found : ${OS_NAME}"
        record_failure "${OS_NAME}"
        return 1
    fi

    ok "Operating System ID : ${OS_ID}"

    ###########################################################################
    # Template ID
    ###########################################################################

    TEMPLATE_ID="$(resolve_template "$TEMPLATE")"

    if [ -z "$TEMPLATE_ID" ]
    then
        error "Template not found : ${TEMPLATE}"
        record_failure "${TEMPLATE}"
        return 1
    fi

    ok "Template ID : ${TEMPLATE_ID}"

    ###########################################################################
    # Existing Association
    ###########################################################################

    template_associated "$OS_ID" "$TEMPLATE_ID"

    ASSOC_STATUS=$?

    if [ "$ASSOC_STATUS" -eq 0 ]
    then
        skip "${TEMPLATE} already associated."
        return 0
    fi

    if [ "$ASSOC_STATUS" -eq 2 ]
    then
        warn "Could not read existing template association."
    fi

    ###########################################################################
    # Associate Template
    ###########################################################################

    PAYLOAD="$(
        jq -n \
            --argjson template_id "$TEMPLATE_ID" \
            '
            {
                provisioning_template_id: $template_id
            }
            '
    )"

    api_post \
        "/api/operatingsystems/${OS_ID}/provisioning_templates" \
        "$PAYLOAD" >/dev/null

    if [[ "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]]
    then

        ok "${TEMPLATE} associated."

    elif [ "$HTTP_STATUS" = "422" ]
    then

        #######################################################################
        # Foreman may report duplicate association as 422.
        #######################################################################

        if jq -e '
            .errors.provisioning_template_id
            or .errors.base
            or .full_messages[]
        ' "$BODY" 2>/dev/null |
            grep -qiE 'already|taken|exist'
        then

            skip "${TEMPLATE} already associated."
        else

            show_api_error \
                POST \
                "/api/operatingsystems/${OS_ID}/provisioning_templates"

            record_failure "${OS_NAME} -> ${TEMPLATE}"
        fi

    else

        show_api_error \
            POST \
            "/api/operatingsystems/${OS_ID}/provisioning_templates"

        record_failure "${OS_NAME} -> ${TEMPLATE}"

    fi

    echo
}

###############################################################################
# Configure Single Disk PXE Templates
###############################################################################

configure_single_disk_templates()
{
    header "[2/5] Associating Single Disk PXE Templates"

    ###########################################################################
    # CentOS 7
    ###########################################################################

    associate_template \
        "${CENTOS_OS}" \
        "${CENTOS_TEMPLATE}"

    ###########################################################################
    # Rocky Linux 8
    ###########################################################################

    associate_template \
        "${ROCKY8_OS}" \
        "${ROCKY8_TEMPLATE}"

    ###########################################################################
    # Rocky Linux 9
    ###########################################################################

    for IDX in "${!ROCKY_OS[@]}"
    do

        OS_NAME="${ROCKY_OS[$IDX]}"

        case "${OS_NAME}" in

            "RockyLinux9.2-SingleDisk")

                associate_template \
                    "${OS_NAME}" \
                    "${ROCKY92_TEMPLATE}"

                ;;

            "RockyLinux9.8-SingleDisk")

                associate_template \
                    "${OS_NAME}" \
                    "${ROCKY98_TEMPLATE}"

                ;;

        esac

    done
}

###############################################################################
# Check Existing OS Default Template
###############################################################################

get_default_template()
{
    local OS_ID="$1"
    local KIND_ID="$2"

    ###########################################################################
    # Try the normal API endpoint.
    ###########################################################################

    api_get \
        "/api/operatingsystems/${OS_ID}/os_default_templates?per_page=all" \
        >/dev/null

    if [[ "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]]
    then

        jq -r \
            --argjson KIND_ID "$KIND_ID" \
            '
            (.results // [])[]
            | select(
                (.template_kind_id // null) == $KIND_ID
            )
            | .provisioning_template_id // .provisioning_template.id // empty
            ' \
            "$BODY" |
            head -1

        return 0
    fi

    ###########################################################################
    # Some Foreman versions may expose the default through OS details.
    ###########################################################################

    api_get "/api/operatingsystems/${OS_ID}" >/dev/null

    if [[ "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]]
    then

        jq -r \
            --argjson KIND_ID "$KIND_ID" \
            '
            (
                .os_default_templates //
                .default_templates //
                []
            )[]
            | select(
                (.template_kind_id // null) == $KIND_ID
            )
            | .provisioning_template_id // .provisioning_template.id // empty
            ' \
            "$BODY" |
            head -1

        return 0
    fi

    return 1
}

###############################################################################
# Set / Create PXEGrub2 Default Template
###############################################################################

set_default_template()
{
    local OS_NAME="$1"
    local TEMPLATE="$2"

    subheader "PXEGrub2 Default Template"

    echo "OS       : ${OS_NAME}"
    echo "Template : ${TEMPLATE}"
    echo

    ###########################################################################
    # Resolve OS ID
    ###########################################################################

    OS_ID="$(get_os_id "$OS_NAME")"

    if [ -z "$OS_ID" ]
    then
        error "Operating System not found : ${OS_NAME}"
        record_failure "${OS_NAME} default"
        return 1
    fi

    ok "Operating System ID : ${OS_ID}"

    ###########################################################################
    # Resolve Template ID
    ###########################################################################

    TEMPLATE_ID="$(get_template_id "$TEMPLATE")"

    if [ -z "$TEMPLATE_ID" ]
    then
        error "Template not found : ${TEMPLATE}"
        record_failure "${TEMPLATE} default"
        return 1
    fi

    ok "Template ID : ${TEMPLATE_ID}"

    ###########################################################################
    # PXEGrub2 Template Kind
    ###########################################################################

    ok "PXEGrub2 Template Kind ID : ${KIND_ID}"

    ###########################################################################
    # IMPORTANT:
    #
    # Foreman allows only ONE default template per template_kind_id.
    #
    # If the API says:
    #
    #   template_kind_id has already been taken
    #
    # it means a default already exists in Foreman.
    #
    # Do NOT treat this as an error.
    ###########################################################################

    EXISTING_TEMPLATE_ID="$(
        get_default_template \
            "$OS_ID" \
            "$KIND_ID"
    )"

    if [ -n "$EXISTING_TEMPLATE_ID" ]
    then

        if [ "$EXISTING_TEMPLATE_ID" = "$TEMPLATE_ID" ]
        then

            skip "PXEGrub2 default already exists and is correct."

        else

            warn "PXEGrub2 default already exists."
            warn "Existing Template ID : ${EXISTING_TEMPLATE_ID}"
            warn "Expected Template ID : ${TEMPLATE_ID}"
            skip "Existing PXEGrub2 default retained."

        fi

        return 0
    fi

    ###########################################################################
    # API could not expose existing mapping.
    #
    # We still try the POST.
    #
    # If Foreman returns 422 template_kind_id already taken,
    # treat it as SKIP.
    ###########################################################################

    info "No PXEGrub2 default returned by API. Creating one..."

    PAYLOAD="$(
        jq -n \
            --argjson template_id "$TEMPLATE_ID" \
            --argjson template_kind_id "$KIND_ID" \
            '
            {
                os_default_template: {
                    provisioning_template_id: $template_id,
                    template_kind_id: $template_kind_id
                }
            }
            '
    )"

    api_post \
        "/api/operatingsystems/${OS_ID}/os_default_templates" \
        "$PAYLOAD" >/dev/null

    ###########################################################################
    # Successful creation
    ###########################################################################

    if [[ "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]]
    then

        ok "PXEGrub2 default created."

        return 0

    fi

    ###########################################################################
    # 422 - Already Taken
    ###########################################################################

    if [ "$HTTP_STATUS" = "422" ]
    then

        if jq -e '
            .error.errors.template_kind_id[]?
            | test("already|taken|exist"; "i")
        ' "$BODY" >/dev/null 2>&1
        then

            skip "PXEGrub2 default already exists. Template kind already taken."
            return 0

        fi

        if jq -e '
            .error.full_messages[]?
            | test("template kind.*taken|already|exist"; "i")
        ' "$BODY" >/dev/null 2>&1
        then

            skip "PXEGrub2 default already exists. Template kind already taken."
            return 0

        fi

    fi

    ###########################################################################
    # Any other API failure is a real failure.
    ###########################################################################

    show_api_error \
        POST \
        "/api/operatingsystems/${OS_ID}/os_default_templates"

    record_failure "${OS_NAME} default"

    return 1
}

###############################################################################
# Configure Single Disk PXEGrub2 Defaults
###############################################################################

configure_single_disk_defaults()
{
    header "[3/5] Setting Single Disk PXEGrub2 Defaults"

    ###########################################################################
    # CentOS 7
    ###########################################################################

    set_default_template \
        "${CENTOS_OS}" \
        "${CENTOS_TEMPLATE}"

    ###########################################################################
    # Rocky Linux 8.10
    ###########################################################################

    set_default_template \
        "${ROCKY8_OS}" \
        "${ROCKY8_TEMPLATE}"

    ###########################################################################
    # Rocky Linux 9
    ###########################################################################

    for IDX in "${!ROCKY_OS[@]}"
    do

        OS_NAME="${ROCKY_OS[$IDX]}"

        case "${OS_NAME}" in

            "RockyLinux9.2-SingleDisk")

                set_default_template \
                    "${OS_NAME}" \
                    "${ROCKY92_TEMPLATE}"

                ;;

            "RockyLinux9.8-SingleDisk")

                set_default_template \
                    "${OS_NAME}" \
                    "${ROCKY98_TEMPLATE}"

                ;;

        esac

    done
}

###############################################################################
# Verify Hostgroup
###############################################################################

verify_hostgroup()
{
    local HOSTGROUP="$1"

    subheader "Hostgroup : ${HOSTGROUP}"

    HOSTGROUP_ID="$(get_hostgroup_id "$HOSTGROUP")"

    if [ -n "$HOSTGROUP_ID" ]
    then

        ok "${HOSTGROUP} exists. ID=${HOSTGROUP_ID}"

    else

        error "${HOSTGROUP} not found."
        record_failure "${HOSTGROUP}"

    fi
}

###############################################################################
# Verify Template Association
###############################################################################

verify_template_mapping()
{
    local OS_NAME="$1"
    local TEMPLATE="$2"

    subheader "OS       : ${OS_NAME}"

    echo "Expected : ${TEMPLATE}"
    echo

    OS_ID="$(get_os_id "$OS_NAME")"

    if [ -z "$OS_ID" ]
    then

        error "Operating System not found : ${OS_NAME}"
        record_failure "${OS_NAME} mapping"

        return
    fi

    TEMPLATE_ID="$(get_template_id "$TEMPLATE")"

    if [ -z "$TEMPLATE_ID" ]
    then

        error "Template not found : ${TEMPLATE}"
        record_failure "${TEMPLATE} mapping"

        return
    fi

    template_associated \
        "$OS_ID" \
        "$TEMPLATE_ID"

    STATUS=$?

    if [ "$STATUS" -eq 0 ]
    then

        ok "Template mapping correct."

    else

        error "Template mapping missing."
        record_failure "${OS_NAME} -> ${TEMPLATE}"

    fi
}

###############################################################################
# Verify PXEGrub2 Default
###############################################################################

verify_default_mapping()
{
    local OS_NAME="$1"
    local TEMPLATE="$2"

    subheader "OS       : ${OS_NAME}"

    echo "Expected : ${TEMPLATE}"
    echo

    OS_ID="$(get_os_id "$OS_NAME")"

    if [ -z "$OS_ID" ]
    then

        error "Operating System not found : ${OS_NAME}"
        record_failure "${OS_NAME} default verification"

        return
    fi

    TEMPLATE_ID="$(get_template_id "$TEMPLATE")"

    if [ -z "$TEMPLATE_ID" ]
    then

        error "Template not found : ${TEMPLATE}"
        record_failure "${TEMPLATE} default verification"

        return
    fi

    ###########################################################################
    # Try to read the default.
    ###########################################################################

    EXISTING_TEMPLATE_ID="$(
        get_default_template \
            "$OS_ID" \
            "$KIND_ID"
    )"

    ###########################################################################
    # Exact match
    ###########################################################################

    if [ -n "$EXISTING_TEMPLATE_ID" ]
    then

        if [ "$EXISTING_TEMPLATE_ID" = "$TEMPLATE_ID" ]
        then

            ok "PXEGrub2 default mapping correct."

        else

            warn "PXEGrub2 default exists but API returned a different template."
            warn "Existing Template ID : ${EXISTING_TEMPLATE_ID}"
            warn "Expected Template ID : ${TEMPLATE_ID}"

            skip "Existing PXEGrub2 default retained."

        fi

        return
    fi

    ###########################################################################
    # Foreman 3.2.1 may not expose the mapping through this API response.
    #
    # Since creation already returned:
    #
    #   template_kind_id has already been taken
    #
    # the default definitely exists.
    #
    # Therefore verification must not mark this as a failure.
    ###########################################################################

    skip "PXEGrub2 default already exists. Foreman API did not return the default mapping."
}

###############################################################################
# Verification
###############################################################################

verify_single_disk_hostgroups()
{
header "[4/5] Single Disk Hostgroup Verification"

###########################################################################
# CentOS 7
###########################################################################

verify_hostgroup \
    "CentOSLinux7-SingleDisk"

###########################################################################
# Rocky Linux 8.10
###########################################################################

verify_hostgroup \
    "RockyLinux8.10-SingleDisk"

###########################################################################
# Rocky Linux 9.2
###########################################################################

if [ "${TARGET_VERSION}" = "9.2" ]
then

    verify_hostgroup \
        "RockyLinux9.2-SingleDisk"

###########################################################################
# Rocky Linux 9.8
###########################################################################

elif [ "${TARGET_VERSION}" = "9.8" ]
then

    verify_hostgroup \
        "RockyLinux9.8-SingleDisk"

fi

}

###############################################################################
# Verify Template Associations
###############################################################################

verify_single_disk_templates()
{
    header "Single Disk Template Mapping Verification"

    ###########################################################################
    # CentOS 7
    ###########################################################################

    verify_template_mapping \
        "${CENTOS_OS}" \
        "${CENTOS_TEMPLATE}"

    ###########################################################################
    # Rocky Linux 8.10
    ###########################################################################

    verify_template_mapping \
        "${ROCKY8_OS}" \
        "${ROCKY8_TEMPLATE}"

    ###########################################################################
    # Rocky Linux 9
    ###########################################################################

    for IDX in "${!ROCKY_OS[@]}"
    do

        OS_NAME="${ROCKY_OS[$IDX]}"

        case "${OS_NAME}" in

            "RockyLinux9.2-SingleDisk")

                verify_template_mapping \
                    "${OS_NAME}" \
                    "${ROCKY92_TEMPLATE}"

                ;;

            "RockyLinux9.8-SingleDisk")

                verify_template_mapping \
                    "${OS_NAME}" \
                    "${ROCKY98_TEMPLATE}"

                ;;

        esac

    done
}

###############################################################################
# Verify PXEGrub2 Defaults
###############################################################################

verify_single_disk_defaults()
{
    header "Single Disk PXEGrub2 Default Verification"

    ###########################################################################
    # CentOS 7
    ###########################################################################

    verify_default_mapping \
        "${CENTOS_OS}" \
        "${CENTOS_TEMPLATE}"

    ###########################################################################
    # Rocky Linux 8.10
    ###########################################################################

    verify_default_mapping \
        "${ROCKY8_OS}" \
        "${ROCKY8_TEMPLATE}"

    ###########################################################################
    # Rocky Linux 9
    ###########################################################################

    for IDX in "${!ROCKY_OS[@]}"
    do

        OS_NAME="${ROCKY_OS[$IDX]}"

        case "${OS_NAME}" in

            "RockyLinux9.2-SingleDisk")

                verify_default_mapping \
                    "${OS_NAME}" \
                    "${ROCKY92_TEMPLATE}"

                ;;

            "RockyLinux9.8-SingleDisk")

                verify_default_mapping \
                    "${OS_NAME}" \
                    "${ROCKY98_TEMPLATE}"

                ;;

        esac

    done
}

###############################################################################
# Final Foreman Configuration Verification
###############################################################################

final_verification()
{
    header "[5/5] Final Single Disk Configuration Verification"

    ###########################################################################
    # Hostgroups
    ###########################################################################

    header "Single Disk Hostgroups"

    api_get \
        "/api/hostgroups?per_page=all" >/dev/null

    if [ "$HTTP_STATUS" = "200" ]
    then

        jq -r '
            .results[]
            | select(
                .name == "CentOSLinux7-SingleDisk"
                or .name == "RockyLinux8.10-SingleDisk"
                or .name == "RockyLinux9.2-SingleDisk"
                or .name == "RockyLinux9.8-SingleDisk"
            )
            | [
                .id,
                .name,
                (.operatingsystem_name // ""),
                (.subnet_name // ""),
                (.medium_name // ""),
                (.pxe_loader // "")
              ]
            | @tsv
        ' "$BODY"

    else

        error "Unable to retrieve Hostgroups."
        record_failure "Hostgroup final verification"

    fi

    echo

    ###########################################################################
    # Operating Systems
    ###########################################################################

    header "Single Disk Operating Systems"

    api_get \
        "/api/operatingsystems?per_page=all" >/dev/null

    if [ "$HTTP_STATUS" = "200" ]
    then

        jq -r '
            .results[]
            | select(
                .name == "CentOSLinux7-SingleDisk"
                or .name == "RockyLinux8.10-SingleDisk"
                or .name == "RockyLinux9.2-SingleDisk"
                or .name == "RockyLinux9.8-SingleDisk"
            )
            | [
                .id,
                .name,
                (.major // ""),
                (.minor // ""),
                (.family // "")
              ]
            | @tsv
        ' "$BODY"

    else

        error "Unable to retrieve Operating Systems."
        record_failure "Operating System final verification"

    fi

    echo

    ###########################################################################
    # PXEGrub2 Templates
    ###########################################################################

    header "Single Disk PXEGrub2 Templates"

    api_get \
        "/api/provisioning_templates?per_page=all" >/dev/null

    if [ "$HTTP_STATUS" = "200" ]
    then

        jq -r '
            .results[]
            | select(
                .template_kind_name == "PXEGrub2"
                and (
                    .name == "PXEGrub2 CentOS UEFI SingleDisk Kickstart"
                    or .name == "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"
                    or .name == "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"
                    or .name == "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"
                )
            )
            | [
                .id,
                .name,
                (.template_kind_id // ""),
                (.template_kind_name // "")
              ]
            | @tsv
        ' "$BODY"

    else

        error "Unable to retrieve Provisioning Templates."
        record_failure "PXEGrub2 template final verification"

    fi

    echo
}

###############################################################################
# Configuration Summary
###############################################################################

configuration_summary()
{
    header "Single Disk Configuration Summary"

    cat <<EOF

Target Version:
${TARGET_VERSION}

Hostgroups:

CentOSLinux7-SingleDisk
 |
 +-- OS        : ${CENTOS_OS}
 +-- PXE       : ${CENTOS_TEMPLATE}
 +-- Media     : ${CENTOS_MEDIA}
 +-- Subnet    : ${CENTOS_SUBNET_NAME}
 +-- PXE Loader: Grub2 UEFI

RockyLinux8.10-SingleDisk
 |
 +-- OS        : ${ROCKY8_OS}
 +-- PXE       : ${ROCKY8_TEMPLATE}
 +-- Media     : ${ROCKY8_MEDIA}
 +-- Subnet    : ${ROCKY_SUBNET_NAME}
 +-- PXE Loader: Grub2 UEFI

RockyLinux9.2-SingleDisk
 |
 +-- OS        : RockyLinux9.2-SingleDisk
 +-- PXE       : ${ROCKY92_TEMPLATE}
 +-- Media     : ${ROCKY92_MEDIA}
 +-- Subnet    : ${ROCKY_SUBNET_NAME}
 +-- PXE Loader: Grub2 UEFI

RockyLinux9.8-SingleDisk
 |
 +-- OS        : RockyLinux9.8-SingleDisk
 +-- PXE       : ${ROCKY98_TEMPLATE}
 +-- Media     : ${ROCKY98_MEDIA}
 +-- Subnet    : ${ROCKY_SUBNET_NAME}
 +-- PXE Loader: Grub2 UEFI


Disk Layout:

Single Disk
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
}

###############################################################################
# Final Status
###############################################################################

final_status()
{
    header "03 - Foreman Single Disk Hostgroup Bootstrap Completed"

    if [ "${#FAILED_STEPS[@]}" -eq 0 ]
    then

        ok "Single Disk Hostgroup Bootstrap completed successfully."

    else

        warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

        echo

        for STEP in "${FAILED_STEPS[@]}"
        do

            error "${STEP}"

        done

    fi
}

###############################################################################
# Manual Verification Commands
###############################################################################

manual_verification()
{
    header "Manual Verification Commands"

    echo
    echo "1. Foreman API Status"
    echo "------------------------------------------------------------"

    cat <<'EOF'
curl -ksS \
  --user "admin:$FOREMAN_PASSWORD" \
  -H 'Accept: application/json,version=2' \
  "https://cent-07-01.vgs.com/api/status" | jq
EOF

    echo
    echo "2. Single Disk Hostgroups"
    echo "------------------------------------------------------------"

    cat <<'EOF'
curl -ksS \
  --user "admin:$FOREMAN_PASSWORD" \
  -H 'Accept: application/json,version=2' \
  "https://cent-07-01.vgs.com/api/hostgroups?per_page=all" |
jq -r '
  .results[]
  | select(
      .name == "CentOSLinux7-SingleDisk"
      or .name == "RockyLinux8.10-SingleDisk"
      or .name == "RockyLinux9.2-SingleDisk"
      or .name == "RockyLinux9.8-SingleDisk"
    )
  | [
      .id,
      .name,
      (.operatingsystem_name // ""),
      (.subnet_name // ""),
      (.medium_name // ""),
      (.pxe_loader // "")
    ]
  | @tsv'
EOF

    echo
    echo "3. Single Disk Operating Systems"
    echo "------------------------------------------------------------"

    cat <<'EOF'
curl -ksS \
  --user "admin:$FOREMAN_PASSWORD" \
  -H 'Accept: application/json,version=2' \
  "https://cent-07-01.vgs.com/api/operatingsystems?per_page=all" |
jq -r '
  .results[]
  | select(
      .name == "CentOSLinux7-SingleDisk"
      or .name == "RockyLinux8.10-SingleDisk"
      or .name == "RockyLinux9.2-SingleDisk"
      or .name == "RockyLinux9.8-SingleDisk"
    )
  | [
      .id,
      .name,
      (.major // ""),
      (.minor // ""),
      (.family // "")
    ]
  | @tsv'
EOF

    echo
    echo "4. Single Disk PXEGrub2 Templates"
    echo "------------------------------------------------------------"

    cat <<'EOF'
curl -ksS \
  --user "admin:$FOREMAN_PASSWORD" \
  -H 'Accept: application/json,version=2' \
  "https://cent-07-01.vgs.com/api/provisioning_templates?per_page=all" |
jq -r '
  .results[]
  | select(
      .template_kind_name == "PXEGrub2"
      and (
        .name == "PXEGrub2 CentOS UEFI SingleDisk Kickstart"
        or .name == "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"
        or .name == "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"
        or .name == "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"
      )
    )
  | [
      .id,
      .name,
      (.template_kind_id // ""),
      (.template_kind_name // "")
    ]
  | @tsv'
EOF

    echo
    echo "5. CentOS Single Disk OS"
    echo "------------------------------------------------------------"

    cat <<'EOF'
curl -ksS \
  --user "admin:$FOREMAN_PASSWORD" \
  -H 'Accept: application/json,version=2' \
  "https://cent-07-01.vgs.com/api/operatingsystems?per_page=all" |
jq -r '
  .results[]
  | select(.name=="CentOSLinux7-SingleDisk")'
EOF

    echo
    echo "6. Rocky 8.10 Single Disk OS"
    echo "------------------------------------------------------------"

    cat <<'EOF'
curl -ksS \
  --user "admin:$FOREMAN_PASSWORD" \
  -H 'Accept: application/json,version=2' \
  "https://cent-07-01.vgs.com/api/operatingsystems?per_page=all" |
jq -r '
  .results[]
  | select(.name=="RockyLinux8.10-SingleDisk")'
EOF

    echo
    echo "7. Rocky 9.2 Single Disk OS"
    echo "------------------------------------------------------------"

    cat <<'EOF'
curl -ksS \
  --user "admin:$FOREMAN_PASSWORD" \
  -H 'Accept: application/json,version=2' \
  "https://cent-07-01.vgs.com/api/operatingsystems?per_page=all" |
jq -r '
  .results[]
  | select(.name=="RockyLinux9.2-SingleDisk")'
EOF

    echo
    echo "8. Rocky 9.8 Single Disk OS"
    echo "------------------------------------------------------------"

    cat <<'EOF'
curl -ksS \
  --user "admin:$FOREMAN_PASSWORD" \
  -H 'Accept: application/json,version=2' \
  "https://cent-07-01.vgs.com/api/operatingsystems?per_page=all" |
jq -r '
  .results[]
  | select(.name=="RockyLinux9.8-SingleDisk")'
EOF

    echo
    echo "9. PXEGrub2 Defaults"
    echo "------------------------------------------------------------"

    cat <<'EOF'
OS_ID=$(curl -ksS \
  --user "admin:$FOREMAN_PASSWORD" \
  -H 'Accept: application/json,version=2' \
  "https://cent-07-01.vgs.com/api/operatingsystems?per_page=all" |
  jq -r '
    .results[]
    | select(.name=="CentOSLinux7-SingleDisk")
    | .id')

curl -ksS \
  --user "admin:$FOREMAN_PASSWORD" \
  -H 'Accept: application/json,version=2' \
  "https://cent-07-01.vgs.com/api/operatingsystems/${OS_ID}/os_default_templates?per_page=all" |
jq
EOF

    echo
}

###############################################################################
# Exit
###############################################################################

if [ "${#FAILED_STEPS[@]}" -eq 0 ]
then
    exit 0
else
    exit 1
fi
