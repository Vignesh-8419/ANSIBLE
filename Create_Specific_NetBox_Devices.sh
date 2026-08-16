#!/bin/bash
set -e

# ==========================================================
# NETBOX SPECIFIC DEVICE CREATION SCRIPT
# Separate script - does NOT modify Device_Creation_Netbox.sh
# ==========================================================

# ---------------- CONFIG ----------------

NETBOX_URL="https://192.168.253.143/api"
NETBOX_TOKEN="83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd"

SSH_USER="admin"
SSH_PASS="Vigneshv12$"

SITE_ID=1
DEVICETYPE_ID=1
DEVICEROLE_ID=1

HDR="Content-Type: application/json"

# ==========================================================
# COLORS
# ==========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

SUCCESS_LIST=""
FAILED_LIST=""

START_TIME=$(date +%s)

# ==========================================================
# FUNCTIONS
# ==========================================================

banner() {
    clear
    echo -e "${CYAN}"
    echo "============================================================"
    echo "        NETBOX SPECIFIC DEVICE CREATION TOOL"
    echo "============================================================"
    echo -e "${NC}"
}

slugify() {
    echo "$1" |
        tr '[:upper:]' '[:lower:]' |
        tr ' ' '-' |
        sed 's/[^a-z0-9-]//g'
}

urlencode() {
    jq -rn --arg v "$1" '$v|@uri'
}

api_get() {
    curl -sk \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$1"
}

api_post() {
    curl -sk -X POST \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "$2" \
        "$1"
}

api_patch() {
    curl -sk -X PATCH \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "$2" \
        "$1"
}

# ==========================================================
# GET OR CREATE
# ==========================================================

get_or_create() {

    local ENDPOINT="$1"
    local NAME="$2"
    local EXTRA_JSON="$3"

    local EXISTING_ID
    local SLUG

    SLUG=$(slugify "$NAME")

    EXISTING_ID=$(api_get \
        "$NETBOX_URL/$ENDPOINT/?name=$(urlencode "$NAME")" |
        jq -r '.results[0].id // empty')

    if [ -n "$EXISTING_ID" ] && [ "$EXISTING_ID" != "null" ]; then
        echo "$EXISTING_ID"
        return
    fi

    api_post \
        "$NETBOX_URL/$ENDPOINT/" \
        "{\"name\":\"$NAME\",\"slug\":\"$SLUG\"$EXTRA_JSON}" |
        jq -r '.id // empty'
}

# ==========================================================
# CLUSTER SETUP
# ==========================================================

get_cluster_id() {

    local TYPE_NAME="$1"
    local GROUP_NAME="$2"
    local CLUSTER_NAME="$3"

    local TYPE_ID
    local GROUP_ID
    local CLUSTER_ID

    echo -e "${BLUE}Cluster Type : $TYPE_NAME${NC}"
    echo -e "${BLUE}Cluster Group: $GROUP_NAME${NC}"
    echo -e "${BLUE}Cluster Name : $CLUSTER_NAME${NC}"

    TYPE_ID=$(get_or_create \
        "virtualization/cluster-types" \
        "$TYPE_NAME" \
        "")

    GROUP_ID=$(get_or_create \
        "virtualization/cluster-groups" \
        "$GROUP_NAME" \
        "")

    CLUSTER_ID=$(api_get \
        "$NETBOX_URL/virtualization/clusters/?name=$(urlencode "$CLUSTER_NAME")" |
        jq -r '.results[0].id // empty')

    if [ -z "$CLUSTER_ID" ] || [ "$CLUSTER_ID" = "null" ]; then

        CLUSTER_ID=$(api_post \
            "$NETBOX_URL/virtualization/clusters/" \
            "{\"name\":\"$CLUSTER_NAME\",\"type\":$TYPE_ID,\"group\":$GROUP_ID,\"site\":$SITE_ID}" |
            jq -r '.id // empty')

    fi

    echo "$CLUSTER_ID"
}

# ==========================================================
# GET TAG ID
# ==========================================================

get_tag_id() {

    local TAG_NAME="$1"

    api_get "$NETBOX_URL/extras/tags/?name=$(urlencode "$TAG_NAME")" |
        jq -r '.results[0].id // empty'
}

