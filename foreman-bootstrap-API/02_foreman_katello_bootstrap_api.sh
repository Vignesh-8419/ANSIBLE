#!/bin/bash
###############################################################################
# Foreman Katello Bootstrap - REST API v2
#
# Script Name:
#   02_foreman_katello_bootstrap_api.sh
#
# Supports:
#   CentOS 7
#   Rocky Linux 8.10
#   Rocky Linux 9.2
#   Rocky Linux 9.8
#
# Creates:
#   Products
#   Repositories
#   Content Views
#   Activation Keys
#
# Synchronizes:
#   Repositories
#
# Publishes:
#   Content Views
#
# Attaches:
#   Subscriptions to Activation Keys
#
# API:
#   Foreman API v2
#   Katello API v2
#
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
    echo -e "${CYAN}$1${NC}"
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

summary_ok()
{
    printf "%-35s ${GREEN}[OK]${NC}\n" "$1"
}

###############################################################################
# Variables
###############################################################################

FOREMAN_URL="${FOREMAN_URL:-https://cent-07-01.vgs.com}"

FOREMAN_USER="${FOREMAN_USER:-admin}"

FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"

ORGANIZATION="Default Organization"

TARGET_VERSION="${TARGET_VERSION:-9.8}"

###############################################################################
# API Version
###############################################################################

API_VERSION="2"

###############################################################################
# API Headers
###############################################################################

ACCEPT_HEADER="Accept: application/json,version=${API_VERSION}"

CONTENT_HEADER="Content-Type: application/json"

###############################################################################
# Temporary Files
###############################################################################

TMP_DIR="/tmp/foreman-katello-bootstrap-api"

mkdir -p "${TMP_DIR}"

###############################################################################
# API Endpoints
###############################################################################

FOREMAN_API="${FOREMAN_URL}/api"

KATELLO_API="${FOREMAN_URL}/katello/api"

TASK_API="${FOREMAN_URL}/foreman_tasks/api"

###############################################################################
# Dependency Check
###############################################################################

header "Dependency Check"

