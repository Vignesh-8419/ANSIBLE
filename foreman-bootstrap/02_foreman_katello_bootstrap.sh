#!/bin/bash
###############################################################################
# Foreman PXE Provisioning + Katello Bootstrap
# CentOS 7 & Rocky Linux 8.10
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
    warn "Continuing because the required repository lock may already be released."
    
    return 0
}


header "[1/6] Creating Katello Products"


###############################################################################
# Rocky Linux 8 Product
###############################################################################

info "Checking Product : Rocky Linux 8"

if $HAMMER product info \
    --organization "Default Organization" \
    --name "Rocky Linux 8" >/dev/null 2>&1; then

    skip "Product 'Rocky Linux 8' already exists."

else

    info "Creating Product : Rocky Linux 8"

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
# CentOS 7 Product
###############################################################################

info "Checking Product : CentOS 7"

if $HAMMER product info \
    --organization "Default Organization" \
    --name "CentOS 7" >/dev/null 2>&1; then

    skip "Product 'CentOS 7' already exists."

else

    info "Creating Product : CentOS 7"

    $HAMMER product create \
        --organization "Default Organization" \
        --name "CentOS 7"
    
    if [ $? -eq 0 ]; then
        ok "Product created."
    else
        error "Product creation failed."
        record_failure "CentOS 7 Product"
    fi

fi

echo

###############################################################################
# Rocky 9 Product
###############################################################################

info "Checking Product : Rocky Linux 9"

if $HAMMER product info \
    --organization "Default Organization" \
    --name "Rocky Linux 9" >/dev/null 2>&1; then

    skip "Product 'Rocky Linux 9' already exists."

else

    info "Creating Product : Rocky Linux 9"

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
# 2. Create Repositories
###############################################################################

header "[2/6] Creating Repositories"

###############################################################################
# CentOS 7 Repositories
###############################################################################

header "Creating CentOS 7 Repositories"


###############################################################################
# CentOS-07-BaseOS
###############################################################################

info "Checking Repository : CentOS-07-BaseOS"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "CentOS 7" \
    --name "CentOS-07-BaseOS" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "CentOS 7" \
        --name "CentOS-07-BaseOS" \
        --content-type yum \
        --url "http://192.168.253.136/repo/centos/"

    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "$PRODUCT -> $REPO"
    fi

fi

echo

###############################################################################
# CentOS-07-Updates
###############################################################################

info "Checking Repository : CentOS-07-Updates"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "CentOS 7" \
    --name "CentOS-07-Updates" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "CentOS 7" \
        --name "CentOS-07-Updates" \
        --content-type yum \
        --url "http://192.168.253.136/repo/installed_rhel7/"

    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "$PRODUCT -> $REPO"
    fi

fi

echo

###############################################################################
# Rocky Linux 8 Repositories
###############################################################################


header "Creating Rocky Linux 8 Repositories"


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
        record_failure "$PRODUCT -> $REPO"
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
# Rocky-08-RHEL-Installed
###############################################################################

info "Checking Repository : Rocky-08-RHEL-Installed"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "Rocky Linux 8" \
    --name "Rocky-08-RHEL-Installed" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "Rocky Linux 8" \
        --name "Rocky-08-RHEL-Installed" \
        --content-type yum \
        --url "http://192.168.253.136/repo/installed_rhel8"

    
    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "Rocky Linux 8 -> Rocky-08-RHEL-Installed"
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
# Rocky-09-RHEL-Installed
###############################################################################

info "Checking Repository : Rocky-09-RHEL-Installed"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "Rocky Linux 9" \
    --name "Rocky-09-RHEL-Installed" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "Rocky Linux 9" \
        --name "Rocky-09-RHEL-Installed" \
        --content-type yum \
        --url "http://192.168.253.136/repo/installed_rhel9"

    
    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "Rocky Linux 9 -> Rocky-09-RHEL-Installed"
    fi
fi

echo

###############################################################################
# Verification
###############################################################################

header "Repositories"

