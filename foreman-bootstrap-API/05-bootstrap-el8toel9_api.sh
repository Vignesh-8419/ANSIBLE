#!/bin/bash
###############################################################################
# 05 - Foreman Katello Bootstrap - REST API
# EL8 -> EL9 Rocky Linux Migration Bootstrap
#
# Based on the working 04 EL7->EL8 REST API pattern:
#   - API paths are passed to api_request()
#   - api_request() writes JSON to BODY
#   - all jq reads use BODY
#   - existing resources are reused
#
# Supported targets:
#   TARGET_VERSION=9.2
#   TARGET_VERSION=9.8
#
# Run:
#   export FOREMAN_PASSWORD='...'
#   TARGET_VERSION=9.2 ./05-bootstrap-el8toel9_api.sh
#   TARGET_VERSION=9.8 ./05-bootstrap-el8toel9_api.sh
###############################################################################

set +e

FAILED_STEPS=()

record_failure() { FAILED_STEPS+=("$1"); }

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
skip()  { echo -e "${YELLOW}[SKIP]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

header() {
    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

subheader() {
    echo
    echo "------------------------------------------------------------"
    echo "$1"
    echo "------------------------------------------------------------"
}

###############################################################################
# Foreman configuration
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"
FOREMAN_USER="${FOREMAN_USER:-admin}"
API_VERSION="${API_VERSION:-2}"

ORG_NAME="Default Organization"
LOCATION_NAME="Default Location"

if [ -z "${FOREMAN_PASSWORD:-}" ]; then
    error "FOREMAN_PASSWORD is not set."
    echo "Example: export FOREMAN_PASSWORD='your-password'"
    exit 1
fi

TARGET_VERSION="${TARGET_VERSION:-9.8}"

case "${TARGET_VERSION}" in
    9.2)
        ROCKY_VERSION="9.2"
        TARGET_PRODUCT="Rocky Linux 9.2"
        CONTENT_VIEW="Rocky9.2-CV"
        ACTIVATION_KEY="rocky9.2-key"
        ELEVATE_REPO="Rocky-08-EL8toEL9-9.2"
        ELEVATE_URL="http://192.168.253.136/repo/leapp/9.2/el8toel9"
        ;;
    9.8)
        ROCKY_VERSION="9.8"
        TARGET_PRODUCT="Rocky Linux 9.8"
        CONTENT_VIEW="Rocky9.8-CV"
        ACTIVATION_KEY="rocky9.8-key"
        ELEVATE_REPO="Rocky-08-EL8toEL9-9.8"
        ELEVATE_URL="http://192.168.253.136/repo/leapp/9/el8toel9"
        ;;
    *)
        error "Unsupported TARGET_VERSION=${TARGET_VERSION}"
        echo "Supported versions: 9.2 9.8"
        exit 1
        ;;
esac

SOURCE_PRODUCT="Rocky Linux 8"

BASE_REPO="Rocky-08-BaseOS"
BASE_URL="http://192.168.253.136/repo/rocky8/BaseOS"

APPSTREAM_REPO="Rocky-08-AppStream"
APPSTREAM_URL="http://192.168.253.136/repo/rocky8/AppStream"

ORG_ID=""
LIBRARY_ID=""
SOURCE_PRODUCT_ID=""
TARGET_PRODUCT_ID=""

BASE_REPO_ID=""
APPSTREAM_REPO_ID=""
ELEVATE_REPO_ID=""

TARGET_REPO_IDS=()
TARGET_REPO_NAMES=()
TARGET_REPO_URLS=()

CONTENT_VIEW_ID=""
ACTIVATION_KEY_ID=""

BODY="$(mktemp)"
trap 'rm -f "${BODY}"' EXIT

###############################################################################
# API request - same pattern as working 04
###############################################################################

api_request() {
    local METHOD="$1"
    local API_PATH="$2"
    local PAYLOAD="${3:-}"

    HTTP_STATUS=""

    if [ -n "${PAYLOAD}" ]; then
        HTTP_STATUS="$(
            /bin/curl -ksS -g \
                --user "${FOREMAN_USER}:${FOREMAN_PASSWORD}" \
                -H "Accept: application/json" \
                -H "Content-Type: application/json" \
                -X "${METHOD}" \
                -d "${PAYLOAD}" \
                -o "${BODY}" \
                -w '%{http_code}' \
                "${FOREMAN_URL}${API_PATH}"
        )"
    else
        HTTP_STATUS="$(
            /bin/curl -ksS -g \
                --user "${FOREMAN_USER}:${FOREMAN_PASSWORD}" \
                -H "Accept: application/json" \
                -H "Content-Type: application/json" \
                -X "${METHOD}" \
                -o "${BODY}" \
                -w '%{http_code}' \
                "${FOREMAN_URL}${API_PATH}"
        )"
    fi

    return 0
}

api_success() {
    [[ "${HTTP_STATUS}" =~ ^2[0-9][0-9]$ ]]
}

show_api_error() {
    local METHOD="$1"
    local API_PATH="$2"

    error "API request failed."
    error "HTTP Status : ${HTTP_STATUS}"
    error "Method      : ${METHOD}"
    error "URL         : ${FOREMAN_URL}${API_PATH}"

    if [ -s "${BODY}" ]; then
        /bin/jq . "${BODY}" 2>/dev/null
    else
        error "Empty API response."
    fi
}

###############################################################################
# Dependencies / configuration
###############################################################################

