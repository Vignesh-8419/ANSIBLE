#!/bin/bash
###############################################################################
# 05 - Foreman Katello Bootstrap
# EL8 -> EL9 Upgrade Bootstrap
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
# Logging Functions
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
create_repository()
{
REPO="$1"
URL="$2"
info "Checking Repository : ${REPO}"
if $HAMMER repository info \
--organization "${ORG}" \
--product "${PRODUCT}" \
--name "${REPO}" >/dev/null 2>&1
then
skip "${REPO} already exists."
else
info "Creating Repository : ${REPO}"
$HAMMER repository create \
--organization "${ORG}" \
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
}
###############################################################################
# Update Repository URL
###############################################################################
update_repository_url()
{
REPO="$1"
URL="$2"
info "Updating Repository URL : ${REPO}"
$HAMMER repository update \
--organization "${ORG}" \
--product "${PRODUCT}" \
--name "${REPO}" \
--url "${URL}"
if [ $? -eq 0 ]
then
ok "${REPO} URL updated."
else
error "${REPO} URL update failed."
record_failure "${REPO} URL"
fi
}
###############################################################################
# Create Rocky Linux 8 Repositories
###############################################################################
create_repositories()
{
header "[1/6] Creating Rocky Linux 8 Repositories"
create_repository \
"${BASE_REPO}" \
"${BASE_URL}"
create_repository \
"${APPSTREAM_REPO}" \
"${APPSTREAM_URL}"
create_repository \
"${ELEVATE_REPO_NAME}" \
"${ELEVATE_REPO_URL}"
header "Updating Repository URLs"
update_repository_url \
"${BASE_REPO}" \
"${BASE_URL}"
update_repository_url \
"${APPSTREAM_REPO}" \
"${APPSTREAM_URL}"
update_repository_url \
"${ELEVATE_REPO_NAME}" \
"${ELEVATE_REPO_URL}"
}
###############################################################################
# Get Repository ID
###############################################################################
get_repository_id()
{
REPO="$1"
$HAMMER repository info \
--organization "${ORG}" \
--product "${PRODUCT}" \
--name "${REPO}" 2>/dev/null |
awk -F':' '/Id/ {gsub(/ /,"",$2);print $2}'
}
###############################################################################
# Synchronize Repository
###############################################################################
sync_repository()
{
REPO="$1"
info "Checking Sync Status : ${REPO}"
STATUS=$(
$HAMMER repository info \
--organization "${ORG}" \
--product "${PRODUCT}" \
--name "${REPO}" 2>/dev/null |
grep "Sync State" |
awk -F':' '{print $2}' |
xargs
)
if echo "${STATUS}" | grep -qi "Complete"
then
skip "${REPO} already synced."
return 0
fi
info "Starting synchronization : ${REPO}"
OUTPUT=$(
$HAMMER repository synchronize \
--organization "${ORG}" \
--product "${PRODUCT}" \
--name "${REPO}" 2>&1
)
RC=$?
echo "${OUTPUT}"
if [ ${RC} -eq 0 ]
then
ok "${REPO} synchronization started."
return 0
fi
if echo "${OUTPUT}" | grep -qi "Required lock is already taken"
then
warn "Repository lock detected."
resume_paused_tasks
sleep 10
info "Retrying synchronization..."
$HAMMER repository synchronize \
--organization "${ORG}" \
--product "${PRODUCT}" \
--name "${REPO}"
if [ $? -eq 0 ]
then
ok "${REPO} synchronization started."
return 0
fi
fi
error "${REPO} synchronization failed."
record_failure "Sync ${REPO}"
}
###############################################################################
# Synchronize All EL8 Repositories
###############################################################################
sync_repositories()
{
header "[2/6] Synchronizing Rocky Linux 8 Repositories"
sync_repository "${BASE_REPO}"
sync_repository "${APPSTREAM_REPO}"
sync_repository "${ELEVATE_REPO_NAME}"
}
###############################################################################
# Create Content View
###############################################################################
create_content_view()
{
header "[3/6] Creating Content View"
info "Checking Content View : ${CONTENT_VIEW}"
if $HAMMER content-view info \
--organization "${ORG}" \
--name "${CONTENT_VIEW}" >/dev/null 2>&1
then
skip "Content View ${CONTENT_VIEW} already exists."
else
info "Creating Content View : ${CONTENT_VIEW}"
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
REPO="$1"
info "Checking Repository Assignment : ${REPO}"
EXISTING=$(
$HAMMER content-view info \
--organization "${ORG}" \
--name "${CONTENT_VIEW}" 2>/dev/null |
grep -F "${REPO}" || true
)
if [ -n "${EXISTING}" ]
then
skip "${REPO} already assigned."
return 0
fi
info "Adding ${REPO} to ${CONTENT_VIEW}"
$HAMMER content-view add-repository \
--organization "${ORG}" \
--name "${CONTENT_VIEW}" \
--product "${PRODUCT}" \
--repository "${REPO}"
if [ $? -eq 0 ]
then
ok "${REPO} added to ${CONTENT_VIEW}."
else
error "Failed adding ${REPO}"
record_failure "${REPO} -> ${CONTENT_VIEW}"
fi
}
###############################################################################
# Configure Content View
###############################################################################
configure_content_view()
{
header "Configuring Content View Repositories"
add_repository_to_cv \
"${BASE_REPO}"
add_repository_to_cv \
"${APPSTREAM_REPO}"
add_repository_to_cv \
"${ELEVATE_REPO_NAME}"
}
###############################################################################
# Verify Content View Repository Mapping
###############################################################################
verify_content_view()
{
header "Verifying Content View Repository Mapping"
FAILED=0
for REPO in \
"${BASE_REPO}" \
"${APPSTREAM_REPO}" \
"${ELEVATE_REPO_NAME}"
do
if $HAMMER content-view info \
--organization "${ORG}" \
--name "${CONTENT_VIEW}" 2>/dev/null |
grep -Fq "${REPO}"
then
ok "${REPO} mapped correctly."
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
ok "All repositories mapped successfully."
}
###############################################################################
# Publish Content View
###############################################################################
publish_content_view()
{
header "[4/6] Publishing Content View"
verify_content_view
if [ $? -ne 0 ]
then
error "Publishing skipped because repository mapping failed."
return 1
fi
EXISTING_VERSION=$(
$HAMMER content-view version list \
--organization "${ORG}" \
--content-view "${CONTENT_VIEW}" 2>/dev/null |
grep "${CONTENT_VIEW}" |
tail -1
)
if [ -n "${EXISTING_VERSION}" ]
then
warn "Existing Content View version detected."
info "Publishing new version after repository validation."
fi
info "Publishing ${CONTENT_VIEW}"
OUTPUT=$(
$HAMMER content-view publish \
--organization "${ORG}" \
--name "${CONTENT_VIEW}" \
--description "EL8 to EL9 Migration $(date '+%F %T')" \
--async 2>&1
)
RC=$?
echo "${OUTPUT}"
if [ ${RC} -eq 0 ]
then
ok "${CONTENT_VIEW} publish started."
else
if echo "${OUTPUT}" | grep -qi "Required lock is already taken"
then
warn "Content View publish lock detected."
resume_paused_tasks
sleep 10
info "Retrying publish..."
$HAMMER content-view publish \
--organization "${ORG}" \
--name "${CONTENT_VIEW}" \
--description "EL8 to EL9 Migration Retry $(date '+%F %T')" \
--async
if [ $? -eq 0 ]
then
ok "${CONTENT_VIEW} publish retry started."
return 0
fi
fi
error "${CONTENT_VIEW} publish failed."
record_failure "${CONTENT_VIEW} publish"
fi
}
###############################################################################
# Content View Summary
###############################################################################
content_view_summary()
{
header "Content View Summary"
echo
echo "Content View"
echo "------------------------------------------------------------"
$HAMMER content-view info \
--organization "${ORG}" \
--name "${CONTENT_VIEW}"
echo
}
###############################################################################
# Get Repository Content Label
###############################################################################
get_content_label()
{
REPO="$1"
$HAMMER repository info \
--organization "${ORG}" \
--product "${PRODUCT}" \
--name "${REPO}" 2>/dev/null |
awk -F':' '/Content Label/ {
gsub(/ /,"",$2);
print $2
}'
}
###############################################################################
# Create Activation Key
###############################################################################
create_activation_key()
{
header "[5/6] Creating Activation Key"
info "Checking Activation Key : ${ACTIVATION_KEY}"
if $HAMMER activation-key info \
--organization "${ORG}" \
--name "${ACTIVATION_KEY}" >/dev/null 2>&1
then
skip "Activation Key already exists."
info "Updating Activation Key Content View"
$HAMMER activation-key update \
--organization "${ORG}" \
--name "${ACTIVATION_KEY}" \
--content-view "${CONTENT_VIEW}" \
--lifecycle-environment "Library"
return 0
fi
info "Creating Activation Key"
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
}
###############################################################################
# Configure Activation Key Repositories
###############################################################################
configure_activation_key()
{
header "Configuring Activation Key Repositories"
for REPO in \
"${BASE_REPO}" \
"${APPSTREAM_REPO}" \
"${ELEVATE_REPO_NAME}"
do
LABEL=$(get_content_label "${REPO}")
if [ -z "${LABEL}" ]
then
warn "Content label not found for ${REPO}"
record_failure "${REPO} content label"
continue
fi
info "Enabling Repository"
echo "Repository : ${REPO}"
echo "Label      : ${LABEL}"
$HAMMER activation-key content-override \
--organization "${ORG}" \
--name "${ACTIVATION_KEY}" \
--content-label "${LABEL}" \
--value 1
if [ $? -eq 0 ]
then
ok "${REPO} enabled."
else
error "${REPO} enable failed."
record_failure "${REPO} activation key"
fi
done
}
###############################################################################
# Generate Bootstrap Command
###############################################################################
generate_bootstrap_command()
{
header "Generating Rocky Linux 8 Bootstrap Command"
echo
echo "Run on Rocky Linux 8 source server"
echo
echo "------------------------------------------------------------"
echo
echo "subscription-manager register \\"
echo "  --org=\"${ORG}\" \\"
echo "  --activationkey=\"${ACTIVATION_KEY}\""
echo
echo "------------------------------------------------------------"
echo
echo "After registration:"
echo
echo "dnf clean all"
echo "dnf repolist"
echo
echo "Install ELevate packages:"
echo
echo "dnf install -y leapp-upgrade leapp-data-rocky"
echo
echo "Run upgrade checks:"
echo
echo "leapp preupgrade"
echo
echo "Execute migration:"
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
--organization "${ORG}" |
grep "${PRODUCT}"
echo
echo "Repositories"
echo "------------------------------------------------------------"
$HAMMER repository list \
--organization "${ORG}" \
--product "${PRODUCT}"
echo
echo "Content View"
echo "------------------------------------------------------------"
$HAMMER content-view list \
--organization "${ORG}" |
grep "${CONTENT_VIEW}"
echo
echo "Activation Key"
echo "------------------------------------------------------------"
$HAMMER activation-key list \
--organization "${ORG}" |
grep "${ACTIVATION_KEY}"
echo
echo "Migration Configuration"
echo "------------------------------------------------------------"
echo "Target Version : ${ROCKY_VERSION}"
echo "Product        : ${PRODUCT}"
echo "Content View   : ${CONTENT_VIEW}"
echo "Activation Key : ${ACTIVATION_KEY}"
}
###############################################################################
# Main Execution
###############################################################################

header "05 - Foreman Katello Bootstrap EL8 To EL9"

resume_paused_tasks

create_product

create_repositories

sync_repositories

create_content_view

configure_content_view

publish_content_view

create_activation_key

configure_activation_key

generate_bootstrap_command

content_view_summary

summary


header "05 - EL8 To EL9 Bootstrap Completed"


###############################################################################
# Final Status
###############################################################################

if [ ${#FAILED_STEPS[@]} -eq 0 ]
then
ok "EL8 To EL9 Bootstrap completed successfully."
else
warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."
for ITEM in "${FAILED_STEPS[@]}"
do
error "${ITEM}"
done
fi


exit 0
