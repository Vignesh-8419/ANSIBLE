#!/bin/bash

# NetBox API URL and token
NETBOX_URL="https://192.168.253.134/api"
TOKEN="6cc3f3c7bdd27d7ba032d5e65c73f58bf3ec3eb8"

# Site data
SITE_NAME="VGS"
SITE_SLUG="vgs"
SITE_STATUS="active"  # Use status ID or string if supported

# Create site via API
curl -X POST -k "$NETBOX_URL/dcim/sites/" \
  -H "Authorization: Token $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "'"$SITE_NAME"'",
    "slug": "'"$SITE_SLUG"'",
    "status": "'"$SITE_STATUS"'"
  }'
