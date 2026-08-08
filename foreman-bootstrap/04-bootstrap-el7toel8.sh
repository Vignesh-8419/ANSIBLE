#!/bin/bash

###############################################################################
# 04 - Foreman Katello Bootstrap
#
# EL7 -> EL8 Upgrade Bootstrap
#
# Purpose:
#
#   - Create CentOS 7 migration product
#   - Create BaseOS / Updates / ELevate repositories
#   - Sync repositories
#   - Create Content View
#   - Publish Content View
#   - Create Activation Key
#   - Generate bootstrap command
#
# Supports:
#
#   CentOS Linux 7
#   ELevate migration repositories
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



###############################################################################
# Foreman Configuration
###############################################################################

FOREMAN_USER="${FOREMAN_USER:-admin}"

FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"


HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"


ORG="Default Organization"


LOCATION="Default Location"



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
# Resume Paused Foreman Tasks
###############################################################################

resume_paused_tasks()
{

header "Recovering Paused Foreman Tasks"


COUNT=$(
$HAMMER task list \
--search "state = paused" 2>/dev/null |
grep -c paused || true
)



if [ "$COUNT" -eq 0 ]

then

    ok "No paused tasks found."

    return 0

fi



warn "Found ${COUNT} paused task(s)."



$HAMMER task resume \
--search "state = paused"



sleep 10



COUNT=$(
$HAMMER task list \
--search "state = paused" 2>/dev/null |
grep -c paused || true
)



if [ "$COUNT" -eq 0 ]

then

    ok "Paused tasks cleared."

else

    warn "${COUNT} paused task(s) still remain."

fi


}



###############################################################################
# Get Repository ID
###############################################################################

get_repo_id()
{

REPO="$1"


$HAMMER repository info \
--organization "${ORG}" \
--product "${PRODUCT_NAME}" \
--name "${REPO}" 2>/dev/null |
awk -F':' '/^Id/ {gsub(/ /,"",$2);print $2}'


}



###############################################################################
# Create Product
###############################################################################

