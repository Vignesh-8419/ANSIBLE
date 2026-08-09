#!/bin/bash
###############################################################################
# 05 - Foreman Katello Bootstrap
# EL8 -> EL9 Upgrade Bootstrap
#
# REST API ONLY
#
# Supports:
#   - Rocky Linux 9.2
#   - Rocky Linux 9.8
#
# Foreman:
#   https://cent-07-01.vgs.com
#   Foreman 3.2.1
#
# IMPORTANT:
#   - NO Hammer CLI
#   - /api/status uses Accept: version=2,application/json
#   - /katello/api/* uses Accept: application/json
#   - Library is resolved from Content View API
#   - Content View publish uses force:true
###############################################################################

set +e

###############################################################################
# Failure Tracking
###############################################################################

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
# Logging Functions
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

###############################################################################
# Dependency Check
###############################################################################

header "Dependency Check"

REQUIRED_COMMANDS=(
    curl
    jq
    grep
    awk
    mktemp
    rm
    head
    sed
    date
)

DEPENDENCY_FAILED=0

for CMD in "${REQUIRED_COMMANDS[@]}"
do
    PATH_FOUND=$(command -v "${CMD}" 2>/dev/null)

    if [ -n "${PATH_FOUND}" ]
    then
        ok "${CMD} found: ${PATH_FOUND}"
    else
        error "${CMD} not found."
        DEPENDENCY_FAILED=1
    fi
done

if [ "${DEPENDENCY_FAILED}" -ne 0 ]
then
    error "Required dependencies are missing."
    exit 1
fi

###############################################################################
# Foreman Configuration
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"

FOREMAN_USER="${FOREMAN_USER:-admin}"

#
# Existing password behaviour retained.
# You can override it with:
#
# export FOREMAN_PASSWORD='password'
#
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"

ORG="${ORG:-Default Organization}"

LOCATION="${LOCATION:-Default Location}"

###############################################################################
# API Headers
###############################################################################

#
# Foreman 3.2.1:
#
# /api/status
#   Accept: version=2,application/json
#
# /katello/api/*
#   Accept: application/json
#
KATELLO_ACCEPT="Accept: application/json"
CONTENT_TYPE="Content-Type: application/json"

###############################################################################
# Target Version
###############################################################################

TARGET_VERSION="${TARGET_VERSION:-9.8}"

case "${TARGET_VERSION}" in

    9.2)

        ROCKY_VERSION="9.2"

        CONTENT_VIEW="Rocky9.2-CV"

        ACTIVATION_KEY="rocky9.2-key"

        ELEVATE_REPO_NAME="Rocky-08-EL8toEL9-9.2"

        ELEVATE_REPO_URL="http://192.168.253.136/repo/leapp/9.2/el8toel9"

        ;;

    9.8)

        ROCKY_VERSION="9.8"

        CONTENT_VIEW="Rocky9.8-CV"

        ACTIVATION_KEY="rocky9.8-key"

        ELEVATE_REPO_NAME="Rocky-08-EL8toEL9-9.8"

        ELEVATE_REPO_URL="http://192.168.253.136/repo/leapp/9/el8toel9"

        ;;

    *)

        error "Unsupported TARGET_VERSION=${TARGET_VERSION}"

        echo
        echo "Supported versions:"
        echo "  9.2"
        echo "  9.8"

        exit 1

        ;;

esac

###############################################################################
# Product / Repository Configuration
###############################################################################

PRODUCT="Rocky Linux 8"

BASE_REPO="Rocky-08-BaseOS"

APPSTREAM_REPO="Rocky-08-AppStream"

BASE_URL="http://192.168.253.136/repo/rocky8/BaseOS"

APPSTREAM_URL="http://192.168.253.136/repo/rocky8/AppStream"

###############################################################################
# Runtime IDs
###############################################################################

ORG_ID=""

PRODUCT_ID=""

BASE_REPO_ID=""

APPSTREAM_REPO_ID=""

ELEVATE_REPO_ID=""

CONTENT_VIEW_ID=""

LIBRARY_ENVIRONMENT_ID=""

LIBRARY_ENVIRONMENT_NAME="Library"

ACTIVATION_KEY_ID=""

###############################################################################
# Temporary Files
###############################################################################

TMP_DIR=$(mktemp -d /tmp/foreman-el8toel9-api.XXXXXX)

cleanup()
{
    rm -rf "${TMP_DIR}" >/dev/null 2>&1
}

trap cleanup EXIT

###############################################################################
# Display Configuration
###############################################################################

header "05 - Foreman Katello Bootstrap EL8 To EL9 - REST API"

echo "Foreman URL    : ${FOREMAN_URL}"
echo "API Version    : 2"
echo "Organization   : ${ORG}"
echo "Location       : ${LOCATION}"
echo
echo "Target Version : ${ROCKY_VERSION}"
echo "Product        : ${PRODUCT}"
echo "BaseOS         : ${BASE_REPO}"
echo "AppStream      : ${APPSTREAM_REPO}"
echo "ELevate        : ${ELEVATE_REPO_NAME}"
echo "Content View   : ${CONTENT_VIEW}"
echo "Activation Key : ${ACTIVATION_KEY}"

###############################################################################
# Generic Katello API Request
###############################################################################
#
# Usage:
#
# katello_api METHOD URL [JSON_DATA]
#
# Result:
#
# API_HTTP_STATUS
# API_RESPONSE
#
###############################################################################

