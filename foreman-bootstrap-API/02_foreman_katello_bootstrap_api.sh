#!/bin/bash
###############################################################################
# Foreman Katello Bootstrap - REST API v2
#
# Script:
#   02_foreman_katello_bootstrap_api.sh
#
# Supports:
#   CentOS 7
#   Rocky Linux 8.10
#   Rocky Linux 9.2
#   Rocky Linux 9.8
#
# Creates / Verifies:
#   Products
#   Repositories
#   Content Views
#   Activation Keys
#   Subscriptions
#
# API:
#   Foreman API v2
#   Katello API v2
###############################################################################

set +e

###############################################################################
# Colors
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
MAGENTA='\033[1;35m'
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

section()
{
    echo
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
}

summary_ok()
{
    printf "%-45s ${GREEN}[OK]${NC}\n" "$1"
}

###############################################################################
# Failure Tracking
###############################################################################

FAILED_STEPS=()

record_failure()
{
    FAILED_STEPS+=("$1")
}

###############################################################################
# Variables
###############################################################################

FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"

ORGANIZATION="${ORGANIZATION:-Default Organization}"

TARGET_VERSION="${TARGET_VERSION:-9.8}"

###############################################################################
# API VERSION
###############################################################################

API_VERSION="2"

# Explicit API v2 route.
FOREMAN_API="${FOREMAN_URL}/api/v2"
KATELLO_API="${FOREMAN_URL}/katello/api/v2"

###############################################################################
# Temporary Directory
###############################################################################

TMP_DIR="/tmp/foreman-katello-bootstrap"

mkdir -p "${TMP_DIR}"

###############################################################################
# Dependency Check
###############################################################################

header "Dependency Check"

DEPENDENCIES=(
    curl
    jq
    cat
    head
    grep
    awk
    sed
    mkdir
    rm
    mktemp
    tr
    printf
    date
)

for CMD in "${DEPENDENCIES[@]}"
do
    CMD_PATH="$(command -v "${CMD}" 2>/dev/null)"

    if [ -n "${CMD_PATH}" ]
    then
        ok "${CMD} found: ${CMD_PATH}"
    else
        error "${CMD} not found."
        record_failure "Dependency: ${CMD}"
    fi
done

if [ "${#FAILED_STEPS[@]}" -ne 0 ]
then
    error "Required dependencies are missing."
    exit 1
fi

###############################################################################
# Target Version
###############################################################################

case "${TARGET_VERSION}" in

    9.2)
        PRODUCT_NAME="Rocky Linux 9.2"
        REPO_PATH="rocky9.2"
        CONTENT_VIEW="Rocky9.2-CV"
        ACTIVATION_KEY="rocky9.2-prod-key"
        ;;

    9.8)
        PRODUCT_NAME="Rocky Linux 9.8"
        REPO_PATH="rocky9"
        CONTENT_VIEW="Rocky9.8-CV"
        ACTIVATION_KEY="rocky9.8-prod-key"
        ;;

    *)
        error "Unsupported TARGET_VERSION : ${TARGET_VERSION}"
        exit 1
        ;;
esac

###############################################################################
# Start
###############################################################################

header "02 - Foreman Katello Bootstrap - REST API"

echo "Foreman URL   : ${FOREMAN_URL}"
echo "API Version   : ${API_VERSION}"
echo "Target Version: ${TARGET_VERSION}"

###############################################################################
# API Helper
###############################################################################

API_RESPONSE=""
API_STATUS=""

api_request()
{
    METHOD="$1"
    URL="$2"
    DATA="$3"

    RESPONSE_FILE="$(mktemp "${TMP_DIR}/response.XXXXXX")"
    STATUS_FILE="$(mktemp "${TMP_DIR}/status.XXXXXX")"

    if [ "${METHOD}" = "GET" ]
    then

        curl \
            --globoff \
            --silent \
            --show-error \
            --insecure \
            --user "${FOREMAN_USER}:${FOREMAN_PASSWORD}" \
            --request GET \
            --header "Accept: application/json" \
            --output "${RESPONSE_FILE}" \
            --write-out "%{http_code}" \
            "${URL}" \
            > "${STATUS_FILE}" 2>/dev/null

    else

        curl \
            --globoff \
            --silent \
            --show-error \
            --insecure \
            --user "${FOREMAN_USER}:${FOREMAN_PASSWORD}" \
            --request "${METHOD}" \
            --header "Accept: application/json" \
            --header "Content-Type: application/json" \
            --data "${DATA}" \
            --output "${RESPONSE_FILE}" \
            --write-out "%{http_code}" \
            "${URL}" \
            > "${STATUS_FILE}" 2>/dev/null

    fi

    API_STATUS="$(cat "${STATUS_FILE}" 2>/dev/null)"
    API_RESPONSE="$(cat "${RESPONSE_FILE}" 2>/dev/null)"

    rm -f "${RESPONSE_FILE}" "${STATUS_FILE}"

    if [ "${API_STATUS}" != "200" ] &&
       [ "${API_STATUS}" != "201" ] &&
       [ "${API_STATUS}" != "202" ] &&
       [ "${API_STATUS}" != "204" ]
    then
        return 1
    fi

    return 0
}

###############################################################################
# API Error Display
###############################################################################

show_api_error()
{
    error "API request failed."
    error "HTTP Status : ${API_STATUS}"
    error "Method      : ${1}"
    error "URL         : ${2}"

    if [ -n "${API_RESPONSE}" ]
    then
        echo "${API_RESPONSE}" | jq . 2>/dev/null || echo "${API_RESPONSE}"
    fi
}

###############################################################################
# Foreman API Authentication Test
###############################################################################

header "Foreman API Authentication Test"

info "Testing Foreman REST API..."

if api_request \
    "GET" \
    "${FOREMAN_URL}/api/status" \
    ""
then

    FOREMAN_VERSION="$(echo "${API_RESPONSE}" | jq -r '.version // .foreman_version // empty' 2>/dev/null)"

    ok "Foreman API authentication successful."

    echo "Foreman Version : ${FOREMAN_VERSION}"
    echo "API Version     : ${API_VERSION}"
    echo "API Status      : ${API_STATUS}"

else

    show_api_error \
        "GET" \
        "${FOREMAN_URL}/api/status"

    exit 1
fi

###############################################################################
# Organization
###############################################################################

ORG_ID=""

