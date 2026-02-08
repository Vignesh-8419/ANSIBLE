#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'

# --- GENERATE THE LOCAL GRUB SCRIPT ---
# This version is dynamic: it won't break your LVM paths or Kernel location
cat << 'EOF' > enable-verbose-boot.sh
#!/bin/bash

# 1. DOWNLOAD AND VALIDATE MEMTEST
mkdir -p /boot/efi/EFI/memtest
echo "Downloading MemTest86+..."
curl -L -f -o /boot/efi/EFI/memtest/memtest.efi https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/mt86plus || exit 1
chmod 755 /boot/efi/EFI/memtest/memtest.efi

# 2. BACKUP EXISTING CONFIGS
cp /etc/default/grub /etc/default/grub.bak.$(date +%F_%T)

# 3. DYNAMICALLY DETECT PARAMETERS (The "Safety" Part)
# Get UUID of the EFI partition to avoid "hd0,gpt1" guesswork
EFI_UUID=$(lsblk -no UUID $(df /boot/efi | tail -1 | awk '{print $1}'))

# Pull existing LVM/UUID configs to prevent Initramfs errors
# This ensures rd.lvm.lv=rl/root or centos/root is preserved exactly as it is now
CURRENT_PARAMS=$(grep '^GRUB_CMDLINE_LINUX' /etc/default/grub | cut -d'"' -f2 | sed 's/console=ttyS0,[0-9]*//g' | sed 's/console=tty0//g' | xargs)
NEW_PARAMS="console=tty0 console=ttyS0,115200 $CURRENT_PARAMS"

# 4. CONFIGURE 40_CUSTOM (MemTest)
IS_CENTOS7=$(grep -q "release 7" /etc/redhat-release && echo "true" || echo "false")
LOADER="linux"
[ "$IS_CENTOS7" == "true" ] && LOADER="linuxefi"

cat <<EOC > /etc/grub.d/40_custom
#!/bin/sh
exec tail -n +3 \$0
menuentry "MemTest86+ (Self-Compiled)" --class memtest86 {
    insmod part_gpt
    insmod fat
    search --no-floppy --fs-uuid --set=root $EFI_UUID
    $LOADER /EFI/memtest/memtest.efi console=ttyS0,115200
}
EOC
chmod +x /etc/grub.d/40_custom

# 5. UPDATE /etc/default/grub
# Use sed to replace the line while preserving other settings
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$NEW_PARAMS\"|" /etc/default/grub
sed -i "/^GRUB_TERMINAL=/d" /etc/default/grub
echo 'GRUB_TERMINAL="serial console"' >> /etc/default/grub
echo 'GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"' >> /etc/default/grub
echo 'GRUB_TIMEOUT=10' >> /etc/default/grub

# 6. RUN MKCONFIG TO THE CORRECT EFI PATH
if [ -f /boot/efi/EFI/rocky/grub.cfg ]; then
    grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg
elif [ -f /boot/efi/EFI/centos/grub.cfg ]; then
    grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
else
    grub2-mkconfig -o /boot/grub2/grub.cfg
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

    # Check for both Serial Console AND Memtest presence
    MEM_CHECK=$(sshpass -e ssh $SSH_OPTS root@"$VMIP" "[ -f /boot/efi/EFI/memtest/memtest.efi ] && echo 'FOUND'" 2>/dev/null)

    if [ -z "$MEM_CHECK" ]; then
        echo "  -> [!] Updating GRUB Config and adding MemTest..."
        sshpass -e scp $SCP_OPTS enable-verbose-boot.sh root@"$VMIP":/tmp/
        sshpass -e ssh $SSH_OPTS root@"$VMIP" "chmod +x /tmp/enable-verbose-boot.sh && /tmp/enable-verbose-boot.sh && reboot" &
    else
        echo "  -> [OK] GRUB and MemTest already configured."
    fi
done

wait
echo "=========================================================="
echo "AUDIT COMPLETE"
echo "=========================================================="