katello_api()
{
    METHOD="$1"
    URL="$2"
    DATA="${3:-}"

    RESPONSE_FILE="${TMP_DIR}/api_response"
    HEADER_FILE="${TMP_DIR}/api_headers"
    STATUS_FILE="${TMP_DIR}/http_status"

    rm -f \
        "${RESPONSE_FILE}" \
        "${HEADER_FILE}" \
        "${STATUS_FILE}"

    if [ -n "${DATA}" ]
    then

        curl -ksS \
            --user "${FOREMAN_USER}:${FOREMAN_PASSWORD}" \
            -X "${METHOD}" \
            -H "${KATELLO_ACCEPT}" \
            -H "${CONTENT_TYPE}" \
            -d "${DATA}" \
            -D "${HEADER_FILE}" \
            -o "${RESPONSE_FILE}" \
            -w '%{http_code}' \
            "${URL}" \
            > "${STATUS_FILE}"

    else

        curl -ksS \
            --user "${FOREMAN_USER}:${FOREMAN_PASSWORD}" \
            -X "${METHOD}" \
            -H "${KATELLO_ACCEPT}" \
            -D "${HEADER_FILE}" \
            -o "${RESPONSE_FILE}" \
            -w '%{http_code}' \
            "${URL}" \
            > "${STATUS_FILE}"

    fi

    RC=$?

    API_HTTP_STATUS=$(cat "${STATUS_FILE}" 2>/dev/null)

    API_RESPONSE=$(cat "${RESPONSE_FILE}" 2>/dev/null)

    if [ ${RC} -ne 0 ]
    then
        error "curl failed."
        return 1
    fi

    if [ "${API_HTTP_STATUS}" -ge 200 ] 2>/dev/null &&
       [ "${API_HTTP_STATUS}" -lt 300 ] 2>/dev/null
    then
        return 0
    fi

    error "API request failed."
    error "HTTP Status : ${API_HTTP_STATUS}"
    error "Method      : ${METHOD}"
    error "URL         : ${URL}"

    if [ -n "${API_RESPONSE}" ]
    then
        echo "${API_RESPONSE}" |
            jq . 2>/dev/null ||
            echo "${API_RESPONSE}"
    fi

    return 1
}

###############################################################################
# Foreman API Authentication Test
###############################################################################

test_api()
{
    header "Foreman API Authentication Test"

    info "Testing Foreman REST API..."

    RESPONSE=$(
        curl -ksS \
            --user "${FOREMAN_USER}:${FOREMAN_PASSWORD}" \
            -H "Accept: version=2,application/json" \
            "${FOREMAN_URL}/api/status" \
            2>/dev/null
    )

    if echo "${RESPONSE}" |
        jq -e '.status == 200' >/dev/null 2>&1
    then

        ok "Foreman API authentication successful."

        echo "Foreman Version : $(echo "${RESPONSE}" | jq -r '.version')"
        echo "API Version     : $(echo "${RESPONSE}" | jq -r '.api_version')"
        echo "API Status      : $(echo "${RESPONSE}" | jq -r '.status')"

        return 0
    fi

    error "Foreman API authentication failed."

    echo "${RESPONSE}" |
        jq . 2>/dev/null ||
        echo "${RESPONSE}"

    record_failure "Foreman API Authentication"

    return 1
}

###############################################################################
# Resolve Organization
###############################################################################

resolve_organization()
{
    header "Resolving Foreman Resources"

    info "Finding Organization : ${ORG}"

    URL="${FOREMAN_URL}/katello/api/organizations?per_page=100"

    if ! katello_api GET "${URL}"
    then
        record_failure "Organization"
        return 1
    fi

    ORGANIZATION_JSON="${API_RESPONSE}"

    ORG_ID=$(
        echo "${ORGANIZATION_JSON}" |
        jq -r --arg NAME "${ORG}" '
            .results[]
            | select(.name == $NAME)
            | .id
        ' |
        head -1
    )

    if [ -z "${ORG_ID}" ] ||
       [ "${ORG_ID}" = "null" ]
    then

        error "Organization not found : ${ORG}"

        echo "${ORGANIZATION_JSON}" |
            jq -r '.results[] | "\(.id) : \(.name)"' 2>/dev/null

        record_failure "Organization ${ORG}"

        return 1
    fi

    ok "Organization found."

    echo "Organization ID   : ${ORG_ID}"
    echo "Organization Name : ${ORG}"
}

###############################################################################
# Resolve Library From Content Views
###############################################################################
#
# Do NOT use:
#
#   /katello/api/environments
#
# Foreman 3.2.1 returns 406 for that endpoint in this environment.
#
###############################################################################

resolve_library_environment()
{
    info "Resolving Lifecycle Environment : Library"

    info "Reading Content Views to resolve Library environment..."

    URL="${FOREMAN_URL}/katello/api/content_views?organization_id=${ORG_ID}&per_page=100"

    if ! katello_api GET "${URL}"
    then
        error "Unable to read Content Views."
        record_failure "Content Views for Library Environment"
        return 1
    fi

    CV_LIST_JSON="${API_RESPONSE}"

    LIBRARY_ENVIRONMENT_ID=$(
        echo "${CV_LIST_JSON}" |
        jq -r '
            [
                .results[]?.environments[]?
                | select(
                    (.name == "Library")
                    or
                    (.label == "Library")
                )
                | .id
            ]
            | unique
            | .[0]
        '
    )

    LIBRARY_ENVIRONMENT_NAME=$(
        echo "${CV_LIST_JSON}" |
        jq -r '
            [
                .results[]?.environments[]?
                | select(
                    (.name == "Library")
                    or
                    (.label == "Library")
                )
                | .name
            ]
            | unique
            | .[0]
        '
    )

    if [ -z "${LIBRARY_ENVIRONMENT_ID}" ] ||
       [ "${LIBRARY_ENVIRONMENT_ID}" = "null" ]
    then

        error "Library lifecycle environment could not be resolved."

        echo
        echo "Available lifecycle environments:"
        echo "${CV_LIST_JSON}" |
            jq -r '
                [
                    .results[]?.environments[]?
                    | "\(.id) : \(.name)"
                ]
                | unique[]
            ' 2>/dev/null

        record_failure "Library Environment"

        return 1
    fi

    ok "Library lifecycle environment resolved."

    echo "Library Environment ID   : ${LIBRARY_ENVIRONMENT_ID}"
    echo "Library Environment Name : ${LIBRARY_ENVIRONMENT_NAME}"
}