api_request \
    "GET" \
    "${FOREMAN_URL}/api/organizations?search=$(printf '%s' "${ORGANIZATION}" | sed 's/ /%20/g')" \
    ""

if [ $? -eq 0 ]
then
    ORG_ID="$(
        echo "${API_RESPONSE}" |
        jq -r --arg NAME "${ORGANIZATION}" '
            (.results // [])[]
            | select(.name == $NAME)
            | .id
        ' |
        head -n 1
    )"
fi

if [ -z "${ORG_ID}" ] || [ "${ORG_ID}" = "null" ]
then
    error "Organization not found : ${ORGANIZATION}"
    record_failure "Organization : ${ORGANIZATION}"
    exit 1
fi

ok "Organization found : ${ORGANIZATION} ID=${ORG_ID}"

###############################################################################
# Recover Paused Tasks
###############################################################################

resume_paused_tasks()
{
    header "Recovering Paused Foreman Tasks"

    api_request \
        "GET" \
        "${FOREMAN_URL}/foreman_tasks/api/tasks?search=state%20%3D%20paused&per_page=100" \
        ""

    if [ $? -ne 0 ]
    then
        warn "Unable to query paused Foreman tasks."
        return 0
    fi

    PAUSED_IDS="$(
        echo "${API_RESPONSE}" |
        jq -r '
            (.results // [])[]
            | select(.state == "paused")
            | .id
        '
    )"

    if [ -z "${PAUSED_IDS}" ]
    then
        ok "No paused tasks found."
        return 0
    fi

    COUNT="$(echo "${PAUSED_IDS}" | grep -c .)"

    warn "Found ${COUNT} paused task(s)."

    while read -r TASK_ID
    do
        [ -z "${TASK_ID}" ] && continue

        api_request \
            "POST" \
            "${FOREMAN_URL}/foreman_tasks/api/tasks/${TASK_ID}/resume" \
            "{}"

        if [ $? -eq 0 ]
        then
            ok "Resumed task ID=${TASK_ID}"
        else
            warn "Unable to resume task ID=${TASK_ID}"
        fi

    done <<< "${PAUSED_IDS}"

    return 0
}

###############################################################################
# Product Functions
###############################################################################

get_product_id()
{
    PRODUCT="$1"

    api_request \
        "GET" \
        "${KATELLO_API}/organizations/${ORG_ID}/products?per_page=100&search=$(printf '%s' "${PRODUCT}" | sed 's/ /%20/g')" \
        ""

    if [ $? -ne 0 ]
    then
        return 1
    fi

    echo "${API_RESPONSE}" |
    jq -r --arg NAME "${PRODUCT}" '
        (.results // [])[]
        | select(.name == $NAME)
        | .id
    ' |
    head -n 1
}

create_product()
{
    PRODUCT="$1"

    section "Product : ${PRODUCT}"

    PRODUCT_ID="$(get_product_id "${PRODUCT}")"

    if [ -n "${PRODUCT_ID}" ] &&
       [ "${PRODUCT_ID}" != "null" ]
    then
        skip "Product '${PRODUCT}' already exists. ID=${PRODUCT_ID}"
        echo "${PRODUCT_ID}"
        return 0
    fi

    info "Creating Product : ${PRODUCT}"

    PAYLOAD="$(
        jq -n \
            --argjson organization_id "${ORG_ID}" \
            --arg name "${PRODUCT}" \
            '{
                organization_id: $organization_id,
                name: $name
            }'
    )"

    if api_request \
        "POST" \
        "${KATELLO_API}/products" \
        "${PAYLOAD}"
    then

        PRODUCT_ID="$(echo "${API_RESPONSE}" | jq -r '.id // empty')"

        if [ -n "${PRODUCT_ID}" ]
        then
            ok "Product created. ID=${PRODUCT_ID}"
            echo "${PRODUCT_ID}"
            return 0
        fi
    fi

    show_api_error \
        "POST" \
        "${KATELLO_API}/products"

    record_failure "${PRODUCT} Product"
    return 1
}

###############################################################################
# Products
###############################################################################

header "[1/6] Creating Katello Products"

CENTOS_PRODUCT_ID="$(create_product "CentOS 7" | tail -n 1)"
ROCKY8_PRODUCT_ID="$(create_product "Rocky Linux 8" | tail -n 1)"
ROCKY9_PRODUCT_ID="$(create_product "${PRODUCT_NAME}" | tail -n 1)"

###############################################################################
# Product Verification
###############################################################################

header "Product Verification"

api_request \
    "GET" \
    "${KATELLO_API}/organizations/${ORG_ID}/products?per_page=100" \
    ""

if [ $? -eq 0 ]
then

    echo "${API_RESPONSE}" |
    jq -r '
        (.results // [])[]
        | [.id,.name,.label,.custom]
        | @tsv
    '

else

    show_api_error \
        "GET" \
        "${KATELLO_API}/organizations/${ORG_ID}/products"
fi

###############################################################################
# Repository Functions
###############################################################################

get_repository_id()
{
    PRODUCT_ID="$1"
    REPO="$2"

    if [ -z "${PRODUCT_ID}" ] ||
       [ "${PRODUCT_ID}" = "null" ]
    then
        return 1
    fi

    api_request \
        "GET" \
        "${KATELLO_API}/products/${PRODUCT_ID}/repositories?per_page=100" \
        ""

    if [ $? -ne 0 ]
    then
        return 1
    fi

    echo "${API_RESPONSE}" |
    jq -r --arg NAME "${REPO}" '
        (.results // [])[]
        | select(.name == $NAME)
        | .id
    ' |
    head -n 1
}

create_repository()
{
    PRODUCT="$1"
    PRODUCT_ID="$2"
    REPO="$3"
    URL="$4"

    section "Repository : ${REPO}"

    if [ -z "${PRODUCT_ID}" ] ||
       [ "${PRODUCT_ID}" = "null" ]
    then
        error "Product ID unavailable for ${PRODUCT}"
        record_failure "${PRODUCT} -> ${REPO}"
        return 1
    fi

    REPO_ID="$(get_repository_id "${PRODUCT_ID}" "${REPO}")"

    if [ -n "${REPO_ID}" ] &&
       [ "${REPO_ID}" != "null" ]
    then
        skip "Repository '${REPO}' already exists. ID=${REPO_ID}"
        echo "${REPO_ID}"
        return 0
    fi

    info "Creating Repository : ${REPO}"

    PAYLOAD="$(
        jq -n \
            --argjson organization_id "${ORG_ID}" \
            --argjson product_id "${PRODUCT_ID}" \
            --arg name "${REPO}" \
            --arg url "${URL}" \
            '{
                organization_id: $organization_id,
                product_id: $product_id,
                name: $name,
                content_type: "yum",
                url: $url
            }'
    )"

    if api_request \
        "POST" \
        "${KATELLO_API}/repositories" \
        "${PAYLOAD}"
    then

        REPO_ID="$(echo "${API_RESPONSE}" | jq -r '.id // empty')"

        if [ -n "${REPO_ID}" ]
        then
            ok "Repository created. ID=${REPO_ID}"
            echo "${REPO_ID}"
            return 0
        fi
    fi

    show_api_error \
        "POST" \
        "${KATELLO_API}/repositories"

    record_failure "${PRODUCT} -> ${REPO}"
    return 1
}

