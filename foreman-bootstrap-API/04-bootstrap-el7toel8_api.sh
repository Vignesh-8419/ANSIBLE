#!/bin/bash
###############################################################################
# 04 - Foreman Katello Bootstrap - REST API
# EL7 -> EL8 Upgrade Bootstrap
#
# Name:
#   04-bootstrap-el7toel8_api.sh
#
# Purpose:
#   - Create CentOS 7 migration product
#   - Create BaseOS / Updates / ELevate repositories
#   - Sync repositories
#   - Create Content View
#   - Add repositories to Content View
#   - Publish Content View
#   - Create / Update Activation Key
#   - Generate bootstrap command
#
# REST API ONLY
# Hammer CLI is NOT required.
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
    echo "------------------------------------------------------------"
    echo "$1"
    echo "------------------------------------------------------------"
}

###############################################################################
# Foreman API Configuration
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"

FOREMAN_USER="${FOREMAN_USER:-admin}"

if [ -z "${FOREMAN_PASSWORD:-}" ]
then
    error "FOREMAN_PASSWORD is not set."
    echo
    echo "Example:"
    echo "export FOREMAN_PASSWORD='your-password'"
    exit 1
fi

API_VERSION="${API_VERSION:-2}"

ORG_NAME="Default Organization"
LOCATION_NAME="Default Location"

###############################################################################
# EL7 Migration Configuration
###############################################################################

PRODUCT_NAME="CentOS 7"

CONTENT_VIEW="EL7toEL8-CV"

ACTIVATION_KEY="el7toel8-key"

###############################################################################
# Repository Configuration
###############################################################################

BASE_REPO="CentOS-07-BaseOS"
BASE_URL="http://192.168.253.136/repo/centos"

UPDATE_REPO="CentOS-07-Updates"
UPDATE_URL="http://192.168.253.136/repo/installed_rhel7"

ELEVATE_REPO="CentOS-07-ELevate"
ELEVATE_URL="http://192.168.253.136/repo/elevate"

###############################################################################
# Temporary Response File
###############################################################################

BODY="$(mktemp)"

trap 'rm -f "${BODY}"' EXIT

###############################################################################
# API Request
###############################################################################

api_request()
{
    local METHOD="$1"
    local API_PATH="$2"
    local PAYLOAD="${3:-}"

    if [ ! -x /bin/curl ]
    then
        error "curl executable not found: /bin/curl"
        HTTP_STATUS=""
        return 1
    fi

    if [ -n "${PAYLOAD}" ]
    then

        HTTP_STATUS="$(
            /bin/curl -ksS \
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
            /bin/curl -ksS \
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
###############################################################################
# API Success Check
###############################################################################

api_success()
{
    [[ "${HTTP_STATUS}" =~ ^2[0-9][0-9]$ ]]
}

###############################################################################
# API Error Display
###############################################################################

show_api_error()
{
    local METHOD="$1"
    local PATH="$2"

    error "API request failed."
    error "HTTP Status : ${HTTP_STATUS}"
    error "Method      : ${METHOD}"
    error "URL         : ${FOREMAN_URL}${PATH}"

    if [ -s "${BODY}" ]
    then
        jq . "${BODY}" 2>/dev/null || /bin/cat "${BODY}"
    fi
}

###############################################################################
# Dependency Check
###############################################################################

check_dependencies()
{
    header "Dependency Check"

    local COMMAND

    for COMMAND in \
        curl \
        jq \
        cat \
        head \
        grep \
        awk \
        mkdir \
        rm \
        mktemp \
        ls
    do

        if command -v "${COMMAND}" >/dev/null 2>&1
        then
            ok "${COMMAND} found: $(command -v "${COMMAND}")"
        else
            error "${COMMAND} not found."
            record_failure "Dependency ${COMMAND}"
        fi

    done
}

###############################################################################
# Configuration Display
###############################################################################

print_configuration()
{
    header "04 - Foreman Katello Bootstrap EL7 To EL8 - REST API"

    echo "Foreman URL    : ${FOREMAN_URL}"
    echo "API Version    : ${API_VERSION}"
    echo "Organization   : ${ORG_NAME}"
    echo "Location       : ${LOCATION_NAME}"
    echo
    echo "Product        : ${PRODUCT_NAME}"
    echo "Content View   : ${CONTENT_VIEW}"
    echo "Activation Key : ${ACTIVATION_KEY}"
}

###############################################################################
# Foreman API Authentication Test
###############################################################################

test_foreman_api()
{
    header "Foreman API Authentication Test"

    info "Testing Foreman REST API..."

    api_request \
        GET \
        "/api/status"

    if ! api_success
    then
        show_api_error GET "/api/status"
        record_failure "Foreman API Authentication"
        return 1
    fi

    local VERSION
    local STATUS
    local API

    VERSION="$(jq -r '.version // empty' "${BODY}" 2>/dev/null)"
    STATUS="$(jq -r '.status // empty' "${BODY}" 2>/dev/null)"
    API="$(jq -r '.api_version // empty' "${BODY}" 2>/dev/null)"

    if [ -n "${VERSION}" ]
    then
        ok "Foreman API authentication successful."
        echo "Foreman Version : ${VERSION}"
        echo "API Version     : ${API}"
        echo "API Status      : ${STATUS}"
    else
        error "Invalid Foreman API response."
        jq . "${BODY}" 2>/dev/null
        record_failure "Foreman API Authentication"
        return 1
    fi
}

###############################################################################
# Resolve Organization
###############################################################################

resolve_organization()
{
    header "Resolving Foreman Resources"

    info "Finding Organization : ${ORG_NAME}"

    # The organization list endpoint on this Foreman installation
    # reports total=1 but returns an empty results array.
    # Therefore use the known organization ID directly and verify it.

    ORG_ID="1"

    info "Checking Organization ID : ${ORG_ID}"

    api_request \
        GET \
        "/api/organizations/${ORG_ID}"

    if ! api_success
    then
        show_api_error \
            GET \
            "/api/organizations/${ORG_ID}"

        ORG_ID=""
        record_failure "Organization ${ORG_NAME}"
        return 1
    fi

    API_ORG_ID="$(
        jq -r '.id // empty' "${BODY}" 2>/dev/null
    )"

    API_ORG_NAME="$(
        jq -r '.name // empty' "${BODY}" 2>/dev/null
    )"

    if [ "${API_ORG_ID}" = "${ORG_ID}" ] &&
       [ "${API_ORG_NAME}" = "${ORG_NAME}" ]
    then
        ok "Organization found."
        echo "Organization ID   : ${API_ORG_ID}"
        echo "Organization Name : ${API_ORG_NAME}"
        return 0
    fi

    error "Organization verification failed."
    error "Expected ID   : ${ORG_ID}"
    error "Expected Name : ${ORG_NAME}"
    error "Returned ID   : ${API_ORG_ID}"
    error "Returned Name : ${API_ORG_NAME}"

    ORG_ID=""
    record_failure "Organization ${ORG_NAME}"
    return 1
}

