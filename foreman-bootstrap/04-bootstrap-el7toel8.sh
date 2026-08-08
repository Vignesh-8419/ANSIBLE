#!/bin/bash
###############################################################################
# Foreman Katello Bootstrap
# EL7 -> EL8 Upgrade Bootstrap
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

###############################################################################
# Variables
###############################################################################

FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"

HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"

ORG="Default Organization"
LOCATION="Default Location"

PRODUCT_NAME="CentOS 7"

###############################################################################
# Repository Configuration
###############################################################################

BASE_REPO="CentOS-07-BaseOS"
BASE_REPO_ID="1"
BASE_URL="http://192.168.253.136/repo/centos"

UPDATE_REPO="CentOS-07-Updates"
UPDATE_REPO_ID="2"
UPDATE_URL="http://192.168.253.136/repo/installed_rhel7"

ELEVATE_REPO="CentOS-07-ELevate"
ELEVATE_REPO_ID="25"
ELEVATE_URL="http://192.168.253.136/repo/elevate"

CONTENT_VIEW="EL7toEL8-CV"
ACTIVATION_KEY="el7toel8-key"

###############################################################################
# Resume Paused Tasks
###############################################################################

resume_paused_tasks()
{
    header "Recovering Paused Foreman Tasks"

    local COUNT

    COUNT=$(
        $HAMMER task list \
            --search "state = paused" 2>/dev/null |
            grep -c paused || true
    )

    if [ "$COUNT" -eq 0 ]; then
        ok "No paused tasks found."
        return 0
    fi

    warn "Found ${COUNT} paused task(s)."

    $HAMMER task resume \
        --search "state = paused"

    for i in {1..6}; do

        COUNT=$(
            $HAMMER task list \
                --search "state = paused" 2>/dev/null |
                grep -c paused || true
        )

        if [ "$COUNT" -eq 0 ]; then
            ok "Paused tasks cleared."
            return 0
        fi

        warn "${COUNT} paused task(s) still remain. Waiting..."
        sleep 10
    done

    warn "Some paused tasks still remain."
    warn "Continuing because the repository lock may already be released."

    return 0
}

###############################################################################
# Create Product
###############################################################################

create_product()
{
    header "Creating Product"

    if $HAMMER product list \
        --organization "$ORG" |
        grep -q "$PRODUCT_NAME"
    then

        skip "Product ${PRODUCT_NAME} already exists."

    else

        echo "Creating Product ${PRODUCT_NAME}..."

        $HAMMER product create \
            --organization "$ORG" \
            --name "$PRODUCT_NAME"

        if [ $? -eq 0 ]; then
            ok "Product created."
        else
            error "Product creation failed."
            record_failure "Product ${PRODUCT_NAME}"
        fi
    fi
}

###############################################################################
# Create Repository
###############################################################################

create_repo()
{
    REPO_NAME="$1"
    REPO_URL="$2"
    REPO_TYPE="$3"

    echo
    echo "Checking Repository : ${REPO_NAME}"

    if $HAMMER repository list \
        --organization "$ORG" \
        --product "$PRODUCT_NAME" |
        grep -q "$REPO_NAME"
    then

        skip "${REPO_NAME} already exists."

    else

        echo "Creating ${REPO_NAME}..."

        $HAMMER repository create \
            --organization "$ORG" \
            --product "$PRODUCT_NAME" \
            --name "$REPO_NAME" \
            --content-type "$REPO_TYPE" \
            --url "$REPO_URL"

        if [ $? -eq 0 ]; then
            ok "${REPO_NAME} created."
        else
            error "${REPO_NAME} creation failed."
            record_failure "${REPO_NAME}"
        fi
    fi
}

###############################################################################
# Update Repository URL
###############################################################################

update_repository_url()
{
    REPO_NAME="$1"
    REPO_URL="$2"

    echo
    echo "Updating Repository URL : ${REPO_NAME}"

    $HAMMER repository update \
        --organization "$ORG" \
        --product "$PRODUCT_NAME" \
        --name "$REPO_NAME" \
        --url "$REPO_URL"

    if [ $? -eq 0 ]; then
        ok "${REPO_NAME} URL updated."
    else
        error "${REPO_NAME} URL update failed."
        record_failure "${REPO_NAME} URL"
    fi
}

###############################################################################
# Create EL7 Repositories
###############################################################################

create_el7_repositories()
{
    header "Creating EL7 Repositories"

    create_repo \
        "${BASE_REPO}" \
        "${BASE_URL}" \
        "yum"

    create_repo \
        "${UPDATE_REPO}" \
        "${UPDATE_URL}" \
        "yum"

    create_repo \
        "${ELEVATE_REPO}" \
        "${ELEVATE_URL}" \
        "yum"

    header "Updating Existing Repository URLs"

    update_repository_url \
        "${BASE_REPO}" \
        "${BASE_URL}"

    update_repository_url \
        "${UPDATE_REPO}" \
        "${UPDATE_URL}"

    update_repository_url \
        "${ELEVATE_REPO}" \
        "${ELEVATE_URL}"
}