###############################################################################
# Create Product
###############################################################################

create_product()
{
    header "Checking Product"

    info "Product : ${PRODUCT}"

    URL="${FOREMAN_URL}/katello/api/organizations/${ORG_ID}/products?per_page=100"

    if ! katello_api GET "${URL}"
    then
        record_failure "Product lookup"
        return 1
    fi

    PRODUCT_JSON="${API_RESPONSE}"

    PRODUCT_ID=$(
        echo "${PRODUCT_JSON}" |
        jq -r --arg NAME "${PRODUCT}" '
            (.results // [])[]
            | select(.name == $NAME)
            | .id
        ' |
        head -1
    )

    if [ -n "${PRODUCT_ID}" ] &&
       [ "${PRODUCT_ID}" != "null" ]
    then

        skip "Product ${PRODUCT} already exists. ID=${PRODUCT_ID}"

        return 0
    fi

    info "Creating Product : ${PRODUCT}"

    DATA=$(
        jq -n \
            --arg name "${PRODUCT}" \
            --argjson organization_id "${ORG_ID}" '
            {
                name: $name,
                organization_id: $organization_id
            }
            '
    )

    URL="${FOREMAN_URL}/katello/api/products"

    if ! katello_api POST "${URL}" "${DATA}"
    then

        record_failure "Product ${PRODUCT}"

        return 1
    fi

    PRODUCT_ID=$(echo "${API_RESPONSE}" | jq -r '.id')

    if [ -z "${PRODUCT_ID}" ] ||
       [ "${PRODUCT_ID}" = "null" ]
    then

        error "Product creation returned no ID."

        record_failure "Product ${PRODUCT}"

        return 1
    fi

    ok "Product created. ID=${PRODUCT_ID}"
}

###############################################################################
# Get Repository
###############################################################################

get_repository()
{
    REPO_NAME="$1"

    URL="${FOREMAN_URL}/katello/api/products/${PRODUCT_ID}/repositories?per_page=100"

    if ! katello_api GET "${URL}"
    then
        return 1
    fi

    echo "${API_RESPONSE}" |
        jq -r --arg NAME "${REPO_NAME}" '
            .results[]
            | select(.name == $NAME)
            | .id
        ' |
        head -1
}

###############################################################################
# Create Repository
###############################################################################

create_repository()
{
    REPO_NAME="$1"
    REPO_URL="$2"

    info "Checking Repository : ${REPO_NAME}"

    REPO_ID="$(get_repository "${REPO_NAME}")"

    if [ -n "${REPO_ID}" ] &&
       [ "${REPO_ID}" != "null" ]
    then

        skip "${REPO_NAME} already exists. ID=${REPO_ID}"

        case "${REPO_NAME}" in
            "${BASE_REPO}")
                BASE_REPO_ID="${REPO_ID}"
                ;;
            "${APPSTREAM_REPO}")
                APPSTREAM_REPO_ID="${REPO_ID}"
                ;;
            "${ELEVATE_REPO_NAME}")
                ELEVATE_REPO_ID="${REPO_ID}"
                ;;
        esac

        return 0
    fi

    info "Creating Repository : ${REPO_NAME}"

    DATA=$(
        jq -n \
            --arg name "${REPO_NAME}" \
            --arg url "${REPO_URL}" \
            --argjson product_id "${PRODUCT_ID}" \
            --argjson organization_id "${ORG_ID}" '
            {
                name: $name,
                url: $url,
                product_id: $product_id,
                organization_id: $organization_id,
                content_type: "yum"
            }
            '
    )

    URL="${FOREMAN_URL}/katello/api/repositories"

    if ! katello_api POST "${URL}" "${DATA}"
    then

        record_failure "${REPO_NAME}"

        return 1
    fi

    NEW_ID=$(echo "${API_RESPONSE}" | jq -r '.id')

    if [ -z "${NEW_ID}" ] ||
       [ "${NEW_ID}" = "null" ]
    then

        error "Repository creation returned no ID."

        record_failure "${REPO_NAME}"

        return 1
    fi

    ok "${REPO_NAME} created. ID=${NEW_ID}"

    case "${REPO_NAME}" in
        "${BASE_REPO}")
            BASE_REPO_ID="${NEW_ID}"
            ;;
        "${APPSTREAM_REPO}")
            APPSTREAM_REPO_ID="${NEW_ID}"
            ;;
        "${ELEVATE_REPO_NAME}")
            ELEVATE_REPO_ID="${NEW_ID}"
            ;;
    esac
}

###############################################################################
# Update Repository URL
###############################################################################

update_repository_url()
{
    REPO_NAME="$1"
    REPO_ID="$2"
    REPO_URL="$3"

    info "Checking Repository URL : ${REPO_NAME}"

    URL="${FOREMAN_URL}/katello/api/repositories/${REPO_ID}"

    if ! katello_api GET "${URL}"
    then
        record_failure "${REPO_NAME} lookup"
        return 1
    fi

    CURRENT_URL=$(
        echo "${API_RESPONSE}" |
        jq -r '.url // empty'
    )

    if [ "${CURRENT_URL}" = "${REPO_URL}" ]
    then

        skip "${REPO_NAME} URL already correct."

        return 0
    fi

    info "Updating Repository URL : ${REPO_NAME}"

    DATA=$(
        jq -n \
            --arg url "${REPO_URL}" '
            {
                url: $url
            }
            '
    )

    if ! katello_api PUT "${URL}" "${DATA}"
    then
        record_failure "${REPO_NAME} URL"
        return 1
    fi

    ok "${REPO_NAME} URL updated."
}