###############################################################################
# Resolve Library Environment
###############################################################################

resolve_library_environment()
{
    info "Finding Lifecycle Environment : Library"

    api_request \
        GET \
        "/katello/api/environments?organization_id=${ORG_ID}"

    if ! api_success
    then
        show_api_error \
            GET \
            "/katello/api/environments?organization_id=${ORG_ID}"

        record_failure "Library Environment"
        return 1
    fi

    LIBRARY_ID="$(
        jq -r '
            .results[]
            | select(
                .name == "Library" or
                .label == "Library"
            )
            | .id
        ' \
        "${BODY}" 2>/dev/null |
        head -n 1
    )"

    if [ -n "${LIBRARY_ID}" ]
    then
        ok "Library Environment found. ID=${LIBRARY_ID}"
        return 0
    fi

    error "Library lifecycle environment not found."

    echo
    echo "API Response:"
    jq . "${BODY}" 2>/dev/null

    record_failure "Library Environment"
    return 1
}

###############################################################################
# Get Product ID
###############################################################################

get_product_id()
{
    api_request \
        GET \
        "/katello/api/organizations/${ORG_ID}/products"

    if ! api_success
    then
        return 1
    fi

    jq -r \
        --arg NAME "${PRODUCT_NAME}" \
        '
        .results[]
        | select(.name == $NAME)
        | .id
        ' \
        "${BODY}" 2>/dev/null |
    head -n 1
}

###############################################################################
# Get Repository ID
###############################################################################

get_repo_id()
{
    local REPO_NAME="$1"

    api_request \
        GET \
        "/katello/api/products/${PRODUCT_ID}/repositories"

    if ! api_success
    then
        return 1
    fi

    jq -r \
        --arg NAME "${REPO_NAME}" \
        '
        .results[]
        | select(.name == $NAME)
        | .id
        ' \
        "${BODY}" 2>/dev/null |
    head -n 1
}

###############################################################################
# Get Content View ID
###############################################################################

get_content_view_id()
{
    api_request \
        GET \
        "/katello/api/organizations/${ORG_ID}/content_views"

    if ! api_success
    then
        return 1
    fi

    jq -r \
        --arg NAME "${CONTENT_VIEW}" \
        '
        .results[]
        | select(.name == $NAME)
        | .id
        ' \
        "${BODY}" 2>/dev/null |
    head -n 1
}

###############################################################################
# Get Activation Key ID
###############################################################################

get_activation_key_id()
{
    api_request \
        GET \
        "/katello/api/organizations/${ORG_ID}/activation_keys"

    if ! api_success
    then
        return 1
    fi

    jq -r \
        --arg NAME "${ACTIVATION_KEY}" \
        '
        .results[]
        | select(.name == $NAME)
        | .id
        ' \
        "${BODY}" 2>/dev/null |
    head -n 1
}
###############################################################################
# Resolve All Resources
###############################################################################

resolve_resources()
{
    resolve_organization

    if [ -z "${ORG_ID}" ]
    then
        return 1
    fi

    resolve_library_environment
}

###############################################################################
# Create Product
###############################################################################

create_product()
{
    header "Creating Product"

    PRODUCT_ID="$(get_product_id)"

    if [ -n "${PRODUCT_ID}" ]
    then
        skip "Product ${PRODUCT_NAME} already exists. ID=${PRODUCT_ID}"
        return 0
    fi

    info "Creating Product : ${PRODUCT_NAME}"

    PAYLOAD="$(
        jq -n \
            --arg name "${PRODUCT_NAME}" \
            --argjson organization_id "${ORG_ID}" \
            '
            {
                name: $name,
                organization_id: $organization_id
            }
            '
    )"

    api_request \
        POST \
        "/katello/api/products" \
        "${PAYLOAD}"

    if api_success
    then

        PRODUCT_ID="$(jq -r '.id // empty' "${BODY}")"

        if [ -n "${PRODUCT_ID}" ]
        then
            ok "Product created. ID=${PRODUCT_ID}"
        else
            PRODUCT_ID="$(get_product_id)"
            ok "Product created. ID=${PRODUCT_ID}"
        fi

    else

        if jq -e '
            (
                .errors.name // []
            )[] |
            test("already"; "i")
        ' "${BODY}" >/dev/null 2>&1
        then
            PRODUCT_ID="$(get_product_id)"
            skip "Product ${PRODUCT_NAME} already exists. ID=${PRODUCT_ID}"
            return 0
        fi

        show_api_error \
            POST \
            "/katello/api/products"

        record_failure "Product ${PRODUCT_NAME}"
        return 1
    fi
}

