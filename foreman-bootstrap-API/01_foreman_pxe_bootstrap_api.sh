#!/bin/bash

###############################################################################
# 01 - Foreman PXE Bootstrap - REST API
#
# Foreman : 3.2.1
# API     : v2
#
# Creates / verifies:
#   - Installation Media
#   - Operating Systems
#   - PXEGrub2 Provisioning Templates
#   - OS <-> PXEGrub2 template associations
#   - PXEGrub2 default templates
#   - PXE Subnets
#
# IMPORTANT:
#   Existing resources are SKIPPED.
#   Existing PXEGrub2 defaults are UPDATED when necessary.
###############################################################################

set +e

###############################################################################
# CONFIGURATION
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
FOREMAN_USER="${FOREMAN_USER:-admin}"

# DO NOT put the token directly into this script.
# Export it before running:
#
# export FOREMAN_TOKEN='YOUR_CURRENT_PAT'
#
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
# RESULT TRACKING
###############################################################################

FAILURES=()
WARNINGS=()

###############################################################################
# DISPLAY FUNCTIONS
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

record_failure()
{
    FAILURES+=("$1")
}

###############################################################################
# DEPENDENCY CHECK
###############################################################################

header "Dependency Check"

REQUIRED_COMMANDS="
curl
jq
cat
head
grep
awk
sed
mkdir
mktemp
"

for CMD in $REQUIRED_COMMANDS
do
    CMD_PATH="$(command -v "$CMD" 2>/dev/null)"

    if [ -n "$CMD_PATH" ]
    then
        ok "$CMD found: $CMD_PATH"
    else
        error "$CMD not found."
        record_failure "Missing dependency: $CMD"
    fi
done

if [ "${#FAILURES[@]}" -gt 0 ]
then
    error "Required dependencies are missing."
    exit 1
fi

###############################################################################
# TOKEN CHECK
###############################################################################

if [ -z "$FOREMAN_TOKEN" ]
then
    echo
    error "FOREMAN_TOKEN is not set."
    echo
    echo "Run:"
    echo
    echo "  export FOREMAN_TOKEN='YOUR_CURRENT_PAT'"
    echo
    echo "Then run:"
    echo
    echo "  ./01_foreman_pxe_bootstrap_api.sh"
    echo
    exit 1
fi

###############################################################################
# TEMP DIRECTORY
###############################################################################

mkdir -p "$TMP_DIR"

###############################################################################
# JSON VALIDATION
###############################################################################

is_json()
{
    echo "$1" | jq -e . >/dev/null 2>&1
}

###############################################################################
# URL ENCODING
###############################################################################

urlencode()
{
    printf '%s' "$1" |
    jq -sRr @uri
}

###############################################################################
# API REQUEST
#
# Usage:
#   api_request METHOD URL JSON
#
# Sets:
#   API_STATUS
#   API_BODY
###############################################################################

api_request()
{
    local METHOD="$1"
    local URL="$2"
    local DATA="${3:-}"

    local RESPONSE_FILE
    local BODY_FILE

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

###############################################################################
# API GET
###############################################################################

api_get()
{
    api_request GET "$1"
    return $?
}

###############################################################################
# API POST
###############################################################################

api_post()
{
    api_request POST "$1" "$2"
    return $?
}

###############################################################################
# API PUT
###############################################################################

api_put()
{
    api_request PUT "$1" "$2"
    return $?
}

###############################################################################
# API DELETE
###############################################################################

api_delete()
{
    api_request DELETE "$1" ""
    return $?
}

###############################################################################
# API ERROR DISPLAY
###############################################################################

show_api_error()
{
    error "API request failed."
    error "HTTP Status : ${API_STATUS}"
    error "Method      : $1"
    error "URL         : $2"

    if [ -n "$API_BODY" ]
    then
        echo "$API_BODY" | jq . 2>/dev/null || echo "$API_BODY"
    fi
}

###############################################################################
# FIND MEDIA
###############################################################################

find_media()
{
    local NAME="$1"

    MEDIA_ID=""

    api_get "${API}/media?per_page=all"

    if [ "$API_STATUS" != "200" ]
    then
        return 1
    fi

    if ! is_json "$API_BODY"
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

###############################################################################
# FIND MEDIA BY PATH
###############################################################################

find_media_by_path()
{
    local PATH_VALUE="$1"

    MEDIA_ID=""

    api_get "${API}/media?per_page=all"

    if [ "$API_STATUS" != "200" ]
    then
        return 1
    fi

    if ! is_json "$API_BODY"
    then
        return 1
    fi

    MEDIA_ID="$(
        echo "$API_BODY" |
        jq -r --arg PATH "$PATH_VALUE" '
            .results[]?
            | select(.path == $PATH)
            | .id
        ' |
        head -n 1
    )"

    [ -n "$MEDIA_ID" ] &&
    [ "$MEDIA_ID" != "null" ]
}

###############################################################################
# CREATE / VERIFY MEDIA
###############################################################################

ensure_media()
{
    local NAME="$1"
    local PATH_VALUE="$2"
    local FAMILY="$3"

    section "Installation Media : $NAME"

    ###########################################################################
    # First search by NAME
    ###########################################################################

    if find_media "$NAME"
    then
        skip "$NAME already exists. ID=$MEDIA_ID"

        MEDIA_IDS["$NAME"]="$MEDIA_ID"

        return 0
    fi

    ###########################################################################
    # Then search by PATH
    ###########################################################################

    if find_media_by_path "$PATH_VALUE"
    then
        skip "Path already exists for $NAME. Existing ID=$MEDIA_ID"

        MEDIA_IDS["$NAME"]="$MEDIA_ID"

        return 0
    fi

    ###########################################################################
    # Create
    ###########################################################################

    info "Creating $NAME"

    PAYLOAD="$(
        jq -n \
            --arg NAME "$NAME" \
            --arg PATH "$PATH_VALUE" \
            --arg FAMILY "$FAMILY" \
            '{
                medium: {
                    name: $NAME,
                    path: $PATH,
                    os_family: $FAMILY
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

    ###########################################################################
    # Race condition / already exists
    ###########################################################################

    if [ "$API_STATUS" = "422" ]
    then
        if find_media "$NAME"
        then
            skip "$NAME already exists. ID=$MEDIA_ID"
            MEDIA_IDS["$NAME"]="$MEDIA_ID"
            return 0
        fi

        if find_media_by_path "$PATH_VALUE"
        then
            skip "Path already exists for $NAME. Existing ID=$MEDIA_ID"
            MEDIA_IDS["$NAME"]="$MEDIA_ID"
            return 0
        fi
    fi

    show_api_error POST "${API}/media"
    record_failure "$NAME media"

    return 1
}

###############################################################################
# FIND ARCHITECTURE
###############################################################################

find_architecture()
{
    ARCH_ID=""

    api_get "${API}/architectures?per_page=all"

    if [ "$API_STATUS" != "200" ]
    then
        return 1
    fi

    if ! is_json "$API_BODY"
    then
        return 1
    fi

    ARCH_ID="$(
        echo "$API_BODY" |
        jq -r '
            .results[]?
            | select(.name == "x86_64")
            | .id
        ' |
        head -n 1
    )"

    [ -n "$ARCH_ID" ] &&
    [ "$ARCH_ID" != "null" ]
}

###############################################################################
# FIND PTABLE
###############################################################################

find_ptable()
{
    PTABLE_ID=""

    api_get "${API}/ptables?per_page=all"

    if [ "$API_STATUS" != "200" ]
    then
        return 1
    fi

    if ! is_json "$API_BODY"
    then
        return 1
    fi

    PTABLE_ID="$(
        echo "$API_BODY" |
        jq -r '
            .results[]?
            | select(.name == "Kickstart default")
            | .id
        ' |
        head -n 1
    )"

    [ -n "$PTABLE_ID" ] &&
    [ "$PTABLE_ID" != "null" ]
}

