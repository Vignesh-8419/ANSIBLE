#!/bin/bash

USER="root"
PASS="Root@123"
SERVER_FILE="servers.txt"
PARALLEL=20

if [ ! -f "$SERVER_FILE" ]; then
  echo "servers.txt not found!"
  exit 1
fi

while read -r SERVER; do
(
sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 $USER@$SERVER << 'EOF'
echo "-----------------------------------------"
echo "Hostname:"
hostname
echo

echo "OS Release:"
grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"'
echo

echo "Kernel Version:"
uname -r
echo

echo "Interface | IP Address | MAC Address"
echo "------------------------------------"

ip -o -4 addr show up | awk '{print $2, $4}' | while read iface ip; do
    mac=$(cat /sys/class/net/$iface/address 2>/dev/null)
    printf "%s | %s | %s\n" "$iface" "$ip" "$mac"
done
echo "-----------------------------------------"
EOF
) &
done < "$SERVER_FILE"

wait
