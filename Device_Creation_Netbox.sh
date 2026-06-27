#!/bin/bash
set -e

# ---------------- CONFIG ----------------
NETBOX_URL="https://192.168.253.143/api"
NETBOX_TOKEN="83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd"
HDR="Content-Type: application/json"

SSH_USER="root"
SSH_PASS="Root@123"

SITE_ID=1
DEVICETYPE_ID=1
DEVICEROLE_ID=1

# ==================================================
# UI / COLORS
# ==================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

LOGFILE="/var/log/netbox-sync.log"

START_TIME=$(date +%s)

log() {
    echo -e "$1"
    echo "$(date '+%F %T') $(echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g')" >> "$LOGFILE"
}

banner() {
clear

echo -e "${CYAN}"
echo "==========================================================="
echo "             NETBOX INVENTORY SYNC TOOL"
echo "==========================================================="
echo -e "${NC}"
}

banner

SUCCESS_LIST=""
FAILED_LIST=""

# --------------------------------------------------
# Dependency Checks
# --------------------------------------------------

for cmd in curl jq ping ssh sshpass
do
    if ! command -v "$cmd" >/dev/null 2>&1
    then
        echo ""
        echo "Missing dependency: $cmd"
        echo ""

        case $cmd in
            sshpass)
                echo "Install using:"
                echo "yum install -y sshpass"
                ;;
            jq)
                echo "Install using:"
                echo "yum install -y jq"
                ;;
            *)
                echo "Install the package providing $cmd"
                ;;
        esac

        exit 1
    fi
done

# --------------------------------------------------
# Log File Check
# --------------------------------------------------

touch "$LOGFILE" 2>/dev/null || {
    echo "Cannot write to $LOGFILE"
    exit 1
}

# --------------------------------------------------
# NetBox Connectivity Check
# --------------------------------------------------

echo ""
echo "Checking NetBox API connectivity..."

HTTP_CODE=$(curl -sk \
    -o /dev/null \
    -w "%{http_code}" \
    -H "Authorization: Token $NETBOX_TOKEN" \
    "$NETBOX_URL/status/")

if [ "$HTTP_CODE" != "200" ]; then
    echo ""
    echo "ERROR: NetBox API check failed"
    echo "HTTP Code : $HTTP_CODE"
    echo "URL       : $NETBOX_URL"
    echo ""
    exit 1
fi

echo "NetBox API reachable."
echo ""

# ---------------- HELPERS ----------------

slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g'
}

urlencode() {
    jq -rn --arg v "$1" '$v|@uri'
}

get_or_create() {
    local endpoint=$1
    local name=$2
    local extra_json=$3
    local slug=$(slugify "$name")

    # Check if exists
    local existing_id=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/$endpoint/?name=$(urlencode "$name")" \
        | jq -r '.results[0].id // empty')

    if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then
        echo "$existing_id"
    else
        # Create new
        local response=$(curl -sk -X POST "$NETBOX_URL/$endpoint/" \
            -H "$HDR" \
            -H "Authorization: Token $NETBOX_TOKEN" \
            -d "{\"name\":\"$name\",\"slug\":\"$slug\"$extra_json}")

        echo "$response" | jq -r '.id // empty'
    fi
}

# --------------------------------------------------
# Get Config Context ID
# --------------------------------------------------

get_context_id() {

    local NAME="$1"

    curl -sk \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/extras/config-contexts/?name=$(urlencode "$NAME")" \
        | jq -r '.results[0].id // empty'
}

get_tag_id() {

    local NAME="$1"

    curl -sk \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/extras/tags/" \
    | jq -r --arg NAME "$NAME" '.results[] | select(.name==$NAME) | .id'
}

# ---------------- DATA SOURCE ----------------
echo "How would you like to get server details?"
echo "1) Fetch automatically via SSH"
echo "2) Type manually"

read -p "Choice [1-2]: " SOURCE_CHOICE

# ---------------- DEVICE STATUS ----------------