###############################################################################
# FIND OPERATING SYSTEM
###############################################################################

find_os()
{
    local NAME="$1"

    OS_ID=""

    api_get "${API}/operatingsystems?per_page=all"

    if [ "$API_STATUS" != "200" ]
    then
        return 1
    fi

    if ! is_json "$API_BODY"
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

###############################################################################
# CREATE / VERIFY OPERATING SYSTEM
###############################################################################

ensure_os()
{
    local NAME="$1"
    local MAJOR="$2"
    local MINOR="$3"
    local MEDIA_NAME="$4"

    section "Operating System : $NAME"

    ###########################################################################
    # Existing OS
    ###########################################################################

    if find_os "$NAME"
    then
        skip "$NAME already exists. ID=$OS_ID"

        OS_IDS["$NAME"]="$OS_ID"

        #######################################################################
        # Make sure media is associated
        #######################################################################

        local MEDIUM_ID="${MEDIA_IDS[$MEDIA_NAME]}"

        if [ -n "$MEDIUM_ID" ]
        then
            PAYLOAD="$(
                jq -n \
                    --argjson MEDIA_ID "$MEDIUM_ID" \
                    --argjson ARCH_ID "$ARCH_ID" \
                    --argjson PTABLE_ID "$PTABLE_ID" \
                    '{
                        operatingsystem: {
                            media: [{id: $MEDIA_ID}],
                            architectures: [{id: $ARCH_ID}],
                            ptables: [{id: $PTABLE_ID}]
                        }
                    }'
            )"

            api_put "${API}/operatingsystems/${OS_ID}" "$PAYLOAD"

            if [ "$API_STATUS" = "200" ]
            then
                ok "$NAME associations verified."
            else
                warn "$NAME exists but association update returned HTTP $API_STATUS."
            fi
        fi

        return 0
    fi

    ###########################################################################
    # Media ID
    ###########################################################################

    MEDIUM_ID="${MEDIA_IDS[$MEDIA_NAME]}"

    if [ -z "$MEDIUM_ID" ]
    then
        error "Installation media unavailable : $MEDIA_NAME"
        record_failure "$NAME - media"
        return 1
    fi

    ###########################################################################
    # Create OS
    ###########################################################################

    info "Creating $NAME"

    PAYLOAD="$(
        jq -n \
            --arg NAME "$NAME" \
            --arg MAJOR "$MAJOR" \
            --arg MINOR "$MINOR" \
            --argjson MEDIA_ID "$MEDIUM_ID" \
            --argjson ARCH_ID "$ARCH_ID" \
            --argjson PTABLE_ID "$PTABLE_ID" \
            '{
                operatingsystem: {
                    name: $NAME,
                    major: $MAJOR,
                    minor: $MINOR,
                    family: "Redhat",
                    media: [{id: $MEDIA_ID}],
                    architectures: [{id: $ARCH_ID}],
                    ptables: [{id: $PTABLE_ID}]
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

    ###########################################################################
    # Existing race condition
    ###########################################################################

    if [ "$API_STATUS" = "422" ]
    then
        if find_os "$NAME"
        then
            skip "$NAME already exists. ID=$OS_ID"
            OS_IDS["$NAME"]="$OS_ID"
            return 0
        fi
    fi

    show_api_error POST "${API}/operatingsystems"
    record_failure "$NAME"

    return 1
}

###############################################################################
# FIND TEMPLATE KIND
###############################################################################