###############################################################################
# Create All Repositories
###############################################################################

create_repositories()
{
    header "[1/6] Creating Rocky Linux 8 Repositories"

    create_repository \
        "${BASE_REPO}" \
        "${BASE_URL}"

    create_repository \
        "${APPSTREAM_REPO}" \
        "${APPSTREAM_URL}"

    create_repository \
        "${ELEVATE_REPO_NAME}" \
        "${ELEVATE_REPO_URL}"

    header "Updating Repository URLs"

    if [ -n "${BASE_REPO_ID}" ]
    then
        update_repository_url \
            "${BASE_REPO}" \
            "${BASE_REPO_ID}" \
            "${BASE_URL}"
    fi

    if [ -n "${APPSTREAM_REPO_ID}" ]
    then
        update_repository_url \
            "${APPSTREAM_REPO}" \
            "${APPSTREAM_REPO_ID}" \
            "${APPSTREAM_URL}"
    fi

    if [ -n "${ELEVATE_REPO_ID}" ]
    then
        update_repository_url \
            "${ELEVATE_REPO_NAME}" \
            "${ELEVATE_REPO_ID}" \
            "${ELEVATE_REPO_URL}"
    fi
}

###############################################################################
# Extract Task ID
###############################################################################

extract_task_id()
{
    JSON="$1"

    echo "${JSON}" |
        jq -r '
            .id
            // .task_id
            // .task_group_id
            // .task_group.id
            // .task.id
            // empty
        ' |
        head -1
}

###############################################################################
# Monitor Foreman Task
###############################################################################

monitor_task()
{
    TASK_ID="$1"
    TASK_NAME="$2"

    if [ -z "${TASK_ID}" ] ||
       [ "${TASK_ID}" = "null" ]
    then
        warn "No task ID returned for ${TASK_NAME}."
        return 0
    fi

    info "Monitoring Foreman task..."
    echo "Task ID : ${TASK_ID}"

    MAX_LOOPS=180
    LOOP=0

    while [ ${LOOP} -lt ${MAX_LOOPS} ]
    do

        URL="${FOREMAN_URL}/foreman_tasks/api/tasks/${TASK_ID}"

        if ! katello_api GET "${URL}"
        then

            warn "Unable to query task ${TASK_ID}."

            sleep 5

            LOOP=$((LOOP + 1))

            continue
        fi

        TASK_JSON="${API_RESPONSE}"

        STATE=$(
            echo "${TASK_JSON}" |
            jq -r '.state // .status // "unknown"'
        )

        RESULT=$(
            echo "${TASK_JSON}" |
            jq -r '.result // "unknown"'
        )

        PROGRESS=$(
            echo "${TASK_JSON}" |
            jq -r '
                .progress
                // .percentage
                // .progress_percent
                // 0
            '
        )

        printf '\r[SYNC] %-30s Progress: %6s%% State: %-12s Result: %-10s' \
            "${TASK_NAME}" \
            "${PROGRESS}" \
            "${STATE}" \
            "${RESULT}"

        if [ "${RESULT}" = "success" ]
        then

            echo

            ok "${TASK_NAME} completed successfully."

            return 0
        fi

        if [ "${RESULT}" = "error" ] ||
           [ "${RESULT}" = "failure" ] ||
           {
               [ "${STATE}" = "stopped" ] &&
               [ "${RESULT}" != "success" ] &&
               [ "${RESULT}" != "unknown" ];
           }
        then

            echo

            error "${TASK_NAME} task failed."

            echo "${TASK_JSON}" |
                jq . 2>/dev/null

            return 1
        fi

        sleep 5

        LOOP=$((LOOP + 1))

    done

    echo

    warn "${TASK_NAME} task monitoring timed out."

    return 1
}

###############################################################################
# Synchronize Repository
###############################################################################

sync_repository()
{
    REPO_NAME="$1"
    REPO_ID="$2"

    if [ -z "${REPO_ID}" ]
    then

        error "Repository ID missing for ${REPO_NAME}."

        record_failure "Sync ${REPO_NAME}"

        return 1
    fi

    echo
    echo "------------------------------------------------------------"
    echo "Repository Sync : ${REPO_NAME}"
    echo "------------------------------------------------------------"

    info "Repository ID : ${REPO_ID}"

    URL="${FOREMAN_URL}/katello/api/repositories/${REPO_ID}"

    if ! katello_api GET "${URL}"
    then

        record_failure "Sync status ${REPO_NAME}"

        return 1
    fi

    REPO_JSON="${API_RESPONSE}"

    SYNC_STATE=$(
        echo "${REPO_JSON}" |
        jq -r '
            .sync_state
            // .sync_state_label
            // .last_sync.result
            // empty
        '
    )

    LAST_RESULT=$(
        echo "${REPO_JSON}" |
        jq -r '
            .last_sync.result
            // empty
        '
    )

    if echo "${SYNC_STATE}" |
        grep -Eqi 'complete|success|synced'
    then

        skip "${REPO_NAME} already synchronized."

        return 0
    fi

    if [ "${LAST_RESULT}" = "success" ]
    then

        skip "${REPO_NAME} last synchronization was successful."

        return 0
    fi

    info "Starting synchronization : ${REPO_NAME}"

    SYNC_DATA='{"skip_metadata_check":true}'

    URL="${FOREMAN_URL}/katello/api/repositories/${REPO_ID}/sync"

    if ! katello_api POST "${URL}" "${SYNC_DATA}"
    then

        if echo "${API_RESPONSE}" |
            grep -qiE 'lock|already running'
        then

            warn "Repository lock detected."

            sleep 10

            info "Retrying synchronization..."

            if ! katello_api POST "${URL}" "${SYNC_DATA}"
            then

                error "Retry failed."

                record_failure "Sync ${REPO_NAME}"

                return 1
            fi

        else

            error "Repository synchronization failed."

            record_failure "Sync ${REPO_NAME}"

            return 1
        fi
    fi

    TASK_ID=$(extract_task_id "${API_RESPONSE}")

    if [ -n "${TASK_ID}" ]
    then

        ok "${REPO_NAME} synchronization started."

        echo "Task : ${TASK_ID}"

        if ! monitor_task \
            "${TASK_ID}" \
            "${REPO_NAME}"
        then

            record_failure "Sync ${REPO_NAME}"

            return 1
        fi

    else

        ok "${REPO_NAME} synchronization request accepted."

        sleep 5
    fi
}

