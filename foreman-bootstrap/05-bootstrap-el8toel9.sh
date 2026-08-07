#!/bin/bash
###############################################################################
# 05 - Foreman Katello Bootstrap
# EL8 -> EL9 Upgrade Bootstrap
# Supports Rocky Linux 9.2 and Rocky Linux 9.8
###############################################################################

set +e

FAILED_STEPS=()

record_failure() {
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

info() {
    echo -e "${CYAN}$1${NC}"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

header() {
    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

summary_ok() {
    printf "%-40s ${GREEN}[OK]${NC}\n" "$1"
}

header "05 - Foreman Katello Bootstrap"

echo

###############################################################################
# Resume Paused Tasks
###############################################################################

resume_paused_tasks() {

    header "Recovering Paused Foreman Tasks"

    local COUNT

    COUNT=$($HAMMER task list \
        --search "state = paused" 2>/dev/null |
        grep -c paused || true)

    if [ "$COUNT" -eq 0 ]; then
        ok "No paused tasks found."
        return 0
    fi

    warn "Found $COUNT paused task(s)."

    $HAMMER task resume \
        --search "state = paused"

    for i in {1..6}; do

        COUNT=$($HAMMER task list \
            --search "state = paused" 2>/dev/null |
            grep -c paused || true)

        if [ "$COUNT" -eq 0 ]; then
            ok "Paused tasks cleared."
            return 0
        fi

        warn "$COUNT paused task(s) still remain. Waiting..."

        sleep 10

    done

    warn "Some paused tasks still remain."
    warn "Continuing because the repository lock may already be released."

    return 0
}

###############################################################################
# Variables
###############################################################################

FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"

HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"

TARGET_VERSION="${TARGET_VERSION:-9.8}"

case "$TARGET_VERSION" in

    9.2)

        ROCKY_PRODUCT="Rocky Linux 8"

        EL8TOEL9_REPO_NAME="Rocky-08-ELevate-9.2"
        EL8TOEL9_REPO_URL="http://192.168.253.136/repo/leapp/9.2/el8toel9"

        CONTENT_VIEW="Rocky9.2-CV"
        ACTIVATION_KEY="rocky9.2-key"

        ;;

    9.8)

        ROCKY_PRODUCT="Rocky Linux 8"

        EL8TOEL9_REPO_NAME="Rocky-08-ELevate-9.8"
        EL8TOEL9_REPO_URL="http://192.168.253.136/repo/leapp/9/el8toel9"

        CONTENT_VIEW="Rocky9.8-CV"
        ACTIVATION_KEY="rocky9.8-key"

        ;;

    *)

        echo "Unsupported TARGET_VERSION: ${TARGET_VERSION}"
        exit 1

        ;;

esac

echo
info "Selected Upgrade Target"

echo "  Rocky Version : ${TARGET_VERSION}"
echo "  Product       : ${ROCKY_PRODUCT}"
echo "  ELevate Repo  : ${EL8TOEL9_REPO_NAME}"
echo "  Content View  : ${CONTENT_VIEW}"
echo "  ActivationKey : ${ACTIVATION_KEY}"

echo

###############################################################################
# [1/6] Verify Product
###############################################################################

header "[1/6] Verifying Product"

info "Checking Product : ${ROCKY_PRODUCT}"

if $HAMMER product info \
    --organization "Default Organization" \
    --name "${ROCKY_PRODUCT}" >/dev/null 2>&1; then

    skip "Product already exists."

else

    info "Creating Product..."

    $HAMMER product create \
        --organization "Default Organization" \
        --name "${ROCKY_PRODUCT}"

    if [ $? -eq 0 ]; then
        ok "Product created."
    else
        error "Product creation failed."
        record_failure "${ROCKY_PRODUCT}"
    fi

fi

echo

header "Products"

$HAMMER product list \
    --organization "Default Organization"

echo

###############################################################################
# [3/6] Synchronizing Repositories
###############################################################################

header "[3/6] Synchronizing Repositories"

