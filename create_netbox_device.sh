#!/bin/bash

NETBOX_URL="http://192.168.253.135/api"
NETBOX_TOKEN="ac398a41868b98659d10c6f500a433f2409960d8"
HDR="Content-Type: application/json"

# Fixed IDs
MANUFACTURER_ID=1
DEVICETYPE_ID=1
SITE_ID=1
DEVICEROLE_ID=1   # Server

# === User Inputs ===
read -p "Hostname: " HOSTNAME
read -p "Interface name (e.g. eth0): " IFACE
read -p "IP Address (CIDR) (e.g. 192.168.253.44/24): " IPADDR
read -p "MAC Address (e.g. AA:BB:CC:DD:EE:FF): " MAC
read -p "Tags (comma-separated, e.g. rocky,production): " TAGS


# ---------------------------------------------------------
# Convert tags to JSON array and auto-create missing tags
# ---------------------------------------------------------
TAG_IDS=()

IFS=',' read -ra TAGLIST <<< "$TAGS"

for TAG in "${TAGLIST[@]}"; do
    TAG=$(echo "$TAG" | xargs)   # trim spaces

    # Check if tag exists
    EXISTING=$(curl -s -H "Authorization: Token $NETBOX_TOKEN" \
        "$NETBOX_URL/extras/tags/?name=$TAG" | jq '.results | length')

    if [[ "$EXISTING" -eq 0 ]]; then
        echo "Creating tag: $TAG"

        NEW_TAG_PAYLOAD=$(cat <<EOF
{ "name": "$TAG", "slug": "$TAG" }
EOF
)

        TAG_RESPONSE=$(curl -s -X POST "$NETBOX_URL/extras/tags/" \
            -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
            -d "$NEW_TAG_PAYLOAD")

        TAG_ID=$(echo "$TAG_RESPONSE" | jq -r '.id')
    else
        TAG_ID=$(curl -s -H "Authorization: Token $NETBOX_TOKEN" \
            "$NETBOX_URL/extras/tags/?name=$TAG" | jq -r '.results[0].id')
    fi

    TAG_IDS+=("$TAG_ID")
done

# Build JSON array
TAG_JSON="[ $(printf '%s\n' "${TAG_IDS[@]}" | sed 's/^/"/;s/$/"/' | paste -sd ', ' -) ]"


# ---------------------------------------------------------
# Create Device
# ---------------------------------------------------------
echo "=== Creating device ==="

DEVICE_PAYLOAD=$(cat <<EOF
{
  "name": "$HOSTNAME",
  "device_type": $DEVICETYPE_ID,
  "role": $DEVICEROLE_ID,
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

echo "✔ Device created ID: $DEVICE_ID"



# ---------------------------------------------------------
# Create Interface
# ---------------------------------------------------------
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

echo "✔ Interface created ID: $INTERFACE_ID"


# ---------------------------------------------------------
# Create IP Address
# ---------------------------------------------------------
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
    echo "❌ Failed to create IP"
    echo "$IP_RESPONSE"
    exit 1
fi

echo "✔ IP address created ID: $IP_ID"


# ---------------------------------------------------------
# Assign Primary IP
# ---------------------------------------------------------
echo "=== Assigning primary IP ==="

PRIMARY_PAYLOAD=$(cat <<EOF
{
  "primary_ip4": $IP_ID
}
EOF
)

curl -s -X PATCH "$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
    -H "$HDR" -H "Authorization: Token $NETBOX_TOKEN" \
    -d "$PRIMARY_PAYLOAD" >/dev/null

echo "✔ Primary IP assigned"


echo
echo "=== 🎉 Completed Successfully ==="
echo "Device: $HOSTNAME"
echo "Interface: $IFACE"
echo "IP: $IPADDR"
echo "MAC: $MAC"
echo "Tags: $TAGS"
echo "--------------------------------"