###############################################################################
# Synchronize All Repositories
###############################################################################

sync_repositories()
{
    header "[2/6] Synchronizing Rocky Linux 8 Repositories"

    sync_repository \
        "${BASE_REPO}" \
        "${BASE_REPO_ID}"

    sync_repository \
        "${APPSTREAM_REPO}" \
        "${APPSTREAM_REPO_ID}"

    sync_repository \
        "${ELEVATE_REPO_NAME}" \
        "${ELEVATE_REPO_ID}"
}

###############################################################################
# Resolve Content View
###############################################################################

resolve_content_view()
{
    info "Checking Content View : ${CONTENT_VIEW}"

    URL="${FOREMAN_URL}/katello/api/content_views?organization_id=${ORG_ID}&per_page=100"

    if ! katello_api GET "${URL}"
    then
        record_failure "Content View lookup"
        return 1
    fi

    CONTENT_VIEW_LIST_JSON="${API_RESPONSE}"

    CONTENT_VIEW_ID=$(
        echo "${CONTENT_VIEW_LIST_JSON}" |
        jq -r \
            --arg NAME "${CONTENT_VIEW}" '
            .results[]
            | select(.name == $NAME)
            | .id
            ' |
        head -1
    )

    if [ -n "${CONTENT_VIEW_ID}" ] &&
       [ "${CONTENT_VIEW_ID}" != "null" ]
    then

        skip "Content View ${CONTENT_VIEW} already exists. ID=${CONTENT_VIEW_ID}"

        return 0
    fi

    return 1
}

###############################################################################
# Create Content View
###############################################################################

create_content_view()
{
    header "[3/6] Creating Content View"

    if resolve_content_view
    then
        return 0
    fi

    info "Creating Content View : ${CONTENT_VIEW}"

    DATA=$(
        jq -n \
            --arg name "${CONTENT_VIEW}" \
            --argjson organization_id "${ORG_ID}" '
            {
                name: $name,
                organization_id: $organization_id,
                composite: false,
                auto_publish: false,
                solve_dependencies: false,
                import_only: false
            }
            '
    )

    URL="${FOREMAN_URL}/katello/api/content_views"

    if ! katello_api POST "${URL}" "${DATA}"
    then

        record_failure "${CONTENT_VIEW}"

        return 1
    fi

    CONTENT_VIEW_ID=$(echo "${API_RESPONSE}" | jq -r '.id')

    if [ -z "${CONTENT_VIEW_ID}" ] ||
       [ "${CONTENT_VIEW_ID}" = "null" ]
    then

        error "Content View creation returned no ID."

        record_failure "${CONTENT_VIEW}"

        return 1
    fi

    ok "Content View created. ID=${CONTENT_VIEW_ID}"
}

###############################################################################
# Get Content View
###############################################################################

get_content_view()
{
    URL="${FOREMAN_URL}/katello/api/content_views/${CONTENT_VIEW_ID}"

    katello_api GET "${URL}"
}

###############################################################################
# Configure Content View Repositories
###############################################################################

configure_content_view()
{
    header "Configuring Content View Repositories"

    if ! get_content_view
    then
        record_failure "Content View read"
        return 1
    fi

    CURRENT_REPOSITORIES=$(
        echo "${API_RESPONSE}" |
        jq -c '.repository_ids // []'
    )

    DESIRED_REPOSITORIES=$(
        jq -n \
            --argjson base "${BASE_REPO_ID}" \
            --argjson appstream "${APPSTREAM_REPO_ID}" \
            --argjson elevate "${ELEVATE_REPO_ID}" '
            [
                $base,
                $appstream,
                $elevate
            ]
            | unique
            '
    )

    echo
    echo "Current Repository IDs : ${CURRENT_REPOSITORIES}"
    echo "Desired Repository IDs : ${DESIRED_REPOSITORIES}"

    if [ "${CURRENT_REPOSITORIES}" = "${DESIRED_REPOSITORIES}" ]
    then

        skip "All required repositories already assigned."

    else

        info "Updating Content View repository assignments..."

        DATA=$(
            jq -n \
                --argjson repository_ids "${DESIRED_REPOSITORIES}" '
                {
                    repository_ids: $repository_ids
                }
                '
        )

        URL="${FOREMAN_URL}/katello/api/content_views/${CONTENT_VIEW_ID}"

        if ! katello_api PUT "${URL}" "${DATA}"
        then

            record_failure "Content View repository configuration"

            return 1
        fi

        ok "Content View repository configuration updated."
    fi

    verify_content_view
}

###############################################################################
# Verify Content View Repository Mapping
###############################################################################

