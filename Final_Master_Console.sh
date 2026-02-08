#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'
GITHUB_URL="https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/enable-verbose-boot.sh"

echo "=========================================================="
echo "STEP 1: SMART HARDWARE AUDIT"
echo "=========================================================="

wget -q "$GITHUB_URL" -O enable-verbose-boot.sh || true
chmod +x enable-verbose-boot.sh

sshpass -p "$ESXI_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ESXI_IP << 'EOF'
    IDS=$(vim-cmd vmsvc/getallvms 2>/dev/null | awk 'NR>1 {print $1}' | grep -E '^[0-9]+$')
    
    for VMID in $IDS; do
        VMNAME=$(vim-cmd vmsvc/getallvms | awk -v id="$VMID" '$1==id {print $2}')
        [ -z "$VMNAME" ] || [ "$VMNAME" == "dns-server-01" ] && continue

        VMX_PATH=$(find /vmfs/volumes/ -name "${VMNAME}.vmx" | head -n 1)
        [ -z "$VMX_PATH" ] && continue

        if grep -q "serial0.present = \"TRUE\"" "$VMX_PATH" && grep -q "serial0.fileType = \"network\"" "$VMX_PATH"; then
            echo "[OK] Hardware exists for $VMNAME."
        else
            echo "[!] Fixing Hardware for $VMNAME..." >&2
            WID=$(localcli vm process list | grep -A 1 "$VMNAME" | grep "World ID" | awk '{print $3}')
            [ ! -z "$WID" ] && localcli vm process kill --type=force --world-id=$WID && sleep 2
            
            sed -i '/serial0/d' "$VMX_PATH"
            VPORT=$((2000 + $VMID))
            cat <<EOL >> "$VMX_PATH"
serial0.present = "TRUE"
serial0.yieldOnPoll = "TRUE"
serial0.fileType = "network"
serial0.fileName = "telnet://:$VPORT"
serial0.network.endPoint = "server"
EOL
            vim-cmd vmsvc/reload $VMID
            sleep 1
            vim-cmd vmsvc/power.on $VMID
        fi
    done
EOF

echo "=========================================================="
echo "STEP 2: SMART GUEST OS (GRUB) AUDIT"
echo "=========================================================="

export SSHPASS="$VM_PASS"
SSH_OPTS="-n -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
SCP_OPTS="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

VMLIST="ipa-server-01 ansible-server-01 rocky-08-02 http-server-01 cert-server-01 cent-07-01 cent-07-02 tftp-server-01 tftp-server-02"

for VMNAME in $VMLIST; do
    VMIP=$(nslookup "$VMNAME" | grep -A 1 "Name:" | grep "Address" | awk '{print $2}' | head -n 1)
    [ -z "$VMIP" ] && continue

    echo "--- Analyzing $VMNAME ($VMIP) ---"
    
    # NEW: Patient Wait Loop
    echo -n "  -> Waiting for SSH service to start..."
    COUNT=0
    until timeout 1 bash -c "</dev/tcp/$VMIP/22" 2>/dev/null || [ $COUNT -eq 30 ]; do
        echo -n "."
        sleep 5
        ((COUNT++))
    done

    if ! timeout 1 bash -c "</dev/tcp/$VMIP/22" 2>/dev/null; then
        echo " FAILED (Timed out after 2.5 mins)."
        continue
    else
        echo " ONLINE."
    fi

    # Check and Fix GRUB
    GRUB_CHECK=$(sshpass -e ssh $SSH_OPTS root@"$VMIP" "grep 'console=ttyS0' /etc/default/grub" 2>/dev/null)

    if [ -z "$GRUB_CHECK" ]; then
        echo "  -> [!] GRUB Config missing. Applying..."
        sshpass -e scp $SCP_OPTS enable-verbose-boot.sh root@"$VMIP":/tmp/
        sshpass -e ssh $SSH_OPTS root@"$VMIP" "chmod +x /tmp/enable-verbose-boot.sh && /tmp/enable-verbose-boot.sh && reboot" &
    else
        echo "  -> [OK] GRUB already configured."
    fi
done

wait
echo "=========================================================="
echo "AUDIT COMPLETE"
echo "=========================================================="
