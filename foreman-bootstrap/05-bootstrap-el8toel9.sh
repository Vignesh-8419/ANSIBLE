#!/bin/bash
###############################################################################
# Foreman Katello Bootstrap
# EL8 -> EL9 Upgrade Bootstrap
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
    printf "%-35s ${GREEN}[OK]${NC}\n" "$1"
}

###############################################################################
# Resume Paused Tasks
###############################################################################

resume_paused_tasks() {

    header "Recovering Paused Foreman Tasks"

    local COUNT

    COUNT=$($HAMMER task list \
        --search "state = paused" 2>/dev/null | \
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
            --search "state = paused" 2>/dev/null | \
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

###############################################################################
# Create Products
###############################################################################

header "[1/6] Verifying Products"

###############################################################################
# Rocky Linux 8 Product
###############################################################################

info "Checking Product : Rocky Linux 8"

if $HAMMER product info \
    --organization "Default Organization" \
    --name "Rocky Linux 8" >/dev/null 2>&1; then

    skip "Product already exists."

else

    info "Creating Product..."

    $HAMMER product create \
        --organization "Default Organization" \
        --name "Rocky Linux 8"

    if [ $? -eq 0 ]; then
        ok "Product created."
    else
        error "Product creation failed."
        record_failure "Rocky Linux 8 Product"
    fi

fi

echo

###############################################################################
# Rocky Linux 9 Product
###############################################################################

info "Checking Product : Rocky Linux 9"

if $HAMMER product info \
    --organization "Default Organization" \
    --name "Rocky Linux 9" >/dev/null 2>&1; then

    skip "Product already exists."

else

    info "Creating Product..."

    $HAMMER product create \
        --organization "Default Organization" \
        --name "Rocky Linux 9"

    if [ $? -eq 0 ]; then
        ok "Product created."
    else
        error "Product creation failed."
        record_failure "Rocky Linux 9 Product"
    fi

fi

echo

###############################################################################
# Verification
###############################################################################

header "Products"

$HAMMER product list \
    --organization "Default Organization"

echo

###############################################################################
# Repository Creation
###############################################################################

header "[2/6] Creating Upgrade Repositories"

###############################################################################
# Rocky-08-BaseOS
###############################################################################

info "Checking Repository : Rocky-08-BaseOS"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "Rocky Linux 8" \
    --name "Rocky-08-BaseOS" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "Rocky Linux 8" \
        --name "Rocky-08-BaseOS" \
        --content-type yum \
        --url "http://192.168.253.136/repo/rocky8/BaseOS"

    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "Rocky Linux 8 -> Rocky-08-BaseOS"
    fi

fi

echo

###############################################################################
# Rocky-08-AppStream
###############################################################################

info "Checking Repository : Rocky-08-AppStream"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "Rocky Linux 8" \
    --name "Rocky-08-AppStream" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "Rocky Linux 8" \
        --name "Rocky-08-AppStream" \
        --content-type yum \
        --url "http://192.168.253.136/repo/rocky8/AppStream"

    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "Rocky Linux 8 -> Rocky-08-AppStream"
    fi

fi

echo

###############################################################################
# Rocky-08-EL8toEL9
###############################################################################

info "Checking Repository : Rocky-08-EL8toEL9"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "Rocky Linux 8" \
    --name "Rocky-08-EL8toEL9" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "Rocky Linux 8" \
        --name "Rocky-08-EL8toEL9" \
        --content-type yum \
        --url "http://192.168.253.136/repo/leapp/el8toel9"

    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "Rocky Linux 8 -> Rocky-08-EL8toEL9"
    fi

fi

echo

###############################################################################
# Rocky-09-BaseOS
###############################################################################

info "Checking Repository : Rocky-09-BaseOS"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "Rocky Linux 9" \
    --name "Rocky-09-BaseOS" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "Rocky Linux 9" \
        --name "Rocky-09-BaseOS" \
        --content-type yum \
        --url "http://192.168.253.136/repo/rocky9/BaseOS"

    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "Rocky Linux 9 -> Rocky-09-BaseOS"
    fi

fi

echo

###############################################################################
# Rocky-09-AppStream
###############################################################################

info "Checking Repository : Rocky-09-AppStream"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "Rocky Linux 9" \
    --name "Rocky-09-AppStream" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "Rocky Linux 9" \
        --name "Rocky-09-AppStream" \
        --content-type yum \
        --url "http://192.168.253.136/repo/rocky9/AppStream"

    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "Rocky Linux 9 -> Rocky-09-AppStream"
    fi

fi

echo

###############################################################################
# Repository Verification
###############################################################################

header "Repositories"

echo
info "Rocky Linux 8"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "Rocky Linux 8"

echo

info "Rocky Linux 9"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "Rocky Linux 9"

echo

###############################################################################
# Repository Synchronization
###############################################################################

header "[3/6] Synchronizing Repositories"

sync_repository() {

    PRODUCT="$1"
    REPO="$2"

    echo
    info "Checking Repository : $REPO"

    SYNC_STATUS=$(
        $HAMMER repository info \
            --organization "Default Organization" \
            --product "$PRODUCT" \
            --name "$REPO" 2>/dev/null |
        awk -F': ' '/Sync State/ {print $2}'
    )

    if echo "$SYNC_STATUS" | grep -qi running; then
        skip "Synchronization already running."
        return
    fi

    info "Starting synchronization..."

    OUTPUT=$(
        $HAMMER repository synchronize \
            --organization "Default Organization" \
            --product "$PRODUCT" \
            --name "$REPO" 2>&1
    )

    RC=$?

    echo "$OUTPUT"

    if [ $RC -eq 0 ]; then
        ok "Synchronization started."
        return
    fi

    if echo "$OUTPUT" | grep -qi "Required lock is already taken"; then

        warn "Repository lock detected."

        for TRY in 1 2 3
        do

            warn "Recovery attempt $TRY..."

            resume_paused_tasks

            sleep 5

            info "Retrying synchronization..."

            OUTPUT=$(
                $HAMMER repository synchronize \
                    --organization "Default Organization" \
                    --product "$PRODUCT" \
                    --name "$REPO" 2>&1
            )

            RC=$?

            echo "$OUTPUT"

            if [ $RC -eq 0 ]; then
                ok "Synchronization started."
                return
            fi

            if ! echo "$OUTPUT" | grep -qi "Required lock is already taken"; then
                break
            fi

        done

    fi

    error "Synchronization failed."

    record_failure "$PRODUCT -> $REPO"
}

###############################################################################
# Synchronize Rocky Linux 8 Repositories
###############################################################################

sync_repository "Rocky Linux 8" "Rocky-08-BaseOS"
sync_repository "Rocky Linux 8" "Rocky-08-AppStream"
sync_repository "Rocky Linux 8" "Rocky-08-EL8toEL9"

###############################################################################
# Synchronize Rocky Linux 9 Repositories
###############################################################################

sync_repository "Rocky Linux 9" "Rocky-09-BaseOS"
sync_repository "Rocky Linux 9" "Rocky-09-AppStream"

###############################################################################
# Verification
###############################################################################

echo

header "Repository Synchronization"

echo
info "Rocky Linux 8"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "Rocky Linux 8"

echo

info "Rocky Linux 9"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "Rocky Linux 9"

echo

###############################################################################
# Create Content View
###############################################################################

header "[4/6] Creating EL8 -> EL9 Content View"

###############################################################################
# Function : Create Content View
###############################################################################

create_content_view() {

    CV_NAME="$1"

    info "Checking Content View : $CV_NAME"

    if $HAMMER content-view info \
        --organization "Default Organization" \
        --name "$CV_NAME" >/dev/null 2>&1; then

        skip "Content View '$CV_NAME' already exists."

    else

        info "Creating Content View..."

        $HAMMER content-view create \
            --organization "Default Organization" \
            --name "$CV_NAME"

        if [ $? -eq 0 ]; then
            ok "Content View created."
        else
            error "Content View creation failed."
            record_failure "Content View : $CV_NAME"
        fi

    fi

    echo
}

###############################################################################
# Create EL8toEL9 Content View
###############################################################################

create_content_view "EL8toEL9-CV"

###############################################################################
# Function : Add Repository to Content View
###############################################################################

add_repository_to_cv() {

    CV="$1"
    PRODUCT="$2"
    REPO="$3"

    info "Checking Repository '$REPO' in '$CV'..."

    if $HAMMER content-view info \
        --organization "Default Organization" \
        --name "$CV" | grep -q "$REPO"; then

        skip "Repository already assigned."

    else

        info "Adding Repository..."

        $HAMMER content-view add-repository \
            --organization "Default Organization" \
            --name "$CV" \
            --product "$PRODUCT" \
            --repository "$REPO"

        if [ $? -eq 0 ]; then
            ok "Repository added."
        else
            error "Failed to add repository."
            record_failure "$REPO -> $CV"
        fi

    fi

    echo
}

###############################################################################
# Add Rocky Linux 8 Repositories
###############################################################################

add_repository_to_cv \
    "EL8toEL9-CV" \
    "Rocky Linux 8" \
    "Rocky-08-BaseOS"

add_repository_to_cv \
    "EL8toEL9-CV" \
    "Rocky Linux 8" \
    "Rocky-08-AppStream"

add_repository_to_cv \
    "EL8toEL9-CV" \
    "Rocky Linux 8" \
    "Rocky-08-EL8toEL9"

###############################################################################
# Add Rocky Linux 9 Repositories
###############################################################################

add_repository_to_cv \
    "EL8toEL9-CV" \
    "Rocky Linux 9" \
    "Rocky-09-BaseOS"

add_repository_to_cv \
    "EL8toEL9-CV" \
    "Rocky Linux 9" \
    "Rocky-09-AppStream"

###############################################################################
# Function : Publish Content View
###############################################################################

publish_cv() {

    CV="$1"

    info "Checking Content View : $CV"

    OUTPUT=$(
    $HAMMER content-view publish \
        --organization "Default Organization" \
        --name "$CV" \
        --description "Bootstrap Publish $(date '+%F %T')" 2>&1
    )

    RC=$?

    echo "$OUTPUT"

    if [ $RC -eq 0 ]; then
        ok "Content View published."
        return
    fi

    if echo "$OUTPUT" | grep -qi "Required lock is already taken"; then

        warn "Publish task locked."

        for TRY in 1 2 3
        do

            warn "Recovery attempt $TRY..."

            LOCK_TASK=$(echo "$OUTPUT" | grep -oE '[0-9a-f-]{36}' | head -1)

            if [ -n "$LOCK_TASK" ]; then

                warn "Cancelling conflicting task $LOCK_TASK"

                $HAMMER task cancel \
                    --search "id = $LOCK_TASK" >/dev/null 2>&1 || true

                sleep 10

            else

                resume_paused_tasks

            fi

            info "Retrying publish..."

            OUTPUT=$(
                $HAMMER content-view publish \
                    --organization "Default Organization" \
                    --name "$CV" \
                    --description "Bootstrap Publish $(date '+%F %T')" 2>&1
            )

            RC=$?

            echo "$OUTPUT"

            if [ $RC -eq 0 ]; then
                ok "Content View published."
                return
            fi

            if ! echo "$OUTPUT" | grep -qi "Required lock is already taken"; then
                break
            fi

        done

    fi

    error "Content View publish failed."

    record_failure "Publish : $CV"

}

###############################################################################
# Publish EL8toEL9 Content View
###############################################################################

publish_cv "EL8toEL9-CV"

###############################################################################
# Verification
###############################################################################

header "EL8toEL9 Content View"

$HAMMER content-view info \
    --organization "Default Organization" \
    --name "EL8toEL9-CV"

echo

$HAMMER content-view version list \
    --organization "Default Organization" \
    --content-view "EL8toEL9-CV"

echo

###############################################################################
# Create Activation Key
###############################################################################

header "[5/6] Creating Activation Key"

create_activation_key() {

    KEY="$1"
    CV="$2"

    info "Checking Activation Key : $KEY"

    if $HAMMER activation-key info \
        --organization "Default Organization" \
        --name "$KEY" >/dev/null 2>&1; then

        info "Activation Key already exists. Updating Content View..."

        $HAMMER activation-key update \
            --organization "Default Organization" \
            --name "$KEY" \
            --content-view "$CV" \
            --lifecycle-environment "Library"

        if [ $? -eq 0 ]; then
            ok "Activation Key updated."
        else
            error "Activation Key update failed."
            record_failure "Activation Key : $KEY"
        fi

    else

        info "Creating Activation Key..."

        $HAMMER activation-key create \
            --organization "Default Organization" \
            --name "$KEY" \
            --lifecycle-environment "Library" \
            --content-view "$CV"

        if [ $? -eq 0 ]; then
            ok "Activation Key created."
        else
            error "Activation Key creation failed."
            record_failure "Activation Key : $KEY"
        fi

    fi

    echo
}

###############################################################################
# Create EL8->EL9 Activation Key
###############################################################################

create_activation_key "el8toel9-key" "EL8toEL9-CV"

###############################################################################
# Attach Subscriptions
###############################################################################

header "Attaching Subscriptions"

ROCKY8_SUB_ID=$(
$HAMMER subscription list \
    --organization "Default Organization" |
awk -F'|' '$3 ~ /Rocky Linux 8/ {gsub(/ /,"",$1); print $1}'
)

ROCKY9_SUB_ID=$(
$HAMMER subscription list \
    --organization "Default Organization" |
awk -F'|' '$3 ~ /Rocky Linux 9/ {gsub(/ /,"",$1); print $1}'
)

echo "ROCKY8_SUB_ID=$ROCKY8_SUB_ID"
echo "ROCKY9_SUB_ID=$ROCKY9_SUB_ID"
echo

###############################################################################
# Attach Rocky Linux 8 Subscription
###############################################################################

info "Attaching Rocky Linux 8 subscription..."

OUTPUT=$(
$HAMMER activation-key add-subscription \
    --organization "Default Organization" \
    --name "el8toel9-key" \
    --subscription-id "$ROCKY8_SUB_ID" 2>&1
)

echo "$OUTPUT"

if echo "$OUTPUT" | grep -qi "already"; then
    skip "Rocky Linux 8 subscription already attached."
elif [ $? -eq 0 ]; then
    ok "Rocky Linux 8 subscription attached."
else
    error "Subscription attachment failed."
    record_failure "el8toel9-key -> Rocky Linux 8"
fi

echo

###############################################################################
# Attach Rocky Linux 9 Subscription
###############################################################################

info "Attaching Rocky Linux 9 subscription..."

OUTPUT=$(
$HAMMER activation-key add-subscription \
    --organization "Default Organization" \
    --name "el8toel9-key" \
    --subscription-id "$ROCKY9_SUB_ID" 2>&1
)

echo "$OUTPUT"

if echo "$OUTPUT" | grep -qi "already"; then
    skip "Rocky Linux 9 subscription already attached."
elif [ $? -eq 0 ]; then
    ok "Rocky Linux 9 subscription attached."
else
    error "Subscription attachment failed."
    record_failure "el8toel9-key -> Rocky Linux 9"
fi

###############################################################################
# Verification
###############################################################################

header "[6/6] Verification"

echo
header "Activation Keys"

$HAMMER activation-key list \
    --organization "Default Organization"

echo
header "EL8toEL9-CV"

$HAMMER content-view info \
    --organization "Default Organization" \
    --name "EL8toEL9-CV"

echo
header "Activation Key Details"

$HAMMER activation-key info \
    --organization "Default Organization" \
    --name "el8toel9-key"

###############################################################################
# Registration Command
###############################################################################

echo
header "Registration Command"

echo "subscription-manager register \\"
echo "  --org=\"Default_Organization\" \\"
echo "  --activationkey=\"el8toel9-key\""

echo

###############################################################################
# Summary
###############################################################################

header "EL8 -> EL9 Bootstrap Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
    ok "EL8 -> EL9 Upgrade Bootstrap completed successfully."
else
    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

    for step in "${FAILED_STEPS[@]}"; do
        error "$step"
    done
fi

echo
