#!/bin/bash

# === CONFIGURATION ===
PIHOLE_URL="https://192.168.253.151"  # or use IP like https://192.168.253.151
PIHOLE_PASSWORD='admin$22'

# === Authenticate with Pi-hole ===
auth() {
  AUTH_RESPONSE=$(curl -sk -X POST "$PIHOLE_URL/api/auth" \
    -H "Content-Type: application/json" \
    --data "{\"password\":\"$PIHOLE_PASSWORD\"}")

  SID=$(echo "$AUTH_RESPONSE" | jq -r '.session.sid')
  CSRF=$(echo "$AUTH_RESPONSE" | jq -r '.session.csrf')

  if [[ "$SID" == "null" || "$CSRF" == "null" ]]; then
    echo "[!] Authentication failed"
    exit 1
  fi
}

# === Add DNS Entry ===
add_dns_entry() {
  HOSTNAME="$1"
  IP="$2"

  if [[ -z "$HOSTNAME" || -z "$IP" ]]; then
    echo "[!] Missing hostname or IP"
    exit 1
  fi

  echo "[+] Adding DNS entry: $HOSTNAME → $IP"

  curl -sk -X PUT "$PIHOLE_URL/api/config/dns/hosts/$IP%20$HOSTNAME" \
    -H "x-csrf-token: $CSRF" \
    -H "Cookie: sid=$SID" \
    -H "Content-Type: application/json"
}

# === Main ===
if [[ "$1" == "--add" ]]; then
  auth
  add_dns_entry "$2" "$3"
else
  echo "Usage: $0 --add <hostname> <ip>"
  exit 1
fi