###############################################################################
# Repository URLs
###############################################################################

CENTOS_BASE_URL="http://192.168.253.136/repo/centos/"
CENTOS_UPDATES_URL="http://192.168.253.136/repo/installed_rhel7/"

ROCKY8_BASE_URL="http://192.168.253.136/repo/rocky8/BaseOS/"
ROCKY8_APP_URL="http://192.168.253.136/repo/rocky8/AppStream/"
ROCKY8_INSTALLED_URL="http://192.168.253.136/repo/installed_rhel8/"

ROCKY9_BASE_URL="http://192.168.253.136/repo/${REPO_PATH}/BaseOS/"
ROCKY9_APP_URL="http://192.168.253.136/repo/${REPO_PATH}/AppStream/"
ROCKY9_INSTALLED_URL="http://192.168.253.136/repo/installed_rhel9/"

###############################################################################
# CentOS 7 Repositories
###############################################################################

header "Creating CentOS 7 Repositories"

CENTOS_BASE_ID="$(
    create_repository \
        "CentOS 7" \
        "${CENTOS_PRODUCT_ID}" \
        "CentOS-07-BaseOS" \
        "${CENTOS_BASE_URL}" |
    tail -n 1
)"

CENTOS_UPDATES_ID="$(
    create_repository \
        "CentOS 7" \
        "${CENTOS_PRODUCT_ID}" \
        "CentOS-07-Updates" \
        "${CENTOS_UPDATES_URL}" |
    tail -n 1
)"

###############################################################################
# Rocky Linux 8 Repositories
###############################################################################

header "Creating Rocky Linux 8 Repositories"

ROCKY8_BASE_ID="$(
    create_repository \
        "Rocky Linux 8" \
        "${ROCKY8_PRODUCT_ID}" \
        "Rocky-08-BaseOS" \
        "${ROCKY8_BASE_URL}" |
    tail -n 1
)"

ROCKY8_APP_ID="$(
    create_repository \
        "Rocky Linux 8" \
        "${ROCKY8_PRODUCT_ID}" \
        "Rocky-08-AppStream" \
        "${ROCKY8_APP_URL}" |
    tail -n 1
)"

ROCKY8_INSTALLED_ID="$(
    create_repository \
        "Rocky Linux 8" \
        "${ROCKY8_PRODUCT_ID}" \
        "Rocky-08-RHEL-Installed" \
        "${ROCKY8_INSTALLED_URL}" |
    tail -n 1
)"

###############################################################################
# Rocky Linux 9 Repositories
###############################################################################

header "Creating ${PRODUCT_NAME} Repositories"

ROCKY9_BASE_ID="$(
    create_repository \
        "${PRODUCT_NAME}" \
        "${ROCKY9_PRODUCT_ID}" \
        "Rocky-09-BaseOS" \
        "${ROCKY9_BASE_URL}" |
    tail -n 1
)"

ROCKY9_APP_ID="$(
    create_repository \
        "${PRODUCT_NAME}" \
        "${ROCKY9_PRODUCT_ID}" \
        "Rocky-09-AppStream" \
        "${ROCKY9_APP_URL}" |
    tail -n 1
)"

ROCKY9_INSTALLED_ID="$(
    create_repository \
        "${PRODUCT_NAME}" \
        "${ROCKY9_PRODUCT_ID}" \
        "Rocky-09-RHEL-Installed" \
        "${ROCKY9_INSTALLED_URL}" |
    tail -n 1
)"

###############################################################################
# Repository Verification
###############################################################################

header "Repository Verification"

api_request \
    "GET" \
    "${KATELLO_API}/organizations/${ORG_ID}/repositories?per_page=100" \
    ""