###############################################################################
# Create Repository
###############################################################################

create_repo()
{
    local REPO_NAME="$1"
    local REPO_URL="$2"

    subheader "Repository : ${REPO_NAME}"

    REPO_ID="$(get_repo_id "${REPO_NAME}")"

    if [ -n "${REPO_ID}" ]
    then
        skip "${REPO_NAME} already exists. ID=${REPO_ID}"
        return 0
    fi

    info "Creating Repository : ${REPO_NAME}"
    info "URL : ${REPO_URL}"

    PAYLOAD="$(
        jq -n \
            --arg name "${REPO_NAME}" \
            --arg url "${REPO_URL}" \
            --argjson product_id "${PRODUCT_ID}" \
            '
            {
                name: $name,
                product_id: $product_id,
                url: $url,
                content_type: "yum"
            }
            '
    )"

    api_request \
        POST \
        "/katello/api/repositories" \
        "${PAYLOAD}"

    if api_success
    then

        REPO_ID="$(jq -r '.id // empty' "${BODY}")"

        if [ -n "${REPO_ID}" ]
        then
            ok "${REPO_NAME} created. ID=${REPO_ID}"
        else
            REPO_ID="$(get_repo_id "${REPO_NAME}")"
            ok "${REPO_NAME} created. ID=${REPO_ID}"
        fi

    else

        if grep -qiE "already|taken|exists" "${BODY}" 2>/dev/null
        then
            REPO_ID="$(get_repo_id "${REPO_NAME}")"
            skip "${REPO_NAME} already exists. ID=${REPO_ID}"
            return 0
        fi

        show_api_error \
            POST \
            "/katello/api/repositories"

        record_failure "${REPO_NAME}"
        return 1
    fi
}

###############################################################################
# Update Repository URL
###############################################################################

update_repo_url()
{
    local REPO_NAME="$1"
    local REPO_URL="$2"

    REPO_ID="$(get_repo_id "${REPO_NAME}")"

    if [ -z "${REPO_ID}" ]
    then
        error "Repository ID not found : ${REPO_NAME}"
        record_failure "${REPO_NAME} ID"
        return 1
    fi

    info "Checking Repository URL : ${REPO_NAME}"

    api_request \
        GET \
        "/katello/api/repositories/${REPO_ID}"

    CURRENT_URL="$(
        jq -r '.url // empty' "${BODY}" 2>/dev/null
    )"

    if [ "${CURRENT_URL}" = "${REPO_URL}" ]
    then
        skip "${REPO_NAME} URL already correct."
        return 0
    fi

    info "Current URL  : ${CURRENT_URL}"
    info "Required URL : ${REPO_URL}"

    PAYLOAD="$(
        jq -n \
            --arg url "${REPO_URL}" \
            '{url: $url}'
    )"

    api_request \
        PUT \
        "/katello/api/repositories/${REPO_ID}" \
        "${PAYLOAD}"

    if api_success
    then
        ok "${REPO_NAME} URL updated."
    else
        show_api_error \
            PUT \
            "/katello/api/repositories/${REPO_ID}"

        record_failure "${REPO_NAME} URL"
        return 1
    fi
}

###############################################################################
# Create EL7 Repositories
###############################################################################

create_el7_repositories()
{
    header "Creating EL7 Migration Repositories"

    create_repo \
        "${BASE_REPO}" \
        "${BASE_URL}"

    create_repo \
        "${UPDATE_REPO}" \
        "${UPDATE_URL}"

    create_repo \
        "${ELEVATE_REPO}" \
        "${ELEVATE_URL}"

    header "Updating Repository URLs"

    update_repo_url \
        "${BASE_REPO}" \
        "${BASE_URL}"

    update_repo_url \
        "${UPDATE_REPO}" \
        "${UPDATE_URL}"

    update_repo_url \
        "${ELEVATE_REPO}" \
        "${ELEVATE_URL}"
}

###############################################################################
# Resume Paused Foreman Tasks
###############################################################################

resume_paused_tasks()
{
    header "Recovering Paused Foreman Tasks"

    api_request \
        GET \
        "/foreman_tasks/api/tasks?search=state%20%3D%20paused&per_page=all"

    COUNT="$(
        jq '.results | length' "${BODY}" 2>/dev/null
    )"

    COUNT="${COUNT:-0}"

    if [ "${COUNT}" -eq 0 ]
    then
        ok "No paused tasks found."
        return 0
    fi

    warn "Found ${COUNT} paused task(s)."

    PAYLOAD='{}'

    api_request \
        POST \
        "/foreman_tasks/api/tasks/bulk_resume" \
        "${PAYLOAD}"

    if api_success
    then
        ok "Paused task recovery requested."
        sleep 10
    else
        warn "Unable to resume paused tasks."
    fi
}

###############################################################################
# Repository Sync Status
###############################################################################