sync_repository() {

    PRODUCT="$1"
    REPO="$2"

    echo
    info "Checking Repository : ${REPO}"

    SYNC_STATUS=$(
        $HAMMER repository info \
            --organization "Default Organization" \
            --product "${PRODUCT}" \
            --name "${REPO}" 2>/dev/null |
        awk -F': ' '/Sync State/ {print $2}'
    )

    if echo "${SYNC_STATUS}" | grep -qi running; then
        skip "Synchronization already running."
        return
    fi

    info "Starting synchronization..."

    OUTPUT=$(
        $HAMMER repository synchronize \
            --organization "Default Organization" \
            --product "${PRODUCT}" \
            --name "${REPO}" 2>&1
    )

    RC=$?

    echo "${OUTPUT}"

    if [ ${RC} -eq 0 ]; then
        ok "Synchronization started."
        return
    fi

    if echo "${OUTPUT}" | grep -qi "Required lock is already taken"; then

        warn "Repository lock detected."

        for TRY in 1 2 3
        do

            warn "Recovery attempt ${TRY}..."

            resume_paused_tasks

            sleep 5

            info "Retrying synchronization..."

            OUTPUT=$(
                $HAMMER repository synchronize \
                    --organization "Default Organization" \
                    --product "${PRODUCT}" \
                    --name "${REPO}" 2>&1
            )

            RC=$?

            echo "${OUTPUT}"

            if [ ${RC} -eq 0 ]; then
                ok "Synchronization started."
                return
            fi

            if ! echo "${OUTPUT}" | grep -qi "Required lock is already taken"; then
                break
            fi

        done

    fi

    error "Synchronization failed."

    record_failure "${PRODUCT} -> ${REPO}"
}

###############################################################################
# Synchronize Rocky Linux 8 Repositories
###############################################################################

sync_repository "${ROCKY_PRODUCT}" "Rocky8-BaseOS"

sync_repository "${ROCKY_PRODUCT}" "Rocky8-AppStream"

sync_repository "${ROCKY_PRODUCT}" "${EL8TOEL9_REPO_NAME}"

###############################################################################
# Verification
###############################################################################

echo

header "Repository Synchronization"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "${ROCKY_PRODUCT}"

echo

###############################################################################
# [4/6] Creating Content View
###############################################################################

header "[4/6] Creating Content View"

###############################################################################
# Function : Create Content View
###############################################################################

create_content_view() {

    local CV_NAME="$1"

    info "Checking Content View : ${CV_NAME}"

    if $HAMMER content-view info \
        --organization "Default Organization" \
        --name "${CV_NAME}" >/dev/null 2>&1; then

        skip "Content View already exists."

    else

        info "Creating Content View..."

        $HAMMER content-view create \
            --organization "Default Organization" \
            --name "${CV_NAME}"

        if [ $? -eq 0 ]; then
            ok "Content View created."
        else
            error "Content View creation failed."
            record_failure "${CV_NAME}"
        fi

    fi

    echo
}

###############################################################################
# Create Selected Content View
###############################################################################

create_content_view "${CONTENT_VIEW}"

###############################################################################
# Function : Add Repository to Content View
###############################################################################

add_repository_to_cv() {

    local CV="$1"
    local PRODUCT="$2"
    local REPO="$3"

    info "Checking Repository '${REPO}' in '${CV}'..."

    if $HAMMER content-view info \
        --organization "Default Organization" \
        --name "${CV}" |
        grep -q "${REPO}"; then

        skip "Repository already assigned."

    else

        info "Adding Repository..."

        $HAMMER content-view add-repository \
            --organization "Default Organization" \
            --name "${CV}" \
            --product "${PRODUCT}" \
            --repository "${REPO}"

        if [ $? -eq 0 ]; then
            ok "Repository added."
        else
            error "Failed to add repository."
            record_failure "${REPO} -> ${CV}"
        fi

    fi

    echo
}

###############################################################################
# Add Rocky Linux 8 Repositories
###############################################################################

add_repository_to_cv \
    "${CONTENT_VIEW}" \
    "${ROCKY_PRODUCT}" \
    "Rocky8-BaseOS"

add_repository_to_cv \
    "${CONTENT_VIEW}" \
    "${ROCKY_PRODUCT}" \
    "Rocky8-AppStream"

add_repository_to_cv \
    "${CONTENT_VIEW}" \
    "${ROCKY_PRODUCT}" \
    "${EL8TOEL9_REPO_NAME}"

###############################################################################
# Function : Publish Content View
###############################################################################

publish_cv() {

    local CV="$1"

    info "Publishing Content View : ${CV}"

    OUTPUT=$(
        $HAMMER content-view publish \
            --organization "Default Organization" \
            --name "${CV}" \
            --description "Bootstrap Publish $(date '+%F %T')" 2>&1
    )

    RC=$?

    echo "${OUTPUT}"

    if [ ${RC} -eq 0 ]; then
        ok "Content View published."
        return
    fi

    if echo "${OUTPUT}" | grep -qi "Required lock is already taken"; then

        warn "Publish task locked."

        for TRY in 1 2 3
        do

            warn "Recovery attempt ${TRY}..."

            resume_paused_tasks

            sleep 5

            info "Retrying publish..."

            OUTPUT=$(
                $HAMMER content-view publish \
                    --organization "Default Organization" \
                    --name "${CV}" \
                    --description "Bootstrap Publish $(date '+%F %T')" 2>&1
            )

            RC=$?

            echo "${OUTPUT}"

            if [ ${RC} -eq 0 ]; then
                ok "Content View published."
                return
            fi

            if ! echo "${OUTPUT}" | grep -qi "Required lock is already taken"; then
                break
            fi

        done

    fi

    error "Content View publish failed."

    record_failure "Publish ${CV}"
}

