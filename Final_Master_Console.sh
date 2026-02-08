#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'

# --- NEW: GENERATE THE LOCAL GRUB SCRIPT WITH YOUR EXACT CONFIG ---
cat << 'EOF' > enable-verbose-boot.sh
#!/bin/bash
# Detect OS Version
EL_VERSION=$(grep -oE '[0-9]' /etc/redhat-release | head -1)

# 1. Update /etc/default/grub with your exact requested config
cat << 'EOG' > /etc/default/grub
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200 crashkernel=auto resume=/dev/mapper/rl-swap rd.lvm.lv=rl/root rd.lvm.lv=rl/swap "
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
GRUB_TIMEOUT=10
GRUB_TERMINAL="serial console"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
EOG

# 2. Regenerate GRUB config based on EL Version
if [ "$EL_VERSION" -eq "7" ]; then
    grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
else
    # Rocky / CentOS 8/9
    grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg
fi
EOF

chmod +x enable-verbose-boot.sh

echo "=========================================================="
echo "STEP 1: SMART HARDWARE AUDIT"
echo "=========================================================="

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

    # Check and Fix GRUB - Looking for your specific serial input config
    GRUB_CHECK=$(sshpass -e ssh $SSH_OPTS root@"$VMIP" "grep 'GRUB_TERMINAL=\"serial console\"' /etc/default/grub" 2>/dev/null)

    if [ -z "$GRUB_CHECK" ]; then
        echo "  -> [!] GRUB Config missing or incorrect. Applying your exact config..."
        sshpass -e scp $SCP_OPTS enable-verbose-boot.sh root@"$VMIP":/tmp/
        sshpass -e ssh $SSH_OPTS root@"$VMIP" "chmod +x /tmp/enable-verbose-boot.sh && /tmp/enable-verbose-boot.sh && reboot" &
    else
        echo "  -> [OK] GRUB matches your requested configuration."
    fi
done

wait
echo "=========================================================="
echo "AUDIT COMPLETE"
echo "=========================================================="