create_product()
{

header "Creating Product"



if $HAMMER product info \
--organization "${ORG}" \
--name "${PRODUCT_NAME}" >/dev/null 2>&1

then

    skip "Product ${PRODUCT_NAME} already exists."

else


    info "Creating Product ${PRODUCT_NAME}"



    $HAMMER product create \
    --organization "${ORG}" \
    --name "${PRODUCT_NAME}"



    if [ $? -eq 0 ]

    then

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



echo

info "Checking Repository : ${REPO_NAME}"



if $HAMMER repository info \
--organization "${ORG}" \
--product "${PRODUCT_NAME}" \
--name "${REPO_NAME}" >/dev/null 2>&1

then

    skip "${REPO_NAME} already exists."

else


    info "Creating Repository : ${REPO_NAME}"



    $HAMMER repository create \
    --organization "${ORG}" \
    --product "${PRODUCT_NAME}" \
    --name "${REPO_NAME}" \
    --content-type yum \
    --url "${REPO_URL}"



    if [ $? -eq 0 ]

    then

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

update_repo_url()
{

REPO_NAME="$1"

REPO_URL="$2"



info "Checking Repository URL : ${REPO_NAME}"



CURRENT_URL=$(
$HAMMER repository info \
--organization "${ORG}" \
--product "${PRODUCT_NAME}" \
--name "${REPO_NAME}" 2>/dev/null |
awk -F':' '/Relative Path|URL/ {print $2}' |
xargs
)



info "Configured URL : ${REPO_URL}"



$HAMMER repository update \
--organization "${ORG}" \
--product "${PRODUCT_NAME}" \
--name "${REPO_NAME}" \
--url "${REPO_URL}"



if [ $? -eq 0 ]

then

    ok "${REPO_NAME} URL updated."

else

    error "${REPO_NAME} URL update failed."

    record_failure "${REPO_NAME} URL"

fi


}



###############################################################################
# Create EL7 Migration Repositories
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
# Repository Sync With Lock Recovery
###############################################################################

sync_repository()
{

REPO_NAME="$1"



echo

info "Checking Sync Status : ${REPO_NAME}"



STATUS=$(
$HAMMER repository info \
--organization "${ORG}" \
--product "${PRODUCT_NAME}" \
--name "${REPO_NAME}" 2>/dev/null |
grep -Ei "Sync State|Sync Status" |
awk -F':' '{print $2}' |
xargs
)



if echo "${STATUS}" | grep -qi "Complete"

then

    skip "${REPO_NAME} already synced."

    return 0

fi



info "Starting synchronization : ${REPO_NAME}"



OUTPUT=$(
$HAMMER repository synchronize \
--organization "${ORG}" \
--product "${PRODUCT_NAME}" \
--name "${REPO_NAME}" 2>&1
)



RC=$?



echo "${OUTPUT}"



if [ ${RC} -eq 0 ]

then

    ok "${REPO_NAME} synchronization started."

    return 0

fi



###############################################################################
# Repository Lock Recovery
###############################################################################

if echo "${OUTPUT}" | grep -qi "Required lock is already taken"

then


    warn "Repository lock detected."



    for TRY in 1 2 3

    do


        warn "Recovery attempt ${TRY}"



        resume_paused_tasks



        sleep 10



        info "Retrying synchronization..."



        OUTPUT=$(
        $HAMMER repository synchronize \
        --organization "${ORG}" \
        --product "${PRODUCT_NAME}" \
        --name "${REPO_NAME}" 2>&1
        )



        RC=$?



        echo "${OUTPUT}"



        if [ ${RC} -eq 0 ]

        then

            ok "${REPO_NAME} synchronization started."

            return 0

        fi



        if ! echo "${OUTPUT}" | grep -qi "Required lock is already taken"

        then

            break

        fi


    done


fi



error "${REPO_NAME} synchronization failed."

record_failure "Sync ${REPO_NAME}"


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



if $HAMMER content-view info \
--organization "${ORG}" \
--name "${CONTENT_VIEW}" >/dev/null 2>&1

then

    skip "Content View ${CONTENT_VIEW} already exists."

else


    info "Creating Content View ${CONTENT_VIEW}"



    $HAMMER content-view create \
    --organization "${ORG}" \
    --name "${CONTENT_VIEW}"



    if [ $? -eq 0 ]

    then

        ok "Content View created."

    else

        error "Content View creation failed."

        record_failure "${CONTENT_VIEW}"

    fi


fi


}

###############################################################################
# Add Repository To Content View
###############################################################################

add_repository_to_cv()
{

REPO_NAME="$1"


REPO_ID=$(get_repo_id "${REPO_NAME}")


echo

info "Checking Content View Repository : ${REPO_NAME}"

info "Repository ID : ${REPO_ID}"



if [ -z "${REPO_ID}" ]

then

    error "Unable to find repository ID for ${REPO_NAME}"

    record_failure "${REPO_NAME} ID"

    return 1

fi



###############################################################################
# Check Existing Assignment
###############################################################################

EXISTING=$(
$HAMMER content-view info \
--organization "${ORG}" \
--name "${CONTENT_VIEW}" 2>/dev/null |
grep -F "${REPO_NAME}" || true
)



if [ -n "${EXISTING}" ]

then

    skip "${REPO_NAME} already assigned."

    return 0

fi



###############################################################################
# Add Repository
###############################################################################

info "Adding ${REPO_NAME} to ${CONTENT_VIEW}"



$HAMMER content-view add-repository \
--organization "${ORG}" \
--name "${CONTENT_VIEW}" \
--repository-id "${REPO_ID}"



if [ $? -eq 0 ]

then

    ok "${REPO_NAME} added."

else

    error "Failed adding ${REPO_NAME}"

    record_failure "${REPO_NAME} Content View"

fi


}



###############################################################################
# Configure Content View
###############################################################################

configure_content_view()
{

header "Configuring Content View"



add_repository_to_cv \
"${BASE_REPO}"



add_repository_to_cv \
"${UPDATE_REPO}"



add_repository_to_cv \
"${ELEVATE_REPO}"


}



###############################################################################
# Verify Content View Repository Mapping
###############################################################################

verify_content_view()
{

header "Verifying Content View"



FAILED=0



for REPO in \
"${BASE_REPO}" \
"${UPDATE_REPO}" \
"${ELEVATE_REPO}"

do


if $HAMMER content-view info \
--organization "${ORG}" \
--name "${CONTENT_VIEW}" 2>/dev/null |
grep -Fq "${REPO}"

then


    ok "${REPO} attached to ${CONTENT_VIEW}"


else


    error "${REPO} missing from ${CONTENT_VIEW}"

    FAILED=1


fi


done



if [ ${FAILED} -eq 1 ]

then

    record_failure "Content View Repository Verification"

    return 1

fi



ok "All repositories verified."


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

    return 1

fi



###############################################################################
# Check running publish task
###############################################################################

ACTIVE_TASK=$(
$HAMMER task list \
--search "state = running" 2>/dev/null |
grep -F "${CONTENT_VIEW}" || true
)



if [ -n "${ACTIVE_TASK}" ]

then

    skip "Publish already running."

    return 0

fi



###############################################################################
# Publish
###############################################################################

info "Publishing ${CONTENT_VIEW}"



OUTPUT=$(
$HAMMER content-view publish \
--organization "${ORG}" \
--name "${CONTENT_VIEW}" \
--description "EL7 Migration Publish $(date '+%F %T')" 2>&1
)



RC=$?



echo "${OUTPUT}"



if [ ${RC} -eq 0 ]

then

    ok "${CONTENT_VIEW} publish started."

    return 0

fi



###############################################################################
# Publish Lock Recovery
###############################################################################

if echo "${OUTPUT}" | grep -qi "Required lock is already taken"

then


    warn "Publish lock detected."



    for TRY in 1 2 3

    do


        warn "Publish recovery attempt ${TRY}"



        resume_paused_tasks



        sleep 10



        info "Retrying publish..."



        OUTPUT=$(
        $HAMMER content-view publish \
        --organization "${ORG}" \
        --name "${CONTENT_VIEW}" \
        --description "EL7 Migration Publish $(date '+%F %T')" 2>&1
        )



        RC=$?



        echo "${OUTPUT}"



        if [ ${RC} -eq 0 ]

        then

            ok "Publish started."

            return 0

        fi



        if ! echo "${OUTPUT}" | grep -qi "Required lock is already taken"

        then

            break

        fi


    done


fi



error "Content View publish failed."

record_failure "${CONTENT_VIEW} publish"


}



###############################################################################
# Create / Update Activation Key
###############################################################################

create_activation_key()
{

header "Creating Activation Key"



if $HAMMER activation-key info \
--organization "${ORG}" \
--name "${ACTIVATION_KEY}" >/dev/null 2>&1

then


    skip "Activation Key ${ACTIVATION_KEY} already exists."



    info "Updating Activation Key Content View"



    $HAMMER activation-key update \
    --organization "${ORG}" \
    --name "${ACTIVATION_KEY}" \
    --content-view "${CONTENT_VIEW}" \
    --lifecycle-environment "Library"



    if [ $? -eq 0 ]

    then

        ok "Activation Key updated."

    else

        error "Activation Key update failed."

        record_failure "${ACTIVATION_KEY}"

    fi



else


    info "Creating Activation Key ${ACTIVATION_KEY}"



    $HAMMER activation-key create \
    --organization "${ORG}" \
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

###############################################################################
# Activation Key Verification
###############################################################################

verify_activation_key()
{

header "Verifying Activation Key"



$HAMMER activation-key info \
--organization "${ORG}" \
--name "${ACTIVATION_KEY}"



if [ $? -eq 0 ]

then

    ok "Activation Key verification completed."

else

    error "Activation Key verification failed."

    record_failure "${ACTIVATION_KEY} verification"

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



echo "rpm -Uvh http://192.168.253.136/pub/katello-ca-consumer-latest.noarch.rpm"



echo



echo "subscription-manager register \\"

echo "  --org=\"${ORG}\" \\"

echo "  --activationkey=\"${ACTIVATION_KEY}\""



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



$HAMMER product info \
--organization "${ORG}" \
--name "${PRODUCT_NAME}"



echo

echo "============================================================"

echo "Repositories"

echo "============================================================"



$HAMMER repository list \
--organization "${ORG}" \
--product "${PRODUCT_NAME}"



echo

echo "============================================================"

echo "Content View"

echo "============================================================"



$HAMMER content-view info \
--organization "${ORG}" \
--name "${CONTENT_VIEW}"



echo

echo "============================================================"

echo "Activation Key"

echo "============================================================"



$HAMMER activation-key info \
--organization "${ORG}" \
--name "${ACTIVATION_KEY}"



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
# Main Execution
###############################################################################

header "04 - Foreman Katello Bootstrap EL7 To EL8"



###############################################################################
# Recover Foreman Tasks
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



configure_content_view



publish_content_view



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

header "04 - EL7 To EL8 Bootstrap Completed"



if [ ${#FAILED_STEPS[@]} -eq 0 ]

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



###############################################################################
# Manual Verification
###############################################################################

echo

echo "Manual Verification Commands"

echo "------------------------------------------------------------"



echo

echo 'hammer product info --organization "Default Organization" --name "CentOS 7"'



echo

echo 'hammer repository list --organization "Default Organization" --product "CentOS 7"'



echo

echo 'hammer content-view info --organization "Default Organization" --name "EL7toEL8-CV"'



echo

echo 'hammer activation-key info --organization "Default Organization" --name "el7toel8-key"'



exit 0