check_dependencies() {
    header "Dependency Check"

    local COMMAND
    for COMMAND in curl jq head grep awk mktemp rm ls; do
        if command -v "${COMMAND}" >/dev/null 2>&1; then
            ok "${COMMAND} found: $(command -v "${COMMAND}")"
        else
            error "${COMMAND} not found."
            record_failure "Dependency ${COMMAND}"
        fi
    done

    [ "${#FAILED_STEPS[@]}" -eq 0 ]
}

print_configuration() {
    header "05 - Foreman Katello Bootstrap EL8 To EL9 - REST API"

    echo "Foreman URL    : ${FOREMAN_URL}"
    echo "API Version    : ${API_VERSION}"
    echo "Organization   : ${ORG_NAME}"
    echo "Location       : ${LOCATION_NAME}"
    echo
    echo "Target Version : ${ROCKY_VERSION}"
    echo "Source Product : ${SOURCE_PRODUCT}"
    echo "Target Product : ${TARGET_PRODUCT}"
    echo "BaseOS         : ${BASE_REPO}"
    echo "AppStream      : ${APPSTREAM_REPO}"
    echo "ELevate        : ${ELEVATE_REPO}"
    echo "Content View   : ${CONTENT_VIEW}"
    echo "Activation Key : ${ACTIVATION_KEY}"
}

###############################################################################
# Foreman resources
###############################################################################

test_foreman_api() {
    header "Foreman API Authentication Test"

    info "Testing Foreman REST API..."
    api_request GET "/api/status"

    if ! api_success; then
        show_api_error GET "/api/status"
        record_failure "Foreman API Authentication"
        return 1
    fi

    VERSION="$(/bin/jq -r '.version // empty' "${BODY}" 2>/dev/null)"
    STATUS="$(/bin/jq -r '.status // empty' "${BODY}" 2>/dev/null)"
    API="$(/bin/jq -r '.api_version // empty' "${BODY}" 2>/dev/null)"

    if [ -n "${VERSION}" ]; then
        ok "Foreman API authentication successful."
        echo "Foreman Version : ${VERSION}"
        echo "API Version     : ${API}"
        echo "API Status      : ${STATUS}"
        return 0
    fi

    error "Invalid Foreman API response."
    /bin/jq . "${BODY}" 2>/dev/null
    record_failure "Foreman API Authentication"
    return 1
}

resolve_organization() {
    info "Finding Organization : ${ORG_NAME}"

    api_request GET "/api/organizations?search=$(printf '%s' "${ORG_NAME}" | sed 's/ /%20/g')"

    if api_success; then
        ORG_ID="$(
            /bin/jq -r \
                --arg NAME "${ORG_NAME}" \
                '(.results // [])[] | select(.name == $NAME) | .id' \
                "${BODY}" 2>/dev/null | head -n 1
        )"
    fi

    if [ -z "${ORG_ID}" ]; then
        ORG_ID="1"
        info "Checking Organization ID : ${ORG_ID}"
        api_request GET "/api/organizations/${ORG_ID}"

        if ! api_success; then
            show_api_error GET "/api/organizations/${ORG_ID}"
            ORG_ID=""
            record_failure "Organization ${ORG_NAME}"
            return 1
        fi

        API_ORG_ID="$(/bin/jq -r '.id // empty' "${BODY}" 2>/dev/null)"
        API_ORG_NAME="$(/bin/jq -r '.name // empty' "${BODY}" 2>/dev/null)"

        if [ "${API_ORG_ID}" != "${ORG_ID}" ] || [ "${API_ORG_NAME}" != "${ORG_NAME}" ]; then
            error "Organization verification failed."
            ORG_ID=""
            record_failure "Organization ${ORG_NAME}"
            return 1
        fi
    fi

    ok "Organization found."
    echo "Organization ID   : ${ORG_ID}"
    echo "Organization Name : ${ORG_NAME}"
    return 0
}

resolve_library_environment() {
    info "Resolving Lifecycle Environment : Library"

    api_request GET "/katello/api/environments?organization_id=${ORG_ID}&per_page=all"

    if api_success; then
        LIBRARY_ID="$(
            /bin/jq -r '
                (.results // [])[] |
                select(.name == "Library" or .label == "Library") |
                .id
            ' "${BODY}" 2>/dev/null | head -n 1
        )"
    fi

    if [ -n "${LIBRARY_ID}" ]; then
        ok "Library lifecycle environment resolved."
        echo "Library Environment ID   : ${LIBRARY_ID}"
        echo "Library Environment Name : Library"
        return 0
    fi

    LIBRARY_ID="1"
    api_request GET "/katello/api/environments/${LIBRARY_ID}"
    CHECK_NAME="$(/bin/jq -r '.name // empty' "${BODY}" 2>/dev/null)"

    if [ "${CHECK_NAME}" = "Library" ]; then
        ok "Library lifecycle environment resolved."
        echo "Library Environment ID   : ${LIBRARY_ID}"
        echo "Library Environment Name : Library"
        return 0
    fi

    error "Library lifecycle environment not found."
    LIBRARY_ID=""
    record_failure "Library Environment"
    return 1
}

resolve_resources() {
    header "Resolving Foreman Resources"

    resolve_organization || return 1
    [ -n "${ORG_ID}" ] || return 1
    resolve_library_environment || return 1
}

###############################################################################
# Product lookup / creation
###############################################################################

