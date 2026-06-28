#!/bin/bash
###############################################################################
# NetBox Bootstrap Script
#
# Description:
#   Creates NetBox Tags, Configuration Contexts and Custom Fields
#
# Author  : VGS
# Version : 1.0
###############################################################################

set -euo pipefail

###############################################
# Configuration
###############################################

NETBOX_URL="https://192.168.253.143"
NETBOX_TOKEN="83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd"

VERIFY_SSL=false

###############################################
# Curl Options
###############################################

if [ "$VERIFY_SSL" = false ]; then
    CURL_SSL="-k"
else
    CURL_SSL=""
fi

###############################################
# Colours
###############################################

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

###############################################
# Banner
###############################################

banner() {

clear

echo -e "${CYAN}"
echo "==============================================================="
echo "               NETBOX BOOTSTRAP UTILITY"
echo "==============================================================="
echo " Creates:"
echo "   ✔ Tags"
echo "   ✔ Configuration Contexts"
echo "   ✔ Custom Fields"
echo "   ✔ Choice Sets"
echo "==============================================================="
echo -e "${NC}"

}

###############################################
# API Wrapper
###############################################

api_get() {

curl -s ${CURL_SSL} \
-H "Authorization: Token ${NETBOX_TOKEN}" \
-H "Content-Type: application/json" \
"${NETBOX_URL}$1"

}

api_post() {

curl -s ${CURL_SSL} \
-X POST \
-H "Authorization: Token ${NETBOX_TOKEN}" \
-H "Content-Type: application/json" \
"${NETBOX_URL}$1" \
-d "$2"

}

api_patch() {

curl -s ${CURL_SSL} \
-X PATCH \
-H "Authorization: Token ${NETBOX_TOKEN}" \
-H "Content-Type: application/json" \
"${NETBOX_URL}$1" \
-d "$2"

}

###############################################
# Status Functions
###############################################

success() {

echo -e "${GREEN}[ OK ]${NC} $1"

}

warn() {

echo -e "${YELLOW}[WARN]${NC} $1"

}

error() {

echo -e "${RED}[FAIL]${NC} $1"

}

info() {

echo -e "${BLUE}[INFO]${NC} $1"

}

###############################################
# Lookup Functions
###############################################

get_tag_id() {
    api_get "/api/extras/tags/?name=$1" \
    | grep -o '"id":[0-9]*' \
    | head -1 \
    | cut -d: -f2 || true
}

get_context_id() {
    api_get "/api/extras/config-contexts/?name=$1" \
    | grep -o '"id":[0-9]*' \
    | head -1 \
    | cut -d: -f2 || true
}

get_custom_field_id() {
    api_get "/api/extras/custom-fields/?name=$1" \
    | grep -o '"id":[0-9]*' \
    | head -1 \
    | cut -d: -f2 || true
}

get_choice_set_id() {
    api_get "/api/extras/custom-field-choice-sets/?name=$1" \
    | grep -o '"id":[0-9]*' \
    | head -1 \
    | cut -d: -f2 || true
}

###############################################
# Create Tag
###############################################

create_tag() {

TAG="$1"

if [ -n "$(get_tag_id "$TAG")" ]; then
    warn "Tag already exists : $TAG"
    return
fi

JSON=$(cat <<EOF
{
    "name":"$TAG",
    "slug":"$TAG"
}
EOF
)

api_post "/api/extras/tags/" "$JSON" >/dev/null

success "Created Tag : $TAG"

}

###############################################
# Create All Tags
###############################################

create_tags() {

info "Creating NetBox Tags..."

for TAG in \
vmware-awx-context \
pxe-centos-context \
pxe-rockyos-context \
patch-context \
repo-config-context \
centostorocky-context \
patch-el8-context \
centos-patch-context \
rocky-patch-context
do
    create_tag "$TAG"
done

echo

}

###############################################
# Main
###############################################

###############################################################################
# Generic Configuration Context Function
###############################################################################

create_or_update_context() {

NAME="$1"
PAYLOAD="$2"

ID=$(get_context_id "$NAME")

if [ -z "$ID" ]; then

    info "Creating Context : $NAME"

    api_post "/api/extras/config-contexts/" "$PAYLOAD" >/dev/null

    success "Created Context : $NAME"

else

    info "Updating Context : $NAME"

    api_patch "/api/extras/config-contexts/${ID}/" "$PAYLOAD" >/dev/null

    success "Updated Context : $NAME"

fi

echo

}

