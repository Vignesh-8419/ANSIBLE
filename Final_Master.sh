#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'
GITHUB_URL="https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/enable-verbose-boot.sh"

echo "=========================================================="
echo "STEP 1: HARDWARE AUDIT (SERIAL PORT INJECTION)"
echo "=========================================================="

# Ensure the local script exists for Step 2
wget -q "$GITHUB_URL" -O enable-verbose-boot.sh || true
chmod +x enable-verbose-boot.sh

TMP_DATA="/tmp/vm_audit.txt"
> $TMP_DATA

# Fetch ONLY valid VMs and modify hardware on ESXi
sshpass -p "$ESXI_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ESXI_IP << 'EOF' > $TMP_DATA
    # Get IDs of VMs that are numeric and NOT invalid
    IDS=$(vim-cmd vmsvc/getallvms 2>/dev/null | awk 'NR>1 {print $1}' | grep -E '^[0-9]+$')
    
    for VMID in $IDS; do
        VMNAME=$(vim-cmd vmsvc/getallvms | awk -v id="$VMID" '$1==id {print $2}')
        # Skip current DNS server
        [ -z "$VMNAME" ] || [ "$VMNAME" == "dns-server-01" ] && continue

        VMX_PATH=$(find /vmfs/volumes/ -name "${VMNAME}.vmx" | head -n 1)
        [ -z "$VMX_PATH" ] && continue

        # Check if hardware is missing
        if ! grep -q "serial0.present" "$VMX_PATH"; then
            echo "Modifying Hardware for $VMNAME..." >&2
            
            # 1. Power off if it is running
            STATE=$(vim-cmd vmsvc/power.getstate $VMID | grep -v "Retrieved")
            if [[ "$STATE" == *"Powered on"* ]]; then
                vim-cmd vmsvc/power.off $VMID > /dev/null
                sleep 5
            fi

            # 2. Inject Serial Config (Clean block)
            VM_PORT=$((2000 + $VMID))
            cat <<EOL >> "$VMX_PATH"
serial0.present = "TRUE"
serial0.yieldOnPoll = "TRUE"
serial0.fileType = "network"
serial0.fileName = "telnet://:$VM_PORT"
serial0.network.endPoint = "server"
EOL
            
            # 3. Reload and Power back on
            vim-cmd vmsvc/reload $VMID > /dev/null
            sleep 5
            vim-cmd vmsvc/power.on $VMID > /dev/null
            echo "$VMNAME|FIXED"
        else
            echo "$VMNAME|EXISTS"
        fi
    done
EOF

echo "=========================================================="
echo "STEP 2: GUEST OS CONFIGURATION (SSH DEPLOYMENT)"
echo "=========================================================="

export SSHPASS="$VM_PASS"
SSH_OPTS="-n -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15"

while IFS='|' read -u 3 -r VMNAME STATUS; do
    [ -z "$VMNAME" ] && continue
    
    # Resolve IP
    VMIP=$(nslookup "$VMNAME" | grep -A 1 "Name:" | grep "Address" | awk '{print $2}' | head -n 1)
    [ -z "$VMIP" ] && continue

    echo "--- Analyzing $VMNAME ($VMIP) ---"

    # If the VM was just power-cycled, we must wait for SSH port 22
    if [ "$STATUS" == "FIXED" ]; then
        echo "  -> Waiting for VM to boot up..."
        until timeout 1 bash -c "</dev/tcp/$VMIP/22" 2>/dev/null; do 
            echo -n "."
            sleep 3
        done
        echo " Connected!"
    fi
    
    # Check if the GRUB change is already there
    ALREADY_DONE=$(sshpass -e ssh $SSH_OPTS root@"$VMIP" "grep 'console=ttyS0' /etc/default/grub" 2>/dev/null)
    
    if [ "$STATUS" == "FIXED" ] || [ -z "$ALREADY_DONE" ]; then
        echo "  -> Applying Verbose Boot script..."
        sshpass -e scp $SSH_OPTS enable-verbose-boot.sh root@"$VMIP":/tmp/
        sshpass -e ssh $SSH_OPTS root@"$VMIP" "chmod +x /tmp/enable-verbose-boot.sh && /tmp/enable-verbose-boot.sh && reboot" &
    else
        echo "  -> [OK] Guest OS already configured."
    fi

done 3< $TMP_DATA

wait
rm -f $TMP_DATA
echo "--- ALL VALID VMS SYNCHRONIZED AND REBOOTING ---"