REQUIRED_COMMANDS=(
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

for CMD in "${REQUIRED_COMMANDS[@]}"
do

    if command -v "${CMD}" >/dev/null 2>&1
    then
        ok "${CMD} found: $(command -v "${CMD}")"
    else
        error "${CMD} not found."
        record_failure "Dependency: ${CMD}"
    fi

done

if [ ${#FAILED_STEPS[@]} -ne 0 ]
then
    error "Required dependencies are missing."
    exit 1
fi

###############################################################################
# Generic REST API Function
###############################################################################

API_RESPONSE=""
API_STATUS=""

api_request()
{
    METHOD="$1"
    URL="$2"
    DATA="${3:-}"

    RESPONSE_FILE="$(mktemp)"

    if [ -n "${DATA}" ]
    then

        API_STATUS=$(
            curl -ksS \
                -u "${FOREMAN_USER}:${FOREMAN_PASSWORD}" \
                -H "${ACCEPT_HEADER}" \
                -H "${CONTENT_HEADER}" \
                -X "${METHOD}" \
                -d "${DATA}" \
                -o "${RESPONSE_FILE}" \
                -w "%{http_code}" \
                "${URL}"
        )

    else

        API_STATUS=$(
            curl -ksS \
                -u "${FOREMAN_USER}:${FOREMAN_PASSWORD}" \
                -H "${ACCEPT_HEADER}" \
                -X "${METHOD}" \
                -o "${RESPONSE_FILE}" \
                -w "%{http_code}" \
                "${URL}"
        )

    fi

    API_RESPONSE="$(cat "${RESPONSE_FILE}" 2>/dev/null)"

    rm -f "${RESPONSE_FILE}"

    return 0
}

###############################################################################
# API Success Test
###############################################################################

api_success()
{
    case "${API_STATUS}" in

        200|201|202|204)
            return 0
            ;;

        *)
            return 1
            ;;

    esac
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
        echo
        echo "${API_RESPONSE}" | jq . 2>/dev/null || echo "${API_RESPONSE}"
        echo
    fi
}

###############################################################################
# Organization ID
###############################################################################

ORGANIZATION_ID=""

get_organization_id()
{
    api_request \
        GET \
        "${FOREMAN_API}/organizations?search=$(printf '%s' "${ORGANIZATION}" | sed 's/ /%20/g')&per_page=100"

    if ! api_success
    then
        show_api_error GET "${FOREMAN_API}/organizations"
        record_failure "Organization lookup"
        return 1
    fi

    ORGANIZATION_ID=$(
        echo "${API_RESPONSE}" |
        jq -r --arg NAME "${ORGANIZATION}" '
            (.results // [])[]
            | select(.name == $NAME)
            | .id
        ' |
        head -n 1
    )

    if [ -z "${ORGANIZATION_ID}" ] || [ "${ORGANIZATION_ID}" = "null" ]
    then
        error "Organization not found : ${ORGANIZATION}"
        record_failure "Organization : ${ORGANIZATION}"
        return 1
    fi

    ok "Organization found : ${ORGANIZATION} ID=${ORGANIZATION_ID}"

    return 0
}

###############################################################################
# Foreman API Authentication
###############################################################################

test_foreman_api()
{
    header "Foreman API Authentication Test"

    info "Testing Foreman REST API..."

    api_request \
        GET \
        "${FOREMAN_API}/status"

    if ! api_success
    then
        show_api_error GET "${FOREMAN_API}/status"
        record_failure "Foreman API authentication"
        return 1
    fi

    VERSION=$(
        echo "${API_RESPONSE}" |
        jq -r '.version // .foreman_version // "unknown"'
    )

    API_REPORTED_VERSION=$(
        echo "${API_RESPONSE}" |
        jq -r '.api_version // "2"'
    )

    ok "Foreman API authentication successful."

    echo "Foreman Version : ${VERSION}"
    echo "API Version     : ${API_REPORTED_VERSION}"
    echo "API Status      : ${API_STATUS}"

    return 0
}

###############################################################################
# Resume Paused Tasks
###############################################################################

resume_paused_tasks()
{
    header "Recovering Paused Foreman Tasks"

    api_request \
        GET \
        "${TASK_API}/tasks?search=state%20%3D%20paused&per_page=100"

    if ! api_success
    then
        warn "Could not query Foreman tasks."
        return 0
    fi

    COUNT=$(
        echo "${API_RESPONSE}" |
        jq '[.results // [] | .[] | select(.state == "paused")] | length'
    )

    if [ "${COUNT}" -eq 0 ]
    then
        ok "No paused tasks found."
        return 0
    fi

    warn "Found ${COUNT} paused task(s)."

    DATA='{"search":"state = paused"}'

    api_request \
        POST \
        "${TASK_API}/tasks/bulk_resume" \
        "${DATA}"

    if api_success
    then
        ok "Paused task recovery request completed."
    else
        warn "Unable to resume paused tasks."
        show_api_error POST "${TASK_API}/tasks/bulk_resume"
    fi

    for i in 1 2 3 4 5 6
    do

        sleep 10

        api_request \
            GET \
            "${TASK_API}/tasks?search=state%20%3D%20paused&per_page=100"

        if ! api_success
        then
            continue
        fi

        COUNT=$(
            echo "${API_RESPONSE}" |
            jq '[.results // [] | .[] | select(.state == "paused")] | length'
        )

        if [ "${COUNT}" -eq 0 ]
        then
            ok "Paused tasks cleared."
            return 0
        fi

        warn "${COUNT} paused task(s) still remain."

    done

    warn "Some paused tasks still remain."

    return 0
}

###############################################################################
# Start
###############################################################################

header "02 - Foreman Katello Bootstrap - REST API"

info "Foreman URL  : ${FOREMAN_URL}"
info "API Version  : ${API_VERSION}"
info "Target Version : ${TARGET_VERSION}"

###############################################################################
# TARGET VERSION
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
# Authentication
###############################################################################

test_foreman_api

###############################################################################
# Organization
###############################################################################

get_organization_id

###############################################################################
# Product IDs
###############################################################################

CENTOS_PRODUCT_ID=""
ROCKY8_PRODUCT_ID=""
ROCKY9_PRODUCT_ID=""

###############################################################################
# Product Lookup
###############################################################################

get_product_id()
{
    PRODUCT="$1"

    api_request \
        GET \
        "${KATELLO_API}/organizations/${ORGANIZATION_ID}/products?search=$(printf '%s' "name = ${PRODUCT}" | sed 's/ /%20/g')&per_page=100"

    if ! api_success
    then
        show_api_error GET "${KATELLO_API}/organizations/${ORGANIZATION_ID}/products"
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

###############################################################################
# Create Product
###############################################################################

create_product()
{
    PRODUCT="$1"

    info "Checking Product : ${PRODUCT}"

    PRODUCT_ID="$(get_product_id "${PRODUCT}")"

    if [ -n "${PRODUCT_ID}" ] && [ "${PRODUCT_ID}" != "null" ]
    then

        skip "Product '${PRODUCT}' already exists. ID=${PRODUCT_ID}"

    else

        info "Creating Product : ${PRODUCT}"

        DATA=$(
            jq -n \
                --arg name "${PRODUCT}" \
                --argjson org "${ORGANIZATION_ID}" \
                '{
                    organization_id: $org,
                    product: {
                        name: $name
                    }
                }'
        )

        api_request \
            POST \
            "${KATELLO_API}/products" \
            "${DATA}"

        if api_success
        then

            PRODUCT_ID=$(
                echo "${API_RESPONSE}" |
                jq -r '.id // empty'
            )

            ok "Product created. ID=${PRODUCT_ID}"

        else

            show_api_error POST "${KATELLO_API}/products"

            record_failure "${PRODUCT} Product"

            echo

            return 1

        fi

    fi

    case "${PRODUCT}" in

        "CentOS 7")
            CENTOS_PRODUCT_ID="${PRODUCT_ID}"
            ;;

        "Rocky Linux 8")
            ROCKY8_PRODUCT_ID="${PRODUCT_ID}"
            ;;

        "${PRODUCT_NAME}")
            ROCKY9_PRODUCT_ID="${PRODUCT_ID}"
            ;;

    esac

    echo
}

###############################################################################
# [1/6] Create Products
###############################################################################

header "[1/6] Creating Katello Products"

create_product "CentOS 7"

create_product "Rocky Linux 8"

