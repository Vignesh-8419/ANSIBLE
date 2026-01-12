#!/bin/bash
set -e

# ---------------- CONFIG ----------------
NETBOX_URL="https://192.168.253.134/api"
NETBOX_TOKEN="FZRvENMkPG8xXTKdP9ewxmGtSgLuN8xaAMHkvcgr"
HDR="Content-Type: application/json"

SSH_USER="root"
SSH_PASS="Root@123"

SITE_ID=1
DEVICETYPE_ID=1
DEVICEROLE_ID=1

# ---------------- HELPERS ----------------
slugify() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g'; }
urlencode() { jq -rn --arg v "$1" '$v|@uri'; }

select_from_netbox() {
    local endpoint=$1
    local display_name=$2
    local force_manual=$3

    if [ "$force_manual" == "true" ]; then
        read -p "Enter $display_name name: " new_name
        SELECTED_NAME="$new_name"
        SELECTED_ID=""
        return
    fi

    echo -e "\n--- Select $display_name ---"
    results=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/$endpoint" | jq -r '.results[] | "\(.id)|\(.name)"')
    local count=1
    declare -A map
    declare -A name_map
    if [ -n "$results" ]; then
        while IFS='|' read -r id name; do
            echo "$count) $name"
            map[$count]=$id
            name_map[$count]=$name
            ((count++))
        done <<< "$results"
    fi
    echo "$count) Type New $display_name Manually"
    read -p "Choose option [1-$count]: " choice
    if [[ "$choice" -eq "$count" ]]; then
        read -p "Enter new $display_name name: " new_name
        SELECTED_NAME="$new_name"
        SELECTED_ID=""
    else
        SELECTED_ID="${map[$choice]}"
        SELECTED_NAME="${name_map[$choice]}"
    fi
}

# ---------------- DATA SOURCE ----------------
echo "How would you like to get server details?"
echo "1) Fetch automatically via SSH"
echo "2) Type manually"
read -p "Choice [1-2]: " SOURCE_CHOICE

if [ "$SOURCE_CHOICE" == "1" ]; then
    read -p "Enter Target Server IP/Hostname: " REMOTE_HOST
    echo "Fetching data from $REMOTE_HOST..."
    
    HOSTNAME=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no ${SSH_USER}@${REMOTE_HOST} "hostname" | xargs)
    IFACE_DATA=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no ${SSH_USER}@${REMOTE_HOST} "ip -o -4 addr show scope global | head -1")
    IFACE=$(echo $IFACE_DATA | awk '{print $2}' | xargs)
    IPADDR=$(echo $IFACE_DATA | awk '{print $4}' | xargs)
    MAC=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no ${SSH_USER}@${REMOTE_HOST} "cat /sys/class/net/$IFACE/address" | xargs | tr '[:lower:]' '[:upper:]')
    
    echo ">>> Fetched: $HOSTNAME | $IPADDR | $MAC | Interface: $IFACE"
else
    read -p "Hostname: " HOSTNAME
    read -p "Interface name: " IFACE
    read -p "IP Address (CIDR): " IPADDR
    read -p "MAC Address (optional): " MAC
    MAC=$(echo "$MAC" | xargs | tr '[:lower:]' '[:upper:]')
fi

# ---------------- PRE-CHECK EXISTING DEVICE ----------------
DEV_PRECHECK=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/dcim/devices/?name=$(urlencode "$HOSTNAME")")
EXISTING_DEV_ID=$(echo "$DEV_PRECHECK" | jq -r '.results[0].id // empty')

CURRENT_CLUSTER_INFO="None"
if [ -n "$EXISTING_DEV_ID" ]; then
    C_NAME=$(echo "$DEV_PRECHECK" | jq -r '.results[0].cluster.name // "N/A"')
    C_TYPE=$(echo "$DEV_PRECHECK" | jq -r '.results[0].cluster.type.name // "N/A"')
    CURRENT_CLUSTER_INFO="Name: $C_NAME | Type: $C_TYPE"
fi

# ---------------- CLUSTER MODE SELECTION ----------------
echo -e "\nCluster Configuration:"
if [ "$CURRENT_CLUSTER_INFO" != "None" ]; then
    echo "1) Keep existing configuration ($CURRENT_CLUSTER_INFO)"
else
    echo "1) Pick from existing Netbox clusters/groups"
fi
echo "2) Add to a specific/new cluster setup (Manual entry)"
read -p "Choice [1-2]: " CLUSTER_MODE

FORCE_MANUAL="false"
USE_EXISTING="false"

if [ "$CLUSTER_MODE" == "1" ] && [ -n "$EXISTING_DEV_ID" ]; then
    CLUSTER_ID=$(echo "$DEV_PRECHECK" | jq -r '.results[0].cluster.id // empty')
    [ "$CLUSTER_ID" != "null" ] && [ -n "$CLUSTER_ID" ] && USE_EXISTING="true"
fi
[ "$CLUSTER_MODE" == "2" ] && FORCE_MANUAL="true"