if [ $? -eq 0 ]
then

    echo "${API_RESPONSE}" |
    jq -r '
        (.results // [])[]
        | [.id,.name,.url,.sync_state]
        | @tsv
    '

else

    show_api_error \
        "GET" \
        "${KATELLO_API}/organizations/${ORG_ID}/repositories"
fi

###############################################################################
# Repository Synchronization - LIVE SEQUENTIAL
###############################################################################

wait_for_foreman_task()
{
    TASK_ID="$1"
    TASK_NAME="$2"

    info "Waiting for task completion : ${TASK_NAME}"
    info "Task ID : ${TASK_ID}"

    while true
    do
        #######################################################################
        # Fetch task status LIVE from Foreman
        #######################################################################

        if api_request \
            "GET" \
            "${FOREMAN_URL}/foreman_tasks/api/tasks/${TASK_ID}" \
            ""
        then

            TASK_STATE="$(
                echo "${API_RESPONSE}" |
                jq -r '
                    .state //
                    .task.state //
                    empty
                ' |
                head -n 1
            )"

            TASK_RESULT="$(
                echo "${API_RESPONSE}" |
                jq -r '
                    .result //
                    .task.result //
                    empty
                ' |
                head -n 1
            )"

            TASK_PROGRESS="$(
                echo "${API_RESPONSE}" |
                jq -r '
                    .progress //
                    .task.progress //
                    0
                ' |
                head -n 1
            )"

            ###########################################################################
            # Normalize progress
            #
            # Foreman/Dynflow may return progress as:
            #   0.39 = 39%
            #   1    = 100%
            #
            # Convert fractional progress (0 to 1) into percentage (0 to 100).
            ###########################################################################
            
            if ! echo "${TASK_PROGRESS}" | grep -qE '^[0-9]+([.][0-9]+)?$'
            then
                TASK_PROGRESS="0"
            else
                TASK_PROGRESS="$(
                    awk -v progress="${TASK_PROGRESS}" '
                    BEGIN {
                        if (progress >= 0 && progress <= 1) {
                            progress = progress * 100
                        }
            
                        if (progress > 100) {
                            progress = 100
                        }
            
                        printf "%.2f", progress
                    }'
                )"
            
                # Remove unnecessary trailing zeros:
                # 39.00 -> 39
                # 39.50 -> 39.5
                TASK_PROGRESS="$(
                    echo "${TASK_PROGRESS}" |
                    sed 's/\.00$//; s/\([0-9]\)0$/\1/'
                )"
            fi

            ###################################################################
            # LIVE STATUS
            #
            # \r keeps updating the same terminal line.
            ###################################################################

            printf "\r${CYAN}[LIVE]${NC} %-32s | State: %-10s | Result: %-10s | Progress: %6s%%" \
                "${TASK_NAME}" \
                "${TASK_STATE:-unknown}" \
                "${TASK_RESULT:-unknown}" \
                "${TASK_PROGRESS}"

            ###################################################################
            # SUCCESS
            ###################################################################

            if echo "${TASK_RESULT}" |
                grep -qiE '^success$'
            then
                printf "\n"
                ok "Synchronization completed : ${TASK_NAME}"
                ok "Task ${TASK_ID} finished successfully."
                return 0
            fi

            if echo "${TASK_STATE}" |
                grep -qiE '^stopped$' &&
                echo "${TASK_RESULT}" |
                grep -qiE '^success$'
            then
                printf "\n"
                ok "Synchronization completed : ${TASK_NAME}"
                return 0
            fi

            ###################################################################
            # FAILURE
            ###################################################################

            if echo "${TASK_STATE}" |
                grep -qiE 'error|failed|cancelled|canceled'
            then
                printf "\n"

                error "Synchronization failed : ${TASK_NAME}"
                error "Task ID : ${TASK_ID}"
                error "State   : ${TASK_STATE}"
                error "Result  : ${TASK_RESULT}"

                echo
                echo "${API_RESPONSE}" | jq . 2>/dev/null || true

                return 1
            fi

            if echo "${TASK_RESULT}" |
                grep -qiE 'error|failed|cancelled|canceled'
            then
                printf "\n"

                error "Synchronization failed : ${TASK_NAME}"
                error "Task ID : ${TASK_ID}"
                error "Result  : ${TASK_RESULT}"

                echo
                echo "${API_RESPONSE}" | jq . 2>/dev/null || true

                return 1
            fi

        else

            ###################################################################
            # Temporary API failure.
            #
            # Do NOT consider the sync failed immediately.
            # Try fetching the task again.
            ###################################################################

            printf "\n"
            warn "Unable to fetch task status. Retrying..."
        fi

        #######################################################################
        # Poll Foreman again.
        #
        # This is NOT waiting blindly.
        # Every 5 seconds we fetch the LIVE task status again.
        #######################################################################

        sleep 5
    done
}


sync_repository()
{
    PRODUCT="$1"
    REPO_ID="$2"
    REPO="$3"

    section "Synchronizing Repository : ${REPO}"

    ###########################################################################
    # Validate Repository ID
    ###########################################################################

    if [ -z "${REPO_ID}" ] ||
       [ "${REPO_ID}" = "null" ]
    then
        error "Repository ID unavailable : ${REPO}"
        record_failure "${PRODUCT} -> ${REPO}"
        return 1
    fi

    ###########################################################################
    # Get Repository Information
    ###########################################################################

    if ! api_request \
        "GET" \
        "${KATELLO_API}/repositories/${REPO_ID}" \
        ""
    then
        error "Repository not found : ${REPO}"
        record_failure "${PRODUCT} -> ${REPO}"
        return 1
    fi

    SYNC_STATE="$(
        echo "${API_RESPONSE}" |
        jq -r '.sync_state // empty'
    )"

    ###########################################################################
    # If repository is already syncing:
    #
    # DO NOT SKIP IT.
    # Find the running Foreman task and wait for it.
    ###########################################################################

    if echo "${SYNC_STATE}" | grep -qiE 'running|syncing'
    then

        warn "Synchronization already running : ${REPO}"

        #######################################################################
        # Find running task belonging to this repository.
        #######################################################################

        SEARCH_TERM="resource_id = ${REPO_ID}"

        ENCODED_SEARCH="$(
            printf '%s' "${SEARCH_TERM}" |
            sed \
                -e 's/ /%20/g' \
                -e 's/=/%3D/g'
        )"

        if api_request \
            "GET" \
            "${FOREMAN_URL}/foreman_tasks/api/tasks?search=${ENCODED_SEARCH}&per_page=100" \
            ""
        then

            EXISTING_TASK_ID="$(
                echo "${API_RESPONSE}" |
                jq -r --arg RID "${REPO_ID}" '
                    (.results // [])[]
                    |
                    select(
                        (.resource_id | tostring) == $RID
                        and
                        (.state // "") |
                        test("running|pending|planned"; "i")
                    )
                    |
                    .id
                ' |
                head -n 1
            )"

            if [ -n "${EXISTING_TASK_ID}" ] &&
               [ "${EXISTING_TASK_ID}" != "null" ]
            then

                ok "Existing synchronization task found."
                ok "Task=${EXISTING_TASK_ID}"

                wait_for_foreman_task \
                    "${EXISTING_TASK_ID}" \
                    "${REPO}"

                if [ $? -ne 0 ]
                then
                    record_failure "${PRODUCT} -> ${REPO}"
                    return 1
                fi

                return 0
            fi
        fi

        #######################################################################
        # Repository says running but task could not be identified.
        #######################################################################

        warn "Repository reports running but active task was not found."
        warn "Re-checking repository status..."

        sleep 5

        if api_request \
            "GET" \
            "${KATELLO_API}/repositories/${REPO_ID}" \
            ""
        then

            SYNC_STATE="$(
                echo "${API_RESPONSE}" |
                jq -r '.sync_state // empty'
            )"

            if echo "${SYNC_STATE}" | grep -qiE 'running|syncing'
            then
                warn "Repository is still running."
                warn "Skipping new sync request to avoid duplicate synchronization."

                return 0
            fi
        fi
    fi

    ###########################################################################
    # Start NEW synchronization
    ###########################################################################

    info "Starting synchronization : ${REPO}"

    if api_request \
        "POST" \
        "${KATELLO_API}/repositories/${REPO_ID}/sync" \
        "{}"
    then

        TASK_ID="$(
            echo "${API_RESPONSE}" |
            jq -r '
                .id //
                .task_id //
                .task.uuid //
                .uuid //
                empty
            ' |
            head -n 1
        )"

        #######################################################################
        # Task ID is required because we need to monitor it LIVE.
        #######################################################################

        if [ -z "${TASK_ID}" ] ||
           [ "${TASK_ID}" = "null" ]
        then
            error "Synchronization started but Task ID was not returned."
            echo "${API_RESPONSE}" | jq . 2>/dev/null || true

            record_failure "${PRODUCT} -> ${REPO}"
            return 1
        fi

        ok "Synchronization started. Task=${TASK_ID}"

        #######################################################################
        # IMPORTANT:
        #
        # DO NOT RETURN HERE.
        #
        # Stay inside this function until the repository sync is complete.
        #######################################################################

        wait_for_foreman_task \
            "${TASK_ID}" \
            "${REPO}"

        if [ $? -ne 0 ]
        then
            record_failure "${PRODUCT} -> ${REPO}"
            return 1
        fi

        #######################################################################
        # Only now can the next repository start.
        #######################################################################

        return 0
    fi

    ###########################################################################
    # Repository lock recovery
    ###########################################################################

    if echo "${API_RESPONSE}" |
        grep -qi "Required lock is already taken"
    then

        warn "Repository lock detected : ${REPO}"

        resume_paused_tasks

        sleep 10

        info "Retrying synchronization : ${REPO}"

        if api_request \
            "POST" \
            "${KATELLO_API}/repositories/${REPO_ID}/sync" \
            "{}"
        then

            TASK_ID="$(
                echo "${API_RESPONSE}" |
                jq -r '
                    .id //
                    .task_id //
                    .task.uuid //
                    .uuid //
                    empty
                ' |
                head -n 1
            )"

            if [ -z "${TASK_ID}" ] ||
               [ "${TASK_ID}" = "null" ]
            then
                error "Retry succeeded but Task ID was not returned."

                record_failure "${PRODUCT} -> ${REPO}"
                return 1
            fi

            ok "Synchronization restarted. Task=${TASK_ID}"

            ###################################################################
            # WAIT FOR RETRY TASK TO COMPLETE
            ###################################################################

            wait_for_foreman_task \
                "${TASK_ID}" \
                "${REPO}"

            if [ $? -ne 0 ]
            then
                record_failure "${PRODUCT} -> ${REPO}"
                return 1
            fi

            return 0
        fi
    fi

    ###########################################################################
    # Final API error
    ###########################################################################

    show_api_error \
        "POST" \
        "${KATELLO_API}/repositories/${REPO_ID}/sync"

    error "Synchronization failed : ${REPO}"
    record_failure "${PRODUCT} -> ${REPO}"

    return 1
}