verify_content_view()
{
    if ! get_content_view
    then
        record_failure "Content View verification"
        return 1
    fi

    CV_REPOSITORIES=$(
        echo "${API_RESPONSE}" |
        jq -c '.repository_ids // []'
    )

    FAILED=0

    if jq -e \
        --argjson ID "${BASE_REPO_ID}" \
        'index($ID) != null' \
        <<< "${CV_REPOSITORIES}" \
        >/dev/null 2>&1
    then
        ok "${BASE_REPO} attached to ${CONTENT_VIEW}."
    else
        error "${BASE_REPO} missing from ${CONTENT_VIEW}."
        FAILED=1
    fi

    if jq -e \
        --argjson ID "${APPSTREAM_REPO_ID}" \
        'index($ID) != null' \
        <<< "${CV_REPOSITORIES}" \
        >/dev/null 2>&1
    then
        ok "${APPSTREAM_REPO} attached to ${CONTENT_VIEW}."
    else
        error "${APPSTREAM_REPO} missing from ${CONTENT_VIEW}."
        FAILED=1
    fi

    if jq -e \
        --argjson ID "${ELEVATE_REPO_ID}" \
        'index($ID) != null' \
        <<< "${CV_REPOSITORIES}" \
        >/dev/null 2>&1
    then
        ok "${ELEVATE_REPO_NAME} attached to ${CONTENT_VIEW}."
    else
        error "${ELEVATE_REPO_NAME} missing from ${CONTENT_VIEW}."
        FAILED=1
    fi

    if [ "${FAILED}" -ne 0 ]
    then

        error "Content View repository verification failed."

        record_failure "Content View Repository Verification"

        return 1
    fi

    ok "All required repositories verified."

    return 0
}

###############################################################################
# Publish Content View
###############################################################################
#
# IMPORTANT:
#
# Your Foreman 3.2.1 returned:
#
#   Cannot promote environment out of sequence.
#   Use force to bypass restriction.
#
# Therefore force:true is intentionally used below.
#
###############################################################################

publish_content_view()
{
    header "[4/6] Publishing Content View"

    if ! verify_content_view
    then
        error "Publishing skipped because repository mapping failed."
        return 1
    fi

    info "Publishing ${CONTENT_VIEW}"

    DATA=$(
        jq -n \
            --arg description \
                "EL8 to EL9 Migration Rocky ${ROCKY_VERSION} $(date '+%F %T')" \
            --argjson environment_ids \
                "[${LIBRARY_ENVIRONMENT_ID}]" '
            {
                description: $description,
                environment_ids: $environment_ids,
                force: true
            }
            '
    )

    URL="${FOREMAN_URL}/katello/api/content_views/${CONTENT_VIEW_ID}/publish"

    if ! katello_api POST "${URL}" "${DATA}"
    then

        if echo "${API_RESPONSE}" |
            grep -qiE 'Required lock is already taken|lock'
        then

            warn "Content View publish lock detected."

            sleep 10

            info "Retrying Content View publish..."

            if ! katello_api POST "${URL}" "${DATA}"
            then

                error "Content View publish retry failed."

                record_failure "${CONTENT_VIEW} publish"

                return 1
            fi

        else

            error "Content View publish failed."

            record_failure "${CONTENT_VIEW} publish"

            return 1
        fi
    fi

    TASK_ID=$(extract_task_id "${API_RESPONSE}")

    if [ -n "${TASK_ID}" ]
    then

        ok "${CONTENT_VIEW} publish started."

        echo "Task : ${TASK_ID}"

        if ! monitor_task \
            "${TASK_ID}" \
            "${CONTENT_VIEW} publish"
        then

            record_failure "${CONTENT_VIEW} publish"

            return 1
        fi

    else

        ok "${CONTENT_VIEW} publish request accepted."
    fi
}

###############################################################################
# Get Repository Content Label
###############################################################################

get_repository_content_label()
{
    REPO_ID="$1"

    URL="${FOREMAN_URL}/katello/api/repositories/${REPO_ID}"

    if ! katello_api GET "${URL}"
    then
        return 1
    fi

    echo "${API_RESPONSE}" |
        jq -r '.content_label // empty'
}

###############################################################################
# Create Activation Key
###############################################################################

create_activation_key()
{
    header "[5/6] Creating Activation Key"

    info "Checking Activation Key : ${ACTIVATION_KEY}"

    URL="${FOREMAN_URL}/katello/api/organizations/${ORG_ID}/activation_keys?per_page=100"

    if ! katello_api GET "${URL}"
    then
        record_failure "Activation Key lookup"
        return 1
    fi

    ACTIVATION_KEY_ID=$(
        echo "${API_RESPONSE}" |
        jq -r \
            --arg NAME "${ACTIVATION_KEY}" '
            .results[]
            | select(.name == $NAME)
            | .id
            ' |
        head -1
    )

    if [ -n "${ACTIVATION_KEY_ID}" ] &&
       [ "${ACTIVATION_KEY_ID}" != "null" ]
    then

        skip "Activation Key ${ACTIVATION_KEY} already exists. ID=${ACTIVATION_KEY_ID}"

        info "Updating Activation Key Content View"

        DATA=$(
            jq -n \
                --argjson content_view_id "${CONTENT_VIEW_ID}" \
                --argjson environment_id "${LIBRARY_ENVIRONMENT_ID}" '
                {
                    content_view_id: $content_view_id,
                    environment_id: $environment_id
                }
                '
        )

        URL="${FOREMAN_URL}/katello/api/activation_keys/${ACTIVATION_KEY_ID}"

        if katello_api PUT "${URL}" "${DATA}"
        then
            ok "Activation Key updated."
            return 0
        fi

        record_failure "${ACTIVATION_KEY} update"

        return 1
    fi

    info "Creating Activation Key"

    DATA=$(
        jq -n \
            --arg name "${ACTIVATION_KEY}" \
            --argjson organization_id "${ORG_ID}" \
            --argjson content_view_id "${CONTENT_VIEW_ID}" \
            --argjson environment_id "${LIBRARY_ENVIRONMENT_ID}" '
            {
                name: $name,
                organization_id: $organization_id,
                content_view_id: $content_view_id,
                environment_id: $environment_id,
                unlimited_hosts: true
            }
            '
    )

    URL="${FOREMAN_URL}/katello/api/activation_keys"

    if ! katello_api POST "${URL}" "${DATA}"
    then

        record_failure "${ACTIVATION_KEY}"

        return 1
    fi

    ACTIVATION_KEY_ID=$(echo "${API_RESPONSE}" | jq -r '.id')

    if [ -z "${ACTIVATION_KEY_ID}" ] ||
       [ "${ACTIVATION_KEY_ID}" = "null" ]
    then

        error "Activation Key creation returned no ID."

        record_failure "${ACTIVATION_KEY}"

        return 1
    fi

    ok "Activation Key created. ID=${ACTIVATION_KEY_ID}"
}

