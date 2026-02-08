#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'
GITHUB_URL="https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/enable-verbose-boot.sh"

echo "=========================================================="
echo "STEP 1: HARDWARE AUDIT (CLEANED)"
echo "=========================================================="

wget -q "$GITHUB_URL" -O enable-verbose-boot.sh || true
chmod +x enable-verbose-boot.sh

TMP_DATA="/tmp/vm_audit.txt"
> $TMP_DATA

# Fetch ONLY valid VMs. Grep -v handles the "Skipping invalid VM" noise.
sshpass -p "$ESXI_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ESXI_IP << 'EOF' > $TMP_DATA
    # Get IDs of VMs that are NOT invalid
    IDS=$(vim-cmd vmsvc/getallvms 2>/dev/null | awk 'NR>1 {print $1}' | grep -E '^[0-9]+$')
    
    for VMID in $IDS; do
        VMNAME=$(vim-cmd vmsvc/getallvms | awk -v id="$VMID" '$1==id {print $2}')
        [ -z "$VMNAME" ] || [ "$VMNAME" == "dns-server-01" ] && continue

        VMX_PATH=$(find /vmfs/volumes/ -name "${VMNAME}.vmx" | head -n 1)
        [ -z "$VMX_PATH" ] && continue

        if ! grep -q "serial0.present" "$VMX_PATH"; then
            STATE=$(vim-cmd vmsvc/power.getstate $VMID | grep -v "Retrieved")
            if [[ "$STATE" == *"Powered on"* ]]; then
                vim-cmd vmsvc/power.off $VMID > /dev/null
                sleep 3
            fi

            VM_PORT=$((2000 + $VMID))
            printf "serial0.present = \"TRUE\"\nserial0.yieldOnPoll = \"TRUE\"\nserial0.fileType = \"network\"\nserial0.fileName = \"telnet://:$VM_PORT\"\nserial0.network.endPoint = \"server\"\n" >> "$VMX_PATH"
            
            vim-cmd vmsvc/reload $VMID > /dev/null
            sleep 2
            vim-cmd vmsvc/power.on $VMID > /dev/null
            echo "$VMNAME|FIXED"
        else
            echo "$VMNAME|EXISTS"
        fi
    done
EOF

echo "=========================================================="
echo "STEP 2: GUEST OS CONFIGURATION"
echo "=========================================================="

export SSHPASS="$VM_PASS"
SSH_OPTS="-n -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15"

while IFS='|' read -u 3 -r VMNAME STATUS; do
    [ -z "$VMNAME" ] && continue
    
    VMIP=$(nslookup "$VMNAME" | grep -A 1 "Name:" | grep "Address" | awk '{print $2}' | head -n 1)
    [ -z "$VMIP" ] && continue

    echo "--- Analyzing $VMNAME ($VMIP) ---"

    if [ "$STATUS" == "FIXED" ]; then
        echo "  -> VM was rebooted for Hardware. Waiting for SSH..."
        until timeout 1 bash -c "</dev/tcp/$VMIP/22" 2>/dev/null; do echo -n "."; sleep 3; done
        echo " Connected!"
    fi
    
    ALREADY_DONE=$(sshpass -e ssh $SSH_OPTS root@"$VMIP" "grep 'console=ttyS0' /etc/default/grub" 2>/dev/null)
    
    if [ "$STATUS" == "FIXED" ] || [ -z "$ALREADY_DONE" ]; then
        echo "  -> Applying Verbose Boot..."
        sshpass -e scp $SSH_OPTS enable-verbose-boot.sh root@"$VMIP":/tmp/
        sshpass -e ssh $SSH_OPTS root@"$VMIP" "chmod +x /tmp/enable-verbose-boot.sh && /tmp/enable-verbose-boot.sh && reboot" &
    else
        echo "  -> [OK] Already configured."
    fi

done 3< $TMP_DATA

wait
rm -f $TMP_DATA
echo "=========================================================="
echo "ALL VALID VMS SYNCHRONIZED"
echo "=========================================================="
