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
# UI
# ==========================================================

banner() {
    clear
    echo -e "${CYAN}"
    echo "============================================================"
    echo "        NETBOX SPECIFIC DEVICE CREATION TOOL"
    echo "============================================================"
    echo -e "${NC}"
}

# ==========================================================
# HELPERS
# ==========================================================

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
# GET OR CREATE RESOURCE
# IMPORTANT:
# Only the ID is printed to stdout.
# ==========================================================

get_or_create() {

    local ENDPOINT="$1"
    local NAME="$2"
    local EXTRA_JSON="$3"

    local EXISTING_ID
    local SLUG
    local RESPONSE
    local CREATED_ID

    SLUG=$(slugify "$NAME")

    EXISTING_ID=$(api_get \
        "$NETBOX_URL/$ENDPOINT/?name=$(urlencode "$NAME")" |
        jq -r '.results[0].id // empty')

    if [ -n "$EXISTING_ID" ] &&
       [ "$EXISTING_ID" != "null" ]; then

        echo "$EXISTING_ID"
        return 0
    fi

    RESPONSE=$(api_post \
        "$NETBOX_URL/$ENDPOINT/" \
        "{\"name\":\"$NAME\",\"slug\":\"$SLUG\"$EXTRA_JSON}")

    CREATED_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

    if [ -z "$CREATED_ID" ] ||
       [ "$CREATED_ID" = "null" ]; then

        echo -e "${RED}Failed creating resource: $NAME${NC}" >&2
        echo "$RESPONSE" | jq . >&2
        return 1
    fi

    echo "$CREATED_ID"
}

# ==========================================================
# GET OR CREATE CLUSTER
# IMPORTANT:
# Informational output goes to stderr.
# Only Cluster ID goes to stdout.
# ==========================================================

get_cluster_id() {

    local TYPE_NAME="$1"
    local GROUP_NAME="$2"
    local CLUSTER_NAME="$3"

    local TYPE_ID
    local GROUP_ID
    local CLUSTER_ID
    local RESPONSE

    echo -e "${BLUE}Cluster Type : $TYPE_NAME${NC}" >&2
    echo -e "${BLUE}Cluster Group: $GROUP_NAME${NC}" >&2
    echo -e "${BLUE}Cluster Name : $CLUSTER_NAME${NC}" >&2

    TYPE_ID=$(get_or_create \
        "virtualization/cluster-types" \
        "$TYPE_NAME" \
        "")

    if [ -z "$TYPE_ID" ] ||
       [ "$TYPE_ID" = "null" ]; then

        echo -e "${RED}Failed to get/create Cluster Type${NC}" >&2
        return 1
    fi

    GROUP_ID=$(get_or_create \
        "virtualization/cluster-groups" \
        "$GROUP_NAME" \
        "")

    if [ -z "$GROUP_ID" ] ||
       [ "$GROUP_ID" = "null" ]; then

        echo -e "${RED}Failed to get/create Cluster Group${NC}" >&2
        return 1
    fi

    CLUSTER_ID=$(api_get \
        "$NETBOX_URL/virtualization/clusters/?name=$(urlencode "$CLUSTER_NAME")" |
        jq -r '.results[0].id // empty')

    if [ -z "$CLUSTER_ID" ] ||
       [ "$CLUSTER_ID" = "null" ]; then

        echo -e "${YELLOW}Creating cluster: $CLUSTER_NAME${NC}" >&2

        RESPONSE=$(api_post \
            "$NETBOX_URL/virtualization/clusters/" \
            "{\"name\":\"$CLUSTER_NAME\",\"type\":$TYPE_ID,\"group\":$GROUP_ID,\"site\":$SITE_ID}")

        CLUSTER_ID=$(echo "$RESPONSE" |
            jq -r '.id // empty')

        if [ -z "$CLUSTER_ID" ] ||
           [ "$CLUSTER_ID" = "null" ]; then

            echo -e "${RED}Failed creating cluster: $CLUSTER_NAME${NC}" >&2
            echo "$RESPONSE" | jq . >&2
            return 1
        fi

    else

        echo -e "${GREEN}Cluster already exists: $CLUSTER_NAME${NC}" >&2

    fi

    # ONLY ID ON STDOUT
    echo "$CLUSTER_ID"
}

# ==========================================================
# GET TAG ID
# ==========================================================

get_tag_id() {

    local TAG_NAME="$1"

    api_get \
        "$NETBOX_URL/extras/tags/?name=$(urlencode "$TAG_NAME")" |
        jq -r '.results[0].id // empty'
}