###############################################################################
# Publish Selected Content View
###############################################################################

publish_cv "${CONTENT_VIEW}"

###############################################################################
# Verification
###############################################################################

header "${CONTENT_VIEW}"

$HAMMER content-view info \
    --organization "Default Organization" \
    --name "${CONTENT_VIEW}"

echo

$HAMMER content-view version list \
    --organization "Default Organization" \
    --content-view "${CONTENT_VIEW}"

echo

###############################################################################
# [5/6] Creating Activation Key
###############################################################################

header "[5/6] Creating Activation Key"

###############################################################################
# Function : Create Activation Key
###############################################################################

create_activation_key() {

    KEY="$1"
    CV="$2"

    info "Checking Activation Key : ${KEY}"

    if $HAMMER activation-key info \
        --organization "Default Organization" \
        --name "${KEY}" >/dev/null 2>&1; then

        info "Activation Key already exists. Updating..."

        $HAMMER activation-key update \
            --organization "Default Organization" \
            --name "${KEY}" \
            --content-view "${CV}" \
            --lifecycle-environment "Library"

        if [ $? -eq 0 ]; then
            ok "Activation Key updated."
        else
            error "Activation Key update failed."
            record_failure "${KEY}"
        fi

    else

        info "Creating Activation Key..."

        $HAMMER activation-key create \
            --organization "Default Organization" \
            --name "${KEY}" \
            --lifecycle-environment "Library" \
            --content-view "${CV}"

        if [ $? -eq 0 ]; then
            ok "Activation Key created."
        else
            error "Activation Key creation failed."
            record_failure "${KEY}"
        fi

    fi

    echo
}

###############################################################################
# Create Selected Activation Key
###############################################################################

create_activation_key \
    "${ACTIVATION_KEY}" \
    "${CONTENT_VIEW}"

###############################################################################
# Attach Subscription
###############################################################################

header "Attaching Subscription"

ROCKY_SUB_ID=$(
$HAMMER subscription list \
    --organization "Default Organization" |
awk -F'|' '$3 ~ /Rocky Linux 8/ {gsub(/ /,"",$1); print $1}'
)

echo "ROCKY_SUB_ID=${ROCKY_SUB_ID}"
echo

info "Attaching Rocky Linux 8 subscription..."

OUTPUT=$(
$HAMMER activation-key add-subscription \
    --organization "Default Organization" \
    --name "${ACTIVATION_KEY}" \
    --subscription-id "${ROCKY_SUB_ID}" 2>&1
)

RC=$?

echo "${OUTPUT}"

if echo "${OUTPUT}" | grep -qi "already"; then

    skip "Subscription already attached."

elif echo "${OUTPUT}" | grep -qi "Subscription added"; then

    ok "Subscription attached."

elif [ ${RC} -eq 0 ]; then

    ok "Subscription attached."

else

    error "Subscription attachment failed."

    record_failure "${ACTIVATION_KEY}"

fi

echo

###############################################################################
# [6/6] Verification
###############################################################################

header "[6/6] Verification"

echo

header "Activation Keys"

$HAMMER activation-key list \
    --organization "Default Organization"

echo

header "${CONTENT_VIEW}"

$HAMMER content-view info \
    --organization "Default Organization" \
    --name "${CONTENT_VIEW}"

echo

header "Activation Key Details"

$HAMMER activation-key info \
    --organization "Default Organization" \
    --name "${ACTIVATION_KEY}"

echo

###############################################################################
# Registration Command
###############################################################################

header "Registration Command"

echo

echo "subscription-manager register \\"
echo "  --org=\"Default_Organization\" \\"
echo "  --activationkey=\"${ACTIVATION_KEY}\""

echo

###############################################################################
# Selected Upgrade Configuration
###############################################################################

header "Selected Upgrade Configuration"

echo "TARGET_VERSION : ${TARGET_VERSION}"
echo "Product        : ${ROCKY_PRODUCT}"
echo "Repository     : ${EL8TOEL9_REPO_NAME}"
echo "Content View   : ${CONTENT_VIEW}"
echo "Activation Key : ${ACTIVATION_KEY}"

echo

###############################################################################
# Bootstrap Summary
###############################################################################

header "05 - EL8 -> EL9 Bootstrap Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then

    ok "EL8 -> EL9 Upgrade Bootstrap completed successfully."

else

    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

    for step in "${FAILED_STEPS[@]}"; do
        error "$step"
    done

fi

echo

###############################################################################
# End of Script
###############################################################################

ok "Bootstrap finished."

exit 0
