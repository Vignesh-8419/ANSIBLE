#!/bin/bash
set -euo pipefail

# ============================================================
# NETBOX SPECIFIC DEVICE CREATION TOOL
# Separate script - does NOT modify Device_Creation_Netbox.sh
# ============================================================

# ---------------- CONFIG ----------------

NETBOX_URL="https://192.168.253.143/api"
NETBOX_TOKEN="PUT_YOUR_NETBOX_TOKEN_HERE"

SSH_USER="admin"
SSH_PASS="PUT_YOUR_SSH_PASSWORD_HERE"

SITE_ID=1
DEVICETYPE_ID=1
DEVICEROLE_ID=1

HDR="Content-Type: application/json"

SUCCESS_LIST=""
FAILED_LIST=""

# ============================================================
# COLORS
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ============================================================
# BANNER
# ============================================================

banner() {
    clear
    echo
    echo "============================================================"
    echo "        NETBOX SPECIFIC DEVICE CREATION TOOL"
    echo "============================================================"
    echo
}

banner

# ============================================================
# DEPENDENCY CHECK
# ============================================================

echo "Checking dependencies..."

for cmd in curl jq ssh sshpass ping
do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo
        echo -e "${RED}ERROR: Missing dependency: $cmd${NC}"

        case "$cmd" in
            jq)
                echo "Install: yum install -y jq"
                ;;
            sshpass)
                echo "Install: yum install -y sshpass"
                ;;
            *)
                echo "Please install the package providing: $cmd"
                ;;
        esac

        exit 1
    fi
done

echo -e "${GREEN}Dependencies OK${NC}"
echo

# ============================================================
# CONFIG VALIDATION
# ============================================================

if [ "$NETBOX_TOKEN" = "PUT_YOUR_NETBOX_TOKEN_HERE" ]; then
    echo -e "${RED}ERROR: Update NETBOX_TOKEN in the script.${NC}"
    exit 1
fi

if [ "$SSH_PASS" = "PUT_YOUR_SSH_PASSWORD_HERE" ]; then
    echo -e "${RED}ERROR: Update SSH_PASS in the script.${NC}"
    exit 1
fi

# ============================================================
# API FUNCTIONS
# ============================================================

api_get() {
    curl -sk \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$1"
}

api_post() {
    local URL="$1"
    local DATA="$2"

    curl -sk -X POST \
        "$URL" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "$DATA"
}

api_patch() {
    local URL="$1"
    local DATA="$2"

    curl -sk -X PATCH \
        "$URL" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "$DATA"
}

urlencode() {
    jq -rn --arg v "$1" '$v | @uri'
}

slugify() {
    echo "$1" |
        tr '[:upper:]' '[:lower:]' |
        tr ' ' '-' |
        sed 's/[^a-z0-9-]//g'
}

# ============================================================
# NETBOX CONNECTIVITY CHECK
# ============================================================

echo "Checking NetBox API..."

HTTP_CODE=$(curl -sk \
    -o /dev/null \
    -w "%{http_code}" \
    -H "Authorization: Token $NETBOX_TOKEN" \
    "$NETBOX_URL/status/")

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}ERROR: NetBox API is not reachable${NC}"
    echo "HTTP Code: $HTTP_CODE"
    exit 1
fi

echo -e "${GREEN}NetBox API reachable${NC}"

# ============================================================
# JSON ESCAPE
# ============================================================

json_string() {
    jq -Rn --arg value "$1" '$value'
}

# ============================================================
# GET OR CREATE CLUSTER TYPE
# ============================================================

get_or_create_cluster_type() {

    local TYPE_NAME="$1"
    local TYPE_ID
    local RESPONSE
    local SLUG

    TYPE_ID=$(api_get \
        "$NETBOX_URL/virtualization/cluster-types/?name=$(urlencode "$TYPE_NAME")" |
        jq -r '.results[0].id // empty')

    if [ -n "$TYPE_ID" ] && [ "$TYPE_ID" != "null" ]; then
        echo "$TYPE_ID"
        return 0
    fi

    SLUG=$(slugify "$TYPE_NAME")

    RESPONSE=$(api_post \
        "$NETBOX_URL/virtualization/cluster-types/" \
        "{\"name\":$(json_string "$TYPE_NAME"),\"slug\":$(json_string "$SLUG")}")

    TYPE_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

    if [ -z "$TYPE_ID" ] || [ "$TYPE_ID" = "null" ]; then
        echo -e "${RED}ERROR: Failed to create cluster type${NC}" >&2
        echo "$RESPONSE" | jq . >&2
        return 1
    fi

    echo "$TYPE_ID"
}

