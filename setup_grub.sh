#!/bin/bash

# --- CONFIGURATION ---
SSHPASSWORD="Root@123"  # Replace with your root password
IP_LIST="ips.txt"
SCRIPT_NAME="enable-verbose-boot.sh"

if [ ! -f "$IP_LIST" ]; then
    echo "Error: $IP_LIST not found."
    exit 1
fi

echo "==== Starting Parallel Deployment ===="

for ip in $(cat "$IP_LIST"); do
    echo "Processing $ip..."

    # 1. Copy the script to the remote server
    sshpass -p "$SSHPASSWORD" scp -o StrictHostKeyChecking=no "$SCRIPT_NAME" root@"$ip":/tmp/ >/dev/null 2>&1

    # 2. Execute the script and reboot in the background (&)
    # The -f flag in sshpass is used here to execute the command string
    sshpass -p "$SSHPASSWORD" ssh -o StrictHostKeyChecking=no root@"$ip" \
    "chmod +x /tmp/$SCRIPT_NAME && /tmp/$SCRIPT_NAME && reboot" & 

done

# Wait for all background processes to finish
wait

echo "------------------------------------------------"
echo "Done! All servers have been triggered to reboot."
echo "You can now open your PuTTY sessions to watch them start."
