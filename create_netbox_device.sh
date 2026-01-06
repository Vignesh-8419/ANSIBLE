#!/bin/bash

# --- CONFIGURATION ---
NETBOX_URL="https://192.168.253.134/api"
NETBOX_TOKEN="e3b30f093150844cb025c4b5b91c49f4b8285092"
HDR="Content-Type: application/json"

# Fixed IDs from your environment
SITE_ID=1
DEVICETYPE_ID=1
DEVICEROLE_ID=1

# === User Inputs ===
read -p "Hostname: " HOSTNAME
read -p "Interface name: " IFACE
read -p "IP Address (CIDR): " IPADDR
read -p "MAC Address: " MAC
read -p "Cluster Type (e.g. VMware/Physical): " TYPE_NAME
read -p "Cluster Group (e.g. Production): " GROUP_NAME
read -p "Cluster Name (e.g. rocky-8-servers): " CLUSTER_NAME

# ---------------------------------------------------------
# 1. Handle Cluster Type (Check/Create)
# ---------------------------------------------------------
echo "=== Checking Cluster Type: $TYPE_NAME ==="
TYPE_CHECK=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/virtualization/cluster-types/?name=$TYPE_NAME")
CLUSTER_TYPE_ID=$(echo "$TYPE_CHECK" | jq -r '.results[0].id // empty')

if [ -z "$CLUSTER_TYPE_ID" ] || [ "$CLUSTER_TYPE_ID" == "null" ]; then
    echo "Creating new Cluster Type: $TYPE_NAME..."
    TYPE_SLUG=$(echo "$TYPE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
    CLUSTER_TYPE_ID=$(curl -sk -X POST "$NETBOX_URL/virtualization/cluster-types/" \
        -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
        -d "{\"name\":\"$TYPE_NAME\",\"slug\":\"$TYPE_SLUG\"}" | jq -r '.id')
fi

# ---------------------------------------------------------
# 2. Handle Cluster Group (Check/Create)
# ---------------------------------------------------------
echo "=== Checking Cluster Group: $GROUP_NAME ==="
GROUP_CHECK=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/virtualization/cluster-groups/?name=$GROUP_NAME")
GROUP_ID=$(echo "$GROUP_CHECK" | jq -r '.results[0].id // empty')

if [ -z "$GROUP_ID" ] || [ "$GROUP_ID" == "null" ]; then
    echo "Creating new Cluster Group: $GROUP_NAME..."
    GROUP_SLUG=$(echo "$GROUP_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
    GROUP_ID=$(curl -sk -X POST "$NETBOX_URL/virtualization/cluster-groups/" \
        -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
        -d "{\"name\":\"$GROUP_NAME\",\"slug\":\"$GROUP_SLUG\"}" | jq -r '.id')
fi

# ---------------------------------------------------------
# 3. Handle Cluster (Check/Create)
# ---------------------------------------------------------
echo "=== Checking Cluster: $CLUSTER_NAME ==="
EXISTING_CLUSTER=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" "$NETBOX_URL/virtualization/clusters/?name=$CLUSTER_NAME")
CLUSTER_ID=$(echo "$EXISTING_CLUSTER" | jq -r '.results[0].id // empty')

if [ -z "$CLUSTER_ID" ] || [ "$CLUSTER_ID" == "null" ]; then
    echo "Creating new cluster: $CLUSTER_NAME..."
    CLUSTER_SLUG=$(echo "$CLUSTER_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')

    CLUSTER_PAYLOAD=$(cat <<EOF
{
  "name": "$CLUSTER_NAME",
  "slug": "$CLUSTER_SLUG",
  "type": $CLUSTER_TYPE_ID,
  "group": $GROUP_ID,
  "site": $SITE_ID
}
EOF
)
    CLUSTER_ID=$(curl -sk -X POST "$NETBOX_URL/virtualization/clusters/" \
        -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
        -d "$CLUSTER_PAYLOAD" | jq -r '.id // empty')
fi

# ---------------------------------------------------------
# 4. Create Device
# ---------------------------------------------------------
echo "=== Creating device: $HOSTNAME ==="
DEVICE_PAYLOAD=$(cat <<EOF
{
  "name": "$HOSTNAME",
  "device_type": $DEVICETYPE_ID,
  "role": $DEVICEROLE_ID,
  "site": $SITE_ID,
  "cluster": $CLUSTER_ID
}
EOF
)
DEVICE_RESPONSE=$(curl -sk -X POST "$NETBOX_URL/dcim/devices/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "$DEVICE_PAYLOAD")
DEVICE_ID=$(echo "$DEVICE_RESPONSE" | jq -r '.id // empty')

if [ -z "$DEVICE_ID" ] || [ "$DEVICE_ID" == "null" ]; then
    echo "❌ Failed to create device. Response: $DEVICE_RESPONSE"
    exit 1
fi

# ---------------------------------------------------------
# 5. Network Setup (Interface & IP)
# ---------------------------------------------------------
echo "=== Finalizing Network Configuration ==="
INTERFACE_ID=$(curl -sk -X POST "$NETBOX_URL/dcim/interfaces/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
    -d "{\"device\":$DEVICE_ID,\"name\":\"$IFACE\",\"type\":\"1000base-t\",\"mac_address\":\"$MAC\"}" | jq -r '.id // empty')

IP_ID=$(curl -sk -X POST "$NETBOX_URL/ipam/ip-addresses/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
    -d "{\"address\":\"$IPADDR\",\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID,\"status\":\"active\"}" | jq -r '.id // empty')

# Set Primary IP
curl -sk -X PATCH "$NETBOX_URL/dcim/devices/$DEVICE_ID/" -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" -d "{\"primary_ip4\": $IP_ID}" > /dev/null

echo "------------------------------------------------"
echo "✅ SUCCESS: $HOSTNAME created!"
echo "Type: $TYPE_NAME | Group: $GROUP_NAME | Cluster: $CLUSTER_NAME"
echo "------------------------------------------------"