# ============================================================
# GET OR CREATE CLUSTER GROUP
# ============================================================

get_or_create_cluster_group() {

    local GROUP_NAME="$1"
    local GROUP_ID
    local RESPONSE
    local SLUG

    GROUP_ID=$(api_get \
        "$NETBOX_URL/virtualization/cluster-groups/?name=$(urlencode "$GROUP_NAME")" |
        jq -r '.results[0].id // empty')

    if [ -n "$GROUP_ID" ] && [ "$GROUP_ID" != "null" ]; then
        echo "$GROUP_ID"
        return 0
    fi

    SLUG=$(slugify "$GROUP_NAME")

    RESPONSE=$(api_post \
        "$NETBOX_URL/virtualization/cluster-groups/" \
        "{\"name\":$(json_string "$GROUP_NAME"),\"slug\":$(json_string "$SLUG")}")

    GROUP_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

    if [ -z "$GROUP_ID" ] || [ "$GROUP_ID" = "null" ]; then
        echo -e "${RED}ERROR: Failed to create cluster group${NC}" >&2
        echo "$RESPONSE" | jq . >&2
        return 1
    fi

    echo "$GROUP_ID"
}

# ============================================================
# GET OR CREATE CLUSTER
# ============================================================

get_or_create_cluster() {

    local TYPE_NAME="$1"
    local GROUP_NAME="$2"
    local CLUSTER_NAME="$3"

    local TYPE_ID
    local GROUP_ID
    local CLUSTER_ID
    local RESPONSE

    echo "Cluster Type : $TYPE_NAME" >&2
    echo "Cluster Group: $GROUP_NAME" >&2
    echo "Cluster Name : $CLUSTER_NAME" >&2

    TYPE_ID=$(get_or_create_cluster_type "$TYPE_NAME")
    GROUP_ID=$(get_or_create_cluster_group "$GROUP_NAME")

    CLUSTER_ID=$(api_get \
        "$NETBOX_URL/virtualization/clusters/?name=$(urlencode "$CLUSTER_NAME")" |
        jq -r '.results[0].id // empty')

    if [ -n "$CLUSTER_ID" ] && [ "$CLUSTER_ID" != "null" ]; then
        echo "Cluster already exists: $CLUSTER_NAME" >&2

        api_patch \
            "$NETBOX_URL/virtualization/clusters/$CLUSTER_ID/" \
            "{\"type\":$TYPE_ID,\"group\":$GROUP_ID,\"scope_type\":\"dcim.site\",\"scope_id\":$SITE_ID}" \
            >/dev/null || true

        echo "$CLUSTER_ID"
        return 0
    fi

    echo "Creating cluster: $CLUSTER_NAME" >&2

    RESPONSE=$(api_post \
        "$NETBOX_URL/virtualization/clusters/" \
        "{
            \"name\":$(json_string "$CLUSTER_NAME"),
            \"type\":$TYPE_ID,
            \"group\":$GROUP_ID,
            \"scope_type\":\"dcim.site\",
            \"scope_id\":$SITE_ID
        }")

    CLUSTER_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

    if [ -z "$CLUSTER_ID" ] || [ "$CLUSTER_ID" = "null" ]; then
        echo -e "${RED}ERROR: Failed to create cluster${NC}" >&2
        echo "$RESPONSE" | jq . >&2
        return 1
    fi

    echo "$CLUSTER_ID"
}

# ============================================================
# GET TAG ID
# ============================================================

get_tag_id() {

    local TAG_NAME="$1"

    api_get \
        "$NETBOX_URL/extras/tags/?name=$(urlencode "$TAG_NAME")" |
        jq -r '.results[0].id // empty'
}