repository_sync_status()
{
    local REPO_ID="$1"

    api_request \
        GET \
        "/katello/api/repositories/${REPO_ID}/sync"

    jq -r '
        [
            (.state // ""),
            (.status // ""),
            (.raw_state // ""),
            (.is_running // "")
        ]
        | @tsv
    ' "${BODY}" 2>/dev/null
}

###############################################################################
# Wait For Repository Sync
###############################################################################

wait_for_repository_sync()
{
    local REPO_ID="$1"
    local REPO_NAME="$2"

    local TRY
    local STATE
    local RUNNING

    for TRY in $(seq 1 60)
    do

        api_request \
            GET \
            "/katello/api/repositories/${REPO_ID}/sync"

        STATE="$(
            jq -r '
                .state //
                .status //
                .raw_state //
                ""
            ' "${BODY}" 2>/dev/null
        )"

        RUNNING="$(
            jq -r '.is_running // false' "${BODY}" 2>/dev/null
        )"

        case "${STATE}" in

            stopped|complete|completed|success|Success)
                ok "${REPO_NAME} synchronization completed."
                return 0
                ;;

            error|failed|Error|Failure)
                error "${REPO_NAME} synchronization failed."
                return 1
                ;;

        esac

        if [ "${RUNNING}" = "false" ] &&
           echo "${STATE}" | grep -qiE 'complete|success|stopped'
        then
            ok "${REPO_NAME} synchronization completed."
            return 0
        fi

        info "${REPO_NAME} sync state : ${STATE:-unknown}"

        sleep 10

    done

    warn "${REPO_NAME} synchronization is still in progress."
    return 0
}

###############################################################################
# Sync Repository
###############################################################################

sync_repository()
{
    local REPO_NAME="$1"

    subheader "Repository Sync : ${REPO_NAME}"

    REPO_ID="$(get_repo_id "${REPO_NAME}")"

    if [ -z "${REPO_ID}" ]
    then
        error "Repository ID not found : ${REPO_NAME}"
        record_failure "Sync ${REPO_NAME}"
        return 1
    fi

    info "Repository ID : ${REPO_ID}"

    api_request \
        GET \
        "/katello/api/repositories/${REPO_ID}/sync"

    STATE="$(
        jq -r '
            .state //
            .status //
            .raw_state //
            ""
        ' "${BODY}" 2>/dev/null
    )"

    RUNNING="$(
        jq -r '.is_running // false' "${BODY}" 2>/dev/null
    )"

    if echo "${STATE}" |
        grep -qiE 'complete|completed|success|stopped'
    then
        skip "${REPO_NAME} already synced."
        return 0
    fi

    if [ "${RUNNING}" = "true" ]
    then
        skip "${REPO_NAME} synchronization already running."
        wait_for_repository_sync \
            "${REPO_ID}" \
            "${REPO_NAME}"
        return $?
    fi

    info "Starting synchronization : ${REPO_NAME}"

api_request \
    POST \
    "/katello/api/repositories/${REPO_ID}/sync" \
    '{}'

if api_success
then

    ok "${REPO_NAME} synchronization started."

    ###########################################################################
    # Capture task ID if returned by the API
    ###########################################################################

    SYNC_TASK_ID="$(
        jq -r '
            .id //
            .task_id //
            .task.id //
            empty
        ' "${BODY}" 2>/dev/null
    )"

    if [ -n "${SYNC_TASK_ID}" ]
    then
        info "Sync Task ID : ${SYNC_TASK_ID}"

        wait_for_foreman_task \
            "${SYNC_TASK_ID}" \
            "${REPO_NAME}"

        return $?
    fi

    ###########################################################################
    # Fall back to repository sync status
    ###########################################################################

    wait_for_repository_sync \
        "${REPO_ID}" \
        "${REPO_NAME}"

    return $?
fi

    if grep -qiE \
        "Required lock is already taken|lock.*taken|already running" \
        "${BODY}" 2>/dev/null
    then

        warn "Repository lock detected."

        local TRY

        for TRY in 1 2 3
        do
            warn "Recovery attempt ${TRY}"

            resume_paused_tasks

            sleep 10

            info "Retrying synchronization..."

            api_request \
                POST \
                "/katello/api/repositories/${REPO_ID}/sync" \
                '{}'

            if api_success
            then
                ok "${REPO_NAME} synchronization started."
                wait_for_repository_sync \
                    "${REPO_ID}" \
                    "${REPO_NAME}"
                return $?
            fi

            if ! grep -qiE \
                "Required lock is already taken|lock.*taken|already running" \
                "${BODY}" 2>/dev/null
            then
                break
            fi

        done
    fi

    show_api_error \
        POST \
        "/katello/api/repositories/${REPO_ID}/sync"

    record_failure "Sync ${REPO_NAME}"
    return 1
}

###############################################################################
# Wait For Foreman Task - LIVE PROGRESS
###############################################################################

wait_for_foreman_task()
{
    local TASK_ID="$1"
    local REPO_NAME="$2"

    local TRY
    local STATE
    local RESULT
    local PROGRESS
    local LABEL
    local STARTED
    local ENDED

    info "Monitoring Foreman task..."
    info "Task ID : ${TASK_ID}"

    for TRY in $(seq 1 720)
    do

        #######################################################################
        # Get main task
        #######################################################################

        api_request \
            GET \
            "/foreman_tasks/api/tasks/${TASK_ID}"

        if ! api_success
        then
            warn "Unable to query Foreman task ${TASK_ID}"
            sleep 5
            continue
        fi

        #######################################################################
        # Extract task information
        #######################################################################

        STATE="$(
            jq -r '.state // ""' "${BODY}" 2>/dev/null
        )"

        RESULT="$(
            jq -r '.result // ""' "${BODY}" 2>/dev/null
        )"

        PROGRESS="$(
            jq -r '
                if .progress != null
                then (.progress | tonumber? // 0)
                else 0
                end
            ' "${BODY}" 2>/dev/null
        )"

        LABEL="$(
            jq -r '.label // .action // ""' "${BODY}" 2>/dev/null
        )"

        STARTED="$(
            jq -r '.started_at // ""' "${BODY}" 2>/dev/null
        )"

        ENDED="$(
            jq -r '.ended_at // ""' "${BODY}" 2>/dev/null
        )"

        #######################################################################
        # Display live task progress
        #######################################################################

        printf "\r[SYNC] %-25s Progress: %6.1f%%  State: %-10s Result: %-10s" \
            "${REPO_NAME}" \
            "${PROGRESS:-0}" \
            "${STATE:-unknown}" \
            "${RESULT:-unknown}"

        #######################################################################
        # Successful completion
        #######################################################################

        if [ "${STATE}" = "stopped" ] &&
           [ "${RESULT}" = "success" ]
        then

            echo
            ok "${REPO_NAME} synchronization completed successfully."

            echo
            echo "Task : ${TASK_ID}"

            if [ -n "${STARTED}" ]
            then
                echo "Started : ${STARTED}"
            fi

            if [ -n "${ENDED}" ]
            then
                echo "Ended   : ${ENDED}"
            fi

            return 0
        fi

        #######################################################################
        # Failed task
        #######################################################################

        if [ "${STATE}" = "stopped" ] &&
           [ "${RESULT}" = "error" ]
        then

            echo

            error "${REPO_NAME} synchronization FAILED."

            echo
            echo "Task Details"
            echo "------------------------------------------------------------"

            jq '{
                id,
                label,
                action,
                state,
                result,
                progress,
                started_at,
                ended_at,
                humanized,
                errors,
                warnings
            }' "${BODY}" 2>/dev/null

            return 1
        fi

        #######################################################################
        # Paused task
        #######################################################################

        if [ "${STATE}" = "paused" ]
        then
            echo
            warn "${REPO_NAME} synchronization is PAUSED."
            warn "Task ID : ${TASK_ID}"
        fi

        sleep 5

    done

    echo
    warn "${REPO_NAME} synchronization polling timeout."
    warn "Task ID : ${TASK_ID}"

    return 1
}