# ==========================================================
# ASSIGN TAGS BASED ON CLUSTER
# ==========================================================

assign_tags() {

    local DEVICE_ID="$1"
    local CLUSTER_NAME="$2"

    local TAGS=()
    local TAG_IDS=()

    echo -e "${CYAN}Assigning tags for cluster: $CLUSTER_NAME${NC}"

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
            echo -e "${YELLOW}No predefined tags for $CLUSTER_NAME${NC}"
            return
            ;;
    esac

    for TAG in "${TAGS[@]}"
    do

        TAG_ID=$(get_tag_id "$TAG")

        if [ -n "$TAG_ID" ] && [ "$TAG_ID" != "null" ]; then

            TAG_IDS+=("$TAG_ID")
            echo -e "${GREEN}  + $TAG${NC}"

        else

            echo -e "${YELLOW}  ! Tag not found: $TAG${NC}"

        fi

    done

    if [ ${#TAG_IDS[@]} -eq 0 ]; then
        echo -e "${YELLOW}No tags found to assign${NC}"
        return
    fi

    JSON_TAGS=$(printf '%s\n' "${TAG_IDS[@]}" |
        jq -R . |
        jq -s .)

    api_patch \
        "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
        "{\"tags\":$JSON_TAGS}" > /dev/null

    echo -e "${GREEN}Tags assigned successfully${NC}"
}

# ==========================================================
# CREATE OR UPDATE DEVICE
# ==========================================================

sync_device() {

    local HOSTNAME="$1"
    local IPADDR="$2"
    local CLUSTER_ID="$3"
    local STATUS="$4"
    local MODE="$5"
    local IFACE="$6"
    local MAC="$7"
    local CPU_COUNT="$8"
    local RAM_GB="$9"
    local DISK_GB="${10}"
    local VM_TYPE="${11}"
    local KERNEL="${12}"
    local UPTIME="${13}"

    echo ""
    echo "------------------------------------------------------------"
    echo -e "${BLUE}Processing: $HOSTNAME${NC}"
    echo "------------------------------------------------------------"

    echo "IP       : $IPADDR"
    echo "Interface: $IFACE"
    echo "MAC      : ${MAC:-N/A}"
    echo "CPU      : ${CPU_COUNT:-N/A}"
    echo "RAM      : ${RAM_GB:-N/A}"
    echo "Disk     : ${DISK_GB:-N/A}"
    echo "Type     : ${VM_TYPE:-N/A}"
    echo "Kernel   : ${KERNEL:-N/A}"
    echo "Uptime   : ${UPTIME:-N/A}"

    # ------------------------------------------------------
    # CHECK DEVICE
    # ------------------------------------------------------

    EXISTING_DEVICE_ID=$(api_get \
        "$NETBOX_URL/dcim/devices/?name=$(urlencode "$HOSTNAME")" |
        jq -r '.results[0].id // empty')

    if [ -z "$EXISTING_DEVICE_ID" ] ||
       [ "$EXISTING_DEVICE_ID" = "null" ]; then

        echo "Creating device..."

        DEVICE_ID=$(api_post \
            "$NETBOX_URL/dcim/devices/" \
            "{\"name\":\"$HOSTNAME\",\"device_type\":$DEVICETYPE_ID,\"role\":$DEVICEROLE_ID,\"site\":$SITE_ID,\"cluster\":$CLUSTER_ID,\"status\":\"$STATUS\"}" |
            jq -r '.id // empty')

    else

        DEVICE_ID="$EXISTING_DEVICE_ID"

        echo "Device already exists. Updating..."

        api_patch \
            "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
            "{\"cluster\":$CLUSTER_ID,\"status\":\"$STATUS\"}" \
            > /dev/null

    fi

    if [ -z "$DEVICE_ID" ] || [ "$DEVICE_ID" = "null" ]; then
        echo -e "${RED}Failed to create/update device: $HOSTNAME${NC}"
        FAILED_LIST+="$HOSTNAME"$'\n'
        return 1
    fi

    # ------------------------------------------------------
    # MANUAL MODE
    # No MAC / Interface / CPU / RAM / Disk required
    # ------------------------------------------------------

    if [ "$MODE" = "manual" ]; then

        echo "Manual mode: creating basic IP information only..."

        IP_ID=$(api_get \
            "$NETBOX_URL/ipam/ip-addresses/?address=$(urlencode "$IPADDR")" |
            jq -r '.results[0].id // empty')

        if [ -z "$IP_ID" ] || [ "$IP_ID" = "null" ]; then

            IP_ID=$(api_post \
                "$NETBOX_URL/ipam/ip-addresses/" \
                "{\"address\":\"$IPADDR\",\"status\":\"active\"}" |
                jq -r '.id // empty')

        fi

        if [ -z "$IP_ID" ] || [ "$IP_ID" = "null" ]; then
            echo -e "${RED}Failed to create IP: $IPADDR${NC}"
            FAILED_LIST+="$HOSTNAME"$'\n'
            return 1
        fi

        api_patch \
            "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
            "{\"cluster\":$CLUSTER_ID,\"status\":\"$STATUS\",\"primary_ip4\":$IP_ID}" \
            > /dev/null

    else

        # --------------------------------------------------
        # AUTOMATIC MODE - INTERFACE
        # --------------------------------------------------

        ALL_INTS=$(api_get \
            "$NETBOX_URL/dcim/interfaces/?device_id=$DEVICE_ID")

        INTERFACE_ID=$(echo "$ALL_INTS" |
            jq -r --arg IFACE "$IFACE" \
            '.results[] | select(.name == $IFACE) | .id // empty')

        if [ -z "$INTERFACE_ID" ] ||
           [ "$INTERFACE_ID" = "null" ]; then

            echo "Creating interface: $IFACE"

            INTERFACE_ID=$(api_post \
                "$NETBOX_URL/dcim/interfaces/" \
                "{\"device\":$DEVICE_ID,\"name\":\"$IFACE\",\"type\":\"1000base-t\"}" |
                jq -r '.id // empty')

        fi

        # --------------------------------------------------
        # MAC
        # --------------------------------------------------

        if [ -n "$MAC" ]; then

            MAC_OBJ_ID=$(api_get \
                "$NETBOX_URL/dcim/mac-addresses/?mac_address=$(urlencode "$MAC")" |
                jq -r '.results[0].id // empty')

            if [ -z "$MAC_OBJ_ID" ] ||
               [ "$MAC_OBJ_ID" = "null" ]; then

                MAC_OBJ_ID=$(api_post \
                    "$NETBOX_URL/dcim/mac-addresses/" \
                    "{\"mac_address\":\"$MAC\",\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID}" |
                    jq -r '.id // empty')

            else

                api_patch \
                    "$NETBOX_URL/dcim/mac-addresses/$MAC_OBJ_ID/" \
                    "{\"assigned_object_id\":$INTERFACE_ID}" \
                    > /dev/null

            fi

            if [ -n "$MAC_OBJ_ID" ] &&
               [ "$MAC_OBJ_ID" != "null" ]; then

                api_patch \
                    "$NETBOX_URL/dcim/interfaces/$INTERFACE_ID/" \
                    "{\"primary_mac_address\":$MAC_OBJ_ID}" \
                    > /dev/null

            fi

        fi

        # --------------------------------------------------
        # IP
        # --------------------------------------------------

        IP_ID=$(api_get \
            "$NETBOX_URL/ipam/ip-addresses/?address=$(urlencode "$IPADDR")" |
            jq -r '.results[0].id // empty')

        if [ -z "$IP_ID" ] ||
           [ "$IP_ID" = "null" ]; then

            IP_ID=$(api_post \
                "$NETBOX_URL/ipam/ip-addresses/" \
                "{\"address\":\"$IPADDR\",\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID,\"status\":\"active\"}" |
                jq -r '.id // empty')

        else

            api_patch \
                "$NETBOX_URL/ipam/ip-addresses/$IP_ID/" \
                "{\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID}" \
                > /dev/null

        fi

        api_patch \
            "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
            "{\"cluster\":$CLUSTER_ID,\"status\":\"$STATUS\",\"primary_ip4\":$IP_ID}" \
            > /dev/null

        # --------------------------------------------------
        # CUSTOM FIELDS - AUTO ONLY
        # --------------------------------------------------

        api_patch \
            "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
            "{
                \"custom_fields\": {
                    \"cpu_count\": $CPU_COUNT,
                    \"ram_gb\": $RAM_GB,
                    \"disk_gb\": \"$DISK_GB\",
                    \"vm_type\": \"$VM_TYPE\",
                    \"kernel\": \"$KERNEL\"
                }
            }" > /dev/null

    fi

    # ------------------------------------------------------
    # TAGS
    # ------------------------------------------------------

    assign_tags "$DEVICE_ID" "$CURRENT_CLUSTER_NAME"

    echo -e "${GREEN}✓ Finished: $HOSTNAME${NC}"

    SUCCESS_LIST+="$HOSTNAME"$'\n'

    return 0
}

