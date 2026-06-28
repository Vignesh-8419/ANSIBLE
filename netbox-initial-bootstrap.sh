#!/bin/bash
###############################################################################
# NetBox Bootstrap Script
#
# Description:
#   Creates required NetBox DCIM objects
#     - Device Role
#     - Manufacturer
#     - Device Type
#     - Site
#
# Author  : VGS
# Version : 1.0
###############################################################################

set -euo pipefail

###############################################
# Configuration
###############################################

NETBOX_URL="https://192.168.253.143/api"
NETBOX_TOKEN="83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd"

HEADER_AUTH="Authorization: Token ${NETBOX_TOKEN}"
HEADER_JSON="Content-Type: application/json"

echo "======================================================"
echo "        NetBox DCIM Bootstrap"
echo "======================================================"
echo

###############################################
# Function
###############################################

create_if_missing() {

    local NAME="$1"
    local SEARCH_URL="$2"
    local CREATE_URL="$3"
    local PAYLOAD="$4"

    echo "Checking ${NAME}..."

    ID=$(curl -sk \
        -H "$HEADER_AUTH" \
        "$SEARCH_URL" | jq -r '.results[0].id // empty')

    if [[ -n "$ID" ]]; then
        echo "✔ ${NAME} already exists (ID: ${ID})"
    else
        echo "Creating ${NAME}..."

        curl -sk -X POST \
            "$CREATE_URL" \
            -H "$HEADER_AUTH" \
            -H "$HEADER_JSON" \
            -d "$PAYLOAD" >/dev/null

        echo "✔ ${NAME} created."
    fi

    echo
}

###############################################
# Step 1 - Device Role
###############################################

create_if_missing \
"Device Role: Server" \
"$NETBOX_URL/dcim/device-roles/?name=Server" \
"$NETBOX_URL/dcim/device-roles/" \
'{
  "name":"Server",
  "slug":"server"
}'

###############################################
# Step 2 - Manufacturer
###############################################

create_if_missing \
"Manufacturer: Generic" \
"$NETBOX_URL/dcim/manufacturers/?name=Generic" \
"$NETBOX_URL/dcim/manufacturers/" \
'{
  "name":"Generic",
  "slug":"generic"
}'

###############################################
# Get Manufacturer ID
###############################################

MANUFACTURER_ID=$(curl -sk \
-H "$HEADER_AUTH" \
"$NETBOX_URL/dcim/manufacturers/?name=Generic" | jq -r '.results[0].id')

###############################################
# Step 3 - Device Type
###############################################

DEVICE_TYPE_EXISTS=$(curl -sk \
-H "$HEADER_AUTH" \
"$NETBOX_URL/dcim/device-types/?model=Generic%20x86%20Server" | jq -r '.results[0].id // empty')

if [[ -n "$DEVICE_TYPE_EXISTS" ]]; then

    echo "✔ Device Type already exists (ID: ${DEVICE_TYPE_EXISTS})"

else

    echo "Creating Device Type..."

    curl -sk -X POST \
        "$NETBOX_URL/dcim/device-types/" \
        -H "$HEADER_AUTH" \
        -H "$HEADER_JSON" \
        -d "{
            \"manufacturer\": ${MANUFACTURER_ID},
            \"model\":\"Generic x86 Server\",
            \"slug\":\"generic-x86-server\"
        }" >/dev/null

    echo "✔ Device Type created."

fi

echo

###############################################
# Step 4 - Site
###############################################

create_if_missing \
"Site: VGS" \
"$NETBOX_URL/dcim/sites/?name=VGS" \
"$NETBOX_URL/dcim/sites/" \
'{
  "name":"VGS",
  "slug":"vgs",
  "status":"active"
}'

echo
echo "======================================================"
echo "Bootstrap completed successfully."
echo "======================================================"
