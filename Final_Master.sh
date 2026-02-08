#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'

echo "=========================================================="
echo "STEP 1: NUCLEAR HARDWARE REBUILD"
echo "=========================================================="

sshpass -p "$ESXI_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ESXI_IP << 'EOF'
    # Get all VM IDs
    IDS=$(vim-cmd vmsvc/getallvms 2>/dev/null | awk 'NR>1 {print $1}' | grep -E '^[0-9]+$')
    
    for VMID in $IDS; do
        VMNAME=$(vim-cmd vmsvc/getallvms | awk -v id="$VMID" '$1==id {print $2}')
        [ -z "$VMNAME" ] || [ "$VMNAME" == "dns-server-01" ] && continue

        VMX_PATH=$(find /vmfs/volumes/ -name "${VMNAME}.vmx" | head -n 1)
        [ -z "$VMX_PATH" ] && continue

        echo "--- Force Rebuilding: $VMNAME ---"
        
        # 1. Kill the VM process immediately (The Nuclear Option)
        WORLD_ID=$(localcli vm process list | grep -A 1 "$VMNAME" | grep "World ID" | awk '{print $3}')
        if [ ! -z "$WORLD_ID" ]; then
            localcli vm process kill --type=force --world-id=$WORLD_ID
            sleep 2
        fi

        # 2. Strip and Re-inject hardware
        sed -i '/serial0/d' "$VMX_PATH"
        VM_PORT=$((2000 + $VMID))
        cat <<EOL >> "$VMX_PATH"
serial0.present = "TRUE"
serial0.yieldOnPoll = "TRUE"
serial0.fileType = "network"
serial0.fileName = "telnet://:$VM_PORT"
serial0.network.endPoint = "server"
EOL
        
        # 3. Reload inventory and Power On
        vim-cmd vmsvc/reload $VMID
        sleep 2
        vim-cmd vmsvc/power.on $VMID
        echo "  -> Started on Port: $VM_PORT"
    done
EOF

echo "=========================================================="
echo "STEP 2: FINAL OS SYNC"
echo "=========================================================="

export SSHPASS="$VM_PASS"
SSH_OPTS="-n -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

for VMNAME in ipa-server-01 ansible-server-01 rocky-08-02 http-server-01 cert-server-01 cent-07-01 cent-07-02 tftp-server-01 tftp-server-02; do
    VMIP=$(nslookup "$VMNAME" | grep -A 1 "Name:" | grep "Address" | awk '{print $2}' | head -n 1)
    if [ ! -z "$VMIP" ]; then
        echo "Final reboot for $VMNAME..."
        # Wait for SSH to be up after the hard kill
        until timeout 1 bash -c "</dev/tcp/$VMIP/22" 2>/dev/null; do echo -n "."; sleep 2; done
        sshpass -e ssh $SSH_OPTS root@"$VMIP" "reboot" &
    fi
done

wait
echo "--- SYSTEM RECOVERED AND CONFIGURED ---"