find_template_kind()
{
    TEMPLATE_KIND_ID=""

    api_get "${API}/template_kinds?per_page=all"

    if [ "$API_STATUS" != "200" ]
    then
        error "Unable to retrieve template kinds."
        return 1
    fi

    if ! is_json "$API_BODY"
    then
        error "Template kind API returned invalid JSON."
        echo "$API_BODY"
        return 1
    fi

    TEMPLATE_KIND_ID="$(
        echo "$API_BODY" |
        jq -r '
            .results[]?
            | select(.name == "PXEGrub2")
            | .id
        ' |
        head -n 1
    )"

    if [ -z "$TEMPLATE_KIND_ID" ] ||
       [ "$TEMPLATE_KIND_ID" = "null" ]
    then
        return 1
    fi

    return 0
}

###############################################################################
# FIND PROVISIONING TEMPLATE
###############################################################################

find_template()
{
    local NAME="$1"

    TEMPLATE_ID=""

    api_get "${API}/provisioning_templates?per_page=all"

    if [ "$API_STATUS" != "200" ]
    then
        return 1
    fi

    if ! is_json "$API_BODY"
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
# CREATE / VERIFY PROVISIONING TEMPLATE
###############################################################################

ensure_template()
{
    local NAME="$1"
    local FILE="$2"

    section "PXEGrub2 Template : $NAME"

    ###########################################################################
    # Existing template
    ###########################################################################

    if find_template "$NAME"
    then
        skip "$NAME already exists. ID=$TEMPLATE_ID"

        TEMPLATE_IDS["$NAME"]="$TEMPLATE_ID"

        return 0
    fi

    ###########################################################################
    # Template kind must exist
    ###########################################################################

    if [ -z "$TEMPLATE_KIND_ID" ]
    then
        error "PXEGrub2 template kind unavailable."
        record_failure "$NAME - template kind"
        return 1
    fi

    ###########################################################################
    # Template file
    ###########################################################################

    if [ ! -f "$FILE" ]
    then
        error "Template file missing: $FILE"
        record_failure "$NAME - template file"
        return 1
    fi

    TEMPLATE_CONTENT="$(cat "$FILE")"

    ###########################################################################
    # Create
    ###########################################################################

    info "Creating $NAME"

    PAYLOAD="$(
        jq -n \
            --arg NAME "$NAME" \
            --arg TEMPLATE "$TEMPLATE_CONTENT" \
            --argjson KIND "$TEMPLATE_KIND_ID" \
            '{
                provisioning_template: {
                    name: $NAME,
                    template: $TEMPLATE,
                    template_kind_id: $KIND
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
    # Existing resource
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

    show_api_error POST "${API}/provisioning_templates"
    record_failure "$NAME"

    return 1
}

###############################################################################
# ASSOCIATE TEMPLATE WITH OS
###############################################################################

ensure_os_template_association()
{
    local OS_NAME="$1"
    local TEMPLATE_NAME="$2"

    section "Associating PXEGrub2 Template"

    echo "OS       : $OS_NAME"
    echo "Template : $TEMPLATE_NAME"

    OS_ID="${OS_IDS[$OS_NAME]}"
    TEMPLATE_ID="${TEMPLATE_IDS[$TEMPLATE_NAME]}"

    if [ -z "$OS_ID" ]
    then
        error "Operating system ID unavailable : $OS_NAME"
        record_failure "$OS_NAME association"
        return 1
    fi

    if [ -z "$TEMPLATE_ID" ]
    then
        error "Template ID unavailable : $TEMPLATE_NAME"
        record_failure "$TEMPLATE_NAME association"
        return 1
    fi

    ###########################################################################
    # Get current OS template associations
    ###########################################################################

    api_get "${API}/operatingsystems/${OS_ID}/provisioning_templates"

    if [ "$API_STATUS" != "200" ]
    then
        show_api_error GET \
            "${API}/operatingsystems/${OS_ID}/provisioning_templates"

        record_failure "$OS_NAME template association lookup"
        return 1
    fi

    if ! is_json "$API_BODY"
    then
        error "Invalid JSON returned while checking OS templates."
        record_failure "$OS_NAME template association lookup"
        return 1
    fi

    ASSOCIATED="$(
        echo "$API_BODY" |
        jq -r --argjson ID "$TEMPLATE_ID" '
            .results[]?
            | select(.id == $ID)
            | .id
        ' |
        head -n 1
    )"

    if [ -n "$ASSOCIATED" ]
    then
        skip "Template already associated."
        return 0
    fi

    ###########################################################################
    # Associate through OS update
    ###########################################################################

    PAYLOAD="$(
        jq -n \
            --argjson TEMPLATE_ID "$TEMPLATE_ID" \
            '{
                operatingsystem: {
                    provisioning_templates: [
                        {id: $TEMPLATE_ID}
                    ]
                }
            }'
    )"

    api_put "${API}/operatingsystems/${OS_ID}" "$PAYLOAD"

    if [ "$API_STATUS" = "200" ]
    then
        ok "Template associated with $OS_NAME."
        return 0
    fi

    ###########################################################################
    # Some Foreman versions require explicit PUT with complete list.
    ###########################################################################

    CURRENT_TEMPLATE_IDS="$(
        echo "$API_BODY" 2>/dev/null |
        jq -r '.results[]?.id' 2>/dev/null |
        awk 'NF'
    )"

    TEMPLATE_JSON="[]"

    while read -r EXISTING_ID
    do
        [ -z "$EXISTING_ID" ] && continue

        TEMPLATE_JSON="$(
            echo "$TEMPLATE_JSON" |
            jq --argjson ID "$EXISTING_ID" '. + [{id:$ID}]'
        )"

    done <<< "$CURRENT_TEMPLATE_IDS"

    TEMPLATE_JSON="$(
        echo "$TEMPLATE_JSON" |
        jq --argjson ID "$TEMPLATE_ID" '. + [{id:$ID}] | unique_by(.id)'
    )"

    PAYLOAD="$(
        jq -n \
            --argjson TEMPLATES "$TEMPLATE_JSON" \
            '{
                operatingsystem: {
                    provisioning_templates: $TEMPLATES
                }
            }'
    )"

    api_put "${API}/operatingsystems/${OS_ID}" "$PAYLOAD"

    if [ "$API_STATUS" = "200" ]
    then
        ok "Template associated with $OS_NAME."
        return 0
    fi

    show_api_error PUT "${API}/operatingsystems/${OS_ID}"
    record_failure "$OS_NAME template association"

    return 1
}