###############################################################################
# Sync All EL7 Repositories
###############################################################################

sync_el7_repositories()
{
    header "Synchronizing EL7 Repositories"

    sync_repository "${BASE_REPO}"

    sync_repository "${UPDATE_REPO}"

    sync_repository "${ELEVATE_REPO}"
}

###############################################################################
# Create Content View
###############################################################################

create_content_view()
{
    header "Creating Content View"

    CONTENT_VIEW_ID="$(get_content_view_id)"

    if [ -n "${CONTENT_VIEW_ID}" ]
    then
        skip "Content View ${CONTENT_VIEW} already exists. ID=${CONTENT_VIEW_ID}"
        return 0
    fi

    info "Creating Content View : ${CONTENT_VIEW}"

    PAYLOAD="$(
        jq -n \
            --arg name "${CONTENT_VIEW}" \
            --argjson organization_id "${ORG_ID}" \
            '
            {
                name: $name,
                organization_id: $organization_id
            }
            '
    )"

    api_request \
        POST \
        "/katello/api/organizations/${ORG_ID}/content_views" \
        "${PAYLOAD}"

    if api_success
    then

        CONTENT_VIEW_ID="$(
            jq -r '.id // empty' "${BODY}"
        )"

        if [ -n "${CONTENT_VIEW_ID}" ]
        then
            ok "Content View created. ID=${CONTENT_VIEW_ID}"
        else
            CONTENT_VIEW_ID="$(get_content_view_id)"
            ok "Content View created. ID=${CONTENT_VIEW_ID}"
        fi

    else

        if grep -qiE \
            "already|taken|exists" \
            "${BODY}" 2>/dev/null
        then
            CONTENT_VIEW_ID="$(get_content_view_id)"
            skip "Content View ${CONTENT_VIEW} already exists. ID=${CONTENT_VIEW_ID}"
            return 0
        fi

        show_api_error \
            POST \
            "/katello/api/organizations/${ORG_ID}/content_views"

        record_failure "${CONTENT_VIEW}"
        return 1
    fi
}

###############################################################################
# Add Repository To Content View
###############################################################################

add_repository_to_cv()
{
    local REPO_NAME="$1"

    REPO_ID="$(get_repo_id "${REPO_NAME}")"

    if [ -z "${REPO_ID}" ]
    then
        error "Repository ID not found : ${REPO_NAME}"
        record_failure "${REPO_NAME} ID"
        return 1
    fi

    subheader "Content View Repository : ${REPO_NAME}"

    api_request \
        GET \
        "/katello/api/content_views/${CONTENT_VIEW_ID}"

    EXISTING="$(
        jq -r \
            --argjson ID "${REPO_ID}" \
            '
            (.repository_ids // [])
            | map(select(. == $ID))
            | length
            ' \
            "${BODY}" 2>/dev/null
    )"

    if [ "${EXISTING}" = "1" ]
    then
        skip "${REPO_NAME} already assigned to ${CONTENT_VIEW}."
        return 0
    fi

    CURRENT_REPOSITORIES="$(
        jq -c '
            .repository_ids // []
        ' "${BODY}" 2>/dev/null
    )"

    if [ -z "${CURRENT_REPOSITORIES}" ]
    then
        CURRENT_REPOSITORIES="[]"
    fi

    NEW_REPOSITORIES="$(
        jq -c \
            --argjson ID "${REPO_ID}" \
            '. + [$ID] | unique' \
            <<< "${CURRENT_REPOSITORIES}"
    )"

    info "Adding ${REPO_NAME} to ${CONTENT_VIEW}"

    PAYLOAD="$(
        jq -n \
            --argjson repository_ids "${NEW_REPOSITORIES}" \
            '
            {
                repository_ids: $repository_ids
            }
            '
    )"

    api_request \
        PUT \
        "/katello/api/content_views/${CONTENT_VIEW_ID}" \
        "${PAYLOAD}"

    if api_success
    then
        ok "${REPO_NAME} added to ${CONTENT_VIEW}."
    else

        if grep -qiE \
            "already|taken|exists" \
            "${BODY}" 2>/dev/null
        then
            skip "${REPO_NAME} already assigned."
            return 0
        fi

        show_api_error \
            PUT \
            "/katello/api/content_views/${CONTENT_VIEW_ID}"

        record_failure "${REPO_NAME} Content View"
        return 1
    fi
}