# ============================================================
# ASSIGN TAGS BASED ON CLUSTER
# ============================================================

assign_tags() {

    local DEVICE_ID="$1"
    local CLUSTER_NAME="$2"

    local TAGS=()
    local TAG_IDS=()
    local TAG_ID
    local JSON_TAGS
    local RESPONSE

    case "$CLUSTER_NAME" in

        centos-07-servers)
            TAGS=(
                "centostorocky-context"
                "patch-context"
                "pxe-centos-context"
                "repo-config-context"
                "vmware-awx-context"
                "centos-patch-context"
            )
            ;;

        rocky-8-servers)
            TAGS=(
                "patch-el8-context"
                "pxe-rockyos-context"
                "repo-config-context"
                "vmware-awx-context"
                "rocky-patch-context"
            )
            ;;

        rocky-9-servers)
            TAGS=(
                "patch-el9-context"
                "pxe-rocky9-context"
                "repo-config-context"
                "vmware-awx-context"
                "rocky9-patch-context"
            )
            ;;

        *)
            echo -e "${YELLOW}No predefined tags for cluster: $CLUSTER_NAME${NC}"
            return 0
            ;;
    esac

    echo "Assigning tags..."

    for TAG in "${TAGS[@]}"
    do
        TAG_ID=$(get_tag_id "$TAG")

        if [ -n "$TAG_ID" ] && [ "$TAG_ID" != "null" ]; then
            echo "  Adding tag: $TAG"
            TAG_IDS+=("$TAG_ID")
        else
            echo -e "${YELLOW}  Tag not found: $TAG${NC}"
        fi
    done

    if [ "${#TAG_IDS[@]}" -eq 0 ]; then
        echo -e "${YELLOW}No tags found to assign${NC}"
        return 0
    fi

    JSON_TAGS=$(printf '%s\n' "${TAG_IDS[@]}" |
        jq -R . |
        jq -s .)

    RESPONSE=$(api_patch \
        "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
        "{\"tags\":$JSON_TAGS}")

    if echo "$RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
        echo -e "${GREEN}Tags assigned successfully${NC}"
    else
        echo -e "${RED}Failed assigning tags${NC}"
        echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
    fi
}

# ============================================================
# CREATE OR GET DEVICE
# ============================================================

create_or_update_device() {

    local HOSTNAME="$1"
    local CLUSTER_ID="$2"
    local STATUS="$3"

    local DEVICE_ID
    local RESPONSE

    DEVICE_ID=$(api_get \
        "$NETBOX_URL/dcim/devices/?name=$(urlencode "$HOSTNAME")" |
        jq -r '.results[0].id // empty')

    if [ -n "$DEVICE_ID" ] && [ "$DEVICE_ID" != "null" ]; then

        echo "Device already exists. Updating..."

        RESPONSE=$(api_patch \
            "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
            "{
                \"cluster\":$CLUSTER_ID,
                \"status\":$(json_string "$STATUS")
            }")

        if ! echo "$RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
            echo -e "${RED}Failed updating device${NC}" >&2
            echo "$RESPONSE" | jq . >&2
            return 1
        fi

        echo "$DEVICE_ID"
        return 0
    fi

    echo "Creating device..."

    RESPONSE=$(api_post \
        "$NETBOX_URL/dcim/devices/" \
        "{
            \"name\":$(json_string "$HOSTNAME"),
            \"device_type\":$DEVICETYPE_ID,
            \"role\":$DEVICEROLE_ID,
            \"site\":$SITE_ID,
            \"cluster\":$CLUSTER_ID,
            \"status\":$(json_string "$STATUS")
        }")

    DEVICE_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

    if [ -z "$DEVICE_ID" ] || [ "$DEVICE_ID" = "null" ]; then
        echo -e "${RED}Failed creating device${NC}" >&2
        echo "$RESPONSE" | jq . >&2
        return 1
    fi

    echo "$DEVICE_ID"
}

# ============================================================
# CREATE OR GET INTERFACE
# ============================================================

