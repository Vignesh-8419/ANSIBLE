#!/bin/bash
set -e

# ---------------- CONFIG ----------------
NETBOX_URL="https://192.168.253.134/api"
NETBOX_TOKEN="d16af27a4c533af154c60b7f6687f824f60183ba"
HDR="Content-Type: application/json"

SSH_USER="root"
SSH_PASS="Root@123"

SITE_ID=1
DEVICETYPE_ID=1
DEVICEROLE_ID=1

# ---------------- HELPERS ----------------
slugify() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g'; }
urlencode() { jq -rn --arg v "$1" '$v|@uri'; }

get_or_create() {
    local endpoint=$1
    local name=$2
    local extra_json=$3
    local slug=$(slugify "$name")

    # Check if exists
    local existing_id=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/$endpoint/?name=$(urlencode "$name")" | jq -r '.results[0].id // empty')

    if [ -n "$existing_id" ] && [ "$existing_id" != "null" ]; then
        echo "$existing_id"
    else
        # Create new
        local response=$(curl -sk -X POST "$NETBOX_URL/$endpoint/" \
            -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
            -d "{\"name\":\"$name\",\"slug\":\"$slug\"$extra_json}")
        echo "$response" | jq -r '.id // empty'
    fi
}

# ---------------- DATA SOURCE ----------------
echo "How would you like to get server details?"
echo "1) Fetch automatically via SSH"
echo "2) Type manually"
read -p "Choice [1-2]: " SOURCE_CHOICE

if [ "$SOURCE_CHOICE" == "1" ]; then
    read -p "Enter Target Server IP/Hostname: " REMOTE_HOST
    echo "Fetching data..."
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
    [ -n "$MAC" ] && MAC=$(echo "$MAC" | xargs | tr '[:lower:]' '[:upper:]')
fi

# ---------------- PRE-CHECK EXISTING DEVICE ----------------
DEV_PRECHECK=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/dcim/devices/?name=$(urlencode "$HOSTNAME")")
EXISTING_DEV_ID=$(echo "$DEV_PRECHECK" | jq -r '.results[0].id // empty')

# ---------------- CLUSTER SYNC ----------------
echo -e "\nCluster Configuration:"
echo "1) Pick from existing Netbox clusters"
echo "2) Add to a specific/new cluster setup (Manual entry)"
read -p "Choice [1-2]: " CLUSTER_MODE

if [ "$CLUSTER_MODE" == "2" ]; then
    read -p "Enter Cluster Type name: " TYPE_NAME
    TYPE_ID=$(get_or_create "virtualization/cluster-types" "$TYPE_NAME")

    read -p "Enter Cluster Group name: " GROUP_NAME
    GROUP_ID=$(get_or_create "virtualization/cluster-groups" "$GROUP_NAME")

    read -p "Enter Cluster name: " CLUSTER_NAME
    CLUSTER_ID=$(get_or_create "virtualization/clusters" "$CLUSTER_NAME" ",\"type\":$TYPE_ID,\"group\":$GROUP_ID,\"site\":$SITE_ID")
else
    echo -e "\n--- Select Cluster ---"
    results=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/virtualization/clusters/" | jq -r '.results[] | "\(.id)|\(.name)"')
    if [ -z "$results" ]; then
        echo "No existing clusters found. Please use Manual Entry."
        exit 1
    fi
    count=1
    declare -A cluster_map
    while IFS='|' read -r id name; do
        echo "$count) $name"
        cluster_map[$count]=$id
        ((count++))
    done <<< "$results"
    read -p "Choose cluster [1-$((count-1))]: " c_choice
    CLUSTER_ID=${cluster_map[$c_choice]}
fi

# Final check for Cluster ID
if [ -z "$CLUSTER_ID" ] || [ "$CLUSTER_ID" == "null" ]; then
    echo "❌ Error: Failed to obtain a valid Cluster ID. Check your Netbox logs or permissions."
    exit 1
fi

# ---------------- FINAL SYNC ----------------
echo -e "\nSyncing to Netbox..."