###############################################################################
# Configure Content View
###############################################################################

configure_content_view()
{
    header "Configuring Content View"

    add_repository_to_cv "${BASE_REPO}"

    add_repository_to_cv "${UPDATE_REPO}"

    add_repository_to_cv "${ELEVATE_REPO}"
}

###############################################################################
# Verify Content View
###############################################################################

verify_content_view()
{
    header "Verifying Content View"

    local FAILED=0
    local REPOSITORY_IDS
    local REPO
    local REPO_ID

    ###########################################################################
    # Get Content View ONCE
    ###########################################################################

    api_request \
        GET \
        "/katello/api/content_views/${CONTENT_VIEW_ID}"

    if ! api_success
    then
        show_api_error \
            GET \
            "/katello/api/content_views/${CONTENT_VIEW_ID}"

        record_failure "Content View Verification"
        return 1
    fi

    ###########################################################################
    # Save repository_ids BEFORE calling get_repo_id()
    ###########################################################################

    REPOSITORY_IDS="$(
        jq -c '.repository_ids // []' "${BODY}" 2>/dev/null
    )"

    info "Content View Repository IDs : ${REPOSITORY_IDS}"

    ###########################################################################
    # Verify each repository
    ###########################################################################

    for REPO in \
        "${BASE_REPO}" \
        "${UPDATE_REPO}" \
        "${ELEVATE_REPO}"
    do

        REPO_ID="$(get_repo_id "${REPO}")"

        if [ -z "${REPO_ID}" ]
        then
            error "${REPO} repository ID could not be resolved."
            FAILED=1
            continue
        fi

        if jq -e \
            --argjson ID "${REPO_ID}" \
            'index($ID) != null' \
            <<< "${REPOSITORY_IDS}" \
            >/dev/null 2>&1
        then
            ok "${REPO} attached to ${CONTENT_VIEW} (ID=${REPO_ID})"
        else
            error "${REPO} missing from ${CONTENT_VIEW} (ID=${REPO_ID})"
            FAILED=1
        fi

    done

    ###########################################################################
    # Final result
    ###########################################################################

    if [ "${FAILED}" -eq 1 ]
    then
        record_failure "Content View Repository Verification"
        return 1
    fi

    ok "All repositories verified."
    return 0
}

###############################################################################
# Publish Content View
###############################################################################

publish_content_view()
{
    header "Publishing Content View"

    verify_content_view

    if [ $? -ne 0 ]
    then
        error "Content View validation failed."
        error "Publish skipped."
        record_failure "${CONTENT_VIEW} publish validation"
        return 1
    fi

    api_request \
        GET \
        "/katello/api/content_views/${CONTENT_VIEW_ID}"

    NEEDS_PUBLISH="$(
        jq -r '.needs_publish // true' "${BODY}" 2>/dev/null
    )"

    LATEST_VERSION="$(
        jq -r '.latest_version // empty' "${BODY}" 2>/dev/null
    )"

    LAST_TASK="$(
        jq -r '.last_task.id // empty' "${BODY}" 2>/dev/null
    )"

    if [ "${NEEDS_PUBLISH}" = "false" ] &&
       [ -n "${LATEST_VERSION}" ]
    then
        skip "${CONTENT_VIEW} already published. Version=${LATEST_VERSION}"
        return 0
    fi

    if [ -n "${LAST_TASK}" ]
    then
        skip "${CONTENT_VIEW} publish task already exists. Task=${LAST_TASK}"
        return 0
    fi

    info "Publishing ${CONTENT_VIEW}"

    DESCRIPTION="EL7 Migration Publish $(date '+%F %T')"

    PAYLOAD="$(
        jq -n \
            --arg description "${DESCRIPTION}" \
            '
            {
                description: $description
            }
            '
    )"

    api_request \
        POST \
        "/katello/api/content_views/${CONTENT_VIEW_ID}/publish" \
        "${PAYLOAD}"

    if api_success
    then

        TASK_ID="$(
            jq -r '
                .id //
                .task_id //
                .task.id //
                empty
            ' "${BODY}" 2>/dev/null
        )"

        if [ -n "${TASK_ID}" ]
        then
            ok "${CONTENT_VIEW} publish started. Task=${TASK_ID}"
        else
            ok "${CONTENT_VIEW} publish started."
        fi

        return 0
    fi

    if grep -qiE \
        "Required lock is already taken|lock.*taken|already running" \
        "${BODY}" 2>/dev/null
    then

        warn "Publish lock detected."

        local TRY

        for TRY in 1 2 3
        do

            warn "Publish recovery attempt ${TRY}"

            resume_paused_tasks

            sleep 10

            info "Retrying publish..."

            api_request \
                POST \
                "/katello/api/content_views/${CONTENT_VIEW_ID}/publish" \
                "${PAYLOAD}"

            if api_success
            then
                ok "Publish started."
                return 0
            fi

            if ! grep -qiE \
                "Required lock is already taken|lock.*taken|already running" \
                "${BODY}" 2>/dev/null
            then
                break
            fi

        done
    fi

    show_api_error \
        POST \
        "/katello/api/content_views/${CONTENT_VIEW_ID}/publish"

    record_failure "${CONTENT_VIEW} publish"
    return 1
}

###############################################################################
# Create / Update Activation Key
###############################################################################