get_or_create_interface() {

    local DEVICE_ID="$1"
    local IFACE="$2"

    local INTERFACE_ID
    local RESPONSE

    INTERFACE_ID=$(api_get \
        "$NETBOX_URL/dcim/interfaces/?device_id=$DEVICE_ID&name=$(urlencode "$IFACE")" |
        jq -r '.results[0].id // empty')

    if [ -n "$INTERFACE_ID" ] && [ "$INTERFACE_ID" != "null" ]; then
        echo "$INTERFACE_ID"
        return 0
    fi

    echo "Creating interface: $IFACE" >&2

    RESPONSE=$(api_post \
        "$NETBOX_URL/dcim/interfaces/" \
        "{
            \"device\":$DEVICE_ID,
            \"name\":$(json_string "$IFACE"),
            \"type\":\"1000base-t\"
        }")

    INTERFACE_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

    if [ -z "$INTERFACE_ID" ] || [ "$INTERFACE_ID" = "null" ]; then
        echo -e "${RED}Failed creating interface${NC}" >&2
        echo "$RESPONSE" | jq . >&2
        return 1
    fi

    echo "$INTERFACE_ID"
}

# ============================================================
# CREATE OR ASSIGN IP
# ============================================================

create_or_assign_ip() {

    local IPADDR="$1"
    local INTERFACE_ID="$2"

    local IP_ID
    local RESPONSE

    IP_ID=$(api_get \
        "$NETBOX_URL/ipam/ip-addresses/?address=$(urlencode "$IPADDR")" |
        jq -r '.results[0].id // empty')

    if [ -n "$IP_ID" ] && [ "$IP_ID" != "null" ]; then

        echo "IP already exists. Assigning to interface..." >&2

        RESPONSE=$(api_patch \
            "$NETBOX_URL/ipam/ip-addresses/$IP_ID/" \
            "{
                \"assigned_object_type\":\"dcim.interface\",
                \"assigned_object_id\":$INTERFACE_ID
            }")

        if ! echo "$RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
            echo -e "${RED}Failed assigning existing IP${NC}" >&2
            echo "$RESPONSE" | jq . >&2
            return 1
        fi

        echo "$IP_ID"
        return 0
    fi

    echo "Creating IP: $IPADDR" >&2

    RESPONSE=$(api_post \
        "$NETBOX_URL/ipam/ip-addresses/" \
        "{
            \"address\":$(json_string "$IPADDR"),
            \"assigned_object_type\":\"dcim.interface\",
            \"assigned_object_id\":$INTERFACE_ID,
            \"status\":\"active\"
        }")

    IP_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

    if [ -z "$IP_ID" ] || [ "$IP_ID" = "null" ]; then
        echo -e "${RED}Failed creating IP${NC}" >&2
        echo "$RESPONSE" | jq . >&2
        return 1
    fi

    echo "$IP_ID"
}

# ============================================================
# SET PRIMARY IP
# ============================================================

set_primary_ip() {

    local DEVICE_ID="$1"
    local IP_ID="$2"
    local CLUSTER_ID="$3"
    local STATUS="$4"

    local RESPONSE

    echo "Assigning Primary IP..."

    RESPONSE=$(api_patch \
        "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
        "{
            \"cluster\":$CLUSTER_ID,
            \"status\":$(json_string "$STATUS"),
            \"primary_ip4\":$IP_ID
        }")

    if ! echo "$RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
        echo -e "${RED}Failed assigning Primary IP${NC}"
        echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
        return 1
    fi

    echo -e "${GREEN}Primary IP assigned successfully${NC}"
}

# ============================================================
# ASSIGN MAC ADDRESS
# ============================================================

