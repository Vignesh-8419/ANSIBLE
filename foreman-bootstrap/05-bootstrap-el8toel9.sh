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
    --name "${ROCKY_PRODUCT}" >/dev/null 2>&1
then

    skip "Product already exists."

else

    info "Creating Product..."


    $HAMMER product create \
        --organization "Default Organization" \
        --name "${ROCKY_PRODUCT}"


    if [ $? -eq 0 ]
    then

        ok "Product created."

    else

        error "Product creation failed."

        record_failure "${ROCKY_PRODUCT}"

    fi


fi


echo


###############################################################################
# Product Verification
###############################################################################

header "Products"


$HAMMER product list \
    --organization "Default Organization"


echo



###############################################################################
# Create Rocky Linux 8 Repositories
###############################################################################

header "[2/6] Creating EL8 Repositories"


create_repository()
{

PRODUCT="$1"
REPO="$2"
URL="$3"


info "Checking Repository : ${REPO}"


if $HAMMER repository info \
    --organization "Default Organization" \
    --product "${PRODUCT}" \
    --name "${REPO}" >/dev/null 2>&1
then

    skip "${REPO} already exists."

else


    info "Creating Repository : ${REPO}"


    $HAMMER repository create \
        --organization "Default Organization" \
        --product "${PRODUCT}" \
        --name "${REPO}" \
        --content-type yum \
        --url "${URL}"


    if [ $? -eq 0 ]
    then

        ok "${REPO} created."

    else

        error "${REPO} creation failed."

        record_failure "${REPO}"

    fi


fi


echo

}


###############################################################################
# Rocky 8 BaseOS
###############################################################################

create_repository \
"${ROCKY_PRODUCT}" \
"Rocky8-BaseOS" \
"http://192.168.253.136/repo/rocky8/BaseOS"



###############################################################################
# Rocky 8 AppStream
###############################################################################

create_repository \
"${ROCKY_PRODUCT}" \
"Rocky8-AppStream" \
"http://192.168.253.136/repo/rocky8/AppStream"



###############################################################################
# Rocky ELevate Repository
###############################################################################

create_repository \
"${ROCKY_PRODUCT}" \
"${EL8TOEL9_REPO_NAME}" \
"${EL8TOEL9_REPO_URL}"


echo

###############################################################################
# [3/6] Synchronizing Repositories
###############################################################################

header "[3/6] Synchronizing Repositories"


sync_repository()
{

REPO="$1"


info "Checking Sync Status : ${REPO}"


STATUS=$(
$HAMMER repository info \
    --organization "Default Organization" \
    --product "${ROCKY_PRODUCT}" \
    --name "${REPO}" 2>/dev/null |
    grep -Ei "Sync State|Last Sync|Sync Status" |
    awk -F':' '{print $2}' |
    xargs
)


if echo "$STATUS" | grep -qi "Complete"
then

    skip "${REPO} already synced."

    return 0

fi



info "Starting sync : ${REPO}"


$HAMMER repository synchronize \
    --organization "Default Organization" \
    --product "${ROCKY_PRODUCT}" \
    --name "${REPO}"


if [ $? -eq 0 ]
then

    ok "${REPO} sync started."

else

    error "${REPO} sync failed."

    record_failure "Sync ${REPO}"

fi


}



###############################################################################
# Sync Rocky 8 BaseOS
###############################################################################

sync_repository \
"Rocky8-BaseOS"



###############################################################################
# Sync Rocky 8 AppStream
###############################################################################

sync_repository \
"Rocky8-AppStream"



###############################################################################
# Sync ELevate Repository
###############################################################################

sync_repository \
"${EL8TOEL9_REPO_NAME}"



###############################################################################
# Repository Summary
###############################################################################

header "Repository Summary"


$HAMMER repository list \
    --organization "Default Organization" \
    --product "${ROCKY_PRODUCT}"



echo



###############################################################################
# [4/6] Creating Content View
###############################################################################

header "[4/6] Creating Content View"


if $HAMMER content-view info \
    --organization "Default Organization" \
    --name "${CONTENT_VIEW}" >/dev/null 2>&1
then

    skip "Content View ${CONTENT_VIEW} already exists."

else


    info "Creating Content View ${CONTENT_VIEW}..."


    $HAMMER content-view create \
        --organization "Default Organization" \
        --name "${CONTENT_VIEW}"


    if [ $? -eq 0 ]
    then

        ok "Content View created."

    else

        error "Content View creation failed."

        record_failure "${CONTENT_VIEW}"

    fi


fi

###############################################################################
# Add Repositories To Content View
###############################################################################

add_repository_to_cv()
{

REPO="$1"


info "Checking Content View Repository : ${REPO}"


if $HAMMER content-view info \
    --organization "Default Organization" \
    --name "${CONTENT_VIEW}" |
    grep -q "${REPO}"
then

    skip "${REPO} already added."

else


    info "Adding ${REPO} to ${CONTENT_VIEW}..."


    $HAMMER content-view repository add \
        --organization "Default Organization" \
        --name "${CONTENT_VIEW}" \
        --product "${ROCKY_PRODUCT}" \
        --repository "${REPO}"


    if [ $? -eq 0 ]
    then

        ok "${REPO} added."

    else

        error "Failed adding ${REPO}"

        record_failure "${REPO} Content View"

    fi


fi


echo

}



###############################################################################
# Configure Content View Repositories
###############################################################################

header "Configuring Content View Repositories"


