#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'
MY_HOSTNAME=$(hostname)

# --- STEP 0: FETCH ALL VMs FROM ESXI ---
echo "[*] Fetching ALL VMs from ESXi ($ESXI_IP)..."
VMLIST=$(sshpass -p "$ESXI_PASS" ssh -o StrictHostKeyChecking=no root@$ESXI_IP "vim-cmd vmsvc/getallvms" | awk 'NR>1 {print $2}')

if [ -z "$VMLIST" ]; then
    echo "[!] No VMs found on ESXi. Exiting."
    exit 1
fi

# --- GENERATE THE LOCAL GRUB SCRIPT ---
# This is the payload that will be sent to the remote VMs
cat << 'EOF' > enable-verbose-boot.sh
#!/bin/bash
mkdir -p /boot/efi/EFI/memtest
echo "[*] Downloading MemTest86+..."
curl -L -f -o /boot/efi/EFI/memtest/memtest.efi https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/mt86plus || exit 1
chmod 755 /boot/efi/EFI/memtest/memtest.efi

# Safety: Detect EFI partition and Kernel parameters
EFI_UUID=$(lsblk -no UUID $(df /boot/efi | tail -1 | awk '{print $1}'))
CURRENT_PARAMS=$(grep '^GRUB_CMDLINE_LINUX' /etc/default/grub | cut -d'"' -f2 | sed 's/console=ttyS0,[0-9]*//g; s/console=tty0//g' | xargs)
NEW_PARAMS="console=tty0 console=ttyS0,115200 $CURRENT_PARAMS"
IS_EL7=$(grep -q "release 7" /etc/redhat-release && echo "true" || echo "false")
LOADER=$([ "$IS_EL7" == "true" ] && echo "linuxefi" || echo "linux")

# Create Custom MemTest Menu Entry
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

# Update GRUB Config
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$NEW_PARAMS\"|" /etc/default/grub
sed -i "/^GRUB_TERMINAL=/d" /etc/default/grub
echo 'GRUB_TERMINAL="serial console"' >> /etc/default/grub
echo 'GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"' >> /etc/default/grub
echo 'GRUB_TIMEOUT=10' >> /etc/default/grub

if [ -f /boot/efi/EFI/rocky/grub.cfg ]; then T="/boot/efi/EFI/rocky/grub.cfg"
elif [ -f /boot/efi/EFI/centos/grub.cfg ]; then T="/boot/efi/EFI/centos/grub.cfg"
else T="/boot/grub2/grub.cfg"; fi

echo "[*] Regenerating GRUB at $T..."
grub2-mkconfig -o $T
EOF
chmod +x enable-verbose-boot.sh

# --- MAIN LOOP ---
for VMNAME in $VMLIST; do
    echo "=========================================================="
    read -p "Process VM: $VMNAME? (y/n): " CONFIRM
    [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && echo "Skipping $VMNAME." && continue

    IS_SELF="false"
    [[ "$VMNAME" == "$MY_HOSTNAME" ]] && IS_SELF="true"

    # 1. HARDWARE AUDIT & POWER ON
    echo "[*] Phase 1: ESXi Hardware & Power Check for $VMNAME..."
    HW_STATUS=$(sshpass -p "$ESXI_PASS" ssh -o StrictHostKeyChecking=no root@$ESXI_IP "sh -s" <<ESX_EOF
        VMID=\$(vim-cmd vmsvc/getallvms | grep " $VMNAME " | awk '{print \$1}')
        if [ -z "\$VMID" ]; then echo "NOT_FOUND"; exit; fi
        
        VMX_PATH=\$(find /vmfs/volumes/ -name "${VMNAME}.vmx" | head -n 1)
        
        if ! grep -q "serial0.present = \"TRUE\"" "\$VMX_PATH"; then
            if [ "$IS_SELF" = "true" ]; then
                echo "HARDWARE_MISSING_SELF"
            else
                echo "HARDWARE_MISSING"
                WID=\$(localcli vm process list | grep -A 1 "$VMNAME" | grep "World ID" | awk '{print \$3}')
                [ ! -z "\$WID" ] && localcli vm process kill --type=force --world-id=\$WID && sleep 2
                
                sed -i '/serial0/d' "\$VMX_PATH"
                VPORT=\$((2000 + \$VMID))
                echo "serial0.present = \"TRUE\"" >> "\$VMX_PATH"
                echo "serial0.yieldOnPoll = \"TRUE\"" >> "\$VMX_PATH"
                echo "serial0.fileType = \"network\"" >> "\$VMX_PATH"
                echo "serial0.fileName = \"telnet://:\$VPORT\"" >> "\$VMX_PATH"
                echo "serial0.network.endPoint = \"server\"" >> "\$VMX_PATH"
                vim-cmd vmsvc/reload \$VMID
                echo "HARDWARE_ADDED"
            fi
        else
            echo "HARDWARE_OK"
        fi

        STATE=\$(vim-cmd vmsvc/power.getstate \$VMID | tail -1)
        if [ "\$STATE" = "Powered off" ]; then
            vim-cmd vmsvc/power.on \$VMID > /dev/null
            echo "POWERED_ON"
        else
            echo "ALREADY_RUNNING"
        fi
ESX_EOF
    )

    echo "  -> Status: $HW_STATUS"
    [[ "$HW_STATUS" == *"NOT_FOUND"* ]] && echo "  [!] VM not found on ESXi. Skipping." && continue

    # 2. IP RESOLUTION (Safety First)
    if [ "$IS_SELF" = "true" ]; then
        VMIP="127.0.0.1"
    else
        VMIP=$(getent hosts "$VMNAME" | awk '{print $1}' | head -n 1)
        [[ -z "$VMIP" ]] && VMIP=$(nslookup "$VMNAME" 2>/dev/null | grep 'Address:' | tail -n1 | awk '{print $2}')
    fi

    if [ -z "$VMIP" ]; then
        echo "  [!] ERROR: Could not resolve IP for $VMNAME. Skipping to avoid self-harm."
        continue
    fi

    # 3. GUEST OS AUDIT (SSH Check)
    echo "[*] Phase 2: Waiting for Guest SSH ($VMNAME @ $VMIP)..."
    COUNT=0
    READY=false
    while [ $COUNT -lt 12 ]; do
        if timeout 2 bash -c "</dev/tcp/$VMIP/22" 2>/dev/null; then
            READY=true
            break
        fi
        echo -n "."
        sleep 5
        ((COUNT++))
    done
    echo ""

    if [ "$READY" = false ]; then
        echo "  [!] Guest OS failed to start SSH. Skipping."
        continue
    fi

    # 4. INTERNAL CONFIG (MemTest & GRUB)
    echo "[*] Phase 3: Internal Config Audit..."
    if [ "$IS_SELF" = "true" ]; then
        echo "  [*] Updating Local DNS Server..."
        ./enable-verbose-boot.sh
        echo "  [SUCCESS] Local config updated. (No auto-reboot for self)."
    else
        echo "  [*] Updating Remote $VMNAME..."
        # Fixed 'sco' to 'scp' here
        sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no enable-verbose-boot.sh root@"$VMIP":/tmp/
        sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no root@"$VMIP" "bash /tmp/enable-verbose-boot.sh && reboot"
        echo "  [SUCCESS] Configuration applied. $VMNAME is rebooting."
    fi
done

echo "=========================================================="
echo "AUDIT SEQUENCE COMPLETE"
