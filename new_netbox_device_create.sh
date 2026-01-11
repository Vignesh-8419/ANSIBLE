#!/bin/bash
set -e

# ---------------- CONFIG ----------------
NETBOX_URL="https://192.168.253.134/api"
NETBOX_TOKEN="6cc3f3c7bdd27d7ba032d5e65c73f58bf3ec3eb8"
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
    HOSTNAME=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no ${SSH_USER}@${REMOTE_HOST} "hostname")
    IFACE_DATA=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no ${SSH_USER}@${REMOTE_HOST} "ip -o -4 addr show scope global | head -1")
    IFACE=$(echo $IFACE_DATA | awk '{print $2}')
    IPADDR=$(echo $IFACE_DATA | awk '{print $4}')
    MAC=$(sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no ${SSH_USER}@${REMOTE_HOST} "cat /sys/class/net/$IFACE/address")
    echo ">>> Fetched: $HOSTNAME | $IPADDR | $MAC"
else
    read -p "Hostname: " HOSTNAME
    read -p "Interface name: " IFACE
    read -p "IP Address (CIDR): " IPADDR
    read -p "MAC Address (optional): " MAC
fi

# ---------------- PRE-CHECK EXISTING DEVICE ----------------
echo -e "\nChecking if $HOSTNAME exists in Netbox..."
DEV_PRECHECK=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/dcim/devices/?name=$(urlencode "$HOSTNAME")")
EXISTING_DEV_ID=$(echo "$DEV_PRECHECK" | jq -r '.results[0].id // empty')

CURRENT_CLUSTER_INFO="None"
if [ -n "$EXISTING_DEV_ID" ]; then
    # Fetch details about the existing cluster assignment
    C_NAME=$(echo "$DEV_PRECHECK" | jq -r '.results[0].cluster.name // "N/A"')
    C_TYPE=$(echo "$DEV_PRECHECK" | jq -r '.results[0].cluster.type.name // "N/A"')
    # Cluster Group is often nested or requires another lookup, for brevity:
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
    # If user picks 1 and device exists, we just reuse the existing Cluster ID
    CLUSTER_ID=$(echo "$DEV_PRECHECK" | jq -r '.results[0].cluster.id // empty')
    CLUSTER_NAME=$(echo "$DEV_PRECHECK" | jq -r '.results[0].cluster.name // empty')
    
    if [ "$CLUSTER_ID" != "null" ] && [ -n "$CLUSTER_ID" ]; then
        USE_EXISTING="true"
        echo "Using existing cluster: $CLUSTER_NAME"
    fi
fi

if [ "$CLUSTER_MODE" == "2" ]; then
    FORCE_MANUAL="true"
fi

# ---------------- CLUSTER SELECTION (SKIP IF USING EXISTING) ----------------
if [ "$USE_EXISTING" == "false" ]; then
    # 1. Cluster Type
    select_from_netbox "virtualization/cluster-types/" "Cluster Type" "$FORCE_MANUAL"
    TYPE_ID=$SELECTED_ID
    [ -z "$TYPE_ID" ] && TYPE_ID=$(curl -sk -X POST "$NETBOX_URL/virtualization/cluster-types/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"name\":\"$SELECTED_NAME\",\"slug\":\"$(slugify "$SELECTED_NAME")\"}" | jq -r '.id')

    # 2. Cluster Group
    select_from_netbox "virtualization/cluster-groups/" "Cluster Group" "$FORCE_MANUAL"
    GROUP_ID=$SELECTED_ID
    [ -z "$GROUP_ID" ] && GROUP_ID=$(curl -sk -X POST "$NETBOX_URL/virtualization/cluster-groups/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"name\":\"$SELECTED_NAME\",\"slug\":\"$(slugify "$SELECTED_NAME")\"}" | jq -r '.id')

    # 3. Cluster Name
    select_from_netbox "virtualization/clusters/" "Cluster" "$FORCE_MANUAL"
    CLUSTER_ID=$SELECTED_ID
    CLUSTER_NAME=$SELECTED_NAME
    [ -z "$CLUSTER_ID" ] && CLUSTER_ID=$(curl -sk -X POST "$NETBOX_URL/virtualization/clusters/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"name\":\"$CLUSTER_NAME\",\"slug\":\"$(slugify "$CLUSTER_NAME")\",\"type\":$TYPE_ID,\"group\":$GROUP_ID,\"site\":$SITE_ID}" | jq -r '.id')
fi

# ---------------- FINAL SYNC ----------------
echo -e "\nSyncing $HOSTNAME to Netbox..."

# 1. Device
DEVICE_ID=$EXISTING_DEV_ID
if [ -z "$DEVICE_ID" ]; then
    DEVICE_ID=$(curl -sk -X POST "$NETBOX_URL/dcim/devices/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"name\":\"$HOSTNAME\",\"device_type\":$DEVICETYPE_ID,\"role\":$DEVICEROLE_ID,\"site\":$SITE_ID,\"cluster\":$CLUSTER_ID}" | jq -r '.id')
else
    # Update cluster if changed
    curl -sk -X PATCH "$NETBOX_URL/dcim/devices/$DEVICE_ID/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"cluster\":$CLUSTER_ID}" > /dev/null
fi

# 2. Interface (Same MAC update logic)
INT_JSON=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/dcim/interfaces/?device_id=$DEVICE_ID&name=$(urlencode "$IFACE")")
INTERFACE_ID=$(echo "$INT_JSON" | jq -r '.results[0].id // empty')
if [ -z "$INTERFACE_ID" ]; then
    INTERFACE_ID=$(curl -sk -X POST "$NETBOX_URL/dcim/interfaces/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"device\":$DEVICE_ID,\"name\":\"$IFACE\",\"type\":\"1000base-t\",\"mac_address\":\"$MAC\"}" | jq -r '.id')
else
    EXISTING_MAC=$(echo "$INT_JSON" | jq -r '.results[0].mac_address // empty' | tr '[:upper:]' '[:lower:]')
    NEW_MAC=$(echo "$MAC" | tr '[:upper:]' '[:lower:]')
    if [ "$EXISTING_MAC" != "$NEW_MAC" ] && [ -n "$NEW_MAC" ]; then
        curl -sk -X PATCH "$NETBOX_URL/dcim/interfaces/$INTERFACE_ID/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"mac_address\":\"$NEW_MAC\"}" > /dev/null
    fi
fi

# 3. IP Address
IP_ID=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/ipam/ip-addresses/?address=$(urlencode "$IPADDR")" | jq -r '.results[0].id // empty')
if [ -z "$IP_ID" ]; then
    IP_ID=$(curl -sk -X POST "$NETBOX_URL/ipam/ip-addresses/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"address\":\"$IPADDR\",\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID,\"status\":\"active\"}" | jq -r '.id')
fi

# Set Primary IP
curl -sk -X PATCH "$NETBOX_URL/dcim/devices/$DEVICE_ID/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"primary_ip4\":$IP_ID}" > /dev/null

echo "------------------------------------------------"
echo "✅ Finished! $HOSTNAME is updated in $CLUSTER_NAME"
echo "------------------------------------------------"