# ==========================================================
# AUTO DISCOVERY FUNCTION
# ==========================================================

discover_and_sync() {

    local REMOTE_HOST="$1"
    local CLUSTER_ID="$2"

    echo ""
    echo "============================================================"
    echo -e "${CYAN}AUTO DISCOVERY: $REMOTE_HOST${NC}"
    echo "============================================================"

    if ! ping -c1 -W2 "$REMOTE_HOST" >/dev/null 2>&1; then
        echo -e "${RED}Host unreachable: $REMOTE_HOST${NC}"
        FAILED_LIST+="$REMOTE_HOST"$'\n'
        return
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
        return
    fi

    echo -e "${GREEN}SSH connected successfully${NC}"

    HOSTNAME=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "hostname -f" 2>/dev/null | tr -d '\r' | xargs)

    IFACE_DATA=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "ip -o -4 addr show scope global | head -1" 2>/dev/null)

    IFACE=$(echo "$IFACE_DATA" | awk '{print $2}')
    IPADDR=$(echo "$IFACE_DATA" | awk '{print $4}')

    MAC=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "cat /sys/class/net/$IFACE/address" 2>/dev/null |
        tr '[:lower:]' '[:upper:]' |
        tr -d '\r' |
        xargs)

    CPU_COUNT=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "nproc" 2>/dev/null | xargs)

    RAM_GB=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "awk '/MemTotal/ {printf \"%d\", (\$2/1024/1024)+0.5}' /proc/meminfo" \
        2>/dev/null | xargs)

    DISK_GB=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "lsblk -bdno SIZE | awk '{s+=\$1} END {printf \"%.0f GB\",s/1024/1024/1024}'" \
        2>/dev/null | xargs)

    VM_TYPE=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "systemd-detect-virt" \
        2>/dev/null | tr -d '\r' | xargs)

    [ -z "$VM_TYPE" ] && VM_TYPE="Physical"

    KERNEL=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "uname -r" 2>/dev/null | tr -d '\r' | xargs)

    UPTIME=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "uptime -p" 2>/dev/null | tr -d '\r' | xargs)

    # Ensure IP has CIDR
    if [[ "$IPADDR" != */* ]]; then
        IPADDR="$IPADDR/24"
    fi

    sync_device \
        "$HOSTNAME" \
        "$IPADDR" \
        "$CLUSTER_ID" \
        "active" \
        "auto" \
        "$IFACE" \
        "$MAC" \
        "$CPU_COUNT" \
        "$RAM_GB" \
        "$DISK_GB" \
        "$VM_TYPE" \
        "$KERNEL" \
        "$UPTIME"
}

# ==========================================================
# CHECK DEPENDENCIES
# ==========================================================

banner

echo "Checking dependencies..."

for CMD in curl jq ping ssh sshpass
do
    if ! command -v "$CMD" >/dev/null 2>&1; then
        echo -e "${RED}Missing dependency: $CMD${NC}"
        exit 1
    fi
done

echo -e "${GREEN}Dependencies OK${NC}"

# ==========================================================
# NETBOX API CHECK
# ==========================================================

echo ""
echo "Checking NetBox API..."

HTTP_CODE=$(curl -sk \
    -o /dev/null \
    -w "%{http_code}" \
    -H "Authorization: Token $NETBOX_TOKEN" \
    "$NETBOX_URL/status/")

if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}NetBox API failed. HTTP Code: $HTTP_CODE${NC}"
    exit 1
fi

echo -e "${GREEN}NetBox API reachable${NC}"

# ==========================================================
# CLUSTER 1
# CENTOS 7
# ==========================================================

echo ""
echo "============================================================"
echo -e "${CYAN}STEP 1 - CENTOS 7 DEVICES${NC}"
echo "============================================================"

CURRENT_CLUSTER_NAME="centos-07-servers"

CENTOS_CLUSTER_ID=$(get_cluster_id \
    "Physical" \
    "centos-07-servers" \
    "centos-07-servers")

if [ -z "$CENTOS_CLUSTER_ID" ]; then
    echo -e "${RED}Failed to get/create CentOS cluster${NC}"
    exit 1
fi

echo "Cluster ID: $CENTOS_CLUSTER_ID"

sync_device \
    "cent-07-01.vgs.com" \
    "192.168.253.131/24" \
    "$CENTOS_CLUSTER_ID" \
    "staged" \
    "manual" \
    "" "" \
    "null" "null" \
    "" "" "" ""

sync_device \
    "cent-07-02.vgs.com" \
    "192.168.253.132/24" \
    "$CENTOS_CLUSTER_ID" \
    "staged" \
    "manual" \
    "" "" \
    "null" "null" \
    "" "" "" ""

# ==========================================================
# CLUSTER 2
# ROCKY 8 - AUTOMATIC SSH DISCOVERY
# ==========================================================

echo ""
echo "============================================================"
echo -e "${CYAN}STEP 2 - ROCKY 8 / AUTOMATIC DISCOVERY${NC}"
echo "============================================================"

CURRENT_CLUSTER_NAME="rocky-8-servers"

ROCKY8_CLUSTER_ID=$(get_cluster_id \
    "Physical" \
    "rocky-8-servers" \
    "rocky-8-servers")

if [ -z "$ROCKY8_CLUSTER_ID" ]; then
    echo -e "${RED}Failed to get/create Rocky 8 cluster${NC}"
    exit 1
fi

echo "Cluster ID: $ROCKY8_CLUSTER_ID"

discover_and_sync \
    "netbox.vgs.com" \
    "$ROCKY8_CLUSTER_ID"

discover_and_sync \
    "ansible-server-01.vgs.com" \
    "$ROCKY8_CLUSTER_ID"

# ==========================================================
# CLUSTER 3
# ROCKY 9
# ==========================================================

echo ""
echo "============================================================"
echo -e "${CYAN}STEP 3 - ROCKY 9 DEVICE${NC}"
echo "============================================================"

CURRENT_CLUSTER_NAME="rocky-9-servers"

ROCKY9_CLUSTER_ID=$(get_cluster_id \
    "Physical" \
    "rocky-9-servers" \
    "rocky-9-servers")

if [ -z "$ROCKY9_CLUSTER_ID" ]; then
    echo -e "${RED}Failed to get/create Rocky 9 cluster${NC}"
    exit 1
fi

echo "Cluster ID: $ROCKY9_CLUSTER_ID"

sync_device \
    "rocky-09-01.vgs.com" \
    "192.168.253.151/24" \
    "$ROCKY9_CLUSTER_ID" \
    "staged" \
    "manual" \
    "" "" \
    "null" "null" \
    "" "" "" ""

# ==========================================================
# SUMMARY
# ==========================================================

END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))

SUCCESS_COUNT=$(echo "$SUCCESS_LIST" | sed '/^$/d' | wc -l)
FAILED_COUNT=$(echo "$FAILED_LIST" | sed '/^$/d' | wc -l)

echo ""
echo "============================================================"
echo -e "${CYAN}                 EXECUTION SUMMARY${NC}"
echo "============================================================"

echo ""
echo -e "${GREEN}SUCCESSFUL HOSTS${NC}"

if [ "$SUCCESS_COUNT" -eq 0 ]; then
    echo "None"
else
    echo "$SUCCESS_LIST"
fi

echo -e "${RED}FAILED HOSTS${NC}"

if [ "$FAILED_COUNT" -eq 0 ]; then
    echo "0"
else
    echo "$FAILED_LIST"
fi

echo ""
echo "Success Count : $SUCCESS_COUNT"
echo "Failed Count  : $FAILED_COUNT"
echo -e "${CYAN}Execution Time: ${RUNTIME} seconds${NC}"

echo "============================================================"