###############################################################################
# Sync Repository
###############################################################################

sync_repository()
{
    REPO_NAME="$1"

    echo
    echo "Checking Sync Status : ${REPO_NAME}"

    STATUS=$(
        $HAMMER repository info \
            --organization "$ORG" \
            --product "$PRODUCT_NAME" \
            --name "$REPO_NAME" 2>/dev/null |
            grep -Ei "Sync State|Last Sync|Sync Status" |
            awk -F':' '{print $2}' |
            xargs
    )

    if echo "$STATUS" | grep -qi "Complete"; then

        skip "${REPO_NAME} already synced."
        return 0
    fi

    echo "Starting sync : ${REPO_NAME}"

    $HAMMER repository synchronize \
        --organization "$ORG" \
        --product "$PRODUCT_NAME" \
        --name "$REPO_NAME"

    if [ $? -eq 0 ]; then
        ok "${REPO_NAME} sync completed."
    else
        error "${REPO_NAME} sync failed."
        record_failure "Sync ${REPO_NAME}"
    fi
}

###############################################################################
# Sync EL7 Repositories
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

publish_content_view()
{
    header "Checking Content View"

    if $HAMMER content-view list \
        --organization "$ORG" |
        grep -q "$CONTENT_VIEW"
    then

        skip "Content View ${CONTENT_VIEW} already exists."

    else

        echo "Creating Content View ${CONTENT_VIEW}..."

        $HAMMER content-view create \
            --organization "$ORG" \
            --name "$CONTENT_VIEW"

        if [ $? -eq 0 ]; then
            ok "Content View created."
        else
            error "Content View creation failed."
            record_failure "$CONTENT_VIEW"
        fi
    fi
}

###############################################################################
# Add Repository To Content View
###############################################################################

add_repository_to_cv()
{
    REPO_NAME="$1"
    REPO_ID="$2"

    echo
    echo "Checking Content View Repository : ${REPO_NAME}"

    info "Repository ID : ${REPO_ID}"

    ###########################################################################
    # Check whether repository is already associated
    ###########################################################################

    EXISTING=$(
        $HAMMER content-view info \
            --organization "$ORG" \
            --name "$CONTENT_VIEW" 2>/dev/null |
            grep -F "$REPO_NAME" || true
    )

    if [ -n "$EXISTING" ]; then

        skip "${REPO_NAME} already added to ${CONTENT_VIEW}."

        return 0
    fi

    ###########################################################################
    # Add repository
    ###########################################################################

    echo "Adding ${REPO_NAME} to ${CONTENT_VIEW}..."

    $HAMMER content-view add-repository \
        --organization "$ORG" \
        --name "$CONTENT_VIEW" \
        --repository-id "$REPO_ID"

    if [ $? -eq 0 ]; then

        ok "${REPO_NAME} added to ${CONTENT_VIEW}."

        return 0

    else

        error "Failed adding ${REPO_NAME} to ${CONTENT_VIEW}"

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

    add_repository_to_cv \
        "${BASE_REPO}" \
        "${BASE_REPO_ID}"

    add_repository_to_cv \
        "${UPDATE_REPO}" \
        "${UPDATE_REPO_ID}"

    add_repository_to_cv \
        "${ELEVATE_REPO}" \
        "${ELEVATE_REPO_ID}"
}

###############################################################################
# Check Content View Repositories
###############################################################################

verify_content_view()
{
    header "Verifying Content View"

    local FAILED=0

    for REPO in \
        "${BASE_REPO}" \
        "${UPDATE_REPO}" \
        "${ELEVATE_REPO}"
    do

        if $HAMMER content-view info \
            --organization "$ORG" \
            --name "$CONTENT_VIEW" 2>/dev/null |
            grep -Fq "$REPO"
        then

            ok "${REPO} is associated with ${CONTENT_VIEW}."

        else

            error "${REPO} is NOT associated with ${CONTENT_VIEW}."

            FAILED=1
        fi

    done

    if [ "$FAILED" -eq 1 ]; then

        error "Content View repository verification failed."

        record_failure "Content View repository verification"

        return 1
    fi

    ok "All EL7 repositories are associated with ${CONTENT_VIEW}."

    return 0
}

###############################################################################
# Publish Content View Version
###############################################################################

