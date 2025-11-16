#!/bin/bash

NETBOX_URL="http://192.168.253.135/api"
NETBOX_TOKEN="ac398a41868b98659d10c6f500a433f2409960d8"

# Common fixed values
MANUFACTURER_ID=1
DEVICETYPE_ID=1
SITE_ID=1

# JSON header
HDR="Content-Type: application/json"

# === Ask user inputs ===
read -p "Hostname: " HOSTNAME
read -p "Interface name (e.g. eth0): " IFACE
read -p "IP Address (CIDR) (e.g. 192.168.253.44/24): " IPADDR
read -p "MAC Address (e.g. AA:BB:CC:DD:EE:FF): " MAC
read -p "Tags (comma-separated, e.g. rocky,production): " TAGS

# Convert tags to JSON array
TAG_JSON=$(printf '%s' "$TAGS" | awk -F, '
BEGIN { printf "[ " }
{
    for (i=1; i<=NF; i++) {
        gsub(/^ +| +$/, "", $i)
        printf "\"%s\"", $i
        if (i < NF) printf ", "
    }
}
END { printf " ]" }')

echo "=== Creating device ==="

DEVICE_PAYLOAD=$(cat <<EOF
{
  "name": "$HOSTNAME",
  "device_type": $DEVICETYPE_ID,
  "device_role": 1,
  "site": $SITE_ID,
  "tags": $TAG_JSON
}
EOF
)

DEVICE_RESPONSE=$(curl -s -X POST "$NETBOX_URL/dcim/devices/" \
     -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
     -d "$DEVICE_PAYLOAD")

DEVICE_ID=$(echo "$DEVICE_RESPONSE" | jq -r '.id')

if [[ "$DEVICE_ID" == "null" ]]; then
    echo "❌ Failed to create device"
    echo "$DEVICE_RESPONSE"
    exit 1
fi

echo "✔ Device created with ID: $DEVICE_ID"

echo "=== Creating interface ==="

INTERFACE_PAYLOAD=$(cat <<EOF
{
  "device": $DEVICE_ID,
  "name": "$IFACE",
  "type": "1000base-t",
  "mac_address": "$MAC"
}
EOF
)

INTERFACE_RESPONSE=$(curl -s -X POST "$NETBOX_URL/dcim/interfaces/" \
    -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
    -d "$INTERFACE_PAYLOAD")

INTERFACE_ID=$(echo "$INTERFACE_RESPONSE" | jq -r '.id')

if [[ "$INTERFACE_ID" == "null" ]]; then
    echo "❌ Failed to create interface"
    echo "$INTERFACE_RESPONSE"
    exit 1
fi

echo "✔ Interface created with ID: $INTERFACE_ID"


echo "=== Creating IP address ==="

IP_PAYLOAD=$(cat <<EOF
{
  "address": "$IPADDR",
  "assigned_object_type": "dcim.interface",
  "assigned_object_id": $INTERFACE_ID,
  "status": "active"
}
EOF
)

IP_RESPONSE=$(curl -s -X POST "$NETBOX_URL/ipam/ip-addresses/" \
    -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
    -d "$IP_PAYLOAD")

IP_ID=$(echo "$IP_RESPONSE" | jq -r '.id')

if [[ "$IP_ID" == "null" ]]; then
    echo "❌ Failed to create IP address"
    echo "$IP_RESPONSE"
    exit 1
fi

echo "✔ IP address created with ID: $IP_ID"


echo "=== Assigning primary IP ==="

PRIMARY_PAYLOAD=$(cat <<EOF
{
  "primary_ip4": $IP_ID
}
EOF
)

PRIMARY_RESPONSE=$(curl -s -X PATCH "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
    -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
    -d "$PRIMARY_PAYLOAD")

echo "✔ Primary IP assigned"


echo "=== ✅ DONE ==="
echo "Device: $HOSTNAME"
echo "IP: $IPADDR"
echo "MAC: $MAC"
echo "Tags: $TAGS"
echo "-------------------------------"