###############################################################################
# VMware AWX Context
###############################################################################

create_vmware_awx_context() {

info "Creating VMware AWX Context..."

JSON=$(cat <<'EOF'
{
    "name": "vmware-awx-context",
    "weight": 1000,
    "tags": ["vmware-awx-context"],
    "data": {
        "centos_template_name": "GOLDENTEMPLATE_CENTOS_07",
        "datacenter_name": "Datacenter",
        "datastore": "datastore1",
        "dns_primary": "192.168.253.1",
        "dns_servers": [
            "192.168.253.1",
            "8.8.8.8"
        ],
        "folder": "vm",
        "gateway": "192.168.253.2",
        "guest_domain": "vgs.com",
        "infra_dns_pass": "Root@123",
        "infra_dns_user": "root",
        "netmask": "255.255.255.0",
        "vcenter_hostname": "192.168.253.129",
        "vcenter_password": "Vigneshv12$",
        "vcenter_username": "administrator@vsphere.local",
        "vm_network": "VM Network",
        "esxi_hostname": "192.168.253.128",
        "esxi_password": "Root@123",
        "esxi_username": "root",
        "vm_root_password": "Root@123",
        "ansible_password": "Root@123",
        "vm_root_user": "root"
    }
}
EOF
)

create_or_update_context "vmware-awx-context" "$JSON"

}

###############################################################################
# PXE CentOS Context
###############################################################################

create_pxe_centos_context() {

info "Creating PXE CentOS Context..."

JSON=$(cat <<'EOF'
{
    "name": "pxe-centos-context",
    "weight": 1000,
    "tags": [
        "pxe-centos-context"
    ],
    "data": {
        "centos_kickstart_url": "http://192.168.253.136/repo/centos/kickstart/centos.cfg",
        "centos_template_name": "GOLDENTEMPLATE_CENTOS_07",
        "http_server": "192.168.253.136",
        "pxe_folder": "/var/lib/tftpboot",
        "vm_root_password": "Root@123",
        "vm_root_user": "root"
    }
}
EOF
)

create_or_update_context "pxe-centos-context" "$JSON"

}

###############################################################################
# PXE Rocky Context
###############################################################################

create_pxe_rocky_context() {

info "Creating PXE Rocky Context..."

JSON=$(cat <<'EOF'
{
    "name": "pxe-rockyos-context",
    "weight": 1000,
    "tags": [
        "pxe-rockyos-context"
    ],
    "data": {
        "http_server": "192.168.253.136",
        "rockyos_kickstart_url": "http://192.168.253.136/repo/rocky8/kickstart/rockyos.cfg",
        "pxe_folder": "/var/lib/tftpboot",
        "rockyos_template_name": "GOLDENTEMPLATE_ROCKYOS_08",
        "vm_root_password": "Root@123",
        "vm_root_user": "root"
    }
}
EOF
)

create_or_update_context "pxe-rockyos-context" "$JSON"

}

###############################################################################
# Execute Part 2
###############################################################################

###############################################################################
# Patch Context (EL7)
###############################################################################

create_patch_context() {

info "Creating Patch Context..."

JSON=$(cat <<'EOF'
{
    "name": "patch-context",
    "weight": 1000,
    "tags": [
        "patch-context"
    ],
    "data": {
        "dns_primary": "192.168.253.1",
        "guest_domain": "vgs.com",
        "httpd_server_url": "http://192.168.253.136/repo/",
        "iso_share_pass": "Vigneshv12$",
        "iso_share_user": "vigne",
        "repo_mount_path": "//192.168.29.241/ISO",
        "repo_mount_point": "/var/www/html/repo",
        "repositories": [
            {
                "folder": "centos",
                "id": "base",
                "name": "CentOS Base Repo"
            },
            {
                "folder": "installed_rhel7",
                "id": "patch",
                "name": "CentOS Patch Repo"
            }
        ]
    }
}
EOF
)

create_or_update_context "patch-context" "$JSON"

}

###############################################################################
# Repository Configuration Context
###############################################################################