echo
info "CentOS 7"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "CentOS 7"

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
# CentOS 7
###############################################################################

sync_repository "CentOS 7" "CentOS-07-BaseOS"
sync_repository "CentOS 7" "CentOS-07-Updates"

###############################################################################
# Rocky Linux 8
###############################################################################

sync_repository "Rocky Linux 8" "Rocky-08-BaseOS"
sync_repository "Rocky Linux 8" "Rocky-08-AppStream"
sync_repository "Rocky Linux 8" "Rocky-08-RHEL-Installed"

###############################################################################
# Rocky Linux 9
###############################################################################

sync_repository "Rocky Linux 9" "Rocky-09-BaseOS"
sync_repository "Rocky Linux 9" "Rocky-09-AppStream"
sync_repository "Rocky Linux 9" "Rocky-09-RHEL-Installed"

###############################################################################
# Verification
###############################################################################

echo
header "Repository Synchronization"

echo
info "CentOS 7"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "CentOS 7"

echo
info "Rocky Linux 8"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "Rocky Linux 8"

echo

echo
info "Rocky Linux 9"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "Rocky Linux 9"

echo

header "[4/6] Creating Content Views & Activation Keys"


###############################################################################
# Function : Create Content View if Missing
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
# Create Content Views
###############################################################################

create_content_view "CentOS7-CV"
create_content_view "Rocky8-CV"
create_content_view "Rocky9-CV"

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
# Add Repositories
###############################################################################

add_repository_to_cv "CentOS7-CV" "CentOS 7" "CentOS-07-BaseOS"
add_repository_to_cv "CentOS7-CV" "CentOS 7" "CentOS-07-Updates"

add_repository_to_cv "Rocky8-CV" "Rocky Linux 8" "Rocky-08-BaseOS"
add_repository_to_cv "Rocky8-CV" "Rocky Linux 8" "Rocky-08-AppStream"
add_repository_to_cv "Rocky8-CV" "Rocky Linux 8" "Rocky-08-RHEL-Installed"

add_repository_to_cv "Rocky9-CV" "Rocky Linux 9" "Rocky-09-BaseOS"
add_repository_to_cv "Rocky9-CV" "Rocky Linux 9" "Rocky-09-AppStream"
add_repository_to_cv "Rocky9-CV" "Rocky Linux 9" "Rocky-09-RHEL-Installed"

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
# Publish Content Views
###############################################################################

publish_cv "CentOS7-CV"
publish_cv "Rocky8-CV"
publish_cv "Rocky9-CV"

###############################################################################
# Create Activation Keys
###############################################################################

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
# Create Activation Keys
###############################################################################

create_activation_key "centos7-prod-key" "CentOS7-CV"
create_activation_key "rocky8-prod-key" "Rocky8-CV"
create_activation_key "rocky9-prod-key" "Rocky9-CV"

###############################################################################
# Attach Subscriptions to Activation Keys
###############################################################################

header "Attaching Subscriptions"

CENTOS_SUB_ID=$(
$HAMMER subscription list \
  --organization "Default Organization" |
awk -F'|' '$3 ~ /CentOS 7/ {gsub(/ /,"",$1); print $1}'
)

ROCKY_SUB_ID=$(
$HAMMER subscription list \
  --organization "Default Organization" |
awk -F'|' '$3 ~ /Rocky Linux 8/ {gsub(/ /,"",$1); print $1}'
)

ROCKY9_SUB_ID=$(
$HAMMER subscription list \
  --organization "Default Organization" |
awk -F'|' '$3 ~ /Rocky Linux 9/ {gsub(/ /,"",$1); print $1}'
)

echo "CENTOS_SUB_ID=$CENTOS_SUB_ID"
echo "ROCKY_SUB_ID=$ROCKY_SUB_ID"
echo "ROCKY9_SUB_ID=$ROCKY9_SUB_ID"
echo

info "Attaching CentOS 7 subscription..."