create_activation_key()
{
    header "Creating Activation Key"

    ACTIVATION_KEY_ID="$(get_activation_key_id)"

    if [ -n "${ACTIVATION_KEY_ID}" ]
    then

        skip "Activation Key ${ACTIVATION_KEY} already exists. ID=${ACTIVATION_KEY_ID}"

        api_request \
            GET \
            "/katello/api/activation_keys/${ACTIVATION_KEY_ID}"

        CURRENT_CV_ID="$(
            jq -r '.content_view_id // empty' "${BODY}" 2>/dev/null
        )"

        CURRENT_ENV_ID="$(
            jq -r '.environment_id // empty' "${BODY}" 2>/dev/null
        )"

        if [ "${CURRENT_CV_ID}" = "${CONTENT_VIEW_ID}" ] &&
           [ "${CURRENT_ENV_ID}" = "${LIBRARY_ID}" ]
        then

            skip "Activation Key already points to ${CONTENT_VIEW} / Library."
            return 0
        fi

        info "Updating Activation Key Content View"

        PAYLOAD="$(
            jq -n \
                --argjson organization_id "${ORG_ID}" \
                --argjson content_view_id "${CONTENT_VIEW_ID}" \
                --argjson environment_id "${LIBRARY_ID}" \
                '
                {
                    organization_id: $organization_id,
                    content_view_id: $content_view_id,
                    environment_id: $environment_id
                }
                '
        )"

        api_request \
            PUT \
            "/katello/api/activation_keys/${ACTIVATION_KEY_ID}" \
            "${PAYLOAD}"

        if api_success
        then
            ok "Activation Key updated."
            return 0
        fi

        show_api_error \
            PUT \
            "/katello/api/activation_keys/${ACTIVATION_KEY_ID}"

        record_failure "${ACTIVATION_KEY}"
        return 1
    fi

    info "Creating Activation Key ${ACTIVATION_KEY}"

    PAYLOAD="$(
        jq -n \
            --arg name "${ACTIVATION_KEY}" \
            --argjson organization_id "${ORG_ID}" \
            --argjson content_view_id "${CONTENT_VIEW_ID}" \
            --argjson environment_id "${LIBRARY_ID}" \
            '
            {
                name: $name,
                organization_id: $organization_id,
                content_view_id: $content_view_id,
                environment_id: $environment_id,
                unlimited_hosts: true
            }
            '
    )"

    api_request \
        POST \
        "/katello/api/activation_keys" \
        "${PAYLOAD}"

    if api_success
    then

        ACTIVATION_KEY_ID="$(
            jq -r '.id // empty' "${BODY}"
        )"

        if [ -n "${ACTIVATION_KEY_ID}" ]
        then
            ok "Activation Key created. ID=${ACTIVATION_KEY_ID}"
        else
            ACTIVATION_KEY_ID="$(get_activation_key_id)"
            ok "Activation Key created. ID=${ACTIVATION_KEY_ID}"
        fi

    else

        if grep -qiE \
            "already|taken|exists" \
            "${BODY}" 2>/dev/null
        then
            ACTIVATION_KEY_ID="$(get_activation_key_id)"
            skip "Activation Key already exists. ID=${ACTIVATION_KEY_ID}"
            return 0
        fi

        show_api_error \
            POST \
            "/katello/api/activation_keys"

        record_failure "${ACTIVATION_KEY}"
        return 1
    fi
}

###############################################################################
# Activation Key Verification
###############################################################################

verify_activation_key()
{
    header "Verifying Activation Key"

    if [ -z "${ACTIVATION_KEY_ID}" ]
    then
        ACTIVATION_KEY_ID="$(get_activation_key_id)"
    fi

    if [ -z "${ACTIVATION_KEY_ID}" ]
    then
        error "Activation Key not found : ${ACTIVATION_KEY}"
        record_failure "${ACTIVATION_KEY} verification"
        return 1
    fi

    api_request \
        GET \
        "/katello/api/activation_keys/${ACTIVATION_KEY_ID}"

    if ! api_success
    then
        show_api_error \
            GET \
            "/katello/api/activation_keys/${ACTIVATION_KEY_ID}"

        record_failure "${ACTIVATION_KEY} verification"
        return 1
    fi

    echo

    jq '{
        id,
        name,
        organization_id,
        content_view_id,
        environment_id,
        unlimited_hosts,
        auto_attach
    }' "${BODY}" 2>/dev/null

    CURRENT_CV_ID="$(
        jq -r '.content_view_id // empty' "${BODY}" 2>/dev/null
    )"

    CURRENT_ENV_ID="$(
        jq -r '.environment_id // empty' "${BODY}" 2>/dev/null
    )"

    if [ "${CURRENT_CV_ID}" = "${CONTENT_VIEW_ID}" ] &&
       [ "${CURRENT_ENV_ID}" = "${LIBRARY_ID}" ]
    then
        ok "Activation Key verification completed."
    else
        error "Activation Key mapping is incorrect."
        record_failure "${ACTIVATION_KEY} verification"
        return 1
    fi
}

###############################################################################
# Generate Bootstrap Registration Command
###############################################################################

generate_bootstrap_command()
{
    header "Generating Bootstrap Command"

    echo
    echo "Run this command on CentOS Linux 7 system:"
    echo
    echo "------------------------------------------------------------"
    echo

    echo "rpm -Uvh http://192.168.253.136/pub/katello-ca-consumer-latest.noarch.rpm"
    echo

    echo "subscription-manager register \\"
    echo "  --org=\"${ORG_NAME}\" \\"
    echo "  --activationkey=\"${ACTIVATION_KEY}\""

    echo
    echo "------------------------------------------------------------"
}

###############################################################################
# Summary
###############################################################################