assign_mac() {

    local INTERFACE_ID="$1"
    local MAC="$2"

    local MAC_OBJ_ID
    local RESPONSE

    [ -z "$MAC" ] && return 0

    MAC=$(echo "$MAC" | tr '[:lower:]' '[:upper:]')

    MAC_OBJ_ID=$(api_get \
        "$NETBOX_URL/dcim/mac-addresses/?mac_address=$(urlencode "$MAC")" |
        jq -r '.results[0].id // empty')

    if [ -z "$MAC_OBJ_ID" ] || [ "$MAC_OBJ_ID" = "null" ]; then

        RESPONSE=$(api_post \
            "$NETBOX_URL/dcim/mac-addresses/" \
            "{
                \"mac_address\":$(json_string "$MAC"),
                \"assigned_object_type\":\"dcim.interface\",
                \"assigned_object_id\":$INTERFACE_ID
            }")

        MAC_OBJ_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

        if [ -z "$MAC_OBJ_ID" ] || [ "$MAC_OBJ_ID" = "null" ]; then
            echo -e "${YELLOW}Warning: Failed creating MAC object${NC}"
            echo "$RESPONSE" | jq . 2>/dev/null || true
            return 0
        fi

    else

        api_patch \
            "$NETBOX_URL/dcim/mac-addresses/$MAC_OBJ_ID/" \
            "{
                \"assigned_object_type\":\"dcim.interface\",
                \"assigned_object_id\":$INTERFACE_ID
            }" >/dev/null
    fi

    api_patch \
        "$NETBOX_URL/dcim/interfaces/$INTERFACE_ID/" \
        "{\"primary_mac_address\":$MAC_OBJ_ID}" >/dev/null
}

# ============================================================
# UPDATE AUTO CUSTOM FIELDS
# ============================================================

update_auto_custom_fields() {

    local DEVICE_ID="$1"
    local CPU_COUNT="$2"
    local RAM_GB="$3"
    local DISK_GB="$4"
    local VM_TYPE="$5"
    local KERNEL="$6"

    local RESPONSE

    RESPONSE=$(api_patch \
        "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
        "{
            \"custom_fields\": {
                \"cpu_count\": $CPU_COUNT,
                \"ram_gb\": $RAM_GB,
                \"disk_gb\": $(json_string "$DISK_GB"),
                \"vm_type\": $(json_string "$VM_TYPE"),
                \"kernel\": $(json_string "$KERNEL")
            }
        }")

    if ! echo "$RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
        echo -e "${YELLOW}Warning: Custom fields could not be updated${NC}"
        echo "$RESPONSE" | jq . 2>/dev/null || true
    fi
}

# ============================================================
# MANUAL DEVICE
# Only hostname + IP required
# ============================================================

sync_manual_device() {

    local HOSTNAME="$1"
    local IPADDR="$2"
    local CLUSTER_ID="$3"
    local CLUSTER_NAME="$4"

    local DEVICE_ID
    local INTERFACE_ID
    local IP_ID

    echo
    echo "------------------------------------------------------------"
    echo -e "${BLUE}Processing: $HOSTNAME${NC}"
    echo "------------------------------------------------------------"

    echo "IP       : $IPADDR"
    echo "Mode     : Manual"
    echo "Rest data: Not required"

    DEVICE_ID=$(create_or_update_device \
        "$HOSTNAME" \
        "$CLUSTER_ID" \
        "staged")

    echo "Device ID: $DEVICE_ID"

    # Automatic internal interface for manual devices
    INTERFACE_ID=$(get_or_create_interface \
        "$DEVICE_ID" \
        "eth0")

    echo "Interface ID: $INTERFACE_ID"

    IP_ID=$(create_or_assign_ip \
        "$IPADDR" \
        "$INTERFACE_ID")

    echo "IP ID: $IP_ID"

    # IP is now assigned to the interface BEFORE becoming Primary IP
    set_primary_ip \
        "$DEVICE_ID" \
        "$IP_ID" \
        "$CLUSTER_ID" \
        "staged"

    assign_tags \
        "$DEVICE_ID" \
        "$CLUSTER_NAME"

    SUCCESS_LIST+="$HOSTNAME"$'\n'

    echo
    echo -e "${GREEN}✓ Finished: $HOSTNAME${NC}"
}

# ============================================================
# AUTOMATIC SSH DISCOVERY
# ============================================================