get_product_id() {
    local PRODUCT_NAME="$1"

    info "Checking Product : ${PRODUCT_NAME}" >&2

    # IMPORTANT:
    # api_request expects an API PATH, not a complete URL.
    api_request GET \
        "/katello/api/organizations/${ORG_ID}/products?per_page=100&page=1"

    if ! api_success; then
        warn "Unable to query products." >&2
        show_api_error GET \
            "/katello/api/organizations/${ORG_ID}/products?per_page=100&page=1" >&2
        return 1
    fi

    /bin/jq -r \
        --arg NAME "${PRODUCT_NAME}" \
        '(.results // [])[] | select(.name == $NAME) | .id' \
        "${BODY}" 2>/dev/null |
    /usr/bin/head -n 1
}

ensure_source_product() {
    header "Source Product"

    SOURCE_PRODUCT_ID="$(get_product_id "${SOURCE_PRODUCT}")"

    if [ -n "${SOURCE_PRODUCT_ID}" ] && [ "${SOURCE_PRODUCT_ID}" != "null" ]; then
        skip "Source Product already exists. ID=${SOURCE_PRODUCT_ID}"
        return 0
    fi

    info "Creating Product : ${SOURCE_PRODUCT}"

    PAYLOAD="$(
        /bin/jq -n \
            --arg name "${SOURCE_PRODUCT}" \
            --argjson organization_id "${ORG_ID}" \
            '{name:$name, organization_id:$organization_id}'
    )"

    api_request POST "/katello/api/products" "${PAYLOAD}"

    if api_success; then
        SOURCE_PRODUCT_ID="$(/bin/jq -r '.id // .product.id // empty' "${BODY}" 2>/dev/null)"
    fi

    if [ -z "${SOURCE_PRODUCT_ID}" ]; then
        SOURCE_PRODUCT_ID="$(get_product_id "${SOURCE_PRODUCT}")"
    fi

    if [ -n "${SOURCE_PRODUCT_ID}" ]; then
        ok "Source Product available. ID=${SOURCE_PRODUCT_ID}"
        return 0
    fi

    show_api_error POST "/katello/api/products"
    record_failure "Source Product ${SOURCE_PRODUCT}"
    return 1
}

ensure_target_product() {
    header "Target Product"

    TARGET_PRODUCT_ID="$(get_product_id "${TARGET_PRODUCT}")"

    if [ -n "${TARGET_PRODUCT_ID}" ] && [ "${TARGET_PRODUCT_ID}" != "null" ]; then
        skip "Target Product already exists. ID=${TARGET_PRODUCT_ID}"
        return 0
    fi

    error "Target Product does not exist: ${TARGET_PRODUCT}"
    error "The script will NOT create a target product automatically."
    error "Create/sync ${TARGET_PRODUCT} in Katello first."
    record_failure "Target Product ${TARGET_PRODUCT}"
    return 1
}

###############################################################################
# Repository lookup
###############################################################################

get_repo_id() {
    local PRODUCT_ID_ARG="$1"
    local REPO_NAME="$2"

    api_request GET \
        "/katello/api/products/${PRODUCT_ID_ARG}/repositories?per_page=100&page=1"

    if ! api_success; then
        return 1
    fi

    /bin/jq -r \
        --arg NAME "${REPO_NAME}" \
        '(.results // [])[] | select(.name == $NAME) | .id' \
        "${BODY}" 2>/dev/null |
    /usr/bin/head -n 1
}

get_repo_detail_url() {
    local REPO_ID="$1"
    api_request GET "/katello/api/repositories/${REPO_ID}"
    api_success || return 1
    /bin/jq -r '.url // empty' "${BODY}" 2>/dev/null
}

ensure_repo() {
    local PRODUCT_ID_ARG="$1"
    local REPO_NAME="$2"
    local REPO_URL="$3"
    local REPO_ID

    subheader "Repository : ${REPO_NAME}" >&2

    REPO_ID="$(get_repo_id "${PRODUCT_ID_ARG}" "${REPO_NAME}")"

    if [ -n "${REPO_ID}" ] && [ "${REPO_ID}" != "null" ]; then
        skip "${REPO_NAME} already exists. ID=${REPO_ID}" >&2

        CURRENT_URL="$(get_repo_detail_url "${REPO_ID}")"
        if [ -n "${CURRENT_URL}" ] && [ "${CURRENT_URL}" != "${REPO_URL}" ]; then
            warn "${REPO_NAME} URL differs." >&2
            echo "Current URL  : ${CURRENT_URL}" >&2
            echo "Expected URL : ${REPO_URL}" >&2
            warn "Existing repository will NOT be recreated." >&2
        fi

        printf '%s\n' "${REPO_ID}"
        return 0
    fi

    info "Creating Repository : ${REPO_NAME}" >&2
    info "URL : ${REPO_URL}" >&2

    PAYLOAD="$(
        /bin/jq -n \
            --arg name "${REPO_NAME}" \
            --arg url "${REPO_URL}" \
            --argjson product_id "${PRODUCT_ID_ARG}" \
            '{
                name:$name,
                product_id:$product_id,
                url:$url,
                content_type:"yum"
            }'
    )"

    api_request POST "/katello/api/repositories" "${PAYLOAD}"

    if api_success; then
        REPO_ID="$(/bin/jq -r '.id // .repository.id // empty' "${BODY}" 2>/dev/null)"
    fi

    if [ -z "${REPO_ID}" ]; then
        REPO_ID="$(get_repo_id "${PRODUCT_ID_ARG}" "${REPO_NAME}")"
    fi

    if [ -n "${REPO_ID}" ]; then
        ok "${REPO_NAME} available. ID=${REPO_ID}" >&2
        printf '%s\n' "${REPO_ID}"
        return 0
    fi

    show_api_error POST "/katello/api/repositories" >&2
    record_failure "${REPO_NAME}"
    return 1
}

