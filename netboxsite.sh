#!/bin/bash

# NetBox API URL and token
NETBOX_URL="http://192.168.253.134/api"
TOKEN="ee63f94d72c6c10a5b4e2cab4edbea9af0f18ac0"

# Site data
SITE_NAME="VGS"
SITE_SLUG="vgs"
SITE_STATUS="active"  # Use status ID or string if supported

# Create site via API
curl -X POST "$NETBOX_URL/dcim/sites/" \
  -H "Authorization: Token $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"$SITE_NAME"'",
    "slug": "'"$SITE_SLUG"'",
    "status": "'"$SITE_STATUS"'"
  }'
