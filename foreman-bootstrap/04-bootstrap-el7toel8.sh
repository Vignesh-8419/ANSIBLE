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
awk -F':' '/URL/ {print $2}' |
xargs
)
info "Current URL : ${CURRENT_URL}"
info "Required URL : ${REPO_URL}"
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
if echo "${OUTPUT}" | grep -qi "Skipping Sync"
then
ok "${REPO_NAME} already synchronized."
return 0
fi
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
# Wait For Repository Sync Completion
###############################################################################
wait_for_sync()
{
REPO_NAME="$1"
info "Waiting for ${REPO_NAME} sync completion..."
while true
do
STATUS=$(
$HAMMER repository info \
--organization "${ORG}" \
--product "${PRODUCT_NAME}" \
--name "${REPO_NAME}" 2>/dev/null |
grep -Ei "Sync State|Sync Status" |
awk -F':' '{print $2}' |
xargs
)
echo "Current Status : ${STATUS}"
case "${STATUS}" in
Complete)
ok "${REPO_NAME} sync completed."
break
;;
Error)
error "${REPO_NAME} sync failed."
record_failure "Sync ${REPO_NAME}"
break
;;
*)
sleep 30
;;
esac
done
}
###############################################################################
# Sync All EL7 Repositories
###############################################################################
sync_el7_repositories()
{
header "Synchronizing EL7 Repositories"
sync_repository "${BASE_REPO}"
wait_for_sync "${BASE_REPO}"
sync_repository "${UPDATE_REPO}"
wait_for_sync "${UPDATE_REPO}"
sync_repository "${ELEVATE_REPO}"
wait_for_sync "${ELEVATE_REPO}"
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
# Wait For Repository Sync Completion
###############################################################################
wait_for_sync()
{
REPO_NAME="$1"

info "Waiting for ${REPO_NAME} sync completion..."

for COUNT in $(seq 1 60)
do

STATUS=$(
$HAMMER repository info \
--organization "${ORG}" \
--product "${PRODUCT_NAME}" \
--name "${REPO_NAME}" 2>/dev/null |
grep -Ei "Sync State|Sync Status|Last Sync Result" |
awk -F':' '{print $2}' |
xargs
)

echo "Current Status : ${STATUS}"


if echo "${STATUS}" | grep -Eqi "Complete|Finished|Success"
then

ok "${REPO_NAME} sync completed."
return 0

fi


if echo "${STATUS}" | grep -Eqi "Error|Failed"
then

error "${REPO_NAME} sync failed."
record_failure "Sync ${REPO_NAME}"
return 1

fi


sleep 30

done


warn "${REPO_NAME} sync status timeout."
record_failure "Sync timeout ${REPO_NAME}"

}
###############################################################################
# Sync All EL7 Repositories
###############################################################################
sync_el7_repositories()
{
header "Synchronizing EL7 Repositories"
sync_repository "${BASE_REPO}"
wait_for_sync "${BASE_REPO}"
sync_repository "${UPDATE_REPO}"
wait_for_sync "${UPDATE_REPO}"
sync_repository "${ELEVATE_REPO}"
wait_for_sync "${ELEVATE_REPO}"
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
# Product Creation
###############################################################################
create_product
###############################################################################
# Repository Creation
###############################################################################
create_el7_repositories
###############################################################################
# Repository Synchronization
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
echo
###############################################################################
# Exit
###############################################################################
if [ ${#FAILED_STEPS[@]} -eq 0 ]
then
exit 0
else
exit 1
fi