###############################################################################
# Source repositories
###############################################################################

resolve_source_repositories() {
    header "Resolving Source Repositories"

    BASE_REPO_ID="$(ensure_repo "${SOURCE_PRODUCT_ID}" "${BASE_REPO}" "${BASE_URL}")" || return 1
    APPSTREAM_REPO_ID="$(ensure_repo "${SOURCE_PRODUCT_ID}" "${APPSTREAM_REPO}" "${APPSTREAM_URL}")" || return 1
    ELEVATE_REPO_ID="$(ensure_repo "${SOURCE_PRODUCT_ID}" "${ELEVATE_REPO}" "${ELEVATE_URL}")" || return 1

    echo "BaseOS Repository ID    : ${BASE_REPO_ID}"
    echo "AppStream Repository ID : ${APPSTREAM_REPO_ID}"
    echo "ELevate Repository ID   : ${ELEVATE_REPO_ID}"
}

###############################################################################
# Target repositories
###############################################################################

resolve_target_repositories() {
    header "Resolving Target Product Repositories"

    TARGET_REPO_IDS=()
    TARGET_REPO_NAMES=()
    TARGET_REPO_URLS=()

    api_request GET \
        "/katello/api/products/${TARGET_PRODUCT_ID}/repositories?per_page=100&page=1"

    if ! api_success; then
        show_api_error GET \
            "/katello/api/products/${TARGET_PRODUCT_ID}/repositories?per_page=100&page=1"
        record_failure "Target Product repositories"
        return 1
    fi

    while IFS=$'\t' read -r ID NAME URL; do
        [ -n "${ID}" ] || continue
        TARGET_REPO_IDS+=("${ID}")
        TARGET_REPO_NAMES+=("${NAME}")
        TARGET_REPO_URLS+=("${URL}")
        ok "Target repository found: ${NAME} ID=${ID}"
    done < <(
        /bin/jq -r '
            (.results // [])[] |
            [.id, .name, (.url // "")] |
            @tsv
        ' "${BODY}" 2>/dev/null
    )

    if [ "${#TARGET_REPO_IDS[@]}" -eq 0 ]; then
        error "No repositories found under ${TARGET_PRODUCT}."
        record_failure "Target Product repositories"
        return 1
    fi

    echo "Target Repo IDs : ${TARGET_REPO_IDS[*]}"
}

###############################################################################
# Sync
###############################################################################

extract_task_id() {
    /bin/jq -r '
        .id //
        .task_id //
        .task.id //
        .task.uuid //
        empty
    ' "${BODY}" 2>/dev/null | head -n 1
}

resume_paused_tasks() {
    header "Recovering Paused Foreman Tasks"

    api_request GET \
        "/foreman_tasks/api/tasks?search=state%20%3D%20paused&per_page=100&page=1"

    if ! api_success; then
        warn "Unable to query paused Foreman tasks."
        return 0
    fi

    COUNT="$(/bin/jq -r '(.results // []) | length' "${BODY}" 2>/dev/null)"
    COUNT="${COUNT:-0}"

    if [ "${COUNT}" -eq 0 ]; then
        ok "No paused tasks found."
        return 0
    fi

    warn "Found ${COUNT} paused task(s)."

    while read -r TASK_ID; do
        [ -n "${TASK_ID}" ] || continue
        info "Attempting to resume task: ${TASK_ID}"

        api_request PUT \
            "/foreman_tasks/api/tasks/${TASK_ID}/resume" \
            '{}'

        if api_success; then
            ok "Task resumed: ${TASK_ID}"
        else
            warn "Unable to resume task: ${TASK_ID}"
        fi
    done < <(
        /bin/jq -r '(.results // [])[] | .id // empty' "${BODY}" 2>/dev/null
    )
}

repository_sync_status() {
    local REPO_ID="$1"

    api_request GET \
        "/katello/api/repositories/${REPO_ID}"

    if ! api_success; then
        return 1
    fi

    /bin/jq -r '
        if .last_sync then
            (.last_sync.result // .last_sync.state // "")
        else
            (.sync_state // "")
        end
    ' "${BODY}" 2>/dev/null
}

sync_repository() {
    local REPO_NAME="$1"
    local REPO_ID="$2"
    local STATE

    subheader "Repository Sync : ${REPO_NAME}"

    STATE="$(repository_sync_status "${REPO_ID}")"

    if [ "${STATE}" = "success" ] || [ "${STATE}" = "Syncing Complete." ]; then
        skip "${REPO_NAME} already has a successful sync."
        return 0
    fi

    info "Starting sync : ${REPO_NAME}"

    api_request POST \
        "/katello/api/repositories/${REPO_ID}/sync" \
        '{}'

    if api_success; then
        TASK_ID="$(extract_task_id)"
        if [ -n "${TASK_ID}" ]; then
            ok "${REPO_NAME} sync started. Task=${TASK_ID}"
        else
            ok "${REPO_NAME} sync request accepted."
        fi
        return 0
    fi

    if grep -qiE "already|running|syncing|task" "${BODY}" 2>/dev/null; then
        warn "${REPO_NAME} may already be syncing."
        return 0
    fi

    show_api_error POST "/katello/api/repositories/${REPO_ID}/sync"
    record_failure "${REPO_NAME} sync"
    return 1
}

sync_repositories() {
    header "Synchronizing Migration Repositories"

    sync_repository "${BASE_REPO}" "${BASE_REPO_ID}"
    sync_repository "${APPSTREAM_REPO}" "${APPSTREAM_REPO_ID}"
    sync_repository "${ELEVATE_REPO}" "${ELEVATE_REPO_ID}"

    local i
    for i in "${!TARGET_REPO_IDS[@]}"; do
        sync_repository \
            "${TARGET_REPO_NAMES[$i]}" \
            "${TARGET_REPO_IDS[$i]}"
    done
}

###############################################################################
# Content View
###############################################################################

get_content_view_id() {
    api_request GET \
        "/katello/api/organizations/${ORG_ID}/content_views?per_page=100&page=1"

    if ! api_success; then
        return 1
    fi

    /bin/jq -r \
        --arg NAME "${CONTENT_VIEW}" \
        '(.results // [])[] | select(.name == $NAME) | .id' \
        "${BODY}" 2>/dev/null |
    head -n 1
}

create_content_view() {
    header "Content View"

    CONTENT_VIEW_ID="$(get_content_view_id)"

    if [ -n "${CONTENT_VIEW_ID}" ]; then
        skip "Content View already exists. ID=${CONTENT_VIEW_ID}"
        return 0
    fi

    info "Creating Content View : ${CONTENT_VIEW}"

    PAYLOAD="$(
        /bin/jq -n \
            --arg name "${CONTENT_VIEW}" \
            --argjson organization_id "${ORG_ID}" \
            '{name:$name, organization_id:$organization_id}'
    )"

    api_request POST \
        "/katello/api/organizations/${ORG_ID}/content_views" \
        "${PAYLOAD}"

    if api_success; then
        CONTENT_VIEW_ID="$(/bin/jq -r '.id // empty' "${BODY}" 2>/dev/null)"
    fi

    if [ -z "${CONTENT_VIEW_ID}" ]; then
        CONTENT_VIEW_ID="$(get_content_view_id)"
    fi

    if [ -n "${CONTENT_VIEW_ID}" ]; then
        ok "Content View available. ID=${CONTENT_VIEW_ID}"
        return 0
    fi

    show_api_error POST \
        "/katello/api/organizations/${ORG_ID}/content_views"
    record_failure "${CONTENT_VIEW}"
    return 1
}

get_cv_repository_ids() {
    api_request GET "/katello/api/content_views/${CONTENT_VIEW_ID}"
    api_success || return 1
    /bin/jq -c '.repository_ids // []' "${BODY}" 2>/dev/null
}

add_repo_to_cv() {
    local REPO_NAME="$1"
    local REPO_ID="$2"
    local CURRENT_IDS
    local NEW_IDS

    [ -n "${REPO_ID}" ] || return 1

    CURRENT_IDS="$(get_cv_repository_ids)"
    [ -n "${CURRENT_IDS}" ] || CURRENT_IDS="[]"

    if /bin/jq -e \
        --argjson ID "${REPO_ID}" \
        'index($ID) != null' \
        <<< "${CURRENT_IDS}" >/dev/null 2>&1; then
        skip "${REPO_NAME} already assigned to ${CONTENT_VIEW}."
        return 0
    fi

    NEW_IDS="$(
        /bin/jq -c \
            --argjson ID "${REPO_ID}" \
            '. + [$ID] | unique' \
            <<< "${CURRENT_IDS}"
    )"

    info "Adding ${REPO_NAME} to ${CONTENT_VIEW}"

    PAYLOAD="$(
        /bin/jq -n \
            --argjson repository_ids "${NEW_IDS}" \
            '{repository_ids:$repository_ids}'
    )"

    api_request PUT \
        "/katello/api/content_views/${CONTENT_VIEW_ID}" \
        "${PAYLOAD}"

    if api_success; then
        ok "${REPO_NAME} added to ${CONTENT_VIEW}."
        return 0
    fi

    if grep -qiE "already|taken|exists" "${BODY}" 2>/dev/null; then
        skip "${REPO_NAME} already assigned."
        return 0
    fi

    show_api_error PUT "/katello/api/content_views/${CONTENT_VIEW_ID}"
    record_failure "${REPO_NAME} Content View"
    return 1
}

configure_content_view() {
    header "Configuring Content View"

    add_repo_to_cv "${BASE_REPO}" "${BASE_REPO_ID}"
    add_repo_to_cv "${APPSTREAM_REPO}" "${APPSTREAM_REPO_ID}"
    add_repo_to_cv "${ELEVATE_REPO}" "${ELEVATE_REPO_ID}"

    local i
    for i in "${!TARGET_REPO_IDS[@]}"; do
        add_repo_to_cv \
            "${TARGET_REPO_NAMES[$i]}" \
            "${TARGET_REPO_IDS[$i]}"
    done
}

verify_content_view() {
    header "Verifying Content View"

    local CURRENT_IDS
    local FAILED=0

    CURRENT_IDS="$(get_cv_repository_ids)"

    if [ -z "${CURRENT_IDS}" ]; then
        error "Unable to read Content View repository IDs."
        record_failure "Content View Verification"
        return 1
    fi

    echo "Content View Repository IDs : ${CURRENT_IDS}"

    check_cv_repo() {
        local NAME="$1"
        local ID="$2"

        if /bin/jq -e \
            --argjson ID "${ID}" \
            'index($ID) != null' \
            <<< "${CURRENT_IDS}" >/dev/null 2>&1; then
            ok "${NAME} attached (ID=${ID})"
        else
            error "${NAME} missing (ID=${ID})"
            FAILED=1
        fi
    }

    check_cv_repo "${BASE_REPO}" "${BASE_REPO_ID}"
    check_cv_repo "${APPSTREAM_REPO}" "${APPSTREAM_REPO_ID}"
    check_cv_repo "${ELEVATE_REPO}" "${ELEVATE_REPO_ID}"

    local i
    for i in "${!TARGET_REPO_IDS[@]}"; do
        check_cv_repo "${TARGET_REPO_NAMES[$i]}" "${TARGET_REPO_IDS[$i]}"
    done

    if [ "${FAILED}" -eq 1 ]; then
        record_failure "Content View Repository Verification"
        return 1
    fi

    ok "All required repositories verified."
    return 0
}

publish_content_view() {
    header "Publishing Content View"

    if ! verify_content_view; then
        error "Content View validation failed. Publish skipped."
        return 1
    fi

    api_request GET "/katello/api/content_views/${CONTENT_VIEW_ID}"

    if ! api_success; then
        show_api_error GET "/katello/api/content_views/${CONTENT_VIEW_ID}"
        record_failure "${CONTENT_VIEW} lookup"
        return 1
    fi

    NEEDS_PUBLISH="$(/bin/jq -r '.needs_publish // true' "${BODY}" 2>/dev/null)"
    LATEST_VERSION="$(/bin/jq -r '.latest_version // empty' "${BODY}" 2>/dev/null)"
    LAST_TASK="$(/bin/jq -r '.last_task.id // empty' "${BODY}" 2>/dev/null)"

    if [ "${NEEDS_PUBLISH}" = "false" ] && [ -n "${LATEST_VERSION}" ]; then
        skip "${CONTENT_VIEW} already published. Version=${LATEST_VERSION}"
        return 0
    fi

    if [ -n "${LAST_TASK}" ]; then
        warn "${CONTENT_VIEW} has an existing task: ${LAST_TASK}"
        skip "Publish not duplicated."
        return 0
    fi

    DESCRIPTION="EL8 To EL9 Rocky ${ROCKY_VERSION} $(date '+%F %T')"
    PAYLOAD="$(
        /bin/jq -n --arg description "${DESCRIPTION}" \
            '{description:$description}'
    )"

    info "Publishing ${CONTENT_VIEW}"

    api_request POST \
        "/katello/api/content_views/${CONTENT_VIEW_ID}/publish" \
        "${PAYLOAD}"

    if api_success; then
        TASK_ID="$(extract_task_id)"
        if [ -n "${TASK_ID}" ]; then
            ok "${CONTENT_VIEW} publish started. Task=${TASK_ID}"
        else
            ok "${CONTENT_VIEW} publish started."
        fi
        return 0
    fi

    if grep -qiE "lock.*taken|already running|Required lock" "${BODY}" 2>/dev/null; then
        warn "Content View publish lock detected."
        resume_paused_tasks
        sleep 5

        api_request POST \
            "/katello/api/content_views/${CONTENT_VIEW_ID}/publish" \
            "${PAYLOAD}"

        if api_success; then
            ok "${CONTENT_VIEW} publish retry accepted."
            return 0
        fi
    fi

    show_api_error POST "/katello/api/content_views/${CONTENT_VIEW_ID}/publish"
    record_failure "${CONTENT_VIEW} publish"
    return 1
}

###############################################################################
# Activation Key
###############################################################################

get_activation_key_id() {
    ACTIVATION_KEY_ID=""

    api_request GET \
        "/katello/api/organizations/${ORG_ID}/activation_keys?per_page=100&page=1"

    if ! api_success; then
        return 1
    fi

    ACTIVATION_KEY_ID="$(
        /bin/jq -r \
            --arg NAME "${ACTIVATION_KEY}" \
            '(.results // [])[] | select(.name == $NAME) | .id' \
            "${BODY}" 2>/dev/null |
        head -n 1
    )"

    [ -n "${ACTIVATION_KEY_ID}" ]
}