###############################################################################
# FIND EXISTING DEFAULT TEMPLATE FOR KIND
###############################################################################

find_os_default()
{
    local OS_ID="$1"
    local KIND_ID="$2"

    DEFAULT_ID=""

    api_get "${API}/operatingsystems/${OS_ID}/os_default_templates"

    if [ "$API_STATUS" != "200" ]
    then
        return 1
    fi

    if ! is_json "$API_BODY"
    then
        return 1
    fi

    DEFAULT_ID="$(
        echo "$API_BODY" |
        jq -r --argjson KIND "$KIND_ID" '
            .results[]?
            | select(.template_kind_id == $KIND)
            | .id
        ' |
        head -n 1
    )"

    [ -n "$DEFAULT_ID" ] &&
    [ "$DEFAULT_ID" != "null" ]
}

###############################################################################
# SET PXEGRUB2 DEFAULT
###############################################################################

ensure_os_default()
{
    local OS_NAME="$1"
    local TEMPLATE_NAME="$2"

    section "Setting PXEGrub2 Default"

    echo "OS       : $OS_NAME"
    echo "Template : $TEMPLATE_NAME"

    OS_ID="${OS_IDS[$OS_NAME]}"
    TEMPLATE_ID="${TEMPLATE_IDS[$TEMPLATE_NAME]}"

    if [ -z "$OS_ID" ]
    then
        error "Operating system ID unavailable : $OS_NAME"
        record_failure "$OS_NAME default template"
        return 1
    fi

    if [ -z "$TEMPLATE_ID" ]
    then
        error "Template ID unavailable : $TEMPLATE_NAME"
        record_failure "$OS_NAME default template"
        return 1
    fi

    if [ -z "$TEMPLATE_KIND_ID" ]
    then
        error "PXEGrub2 template kind ID unavailable."
        record_failure "$OS_NAME default template"
        return 1
    fi

    ###########################################################################
    # Find existing default by KIND
    ###########################################################################

    if find_os_default "$OS_ID" "$TEMPLATE_KIND_ID"
    then

        #######################################################################
        # Check whether already correct
        #######################################################################

        EXISTING_TEMPLATE_ID="$(
            echo "$API_BODY" |
            jq -r --argjson KIND "$TEMPLATE_KIND_ID" --argjson OSID "$OS_ID" '
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

        if [ "$EXISTING_TEMPLATE_ID" = "$TEMPLATE_ID" ]
        then
            skip "PXEGrub2 default already correct. ID=$DEFAULT_ID"
            return 0
        fi

        #######################################################################
        # UPDATE existing default
        #######################################################################

        info "Existing PXEGrub2 default found. Updating it..."

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

        show_api_error \
            PUT \
            "${API}/operatingsystems/${OS_ID}/os_default_templates/${DEFAULT_ID}"

        record_failure "$OS_NAME default template"
        return 1

    fi

    ###########################################################################
    # No default for this kind
    ###########################################################################

    info "No PXEGrub2 default found. Creating one..."

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
    # Another default may have appeared between GET and POST.
    ###########################################################################

    if [ "$API_STATUS" = "422" ]
    then

        if find_os_default "$OS_ID" "$TEMPLATE_KIND_ID"
        then

            info "PXEGrub2 default exists. Updating existing entry..."

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

    show_api_error \
        POST \
        "${API}/operatingsystems/${OS_ID}/os_default_templates"

    record_failure "$OS_NAME default template"

    return 1
}

###############################################################################
# FIND DOMAIN
###############################################################################

