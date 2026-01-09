#!/bin/bash

USER="root"
PASS="Root@123"

if [ -z "$1" ]; then
  echo "Usage: $0 <server_ip>"
  exit 1
fi

SERVER=$1

sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no $USER@$SERVER << EOF
echo "SERVER: $SERVER"

echo "-----------------------------------------"
echo "Hostname:"
hostname
echo

echo "OS Release:"
cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"'
echo

echo "Kernel Version:"
uname -r
echo

echo "Interface | IP Address | MAC Address"
echo "------------------------------------"

ip -o -4 addr show up | awk '{print $2, $4}' | while read iface ip; do
    mac=$(cat /sys/class/net/$iface/address)
    printf "%s | %s | %s\n" "$iface" "$ip" "$mac"
done

echo "-----------------------------------------"

EOF