###############################################################################
# CentOS 7 Sync
###############################################################################

header "Synchronizing CentOS 7"

sync_repository \
    "CentOS 7" \
    "${CENTOS_BASE_ID}" \
    "CentOS-07-BaseOS"

sync_repository \
    "CentOS 7" \
    "${CENTOS_UPDATES_ID}" \
    "CentOS-07-Updates"

###############################################################################
# Rocky 8 Sync
###############################################################################

header "Synchronizing Rocky Linux 8"

sync_repository \
    "Rocky Linux 8" \
    "${ROCKY8_BASE_ID}" \
    "Rocky-08-BaseOS"

sync_repository \
    "Rocky Linux 8" \
    "${ROCKY8_APP_ID}" \
    "Rocky-08-AppStream"

sync_repository \
    "Rocky Linux 8" \
    "${ROCKY8_INSTALLED_ID}" \
    "Rocky-08-RHEL-Installed"

###############################################################################
# Rocky 9 Sync
###############################################################################

header "Synchronizing ${PRODUCT_NAME}"

sync_repository \
    "${PRODUCT_NAME}" \
    "${ROCKY9_BASE_ID}" \
    "Rocky-09-BaseOS"

sync_repository \
    "${PRODUCT_NAME}" \
    "${ROCKY9_APP_ID}" \
    "Rocky-09-AppStream"

sync_repository \
    "${PRODUCT_NAME}" \
    "${ROCKY9_INSTALLED_ID}" \
    "Rocky-09-RHEL-Installed"

###############################################################################
# Content View Functions
###############################################################################

get_content_view_id()
{
    CV_NAME="$1"

    api_request \
        "GET" \
        "${KATELLO_API}/organizations/${ORG_ID}/content_views?per_page=100" \
        ""

    if [ $? -ne 0 ]
    then
        return 1
    fi

    echo "${API_RESPONSE}" |
    jq -r --arg NAME "${CV_NAME}" '
        (.results // [])[]
        | select(.name == $NAME)
        | .id
    ' |
    head -n 1
}

create_content_view()
{
    CV_NAME="$1"

    section "Content View : ${CV_NAME}"

    CV_ID="$(get_content_view_id "${CV_NAME}")"

    if [ -n "${CV_ID}" ] &&
       [ "${CV_ID}" != "null" ]
    then
        skip "Content View '${CV_NAME}' already exists. ID=${CV_ID}"
        echo "${CV_ID}"
        return 0
    fi

    info "Creating Content View : ${CV_NAME}"

    PAYLOAD="$(
        jq -n \
            --argjson organization_id "${ORG_ID}" \
            --arg name "${CV_NAME}" \
            '{
                organization_id: $organization_id,
                name: $name
            }'
    )"

    if api_request \
        "POST" \
        "${KATELLO_API}/organizations/${ORG_ID}/content_views" \
        "${PAYLOAD}"
    then

        CV_ID="$(echo "${API_RESPONSE}" | jq -r '.id // empty')"

        if [ -n "${CV_ID}" ]
        then
            ok "Content View created. ID=${CV_ID}"
            echo "${CV_ID}"
            return 0
        fi
    fi

    show_api_error \
        "POST" \
        "${KATELLO_API}/organizations/${ORG_ID}/content_views"

    record_failure "Content View : ${CV_NAME}"
    return 1
}

###############################################################################
# Add Repository To Content View
###############################################################################

