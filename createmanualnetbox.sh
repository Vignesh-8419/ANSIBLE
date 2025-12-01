#!/bin/bash

# ==============================
# NetBox Configuration
# ==============================
NETBOX_URL="https://192.168.253.134"
NETBOX_TOKEN="e3ee4eda03d81a42b07de1d20064b89bba21e041"

DEVICE_TYPE_ID=1
ROLE_ID=1
SITE_ID=1

# ==============================
# INPUT SECTION
# ==============================

read -p "Hostname (FQDN): " DEVICE_NAME
read -p "IP Address (CIDR) (ex: 192.168.253.162/24): " IPADDR
read -p "MAC Address (ex: 00:50:56:23:97:F9): " MACADDR
read -p "Interface Name (ex: ens192): " IFNAME
read -p "Tag Name: " TAG_NAME
read -p "Serial Number (optional): " SERIAL_NO

TAG_SLUG=$(echo "$TAG_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')

# ==============================
# Helper: Make API calls
# ==============================
api() {
  curl -sk -H "Authorization: Token $NETBOX_TOKEN" \
      -H "Content-Type: application/json" \
      "$@"
}

# ==============================
# 1. CREATE TAG
# ==============================
echo "[1] Creating tag: $TAG_NAME"

api -X POST \
  -d "{\"name\":\"$TAG_NAME\", \"slug\":\"$TAG_SLUG\"}" \
  "$NETBOX_URL/api/extras/tags/" > /dev/null

# ==============================
# 2. GET TAG ID
# ==============================
TAG_ID=$(api "$NETBOX_URL/api/extras/tags/?name=$TAG_NAME" | jq '.results[0].id')

if [ -z "$TAG_ID" ] || [ "$TAG_ID" == "null" ]; then
  echo "❌ Tag ID lookup failed"
  exit 1
fi

echo "➡️ Tag ID = $TAG_ID"


# ==============================
# 3. BUILD DEVICE JSON
# ==============================

if [ -n "$SERIAL_NO" ]; then
  DEVICE_BODY="{
        \"name\": \"$DEVICE_NAME\",
        \"device_type\": $DEVICE_TYPE_ID,
        \"role\": $ROLE_ID,
        \"site\": $SITE_ID,
        \"status\": \"active\",
        \"tags\": [$TAG_ID],
        \"serial\": \"$SERIAL_NO\"
      }"
else
  DEVICE_BODY="{
        \"name\": \"$DEVICE_NAME\",
        \"device_type\": $DEVICE_TYPE_ID,
        \"role\": $ROLE_ID,
        \"site\": $SITE_ID,
        \"status\": \"active\",
        \"tags\": [$TAG_ID]
      }"
fi

# ==============================
# 4. CREATE DEVICE
# ==============================
echo "[2] Creating device: $DEVICE_NAME"

DEVICE_JSON=$(api -X POST \
  -d "$DEVICE_BODY" \
  "$NETBOX_URL/api/dcim/devices/")

DEVICE_ID=$(echo "$DEVICE_JSON" | jq '.id')

if [ -z "$DEVICE_ID" ] || [ "$DEVICE_ID" == "null" ]; then
  echo "❌ Device creation failed"
  echo "$DEVICE_JSON"
  exit 1
fi

echo "➡️ Device ID = $DEVICE_ID"


# ==============================
# 5. CREATE INTERFACE
# ==============================
echo "[3] Creating interface: $IFNAME"

INTERFACE_JSON=$(api -X POST \
  -d "{
        \"device\": $DEVICE_ID,
        \"name\": \"$IFNAME\",
        \"type\": \"1000base-t\",
        \"mac_address\": \"$MACADDR\"
      }" \
  "$NETBOX_URL/api/dcim/interfaces/")

INTERFACE_ID=$(echo "$INTERFACE_JSON" | jq '.id')

if [ -z "$INTERFACE_ID" ] || [ "$INTERFACE_ID" == "null" ]; then
  echo "❌ Interface creation failed"
  echo "$INTERFACE_JSON"
  exit 1
fi

echo "➡️ Interface ID = $INTERFACE_ID"


# ==============================
# 6. CREATE IP ADDRESS
# ==============================
echo "[4] Creating IP Address: $IPADDR"

IP_JSON=$(api -X POST \
  -d "{
        \"address\": \"$IPADDR\",
        \"status\": \"active\",
        \"assigned_object_type\": \"dcim.interface\",
        \"assigned_object_id\": $INTERFACE_ID
      }" \
  "$NETBOX_URL/api/ipam/ip-addresses/")

IP_ID=$(echo "$IP_JSON" | jq '.id')

if [ -z "$IP_ID" ] || [ "$IP_ID" == "null" ]; then
  echo "❌ IP assignment failed"
  echo "$IP_JSON"
  exit 1
fi

echo "➡️ IP ID = $IP_ID"


# ==============================
# 7. SET PRIMARY IP
# ==============================
echo "[5] Setting primary IPv4 for device"

api -X PATCH \
  -d "{\"primary_ip4\": $IP_ID}" \
  "$NETBOX_URL/api/dcim/devices/$DEVICE_ID/" > /dev/null

echo "🎉 DONE! Device successfully created in NetBox."
echo "---------------------------------------------"
echo " Device Name : $DEVICE_NAME"
echo " Device ID   : $DEVICE_ID"
echo " Interface   : $IFNAME"
echo " InterfaceID : $INTERFACE_ID"
echo " IP Address  : $IPADDR (ID: $IP_ID)"
echo " Tag         : $TAG_NAME (ID: $TAG_ID)"
if [ -n "$SERIAL_NO" ]; then
  echo " Serial      : $SERIAL_NO"
else
  echo " Serial      : (none provided)"
fi
echo "---------------------------------------------"