OUTPUT=$(
$HAMMER activation-key add-subscription \
    --organization "Default Organization" \
    --name "centos7-prod-key" \
    --subscription-id "$CENTOS_SUB_ID" 2>&1
)

echo "$OUTPUT"

if echo "$OUTPUT" | grep -qi "already been registered"; then
    skip "CentOS 7 subscription already attached."
elif echo "$OUTPUT" | grep -qi "added"; then
    ok "CentOS 7 subscription attached."
elif [ $? -eq 0 ]; then
    ok "CentOS 7 subscription attached."
else
    error "Subscription attachment failed."
    record_failure "centos7-prod-key"
fi

echo

info "Attaching Rocky Linux 8 subscription..."

OUTPUT=$(
$HAMMER activation-key add-subscription \
    --organization "Default Organization" \
    --name "rocky8-prod-key" \
    --subscription-id "$ROCKY_SUB_ID" 2>&1
)

echo "$OUTPUT"

if echo "$OUTPUT" | grep -qi "already been registered"; then
    skip "Rocky Linux 8 subscription already attached."
elif echo "$OUTPUT" | grep -qi "added"; then
    ok "Rocky Linux 8 subscription attached."
elif [ $? -eq 0 ]; then
    ok "Rocky Linux 8 subscription attached."
else
    error "Subscription attachment failed."
    record_failure "rocky8-prod-key"
fi

info "Attaching Rocky Linux 9 subscription..."

OUTPUT=$(
$HAMMER activation-key add-subscription \
    --organization "Default Organization" \
    --name "rocky9-prod-key" \
    --subscription-id "$ROCKY9_SUB_ID" 2>&1
)

echo "$OUTPUT"

if echo "$OUTPUT" | grep -qi "already"; then
    skip "Rocky Linux 9 subscription already attached."
elif echo "$OUTPUT" | grep -qi "added"; then
    ok "Rocky Linux 9 subscription attached."
elif [ $? -eq 0 ]; then
    ok "Rocky Linux 9 subscription attached."
else
    error "Rocky Linux 9 subscription attachment failed."
    record_failure "rocky9-prod-key"
fi

###############################################################################
# Verification
###############################################################################

header "[5/6] Verification"

###############################################################################
# Content Views
###############################################################################

echo
header "Content Views"

$HAMMER content-view list || true

###############################################################################
# Activation Keys
###############################################################################

echo
header "Activation Keys"

$HAMMER activation-key list \
    --organization "Default Organization" || true

###############################################################################
# CentOS7-CV
###############################################################################

echo
header "CentOS7-CV"


$HAMMER content-view info \
    --organization "Default Organization" \
    --name "CentOS7-CV" || true

###############################################################################
# Rocky8-CV
###############################################################################

echo
header "Rocky8-CV"

$HAMMER content-view info \
    --organization "Default Organization" \
    --name "Rocky8-CV" || true

###############################################################################
# CentOS Repositories
###############################################################################

echo
header "CentOS Repositories"


$HAMMER repository list \
    --organization "Default Organization" \
    --product "CentOS 7" || true

###############################################################################
# Rocky 9 Repositories
###############################################################################

echo
header "Rocky9-CV"

$HAMMER content-view info \
    --organization "Default Organization" \
    --name "Rocky9-CV"

echo
header "Rocky Linux 9 Repositories"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "Rocky Linux 9" || true

###############################################################################
# Rocky Repositories
###############################################################################

echo
header "Rocky Repositories"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "Rocky Linux 8" || true

echo
ok "Verification completed."
echo

header "[6/6] Registration Commands"

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

echo
info "Rocky Linux 9"

echo "subscription-manager register \\"
echo "  --org=\"Default_Organization\" \\"
echo "  --activationkey=\"rocky9-prod-key\""

echo
###############################################################################
# Summary
###############################################################################

header "02 - Foreman Katello Bootstrap Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
    ok "Foreman Katello Bootstrap completed successfully."
else
    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

    for step in "${FAILED_STEPS[@]}"; do
        error "$step"
    done
fi

echo