add_repository_to_cv()
{
    CV="$1"
    CV_ID="$2"
    REPO="$3"
    REPO_ID="$4"

    section "Adding ${REPO} -> ${CV}"

    if [ -z "${CV_ID}" ] ||
       [ "${CV_ID}" = "null" ]
    then
        error "Content View ID unavailable : ${CV}"
        record_failure "${REPO} -> ${CV}"
        return 1
    fi

    if [ -z "${REPO_ID}" ] ||
       [ "${REPO_ID}" = "null" ]
    then
        error "Repository ID unavailable : ${REPO}"
        record_failure "${REPO} -> ${CV}"
        return 1
    fi

    api_request \
        "GET" \
        "${KATELLO_API}/content_views/${CV_ID}/repositories?per_page=100" \
        ""

    if [ $? -eq 0 ]
    then

        EXISTS="$(
            echo "${API_RESPONSE}" |
            jq -r --argjson RID "${REPO_ID}" '
                (.results // [])[]
                | select(.id == $RID)
                | .id
            ' |
            head -n 1
        )"

        if [ -n "${EXISTS}" ]
        then
            skip "Repository already assigned."
            return 0
        fi
    fi

    info "Adding Repository : ${REPO}"

    PAYLOAD="$(
        jq -n \
            --argjson repository_ids "[${REPO_ID}]" \
            '{repository_ids: $repository_ids}'
    )"

    if api_request \
        "PUT" \
        "${KATELLO_API}/content_views/${CV_ID}" \
        "${PAYLOAD}"
    then

        ok "Repository added."
        return 0

    fi

    show_api_error \
        "PUT" \
        "${KATELLO_API}/content_views/${CV_ID}"

    record_failure "${REPO} -> ${CV}"
    return 1
}

###############################################################################
# Content Views
###############################################################################

header "[4/6] Creating Content Views"

CENTOS_CV_ID="$(
    create_content_view "CentOS7-CV" |
    tail -n 1
)"

ROCKY8_CV_ID="$(
    create_content_view "Rocky8-CV" |
    tail -n 1
)"

ROCKY9_CV_ID="$(
    create_content_view "${CONTENT_VIEW}" |
    tail -n 1
)"

###############################################################################
# Add CentOS Repositories
###############################################################################

add_repository_to_cv \
    "CentOS7-CV" \
    "${CENTOS_CV_ID}" \
    "CentOS-07-BaseOS" \
    "${CENTOS_BASE_ID}"

add_repository_to_cv \
    "CentOS7-CV" \
    "${CENTOS_CV_ID}" \
    "CentOS-07-Updates" \
    "${CENTOS_UPDATES_ID}"

###############################################################################
# Add Rocky 8 Repositories
###############################################################################

add_repository_to_cv \
    "Rocky8-CV" \
    "${ROCKY8_CV_ID}" \
    "Rocky-08-BaseOS" \
    "${ROCKY8_BASE_ID}"

add_repository_to_cv \
    "Rocky8-CV" \
    "${ROCKY8_CV_ID}" \
    "Rocky-08-AppStream" \
    "${ROCKY8_APP_ID}"

add_repository_to_cv \
    "Rocky8-CV" \
    "${ROCKY8_CV_ID}" \
    "Rocky-08-RHEL-Installed" \
    "${ROCKY8_INSTALLED_ID}"

###############################################################################
# Add Rocky 9 Repositories
###############################################################################

add_repository_to_cv \
    "${CONTENT_VIEW}" \
    "${ROCKY9_CV_ID}" \
    "Rocky-09-BaseOS" \
    "${ROCKY9_BASE_ID}"

add_repository_to_cv \
    "${CONTENT_VIEW}" \
    "${ROCKY9_CV_ID}" \
    "Rocky-09-AppStream" \
    "${ROCKY9_APP_ID}"

add_repository_to_cv \
    "${CONTENT_VIEW}" \
    "${ROCKY9_CV_ID}" \
    "Rocky-09-RHEL-Installed" \
    "${ROCKY9_INSTALLED_ID}"

###############################################################################
# Publish Content View
###############################################################################

publish_content_view()
{
    CV="$1"
    CV_ID="$2"

    section "Publishing Content View : ${CV}"

    if [ -z "${CV_ID}" ] ||
       [ "${CV_ID}" = "null" ]
    then
        error "Content View ID unavailable : ${CV}"
        record_failure "Publish : ${CV}"
        return 1
    fi

    PAYLOAD="$(
        jq -n \
            --arg description "Bootstrap Publish $(date '+%F %T')" \
            '{
                description: $description
            }'
    )"

    info "Publishing Content View : ${CV}"

    if api_request \
        "POST" \
        "${KATELLO_API}/content_views/${CV_ID}/publish" \
        "${PAYLOAD}"
    then

        TASK_ID="$(
            echo "${API_RESPONSE}" |
            jq -r '.id // .task_id // empty'
        )"

        if [ -n "${TASK_ID}" ]
        then
            ok "Content View publish started. Task=${TASK_ID}"
        else
            ok "Content View published."
        fi

        return 0
    fi

    if echo "${API_RESPONSE}" | grep -qi "Required lock is already taken"
    then

        warn "Content View publish lock detected."

        resume_paused_tasks

        sleep 10

        if api_request \
            "POST" \
            "${KATELLO_API}/content_views/${CV_ID}/publish" \
            "${PAYLOAD}"
        then
            ok "Content View published after recovery."
            return 0
        fi
    fi

    show_api_error \
        "POST" \
        "${KATELLO_API}/content_views/${CV_ID}/publish"

    error "Content View publish failed : ${CV}"
    record_failure "Publish : ${CV}"
    return 1
}

###############################################################################
# Publish Content Views
###############################################################################

publish_content_view \
    "CentOS7-CV" \
    "${CENTOS_CV_ID}"

publish_content_view \
    "Rocky8-CV" \
    "${ROCKY8_CV_ID}"

publish_content_view \
    "${CONTENT_VIEW}" \
    "${ROCKY9_CV_ID}"

###############################################################################
# Lifecycle Environment
###############################################################################