create_product "${PRODUCT_NAME}"

###############################################################################
# Product Verification
###############################################################################

header "Product Verification"

api_request \
    GET \
    "${KATELLO_API}/organizations/${ORGANIZATION_ID}/products?per_page=100"

if api_success
then

    echo "${API_RESPONSE}" |
        jq -r '
            (.results // [])[] |
            [.id,.name,.label] |
            @tsv
        '

else

    show_api_error GET "${KATELLO_API}/organizations/${ORGANIZATION_ID}/products"

fi

###############################################################################
# Repository IDs
###############################################################################

###############################################################################
# Repository Lookup
###############################################################################

get_repository_id()
{
    PRODUCT_ID="$1"
    REPO="$2"

    api_request \
        GET \
        "${KATELLO_API}/products/${PRODUCT_ID}/repositories?search=$(printf '%s' "name = ${REPO}" | sed 's/ /%20/g')&per_page=100"

    if ! api_success
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

###############################################################################
# Create Repository
###############################################################################

create_repository()
{
    PRODUCT="$1"
    PRODUCT_ID="$2"
    REPO="$3"
    URL="$4"

    info "Checking Repository : ${REPO}"

    REPO_ID="$(get_repository_id "${PRODUCT_ID}" "${REPO}")"

    if [ -n "${REPO_ID}" ] && [ "${REPO_ID}" != "null" ]
    then

        skip "Repository '${REPO}' already exists. ID=${REPO_ID}"

        echo

        return 0

    fi

    info "Creating Repository : ${REPO}"

    DATA=$(
        jq -n \
            --arg name "${REPO}" \
            --arg url "${URL}" \
            --argjson product "${PRODUCT_ID}" \
            --argjson org "${ORGANIZATION_ID}" \
            '{
                organization_id: $org,
                product_id: $product,
                repository: {
                    name: $name,
                    content_type: "yum",
                    url: $url
                }
            }'
    )

    api_request \
        POST \
        "${KATELLO_API}/repositories" \
        "${DATA}"

    if api_success
    then

        REPO_ID=$(
            echo "${API_RESPONSE}" |
            jq -r '.id // empty'
        )

        ok "Repository created. ID=${REPO_ID}"

    else

        show_api_error POST "${KATELLO_API}/repositories"

        record_failure "${PRODUCT} -> ${REPO}"

    fi

    echo
}

###############################################################################
# [2/6] Create Repositories
###############################################################################

header "[2/6] Creating Katello Repositories"

###############################################################################
# CentOS 7
###############################################################################

header "Creating CentOS 7 Repositories"

create_repository \
    "CentOS 7" \
    "${CENTOS_PRODUCT_ID}" \
    "CentOS-07-BaseOS" \
    "http://192.168.253.136/repo/centos/"

create_repository \
    "CentOS 7" \
    "${CENTOS_PRODUCT_ID}" \
    "CentOS-07-Updates" \
    "http://192.168.253.136/repo/installed_rhel7/"

###############################################################################
# Rocky 8
###############################################################################

header "Creating Rocky Linux 8 Repositories"

create_repository \
    "Rocky Linux 8" \
    "${ROCKY8_PRODUCT_ID}" \
    "Rocky-08-BaseOS" \
    "http://192.168.253.136/repo/rocky8/BaseOS/"

create_repository \
    "Rocky Linux 8" \
    "${ROCKY8_PRODUCT_ID}" \
    "Rocky-08-AppStream" \
    "http://192.168.253.136/repo/rocky8/AppStream/"

create_repository \
    "Rocky Linux 8" \
    "${ROCKY8_PRODUCT_ID}" \
    "Rocky-08-RHEL-Installed" \
    "http://192.168.253.136/repo/installed_rhel8/"

###############################################################################
# Rocky 9
###############################################################################

header "Creating ${PRODUCT_NAME} Repositories"

create_repository \
    "${PRODUCT_NAME}" \
    "${ROCKY9_PRODUCT_ID}" \
    "Rocky-09-BaseOS" \
    "http://192.168.253.136/repo/${REPO_PATH}/BaseOS/"

create_repository \
    "${PRODUCT_NAME}" \
    "${ROCKY9_PRODUCT_ID}" \
    "Rocky-09-AppStream" \
    "http://192.168.253.136/repo/${REPO_PATH}/AppStream/"

create_repository \
    "${PRODUCT_NAME}" \
    "${ROCKY9_PRODUCT_ID}" \
    "Rocky-09-RHEL-Installed" \
    "http://192.168.253.136/repo/installed_rhel9/"

###############################################################################
# Repository Verification
###############################################################################

header "Repository Verification"

echo
info "CentOS 7"

api_request \
    GET \
    "${KATELLO_API}/products/${CENTOS_PRODUCT_ID}/repositories?per_page=100"

if api_success
then
    echo "${API_RESPONSE}" |
        jq -r '
            (.results // [])[] |
            [.id,.name,.url,.content_type] |
            @tsv
        '
fi

echo
info "Rocky Linux 8"

api_request \
    GET \
    "${KATELLO_API}/products/${ROCKY8_PRODUCT_ID}/repositories?per_page=100"

if api_success
then
    echo "${API_RESPONSE}" |
        jq -r '
            (.results // [])[] |
            [.id,.name,.url,.content_type] |
            @tsv
        '
fi

echo
info "${PRODUCT_NAME}"

api_request \
    GET \
    "${KATELLO_API}/products/${ROCKY9_PRODUCT_ID}/repositories?per_page=100"

if api_success
then
    echo "${API_RESPONSE}" |
        jq -r '
            (.results // [])[] |
            [.id,.name,.url,.content_type] |
            @tsv
        '
fi

###############################################################################
# Repository Synchronization
###############################################################################

sync_repository()
{
PRODUCT="$1"
PRODUCT_ID="$2"
REPO="$3"

info "Checking Repository : ${REPO}"

REPO_ID="$(get_repository_id "${PRODUCT_ID}" "${REPO}")"

if [ -z "${REPO_ID}" ] || [ "${REPO_ID}" = "null" ]
then

    error "Repository not found : ${REPO}"

    record_failure "${PRODUCT} -> ${REPO}"

    return 1

fi

###############################################################################
# Check Sync State
###############################################################################

api_request \
    GET \
    "${KATELLO_API}/repositories/${REPO_ID}"

if api_success
then

    SYNC_STATUS=$(
        echo "${API_RESPONSE}" |
        jq -r '
            .sync_state
            // .sync_state_aggregated
            // "unknown"
        '
    )

else

    SYNC_STATUS="unknown"

fi

if echo "${SYNC_STATUS}" | grep -qi "running"
then

    skip "Synchronization already running."

    return 0

fi

###############################################################################
# Start Sync
###############################################################################

info "Starting synchronization : ${REPO}"

DATA='{"repository":{}}'

api_request \
    POST \
    "${KATELLO_API}/repositories/${REPO_ID}/sync" \
    "${DATA}"

if api_success
then

    ok "Synchronization started."

    return 0

fi

###############################################################################
# Lock Recovery
###############################################################################

if echo "${API_RESPONSE}" | grep -qi "Required lock is already taken"
then

    warn "Repository lock detected."

    resume_paused_tasks

    sleep 10

    api_request \
        POST \
        "${KATELLO_API}/repositories/${REPO_ID}/sync" \
        "${DATA}"

    if api_success
    then

        ok "Synchronization started after recovery."

        return 0

    fi

fi

error "Synchronization failed : ${REPO}"

show_api_error POST "${KATELLO_API}/repositories/${REPO_ID}/sync"

record_failure "${PRODUCT} -> ${REPO}"

return 1
}

###############################################################################
# Repository Sync - CentOS 7
###############################################################################

header "Synchronizing CentOS 7"

sync_repository \
    "CentOS 7" \
    "${CENTOS_PRODUCT_ID}" \
    "CentOS-07-BaseOS"

sync_repository \
    "CentOS 7" \
    "${CENTOS_PRODUCT_ID}" \
    "CentOS-07-Updates"

###############################################################################
# Repository Sync - Rocky 8
###############################################################################

header "Synchronizing Rocky Linux 8"

sync_repository \
    "Rocky Linux 8" \
    "${ROCKY8_PRODUCT_ID}" \
    "Rocky-08-BaseOS"

sync_repository \
    "Rocky Linux 8" \
    "${ROCKY8_PRODUCT_ID}" \
    "Rocky-08-AppStream"

sync_repository \
    "Rocky Linux 8" \
    "${ROCKY8_PRODUCT_ID}" \
    "Rocky-08-RHEL-Installed"

###############################################################################
# Repository Sync - Rocky 9
###############################################################################

header "Synchronizing ${PRODUCT_NAME}"

sync_repository \
    "${PRODUCT_NAME}" \
    "${ROCKY9_PRODUCT_ID}" \
    "Rocky-09-BaseOS"

sync_repository \
    "${PRODUCT_NAME}" \
    "${ROCKY9_PRODUCT_ID}" \
    "Rocky-09-AppStream"

sync_repository \
    "${PRODUCT_NAME}" \
    "${ROCKY9_PRODUCT_ID}" \
    "Rocky-09-RHEL-Installed"

###############################################################################
# Sync Verification
###############################################################################

header "Repository Synchronization Verification"

echo
info "CentOS 7"

api_request \
    GET \
    "${KATELLO_API}/products/${CENTOS_PRODUCT_ID}/repositories?per_page=100"

if api_success
then
    echo "${API_RESPONSE}" |
        jq -r '
            (.results // [])[] |
            [.id,.name,.sync_state,.last_sync] |
            @tsv
        '
fi

echo
info "Rocky Linux 8"

api_request \
    GET \
    "${KATELLO_API}/products/${ROCKY8_PRODUCT_ID}/repositories?per_page=100"

if api_success
then
    echo "${API_RESPONSE}" |
        jq -r '
            (.results // [])[] |
            [.id,.name,.sync_state,.last_sync] |
            @tsv
        '
fi

echo
info "${PRODUCT_NAME}"

api_request \
    GET \
    "${KATELLO_API}/products/${ROCKY9_PRODUCT_ID}/repositories?per_page=100"

if api_success
then
    echo "${API_RESPONSE}" |
        jq -r '
            (.results // [])[] |
            [.id,.name,.sync_state,.last_sync] |
            @tsv
        '
fi

###############################################################################
# Content View IDs
###############################################################################

CENTOS_CV_ID=""
ROCKY8_CV_ID=""
ROCKY9_CV_ID=""

###############################################################################
# Content View Lookup
###############################################################################

get_content_view_id()
{
    CV_NAME="$1"

    api_request \
        GET \
        "${KATELLO_API}/organizations/${ORGANIZATION_ID}/content_views?search=$(printf '%s' "name = ${CV_NAME}" | sed 's/ /%20/g')&per_page=100"

    if ! api_success
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

###############################################################################
# Create Content View
###############################################################################

create_content_view()
{
    CV_NAME="$1"

    info "Checking Content View : ${CV_NAME}"

    CV_ID="$(get_content_view_id "${CV_NAME}")"

    if [ -n "${CV_ID}" ] && [ "${CV_ID}" != "null" ]
    then

        skip "Content View '${CV_NAME}' already exists. ID=${CV_ID}"

    else

        info "Creating Content View : ${CV_NAME}"

        DATA=$(
            jq -n \
                --arg name "${CV_NAME}" \
                --argjson org "${ORGANIZATION_ID}" \
                '{
                    organization_id: $org,
                    content_view: {
                        name: $name
                    }
                }'
        )

        api_request \
            POST \
            "${KATELLO_API}/content_views" \
            "${DATA}"

        if api_success
        then

            CV_ID=$(
                echo "${API_RESPONSE}" |
                jq -r '.id // empty'
            )

            ok "Content View created. ID=${CV_ID}"

        else

            show_api_error POST "${KATELLO_API}/content_views"

            record_failure "Content View : ${CV_NAME}"

            return 1

        fi

    fi

    case "${CV_NAME}" in

        "CentOS7-CV")
            CENTOS_CV_ID="${CV_ID}"
            ;;

        "Rocky8-CV")
            ROCKY8_CV_ID="${CV_ID}"
            ;;

        "${CONTENT_VIEW}")
            ROCKY9_CV_ID="${CV_ID}"
            ;;

    esac

    echo
}

###############################################################################
# [4/6] Create Content Views
###############################################################################

header "[4/6] Creating Content Views"

create_content_view "CentOS7-CV"

create_content_view "Rocky8-CV"

create_content_view "${CONTENT_VIEW}"

###############################################################################
# Add Repository To Content View
###############################################################################

add_repository_to_cv()
{
CV="$1"
CV_ID="$2"
PRODUCT="$3"
PRODUCT_ID="$4"
REPO="$5"

info "Checking Repository : ${REPO} in ${CV}"

REPO_ID="$(get_repository_id "${PRODUCT_ID}" "${REPO}")"

if [ -z "${REPO_ID}" ] || [ "${REPO_ID}" = "null" ]
then

    error "Repository not found : ${REPO}"

    record_failure "${REPO} -> ${CV}"

    return 1

fi

###############################################################################
# Current CV repositories
###############################################################################

api_request \
    GET \
    "${KATELLO_API}/content_views/${CV_ID}/repositories?per_page=100"

if api_success
then

    ALREADY_ASSIGNED=$(
        echo "${API_RESPONSE}" |
        jq -r --argjson ID "${REPO_ID}" '
            [
                (.results // [])[] |
                select(.id == $ID)
            ] |
            length
        '
    )

    if [ "${ALREADY_ASSIGNED}" -gt 0 ]
    then

        skip "Repository already assigned."

        echo

        return 0

    fi

fi

###############################################################################
# Get Existing Repository IDs
###############################################################################

CURRENT_REPO_IDS=$(
    echo "${API_RESPONSE}" |
    jq -r '
        [
            (.results // [])[] |
            .id
        ] |
        join(",")
    '
)

if [ -z "${CURRENT_REPO_IDS}" ]
then

    NEW_REPO_IDS="${REPO_ID}"

else

    NEW_REPO_IDS="${CURRENT_REPO_IDS},${REPO_ID}"

fi

###############################################################################
# Update Content View
###############################################################################

info "Adding Repository : ${REPO}"

DATA=$(
    jq -n \
        --argjson org "${ORGANIZATION_ID}" \
        --argjson cv "${CV_ID}" \
        --argjson repo "${REPO_ID}" \
        --arg ids "${NEW_REPO_IDS}" '
        {
            organization_id: $org,
            content_view: {
                repository_ids:
                    ($ids | split(",") | map(tonumber))
            }
        }
    '
)

api_request \
    PUT \
    "${KATELLO_API}/content_views/${CV_ID}" \
    "${DATA}"

if api_success
then

    ok "Repository added."

else

    error "Failed adding repository."

    show_api_error PUT "${KATELLO_API}/content_views/${CV_ID}"

    record_failure "${REPO} -> ${CV}"

fi

echo
}

###############################################################################
# CentOS 7 Content View
###############################################################################

add_repository_to_cv \
    "CentOS7-CV" \
    "${CENTOS_CV_ID}" \
    "CentOS 7" \
    "${CENTOS_PRODUCT_ID}" \
    "CentOS-07-BaseOS"

add_repository_to_cv \
    "CentOS7-CV" \
    "${CENTOS_CV_ID}" \
    "CentOS 7" \
    "${CENTOS_PRODUCT_ID}" \
    "CentOS-07-Updates"

###############################################################################
# Rocky 8 Content View
###############################################################################

add_repository_to_cv \
    "Rocky8-CV" \
    "${ROCKY8_CV_ID}" \
    "Rocky Linux 8" \
    "${ROCKY8_PRODUCT_ID}" \
    "Rocky-08-BaseOS"

add_repository_to_cv \
    "Rocky8-CV" \
    "${ROCKY8_CV_ID}" \
    "Rocky Linux 8" \
    "${ROCKY8_PRODUCT_ID}" \
    "Rocky-08-AppStream"

add_repository_to_cv \
    "Rocky8-CV" \
    "${ROCKY8_CV_ID}" \
    "Rocky Linux 8" \
    "${ROCKY8_PRODUCT_ID}" \
    "Rocky-08-RHEL-Installed"

###############################################################################
# Rocky 9 Content View
###############################################################################

add_repository_to_cv \
    "${CONTENT_VIEW}" \
    "${ROCKY9_CV_ID}" \
    "${PRODUCT_NAME}" \
    "${ROCKY9_PRODUCT_ID}" \
    "Rocky-09-BaseOS"

add_repository_to_cv \
    "${CONTENT_VIEW}" \
    "${ROCKY9_CV_ID}" \
    "${PRODUCT_NAME}" \
    "${ROCKY9_PRODUCT_ID}" \
    "Rocky-09-AppStream"

add_repository_to_cv \
    "${CONTENT_VIEW}" \
    "${ROCKY9_CV_ID}" \
    "${PRODUCT_NAME}" \
    "${ROCKY9_PRODUCT_ID}" \
    "Rocky-09-RHEL-Installed"

###############################################################################
# Publish Content View
###############################################################################

publish_content_view()
{
    CV="$1"
    CV_ID="$2"

    info "Publishing Content View : ${CV}"

    DATA=$(
        jq -n \
            --arg desc "Bootstrap Publish $(date '+%F %T')" \
            '{
                description: $desc
            }'
    )

    api_request \
        POST \
        "${KATELLO_API}/content_views/${CV_ID}/publish" \
        "${DATA}"

    if api_success
    then

        ok "Content View publish request completed."

        return 0

    fi

###############################################################################
# Lock Recovery
###############################################################################

    if echo "${API_RESPONSE}" | grep -qi "Required lock is already taken"
    then

        warn "Content View publish locked."

        resume_paused_tasks

        sleep 10

        api_request \
            POST \
            "${KATELLO_API}/content_views/${CV_ID}/publish" \
            "${DATA}"

        if api_success
        then

            ok "Content View published after recovery."

            return 0

        fi

    fi

    error "Content View publish failed."

    show_api_error \
        POST \
        "${KATELLO_API}/content_views/${CV_ID}/publish"

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
# Activation Key IDs
###############################################################################

CENTOS_AK_ID=""
ROCKY8_AK_ID=""
ROCKY9_AK_ID=""

###############################################################################
# Activation Key Lookup
###############################################################################

get_activation_key_id()
{
    KEY="$1"

    api_request \
        GET \
        "${KATELLO_API}/organizations/${ORGANIZATION_ID}/activation_keys?name=$(printf '%s' "${KEY}" | sed 's/ /%20/g')&per_page=100"

    if ! api_success
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

###############################################################################
# Create Activation Key
###############################################################################

create_activation_key()
{
    KEY="$1"
    CV="$2"
    CV_ID="$3"

    info "Checking Activation Key : ${KEY}"

    KEY_ID="$(get_activation_key_id "${KEY}")"

    if [ -n "${KEY_ID}" ] && [ "${KEY_ID}" != "null" ]
    then

        skip "Activation Key '${KEY}' already exists. ID=${KEY_ID}"

        #######################################################################
        # Update existing activation key
        #######################################################################

        DATA=$(
            jq -n \
                --argjson org "${ORGANIZATION_ID}" \
                --argjson cv "${CV_ID}" '
                {
                    organization_id: $org,
                    activation_key: {
                        content_view_id: $cv
                    }
                }
            '
        )

        api_request \
            PUT \
            "${KATELLO_API}/activation_keys/${KEY_ID}" \
            "${DATA}"

        if api_success
        then
            ok "Activation Key updated."
        else
            warn "Activation Key exists but update failed."
            show_api_error PUT "${KATELLO_API}/activation_keys/${KEY_ID}"
        fi

    else

        info "Creating Activation Key : ${KEY}"

        DATA=$(
            jq -n \
                --arg name "${KEY}" \
                --argjson org "${ORGANIZATION_ID}" \
                --argjson cv "${CV_ID}" '
                {
                    organization_id: $org,
                    activation_key: {
                        name: $name,
                        unlimited_hosts: true,
                        auto_attach: true,
                        content_view_id: $cv
                    }
                }
            '
        )

        api_request \
            POST \
            "${KATELLO_API}/activation_keys" \
            "${DATA}"

        if api_success
        then

            KEY_ID=$(
                echo "${API_RESPONSE}" |
                jq -r '.id // empty'
            )

            ok "Activation Key created. ID=${KEY_ID}"

        else

            show_api_error POST "${KATELLO_API}/activation_keys"

            record_failure "Activation Key : ${KEY}"

            return 1

        fi

    fi

    case "${KEY}" in

        "centos7-prod-key")
            CENTOS_AK_ID="${KEY_ID}"
            ;;

        "rocky8-prod-key")
            ROCKY8_AK_ID="${KEY_ID}"
            ;;

        "${ACTIVATION_KEY}")
            ROCKY9_AK_ID="${KEY_ID}"
            ;;

    esac

    echo
}

###############################################################################
# [5/6] Create Activation Keys
###############################################################################

header "[5/6] Creating Activation Keys"

create_activation_key \
    "centos7-prod-key" \
    "CentOS7-CV" \
    "${CENTOS_CV_ID}"

create_activation_key \
    "rocky8-prod-key" \
    "Rocky8-CV" \
    "${ROCKY8_CV_ID}"

create_activation_key \
    "${ACTIVATION_KEY}" \
    "${CONTENT_VIEW}" \
    "${ROCKY9_CV_ID}"

###############################################################################
# Subscription IDs
###############################################################################

CENTOS_SUB_ID=""
ROCKY8_SUB_ID=""
ROCKY9_SUB_ID=""

###############################################################################
# Get Subscription ID
###############################################################################

get_subscription_id()
{
    PRODUCT="$1"

    api_request \
        GET \
        "${KATELLO_API}/organizations/${ORGANIZATION_ID}/subscriptions?per_page=100"

    if ! api_success
    then

        show_api_error \
            GET \
            "${KATELLO_API}/organizations/${ORGANIZATION_ID}/subscriptions"

        return 1

    fi

    echo "${API_RESPONSE}" |
        jq -r --arg PRODUCT "${PRODUCT}" '
            (.results // [])[]
            |
            select(
                .product_name == $PRODUCT
                or
                .name == $PRODUCT
            )
            |
            .id
        ' |
        head -n 1
}

###############################################################################
# Attach Subscription
###############################################################################

attach_subscription()
{
    KEY="$1"
    KEY_ID="$2"
    SUB_ID="$3"
    PRODUCT="$4"

    info "Attaching Subscription : ${PRODUCT}"

    if [ -z "${SUB_ID}" ] || [ "${SUB_ID}" = "null" ]
    then

        error "Subscription ID not found : ${PRODUCT}"

        record_failure "${PRODUCT} Subscription"

        return 1

    fi

    if [ -z "${KEY_ID}" ] || [ "${KEY_ID}" = "null" ]
    then

        error "Activation Key ID not found : ${KEY}"

        record_failure "${KEY} Activation Key"

        return 1

    fi

###############################################################################
# Check existing activation-key subscriptions
###############################################################################

    api_request \
        GET \
        "${KATELLO_API}/activation_keys/${KEY_ID}/subscriptions?per_page=100"

    if api_success
    then

        ALREADY_ATTACHED=$(
            echo "${API_RESPONSE}" |
            jq -r --argjson SID "${SUB_ID}" '
                [
                    (.results // [])[] |
                    select(.id == $SID)
                ] |
                length
            '
        )

        if [ "${ALREADY_ATTACHED}" -gt 0 ]
        then

            skip "${PRODUCT} subscription already attached."

            return 0

        fi

    fi

###############################################################################
# Attach
###############################################################################

    DATA=$(
        jq -n \
            --argjson org "${ORGANIZATION_ID}" \
            --argjson sub "${SUB_ID}" '
            {
                organization_id: $org,
                subscription_id: $sub,
                activation_key: {
                    organization_id: $org
                }
            }
        '
    )

    api_request \
        PUT \
        "${KATELLO_API}/activation_keys/${KEY_ID}/add_subscriptions" \
        "${DATA}"

    if api_success
    then

        ok "${PRODUCT} subscription attached."

    else

        if echo "${API_RESPONSE}" | grep -qi "already"
        then

            skip "${PRODUCT} subscription already attached."

        else

            error "${PRODUCT} subscription failed."

            show_api_error \
                PUT \
                "${KATELLO_API}/activation_keys/${KEY_ID}/add_subscriptions"

            record_failure "${PRODUCT} Subscription"

        fi

    fi
}

###############################################################################
# Get Subscription IDs
###############################################################################

header "Attaching Subscriptions"

CENTOS_SUB_ID="$(get_subscription_id "CentOS 7")"

ROCKY8_SUB_ID="$(get_subscription_id "Rocky Linux 8")"

ROCKY9_SUB_ID="$(get_subscription_id "${PRODUCT_NAME}")"

###############################################################################
# Attach
###############################################################################

attach_subscription \
    "centos7-prod-key" \
    "${CENTOS_AK_ID}" \
    "${CENTOS_SUB_ID}" \
    "CentOS 7"

attach_subscription \
    "rocky8-prod-key" \
    "${ROCKY8_AK_ID}" \
    "${ROCKY8_SUB_ID}" \
    "Rocky Linux 8"

attach_subscription \
    "${ACTIVATION_KEY}" \
    "${ROCKY9_AK_ID}" \
    "${ROCKY9_SUB_ID}" \
    "${PRODUCT_NAME}"

###############################################################################
# Verification
###############################################################################

header "[6/6] Verification"

###############################################################################
# Content Views
###############################################################################

header "Content Views"

api_request \
    GET \
    "${KATELLO_API}/organizations/${ORGANIZATION_ID}/content_views?per_page=100"

if api_success
then

    echo "${API_RESPONSE}" |
        jq -r '
            (.results // [])[] |
            [.id,.name,.label] |
            @tsv
        '

else

    show_api_error \
        GET \
        "${KATELLO_API}/organizations/${ORGANIZATION_ID}/content_views"

fi

###############################################################################
# Activation Keys
###############################################################################

header "Activation Keys"

api_request \
    GET \
    "${KATELLO_API}/organizations/${ORGANIZATION_ID}/activation_keys?per_page=100"

if api_success
then

    echo "${API_RESPONSE}" |
        jq -r '
            (.results // [])[] |
            [.id,.name,.content_view.name,.environment.name] |
            @tsv
        '

else

    show_api_error \
        GET \
        "${KATELLO_API}/organizations/${ORGANIZATION_ID}/activation_keys"

fi

###############################################################################
# Repositories
###############################################################################

header "Repositories"

echo
info "CentOS 7"

api_request \
    GET \
    "${KATELLO_API}/products/${CENTOS_PRODUCT_ID}/repositories?per_page=100"

if api_success
then

    echo "${API_RESPONSE}" |
        jq -r '
            (.results // [])[] |
            [.id,.name,.url,.sync_state] |
            @tsv
        '

fi

echo
info "Rocky Linux 8"

api_request \
    GET \
    "${KATELLO_API}/products/${ROCKY8_PRODUCT_ID}/repositories?per_page=100"

if api_success
then

    echo "${API_RESPONSE}" |
        jq -r '
            (.results // [])[] |
            [.id,.name,.url,.sync_state] |
            @tsv
        '

fi

echo
info "${PRODUCT_NAME}"

api_request \
    GET \
    "${KATELLO_API}/products/${ROCKY9_PRODUCT_ID}/repositories?per_page=100"

if api_success
then

    echo "${API_RESPONSE}" |
        jq -r '
            (.results // [])[] |
            [.id,.name,.url,.sync_state] |
            @tsv
        '

fi

###############################################################################
# Registration Commands
###############################################################################

header "Registration Commands"

echo

info "CentOS 7"

echo "subscription-manager register \\"
echo "  --org=\"Default_Organization\" \\"
echo "  --activationkey=\"centos7-prod-key\""

echo

info "Rocky Linux 8"

echo "subscription-manager register \\"
echo "  --org=\"Default_Organization\" \\"
echo "  --activationkey=\"rocky8-prod-key\""

echo

info "${PRODUCT_NAME}"

echo "subscription-manager register \\"
echo "  --org=\"Default_Organization\" \\"
echo "  --activationkey=\"${ACTIVATION_KEY}\""

echo

###############################################################################
# Final Summary
###############################################################################

header "02 - Foreman Katello Bootstrap API Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]
then

    ok "Foreman Katello Bootstrap API completed successfully."

else

    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

    for STEP in "${FAILED_STEPS[@]}"
    do
        error "${STEP}"
    done

fi

echo

###############################################################################
# Manual Verification
###############################################################################

header "Manual Verification Commands"

echo

echo "1. Foreman API Status:"
echo
echo "curl -ksS --user \"${FOREMAN_USER}:\${FOREMAN_PASSWORD}\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${FOREMAN_API}/status' | jq"

echo

echo "2. Products:"
echo
echo "curl -ksS --user \"${FOREMAN_USER}:\${FOREMAN_PASSWORD}\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${KATELLO_API}/organizations/${ORGANIZATION_ID}/products?per_page=100' | \\"
echo "  jq -r '.results[] | [.id,.name,.label] | @tsv'"

echo

echo "3. Repositories:"
echo
echo "curl -ksS --user \"${FOREMAN_USER}:\${FOREMAN_PASSWORD}\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${KATELLO_API}/repositories?per_page=100' | \\"
echo "  jq -r '.results[] | [.id,.name,.url,.sync_state] | @tsv'"

echo

echo "4. Content Views:"
echo
echo "curl -ksS --user \"${FOREMAN_USER}:\${FOREMAN_PASSWORD}\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${KATELLO_API}/content_views?per_page=100' | \\"
echo "  jq -r '.results[] | [.id,.name,.label] | @tsv'"

echo

echo "5. Activation Keys:"
echo
echo "curl -ksS --user \"${FOREMAN_USER}:\${FOREMAN_PASSWORD}\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${KATELLO_API}/activation_keys?per_page=100' | \\"
echo "  jq -r '.results[] | [.id,.name] | @tsv'"

echo

echo "6. Subscriptions:"
echo
echo "curl -ksS --user \"${FOREMAN_USER}:\${FOREMAN_PASSWORD}\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${KATELLO_API}/organizations/${ORGANIZATION_ID}/subscriptions?per_page=100' | \\"
echo "  jq -r '.results[] | [.id,.name,.product_name,.available,.consumed] | @tsv'"

echo

echo "7. Foreman Tasks:"
echo
echo "curl -ksS --user \"${FOREMAN_USER}:\${FOREMAN_PASSWORD}\" \\"
echo "  -H 'Accept: application/json,version=2' \\"
echo "  '${TASK_API}/tasks?per_page=100' | jq"

echo

###############################################################################
# Exit
###############################################################################

exit 0
