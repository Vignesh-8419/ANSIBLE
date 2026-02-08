#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'
MY_NAME="dns-server-01"
GITHUB_URL="https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/enable-verbose-boot.sh"

# Get local IPs
MY_IPS=$(hostname -I)

echo "=========================================================="
echo "STEP 1: CONFIGURING ESXi HARDWARE & RESOLVING IPs"
echo "=========================================================="

wget -q "$GITHUB_URL" -O enable-verbose-boot.sh || true
chmod +x enable-verbose-boot.sh

TMP_VMS="/tmp/vm_list.txt"
> $TMP_VMS

# Fetch VM names from ESXi
sshpass -p "$ESXI_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ESXI_IP << 'EOF' > $TMP_VMS
    IDS=$(vim-cmd vmsvc/getallvms | awk 'NR>1 {print $1}')
    for VMID in $IDS; do
        VMNAME=$(vim-cmd vmsvc/getallvms | awk -v id="$VMID" '$1==id {print $2}')
        [ "$VMNAME" == "dns-server-01" ] && continue
        echo "$VMNAME"
    done
EOF

echo "=========================================================="
echo "STEP 2: SMART GUEST OS UPDATE"
echo "=========================================================="

# ADDED -t -t to force a TTY allocation
# ADDED -o BatchMode=no to ensure it doesn't try to fail fast without a password
SSH_BASE_OPTS="-t -t -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15 -o BatchMode=no"

while read -u 3 -r VMNAME; do
    [ -z "$VMNAME" ] && continue
    
    VMIP=$(nslookup "$VMNAME" | grep -A 1 "Name:" | grep "Address" | awk '{print $2}' | head -n 1)
    [ -z "$VMIP" ] && continue
    [[ $MY_IPS =~ $VMIP ]] && continue

    echo "--- Analyzing $VMNAME ($VMIP) ---"
    
    # Check if console is already configured
    # We use sshpass -p here to keep it simple and direct
    ALREADY_DONE=$(sshpass -p "$VM_PASS" ssh $SSH_BASE_OPTS root@"$VMIP" "grep 'console=ttyS0' /etc/default/grub" 2>/dev/null)
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ] && [ -n "$ALREADY_DONE" ]; then
        echo "  -> [OK] Serial console already active. Skipping."
    elif [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 1 ]; then
        # If grep fails (Code 1 from grep, but 0 from SSH), it means config is missing
        if [[ "$ALREADY_DONE" != *"console=ttyS0"* ]]; then
            echo "  -> Config missing. Updating $VMNAME..."
            sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null enable-verbose-boot.sh root@"$VMIP":/tmp/ >/dev/null 2>&1
            sshpass -p "$VM_PASS" ssh $SSH_BASE_OPTS root@"$VMIP" "chmod +x /tmp/enable-verbose-boot.sh && /tmp/enable-verbose-boot.sh && reboot" &
        fi
    else
        echo "  -> [ERROR] SSH failed (Code $EXIT_CODE). Manual check: sshpass -p '$VM_PASS' ssh $VMIP"
    fi

    sleep 1

done 3< $TMP_VMS

wait
rm -f $TMP_VMS
echo "=========================================================="
echo "DEPLOYMENT COMPLETE"
echo "=========================================================="
