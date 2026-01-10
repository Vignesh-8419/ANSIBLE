#!/bin/bash
set -e

# ---------------- CONFIG ----------------
NETBOX_URL="https://192.168.253.134/api"
NETBOX_TOKEN="6cc3f3c7bdd27d7ba032d5e65c73f58bf3ec3eb8"
HDR="Content-Type: application/json"

SITE_ID=1
DEVICETYPE_ID=1
DEVICEROLE_ID=1

# ---------------- FUNCTIONS ----------------
slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g'
}

urlencode() {
  jq -rn --arg v "$1" '$v|@uri'
}

# ---------------- INPUT ----------------
read -p "Hostname: " HOSTNAME
read -p "Interface name: " IFACE
read -p "IP Address (CIDR): " IPADDR
read -p "MAC Address (optional): " MAC
read -p "Cluster Type: " TYPE_NAME
read -p "Cluster Group: " GROUP_NAME
read -p "Cluster Name: " CLUSTER_NAME

# ---------------- CLUSTER TYPE ----------------
echo "Checking Cluster Type..."
TYPE_ID=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" \
"$NETBOX_URL/virtualization/cluster-types/?name=$(urlencode "$TYPE_NAME")" | jq -r '.results[0].id // empty')

if [ -z "$TYPE_ID" ]; then
  TYPE_ID=$(curl -sk -X POST "$NETBOX_URL/virtualization/cluster-types/" \
    -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
    -d "{\"name\":\"$TYPE_NAME\",\"slug\":\"$(slugify "$TYPE_NAME")\"}" | jq -r '.id')
fi

# ---------------- CLUSTER GROUP ----------------
echo "Checking Cluster Group..."
GROUP_ID=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" \
"$NETBOX_URL/virtualization/cluster-groups/?name=$(urlencode "$GROUP_NAME")" | jq -r '.results[0].id // empty')

if [ -z "$GROUP_ID" ]; then
  GROUP_ID=$(curl -sk -X POST "$NETBOX_URL/virtualization/cluster-groups/" \
    -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
    -d "{\"name\":\"$GROUP_NAME\",\"slug\":\"$(slugify "$GROUP_NAME")\"}" | jq -r '.id')
fi

# ---------------- CLUSTER ----------------
echo "Checking Cluster..."
CLUSTER_JSON=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" \
"$NETBOX_URL/virtualization/clusters/?name=$(urlencode "$CLUSTER_NAME")")
CLUSTER_ID=$(echo "$CLUSTER_JSON" | jq -r '.results[0].id // empty')

if [ -z "$CLUSTER_ID" ]; then
  CLUSTER_ID=$(curl -sk -X POST "$NETBOX_URL/virtualization/clusters/" \
    -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
    -d "{\"name\":\"$CLUSTER_NAME\",\"slug\":\"$(slugify "$CLUSTER_NAME")\",\"type\":$TYPE_ID,\"group\":$GROUP_ID,\"site\":$SITE_ID}" | jq -r '.id')
fi

# ---------------- DEVICE ----------------
echo "Checking Device..."
DEV_JSON=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" \
"$NETBOX_URL/dcim/devices/?name=$(urlencode "$HOSTNAME")")
DEVICE_ID=$(echo "$DEV_JSON" | jq -r '.results[0].id // empty')

if [ -z "$DEVICE_ID" ]; then
  echo "Creating Device..."
  DEVICE_ID=$(curl -sk -X POST "$NETBOX_URL/dcim/devices/" \
    -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
    -d "{\"name\":\"$HOSTNAME\",\"device_type\":$DEVICETYPE_ID,\"role\":$DEVICEROLE_ID,\"site\":$SITE_ID,\"cluster\":$CLUSTER_ID}" | jq -r '.id')
else
  EXIST_CLUSTER=$(echo "$DEV_JSON" | jq -r '.results[0].cluster.id')
  if [ "$EXIST_CLUSTER" != "$CLUSTER_ID" ]; then
    echo "Updating device cluster..."
    curl -sk -X PATCH "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
      -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
      -d "{\"cluster\":$CLUSTER_ID}" > /dev/null
  else
    echo "Device OK – no change"
  fi
fi

# ---------------- INTERFACE ----------------
echo "Checking Interface..."
INT_JSON=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" \
"$NETBOX_URL/dcim/interfaces/?device_id=$DEVICE_ID&name=$(urlencode "$IFACE")")
INTERFACE_ID=$(echo "$INT_JSON" | jq -r '.results[0].id // empty')

if [ -z "$INTERFACE_ID" ]; then
  echo "Creating Interface..."
  if [ -n "$MAC" ]; then
    INTERFACE_ID=$(curl -sk -X POST "$NETBOX_URL/dcim/interfaces/" \
      -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
      -d "{\"device\":$DEVICE_ID,\"name\":\"$IFACE\",\"type\":\"1000base-t\",\"mac_address\":\"$MAC\"}" | jq -r '.id')
  else
    INTERFACE_ID=$(curl -sk -X POST "$NETBOX_URL/dcim/interfaces/" \
      -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
      -d "{\"device\":$DEVICE_ID,\"name\":\"$IFACE\",\"type\":\"1000base-t\"}" | jq -r '.id')
  fi
else
  if [ -n "$MAC" ]; then
    EXIST_MAC=$(echo "$INT_JSON" | jq -r '.results[0].mac_address')
    if [ "$EXIST_MAC" != "$MAC" ]; then
      echo "Updating MAC..."
      curl -sk -X PATCH "$NETBOX_URL/dcim/interfaces/$INTERFACE_ID/" \
        -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
        -d "{\"mac_address\":\"$MAC\"}" > /dev/null
    else
      echo "Interface OK – no change"
    fi
  else
    echo "Interface exists (MAC not managed)"
  fi
fi

# ---------------- IP ----------------
echo "Checking IP..."
IP_JSON=$(curl -sk -H "Authorization: Token $NETBOX_TOKEN" \
"$NETBOX_URL/ipam/ip-addresses/?address=$(urlencode "$IPADDR")")
IP_ID=$(echo "$IP_JSON" | jq -r '.results[0].id // empty')

if [ -z "$IP_ID" ]; then
  echo "Creating IP..."
  IP_ID=$(curl -sk -X POST "$NETBOX_URL/ipam/ip-addresses/" \
    -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
    -d "{\"address\":\"$IPADDR\",\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID,\"status\":\"active\"}" | jq -r '.id')
else
  ASSIGNED=$(echo "$IP_JSON" | jq -r '.results[0].assigned_object_id')
  if [ "$ASSIGNED" != "$INTERFACE_ID" ]; then
    echo "Reassigning IP..."
    curl -sk -X PATCH "$NETBOX_URL/ipam/ip-addresses/$IP_ID/" \
      -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
      -d "{\"assigned_object_type\":\"dcim.interface\",\"assigned_object_id\":$INTERFACE_ID}" > /dev/null
  else
    echo "IP OK – no change"
  fi
fi

# ---------------- PRIMARY IP ----------------
curl -sk -X PATCH "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
  -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
  -d "{\"primary_ip4\":$IP_ID}" > /dev/null

echo "------------------------------------------------"
echo "✅ $HOSTNAME synchronized successfully"
echo "------------------------------------------------"
