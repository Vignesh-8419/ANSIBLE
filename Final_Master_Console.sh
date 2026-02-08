#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'

# --- GENERATE THE LOCAL GRUB SCRIPT ---
# This script handles the OS-specific differences between CentOS 7 and Rocky 8/9
cat << 'EOF' > enable-verbose-boot.sh
#!/bin/bash

# Detect OS Version
IS_CENTOS7=$(grep -q "release 7" /etc/redhat-release && echo "true" || echo "false")

if [ "$IS_CENTOS7" == "true" ]; then
    echo "Configuring for CentOS 7..."
    cat << 'EOG' > /etc/default/grub
GRUB_TIMEOUT=10
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL="serial console"
GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200 crashkernel=auto rd.lvm.lv=centos/root rd.lvm.lv=centos/swap console=tty0"
GRUB_DISABLE_RECOVERY="true"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
EOG
    # Target CentOS 7 EFI Path
    grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
else
    echo "Configuring for Rocky / EL8+..."
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
    # Target Rocky EFI Path
    grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg
fi
EOF

chmod +x enable-verbose-boot.sh

echo "=========================================================="
echo "STEP 1: SMART HARDWARE AUDIT (ESXi)"
echo "=========================================================="

sshpass -p "$ESXI_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ESXI_IP << 'EOF'
    IDS=$(vim-cmd vmsvc/getallvms 2>/dev/null | awk 'NR>1 {print $1}' | grep -E '^[0-9]+$')
    
    for VMID in $IDS; do
        VMNAME=$(vim-cmd vmsvc/getallvms | awk -v id="$VMID" '$1==id {print $2}')
        [ -z "$VMNAME" ] || [ "$VMNAME" == "dns-server-01" ] && continue

        VMX_PATH=$(find /vmfs/volumes/ -name "${VMNAME}.vmx" | head -n 1)
        [ -z "$VMX_PATH" ] && continue

        if grep -q "serial0.present = \"TRUE\"" "$VMX_PATH" && grep -q "serial0.yieldOnPoll = \"TRUE\"" "$VMX_PATH"; then
            echo "[OK] Hardware exists and configured for $VMNAME."
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
    
    echo -n "  -> Waiting for SSH..."
    COUNT=0
    until timeout 1 bash -c "</dev/tcp/$VMIP/22" 2>/dev/null || [ $COUNT -eq 30 ]; do
        echo -n "."
        sleep 5
        ((COUNT++))
    done

    if ! timeout 1 bash -c "</dev/tcp/$VMIP/22" 2>/dev/null; then
        echo " OFFLINE."
        continue
    else
        echo " ONLINE."
    fi

    # Audit for your specific GRUB_TERMINAL requirement
    GRUB_CHECK=$(sshpass -e ssh $SSH_OPTS root@"$VMIP" "grep '^GRUB_TERMINAL=\"serial console\"' /etc/default/grub" 2>/dev/null)

    if [ -z "$GRUB_CHECK" ]; then
        echo "  -> [!] Updating GRUB Config to 'serial console'..."
        sshpass -e scp $SCP_OPTS enable-verbose-boot.sh root@"$VMIP":/tmp/
        sshpass -e ssh $SSH_OPTS root@"$VMIP" "chmod +x /tmp/enable-verbose-boot.sh && /tmp/enable-verbose-boot.sh && reboot" &
    else
        echo "  -> [OK] GRUB already matches requested configuration."
    fi
done

wait
echo "=========================================================="
echo "AUDIT COMPLETE"
echo "=========================================================="
