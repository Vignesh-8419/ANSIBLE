#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'
GITHUB_URL="https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/enable-verbose-boot.sh"

echo "=========================================================="
echo "STEP 1: HARDWARE AUDIT"
echo "=========================================================="

wget -q "$GITHUB_URL" -O enable-verbose-boot.sh || true
chmod +x enable-verbose-boot.sh

TMP_DATA="/tmp/vm_audit.txt"
> $TMP_DATA

sshpass -p "$ESXI_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ESXI_IP << 'EOF' > $TMP_DATA
    IDS=$(vim-cmd vmsvc/getallvms 2>/dev/null | awk 'NR>1 {print $1}' | grep -E '^[0-9]+$')
    
    for VMID in $IDS; do
        VMNAME=$(vim-cmd vmsvc/getallvms | awk -v id="$VMID" '$1==id {print $2}')
        [ -z "$VMNAME" ] || [ "$VMNAME" == "dns-server-01" ] && continue

        VMX_PATH=$(find /vmfs/volumes/ -name "${VMNAME}.vmx" | head -n 1)
        [ -z "$VMX_PATH" ] && continue

        if ! grep -q "serial0.present" "$VMX_PATH"; then
            echo "Repairing Hardware for $VMNAME..." >&2
            vim-cmd vmsvc/power.off $VMID > /dev/null 2>&1
            
            # Wait for off
            while [[ "$(vim-cmd vmsvc/power.getstate $VMID | tail -1)" != *"Powered off"* ]]; do sleep 2; done

            VM_PORT=$((2000 + $VMID))
            cat <<EOL >> "$VMX_PATH"
serial0.present = "TRUE"
serial0.yieldOnPoll = "TRUE"
serial0.fileType = "network"
serial0.fileName = "telnet://:$VM_PORT"
serial0.network.endPoint = "server"
EOL
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
# Note: Removed -n from SCP_OPTS
SSH_OPTS="-n -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15"
SCP_OPTS="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15"

while IFS='|' read -u 3 -r VMNAME STATUS; do
    [ -z "$VMNAME" ] && continue
    VMIP=$(nslookup "$VMNAME" | grep -A 1 "Name:" | grep "Address" | awk '{print $2}' | head -n 1)
    [ -z "$VMIP" ] && continue

    echo "--- Analyzing $VMNAME ($VMIP) ---"

    # Strict check: Does the grub file actually have the serial console AND is it the active config?
    # If this fails, we force a re-run.
    NEEDS_OS_FIX=$(sshpass -e ssh $SSH_OPTS root@"$VMIP" "grep 'console=ttyS0' /etc/default/grub && stat /boot/grub2/grub.cfg" 2>/dev/null)

    if [ -z "$NEEDS_OS_FIX" ] || [ "$STATUS" == "FIXED" ]; then
        echo "  -> Configuring Guest OS..."
        
        # Ensure SSH is up before SCP
        until timeout 1 bash -c "</dev/tcp/$VMIP/22" 2>/dev/null; do echo -n "."; sleep 3; done
        
        sshpass -e scp $SCP_OPTS enable-verbose-boot.sh root@"$VMIP":/tmp/
        sshpass -e ssh $SSH_OPTS root@"$VMIP" "chmod +x /tmp/enable-verbose-boot.sh && /tmp/enable-verbose-boot.sh && reboot" &
        echo "  -> Update triggered and rebooting."
    else
        echo "  -> [OK] Already fully configured."
    fi
done 3< $TMP_DATA

wait
rm -f $TMP_DATA
echo "=========================================================="
echo "ALL SERVERS ARE NOW SYNCHRONIZED"
echo "=========================================================="