find_domain()
{
    local NAME="$1"

    DOMAIN_ID=""

    api_get "${API}/domains?per_page=all"

    if [ "$API_STATUS" != "200" ]
    then
        return 1
    fi

    if ! is_json "$API_BODY"
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
# FIND PROXY
###############################################################################

find_proxy()
{
    local NAME="$1"

    PROXY_ID=""

    api_get "${API}/smart_proxies?per_page=all"

    if [ "$API_STATUS" != "200" ]
    then
        return 1
    fi

    if ! is_json "$API_BODY"
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
# FIND SUBNET
###############################################################################

find_subnet()
{
    local NAME="$1"

    SUBNET_ID=""

    api_get "${API}/subnets?per_page=all"

    if [ "$API_STATUS" != "200" ]
    then
        return 1
    fi

    if ! is_json "$API_BODY"
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

###############################################################################
# CREATE / UPDATE SUBNET
###############################################################################

ensure_subnet()
{
    local NAME="$1"
    local NETWORK="$2"
    local MASK="$3"
    local GATEWAY="$4"
    local DNS="$5"
    local TFTP_PROXY_NAME="$6"
    local DHCP_PROXY_NAME="$7"

    section "Subnet : $NAME"

    echo "Network      : $NETWORK"
    echo "Mask         : $MASK"
    echo "Gateway      : $GATEWAY"
    echo "DNS          : $DNS"
    echo "TFTP Proxy   : $TFTP_PROXY_NAME"
    echo "DHCP Proxy   : $DHCP_PROXY_NAME"

    ###########################################################################
    # DOMAIN
    ###########################################################################

    if find_domain "vgs.com"
    then
        DOMAIN_ID_FOUND="$DOMAIN_ID"
        ok "Domain found : vgs.com ID=$DOMAIN_ID_FOUND"
    else
        warn "Domain vgs.com not found."
        DOMAIN_ID_FOUND=""
    fi

    ###########################################################################
    # TFTP PROXY
    ###########################################################################

    if find_proxy "$TFTP_PROXY_NAME"
    then
        TFTP_PROXY_ID="$PROXY_ID"
        ok "TFTP proxy found : $TFTP_PROXY_NAME ID=$TFTP_PROXY_ID"
    else
        error "TFTP proxy not found : $TFTP_PROXY_NAME"
        record_failure "$NAME TFTP proxy"
        return 1
    fi

    ###########################################################################
    # DHCP PROXY
    ###########################################################################

    if find_proxy "$DHCP_PROXY_NAME"
    then
        DHCP_PROXY_ID="$PROXY_ID"
        ok "DHCP proxy found : $DHCP_PROXY_NAME ID=$DHCP_PROXY_ID"
    else
        error "DHCP proxy not found : $DHCP_PROXY_NAME"
        record_failure "$NAME DHCP proxy"
        return 1
    fi

    ###########################################################################
    # EXISTING SUBNET
    ###########################################################################

    if find_subnet "$NAME"
    then

        skip "$NAME already exists. ID=$SUBNET_ID"

        PAYLOAD="$(
            jq -n \
                --arg NETWORK "$NETWORK" \
                --arg MASK "$MASK" \
                --arg GATEWAY "$GATEWAY" \
                --arg DNS "$DNS" \
                --argjson DOMAIN "$DOMAIN_ID_FOUND" \
                --argjson TFTP "$TFTP_PROXY_ID" \
                --argjson DHCP "$DHCP_PROXY_ID" \
                '{
                    subnet: {
                        network: $NETWORK,
                        mask: $MASK,
                        gateway: $GATEWAY,
                        dns_primary: $DNS,
                        domain_ids: (if $DOMAIN == 0 then [] else [$DOMAIN] end),
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

        return 0
    fi

    ###########################################################################
    # CREATE
    ###########################################################################

    info "Creating $NAME"

    PAYLOAD="$(
        jq -n \
            --arg NAME "$NAME" \
            --arg NETWORK "$NETWORK" \
            --arg MASK "$MASK" \
            --arg GATEWAY "$GATEWAY" \
            --arg DNS "$DNS" \
            --argjson DOMAIN "$DOMAIN_ID_FOUND" \
            --argjson TFTP "$TFTP_PROXY_ID" \
            --argjson DHCP "$DHCP_PROXY_ID" \
            '{
                subnet: {
                    name: $NAME,
                    network: $NETWORK,
                    mask: $MASK,
                    gateway: $GATEWAY,
                    dns_primary: $DNS,
                    domain_ids: (if $DOMAIN == 0 then [] else [$DOMAIN] end),
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

    ###########################################################################
    # Existing
    ###########################################################################

    if [ "$API_STATUS" = "422" ]
    then
        if find_subnet "$NAME"
        then
            skip "$NAME already exists. ID=$SUBNET_ID"
            return 0
        fi
    fi

    show_api_error POST "${API}/subnets"
    record_failure "$NAME subnet"

    return 1
}

###############################################################################
# GENERATE PXE TEMPLATE FILES
###############################################################################

generate_template_files()
{
    header "Generating PXEGrub2 Template Files"

    mkdir -p "$TMP_DIR"

    ###########################################################################
    # CentOS 7 RAID
    ###########################################################################

    cat > "$TMP_DIR/centos-raid.erb" <<'EOF'
set timeout=5
set default=0

menuentry 'Install CentOS 7 - RAID1' {
    linuxefi http://192.168.253.136/tftpboot/centos7/vmlinuz inst.repo=http://192.168.253.136/repo/centos/ inst.ks=<%= foreman_url %>/unattended/provision
    initrdefi http://192.168.253.136/tftpboot/centos7/initrd.img
}
EOF

    ###########################################################################
    # CentOS 7 Single Disk
    ###########################################################################

    cat > "$TMP_DIR/centos-singledisk.erb" <<'EOF'
set timeout=5
set default=0

menuentry 'Install CentOS 7 - Single Disk' {
    linuxefi http://192.168.253.136/tftpboot/centos7/vmlinuz inst.repo=http://192.168.253.136/repo/centos/ inst.ks=<%= foreman_url %>/unattended/provision
    initrdefi http://192.168.253.136/tftpboot/centos7/initrd.img
}
EOF

    ###########################################################################
    # Rocky 8 RAID
    ###########################################################################

    cat > "$TMP_DIR/rocky8-raid.erb" <<'EOF'
set timeout=5
set default=0

menuentry 'Install Rocky Linux 8.10 - RAID1' {
    linuxefi http://192.168.253.136/tftpboot/rocky8/vmlinuz inst.repo=http://192.168.253.136/repo/rocky8/ inst.ks=<%= foreman_url %>/unattended/provision
    initrdefi http://192.168.253.136/tftpboot/rocky8/initrd.img
}
EOF

    ###########################################################################
    # Rocky 8 Single Disk
    ###########################################################################

    cat > "$TMP_DIR/rocky8-singledisk.erb" <<'EOF'
set timeout=5
set default=0

menuentry 'Install Rocky Linux 8.10 - Single Disk' {
    linuxefi http://192.168.253.136/tftpboot/rocky8/vmlinuz inst.repo=http://192.168.253.136/repo/rocky8/ inst.ks=<%= foreman_url %>/unattended/provision
    initrdefi http://192.168.253.136/tftpboot/rocky8/initrd.img
}
EOF

    ###########################################################################
    # Rocky 9.2 RAID
    ###########################################################################

    cat > "$TMP_DIR/rocky92-raid.erb" <<'EOF'
set timeout=5
set default=0

menuentry 'Install Rocky Linux 9.2 - RAID1' {
    linuxefi http://192.168.253.136/tftpboot/rocky92/vmlinuz inst.repo=http://192.168.253.136/repo/rocky9.2/ inst.ks=<%= foreman_url %>/unattended/provision
    initrdefi http://192.168.253.136/tftpboot/rocky92/initrd.img
}
EOF

    ###########################################################################
    # Rocky 9.2 Single Disk
    ###########################################################################

    cat > "$TMP_DIR/rocky92-singledisk.erb" <<'EOF'
set timeout=5
set default=0

menuentry 'Install Rocky Linux 9.2 - Single Disk' {
    linuxefi http://192.168.253.136/tftpboot/rocky92/vmlinuz inst.repo=http://192.168.253.136/repo/rocky9.2/ inst.ks=<%= foreman_url %>/unattended/provision
    initrdefi http://192.168.253.136/tftpboot/rocky92/initrd.img
}
EOF

    ###########################################################################
    # Rocky 9.8 RAID
    ###########################################################################

    cat > "$TMP_DIR/rocky98-raid.erb" <<'EOF'
set timeout=5
set default=0

menuentry 'Install Rocky Linux 9.8 - RAID1' {
    linuxefi http://192.168.253.136/tftpboot/rocky9/vmlinuz inst.repo=http://192.168.253.136/repo/rocky9/ inst.ks=<%= foreman_url %>/unattended/provision
    initrdefi http://192.168.253.136/tftpboot/rocky9/initrd.img
}
EOF

    ###########################################################################
    # Rocky 9.8 Single Disk
    ###########################################################################

    cat > "$TMP_DIR/rocky98-singledisk.erb" <<'EOF'
set timeout=5
set default=0

menuentry 'Install Rocky Linux 9.8 - Single Disk' {
    linuxefi http://192.168.253.136/tftpboot/rocky9/vmlinuz inst.repo=http://192.168.253.136/repo/rocky9/ inst.ks=<%= foreman_url %>/unattended/provision
    initrdefi http://192.168.253.136/tftpboot/rocky9/initrd.img
}
EOF

    ok "All 8 PXEGrub2 template files generated."

    ls -lh "$TMP_DIR"/*.erb
}

###############################################################################
# VERIFY PXE TEMPLATES
###############################################################################

verify_templates()
{
    header "PXEGrub2 Template Verification"

    local NAME
    local ID

    for NAME in \
        "PXEGrub2 CentOS UEFI RAID Kickstart" \
        "PXEGrub2 CentOS UEFI SingleDisk Kickstart" \
        "PXEGrub2 Rocky8 UEFI RAID Kickstart" \
        "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" \
        "PXEGrub2 Rocky9.2 UEFI RAID Kickstart" \
        "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart" \
        "PXEGrub2 Rocky9.8 UEFI RAID Kickstart" \
        "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"
    do

        ID="${TEMPLATE_IDS[$NAME]}"

        if [ -n "$ID" ]
        then
            ok "$NAME | ID=$ID | kind=PXEGrub2 | kind_id=$TEMPLATE_KIND_ID"
        else
            error "$NAME verification failed."
        fi

    done
}

###############################################################################
# VERIFY OS MAPPINGS
###############################################################################

verify_os_mappings()
{
    header "OS Template Mapping Verification"

    local OS_NAME
    local TEMPLATE_NAME
    local OS_ID
    local TEMPLATE_ID

    for MAPPING in \
        "CentOSLinux7-RAID|PXEGrub2 CentOS UEFI RAID Kickstart" \
        "CentOSLinux7-SingleDisk|PXEGrub2 CentOS UEFI SingleDisk Kickstart" \
        "RockyLinux8.10-RAID|PXEGrub2 Rocky8 UEFI RAID Kickstart" \
        "RockyLinux8.10-SingleDisk|PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" \
        "RockyLinux9.2-RAID|PXEGrub2 Rocky9.2 UEFI RAID Kickstart" \
        "RockyLinux9.2-SingleDisk|PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart" \
        "RockyLinux9.8-RAID|PXEGrub2 Rocky9.8 UEFI RAID Kickstart" \
        "RockyLinux9.8-SingleDisk|PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"
    do

        OS_NAME="${MAPPING%%|*}"
        TEMPLATE_NAME="${MAPPING#*|}"

        OS_ID="${OS_IDS[$OS_NAME]}"
        TEMPLATE_ID="${TEMPLATE_IDS[$TEMPLATE_NAME]}"

        if [ -z "$OS_ID" ] ||
           [ -z "$TEMPLATE_ID" ]
        then
            error "$OS_NAME -> $TEMPLATE_NAME"
            continue
        fi

        api_get "${API}/operatingsystems/${OS_ID}/provisioning_templates"

        if [ "$API_STATUS" != "200" ] ||
           ! is_json "$API_BODY"
        then
            error "$OS_NAME -> $TEMPLATE_NAME"
            continue
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
            ok "$OS_NAME -> $TEMPLATE_NAME"
        else
            error "$OS_NAME -> $TEMPLATE_NAME"
        fi

    done
}

###############################################################################
# VERIFY DEFAULTS
###############################################################################

verify_defaults()
{
    header "PXEGrub2 Default Template Verification"

    local OS_NAME
    local TEMPLATE_NAME
    local OS_ID
    local TEMPLATE_ID

    for MAPPING in \
        "CentOSLinux7-RAID|PXEGrub2 CentOS UEFI RAID Kickstart" \
        "CentOSLinux7-SingleDisk|PXEGrub2 CentOS UEFI SingleDisk Kickstart" \
        "RockyLinux8.10-RAID|PXEGrub2 Rocky8 UEFI RAID Kickstart" \
        "RockyLinux8.10-SingleDisk|PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" \
        "RockyLinux9.2-RAID|PXEGrub2 Rocky9.2 UEFI RAID Kickstart" \
        "RockyLinux9.2-SingleDisk|PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart" \
        "RockyLinux9.8-RAID|PXEGrub2 Rocky9.8 UEFI RAID Kickstart" \
        "RockyLinux9.8-SingleDisk|PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"
    do

        OS_NAME="${MAPPING%%|*}"
        TEMPLATE_NAME="${MAPPING#*|}"

        OS_ID="${OS_IDS[$OS_NAME]}"
        TEMPLATE_ID="${TEMPLATE_IDS[$TEMPLATE_NAME]}"

        if [ -z "$OS_ID" ] ||
           [ -z "$TEMPLATE_ID" ]
        then
            error "$OS_NAME default template missing."
            continue
        fi

        api_get "${API}/operatingsystems/${OS_ID}/os_default_templates"

        if [ "$API_STATUS" != "200" ] ||
           ! is_json "$API_BODY"
        then
            error "$OS_NAME default template lookup failed."
            continue
        fi

        FOUND="$(
            echo "$API_BODY" |
            jq -r \
                --argjson KIND "$TEMPLATE_KIND_ID" \
                --argjson TEMPLATE "$TEMPLATE_ID" '
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

        if [ -n "$FOUND" ]
        then
            ok "$OS_NAME -> $TEMPLATE_NAME | default_id=$FOUND"
        else
            error "$OS_NAME default template missing."
        fi

    done
}

###############################################################################
# VERIFY SUBNETS
###############################################################################

verify_subnets()
{
    header "PXE Subnet Verification"

    api_get "${API}/subnets?per_page=all"

    if [ "$API_STATUS" != "200" ] ||
       ! is_json "$API_BODY"
    then
        error "Unable to retrieve subnets."
        return
    fi

    echo "$API_BODY" |
    jq -r '
        .results[]? |
        [
            .id,
            .name,
            (.network + "/" + .mask),
            (.dhcp.name // "-"),
            (.tftp.name // "-")
        ] |
        @tsv
    '
}

###############################################################################
# FINAL OS VERIFICATION
###############################################################################

final_os_verification()
{
    header "Final Operating System Verification"

    local NAME
    local ID

    for NAME in \
        "CentOSLinux7-RAID" \
        "CentOSLinux7-SingleDisk" \
        "RockyLinux8.10-RAID" \
        "RockyLinux8.10-SingleDisk" \
        "RockyLinux9.2-RAID" \
        "RockyLinux9.2-SingleDisk" \
        "RockyLinux9.8-RAID" \
        "RockyLinux9.8-SingleDisk"
    do

        ID="${OS_IDS[$NAME]}"

        if [ -z "$ID" ]
        then
            continue
        fi

        api_get "${API}/operatingsystems/${ID}"

        if [ "$API_STATUS" != "200" ] ||
           ! is_json "$API_BODY"
        then
            continue
        fi

        echo
        echo -e "${MAGENTA}------------------------------------------------------------${RESET}"
        echo -e "${WHITE}OS : $NAME${RESET}"
        echo -e "${WHITE}ID : $ID${RESET}"
        echo -e "${MAGENTA}------------------------------------------------------------${RESET}"

        echo "$API_BODY" |
        jq -r '
            "Name          : \(.name)",
            "Title         : \(.title)",
            "Major         : \(.major)",
            "Minor         : \(.minor)",
            "Family        : \(.family)",
            "Architecture  : \(.architectures | map(.name) | join(", "))",
            "Media         : \(.media | map(.name) | join(", "))",
            "Ptable        : \(.ptables | map(.name) | join(", "))",
            "Templates     : \(.provisioning_templates | map(.name) | join(", "))"
        '

    done
}

###############################################################################
# MAIN
###############################################################################

header "01 - Foreman PXE Bootstrap - REST API"

###############################################################################
# AUTHENTICATION
###############################################################################

header "Foreman API Authentication Test"

info "Testing Foreman REST API..."

api_get "${API}/status"

if [ "$API_STATUS" = "200" ] &&
   is_json "$API_BODY"
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

    show_api_error GET "${API}/status"
    error "Foreman API authentication failed."
    exit 1

fi

###############################################################################
# ARCHITECTURE
###############################################################################

if find_architecture
then
    ok "x86_64 architecture found. ID=$ARCH_ID"
else
    error "x86_64 architecture not found."
    exit 1
fi

###############################################################################
# PTABLE
###############################################################################

if find_ptable
then
    ok "Kickstart default partition table found. ID=$PTABLE_ID"
else
    error "Kickstart default partition table not found."
    exit 1
fi

###############################################################################
# ARRAYS
###############################################################################

declare -A MEDIA_IDS
declare -A OS_IDS
declare -A TEMPLATE_IDS

###############################################################################
# MEDIA
###############################################################################

header "Creating Installation Media"

ensure_media \
    "CentOS 7 Remote" \
    "http://192.168.253.136/repo/centos/" \
    "Redhat"

ensure_media \
    "Rocky 8 Remote" \
    "http://192.168.253.136/repo/rocky8/" \
    "Redhat"

ensure_media \
    "Rocky 9.2 Remote" \
    "http://192.168.253.136/repo/rocky9.2/" \
    "Redhat"

ensure_media \
    "Rocky 9 Remote" \
    "http://192.168.253.136/repo/rocky9/" \
    "Redhat"

###############################################################################
# MEDIA VERIFICATION
###############################################################################

header "Installation Media Verification"

api_get "${API}/media?per_page=all"

if [ "$API_STATUS" = "200" ] &&
   is_json "$API_BODY"
then

    echo "$API_BODY" |
    jq -r '
        .results[]? |
        [.id, .name, .path] |
        @tsv
    '

else

    error "Installation media verification failed."
    record_failure "Installation Media Verification"

fi

###############################################################################
# OPERATING SYSTEMS
###############################################################################

header "Creating Operating Systems"

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

if [ "$API_STATUS" = "200" ] &&
   is_json "$API_BODY"
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
# TEMPLATE FILES
###############################################################################

generate_template_files

###############################################################################
# PXEGRUB2 KIND
###############################################################################

header "Finding PXEGrub2 Template Kind"

if find_template_kind
then

    ok "PXEGrub2 template kind found. ID=$TEMPLATE_KIND_ID"

else

    error "PXEGrub2 template kind not found."

    echo
    echo "Current template kinds returned by Foreman:"
    echo

    api_get "${API}/template_kinds?per_page=all"

    if is_json "$API_BODY"
    then
        echo "$API_BODY" |
        jq -r '
            .results[]? |
            "\(.id)\t\(.name)"
        '
    else
        echo "$API_BODY"
    fi

    echo
    error "Your Foreman installation does not currently expose PXEGrub2 as a template kind."
    error "PXEGrub2 templates cannot be created until the PXEGrub2 kind exists."

    record_failure "PXEGrub2 template kind"

    TEMPLATE_KIND_ID=""

fi

###############################################################################
# TEMPLATES
###############################################################################

header "Creating PXEGrub2 Templates"

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

    warn "Skipping PXEGrub2 template creation because kind is unavailable."

fi

###############################################################################
# ASSOCIATIONS
###############################################################################

header "Associating PXEGrub2 Templates"

if [ -n "$TEMPLATE_KIND_ID" ]
then

    ensure_os_template_association \
        "CentOSLinux7-RAID" \
        "PXEGrub2 CentOS UEFI RAID Kickstart"

    ensure_os_template_association \
        "CentOSLinux7-SingleDisk" \
        "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

    ensure_os_template_association \
        "RockyLinux8.10-RAID" \
        "PXEGrub2 Rocky8 UEFI RAID Kickstart"

    ensure_os_template_association \
        "RockyLinux8.10-SingleDisk" \
        "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

    ensure_os_template_association \
        "RockyLinux9.2-RAID" \
        "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

    ensure_os_template_association \
        "RockyLinux9.2-SingleDisk" \
        "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

    ensure_os_template_association \
        "RockyLinux9.8-RAID" \
        "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

    ensure_os_template_association \
        "RockyLinux9.8-SingleDisk" \
        "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

else

    warn "Skipping PXEGrub2 associations because kind is unavailable."

fi

###############################################################################
# DEFAULT TEMPLATES
###############################################################################

header "Setting PXEGrub2 Default Templates"

if [ -n "$TEMPLATE_KIND_ID" ]
then

    ensure_os_default \
        "CentOSLinux7-RAID" \
        "PXEGrub2 CentOS UEFI RAID Kickstart"

    ensure_os_default \
        "CentOSLinux7-SingleDisk" \
        "PXEGrub2 CentOS UEFI SingleDisk Kickstart"

    ensure_os_default \
        "RockyLinux8.10-RAID" \
        "PXEGrub2 Rocky8 UEFI RAID Kickstart"

    ensure_os_default \
        "RockyLinux8.10-SingleDisk" \
        "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"

    ensure_os_default \
        "RockyLinux9.2-RAID" \
        "PXEGrub2 Rocky9.2 UEFI RAID Kickstart"

    ensure_os_default \
        "RockyLinux9.2-SingleDisk" \
        "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

    ensure_os_default \
        "RockyLinux9.8-RAID" \
        "PXEGrub2 Rocky9.8 UEFI RAID Kickstart"

    ensure_os_default \
        "RockyLinux9.8-SingleDisk" \
        "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

else

    warn "Skipping PXEGrub2 defaults because kind is unavailable."

fi

###############################################################################
# SUBNETS
###############################################################################

header "Creating PXE Subnets"

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
# VERIFICATIONS
###############################################################################

verify_subnets

verify_templates

verify_os_mappings

if [ -n "$TEMPLATE_KIND_ID" ]
then
    verify_defaults
fi

final_os_verification

###############################################################################
# GENERATED FILES
###############################################################################

header "Generated PXE Template Files"

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
    echo -e "${RED}Failures:${RESET}"

    for FAILURE in "${FAILURES[@]}"
    do
        echo -e "${RED}[ERROR]${RESET} $FAILURE"
    done

fi

if [ "${#WARNINGS[@]}" -gt 0 ]
then

    echo
    echo -e "${YELLOW}Warnings:${RESET}"

    for WARNING in "${WARNINGS[@]}"
    do
        echo -e "${YELLOW}[WARN]${RESET} $WARNING"
    done

fi

###############################################################################
# AUTHENTICATION SUMMARY
###############################################################################

echo
echo -e "${CYAN}Authentication:${RESET}"
echo "------------------------------------------------------------"
echo "Method        : Foreman REST API"
echo "Username      : ${FOREMAN_USER}"
echo "Authentication: Personal Access Token"
echo "Hammer        : NOT USED"
echo "curl          : USED"
echo "API           : ${API}"
echo "------------------------------------------------------------"

echo
echo -e "${CYAN}Manual API Verification:${RESET}"
echo "------------------------------------------------------------"

echo
echo "Foreman status:"
echo
echo "curl -ksS --user \"${FOREMAN_USER}:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  ${API}/status"

echo
echo "PXEGrub2 template kinds:"
echo
echo "curl -ksS --user \"${FOREMAN_USER}:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/template_kinds?per_page=all' | jq"

echo
echo "PXEGrub2 templates:"
echo
echo "curl -ksS --user \"${FOREMAN_USER}:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/provisioning_templates?per_page=all' | jq"

echo
echo "Operating systems:"
echo
echo "curl -ksS --user \"${FOREMAN_USER}:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/operatingsystems?per_page=all' | jq"

echo
echo "Subnets:"
echo
echo "curl -ksS --user \"${FOREMAN_USER}:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/subnets?per_page=all' | jq"

echo
echo "PXEGrub2 defaults for OS ID 2:"
echo
echo "curl -ksS --user \"${FOREMAN_USER}:\$FOREMAN_TOKEN\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${API}/operatingsystems/2/os_default_templates' | jq"

echo

exit 0