create_repo_config_context() {

info "Creating Repository Configuration Context..."

JSON=$(cat <<'EOF'
{
    "name": "repo-config-context",
    "weight": 1000,
    "tags": [
        "repo-config-context"
    ],
    "data": {
        "repo_mount_path": "//192.168.31.87/ISO",
        "repo_mount_point": "/var/www/html/repo",
        "iso_share_user": "vigne",
        "iso_share_pass": "Vigneshv12$",
        "http_server_ip": "192.168.253.136"
    }
}
EOF
)

create_or_update_context "repo-config-context" "$JSON"

}

###############################################################################
# CentOS to Rocky Migration Context
###############################################################################

create_centostorocky_context() {

info "Creating CentOS to Rocky Migration Context..."

JSON=$(cat <<'EOF'
{
    "name": "centostorocky-context",
    "weight": 1000,
    "tags": [
        "centostorocky-context"
    ],
    "data": {
        "ansible_hostname": "ansible-server-01.vgs.com",
        "dns_primary": "192.168.253.1",
        "guest_domain": "vgs.com",
        "httpd_server_url": "http://192.168.253.136/repo/",
        "vault_repositories": [
            {
                "id": "base",
                "name": "CentOS Vault Base",
                "url": "https://vault.centos.org/7.9.2009/os/x86_64/"
            },
            {
                "id": "updates",
                "name": "CentOS Vault Updates",
                "url": "https://vault.centos.org/7.9.2009/updates/x86_64/"
            },
            {
                "id": "extras",
                "name": "CentOS Vault Extras",
                "url": "https://vault.centos.org/7.9.2009/extras/x86_64/"
            }
        ],
        "rocky8_repos": [
            {
                "id": "rocky8-baseos",
                "name": "Rocky Linux 8 - BaseOS",
                "folder": "rocky8/BaseOS/"
            },
            {
                "id": "rocky8-appstream",
                "name": "Rocky Linux 8 - AppStream",
                "folder": "rocky8/AppStream/"
            }
        ]
    }
}
EOF
)

create_or_update_context "centostorocky-context" "$JSON"

}

###############################################################################
# Rocky Linux EL8 Patch Context
###############################################################################

create_patch_el8_context() {

info "Creating EL8 Patch Context..."

JSON=$(cat <<'EOF'
{
    "name": "patch-el8-context",
    "weight": 1000,
    "tags": [
        "patch-el8-context"
    ],
    "data": {
        "httpd_server_url": "http://192.168.253.136/repo/",
        "repositories": [
            {
                "id": "rocky8-baseos",
                "name": "Rocky Linux 8 BaseOS",
                "folder": "rocky8/BaseOS"
            },
            {
                "id": "rocky8-appstream",
                "name": "Rocky Linux 8 AppStream",
                "folder": "rocky8/Appstream"
            },
            {
                "id": "rocky8-rhel-installed",
                "name": "Rocky Linux 8 Installed RHEL",
                "folder": "installed_rhel8"
            }
        ]
    }
}
EOF
)

create_or_update_context "patch-el8-context" "$JSON"

}

create_centos_patch_context() {

info "Creating CentOS Patch Context..."

JSON=$(cat <<'EOF'
{
    "name": "centos-patch-context",
    "weight": 1000,
    "tags": ["centos-patch-context"],
    "data": {
        "organization": "Default_Organization",
        "activation_key": "centos7-prod-key",
        "katello_ca_url": "http://cent-07-01.vgs.com/pub/katello-ca-consumer-latest.noarch.rpm",
        "repo_base": "http://192.168.253.136/repo/centos",
        "repo_patch": "http://192.168.253.136/repo/installed_rhel7",
        "subscription_manager_package": "subscription-manager",
        "reboot_delay": 0,
        "wait_for_down_timeout": 300,
        "wait_for_up_timeout": 600,
        "post_reboot_wait": 120,
        "repo_backup_dir": "/etc/yum.repos.d/backup"
    }
}
EOF
)

create_or_update_context "centos-patch-context" "$JSON"

}

create_rocky_patch_context() {

info "Creating Rocky Patch Context..."

JSON=$(cat <<'EOF'
{
    "name": "rocky-patch-context",
    "weight": 1000,
    "tags": ["rocky-patch-context"],
    "data": {
        "organization": "Default_Organization",
        "activation_key": "rocky8-prod-key",
        "katello_ca_url": "http://cent-07-01.vgs.com/pub/katello-ca-consumer-latest.noarch.rpm",
        "repo_baseos": "http://192.168.253.136/repo/rocky8/BaseOS",
        "repo_appstream": "http://192.168.253.136/repo/rocky8/Appstream",
        "repo_patch": "http://192.168.253.136/repo/installed_rhel8",
        "subscription_manager_package": "subscription-manager",
        "reboot_delay": 0,
        "wait_for_down_timeout": 300,
        "wait_for_up_timeout": 600,
        "post_reboot_wait": 120,
        "repo_backup_dir": "/etc/yum.repos.d/backup"
    }
}
EOF
)

create_or_update_context "rocky-patch-context" "$JSON"

}


