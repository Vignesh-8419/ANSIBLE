#!/bin/bash

# NetBox API details
NETBOX_URL="http://192.168.253.134"
TOKEN="ee63f94d72c6c10a5b4e2cab4edbea9af0f18ac0"

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

# Create device
DEVICE_RESPONSE=$(curl -s -X POST "$NETBOX_URL/api/dcim/devices/" \
  -H "Authorization: Token $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"$DEVICE_NAME\", \"device_type\": 1, \"device_role\": 1, \"site\": 1, \"status\": \"active\", \"tags\": [\"$TAG_NAME\"]}")

DEVICE_ID=$(echo "$DEVICE_RESPONSE" | grep -o '"id":[0-9]*' | cut -d: -f2)

# Create interface
INTERFACE_RESPONSE=$(curl -s -X POST "$NETBOX_URL/api/dcim/interfaces/" \
  -H "Authorization: Token $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"device\": $DEVICE_ID, \"name\": \"$INTERFACE_NAME\", \"type\": \"1000base-t\", \"mac_address\": \"$MAC_ADDRESS\"}")

INTERFACE_ID=$(echo "$INTERFACE_RESPONSE" | grep -o '"id":[0-9]*' | cut -d: -f2)

# Assign IP address
curl -s -X POST "$NETBOX_URL/api/ipam/ip-addresses/" \
  -H "Authorization: Token $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"address\": \"$IP_ADDRESS\", \"status\": \"active\", \"assigned_object_type\": \"dcim.interface\", \"assigned_object_id\": $INTERFACE_ID}" > /dev/null

echo "✅ Device '$DEVICE_NAME' created with IP $IP_ADDRESS and MAC $MAC_ADDRESS"
