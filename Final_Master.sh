#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'
GITHUB_URL="https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/enable-verbose-boot.sh"

echo "=========================================================="
echo "STEP 1: HARDWARE AUDIT (IRONCLAD POWER MANAGEMENT)"
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
            echo "Repairing $VMNAME..." >&2
            
            # 1. FORCE POWER OFF
            # Using power.off usually works, but if it's stuck, we try a hard stop
            vim-cmd vmsvc/power.off $VMID > /dev/null 2>&1
            
            # Wait loop: Check state until it is definitely Off
            COUNT=0
            while [ $COUNT -lt 15 ]; do
                CURRENT_STATE=$(vim-cmd vmsvc/power.getstate $VMID | tail -1)
                if [[ "$CURRENT_STATE" == *"Powered off"* ]]; then
                    break
                fi
                sleep 2
                let COUNT=COUNT+1
            done

            # 2. Inject Serial Config
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
            sleep 3
            # Try to power on; if it fails, wait and try once more
            if ! vim-cmd vmsvc/power.on $VMID > /dev/null 2>&1; then
                sleep 5
                vim-cmd vmsvc/power.on $VMID > /dev/null 2>&1
            fi
            
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
        echo "  -> Waiting for SSH port 22..."
        # Give it a long timeout to boot
        until timeout 1 bash -c "</dev/tcp/$VMIP/22" 2>/dev/null; do 
            echo -n "."
            sleep 4
        done
        echo " Connected!"
    fi
    
    ALREADY_DONE=$(sshpass -e ssh $SSH_OPTS root@"$VMIP" "grep 'console=ttyS0' /etc/default/grub" 2>/dev/null)
    
    if [ "$STATUS" == "FIXED" ] || [ -z "$ALREADY_DONE" ]; then
        echo "  -> Deploying Serial Console Config..."
        sshpass -e scp $SSH_OPTS enable-verbose-boot.sh root@"$VMIP":/tmp/
        sshpass -e ssh $SSH_OPTS root@"$VMIP" "chmod +x /tmp/enable-verbose-boot.sh && /tmp/enable-verbose-boot.sh && reboot" &
    else
        echo "  -> [OK] Already configured."
    fi
done 3< $TMP_DATA

wait
rm -f $TMP_DATA
echo "--- ALL TASKS COMPLETE ---"