###############################################################################
# Execute Part 3
###############################################################################

###############################################################################
# Verification
###############################################################################

verify_tags() {

info "Verifying Tags..."

api_get "/api/extras/tags/"

echo

}

verify_contexts() {

info "Verifying Configuration Contexts..."

api_get "/api/extras/config-contexts/"

echo

}

verify_context() {

NAME="$1"

info "Looking up Context : $NAME"

api_get "/api/extras/config-contexts/?name=${NAME}"

echo

}

###############################################################################
# Execute Part 4A
###############################################################################

###############################################################################
# Generic Custom Field Function
###############################################################################

create_custom_field() {

NAME="$1"
PAYLOAD="$2"

ID=$(get_custom_field_id "$NAME")

if [ -n "$ID" ]; then
    warn "Custom Field already exists : $NAME"
    return
fi

info "Creating Custom Field : $NAME"

api_post "/api/extras/custom-fields/" "$PAYLOAD"

success "Created Custom Field : $NAME"

echo

}

###############################################################################
# Choice Set
###############################################################################

create_patch_choice_set() {

ID=$(get_choice_set_id "Patch Status")

if [ -n "$ID" ]; then
    warn "Choice Set already exists : Patch Status"
    PATCH_STATUS_ID="$ID"
    return
fi

info "Creating Choice Set : Patch Status"

JSON=$(cat <<'EOF'
{
    "name":"Patch Status",
    "extra_choices":[
        ["Compliant","Compliant"],
        ["Non-Compliant","Non-Compliant"],
        ["Unknown","Unknown"]
    ]
}
EOF
)

api_post "/api/extras/custom-field-choice-sets/" "$JSON" >/dev/null

PATCH_STATUS_ID=$(get_choice_set_id "Patch Status")

success "Created Choice Set : Patch Status"

echo

}

###############################################################################
# CPU Count
###############################################################################

create_cpu_count_cf() {

JSON=$(cat <<'EOF'
{
    "name":"cpu_count",
    "label":"CPU Count",
    "type":"integer",
    "object_types":["dcim.device"]
}
EOF
)

create_custom_field "cpu_count" "$JSON"

}

###############################################################################
# RAM
###############################################################################

create_ram_cf() {

JSON=$(cat <<'EOF'
{
    "name":"ram_gb",
    "label":"RAM (GB)",
    "type":"integer",
    "object_types":["dcim.device"]
}
EOF
)

create_custom_field "ram_gb" "$JSON"

}

###############################################################################
# Disk
###############################################################################

create_disk_cf() {

JSON=$(cat <<'EOF'
{
    "name":"disk_gb",
    "label":"Disk Size",
    "type":"text",
    "object_types":["dcim.device"]
}
EOF
)

create_custom_field "disk_gb" "$JSON"

}

###############################################################################
# VM Type
###############################################################################

create_vmtype_cf() {

JSON=$(cat <<'EOF'
{
    "name":"vm_type",
    "label":"VM Type",
    "type":"text",
    "object_types":["dcim.device"]
}
EOF
)

create_custom_field "vm_type" "$JSON"

}

###############################################################################
# Kernel
###############################################################################

create_kernel_cf() {

JSON=$(cat <<'EOF'
{
    "name":"kernel",
    "label":"Kernel",
    "type":"text",
    "object_types":["dcim.device"]
}
EOF
)

create_custom_field "kernel" "$JSON"

}

###############################################################################
# Expected Kernel
###############################################################################

create_expected_kernel_cf() {

JSON=$(cat <<'EOF'
{
    "name":"expected_kernel",
    "label":"Expected Kernel",
    "type":"text",
    "object_types":["dcim.device"]
}
EOF
)

create_custom_field "expected_kernel" "$JSON"

}

###############################################################################
# Last Patch Check
###############################################################################

create_last_patch_cf() {

JSON=$(cat <<'EOF'
{
    "name":"last_patch_check",
    "label":"Last Patch Check",
    "type":"date",
    "object_types":["dcim.device"]
}
EOF
)

create_custom_field "last_patch_check" "$JSON"

}