if [ "$SOURCE_CHOICE" = "1" ]; then
    DEVICE_STATUS="active"
else
    DEVICE_STATUS="staged"
fi

if [ "$SOURCE_CHOICE" == "1" ]; then

    # ==========================================
    # AUTOMATIC DISCOVERY VIA SSH
    # ==========================================

    read -p "Enter Target Server IPs/Hostnames (comma separated): " REMOTE_HOSTS

    IFS=',' read -ra HOST_LIST <<< "$REMOTE_HOSTS"

    HOST_LIST=($(printf "%s\n" "${HOST_LIST[@]}" | awk '!seen[$0]++'))

    TOTAL=${#HOST_LIST[@]}
    COUNT=1

elif [ "$SOURCE_CHOICE" == "2" ]; then

    # ==========================================
    # MANUAL ENTRY
    # ==========================================

    read -p "Hostname(s)       : " HOSTNAMES
    read -p "IP Address(es)    : " IPADDRS
    read -p "MAC Address(es)   : " MACS
    read -p "Interface Name(s) : " IFACES
    
    IFS=',' read -ra HOSTNAME_LIST <<< "$HOSTNAMES"
    IFS=',' read -ra IPADDR_LIST <<< "$IPADDRS"
    IFS=',' read -ra MAC_LIST <<< "${MACS:-}"
    IFS=',' read -ra IFACE_LIST <<< "${IFACES:-}"
    
    TOTAL=${#HOSTNAME_LIST[@]}
    COUNT=1
	
if [ ${#IPADDR_LIST[@]} -ne $TOTAL ]; then
    echo "ERROR: Hostname count and IP count do not match"
    exit 1
fi

# Fill missing interfaces with ens192
if [ ${#IFACE_LIST[@]} -eq 0 ]; then
    for ((i=0;i<TOTAL;i++))
    do
        IFACE_LIST[$i]="ens192"
    done
fi

# Fill missing MAC entries
if [ ${#MAC_LIST[@]} -eq 0 ]; then
    for ((i=0;i<TOTAL;i++))
    do
        MAC_LIST[$i]=""
    done
fi
    
    CPU_COUNT="N/A"
    RAM_GB="N/A"
    DISK_SIZE="N/A"
    VMTYPE="Manual"
    KERNEL="N/A"
    UPTIME="N/A"

else

    echo "Invalid option"
    exit 1

fi

# ---------------- CLUSTER SELECTION ----------------

echo -e "\nCluster Configuration:"
echo "1) Pick from existing Netbox clusters"
echo "2) Add to a specific/new cluster setup (Manual entry)"

read -p "Choice [1-2]: " CLUSTER_MODE

if [ "$CLUSTER_MODE" == "2" ]; then

    read -p "Enter Cluster Type name: (eg: Physical)" TYPE_NAME
    TYPE_ID=$(get_or_create "virtualization/cluster-types" "$TYPE_NAME")

    read -p "Enter Cluster Group name: (eg: rocky-8-servers / centos-07-servers)" GROUP_NAME
    GROUP_ID=$(get_or_create "virtualization/cluster-groups" "$GROUP_NAME")

    read -p "Enter Cluster name: (eg: rocky-8-servers / centos-07-servers)" CLUSTER_NAME

    CLUSTER_ID=$(get_or_create \
        "virtualization/clusters" \
        "$CLUSTER_NAME" \
        ",\"type\":$TYPE_ID,\"group\":$GROUP_ID,\"site\":$SITE_ID")

else

    results=$(curl -sk \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/virtualization/clusters/" \
        | jq -r '.results[] | "\(.id)|\(.name)"')

    count=1
    declare -A cluster_map

    while IFS='|' read -r id name
    do
        echo "$count) $name"
        cluster_map[$count]=$id
        ((count++))
    done <<< "$results"

    read -p "Choose cluster: " c_choice

    CLUSTER_ID=${cluster_map[$c_choice]}
        if [ -z "$CLUSTER_ID" ] || [ "$CLUSTER_ID" = "null" ]; then
    echo -e "${RED}Invalid Cluster Selection${NC}"
    exit 1
    fi
fi

echo
read -p "Do you want to assign Tags? (yes/no): " ADD_TAGS
ADD_TAGS=$(echo "$ADD_TAGS" | tr '[:upper:]' '[:lower:]')

# --------------------------------------------------
# Manual Mode
# --------------------------------------------------

if [ "$SOURCE_CHOICE" = "2" ]; then

    echo ""
    echo "Processing Manual Devices..."

    HOST_LIST=("${HOSTNAME_LIST[@]}")

fi

# ---------------- HOST LOOP ----------------

for REMOTE_HOST in "${HOST_LIST[@]}"
do

if [ "$SOURCE_CHOICE" = "2" ]; then

    IDX=$((COUNT-1))
	
	if [ "$IDX" -ge "${#HOSTNAME_LIST[@]}" ]; then
    break
	fi

    HOSTNAME=$(echo "${HOSTNAME_LIST[$IDX]}" | xargs)
    IPADDR=$(echo "${IPADDR_LIST[$IDX]}" | xargs)
    MAC=$(echo "${MAC_LIST[$IDX]:-}" | xargs)
    IFACE=$(echo "${IFACE_LIST[$IDX]:-ens192}" | xargs)

fi

if [ "$SOURCE_CHOICE" = "2" ]; then

    if [ -z "$HOSTNAME" ] || [ -z "$IPADDR" ]; then
        log "${RED}Missing hostname or IP for entry $COUNT${NC}"
        FAILED_LIST+="Manual-Entry-$COUNT"$'\n'
        ((COUNT++))
        continue
    fi

    [ -z "$IFACE" ] && IFACE="ens192"

fi

    REMOTE_HOST=$(echo "$REMOTE_HOST" | xargs)

    log ""
    PERCENT=$(( COUNT * 100 / TOTAL ))
        if [ "$SOURCE_CHOICE" = "2" ]; then
    log "${BLUE}[${COUNT}/${TOTAL}] (${PERCENT}%) Processing ${HOSTNAME}${NC}"
    else
        log "${BLUE}[${COUNT}/${TOTAL}] (${PERCENT}%) Processing ${REMOTE_HOST}${NC}"
    fi

if [ "$SOURCE_CHOICE" = "1" ]; then

    # --------------------------------------------------
    # Ping Check
    # --------------------------------------------------

    if ! ping -c1 -W2 "$REMOTE_HOST" >/dev/null 2>&1
    then
        log "${RED}✗ Host unreachable${NC}"
        FAILED_LIST+="$REMOTE_HOST"$'\n'
        ((COUNT++))
        continue
    fi

    # --------------------------------------------------
    # SSH Check
    # --------------------------------------------------

    if ! sshpass -p "$SSH_PASS" \
        ssh -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        ${SSH_USER}@${REMOTE_HOST} "echo ok" >/dev/null 2>&1
    then
        log "${RED}✗ SSH connection failed${NC}"
        FAILED_LIST+="$REMOTE_HOST"$'\n'
        ((COUNT++))
        continue
    fi

    log "${GREEN}✓ Host reachable${NC}"

    HOSTNAME=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        ${SSH_USER}@${REMOTE_HOST} hostname | xargs)

    HOSTNAME=$(echo "$HOSTNAME" | tr -d '\r')

    if [ -z "$HOSTNAME" ]; then
        log "${RED}Unable to determine hostname${NC}"
        FAILED_LIST+="$REMOTE_HOST"$'\n'
        ((COUNT++))
        continue
    fi

    UPTIME=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        ${SSH_USER}@${REMOTE_HOST} "uptime -p" 2>/dev/null)

    KERNEL=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        ${SSH_USER}@${REMOTE_HOST} "uname -r" 2>/dev/null)

    IFACE_DATA=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        ${SSH_USER}@${REMOTE_HOST} \
        "ip -o -4 addr show scope global | head -1")

    IFACE=$(echo "$IFACE_DATA" | awk '{print $2}')
    IPADDR=$(echo "$IFACE_DATA" | awk '{print $4}')

    MAC=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        ${SSH_USER}@${REMOTE_HOST} \
        "cat /sys/class/net/$IFACE/address" \
        | tr '[:lower:]' '[:upper:]')

    CPU_COUNT=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        ${SSH_USER}@${REMOTE_HOST} "nproc")

        RAM_GB=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        ${SSH_USER}@${REMOTE_HOST} \
    "   awk '/MemTotal/ {printf \"%d\", (\$2/1024/1024)+0.5}' /proc/meminfo")

    DISK_SIZE=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        ${SSH_USER}@${REMOTE_HOST} \
        "lsblk -bdno SIZE | awk '{s+=\$1} END {printf \"%.0f GB\",s/1024/1024/1024}'")

    VMTYPE=$(sshpass -p "$SSH_PASS" ssh \
        -o StrictHostKeyChecking=no \
        ${SSH_USER}@${REMOTE_HOST} \
        "systemd-detect-virt" 2>/dev/null)

    [ -z "$VMTYPE" ] && VMTYPE="Physical"

fi

log "${WHITE}Hostname : ${HOSTNAME}${NC}"
log "${WHITE}IP       : ${IPADDR}${NC}"
log "${WHITE}MAC      : ${MAC}${NC}"
log "${WHITE}CPU      : ${CPU_COUNT}${NC}"
log "${WHITE}RAM      : ${RAM_GB} GB${NC}"
log "${WHITE}Disk     : ${DISK_SIZE}${NC}"
log "${WHITE}Type     : ${VMTYPE}${NC}"
log "${WHITE}Kernel   : ${KERNEL}${NC}"
log "${WHITE}Uptime   : ${UPTIME}${NC}"

# ---------------- PRE-CHECK EXISTING DEVICE ----------------
DEV_PRECHECK=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" \
    "$NETBOX_URL/dcim/devices/?name=$(urlencode "$HOSTNAME")")

EXISTING_DEV_ID=$(echo "$DEV_PRECHECK" | jq -r '.results[0].id // empty')

# ---------------- FINAL SYNC ----------------
echo -e "\nSyncing to Netbox..."

# 1. Device
if [ -z "$EXISTING_DEV_ID" ] || [ "$EXISTING_DEV_ID" == "null" ]; then

    DEVICE_ID=$(curl -sk -X POST "$NETBOX_URL/dcim/devices/" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "{\"name\":\"$HOSTNAME\",\"device_type\":$DEVICETYPE_ID,\"role\":$DEVICEROLE_ID,\"site\":$SITE_ID,\"cluster\":$CLUSTER_ID,\"status\":\"$DEVICE_STATUS\"}" \
        | jq -r '.id // empty')

    if [ -z "$DEVICE_ID" ]; then
        log "${RED}Failed creating device ${HOSTNAME}${NC}"
        FAILED_LIST+="$HOSTNAME"$'\n'
        ((COUNT++))
        continue
    fi

else

    DEVICE_ID=$EXISTING_DEV_ID

curl -sk -X PATCH "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
    -H "$HDR" \
    -H "Authorization: Token $NETBOX_TOKEN" \
    -d "{\"cluster\":$CLUSTER_ID,\"status\":\"$DEVICE_STATUS\"}" > /dev/null
fi

# 2. Interface Sync & Cleanup
# ------------------------------------------------

# Get all existing interfaces for this device
ALL_INTS_JSON=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" \
    "$NETBOX_URL/dcim/interfaces/?device_id=$DEVICE_ID")

# ------------------------------------------------
# Remove stale interfaces during automatic discovery
# ------------------------------------------------

if [ "$SOURCE_CHOICE" = "1" ]; then

    echo "$ALL_INTS_JSON" | jq -r '.results[] | "\(.id)|\(.name)"' |
    while IFS='|' read -r OLD_ID OLD_NAME
    do
        if [ "$OLD_NAME" != "$IFACE" ]; then

            echo "Removing stale interface: $OLD_NAME"

            curl -sk -X DELETE \
                "$NETBOX_URL/dcim/interfaces/$OLD_ID/" \
                -H "Authorization: Token $NETBOX_TOKEN" \
                >/dev/null
        fi
    done

    # Refresh interface list after cleanup
    ALL_INTS_JSON=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/dcim/interfaces/?device_id=$DEVICE_ID")

fi

# Check if our current interface ($IFACE) already exists
INTERFACE_ID=$(echo "$ALL_INTS_JSON" \
    | jq -r ".results[] | select(.name == \"$IFACE\") | .id // empty")

if [ -z "$INTERFACE_ID" ] || [ "$INTERFACE_ID" == "null" ]; then

    echo "Creating interface: $IFACE"

    INTERFACE_ID=$(curl -sk -X POST "$NETBOX_URL/dcim/interfaces/" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "{\"device\":$DEVICE_ID,\"name\":\"$IFACE\",\"type\":\"1000base-t\"}" \
        | jq -r '.id')

        if [ -z "$INTERFACE_ID" ] || [ "$INTERFACE_ID" = "null" ]; then
    log "${RED}Failed creating interface ${IFACE} on ${HOSTNAME}${NC}"
    FAILED_LIST+="$HOSTNAME"$'\n'
    ((COUNT++))
    continue
    fi
fi

# 3. MAC Object
if [ -n "$MAC" ]; then

    MAC_OBJ_CHECK=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/dcim/mac-addresses/?mac_address=$MAC")

    MAC_OBJ_ID=$(echo "$MAC_OBJ_CHECK" | jq -r '.results[0].id // empty')

    if [ -z "$MAC_OBJ_ID" ] || [ "$MAC_OBJ_ID" == "null" ]; then

        MAC_OBJ_ID=$(curl -sk -X POST "$NETBOX_URL/dcim/mac-addresses/" \
            -H "$HDR" \
            -H "Authorization: Token $NETBOX_TOKEN" \
            -d "{\"mac_address\":\"$MAC\",\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID}" \
            | jq -r '.id')

    else

        curl -sk -X PATCH "$NETBOX_URL/dcim/mac-addresses/$MAC_OBJ_ID/" \
            -H "$HDR" \
            -H "Authorization: Token $NETBOX_TOKEN" \
            -d "{\"assigned_object_id\":$INTERFACE_ID}" > /dev/null
    fi

    curl -sk -X PATCH "$NETBOX_URL/dcim/interfaces/$INTERFACE_ID/" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "{\"primary_mac_address\": $MAC_OBJ_ID}" > /dev/null
fi

# 4. IP Sync
IP_ID=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" \
    "$NETBOX_URL/ipam/ip-addresses/?address=$(urlencode "$IPADDR")" \
    | jq -r '.results[0].id // empty')

if [ -z "$IP_ID" ] || [ "$IP_ID" == "null" ]; then

    IP_ID=$(curl -sk -X POST "$NETBOX_URL/ipam/ip-addresses/" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "{\"address\":\"$IPADDR\",\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID,\"status\":\"active\"}" \
        | jq -r '.id')

else

    curl -sk -X PATCH "$NETBOX_URL/ipam/ip-addresses/$IP_ID/" \
        -H "$HDR" \
        -H "Authorization: Token $NETBOX_TOKEN" \
        -d "{\"assigned_object_id\":$INTERFACE_ID}" > /dev/null
fi

echo "Assigning Primary IP..."
echo "IP_ID=$IP_ID"

curl -sk -X PATCH "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
    -H "$HDR" \
    -H "Authorization: Token $NETBOX_TOKEN" \
    -d "{\"cluster\":$CLUSTER_ID,\"status\":\"$DEVICE_STATUS\",\"primary_ip4\":$IP_ID}" > /dev/null

if [ "$CPU_COUNT" = "N/A" ]; then
    CPU_COUNT=null
fi

if [ "$RAM_GB" = "N/A" ]; then
    RAM_GB=null
fi

# 5. Custom Fields Sync

echo "DEVICE_ID=$DEVICE_ID"
echo "CPU_COUNT=$CPU_COUNT"
echo "RAM_GB=$RAM_GB"
echo "DISK_SIZE=$DISK_SIZE"
echo "VMTYPE=$VMTYPE"
echo "KERNEL=$KERNEL"

curl -sk -X PATCH \
"$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
-H "$HDR" \
-H "Authorization: Token $NETBOX_TOKEN" \
-d "{
  \"custom_fields\": {
    \"cpu_count\": $CPU_COUNT,
    \"ram_gb\": $RAM_GB,
    \"disk_gb\": \"$DISK_SIZE\",
    \"vm_type\": \"$VMTYPE\",
    \"kernel\": \"$KERNEL\"
  }
}" | jq .