###############################################################################
# Configure Activation Key
###############################################################################

configure_activation_key()
{
    header "Configuring Activation Key Repositories"

    for REPO_ID in \
        "${BASE_REPO_ID}" \
        "${APPSTREAM_REPO_ID}" \
        "${ELEVATE_REPO_ID}"
    do

        if [ -z "${REPO_ID}" ]
        then
            continue
        fi

        LABEL="$(get_repository_content_label "${REPO_ID}")"

        if [ -z "${LABEL}" ]
        then

            warn "Content label not found for repository ID ${REPO_ID}"

            record_failure \
                "Repository ${REPO_ID} content label"

            continue
        fi

        info "Enabling Repository"
        echo "Repository ID : ${REPO_ID}"
        echo "Content Label  : ${LABEL}"

        DATA=$(
            jq -n \
                --arg label "${LABEL}" '
                {
                    content_override: [
                        {
                            content_label: $label,
                            value: "1"
                        }
                    ]
                }
                '
        )

        URL="${FOREMAN_URL}/katello/api/activation_keys/${ACTIVATION_KEY_ID}/content_override"

        if katello_api PUT "${URL}" "${DATA}"
        then
            ok "Repository ${REPO_ID} enabled."
        else

            #
            # Some Katello versions use the plural endpoint.
            #
            URL="${FOREMAN_URL}/katello/api/activation_keys/${ACTIVATION_KEY_ID}/content_overrides"

            DATA=$(
                jq -n \
                    --arg label "${LABEL}" '
                    {
                        content_label: $label,
                        value: "1"
                    }
                    '
            )

            if katello_api POST "${URL}" "${DATA}"
            then
                ok "Repository ${REPO_ID} enabled."
            else

                warn "Unable to enable repository ${REPO_ID}."

                record_failure \
                    "Repository ${REPO_ID} activation key"
            fi
        fi
    done
}

###############################################################################
# Verify Activation Key
###############################################################################

verify_activation_key()
{
    header "Verifying Activation Key"

    if [ -z "${ACTIVATION_KEY_ID}" ]
    then

        error "Activation Key ID is empty."

        record_failure "Activation Key verification"

        return 1
    fi

    URL="${FOREMAN_URL}/katello/api/activation_keys/${ACTIVATION_KEY_ID}"

    if ! katello_api GET "${URL}"
    then

        record_failure "Activation Key verification"

        return 1
    fi

    AK_NAME=$(echo "${API_RESPONSE}" | jq -r '.name // empty')

    AK_CV_ID=$(echo "${API_RESPONSE}" | jq -r '.content_view_id // empty')

    AK_ENV_ID=$(echo "${API_RESPONSE}" | jq -r '.environment_id // empty')

    echo
    echo "Activation Key"
    echo "------------------------------------------------------------"
    echo "ID               : ${ACTIVATION_KEY_ID}"
    echo "Name             : ${AK_NAME}"
    echo "Content View ID  : ${AK_CV_ID}"
    echo "Environment ID   : ${AK_ENV_ID}"
    echo

    if [ "${AK_NAME}" != "${ACTIVATION_KEY}" ]
    then

        error "Activation Key name mismatch."

        record_failure "Activation Key name"

        return 1
    fi

    if [ "${AK_CV_ID}" != "${CONTENT_VIEW_ID}" ]
    then

        error "Activation Key Content View mismatch."

        echo "Expected : ${CONTENT_VIEW_ID}"
        echo "Actual   : ${AK_CV_ID}"

        record_failure "Activation Key Content View"

        return 1
    fi

    if [ "${AK_ENV_ID}" != "${LIBRARY_ENVIRONMENT_ID}" ]
    then

        error "Activation Key Lifecycle Environment mismatch."

        echo "Expected : ${LIBRARY_ENVIRONMENT_ID}"
        echo "Actual   : ${AK_ENV_ID}"

        record_failure "Activation Key Environment"

        return 1
    fi

    ok "Activation Key verification successful."

    return 0
}

###############################################################################
# Generate Bootstrap Command
###############################################################################

generate_bootstrap_command()
{
    header "Generating Rocky Linux 8 Bootstrap Command"

    echo
    echo "Run on Rocky Linux 8 source server"
    echo
    echo "------------------------------------------------------------"
    echo

    echo "subscription-manager register \\"
    echo "  --org=\"${ORG}\" \\"
    echo "  --activationkey=\"${ACTIVATION_KEY}\""

    echo
    echo "------------------------------------------------------------"
    echo

    echo "After registration:"
    echo
    echo "dnf clean all"
    echo "dnf repolist"

    echo
    echo "Install ELevate packages:"
    echo
    echo "dnf install -y leapp-upgrade leapp-data-rocky"

    echo
    echo "Run upgrade checks:"
    echo
    echo "leapp preupgrade"

    echo
    echo "Execute migration:"
    echo
    echo "leapp upgrade"

    echo
    echo "Reboot:"
    echo
    echo "reboot"
}

