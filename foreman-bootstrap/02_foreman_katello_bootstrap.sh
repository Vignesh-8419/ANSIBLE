#!/bin/bash
###############################################################################
#Foreman Katello Bootstrap
#Supports:
#CentOS 7
#Rocky Linux 8.10
#Rocky Linux 9.2
#Rocky Linux 9.8
#
#Creates:
#Products
#Repositories
#Content Views
#Activation Keys
###############################################################################
set +e
FAILED_STEPS=()
record_failure()
{
FAILED_STEPS+=("$1")
}
###############################################################################
#Colors
###############################################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'
###############################################################################
#Logging
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
#Variables
###############################################################################
FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"
HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"
ORGANIZATION="Default Organization"
TARGET_VERSION="${TARGET_VERSION:-9.8}"
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
#Resume Paused Tasks
###############################################################################
resume_paused_tasks()
{
header "Recovering Paused Foreman Tasks"
COUNT=$($HAMMER task list --search "state = paused" 2>/dev/null | grep -c paused || true)
if [ "${COUNT}" -eq 0 ]
then
ok "No paused tasks found."
return 0
fi
warn "Found ${COUNT} paused task(s)."
$HAMMER task resume --search "state = paused"
for i in {1..6}
do
COUNT=$($HAMMER task list --search "state = paused" 2>/dev/null | grep -c paused || true)
if [ "${COUNT}" -eq 0 ]
then
ok "Paused tasks cleared."
return 0
fi
warn "${COUNT} paused task(s) still remain."
sleep 10
done
warn "Some paused tasks still remain."
return 0
}
###############################################################################
#Start
###############################################################################
header "02 - Foreman Katello Bootstrap"
info "Target Version : ${TARGET_VERSION}"
###############################################################################
#Create Products
###############################################################################
header "[1/6] Creating Katello Products"
create_product()
{
PRODUCT="$1"
info "Checking Product : ${PRODUCT}"
if $HAMMER product info \
--organization "${ORGANIZATION}" \
--name "${PRODUCT}" >/dev/null 2>&1
then
skip "Product '${PRODUCT}' already exists."
else
info "Creating Product : ${PRODUCT}"
$HAMMER product create \
--organization "${ORGANIZATION}" \
--name "${PRODUCT}"
if [ $? -eq 0 ]
then
ok "Product created."
else
error "Product creation failed."
record_failure "${PRODUCT} Product"
fi
fi
echo
}
###############################################################################
#CentOS 7 Product
###############################################################################
create_product "CentOS 7"
###############################################################################
#Rocky Linux 8 Product
###############################################################################
create_product "Rocky Linux 8"
###############################################################################
#Rocky Linux 9 Product
###############################################################################
create_product "${PRODUCT_NAME}"
###############################################################################
#Product Verification
###############################################################################
header "Product Verification"
$HAMMER product list \
--organization "${ORGANIZATION}"
echo
###############################################################################
#Create Repositories
###############################################################################
header "[2/6] Creating Katello Repositories"
create_repository()
{
PRODUCT="$1"
REPO="$2"
URL="$3"
info "Checking Repository : ${REPO}"
if $HAMMER repository info \
--organization "${ORGANIZATION}" \
--product "${PRODUCT}" \
--name "${REPO}" >/dev/null 2>&1
then
skip "Repository '${REPO}' already exists."
else
info "Creating Repository : ${REPO}"
$HAMMER repository create \
--organization "${ORGANIZATION}" \
--product "${PRODUCT}" \
--name "${REPO}" \
--content-type yum \
--url "${URL}"
if [ $? -eq 0 ]
then
ok "Repository created."
else
error "Repository creation failed."
record_failure "${PRODUCT} -> ${REPO}"
fi
fi
echo
}
###############################################################################
#CentOS 7 Repositories
###############################################################################
header "Creating CentOS 7 Repositories"
create_repository \
"CentOS 7" \
"CentOS-07-BaseOS" \
"http://192.168.253.136/repo/centos/"
create_repository \
"CentOS 7" \
"CentOS-07-Updates" \
"http://192.168.253.136/repo/installed_rhel7/"
###############################################################################
#Rocky Linux 8 Repositories
###############################################################################
header "Creating Rocky Linux 8 Repositories"
create_repository \
"Rocky Linux 8" \
"Rocky-08-BaseOS" \
"http://192.168.253.136/repo/rocky8/BaseOS/"
create_repository \
"Rocky Linux 8" \
"Rocky-08-AppStream" \
"http://192.168.253.136/repo/rocky8/AppStream/"
create_repository \
"Rocky Linux 8" \
"Rocky-08-RHEL-Installed" \
"http://192.168.253.136/repo/installed_rhel8/"
###############################################################################
#Rocky Linux 9 Repositories
###############################################################################
header "Creating ${PRODUCT_NAME} Repositories"
create_repository \
"${PRODUCT_NAME}" \
"Rocky-09-BaseOS" \
"http://192.168.253.136/repo/${REPO_PATH}/BaseOS/"
create_repository \
"${PRODUCT_NAME}" \
"Rocky-09-AppStream" \
"http://192.168.253.136/repo/${REPO_PATH}/AppStream/"
create_repository \
"${PRODUCT_NAME}" \
"Rocky-09-RHEL-Installed" \
"http://192.168.253.136/repo/installed_rhel9/"
###############################################################################
#Repository Verification
###############################################################################
header "Repository Verification"
echo
info "CentOS 7"
$HAMMER repository list \
--organization "${ORGANIZATION}" \
--product "CentOS 7"
echo
info "Rocky Linux 8"
$HAMMER repository list \
--organization "${ORGANIZATION}" \
--product "Rocky Linux 8"
echo
info "${PRODUCT_NAME}"
$HAMMER repository list \
--organization "${ORGANIZATION}" \
--product "${PRODUCT_NAME}"
echo
###############################################################################
#Synchronize Repositories
###############################################################################
header "[3/6] Synchronizing Repositories"
sync_repository()
{
PRODUCT="$1"
REPO="$2"
info "Checking Repository : ${REPO}"
SYNC_STATUS=$(
$HAMMER repository info \
--organization "${ORGANIZATION}" \
--product "${PRODUCT}" \
--name "${REPO}" 2>/dev/null |
awk -F': ' '/Sync State/ {print $2}'
)
if echo "${SYNC_STATUS}" | grep -qi "running"
then
skip "Synchronization already running."
return
fi
info "Starting synchronization : ${REPO}"
OUTPUT=$(
$HAMMER repository synchronize \
--organization "${ORGANIZATION}" \
--product "${PRODUCT}" \
--name "${REPO}" 2>&1
)
RC=$?
echo "${OUTPUT}"
if [ ${RC} -eq 0 ]
then
ok "Synchronization started."
return
fi
if echo "${OUTPUT}" | grep -qi "Required lock is already taken"
then
warn "Repository lock detected."
resume_paused_tasks
sleep 10
OUTPUT=$(
$HAMMER repository synchronize \
--organization "${ORGANIZATION}" \
--product "${PRODUCT}" \
--name "${REPO}" 2>&1
)
RC=$?
echo "${OUTPUT}"
if [ ${RC} -eq 0 ]
then
ok "Synchronization started after recovery."
return
fi
fi
error "Synchronization failed : ${REPO}"
record_failure "${PRODUCT} -> ${REPO}"
}
###############################################################################
#CentOS 7 Sync
###############################################################################
sync_repository \
"CentOS 7" \
"CentOS-07-BaseOS"
sync_repository \
"CentOS 7" \
"CentOS-07-Updates"
###############################################################################
#Rocky Linux 8 Sync
###############################################################################
sync_repository \
"Rocky Linux 8" \
"Rocky-08-BaseOS"
sync_repository \
"Rocky Linux 8" \
"Rocky-08-AppStream"
sync_repository \
"Rocky Linux 8" \
"Rocky-08-RHEL-Installed"
###############################################################################
#Rocky Linux 9 Sync
###############################################################################
sync_repository \
"${PRODUCT_NAME}" \
"Rocky-09-BaseOS"
sync_repository \
"${PRODUCT_NAME}" \
"Rocky-09-AppStream"
sync_repository \
"${PRODUCT_NAME}" \
"Rocky-09-RHEL-Installed"
###############################################################################
#Sync Verification
###############################################################################
header "Repository Synchronization Verification"
echo
info "CentOS 7"
$HAMMER repository list \
--organization "${ORGANIZATION}" \
--product "CentOS 7"
echo
info "Rocky Linux 8"
$HAMMER repository list \
--organization "${ORGANIZATION}" \
--product "Rocky Linux 8"
echo
info "${PRODUCT_NAME}"
$HAMMER repository list \
--organization "${ORGANIZATION}" \
--product "${PRODUCT_NAME}"
echo
###############################################################################
#Create Content Views
###############################################################################
header "[4/6] Creating Content Views"
create_content_view()
{
CV_NAME="$1"
info "Checking Content View : ${CV_NAME}"
if $HAMMER content-view info \
--organization "${ORGANIZATION}" \
--name "${CV_NAME}" >/dev/null 2>&1
then
skip "Content View '${CV_NAME}' already exists."
else
info "Creating Content View : ${CV_NAME}"
$HAMMER content-view create \
--organization "${ORGANIZATION}" \
--name "${CV_NAME}"
if [ $? -eq 0 ]
then
ok "Content View created."
else
error "Content View creation failed."
record_failure "Content View : ${CV_NAME}"
fi
fi
echo
}
###############################################################################
#Create Content Views
###############################################################################
create_content_view "CentOS7-CV"
create_content_view "Rocky8-CV"
create_content_view "${CONTENT_VIEW}"
###############################################################################
#Add Repository To Content View
###############################################################################
add_repository_to_cv()
{
CV="$1"
PRODUCT="$2"
REPO="$3"
info "Checking Repository : ${REPO} in ${CV}"
if $HAMMER content-view info \
--organization "${ORGANIZATION}" \
--name "${CV}" | grep -q "${REPO}"
then
skip "Repository already assigned."
else
info "Adding Repository : ${REPO}"
$HAMMER content-view add-repository \
--organization "${ORGANIZATION}" \
--name "${CV}" \
--product "${PRODUCT}" \
--repository "${REPO}"
if [ $? -eq 0 ]
then
ok "Repository added."
else
error "Failed adding repository."
record_failure "${REPO} -> ${CV}"
fi
fi
echo
}
###############################################################################
#CentOS 7 Content View
###############################################################################
add_repository_to_cv \
"CentOS7-CV" \
"CentOS 7" \
"CentOS-07-BaseOS"
add_repository_to_cv \
"CentOS7-CV" \
"CentOS 7" \
"CentOS-07-Updates"
###############################################################################
#Rocky Linux 8 Content View
###############################################################################
add_repository_to_cv \
"Rocky8-CV" \
"Rocky Linux 8" \
"Rocky-08-BaseOS"
add_repository_to_cv \
"Rocky8-CV" \
"Rocky Linux 8" \
"Rocky-08-AppStream"
add_repository_to_cv \
"Rocky8-CV" \
"Rocky Linux 8" \
"Rocky-08-RHEL-Installed"
###############################################################################
#Rocky Linux 9 Content View
###############################################################################
add_repository_to_cv \
"${CONTENT_VIEW}" \
"${PRODUCT_NAME}" \
"Rocky-09-BaseOS"
add_repository_to_cv \
"${CONTENT_VIEW}" \
"${PRODUCT_NAME}" \
"Rocky-09-AppStream"
add_repository_to_cv \
"${CONTENT_VIEW}" \
"${PRODUCT_NAME}" \
"Rocky-09-RHEL-Installed"
###############################################################################
#Publish Content View
###############################################################################
publish_content_view()
{
CV="$1"
info "Publishing Content View : ${CV}"
OUTPUT=$(
$HAMMER content-view publish \
--organization "${ORGANIZATION}" \
--name "${CV}" \
--description "Bootstrap Publish $(date '+%F %T')" 2>&1
)
RC=$?
echo "${OUTPUT}"
if [ ${RC} -eq 0 ]
then
ok "Content View published."
else
if echo "${OUTPUT}" | grep -qi "Required lock is already taken"
then
warn "Content View publish locked."
resume_paused_tasks
sleep 10
OUTPUT=$(
$HAMMER content-view publish \
--organization "${ORGANIZATION}" \
--name "${CV}" \
--description "Bootstrap Publish $(date '+%F %T')" 2>&1
)
RC=$?
echo "${OUTPUT}"
fi
if [ ${RC} -eq 0 ]
then
ok "Content View published after recovery."
else
error "Content View publish failed."
record_failure "Publish : ${CV}"
fi
fi
}
###############################################################################
#Publish Content Views
###############################################################################
publish_content_view "CentOS7-CV"
publish_content_view "Rocky8-CV"
publish_content_view "${CONTENT_VIEW}"
###############################################################################
#Create Activation Keys
###############################################################################
header "[5/6] Creating Activation Keys"
create_activation_key()
{
KEY="$1"
CV="$2"
info "Checking Activation Key : ${KEY}"
if $HAMMER activation-key info \
--organization "${ORGANIZATION}" \
--name "${KEY}" >/dev/null 2>&1
then
skip "Activation Key '${KEY}' already exists."
$HAMMER activation-key update \
--organization "${ORGANIZATION}" \
--name "${KEY}" \
--content-view "${CV}" \
--lifecycle-environment "Library"
else
info "Creating Activation Key : ${KEY}"
$HAMMER activation-key create \
--organization "${ORGANIZATION}" \
--name "${KEY}" \
--lifecycle-environment "Library" \
--content-view "${CV}"
fi
if [ $? -eq 0 ]
then
ok "Activation Key ready."
else
error "Activation Key failed."
record_failure "Activation Key : ${KEY}"
fi
echo
}
###############################################################################
#Activation Keys
###############################################################################
create_activation_key \
"centos7-prod-key" \
"CentOS7-CV"
create_activation_key \
"rocky8-prod-key" \
"Rocky8-CV"
create_activation_key \
"${ACTIVATION_KEY}" \
"${CONTENT_VIEW}"
###############################################################################
#Attach Subscriptions
###############################################################################
header "Attaching Subscriptions"
get_subscription_id()
{
PRODUCT="$1"
$HAMMER subscription list \
--organization "${ORGANIZATION}" |
awk -F'|' -v product="${PRODUCT}" '
{
gsub(/^ +| +$/,"",$3)
if($3==product)
{
gsub(/ /,"",$1)
print $1
}
}'
}
CENTOS_SUB_ID=$(get_subscription_id "CentOS 7")
ROCKY8_SUB_ID=$(get_subscription_id "Rocky Linux 8")
ROCKY9_SUB_ID=$(get_subscription_id "${PRODUCT_NAME}")
attach_subscription()
{
KEY="$1"
SUB_ID="$2"
PRODUCT="$3"
info "Attaching Subscription : ${PRODUCT}"
if [ -z "${SUB_ID}" ]
then
error "Subscription ID not found : ${PRODUCT}"
record_failure "${PRODUCT} Subscription"
return
fi
OUTPUT=$(
$HAMMER activation-key add-subscription \
--organization "${ORGANIZATION}" \
--name "${KEY}" \
--subscription-id "${SUB_ID}" 2>&1
)
echo "${OUTPUT}"
if echo "${OUTPUT}" | grep -qi "already"
then
skip "${PRODUCT} subscription already attached."
elif echo "${OUTPUT}" | grep -qi "added"
then
ok "${PRODUCT} subscription attached."
elif [ $? -eq 0 ]
then
ok "${PRODUCT} subscription attached."
else
error "${PRODUCT} subscription failed."
record_failure "${PRODUCT} Subscription"
fi
}
attach_subscription \
"centos7-prod-key" \
"${CENTOS_SUB_ID}" \
"CentOS 7"
attach_subscription \
"rocky8-prod-key" \
"${ROCKY8_SUB_ID}" \
"Rocky Linux 8"
attach_subscription \
"${ACTIVATION_KEY}" \
"${ROCKY9_SUB_ID}" \
"${PRODUCT_NAME}"
###############################################################################
#Verification
###############################################################################
header "[6/6] Verification"
echo
header "Content Views"
$HAMMER content-view list \
--organization "${ORGANIZATION}"
echo
header "Activation Keys"
$HAMMER activation-key list \
--organization "${ORGANIZATION}"
echo
header "Repositories"
$HAMMER repository list \
--organization "${ORGANIZATION}" \
--product "CentOS 7"
$HAMMER repository list \
--organization "${ORGANIZATION}" \
--product "Rocky Linux 8"
$HAMMER repository list \
--organization "${ORGANIZATION}" \
--product "${PRODUCT_NAME}"
###############################################################################
#Registration Commands
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
#Final Summary
###############################################################################
header "02 - Foreman Katello Bootstrap Completed"
if [ ${#FAILED_STEPS[@]} -eq 0 ]
then
ok "Foreman Katello Bootstrap completed successfully."
else
warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."
for STEP in "${FAILED_STEPS[@]}"
do
error "${STEP}"
done
fi
echo
###############################################################################
#Manual Verification
###############################################################################
header "Manual Verification Commands"
echo
echo "hammer product list"
echo
echo "hammer repository list --organization \"${ORGANIZATION}\""
echo
echo "hammer content-view list --organization \"${ORGANIZATION}\""
echo
echo "hammer activation-key list --organization \"${ORGANIZATION}\""
echo
echo "hammer subscription list --organization \"${ORGANIZATION}\""
echo
exit 0