create_activation_key() {
    header "Activation Key"

    if get_activation_key_id; then
        skip "Activation Key already exists. ID=${ACTIVATION_KEY_ID}"
    else
        info "Creating Activation Key : ${ACTIVATION_KEY}"

        PAYLOAD="$(
            /bin/jq -n \
                --arg name "${ACTIVATION_KEY}" \
                --argjson organization_id "${ORG_ID}" \
                --argjson content_view_id "${CONTENT_VIEW_ID}" \
                --argjson environment_id "${LIBRARY_ID}" \
                '{
                    name:$name,
                    organization_id:$organization_id,
                    content_view_id:$content_view_id,
                    environment_id:$environment_id,
                    unlimited_hosts:true
                }'
        )"

        api_request POST "/katello/api/activation_keys" "${PAYLOAD}"

        if api_success; then
            ACTIVATION_KEY_ID="$(
                /bin/jq -r '.id // .activation_key.id // empty' "${BODY}" 2>/dev/null
            )"
        fi

        if [ -z "${ACTIVATION_KEY_ID}" ]; then
            get_activation_key_id
        fi

        if [ -z "${ACTIVATION_KEY_ID}" ]; then
            show_api_error POST "/katello/api/activation_keys"
            record_failure "${ACTIVATION_KEY}"
            return 1
        fi

        ok "Activation Key available. ID=${ACTIVATION_KEY_ID}"
    fi

    # Reuse existing key but correct its CV/environment mapping if needed.
    api_request GET "/katello/api/activation_keys/${ACTIVATION_KEY_ID}"

    if ! api_success; then
        show_api_error GET "/katello/api/activation_keys/${ACTIVATION_KEY_ID}"
        record_failure "${ACTIVATION_KEY} lookup"
        return 1
    fi

    CURRENT_CV_ID="$(/bin/jq -r '.content_view_id // empty' "${BODY}" 2>/dev/null)"
    CURRENT_ENV_ID="$(/bin/jq -r '.environment_id // empty' "${BODY}" 2>/dev/null)"

    if [ "${CURRENT_CV_ID}" = "${CONTENT_VIEW_ID}" ] &&
       [ "${CURRENT_ENV_ID}" = "${LIBRARY_ID}" ]; then
        skip "Activation Key already points to ${CONTENT_VIEW} / Library."
        return 0
    fi

    info "Updating Activation Key mapping."

    PAYLOAD="$(
        /bin/jq -n \
            --argjson organization_id "${ORG_ID}" \
            --argjson content_view_id "${CONTENT_VIEW_ID}" \
            --argjson environment_id "${LIBRARY_ID}" \
            '{
                organization_id:$organization_id,
                content_view_id:$content_view_id,
                environment_id:$environment_id
            }'
    )"

    api_request PUT \
        "/katello/api/activation_keys/${ACTIVATION_KEY_ID}" \
        "${PAYLOAD}"

    if api_success; then
        ok "Activation Key mapping updated."
        return 0
    fi

    show_api_error PUT "/katello/api/activation_keys/${ACTIVATION_KEY_ID}"
    record_failure "${ACTIVATION_KEY} mapping"
    return 1
}