add_repository_to_cv \
"Rocky8-BaseOS"


add_repository_to_cv \
"Rocky8-AppStream"


add_repository_to_cv \
"${EL8TOEL9_REPO_NAME}"



###############################################################################
# Publish Content View Version
###############################################################################

publish_content_view()
{

header "Publishing Content View"


VERSION=$(
$HAMMER content-view version list \
    --organization "Default Organization" \
    --content-view "${CONTENT_VIEW}" |
    grep "${CONTENT_VIEW}" |
    awk -F'|' '{print $2}' |
    tail -1
)



if [ -n "$VERSION" ]
then

    skip "Existing Content View version found."

else


    info "Publishing ${CONTENT_VIEW}..."


    $HAMMER content-view publish \
        --organization "Default Organization" \
        --name "${CONTENT_VIEW}" \
        --async



    if [ $? -eq 0 ]
    then

        ok "Content View publish started."

    else

        error "Content View publish failed."

        record_failure "${CONTENT_VIEW} publish"

    fi


fi


}


publish_content_view



###############################################################################
# Content View Verification
###############################################################################

header "Content View Summary"


$HAMMER content-view list \
    --organization "Default Organization" |
    grep "${CONTENT_VIEW}"


echo

###############################################################################
# Create Activation Key
###############################################################################

create_activation_key()
{

header "Creating Activation Key"


if $HAMMER activation-key info \
    --organization "Default Organization" \
    --name "${ACTIVATION_KEY}" >/dev/null 2>&1
then

    skip "Activation Key ${ACTIVATION_KEY} already exists."

else


    info "Creating Activation Key ${ACTIVATION_KEY}..."


    $HAMMER activation-key create \
        --organization "Default Organization" \
        --name "${ACTIVATION_KEY}" \
        --content-view "${CONTENT_VIEW}" \
        --lifecycle-environment "Library"



    if [ $? -eq 0 ]
    then

        ok "Activation Key created."

    else

        error "Activation Key creation failed."

        record_failure "${ACTIVATION_KEY}"

    fi


fi


}


create_activation_key



###############################################################################
# Configure Activation Key Repositories
###############################################################################

configure_activation_key()
{


header "Configuring Activation Key Repositories"



for REPO in \
"Rocky8-BaseOS" \
"Rocky8-AppStream" \
"${EL8TOEL9_REPO_NAME}"

do


info "Enabling Repository : ${REPO}"


$HAMMER activation-key content-override \
    --organization "Default Organization" \
    --name "${ACTIVATION_KEY}" \
    --content-label "${REPO}" \
    --value 1 \
    2>/dev/null || true

done

ok "Activation Key repository configuration completed."


}


configure_activation_key


###############################################################################
# Generate Bootstrap Command
###############################################################################

generate_bootstrap_command()
{


header "Generating EL8 To EL9 Migration Command"


echo

echo "Run this command on Rocky Linux 8 systems:"
echo

echo "------------------------------------------------------------"

echo "subscription-manager register \\"

echo "--org=\"Default Organization\" \\"

echo "--activationkey=${ACTIVATION_KEY}"


echo "------------------------------------------------------------"


echo

echo "After registration run:"

echo

echo "dnf clean all"

echo "dnf repolist"

echo

echo "Install ELevate packages:"

echo

echo "dnf install -y leapp-upgrade leapp-data-rocky"

echo

echo "Run preupgrade:"

echo

echo "leapp preupgrade"

echo

echo "Run upgrade:"

echo

echo "leapp upgrade"

echo

echo "Reboot:"

echo

echo "reboot"


}

###############################################################################
# Final Summary
###############################################################################

summary()
{

header "EL8 To EL9 Bootstrap Summary"



echo
echo "Product"
echo "------------------------------------------------------------"

$HAMMER product list \
    --organization "Default Organization" |
    grep "${ROCKY_PRODUCT}"



echo
echo "Repositories"
echo "------------------------------------------------------------"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "${ROCKY_PRODUCT}"



echo
echo "Content View"
echo "------------------------------------------------------------"

$HAMMER content-view list \
    --organization "Default Organization" |
    grep "${CONTENT_VIEW}"



echo
echo "Activation Key"
echo "------------------------------------------------------------"

$HAMMER activation-key list \
    --organization "Default Organization" |
    grep "${ACTIVATION_KEY}"



echo
echo "Migration Configuration"
echo "------------------------------------------------------------"

echo "Target Version      : ${TARGET_VERSION}"

echo "Product             : ${ROCKY_PRODUCT}"

echo "Content View        : ${CONTENT_VIEW}"

echo "Activation Key      : ${ACTIVATION_KEY}"

echo

echo "Repositories        :"

echo "  - Rocky8-BaseOS"

echo "  - Rocky8-AppStream"

echo "  - ${EL8TOEL9_REPO_NAME}"



}



###############################################################################
# Main Execution
###############################################################################

header "05 - Foreman Katello Bootstrap EL8 To EL9"



resume_paused_tasks



###############################################################################
# Execute Bootstrap Steps
###############################################################################

# Product

# Repository creation

# Repository sync

# Content View

# Activation Key

# Bootstrap command generation



summary



header "05 - EL8 To EL9 Bootstrap Completed"



if [ ${#FAILED_STEPS[@]} -eq 0 ]
then

    echo

    ok "EL8 To EL9 Bootstrap completed successfully."

else

    echo

    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."


    for ITEM in "${FAILED_STEPS[@]}"
    do

        error "${ITEM}"

    done


fi