publish_content_view_version()
{
    header "Publishing Content View Version"

    ###########################################################################
    # Verify repositories before publishing
    ###########################################################################

    verify_content_view

    if [ $? -ne 0 ]; then

        error "Repositories are not correctly associated."

        error "Content View will NOT be published."

        record_failure "${CONTENT_VIEW} publish blocked"

        return 1
    fi

    ###########################################################################
    # Check for an active publish task
    ###########################################################################

    ACTIVE_TASK=$(
        $HAMMER task list \
            --search "name ~ Publish and state = running" 2>/dev/null |
            grep -F "$CONTENT_VIEW" || true
    )

    if [ -n "$ACTIVE_TASK" ]; then

        skip "Content View ${CONTENT_VIEW} already has an active publish task."

        return 0
    fi

    ###########################################################################
    # Always publish a new version after repository association
    ###########################################################################

    echo "Publishing new version of ${CONTENT_VIEW}..."

    $HAMMER content-view publish \
        --organization "$ORG" \
        --name "$CONTENT_VIEW" \
        --async

    if [ $? -eq 0 ]; then

        ok "Content View ${CONTENT_VIEW} publish started."

    else

        error "Content View ${CONTENT_VIEW} publish failed."

        record_failure "${CONTENT_VIEW} publish"

        return 1
    fi
}

###############################################################################
# Create Activation Key
###############################################################################

create_activation_key()
{
    header "Creating Activation Key"

    if $HAMMER activation-key list \
        --organization "$ORG" |
        grep -q "$ACTIVATION_KEY"
    then

        skip "Activation Key ${ACTIVATION_KEY} already exists."

    else

        echo "Creating Activation Key ${ACTIVATION_KEY}..."

        $HAMMER activation-key create \
            --organization "$ORG" \
            --name "$ACTIVATION_KEY" \
            --content-view "$CONTENT_VIEW" \
            --lifecycle-environment "Library"

        if [ $? -eq 0 ]; then

            ok "Activation Key created."

        else

            error "Activation Key creation failed."

            record_failure "${ACTIVATION_KEY}"
        fi
    fi
}

###############################################################################
# Configure Activation Key
###############################################################################

configure_activation_key()
{
    header "Configuring Activation Key"

    echo "Activation Key : ${ACTIVATION_KEY}"
    echo "Content View   : ${CONTENT_VIEW}"

    ###########################################################################
    # Do not use repository names as content labels here.
    #
    # First show current activation-key content configuration.
    ###########################################################################

    $HAMMER activation-key content \
        --organization "$ORG" \
        --name "$ACTIVATION_KEY"

    if [ $? -eq 0 ]; then
        ok "Activation Key content configuration displayed."
    else
        warn "Unable to display Activation Key content configuration."
    fi
}

###############################################################################
# Create Bootstrap Command
###############################################################################

generate_bootstrap_command()
{
    header "Generating Host Bootstrap Command"

    echo
    echo "Run this command on CentOS 7 systems:"
    echo

    echo "------------------------------------------------------------"

    echo "subscription-manager register \\"
    echo "--org=\"${ORG}\" \\"
    echo "--activationkey=\"${ACTIVATION_KEY}\""

    echo "------------------------------------------------------------"
}

###############################################################################
# Summary
###############################################################################

summary()
{
    header "EL7 To EL8 Bootstrap Summary"

    echo
    echo "Product"
    echo "------------------------------------------------------------"

    $HAMMER product list \
        --organization "$ORG" |
        grep "$PRODUCT_NAME"

    echo
    echo "Repositories"
    echo "------------------------------------------------------------"

    $HAMMER repository list \
        --organization "$ORG" \
        --product "$PRODUCT_NAME"

    echo
    echo "Content View"
    echo "------------------------------------------------------------"

    $HAMMER content-view list \
        --organization "$ORG" |
        grep "$CONTENT_VIEW"

    echo
    echo "Content View Repositories"
    echo "------------------------------------------------------------"

    $HAMMER content-view info \
        --organization "$ORG" \
        --name "$CONTENT_VIEW"

    echo
    echo "Activation Key"
    echo "------------------------------------------------------------"

    $HAMMER activation-key list \
        --organization "$ORG" |
        grep "$ACTIVATION_KEY"

    echo
    echo "Migration Configuration"
    echo "------------------------------------------------------------"

    echo "Product             : ${PRODUCT_NAME}"
    echo "Content View        : ${CONTENT_VIEW}"
    echo "Activation Key      : ${ACTIVATION_KEY}"

    echo
    echo "Repositories        :"
    echo "  - ${BASE_REPO} [ID ${BASE_REPO_ID}]"
    echo "  - ${UPDATE_REPO} [ID ${UPDATE_REPO_ID}]"
    echo "  - ${ELEVATE_REPO} [ID ${ELEVATE_REPO_ID}]"
}

###############################################################################
# Main
###############################################################################

header "04 - Foreman Katello Bootstrap EL7 To EL8"

resume_paused_tasks

create_product

create_el7_repositories

sync_el7_repositories

publish_content_view

configure_content_view

publish_content_view_version

create_activation_key

configure_activation_key

generate_bootstrap_command

summary

header "04 - EL7 To EL8 Bootstrap Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then

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