get_content_label() {
    local REPO_ID="$1"

    api_request GET "/katello/api/repositories/${REPO_ID}"
    api_success || return 1

    /bin/jq -r '.content_label // empty' "${BODY}" 2>/dev/null
}

configure_activation_key() {
    header "Configuring Activation Key Content"

    local REPO_ID LABEL REPO_NAME
    local REPO_IDS=()
    local REPO_NAMES=()

    REPO_IDS+=("${BASE_REPO_ID}")
    REPO_NAMES+=("${BASE_REPO}")
    REPO_IDS+=("${APPSTREAM_REPO_ID}")
    REPO_NAMES+=("${APPSTREAM_REPO}")
    REPO_IDS+=("${ELEVATE_REPO_ID}")
    REPO_NAMES+=("${ELEVATE_REPO}")

    local i
    for i in "${!TARGET_REPO_IDS[@]}"; do
        REPO_IDS+=("${TARGET_REPO_IDS[$i]}")
        REPO_NAMES+=("${TARGET_REPO_NAMES[$i]}")
    done

    for i in "${!REPO_IDS[@]}"; do
        REPO_ID="${REPO_IDS[$i]}"
        REPO_NAME="${REPO_NAMES[$i]}"

        LABEL="$(get_content_label "${REPO_ID}")"

        if [ -z "${LABEL}" ]; then
            warn "Content label not found for ${REPO_NAME}; skipping override."
            continue
        fi

        # Build this payload without jq object-key parsing.
        # Some older jq builds used with this Foreman host reject
        # content_label in this object expression as a parser error.
        # The repository content label is generated by Foreman and is
        # therefore JSON-escaped below before constructing the payload.
        LABEL_JSON="$(printf '%s' "${LABEL}" | /bin/jq -Rsa .)" || {
            error "Unable to JSON-encode content label for ${REPO_NAME}."
            record_failure "${REPO_NAME} activation-key content"
            continue
        }

        PAYLOAD="$(printf '{"content_overrides":[{"content_label":%s,"value":"1"}]}' "${LABEL_JSON}")"

        api_request PUT \
            "/katello/api/activation_keys/${ACTIVATION_KEY_ID}/content_override" \
            "${PAYLOAD}"

        if api_success; then
            ok "${REPO_NAME} enabled on Activation Key."
        else
            show_api_error PUT \
                "/katello/api/activation_keys/${ACTIVATION_KEY_ID}/content_override"
            record_failure "${REPO_NAME} activation key"
        fi
    done
}

