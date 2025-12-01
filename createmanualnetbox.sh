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
# 3. CHECK IF DEVICE EXISTS
# ==============================
EXISTING_DEVICE_JSON=$(api "$NETBOX_URL/api/dcim/devices/?name=$DEVICE_NAME&site_id=$SITE_ID")
EXISTING_DEVICE_ID=$(echo "$EXISTING_DEVICE_JSON" | jq '.results[0].id')

if [ "$EXISTING_DEVICE_ID" != "null" ] && [ -n "$EXISTING_DEVICE_ID" ]; then
  echo "ℹ️ Device already exists (ID: $EXISTING_DEVICE_ID). Updating instead of creating."

  # Build PATCH JSON
  if [ -n "$SERIAL_NO" ]; then
    DEVICE_PATCH="{
          \"name\": \"$DEVICE_NAME\",
          \"device_type\": $DEVICE_TYPE_ID,
          \"role\": $ROLE_ID,
          \"site\": $SITE_ID,
          \"status\": \"active\",
          \"tags\": [$TAG_ID],
          \"serial\": \"$SERIAL_NO\"
    }"
  else
    DEVICE_PATCH="{
          \"name\": \"$DEVICE_NAME\",
          \"device_type\": $DEVICE_TYPE_ID,
          \"role\": $ROLE_ID,
          \"site\": $SITE_ID,
          \"status\": \"active\",
          \"tags\": [$TAG_ID]
    }"
  fi

  api -X PATCH \
    -d "$DEVICE_PATCH" \
    "$NETBOX_URL/api/dcim/devices/$EXISTING_DEVICE_ID/" > /dev/null

  DEVICE_ID=$EXISTING_DEVICE_ID
else
  # ==============================
  # 4. CREATE NEW DEVICE
  # ==============================
  echo "[2] Creating device: $DEVICE_NAME"

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
fi


# ==============================
# 5. DELETE OLD INTERFACE IF EXISTS
# ==============================
EXISTING_IF_JSON=$(api "$NETBOX_URL/api/dcim/interfaces/?device_id=$DEVICE_ID&name=$IFNAME")
EXISTING_IF_ID=$(echo "$EXISTING_IF_JSON" | jq '.results[0].id')

if [ "$EXISTING_IF_ID" != "null" ] && [ -n "$EXISTING_IF_ID" ]; then
  echo "ℹ️ Interface exists (ID: $EXISTING_IF_ID). Deleting old interface."

  api -X DELETE "$NETBOX_URL/api/dcim/interfaces/$EXISTING_IF_ID/" > /dev/null
fi


# ==============================
# 6. CREATE NEW INTERFACE
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

echo "➡️ Interface ID = $INTERFACE_ID"


# ==============================
# 7. DELETE EXISTING IP ASSIGNMENTS
# ==============================
EXISTING_IP_JSON=$(api "$NETBOX_URL/api/ipam/ip-addresses/?assigned_object_id=$INTERFACE_ID")
EXISTING_IP_ID=$(echo "$EXISTING_IP_JSON" | jq '.results[0].id')

if [ "$EXISTING_IP_ID" != "null" ] && [ -n "$EXISTING_IP_ID" ]; then
  echo "ℹ️ Removing old IP assignment (ID: $EXISTING_IP_ID)."

  api -X DELETE "$NETBOX_URL/api/ipam/ip-addresses/$EXISTING_IP_ID/" > /dev/null
fi


# ==============================
# 8. CREATE IP ADDRESS
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

echo "➡️ IP ID = $IP_ID"


# ==============================
# 9. SET PRIMARY IP
# ==============================
echo "[5] Setting primary IPv4 for device"

api -X PATCH \
  -d "{\"primary_ip4\": $IP_ID}" \
  "$NETBOX_URL/api/dcim/devices/$DEVICE_ID/" > /dev/null

echo "🎉 DONE! Device created/updated successfully in NetBox."