###############################################################################
# Content View Summary
###############################################################################

content_view_summary()
{
    header "Content View Summary"

    if [ -z "${CONTENT_VIEW_ID}" ]
    then
        error "Content View ID is empty."
        return 1
    fi

    URL="${FOREMAN_URL}/katello/api/content_views/${CONTENT_VIEW_ID}"

    if ! katello_api GET "${URL}"
    then
        return 1
    fi

    echo
    echo "Content View"
    echo "------------------------------------------------------------"

    echo "${API_RESPONSE}" |
        jq '{
            id,
            name,
            label,
            organization_id,
            repository_ids,
            latest_version,
            latest_version_id,
            version_count,
            latest_version_environments,
            environments,
            last_published
        }' 2>/dev/null
}

###############################################################################
# Activation Key Summary
###############################################################################

activation_key_summary()
{
    header "Activation Key Summary"

    if [ -z "${ACTIVATION_KEY_ID}" ]
    then
        error "Activation Key ID is empty."
        return 1
    fi

    URL="${FOREMAN_URL}/katello/api/activation_keys/${ACTIVATION_KEY_ID}"

    if ! katello_api GET "${URL}"
    then
        return 1
    fi

    echo
    echo "Activation Key"
    echo "------------------------------------------------------------"

    echo "${API_RESPONSE}" |
        jq '{
            id,
            name,
            organization_id,
            content_view_id,
            environment_id,
            unlimited_hosts,
            auto_attach
        }' 2>/dev/null
}

###############################################################################
# Final Summary
###############################################################################

summary()
{
    header "EL8 To EL9 Bootstrap Summary"

    echo

    echo "## Product"
    echo "------------------------------------------------------------"
    echo "Name : ${PRODUCT}"
    echo "ID   : ${PRODUCT_ID}"

    echo

    echo "## Repositories"
    echo "------------------------------------------------------------"

    echo
    echo "BaseOS"
    echo "Name : ${BASE_REPO}"
    echo "ID   : ${BASE_REPO_ID}"
    echo "URL  : ${BASE_URL}"

    echo
    echo "AppStream"
    echo "Name : ${APPSTREAM_REPO}"
    echo "ID   : ${APPSTREAM_REPO_ID}"
    echo "URL  : ${APPSTREAM_URL}"

    echo
    echo "ELevate"
    echo "Name : ${ELEVATE_REPO_NAME}"
    echo "ID   : ${ELEVATE_REPO_ID}"
    echo "URL  : ${ELEVATE_REPO_URL}"

    echo

    echo "## Content View"
    echo "------------------------------------------------------------"
    echo "Name          : ${CONTENT_VIEW}"
    echo "ID            : ${CONTENT_VIEW_ID}"
    echo "Environment   : ${LIBRARY_ENVIRONMENT_NAME}"
    echo "Environment ID: ${LIBRARY_ENVIRONMENT_ID}"

    echo

    echo "## Activation Key"
    echo "------------------------------------------------------------"
    echo "Name : ${ACTIVATION_KEY}"
    echo "ID   : ${ACTIVATION_KEY_ID}"

    echo

    echo "## Migration Configuration"
    echo "------------------------------------------------------------"
    echo "Target Version : ${ROCKY_VERSION}"
    echo "Product        : ${PRODUCT}"
    echo "Content View   : ${CONTENT_VIEW}"
    echo "Activation Key : ${ACTIVATION_KEY}"
}

###############################################################################
# Main Execution
###############################################################################

header "05 - Foreman Katello Bootstrap EL8 To EL9"

###############################################################################
# API Test
###############################################################################

if ! test_api
then
    summary
    exit 1
fi

###############################################################################
# Organization
###############################################################################

if ! resolve_organization
then
    summary
    exit 1
fi

###############################################################################
# Library Environment
###############################################################################

if ! resolve_library_environment
then
    summary
    exit 1
fi

###############################################################################
# Product
###############################################################################

if ! create_product
then
    summary
    exit 1
fi

###############################################################################
# Repositories
###############################################################################

create_repositories

if [ -z "${BASE_REPO_ID}" ] ||
   [ -z "${APPSTREAM_REPO_ID}" ] ||
   [ -z "${ELEVATE_REPO_ID}" ]
then

    error "One or more repository IDs are missing."

    summary

    exit 1
fi

###############################################################################
# Synchronization
###############################################################################

sync_repositories

###############################################################################
# Content View
###############################################################################

if ! create_content_view
then
    summary
    exit 1
fi

###############################################################################
# Configure Content View
###############################################################################

if ! configure_content_view
then
    summary
    exit 1
fi

###############################################################################
# Publish Content View
###############################################################################

if ! publish_content_view
then
    summary
    exit 1
fi

###############################################################################
# Activation Key
###############################################################################

if ! create_activation_key
then
    summary
    exit 1
fi

###############################################################################
# Configure Activation Key
###############################################################################

configure_activation_key

###############################################################################
# Verify Activation Key
###############################################################################

if ! verify_activation_key
then
    summary
    exit 1
fi

###############################################################################
# Output Commands / Summaries
###############################################################################

generate_bootstrap_command

content_view_summary

activation_key_summary

summary

###############################################################################
# Final Status
###############################################################################

if [ ${#FAILED_STEPS[@]} -gt 0 ]
then

    echo
    error "Failed steps: ${#FAILED_STEPS[@]}"

    for STEP in "${FAILED_STEPS[@]}"
    do
        error "${STEP}"
    done

    exit 1
fi

echo
ok "EL8 To EL9 Bootstrap completed successfully."

exit 0
