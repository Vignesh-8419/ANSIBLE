#!/bin/bash

# NetBox API details
NETBOX_URL="http://192.168.253.135"
TOKEN="f68492e4231a818bc477b65295c660b2409cddde"

# Prompt for input
read -p "Enter device name: " DEVICE_NAME
read -p "Enter IP address (CIDR format, e.g., 192.168.1.10/24): " IP_ADDRESS
read -p "Enter MAC address (e.g., 00:1A:2B:3C:4D:5E): " MAC_ADDRESS
read -p "Enter tag name (e.g., new-rocky): " TAG_NAME
read -p "Enter interface name (e.g., eth0): " INTERFACE_NAME

# Create tag if not exists
curl -s -X POST "$NETBOX_URL/api/extras/tags/" \
  -H "Authorization: Token $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$TAG_NAME\", \"slug\": \"$TAG_NAME\"}" > /dev/null

# Get tag ID
TAG_ID=$(curl -s -H "Authorization: Token $TOKEN" "$NETBOX_URL/api/extras/tags/?name=$TAG_NAME" | grep -o '"id":[0-9]*' | head -n1 | cut -d: -f2)

if [ -z "$TAG_ID" ]; then
  echo "❌ Failed to retrieve tag ID for '$TAG_NAME'"
  exit 1
fi

# Create device
DEVICE_RESPONSE=$(curl -s -X POST "$NETBOX_URL/api/dcim/devices/" \
  -H "Authorization: Token $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"$DEVICE_NAME\",
    \"device_type\": 1,
    \"role\": 1,
    \"site\": 1,
    \"status\": \"active\",
    \"tags\": [$TAG_ID]
  }")

echo "📦 Device creation response:"
echo "$DEVICE_RESPONSE"

DEVICE_ID=$(echo "$DEVICE_RESPONSE" | grep -o '"id":[0-9]*' | head -n1 | cut -d: -f2)

if [ -z "$DEVICE_ID" ]; then
  echo "❌ Device creation failed. Check response above."
  exit 1
fi

# Create interface
INTERFACE_RESPONSE=$(curl -s -X POST "$NETBOX_URL/api/dcim/interfaces/" \
  -H "Authorization: Token $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"device\": $DEVICE_ID,
    \"name\": \"$INTERFACE_NAME\",
    \"type\": \"1000base-t\",
    \"mac_address\": \"$MAC_ADDRESS\"
  }")

echo "🔌 Interface creation response:"
echo "$INTERFACE_RESPONSE"

INTERFACE_ID=$(echo "$INTERFACE_RESPONSE" | grep -o '"id":[0-9]*' | head -n1 | cut -d: -f2)

if [ -z "$INTERFACE_ID" ]; then
  echo "❌ Interface creation failed. Check response above."
  exit 1
fi

# Assign IP address
IP_RESPONSE=$(curl -s -X POST "$NETBOX_URL/api/ipam/ip-addresses/" \
  -H "Authorization: Token $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"address\": \"$IP_ADDRESS\",
    \"status\": \"active\",
    \"assigned_object_type\": \"dcim.interface\",
    \"assigned_object_id\": $INTERFACE_ID
  }")

echo "🌐 IP assignment response:"
echo "$IP_RESPONSE"

echo "✅ Device '$DEVICE_NAME' created with IP $IP_ADDRESS and MAC $MAC_ADDRESS"