discover_and_sync_device() {

    local REMOTE_HOST="$1"
    local CLUSTER_ID="$2"
    local CLUSTER_NAME="$3"

    local HOSTNAME
    local IFACE_DATA
    local IFACE
    local IPADDR
    local MAC
    local CPU_COUNT
    local RAM_GB
    local DISK_GB
    local VM_TYPE
    local KERNEL
    local UPTIME
    local DEVICE_ID
    local INTERFACE_ID
    local IP_ID

    echo
    echo "------------------------------------------------------------"
    echo -e "${BLUE}Processing: $REMOTE_HOST${NC}"
    echo "------------------------------------------------------------"

    echo "Checking connectivity..."

    if ! ping -c1 -W2 "$REMOTE_HOST" >/dev/null 2>&1; then
        echo -e "${RED}Host unreachable: $REMOTE_HOST${NC}"
        FAILED_LIST+="$REMOTE_HOST"$'\n'
        return 1
    fi

    if ! sshpass -p "$SSH_PASS" \
        ssh \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "echo ok" >/dev/null 2>&1; then

        echo -e "${RED}SSH failed: $REMOTE_HOST${NC}"
        FAILED_LIST+="$REMOTE_HOST"$'\n'
        return 1
    fi

    echo -e "${GREEN}Host reachable${NC}"
    echo "Discovering system information..."

    HOSTNAME=$(sshpass -p "$SSH_PASS" \
        ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "hostname -f 2>/dev/null || hostname" |
        tr -d '\r' |
        xargs)

    IFACE_DATA=$(sshpass -p "$SSH_PASS" \
        ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "ip -o -4 addr show scope global | head -1")

    IFACE=$(echo "$IFACE_DATA" | awk '{print $2}')
    IPADDR=$(echo "$IFACE_DATA" | awk '{print $4}')

    if [ -z "$HOSTNAME" ] ||
       [ -z "$IFACE" ] ||
       [ -z "$IPADDR" ]; then

        echo -e "${RED}Failed discovering hostname/interface/IP${NC}"
        FAILED_LIST+="$REMOTE_HOST"$'\n'
        return 1
    fi

    MAC=$(sshpass -p "$SSH_PASS" \
        ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "cat /sys/class/net/$IFACE/address 2>/dev/null" |
        tr '[:lower:]' '[:upper:]' |
        tr -d '\r' |
        xargs)

    CPU_COUNT=$(sshpass -p "$SSH_PASS" \
        ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "nproc")

    RAM_GB=$(sshpass -p "$SSH_PASS" \
        ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "awk '/MemTotal/ {printf \"%d\", (\$2/1024/1024)+0.5}' /proc/meminfo")

    DISK_GB=$(sshpass -p "$SSH_PASS" \
        ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "lsblk -bdno SIZE | awk '{s+=\$1} END {printf \"%.0f GB\",s/1024/1024/1024}'")

    VM_TYPE=$(sshpass -p "$SSH_PASS" \
        ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "systemd-detect-virt 2>/dev/null || true" |
        tr -d '\r' |
        xargs)

    [ -z "$VM_TYPE" ] && VM_TYPE="Physical"

    KERNEL=$(sshpass -p "$SSH_PASS" \
        ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "uname -r")

    UPTIME=$(sshpass -p "$SSH_PASS" \
        ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "uptime -p" 2>/dev/null || true)

    echo "Hostname : $HOSTNAME"
    echo "IP       : $IPADDR"
    echo "Interface: $IFACE"
    echo "MAC      : ${MAC:-N/A}"
    echo "CPU      : $CPU_COUNT"
    echo "RAM      : $RAM_GB GB"
    echo "Disk     : $DISK_GB"
    echo "Type     : $VM_TYPE"
    echo "Kernel   : $KERNEL"
    echo "Uptime   : $UPTIME"

    DEVICE_ID=$(create_or_update_device \
        "$HOSTNAME" \
        "$CLUSTER_ID" \
        "active")

    echo "Device ID: $DEVICE_ID"

    INTERFACE_ID=$(get_or_create_interface \
        "$DEVICE_ID" \
        "$IFACE")

    echo "Interface ID: $INTERFACE_ID"

    assign_mac \
        "$INTERFACE_ID" \
        "$MAC"

    IP_ID=$(create_or_assign_ip \
        "$IPADDR" \
        "$INTERFACE_ID")

    echo "IP ID: $IP_ID"

    set_primary_ip \
        "$DEVICE_ID" \
        "$IP_ID" \
        "$CLUSTER_ID" \
        "active"

    update_auto_custom_fields \
        "$DEVICE_ID" \
        "$CPU_COUNT" \
        "$RAM_GB" \
        "$DISK_GB" \
        "$VM_TYPE" \
        "$KERNEL"

    assign_tags \
        "$DEVICE_ID" \
        "$CLUSTER_NAME"

    SUCCESS_LIST+="$HOSTNAME"$'\n'

    echo
    echo -e "${GREEN}✓ Finished: $HOSTNAME${NC}"
}