# --------------------------------------------------
# Assign Tags
# --------------------------------------------------

if [[ "$ADD_TAGS" == "yes" || "$ADD_TAGS" == "y" ]]; then

    CLUSTER_NAME=$(curl -sk \
        -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/virtualization/clusters/$CLUSTER_ID/" \
        | jq -r '.name')

    TAG_IDS=()

    if [[ "$CLUSTER_NAME" == "centos-07-servers" ]]; then

        TAGS=(
            "centostorocky-context"
            "patch-context"
            "pxe-centos-context"
            "repo-config-context"
            "vmware-awx-context"
			"centos-patch-context"
        )

    elif [[ "$CLUSTER_NAME" == "rocky-8-servers" ]]; then

        TAGS=(
            "patch-el8-context"
            "pxe-rockyos-context"
            "repo-config-context"
            "vmware-awx-context"
			"rocky-patch-context"
        )

    else

        TAGS=()

    fi

    for TAG in "${TAGS[@]}"
    do
        ID=$(get_tag_id "$TAG")

        if [ -n "$ID" ]; then
            TAG_IDS+=("$ID")
            echo "Adding Tag: $TAG"
        fi
    done

    if [ ${#TAG_IDS[@]} -gt 0 ]; then

        JSON_TAGS=$(printf '%s\n' "${TAG_IDS[@]}" | jq -R . | jq -s .)

        curl -sk -X PATCH \
            "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
            -H "$HDR" \
            -H "Authorization: Token $NETBOX_TOKEN" \
            -d "{\"tags\":$JSON_TAGS}" \
            >/dev/null

        echo "Tags assigned successfully."

    fi

fi

echo "------------------------------------------------"
echo "✅ Finished! $HOSTNAME is updated."
echo "Linked to Cluster ID: $CLUSTER_ID"
echo "------------------------------------------------"

SUCCESS_LIST+="$HOSTNAME"$'\n'

((COUNT++))

done

END_TIME=$(date +%s)
RUNTIME=$((END_TIME-START_TIME))

echo ""
echo "===================================================="

echo -e "${GREEN}SUCCESSFUL HOSTS${NC}"
echo "$SUCCESS_LIST"

echo ""
echo -e "${RED}FAILED HOSTS${NC}"

FAILED_COUNT=$(echo "$FAILED_LIST" | sed '/^$/d' | wc -l)

if [ "$FAILED_COUNT" -eq 0 ]; then
    echo "0"
else
    echo "$FAILED_LIST"
fi

SUCCESS_COUNT=$(echo "$SUCCESS_LIST" | sed '/^$/d' | wc -l)

echo ""
echo "Success Count : $SUCCESS_COUNT"
echo "Failed Count  : $FAILED_COUNT"

echo -e "${CYAN}Execution Time : ${RUNTIME} seconds${NC}"

echo "===================================================="