# ==========================================================
# ASSIGN TAGS
# ==========================================================

assign_tags() {

    local DEVICE_ID="$1"
    local CLUSTER_NAME="$2"

    local TAGS=()
    local TAG_IDS=()
    local TAG
    local TAG_ID
    local JSON_TAGS

    echo -e "${CYAN}Assigning tags for: $CLUSTER_NAME${NC}"

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

            echo -e "${YELLOW}No predefined tags for: $CLUSTER_NAME${NC}"
            return 0
            ;;
    esac

    for TAG in "${TAGS[@]}"
    do

        TAG_ID=$(get_tag_id "$TAG")

        if [ -n "$TAG_ID" ] &&
           [ "$TAG_ID" != "null" ]; then

            TAG_IDS+=("$TAG_ID")
            echo -e "${GREEN}  + Adding Tag: $TAG${NC}"

        else

            echo -e "${YELLOW}  ! Tag not found: $TAG${NC}"

        fi

    done

    if [ ${#TAG_IDS[@]} -eq 0 ]; then
        echo -e "${YELLOW}No valid tags found${NC}"
        return 0
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
    local CLUSTER_NAME="$4"
    local STATUS="$5"
    local MODE="$6"
    local IFACE="$7"
    local MAC="$8"
    local CPU_COUNT="$9"
    local RAM_GB="${10}"
    local DISK_GB="${11}"
    local VM_TYPE="${12}"
    local KERNEL="${13}"
    local UPTIME="${14}"

    local EXISTING_DEVICE_ID
    local DEVICE_ID
    local RESPONSE
    local IP_ID
    local ALL_INTS
    local INTERFACE_ID
    local MAC_OBJ_ID

    echo ""
    echo "------------------------------------------------------------"
    echo -e "${BLUE}Processing: $HOSTNAME${NC}"
    echo "------------------------------------------------------------"

    echo "IP       : $IPADDR"

    if [ "$MODE" = "auto" ]; then
        echo "Interface: $IFACE"
        echo "MAC      : $MAC"
        echo "CPU      : $CPU_COUNT"
        echo "RAM      : $RAM_GB GB"
        echo "Disk     : $DISK_GB"
        echo "Type     : $VM_TYPE"
        echo "Kernel   : $KERNEL"
        echo "Uptime   : $UPTIME"
    else
        echo "Mode     : Manual"
        echo "Rest data: Not required"
    fi

    # ------------------------------------------------------
    # DEVICE CHECK
    # ------------------------------------------------------

    EXISTING_DEVICE_ID=$(api_get \
        "$NETBOX_URL/dcim/devices/?name=$(urlencode "$HOSTNAME")" |
        jq -r '.results[0].id // empty')

    if [ -z "$EXISTING_DEVICE_ID" ] ||
       [ "$EXISTING_DEVICE_ID" = "null" ]; then

        echo "Creating device..."

        RESPONSE=$(api_post \
            "$NETBOX_URL/dcim/devices/" \
            "{\"name\":\"$HOSTNAME\",\"device_type\":$DEVICETYPE_ID,\"role\":$DEVICEROLE_ID,\"site\":$SITE_ID,\"cluster\":$CLUSTER_ID,\"status\":\"$STATUS\"}")

        DEVICE_ID=$(echo "$RESPONSE" |
            jq -r '.id // empty')

        if [ -z "$DEVICE_ID" ] ||
           [ "$DEVICE_ID" = "null" ]; then

            echo -e "${RED}Failed creating device: $HOSTNAME${NC}"
            echo "$RESPONSE" | jq .
            FAILED_LIST+="$HOSTNAME"$'\n'
            return 1
        fi

    else

        DEVICE_ID="$EXISTING_DEVICE_ID"

        echo "Device already exists. Updating..."

        RESPONSE=$(api_patch \
            "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
            "{\"cluster\":$CLUSTER_ID,\"status\":\"$STATUS\"}")

        if ! echo "$RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
            echo -e "${YELLOW}Device update response:${NC}"
            echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
        fi

    fi

    echo "Device ID: $DEVICE_ID"

    # ======================================================
    # MANUAL MODE
    # Only Hostname + IP
    # ======================================================

    if [ "$MODE" = "manual" ]; then

        echo "Manual mode: creating/checking IP..."

        IP_ID=$(api_get \
            "$NETBOX_URL/ipam/ip-addresses/?address=$(urlencode "$IPADDR")" |
            jq -r '.results[0].id // empty')

        if [ -z "$IP_ID" ] ||
           [ "$IP_ID" = "null" ]; then

            RESPONSE=$(api_post \
                "$NETBOX_URL/ipam/ip-addresses/" \
                "{\"address\":\"$IPADDR\",\"status\":\"active\"}")

            IP_ID=$(echo "$RESPONSE" |
                jq -r '.id // empty')

            if [ -z "$IP_ID" ] ||
               [ "$IP_ID" = "null" ]; then

                echo -e "${RED}Failed creating IP: $IPADDR${NC}"
                echo "$RESPONSE" | jq .
                FAILED_LIST+="$HOSTNAME"$'\n'
                return 1
            fi

        fi

        echo "IP ID: $IP_ID"
        echo "Assigning Primary IP..."

        RESPONSE=$(api_patch \
            "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
            "{\"cluster\":$CLUSTER_ID,\"status\":\"$STATUS\",\"primary_ip4\":$IP_ID}")

        if ! echo "$RESPONSE" | jq -e '.id' >/dev/null 2>&1; then

            echo -e "${RED}Failed assigning Primary IP${NC}"
            echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
            FAILED_LIST+="$HOSTNAME"$'\n'
            return 1

        fi

    fi

    # ======================================================
    # AUTO MODE
    # ======================================================

    if [ "$MODE" = "auto" ]; then

        # --------------------------------------------------
        # INTERFACE
        # --------------------------------------------------

        ALL_INTS=$(api_get \
            "$NETBOX_URL/dcim/interfaces/?device_id=$DEVICE_ID")

        INTERFACE_ID=$(echo "$ALL_INTS" |
            jq -r --arg IFACE "$IFACE" \
            '.results[] | select(.name == $IFACE) | .id // empty')

        if [ -z "$INTERFACE_ID" ] ||
           [ "$INTERFACE_ID" = "null" ]; then

            echo "Creating interface: $IFACE"

            RESPONSE=$(api_post \
                "$NETBOX_URL/dcim/interfaces/" \
                "{\"device\":$DEVICE_ID,\"name\":\"$IFACE\",\"type\":\"1000base-t\"}")

            INTERFACE_ID=$(echo "$RESPONSE" |
                jq -r '.id // empty')

            if [ -z "$INTERFACE_ID" ] ||
               [ "$INTERFACE_ID" = "null" ]; then

                echo -e "${RED}Failed creating interface${NC}"
                echo "$RESPONSE" | jq .
                FAILED_LIST+="$HOSTNAME"$'\n'
                return 1
            fi

        fi

        echo "Interface ID: $INTERFACE_ID"

        # --------------------------------------------------
        # MAC ADDRESS
        # --------------------------------------------------

        if [ -n "$MAC" ]; then

            MAC_OBJ_ID=$(api_get \
                "$NETBOX_URL/dcim/mac-addresses/?mac_address=$(urlencode "$MAC")" |
                jq -r '.results[0].id // empty')

            if [ -z "$MAC_OBJ_ID" ] ||
               [ "$MAC_OBJ_ID" = "null" ]; then

                RESPONSE=$(api_post \
                    "$NETBOX_URL/dcim/mac-addresses/" \
                    "{\"mac_address\":\"$MAC\",\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID}")

                MAC_OBJ_ID=$(echo "$RESPONSE" |
                    jq -r '.id // empty')

                if [ -z "$MAC_OBJ_ID" ] ||
                   [ "$MAC_OBJ_ID" = "null" ]; then

                    echo -e "${YELLOW}MAC object creation failed${NC}"
                    echo "$RESPONSE" | jq . 2>/dev/null || true

                fi

            else

                api_patch \
                    "$NETBOX_URL/dcim/mac-addresses/$MAC_OBJ_ID/" \
                    "{\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID}" \
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

            RESPONSE=$(api_post \
                "$NETBOX_URL/ipam/ip-addresses/" \
                "{\"address\":\"$IPADDR\",\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID,\"status\":\"active\"}")

            IP_ID=$(echo "$RESPONSE" |
                jq -r '.id // empty')

            if [ -z "$IP_ID" ] ||
               [ "$IP_ID" = "null" ]; then

                echo -e "${RED}Failed creating IP${NC}"
                echo "$RESPONSE" | jq .
                FAILED_LIST+="$HOSTNAME"$'\n'
                return 1
            fi

        else

            api_patch \
                "$NETBOX_URL/ipam/ip-addresses/$IP_ID/" \
                "{\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID}" \
                > /dev/null

        fi

        echo "IP ID: $IP_ID"

        # --------------------------------------------------
        # PRIMARY IP
        # --------------------------------------------------

        api_patch \
            "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
            "{\"cluster\":$CLUSTER_ID,\"status\":\"$STATUS\",\"primary_ip4\":$IP_ID}" \
            > /dev/null

        # --------------------------------------------------
        # CUSTOM FIELDS
        # --------------------------------------------------

        echo "Updating custom fields..."

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

    # ======================================================
    # TAGS
    # ======================================================

    assign_tags "$DEVICE_ID" "$CLUSTER_NAME"

    echo "------------------------------------------------------------"
    echo -e "${GREEN}✓ Finished: $HOSTNAME${NC}"
    echo "Cluster: $CLUSTER_NAME"
    echo "------------------------------------------------------------"

    SUCCESS_LIST+="$HOSTNAME"$'\n'

    return 0
}

# ==========================================================
# AUTOMATIC SSH DISCOVERY
# ==========================================================

discover_and_sync() {

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

    echo ""
    echo "============================================================"
    echo -e "${CYAN}AUTOMATIC DISCOVERY: $REMOTE_HOST${NC}"
    echo "============================================================"

    # ------------------------------------------------------
    # PING
    # ------------------------------------------------------

    if ! ping -c1 -W2 "$REMOTE_HOST" >/dev/null 2>&1; then

        echo -e "${RED}Host unreachable: $REMOTE_HOST${NC}"
        FAILED_LIST+="$REMOTE_HOST"$'\n'
        return 1

    fi

    echo -e "${GREEN}Host reachable${NC}"

    # ------------------------------------------------------
    # SSH
    # ------------------------------------------------------

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

    echo -e "${GREEN}SSH connected successfully${NC}"

    # ------------------------------------------------------
    # HOSTNAME
    # ------------------------------------------------------

    HOSTNAME=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "hostname -f" 2>/dev/null |
        tr -d '\r' |
        xargs)

    # ------------------------------------------------------
    # INTERFACE + IP
    # ------------------------------------------------------

    IFACE_DATA=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "ip -o -4 addr show scope global | head -1" 2>/dev/null)

    IFACE=$(echo "$IFACE_DATA" | awk '{print $2}')
    IPADDR=$(echo "$IFACE_DATA" | awk '{print $4}')

    # ------------------------------------------------------
    # MAC
    # ------------------------------------------------------

    MAC=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "cat /sys/class/net/$IFACE/address" 2>/dev/null |
        tr '[:lower:]' '[:upper:]' |
        tr -d '\r' |
        xargs)

    # ------------------------------------------------------
    # CPU
    # ------------------------------------------------------

    CPU_COUNT=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "nproc" 2>/dev/null |
        xargs)

    # ------------------------------------------------------
    # RAM
    # ------------------------------------------------------

    RAM_GB=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "awk '/MemTotal/ {printf \"%d\", (\$2/1024/1024)+0.5}' /proc/meminfo" \
        2>/dev/null |
        xargs)

    # ------------------------------------------------------
    # DISK
    # ------------------------------------------------------

    DISK_GB=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "lsblk -bdno SIZE | awk '{s+=\$1} END {printf \"%.0f GB\",s/1024/1024/1024}'" \
        2>/dev/null |
        xargs)

    # ------------------------------------------------------
    # VM TYPE
    # ------------------------------------------------------

    VM_TYPE=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "systemd-detect-virt" 2>/dev/null |
        tr -d '\r' |
        xargs)

    [ -z "$VM_TYPE" ] && VM_TYPE="Physical"

    # ------------------------------------------------------
    # KERNEL
    # ------------------------------------------------------

    KERNEL=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "uname -r" 2>/dev/null |
        tr -d '\r' |
        xargs)

    # ------------------------------------------------------
    # UPTIME
    # ------------------------------------------------------

    UPTIME=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        "$SSH_USER@$REMOTE_HOST" \
        "uptime -p" 2>/dev/null |
        tr -d '\r' |
        xargs)

    # ------------------------------------------------------
    # ENSURE CIDR
    # ------------------------------------------------------

    if [[ "$IPADDR" != */* ]]; then
        IPADDR="$IPADDR/24"
    fi

    # ------------------------------------------------------
    # SYNC
    # ------------------------------------------------------

    sync_device \
        "$HOSTNAME" \
        "$IPADDR" \
        "$CLUSTER_ID" \
        "$CLUSTER_NAME" \
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
# START
# ==========================================================

banner

# ==========================================================
# DEPENDENCY CHECK
# ==========================================================

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
# STEP 1
# CENTOS 7 MANUAL DEVICES
# ==========================================================

echo ""
echo "============================================================"
echo -e "${CYAN}STEP 1 - CENTOS 7 DEVICES${NC}"
echo "============================================================"

CENTOS_CLUSTER_ID=$(get_cluster_id \
    "Physical" \
    "centos-07-servers" \
    "centos-07-servers")

if [ -z "$CENTOS_CLUSTER_ID" ] ||
   [ "$CENTOS_CLUSTER_ID" = "null" ]; then

    echo -e "${RED}Failed to get/create CentOS cluster${NC}"
    exit 1

fi

echo "Cluster ID: $CENTOS_CLUSTER_ID"

# cent-07-01
sync_device \
    "cent-07-01.vgs.com" \
    "192.168.253.131/24" \
    "$CENTOS_CLUSTER_ID" \
    "centos-07-servers" \
    "staged" \
    "manual" \
    "" \
    "" \
    "null" \
    "null" \
    "" \
    "" \
    "" \
    ""

# cent-07-02
sync_device \
    "cent-07-02.vgs.com" \
    "192.168.253.132/24" \
    "$CENTOS_CLUSTER_ID" \
    "centos-07-servers" \
    "staged" \
    "manual" \
    "" \
    "" \
    "null" \
    "null" \
    "" \
    "" \
    "" \
    ""

# ==========================================================
# STEP 2
# ROCKY 8 AUTOMATIC DEVICES
# ==========================================================

echo ""
echo "============================================================"
echo -e "${CYAN}STEP 2 - ROCKY 8 AUTOMATIC DISCOVERY${NC}"
echo "============================================================"

ROCKY8_CLUSTER_ID=$(get_cluster_id \
    "Physical" \
    "rocky-8-servers" \
    "rocky-8-servers")

if [ -z "$ROCKY8_CLUSTER_ID" ] ||
   [ "$ROCKY8_CLUSTER_ID" = "null" ]; then

    echo -e "${RED}Failed to get/create Rocky 8 cluster${NC}"
    exit 1

fi

echo "Cluster ID: $ROCKY8_CLUSTER_ID"

# netbox.vgs.com
discover_and_sync \
    "netbox.vgs.com" \
    "$ROCKY8_CLUSTER_ID" \
    "rocky-8-servers"

# ansible-server-01.vgs.com
discover_and_sync \
    "ansible-server-01.vgs.com" \
    "$ROCKY8_CLUSTER_ID" \
    "rocky-8-servers"

# ==========================================================
# STEP 3
# ROCKY 9 MANUAL DEVICE
# ==========================================================

echo ""
echo "============================================================"
echo -e "${CYAN}STEP 3 - ROCKY 9 DEVICE${NC}"
echo "============================================================"

ROCKY9_CLUSTER_ID=$(get_cluster_id \
    "Physical" \
    "rocky-9-servers" \
    "rocky-9-servers")

if [ -z "$ROCKY9_CLUSTER_ID" ] ||
   [ "$ROCKY9_CLUSTER_ID" = "null" ]; then

    echo -e "${RED}Failed to get/create Rocky 9 cluster${NC}"
    exit 1

fi

echo "Cluster ID: $ROCKY9_CLUSTER_ID"

# rocky-09-01
sync_device \
    "rocky-09-01.vgs.com" \
    "192.168.253.151/24" \
    "$ROCKY9_CLUSTER_ID" \
    "rocky-9-servers" \
    "staged" \
    "manual" \
    "" \
    "" \
    "null" \
    "null" \
    "" \
    "" \
    "" \
    ""

# ==========================================================
# SUMMARY
# ==========================================================

END_TIME=$(date +%s)
RUNTIME=$((END_TIME - START_TIME))

SUCCESS_COUNT=$(echo "$SUCCESS_LIST" | sed '/^$/d' | wc -l)
FAILED_COUNT=$(echo "$FAILED_LIST" | sed '/^$/d' | wc -l)

echo ""
echo "============================================================"
echo -e "${CYAN}                   EXECUTION SUMMARY${NC}"
echo "============================================================"

echo ""
echo -e "${GREEN}SUCCESSFUL HOSTS${NC}"

if [ "$SUCCESS_COUNT" -eq 0 ]; then
    echo "None"
else
    echo "$SUCCESS_LIST"
fi

echo ""
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