summary()
{
    header "EL7 To EL8 Bootstrap Summary"

    echo
    echo "============================================================"
    echo "Product"
    echo "============================================================"

    api_request \
        GET \
        "/katello/api/products/${PRODUCT_ID}"

    jq '{
        id,
        name,
        label,
        organization_id,
        repository_count
    }' "${BODY}" 2>/dev/null

    echo
    echo "============================================================"
    echo "Repositories"
    echo "============================================================"

    api_request \
        GET \
        "/katello/api/products/${PRODUCT_ID}/repositories?per_page=all"

    jq -r '
        .results[]
        | [
            .id,
            .name,
            (.url // ""),
            (.content_type // ""),
            (.sync_state // .state // "")
        ]
        | @tsv
    ' "${BODY}" 2>/dev/null

    echo
    echo "============================================================"
    echo "Content View"
    echo "============================================================"

    api_request \
        GET \
        "/katello/api/content_views/${CONTENT_VIEW_ID}"

    jq '{
        id,
        name,
        label,
        version_count,
        latest_version,
        latest_version_id,
        repository_ids,
        needs_publish
    }' "${BODY}" 2>/dev/null

    echo
    echo "============================================================"
    echo "Activation Key"
    echo "============================================================"

    api_request \
        GET \
        "/katello/api/activation_keys/${ACTIVATION_KEY_ID}"

    jq '{
        id,
        name,
        organization_id,
        content_view_id,
        environment_id,
        unlimited_hosts
    }' "${BODY}" 2>/dev/null

    echo
    echo "============================================================"
    echo "Migration Configuration"
    echo "============================================================"

    echo "Product          : ${PRODUCT_NAME}"
    echo "Content View     : ${CONTENT_VIEW}"
    echo "Activation Key   : ${ACTIVATION_KEY}"

    echo
    echo "Repositories"
    echo "------------------------------------------------------------"

    echo " - ${BASE_REPO}"
    echo "   ${BASE_URL}"

    echo
    echo " - ${UPDATE_REPO}"
    echo "   ${UPDATE_URL}"

    echo
    echo " - ${ELEVATE_REPO}"
    echo "   ${ELEVATE_URL}"
}

###############################################################################
# Manual Verification
###############################################################################

manual_verification()
{
    echo
    echo "============================================================"
    echo "Manual Verification Commands"
    echo "============================================================"
    echo

    cat <<EOF

1. Foreman API Status
------------------------------------------------------------
curl -ksS \\
  --user "admin:\\\$FOREMAN_PASSWORD" \\
  -H 'Accept: application/json' \\
  "${FOREMAN_URL}/api/status" | jq

2. Product
------------------------------------------------------------
curl -ksS \\
  --user "admin:\\\$FOREMAN_PASSWORD" \\
  -H 'Accept: application/json' \\
  "${FOREMAN_URL}/katello/api/organizations/${ORG_ID}/products?per_page=all" |
jq -r '.results[] | select(.name=="${PRODUCT_NAME}")'

3. Repositories
------------------------------------------------------------
curl -ksS \\
  --user "admin:\\\$FOREMAN_PASSWORD" \\
  -H 'Accept: application/json' \\
  "${FOREMAN_URL}/katello/api/products/${PRODUCT_ID}/repositories?per_page=all" |
jq

4. Content View
------------------------------------------------------------
curl -ksS \\
  --user "admin:\\\$FOREMAN_PASSWORD" \\
  -H 'Accept: application/json' \\
  "${FOREMAN_URL}/katello/api/content_views/${CONTENT_VIEW_ID}" |
jq

5. Activation Key
------------------------------------------------------------
curl -ksS \\
  --user "admin:\\\$FOREMAN_PASSWORD" \\
  -H 'Accept: application/json' \\
  "${FOREMAN_URL}/katello/api/activation_keys/${ACTIVATION_KEY_ID}" |
jq

6. Repository Sync Status
------------------------------------------------------------
curl -ksS \\
  --user "admin:\\\$FOREMAN_PASSWORD" \\
  -H 'Accept: application/json' \\
  "${FOREMAN_URL}/katello/api/repositories/REPOSITORY_ID/sync" |
jq

EOF
}

###############################################################################
# Final Status
###############################################################################

final_status()
{
    header "04 - EL7 To EL8 Bootstrap Completed"

    if [ "${#FAILED_STEPS[@]}" -eq 0 ]
    then
        echo
        ok "EL7 To EL8 Bootstrap completed successfully."
    else
        echo
        warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

        for ITEM in "${FAILED_STEPS[@]}"
        do
            error "${ITEM}"
        done
    fi
}

###############################################################################
# Main Execution
###############################################################################

check_dependencies

if [ "${#FAILED_STEPS[@]}" -ne 0 ]
then
    exit 1
fi

print_configuration

test_foreman_api

if [ "${#FAILED_STEPS[@]}" -ne 0 ]
then
    final_status
    exit 1
fi

resolve_resources

if [ "${#FAILED_STEPS[@]}" -ne 0 ]
then
    final_status
    exit 1
fi

###############################################################################
# Recover Paused Tasks
###############################################################################

resume_paused_tasks

###############################################################################
# Product
###############################################################################

create_product

###############################################################################
# Repositories
###############################################################################

create_el7_repositories

###############################################################################
# Sync
###############################################################################

sync_el7_repositories

###############################################################################
# Content View
###############################################################################

create_content_view

if [ -n "${CONTENT_VIEW_ID}" ]
then
    configure_content_view
    publish_content_view
fi

###############################################################################
# Activation Key
###############################################################################

create_activation_key

verify_activation_key

###############################################################################
# Bootstrap Command
###############################################################################

generate_bootstrap_command

###############################################################################
# Summary
###############################################################################

summary

###############################################################################
# Final Status
###############################################################################

final_status

###############################################################################
# Manual Verification
###############################################################################

manual_verification

###############################################################################
# Exit
###############################################################################

if [ "${#FAILED_STEPS[@]}" -eq 0 ]
then
    exit 0
else
    exit 1
fi