# ============================================================
# STEP 1 - CENTOS 7
# ============================================================

echo
echo "============================================================"
echo "STEP 1 - CENTOS 7 DEVICES"
echo "============================================================"

CENTOS_CLUSTER_ID=$(get_or_create_cluster \
    "Physical" \
    "centos-07-servers" \
    "centos-07-servers")

echo "Cluster ID: $CENTOS_CLUSTER_ID"

sync_manual_device \
    "cent-07-01.vgs.com" \
    "192.168.253.131/24" \
    "$CENTOS_CLUSTER_ID" \
    "centos-07-servers" || true

sync_manual_device \
    "cent-07-02.vgs.com" \
    "192.168.253.132/24" \
    "$CENTOS_CLUSTER_ID" \
    "centos-07-servers" || true

# ============================================================
# STEP 2 - ROCKY 8 / AUTOMATIC DISCOVERY
# ============================================================

echo
echo "============================================================"
echo "STEP 2 - ROCKY 8 DEVICES - AUTOMATIC DISCOVERY"
echo "============================================================"

ROCKY8_CLUSTER_ID=$(get_or_create_cluster \
    "Physical" \
    "rocky-8-servers" \
    "rocky-8-servers")

echo "Cluster ID: $ROCKY8_CLUSTER_ID"

AUTO_HOSTS=(
    "netbox.vgs.com"
    "ansible-server-01.vgs.com"
)

for HOST in "${AUTO_HOSTS[@]}"
do
    discover_and_sync_device \
        "$HOST" \
        "$ROCKY8_CLUSTER_ID" \
        "rocky-8-servers" || true
done

# ============================================================
# STEP 3 - ROCKY 9
# ============================================================

echo
echo "============================================================"
echo "STEP 3 - ROCKY 9 DEVICE"
echo "============================================================"

ROCKY9_CLUSTER_ID=$(get_or_create_cluster \
    "Physical" \
    "rocky-9-servers" \
    "rocky-9-servers")

echo "Cluster ID: $ROCKY9_CLUSTER_ID"

sync_manual_device \
    "rocky-09-01.vgs.com" \
    "192.168.253.151/24" \
    "$ROCKY9_CLUSTER_ID" \
    "rocky-9-servers" || true

# ============================================================
# SUMMARY
# ============================================================

echo
echo "============================================================"
echo "                    FINAL SUMMARY"
echo "============================================================"

echo
echo -e "${GREEN}SUCCESSFUL HOSTS${NC}"

if [ -n "$SUCCESS_LIST" ]; then
    printf "%s" "$SUCCESS_LIST"
else
    echo "None"
fi

echo
echo -e "${RED}FAILED HOSTS${NC}"

if [ -n "$FAILED_LIST" ]; then
    printf "%s" "$FAILED_LIST"
else
    echo "0"
fi

SUCCESS_COUNT=$(printf "%s" "$SUCCESS_LIST" | sed '/^$/d' | wc -l)
FAILED_COUNT=$(printf "%s" "$FAILED_LIST" | sed '/^$/d' | wc -l)

echo
echo "Success Count: $SUCCESS_COUNT"
echo "Failed Count : $FAILED_COUNT"

echo
echo "============================================================"
echo -e "${GREEN}NETBOX SPECIFIC DEVICE CREATION COMPLETED${NC}"
echo "============================================================"