get_library_environment_id()
{
    api_request \
        "GET" \
        "${KATELLO_API}/organizations/${ORG_ID}/environments?per_page=100" \
        ""

    if [ $? -ne 0 ]
    then
        return 1
    fi

    echo "${API_RESPONSE}" |
    jq -r '
        (.results // [])[]
        | select(.library == true or .name == "Library")
        | .id
    ' |
    head -n 1
}

###############################################################################
# Activation Key Functions
###############################################################################

get_activation_key_id()
{
    KEY="$1"

    api_request \
        "GET" \
        "${KATELLO_API}/organizations/${ORG_ID}/activation_keys?per_page=100" \
        ""

    if [ $? -ne 0 ]
    then
        return 1
    fi

    echo "${API_RESPONSE}" |
    jq -r --arg NAME "${KEY}" '
        (.results // [])[]
        | select(.name == $NAME)
        | .id
    ' |
    head -n 1
}

create_activation_key()
{
    KEY="$1"
    CV="$2"
    CV_ID="$3"
    ENV_ID="$4"

    section "Activation Key : ${KEY}"

    if [ -z "${CV_ID}" ] ||
       [ "${CV_ID}" = "null" ]
    then
        error "Content View ID unavailable : ${CV}"
        record_failure "Activation Key : ${KEY}"
        return 1
    fi

    if [ -z "${ENV_ID}" ] ||
       [ "${ENV_ID}" = "null" ]
    then
        error "Library environment ID unavailable."
        record_failure "Activation Key : ${KEY}"
        return 1
    fi

    KEY_ID="$(get_activation_key_id "${KEY}")"

    if [ -n "${KEY_ID}" ] &&
       [ "${KEY_ID}" != "null" ]
    then

        skip "Activation Key '${KEY}' already exists. ID=${KEY_ID}"

        PAYLOAD="$(
            jq -n \
                --argjson organization_id "${ORG_ID}" \
                --argjson environment_id "${ENV_ID}" \
                --argjson content_view_id "${CV_ID}" \
                '{
                    organization_id: $organization_id,
                    environment_id: $environment_id,
                    content_view_id: $content_view_id
                }'
        )"

        if api_request \
            "PUT" \
            "${KATELLO_API}/activation_keys/${KEY_ID}" \
            "${PAYLOAD}"
        then
            ok "Activation Key updated."
        else
            warn "Activation Key exists but update failed."
        fi

        echo "${KEY_ID}"
        return 0
    fi

    info "Creating Activation Key : ${KEY}"

    PAYLOAD="$(
        jq -n \
            --argjson organization_id "${ORG_ID}" \
            --arg name "${KEY}" \
            --argjson environment_id "${ENV_ID}" \
            --argjson content_view_id "${CV_ID}" \
            '{
                organization_id: $organization_id,
                name: $name,
                environment_id: $environment_id,
                content_view_id: $content_view_id
            }'
    )"

    if api_request \
        "POST" \
        "${KATELLO_API}/activation_keys" \
        "${PAYLOAD}"
    then

        KEY_ID="$(echo "${API_RESPONSE}" | jq -r '.id // empty')"

        if [ -n "${KEY_ID}" ]
        then
            ok "Activation Key created. ID=${KEY_ID}"
            echo "${KEY_ID}"
            return 0
        fi
    fi

    show_api_error \
        "POST" \
        "${KATELLO_API}/activation_keys"

    record_failure "Activation Key : ${KEY}"
    return 1
}

###############################################################################
# Activation Keys
###############################################################################

header "[5/6] Creating Activation Keys"

LIBRARY_ENV_ID="$(get_library_environment_id)"

if [ -n "${LIBRARY_ENV_ID}" ]
then
    ok "Library environment found. ID=${LIBRARY_ENV_ID}"
else
    error "Library environment not found."
    record_failure "Library Environment"
fi

CENTOS_KEY_ID="$(
    create_activation_key \
        "centos7-prod-key" \
        "CentOS7-CV" \
        "${CENTOS_CV_ID}" \
        "${LIBRARY_ENV_ID}" |
    tail -n 1
)"

ROCKY8_KEY_ID="$(
    create_activation_key \
        "rocky8-prod-key" \
        "Rocky8-CV" \
        "${ROCKY8_CV_ID}" \
        "${LIBRARY_ENV_ID}" |
    tail -n 1
)"

ROCKY9_KEY_ID="$(
    create_activation_key \
        "${ACTIVATION_KEY}" \
        "${CONTENT_VIEW}" \
        "${ROCKY9_CV_ID}" \
        "${LIBRARY_ENV_ID}" |
    tail -n 1
)"

###############################################################################
# Subscription Functions
###############################################################################

get_subscription_id()
{
    PRODUCT="$1"

    api_request \
        "GET" \
        "${KATELLO_API}/organizations/${ORG_ID}/subscriptions?per_page=100" \
        ""

    if [ $? -ne 0 ]
    then
        return 1
    fi

    echo "${API_RESPONSE}" |
    jq -r --arg PRODUCT "${PRODUCT}" '
        (.results // [])[]
        | select(
            .product_name == $PRODUCT
            or
            .product.name == $PRODUCT
        )
        | .id
    ' |
    head -n 1
}

attach_subscription()
{
    KEY="$1"
    KEY_ID="$2"
    SUB_ID="$3"
    PRODUCT="$4"

    section "Attaching Subscription : ${PRODUCT}"

    if [ -z "${KEY_ID}" ] ||
       [ "${KEY_ID}" = "null" ]
    then
        error "Activation Key ID not found : ${KEY}"
        record_failure "${KEY} Activation Key"
        return 1
    fi

    if [ -z "${SUB_ID}" ] ||
       [ "${SUB_ID}" = "null" ]
    then
        warn "Subscription ID not found for ${PRODUCT}."
        warn "Skipping subscription attachment."
        return 0
    fi

    PAYLOAD="$(
        jq -n \
            --argjson subscription_id "${SUB_ID}" \
            --argjson organization_id "${ORG_ID}" \
            '{
                subscription_id: $subscription_id,
                organization_id: $organization_id
            }'
    )"

    if api_request \
        "PUT" \
        "${KATELLO_API}/activation_keys/${KEY_ID}/add_subscriptions" \
        "${PAYLOAD}"
    then

        ok "${PRODUCT} subscription attached."
        return 0
    fi

    if echo "${API_RESPONSE}" | grep -qi "already"
    then
        skip "${PRODUCT} subscription already attached."
        return 0
    fi

    show_api_error \
        "PUT" \
        "${KATELLO_API}/activation_keys/${KEY_ID}/add_subscriptions"

    error "${PRODUCT} subscription failed."
    record_failure "${PRODUCT} Subscription"
    return 1
}

###############################################################################
# Subscription IDs
###############################################################################