###############################################################################
# Patch Status
###############################################################################

create_patch_status_cf() {

    create_patch_choice_set

    JSON=$(cat <<EOF
{
    "name":"patch_status",
    "label":"Patch Status",
    "type":"select",
    "choice_set":${PATCH_STATUS_ID},
    "object_types":["dcim.device"]
}
EOF
)

    echo "PATCH_STATUS_ID=${PATCH_STATUS_ID}"
    echo "$JSON"

    create_custom_field "patch_status" "$JSON"
}

###############################################################################
# Execute
###############################################################################

###############################################################################
# API Connectivity Test
###############################################################################

test_api_connection() {

info "Testing NetBox API Connectivity..."

HTTP_CODE=$(curl -s ${CURL_SSL} \
-o /dev/null \
-w "%{http_code}" \
-H "Authorization: Token ${NETBOX_TOKEN}" \
"${NETBOX_URL}/api/")

if [ "$HTTP_CODE" = "200" ]; then
    success "NetBox API reachable."
else
    error "Unable to connect to NetBox API (HTTP ${HTTP_CODE})"
    exit 1
fi

echo

}

###############################################################################
# Display Statistics
###############################################################################

show_statistics() {

TAG_COUNT=$(api_get "/api/extras/tags/" | grep -o '"count":[0-9]*' | head -1 | cut -d: -f2)

CONTEXT_COUNT=$(api_get "/api/extras/config-contexts/" | grep -o '"count":[0-9]*' | head -1 | cut -d: -f2)

FIELD_COUNT=$(api_get "/api/extras/custom-fields/" | grep -o '"count":[0-9]*' | head -1 | cut -d: -f2)

CHOICESET_COUNT=$(api_get "/api/extras/custom-field-choice-sets/" | grep -o '"count":[0-9]*' | head -1 | cut -d: -f2)

echo
echo "=============================================================="
echo "                 NETBOX OBJECT SUMMARY"
echo "=============================================================="

printf "%-35s : %s\n" "Tags" "$TAG_COUNT"
printf "%-35s : %s\n" "Configuration Contexts" "$CONTEXT_COUNT"
printf "%-35s : %s\n" "Custom Fields" "$FIELD_COUNT"
printf "%-35s : %s\n" "Choice Sets" "$CHOICESET_COUNT"

echo "=============================================================="
echo

}

###############################################################################
# Final Verification
###############################################################################

verify_everything() {

info "Performing Final Verification..."

verify_tags
verify_contexts

verify_context "vmware-awx-context"
verify_context "pxe-centos-context"
verify_context "pxe-rockyos-context"
verify_context "patch-context"
verify_context "repo-config-context"
verify_context "centostorocky-context"
verify_context "patch-el8-context"
verify_context "centos-patch-context"
verify_context "rocky-patch-context"

echo

success "Verification Complete"

}

###############################################################################
# Completion Banner
###############################################################################

finish() {

echo
echo -e "${GREEN}"

echo "==============================================================="
echo "               NETBOX BOOTSTRAP COMPLETED"
echo "==============================================================="
echo
echo "Objects Created/Updated:"
echo
echo " ✔ Tags"
echo " ✔ Configuration Contexts"
echo " ✔ Patch Contexts"
echo " ✔ Repository Context"
echo " ✔ VMware Context"
echo " ✔ PXE Contexts"
echo " ✔ Migration Context"
echo " ✔ EL8 Patch Context"
echo " ✔ Custom Fields"
echo " ✔ Choice Sets"
echo
echo "==============================================================="
echo "      NetBox Bootstrap Finished Successfully"
echo "==============================================================="

echo -e "${NC}"

}

###############################################################################
# Main Execution
###############################################################################

banner

test_api_connection

create_tags

create_vmware_awx_context
create_pxe_centos_context
create_pxe_rocky_context

create_patch_context
create_repo_config_context
create_centostorocky_context
create_patch_el8_context
create_centos_patch_context
create_rocky_patch_context

#update_centos_patch_context
#update_rocky_patch_context

create_cpu_count_cf
create_ram_cf
create_disk_cf
create_vmtype_cf
create_kernel_cf
create_expected_kernel_cf
create_last_patch_cf
create_patch_status_cf

verify_everything

show_statistics

finish

exit 0
