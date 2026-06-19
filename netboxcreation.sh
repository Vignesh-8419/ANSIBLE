#!/bin/bash

# === Configuration ===
NETBOX_URL="http://192.168.253.135/api"
NETBOX_TOKEN="a4b61902bf90fb7e8aa727782881d5aa5cef7030"

# === Helper: URL encode function ===
urlencode() {
  local raw="$1"
  local encoded=""
  local i c
  for (( i = 0; i < ${#raw}; i++ )); do
    c=${raw:$i:1}
    case "$c" in
      [a-zA-Z0-9.~_-]) encoded+="$c" ;;
      *) printf -v encoded '%s%%%02X' "$encoded" "'$c" ;;
    esac
  done
  echo "$encoded"
}

# === Prompt for VM details ===
read -p "Type hostname: " HOSTNAME
read -p "Type IP address (e.g., 192.168.1.100/24): " IPADDR
read -p "Type MAC address (optional): " MAC
read -p "Type interface name (e.g., eth0): " IFACE_NAME
read -p "Type interface type (e.g., virtual, bridge, bond, lag, other): " IFACE_TYPE

# === Helper: Make NetBox API call ===
netbox_post() {
  echo -e "\nPOST to $1"
  echo "$2" | jq .
  curl -s -X POST "$1" \
    -H "Authorization: Token $NETBOX_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$2"
}

netbox_get() {
  curl -s -X GET "$1" \
    -H "Authorization: Token $NETBOX_TOKEN"
}

# === Retrieve or create Site ===
ENCODED_SITE_NAME=$(urlencode "Default DC")
SITE_JSON=$(netbox_get "$NETBOX_URL/dcim/sites/?name=$ENCODED_SITE_NAME")
SITE_ID=$(echo "$SITE_JSON" | jq -r '.results[0].id' 2>/dev/null)
if [ -z "$SITE_ID" ] || [ "$SITE_ID" == "null" ]; then
  echo "Creating site 'Default DC'..."
  SITE_PAYLOAD=$(jq -n --arg name "Default DC" --arg slug "default-dc" '{name: $name, slug: $slug}')
  netbox_post "$NETBOX_URL/dcim/sites/" "$SITE_PAYLOAD"
  SITE_JSON=$(netbox_get "$NETBOX_URL/dcim/sites/?name=$ENCODED_SITE_NAME")
  SITE_ID=$(echo "$SITE_JSON" | jq -r '.results[0].id' 2>/dev/null)
fi
echo "DEBUG: SITE_ID=$SITE_ID"

# === Retrieve or create Cluster Type ===
CLUSTER_TYPE_JSON=$(netbox_get "$NETBOX_URL/virtualization/cluster-types/?slug=vmware-esxi")
CLUSTER_TYPE_ID=$(echo "$CLUSTER_TYPE_JSON" | jq -r '.results[0].id' 2>/dev/null)
if [ -z "$CLUSTER_TYPE_ID" ] || [ "$CLUSTER_TYPE_ID" == "null" ]; then
  echo "Creating cluster type 'VMware ESXi'..."
  TYPE_PAYLOAD=$(jq -n --arg name "VMware ESXi" --arg slug "vmware-esxi" '{name: $name, slug: $slug}')
  netbox_post "$NETBOX_URL/virtualization/cluster-types/" "$TYPE_PAYLOAD"
  CLUSTER_TYPE_JSON=$(netbox_get "$NETBOX_URL/virtualization/cluster-types/?slug=vmware-esxi")
  CLUSTER_TYPE_ID=$(echo "$CLUSTER_TYPE_JSON" | jq -r '.results[0].id' 2>/dev/null)
fi
echo "DEBUG: CLUSTER_TYPE_ID=$CLUSTER_TYPE_ID"

# === Retrieve or create Cluster ===
ENCODED_CLUSTER_NAME=$(urlencode "ESXi Cluster")
CLUSTER_JSON=$(netbox_get "$NETBOX_URL/virtualization/clusters/?name=$ENCODED_CLUSTER_NAME")
CLUSTER_ID=$(echo "$CLUSTER_JSON" | jq -r '.results[0].id' 2>/dev/null)
if [ -z "$CLUSTER_ID" ] || [ "$CLUSTER_ID" == "null" ]; then
  echo "Creating cluster 'ESXi Cluster'..."
  CLUSTER_PAYLOAD=$(jq -n \
    --arg name "ESXi Cluster" \
    --arg type "$CLUSTER_TYPE_ID" \
    --arg site "$SITE_ID" \
    '{name: $name, type: ($type | tonumber), site: ($site | tonumber)}')
  netbox_post "$NETBOX_URL/virtualization/clusters/" "$CLUSTER_PAYLOAD"
  CLUSTER_JSON=$(netbox_get "$NETBOX_URL/virtualization/clusters/?name=$ENCODED_CLUSTER_NAME")
  CLUSTER_ID=$(echo "$CLUSTER_JSON" | jq -r '.results[0].id' 2>/dev/null)
fi
echo "DEBUG: CLUSTER_ID=$CLUSTER_ID"

# === Retrieve or create Tag ===
ENCODED_TAG_NAME=$(urlencode "vm_list")
TAG_JSON=$(netbox_get "$NETBOX_URL/extras/tags/?name=$ENCODED_TAG_NAME")
TAG_ID=$(echo "$TAG_JSON" | jq -r '.results[0].id' 2>/dev/null)
if [ -z "$TAG_ID" ] || [ "$TAG_ID" == "null" ]; then
  echo "Creating tag 'vm_list'..."
  TAG_PAYLOAD=$(jq -n --arg name "vm_list" --arg slug "vm-list" '{name: $name, slug: $slug}')
  netbox_post "$NETBOX_URL/extras/tags/" "$TAG_PAYLOAD"
  TAG_JSON=$(netbox_get "$NETBOX_URL/extras/tags/?name=$ENCODED_TAG_NAME")
  TAG_ID=$(echo "$TAG_JSON" | jq -r '.results[0].id' 2>/dev/null)
fi
echo "DEBUG: TAG_ID=$TAG_ID"

# === Retrieve or create VM ===
VM_JSON=$(netbox_get "$NETBOX_URL/virtualization/virtual-machines/?name=$HOSTNAME")
VM_ID=$(echo "$VM_JSON" | jq -r '.results[0].id' 2>/dev/null)
if [ -z "$VM_ID" ] || [ "$VM_ID" == "null" ]; then
  echo "Creating VM '$HOSTNAME'..."
  VM_PAYLOAD=$(jq -n \
    --arg name "$HOSTNAME" \
    --arg cluster "$CLUSTER_ID" \
    --arg tag "$TAG_ID" \
    '{name: $name, cluster: ($cluster | tonumber), status: "active", tags: [($tag | tonumber)]}')
  netbox_post "$NETBOX_URL/virtualization/virtual-machines/" "$VM_PAYLOAD"
  VM_JSON=$(netbox_get "$NETBOX_URL/virtualization/virtual-machines/?name=$HOSTNAME")
  VM_ID=$(echo "$VM_JSON" | jq -r '.results[0].id' 2>/dev/null)
else
  echo "⚠️ VM '$HOSTNAME' already exists. Skipping creation."
fi
echo "DEBUG: VM_ID=$VM_ID"

# === Retrieve or create interface ===
IFACE_JSON=$(netbox_get "$NETBOX_URL/virtualization/interfaces/?virtual_machine_id=$VM_ID&name=$IFACE_NAME")
IFACE_ID=$(echo "$IFACE_JSON" | jq -r '.results[0].id' 2>/dev/null)
if [ -z "$IFACE_ID" ] || [ "$IFACE_ID" == "null" ]; then
  echo "Creating interface '$IFACE_NAME' of type '$IFACE_TYPE'..."
  if [ -n "$MAC" ]; then
    IFACE_PAYLOAD=$(jq -n \
      --arg name "$IFACE_NAME" \
      --arg type "$IFACE_TYPE" \
      --arg mac "$MAC" \
      --arg vm_id "$VM_ID" \
      '{
        virtual_machine: ($vm_id | tonumber),
        name: $name,
        type: $type,
        mac_address: $mac
      }')
  else
    IFACE_PAYLOAD=$(jq -n \
      --arg name "$IFACE_NAME" \
      --arg type "$IFACE_TYPE" \
      --arg vm_id "$VM_ID" \
      '{
        virtual_machine: ($vm_id | tonumber),
        name: $name,
        type: $type
      }')
  fi
  netbox_post "$NETBOX_URL/virtualization/interfaces/" "$IFACE_PAYLOAD"
  IFACE_JSON=$(netbox_get "$NETBOX_URL/virtualization/interfaces/?virtual_machine_id=$VM_ID&name=$IFACE_NAME")
  IFACE_ID=$(echo "$IFACE_JSON" | jq -r '.results[0].id' 2>/dev/null)
else
  echo "⚠️ Interface '$IFACE_NAME' already exists. Skipping creation."
fi
echo "DEBUG: IFACE_ID=$IFACE_ID"

# === Assign IP ===
echo "Assigning IP address '$IPADDR' to interface '$IFACE_NAME'..."
IP_PAYLOAD=$(jq -n \
  --arg address "$IPADDR" \
  --arg iface_id "$IFACE_ID" \
  '{
    address: $address,
    status: "active",
    assigned_object_type: "virtualization.vminterface",
    assigned_object_id: ($iface_id | tonumber)
  }')
netbox_post "$NETBOX_URL/ipam/ip-addresses/" "$IP_PAYLOAD"

echo -e "\n✅ VM '$HOSTNAME' created or updated with interface '$IFACE_NAME' and IP assigned.