CENTOS_SUB_ID="$(get_subscription_id "CentOS 7")"
ROCKY8_SUB_ID="$(get_subscription_id "Rocky Linux 8")"
ROCKY9_SUB_ID="$(get_subscription_id "${PRODUCT_NAME}")"

###############################################################################
# Attach Subscriptions
###############################################################################

header "Attaching Subscriptions"

attach_subscription \
    "centos7-prod-key" \
    "${CENTOS_KEY_ID}" \
    "${CENTOS_SUB_ID}" \
    "CentOS 7"

attach_subscription \
    "rocky8-prod-key" \
    "${ROCKY8_KEY_ID}" \
    "${ROCKY8_SUB_ID}" \
    "Rocky Linux 8"

attach_subscription \
    "${ACTIVATION_KEY}" \
    "${ROCKY9_KEY_ID}" \
    "${ROCKY9_SUB_ID}" \
    "${PRODUCT_NAME}"

###############################################################################
# Verification
###############################################################################

header "[6/6] Verification"

###############################################################################
# Products
###############################################################################

header "Products"

api_request \
    "GET" \
    "${KATELLO_API}/organizations/${ORG_ID}/products?per_page=100" \
    ""

if [ $? -eq 0 ]
then
    echo "${API_RESPONSE}" |
    jq -r '
        (.results // [])[]
        | [.id,.name,.label]
        | @tsv
    '
fi

###############################################################################
# Repositories
###############################################################################

header "Repositories"

api_request \
    "GET" \
    "${KATELLO_API}/organizations/${ORG_ID}/repositories?per_page=100" \
    ""

if [ $? -eq 0 ]
then
    echo "${API_RESPONSE}" |
    jq -r '
        (.results // [])[]
        | [.id,.name,.url,.sync_state]
        | @tsv
    '
fi

###############################################################################
# Content Views
###############################################################################

header "Content Views"

api_request \
    "GET" \
    "${KATELLO_API}/organizations/${ORG_ID}/content_views?per_page=100" \
    ""

if [ $? -eq 0 ]
then
    echo "${API_RESPONSE}" |
    jq -r '
        (.results // [])[]
        | [.id,.name,.label]
        | @tsv
    '
fi

###############################################################################
# Activation Keys
###############################################################################

header "Activation Keys"

api_request \
    "GET" \
    "${KATELLO_API}/organizations/${ORG_ID}/activation_keys?per_page=100" \
    ""

if [ $? -eq 0 ]
then
    echo "${API_RESPONSE}" |
    jq -r '
        (.results // [])[]
        | [.id,.name,.content_view_id,.environment_id]
        | @tsv
    '
fi

###############################################################################
# Subscriptions
###############################################################################

header "Subscriptions"

api_request \
    "GET" \
    "${KATELLO_API}/organizations/${ORG_ID}/subscriptions?per_page=100" \
    ""

if [ $? -eq 0 ]
then
    echo "${API_RESPONSE}" |
    jq -r '
        (.results // [])[]
        | [
            .id,
            .name,
            (.product_name // .product.name // ""),
            .available,
            .consumed
        ]
        | @tsv
    '
fi

###############################################################################
# Registration Commands
###############################################################################

header "Registration Commands"

echo

info "CentOS 7"

echo 'subscription-manager register \'
echo '  --org="Default_Organization" \'
echo '  --activationkey="centos7-prod-key"'

echo

info "Rocky Linux 8"

echo 'subscription-manager register \'
echo '  --org="Default_Organization" \'
echo '  --activationkey="rocky8-prod-key"'

echo

info "${PRODUCT_NAME}"

echo 'subscription-manager register \'
echo '  --org="Default_Organization" \'
echo "  --activationkey=\"${ACTIVATION_KEY}\""

###############################################################################
# API Endpoint Summary
###############################################################################

header "API Endpoint Summary"

echo
echo "Foreman API:"
echo "  ${FOREMAN_API}"

echo
echo "Katello API:"
echo "  ${KATELLO_API}"

echo
echo "API Version:"
echo "  ${API_VERSION}"

###############################################################################
# Final Summary
###############################################################################

header "02 - Foreman Katello Bootstrap API Completed"

if [ "${#FAILED_STEPS[@]}" -eq 0 ]
then

    ok "Foreman Katello Bootstrap completed successfully."

else

    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

    echo

    for STEP in "${FAILED_STEPS[@]}"
    do
        error "${STEP}"
    done
fi

###############################################################################
# Manual Verification
###############################################################################

header "Manual Verification Commands"

echo

echo "1. Foreman API Status:"
echo
echo "curl -ksS \\"
echo "  --user \"${FOREMAN_USER}:\${FOREMAN_PASSWORD}\" \\"
echo "  -H 'Accept: application/json' \\"
echo "  '${FOREMAN_URL}/api/status' | jq"

echo

echo "2. Products:"
echo
echo "curl -ksS \\"
echo "  --user \"${FOREMAN_USER}:\${FOREMAN_PASSWORD}\" \\"
echo "  -H 'Accept: application/json' \\"
echo "  '${KATELLO_API}/organizations/${ORG_ID}/products?per_page=100' | jq"

echo

echo "3. Repositories:"
echo
echo "curl -ksS \\"
echo "  --user \"${FOREMAN_USER}:\${FOREMAN_PASSWORD}\" \\"
echo "  -H 'Accept: application/json' \\"
echo "  '${KATELLO_API}/organizations/${ORG_ID}/repositories?per_page=100' | jq"

echo

echo "4. Content Views:"
echo
echo "curl -ksS \\"
echo "  --user \"${FOREMAN_USER}:\${FOREMAN_PASSWORD}\" \\"
echo "  -H 'Accept: application/json' \\"
echo "  '${KATELLO_API}/organizations/${ORG_ID}/content_views?per_page=100' | jq"

echo

echo "5. Activation Keys:"
echo
echo "curl -ksS \\"
echo "  --user \"${FOREMAN_USER}:\${FOREMAN_PASSWORD}\" \\"
echo "  -H 'Accept: application/json' \\"
echo "  '${KATELLO_API}/organizations/${ORG_ID}/activation_keys?per_page=100' | jq"

echo

echo "6. Subscriptions:"
echo
echo "curl -ksS \\"
echo "  --user \"${FOREMAN_USER}:\${FOREMAN_PASSWORD}\" \\"
echo "  -H 'Accept: application/json' \\"
echo "  '${KATELLO_API}/organizations/${ORG_ID}/subscriptions?per_page=100' | jq"

echo

exit 0