# ---------------- CLUSTER SELECTION ----------------
if [ "$USE_EXISTING" == "false" ]; then
    select_from_netbox "virtualization/cluster-types/" "Cluster Type" "$FORCE_MANUAL"
    TYPE_ID=$SELECTED_ID
    [ -z "$TYPE_ID" ] && TYPE_ID=$(curl -sk -X POST "$NETBOX_URL/virtualization/cluster-types/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"name\":\"$SELECTED_NAME\",\"slug\":\"$(slugify "$SELECTED_NAME")\"}" | jq -r '.id')

    select_from_netbox "virtualization/cluster-groups/" "Cluster Group" "$FORCE_MANUAL"
    GROUP_ID=$SELECTED_ID
    [ -z "$GROUP_ID" ] && GROUP_ID=$(curl -sk -X POST "$NETBOX_URL/virtualization/cluster-groups/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"name\":\"$SELECTED_NAME\",\"slug\":\"$(slugify "$SELECTED_NAME")\"}" | jq -r '.id')

    select_from_netbox "virtualization/clusters/" "Cluster" "$FORCE_MANUAL"
    CLUSTER_ID=$SELECTED_ID
    CLUSTER_NAME=$SELECTED_NAME
    [ -z "$CLUSTER_ID" ] && CLUSTER_ID=$(curl -sk -X POST "$NETBOX_URL/virtualization/clusters/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"name\":\"$CLUSTER_NAME\",\"slug\":\"$(slugify "$CLUSTER_NAME")\",\"type\":$TYPE_ID,\"group\":$GROUP_ID,\"site\":$SITE_ID}" | jq -r '.id')
fi

# ---------------- FINAL SYNC ----------------
echo -e "\nSyncing to Netbox..."

# 1. Device
DEVICE_ID=$EXISTING_DEV_ID
if [ -z "$DEVICE_ID" ]; then
    DEVICE_ID=$(curl -sk -X POST "$NETBOX_URL/dcim/devices/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"name\":\"$HOSTNAME\",\"device_type\":$DEVICETYPE_ID,\"role\":$DEVICEROLE_ID,\"site\":$SITE_ID,\"cluster\":$CLUSTER_ID}" | jq -r '.id')
else
    curl -sk -X PATCH "$NETBOX_URL/dcim/devices/$DEVICE_ID/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"cluster\":$CLUSTER_ID}" > /dev/null
fi

# 2. Interface Sync
INT_JSON=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/dcim/interfaces/?device_id=$DEVICE_ID")
INTERFACE_ID=$(echo "$INT_JSON" | jq -r ".results[] | select(.name == \"$IFACE\") | .id // empty")

if [ -z "$INTERFACE_ID" ]; then
    echo "Creating Interface $IFACE..."
    INTERFACE_ID=$(curl -sk -X POST "$NETBOX_URL/dcim/interfaces/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"device\":$DEVICE_ID,\"name\":\"$IFACE\",\"type\":\"1000base-t\"}" | jq -r '.id')
fi

# 3. MAC Address Object Sync (Essential for NetBox 4.x)
echo "Syncing MAC Address via L2 Object..."
MAC_OBJ_CHECK=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/dcim/mac-addresses/?mac_address=$MAC")
MAC_OBJ_ID=$(echo "$MAC_OBJ_CHECK" | jq -r '.results[0].id // empty')

if [ -z "$MAC_OBJ_ID" ]; then
    MAC_OBJ_ID=$(curl -sk -X POST "$NETBOX_URL/dcim/mac-addresses/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
        -d "{\"mac_address\":\"$MAC\",\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID}" | jq -r '.id')
else
    curl -sk -X PATCH "$NETBOX_URL/dcim/mac-addresses/$MAC_OBJ_ID/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
        -d "{\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID}" > /dev/null
fi

# Link the MAC Object as Primary to the Interface
curl -sk -X PATCH "$NETBOX_URL/dcim/interfaces/$INTERFACE_ID/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"primary_mac_address\": $MAC_OBJ_ID}" > /dev/null

# --- CLEANUP STEP ---
echo "Cleaning up duplicate interfaces for $HOSTNAME..."
echo "$INT_JSON" | jq -r ".results[] | select(.name != \"$IFACE\") | .id" | while read -r to_delete; do
    if [ -n "$to_delete" ]; then
        curl -sk -X DELETE "$NETBOX_URL/dcim/interfaces/$to_delete/" -H "Authorization: Token $NETBOX_TOKEN"
    fi
done

# 4. IP Address
IP_ID=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/ipam/ip-addresses/?address=$(urlencode "$IPADDR")" | jq -r '.results[0].id // empty')
if [ -z "$IP_ID" ]; then
    IP_ID=$(curl -sk -X POST "$NETBOX_URL/ipam/ip-addresses/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"address\":\"$IPADDR\",\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID,\"status\":\"active\"}" | jq -r '.id')
else
    curl -sk -X PATCH "$NETBOX_URL/ipam/ip-addresses/$IP_ID/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"assigned_object_id\":$INTERFACE_ID}" > /dev/null
fi

# Primary IP set
curl -sk -X PATCH "$NETBOX_URL/dcim/devices/$DEVICE_ID/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"primary_ip4\":$IP_ID}" > /dev/null

echo "------------------------------------------------"
echo "✅ Finished! $HOSTNAME updated. MAC $MAC is linked via Object ID $MAC_OBJ_ID"
echo "------------------------------------------------"