verify_activation_key() {
    header "Verifying Activation Key"

    api_request GET "/katello/api/activation_keys/${ACTIVATION_KEY_ID}"

    if ! api_success; then
        show_api_error GET "/katello/api/activation_keys/${ACTIVATION_KEY_ID}"
        record_failure "${ACTIVATION_KEY} verification"
        return 1
    fi

    CURRENT_CV_ID="$(/bin/jq -r '.content_view_id // empty' "${BODY}" 2>/dev/null)"
    CURRENT_ENV_ID="$(/bin/jq -r '.environment_id // empty' "${BODY}" 2>/dev/null)"

    /bin/jq '{
        id,
        name,
        organization_id,
        content_view_id,
        environment_id,
        unlimited_hosts,
        auto_attach
    }' "${BODY}" 2>/dev/null

    if [ "${CURRENT_CV_ID}" = "${CONTENT_VIEW_ID}" ] &&
       [ "${CURRENT_ENV_ID}" = "${LIBRARY_ID}" ]; then
        ok "Activation Key verification completed."
        return 0
    fi

    error "Activation Key mapping is incorrect."
    echo "Expected Content View ID : ${CONTENT_VIEW_ID}"
    echo "Actual Content View ID   : ${CURRENT_CV_ID}"
    echo "Expected Environment ID  : ${LIBRARY_ID}"
    echo "Actual Environment ID    : ${CURRENT_ENV_ID}"
    record_failure "${ACTIVATION_KEY} verification"
    return 1
}

###############################################################################
# Summary / commands
###############################################################################