# 1. Device
if [ -z "$EXISTING_DEV_ID" ] || [ "$EXISTING_DEV_ID" == "null" ]; then
    DEVICE_ID=$(curl -sk -X POST "$NETBOX_URL/dcim/devices/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
        -d "{\"name\":\"$HOSTNAME\",\"device_type\":$DEVICETYPE_ID,\"role\":$DEVICEROLE_ID,\"site\":$SITE_ID,\"cluster\":$CLUSTER_ID}" | jq -r '.id')
else
    DEVICE_ID=$EXISTING_DEV_ID
    curl -sk -X PATCH "$NETBOX_URL/dcim/devices/$DEVICE_ID/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"cluster\":$CLUSTER_ID}" > /dev/null
fi

# 2. Interface Sync & Cleanup
# ------------------------------------------------
# Get all existing interfaces for this device
ALL_INTS_JSON=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/dcim/interfaces/?device_id=$DEVICE_ID")

# Check if our current interface ($IFACE) already exists
INTERFACE_ID=$(echo "$ALL_INTS_JSON" | jq -r ".results[] | select(.name == \"$IFACE\") | .id // empty")

if [ -z "$INTERFACE_ID" ] || [ "$INTERFACE_ID" == "null" ]; then
    echo "Creating interface: $IFACE"
    INTERFACE_ID=$(curl -sk -X POST "$NETBOX_URL/dcim/interfaces/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
        -d "{\"device\":$DEVICE_ID,\"name\":\"$IFACE\",\"type\":\"1000base-t\"}" | jq -r '.id')
fi

# CLEANUP: Delete any interfaces on this device that are NOT named $IFACE
echo "Cleaning up old interfaces..."
STALE_IDS=$(echo "$ALL_INTS_JSON" | jq -r ".results[] | select(.name != \"$IFACE\") | .id")

for stale_id in $STALE_IDS; do
    echo "Deleting stale interface ID: $stale_id"
    curl -sk -X DELETE "$NETBOX_URL/dcim/interfaces/$stale_id/" -H "Authorization: Token $NETBOX_TOKEN"
done

# 3. MAC Object
if [ -n "$MAC" ]; then
    MAC_OBJ_CHECK=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/dcim/mac-addresses/?mac_address=$MAC")
    MAC_OBJ_ID=$(echo "$MAC_OBJ_CHECK" | jq -r '.results[0].id // empty')

    if [ -z "$MAC_OBJ_ID" ] || [ "$MAC_OBJ_ID" == "null" ]; then
        MAC_OBJ_ID=$(curl -sk -X POST "$NETBOX_URL/dcim/mac-addresses/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
            -d "{\"mac_address\":\"$MAC\",\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID}" | jq -r '.id')
    else
        curl -sk -X PATCH "$NETBOX_URL/dcim/mac-addresses/$MAC_OBJ_ID/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
            -d "{\"assigned_object_id\":$INTERFACE_ID}" > /dev/null
    fi
    curl -sk -X PATCH "$NETBOX_URL/dcim/interfaces/$INTERFACE_ID/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"primary_mac_address\": $MAC_OBJ_ID}" > /dev/null
fi

# 4. IP Sync
IP_ID=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/ipam/ip-addresses/?address=$(urlencode "$IPADDR")" | jq -r '.results[0].id // empty')
if [ -z "$IP_ID" ] || [ "$IP_ID" == "null" ]; then
    IP_ID=$(curl -sk -X POST "$NETBOX_URL/ipam/ip-addresses/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
        -d "{\"address\":\"$IPADDR\",\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID,\"status\":\"active\"}" | jq -r '.id')
else
    curl -sk -X PATCH "$NETBOX_URL/ipam/ip-addresses/$IP_ID/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"assigned_object_id\":$INTERFACE_ID}" > /dev/null
fi

curl -sk -X PATCH "$NETBOX_URL/dcim/devices/$DEVICE_ID/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"primary_ip4\":$IP_ID}" > /dev/null

echo "------------------------------------------------"
echo "✅ Finished! $HOSTNAME is updated."
echo "Linked to Cluster ID: $CLUSTER_ID"
echo "------------------------------------------------"