generate_bootstrap_command() {
    header "Generating Rocky Linux 8 Bootstrap Command"

    cat <<EOF

Run this on the Rocky Linux 8 source server:

------------------------------------------------------------

rpm -Uvh http://192.168.253.136/pub/katello-ca-consumer-latest.noarch.rpm

subscription-manager register \\
  --org="${ORG_NAME}" \\
  --activationkey="${ACTIVATION_KEY}"

dnf clean all
dnf repolist

dnf install -y leapp-upgrade leapp-data-rocky

leapp preupgrade
leapp upgrade
reboot

------------------------------------------------------------

Target Version : Rocky Linux ${ROCKY_VERSION}
Content View   : ${CONTENT_VIEW}
Activation Key : ${ACTIVATION_KEY}

EOF
}

summary() {
    header "EL8 To EL9 Bootstrap Summary"

    echo "Source Product : ${SOURCE_PRODUCT} (ID=${SOURCE_PRODUCT_ID})"
    echo "Target Product : ${TARGET_PRODUCT} (ID=${TARGET_PRODUCT_ID})"
    echo "Content View   : ${CONTENT_VIEW} (ID=${CONTENT_VIEW_ID})"
    echo "Activation Key : ${ACTIVATION_KEY} (ID=${ACTIVATION_KEY_ID})"
    echo
    echo "Source Repositories:"
    echo "  ${BASE_REPO}       ID=${BASE_REPO_ID}"
    echo "  ${APPSTREAM_REPO}  ID=${APPSTREAM_REPO_ID}"
    echo "  ${ELEVATE_REPO}    ID=${ELEVATE_REPO_ID}"
    echo
    echo "Target Repositories:"
    local i
    for i in "${!TARGET_REPO_IDS[@]}"; do
        echo "  ${TARGET_REPO_NAMES[$i]}  ID=${TARGET_REPO_IDS[$i]}"
    done

    echo
    echo "Content View:"
    api_request GET "/katello/api/content_views/${CONTENT_VIEW_ID}"
    if api_success; then
        /bin/jq '{
            id,
            name,
            label,
            version_count,
            latest_version,
            latest_version_id,
            repository_ids,
            needs_publish
        }' "${BODY}" 2>/dev/null
    fi

    echo
    echo "Activation Key:"
    api_request GET "/katello/api/activation_keys/${ACTIVATION_KEY_ID}"
    if api_success; then
        /bin/jq '{
            id,
            name,
            organization_id,
            content_view_id,
            environment_id,
            unlimited_hosts,
            auto_attach
        }' "${BODY}" 2>/dev/null
    fi
}

manual_verification() {
    header "Manual Verification Commands"

    cat <<EOF

1. Foreman API:
curl -ksS \\
  --user "admin:\$FOREMAN_PASSWORD" \\
  -H 'Accept: application/json' \\
  "${FOREMAN_URL}/api/status" | jq

2. Products:
curl -ksS \\
  --user "admin:\$FOREMAN_PASSWORD" \\
  -H 'Accept: application/json' \\
  "${FOREMAN_URL}/katello/api/organizations/${ORG_ID}/products?per_page=100&page=1" |
jq -r '.results[] | [.id,.name,.label,.repository_count] | @tsv'

3. Rocky Linux 8 repositories:
curl -ksS \\
  --user "admin:\$FOREMAN_PASSWORD" \\
  -H 'Accept: application/json' \\
  "${FOREMAN_URL}/katello/api/products/${SOURCE_PRODUCT_ID}/repositories?per_page=100&page=1" |
jq -r '.results[] | [.id,.name,.url] | @tsv'

4. Target repositories:
curl -ksS \\
  --user "admin:\$FOREMAN_PASSWORD" \\
  -H 'Accept: application/json' \\
  "${FOREMAN_URL}/katello/api/products/${TARGET_PRODUCT_ID}/repositories?per_page=100&page=1" |
jq -r '.results[] | [.id,.name,.url] | @tsv'

5. Content View:
curl -ksS \\
  --user "admin:\$FOREMAN_PASSWORD" \\
  -H 'Accept: application/json' \\
  "${FOREMAN_URL}/katello/api/content_views/${CONTENT_VIEW_ID}" | jq

6. Activation Key:
curl -ksS \\
  --user "admin:\$FOREMAN_PASSWORD" \\
  -H 'Accept: application/json' \\
  "${FOREMAN_URL}/katello/api/activation_keys/${ACTIVATION_KEY_ID}" | jq

EOF
}

final_status() {
    header "05 - EL8 To EL9 Bootstrap Completed"

    if [ "${#FAILED_STEPS[@]}" -eq 0 ]; then
        ok "EL8 To EL9 Bootstrap completed successfully."
        return 0
    fi

    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."
    local ITEM
    for ITEM in "${FAILED_STEPS[@]}"; do
        error "${ITEM}"
    done
    return 1
}

###############################################################################
# MAIN
###############################################################################

check_dependencies || {
    final_status
    exit 1
}

print_configuration

test_foreman_api || {
    final_status
    exit 1
}

resolve_resources || {
    final_status
    exit 1
}

resume_paused_tasks

ensure_source_product || {
    final_status
    exit 1
}

ensure_target_product || {
    final_status
    exit 1
}

resolve_source_repositories || {
    final_status
    exit 1
}

resolve_target_repositories || {
    final_status
    exit 1
}

sync_repositories

create_content_view || {
    final_status
    exit 1
}

configure_content_view

if ! publish_content_view; then
    final_status
    exit 1
fi

create_activation_key || {
    final_status
    exit 1
}

configure_activation_key

verify_activation_key

generate_bootstrap_command
summary
manual_verification

final_status
EXIT_STATUS=$?

exit "${EXIT_STATUS}"
