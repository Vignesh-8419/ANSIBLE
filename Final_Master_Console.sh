#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'
MY_HOSTNAME=$(hostname) # Detects 'dns-server-01'

# --- STEP 0: FETCH ALL VMs FROM ESXI ---
echo "[*] Fetching ALL VMs from ESXi ($ESXI_IP)..."
VMLIST=$(sshpass -p "$ESXI_PASS" ssh -o StrictHostKeyChecking=no root@$ESXI_IP "vim-cmd vmsvc/getallvms" | awk 'NR>1 {print $2}')

if [ -z "$VMLIST" ]; then
    echo "[!] No VMs found on ESXi. Exiting."
    exit 1
fi

# --- GENERATE THE LOCAL GRUB SCRIPT ---
cat << 'EOF' > enable-verbose-boot.sh
#!/bin/bash
mkdir -p /boot/efi/EFI/memtest
curl -L -f -o /boot/efi/EFI/memtest/memtest.efi https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/mt86plus || exit 1
chmod 755 /boot/efi/EFI/memtest/memtest.efi
EFI_UUID=$(lsblk -no UUID $(df /boot/efi | tail -1 | awk '{print $1}'))
CURRENT_PARAMS=$(grep '^GRUB_CMDLINE_LINUX' /etc/default/grub | cut -d'"' -f2 | sed 's/console=ttyS0,[0-9]*//g; s/console=tty0//g' | xargs)
NEW_PARAMS="console=tty0 console=ttyS0,115200 $CURRENT_PARAMS"
IS_CENTOS7=$(grep -q "release 7" /etc/redhat-release && echo "true" || echo "false")
LOADER=$([ "$IS_CENTOS7" == "true" ] && echo "linuxefi" || echo "linux")

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
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$NEW_PARAMS\"|" /etc/default/grub
sed -i "/^GRUB_TERMINAL=/d" /etc/default/grub
echo 'GRUB_TERMINAL="serial console"' >> /etc/default/grub
echo 'GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"' >> /etc/default/grub
echo 'GRUB_TIMEOUT=10' >> /etc/default/grub

[ -f /boot/efi/EFI/rocky/grub.cfg ] && T="/boot/efi/EFI/rocky/grub.cfg"
[ -f /boot/efi/EFI/centos/grub.cfg ] && T="/boot/efi/EFI/centos/grub.cfg"
grub2-mkconfig -o ${T:-/boot/grub2/grub.cfg}
EOF
chmod +x enable-verbose-boot.sh

# --- MAIN LOOP ---
for VMNAME in $VMLIST; do
    echo "=========================================================="
    read -p "Process VM: $VMNAME? (y/n): " CONFIRM
    [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && echo "Skipping $VMNAME." && continue

    # 1. HARDWARE AUDIT & POWER ON
    echo "[*] Phase 1: ESXi Hardware & Power Check..."
    
    # Check if this is the DNS server itself
    IS_SELF="false"
    [[ "$VMNAME" == "$MY_HOSTNAME" ]] && IS_SELF="true"

    HW_STATUS=$(sshpass -p "$ESXI_PASS" ssh -o StrictHostKeyChecking=no root@$ESXI_IP "sh -s" <<ESX_EOF
        VMID=\$(vim-cmd vmsvc/getallvms | grep " $VMNAME " | awk '{print \$1}')
        if [ -z "\$VMID" ]; then echo "NOT_FOUND"; exit; fi
        
        VMX_PATH=\$(find /vmfs/volumes/ -name "${VMNAME}.vmx" | head -n 1)
        
        if ! grep -q "serial0.present = \"TRUE\"" "\$VMX_PATH"; then
            if [ "$IS_SELF" = "true" ]; then
                echo "HARDWARE_MISSING_BUT_SELF"
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
    
    if [[ "$HW_STATUS" == *"HARDWARE_MISSING_BUT_SELF"* ]]; then
        echo "  [!] WARNING: Serial hardware is missing on THIS DNS server."
        echo "      I cannot fix it automatically without killing this script."
        echo "      Proceeding to GRUB check anyway..."
    fi

    # 2. GUEST OS AUDIT
    VMIP=$(nslookup "$VMNAME" | grep -A 1 "Address" | tail -1 | awk '{print $2}')
    [[ -z "$VMIP" ]] && VMIP="127.0.0.1" # Fallback if self
    
    echo "[*] Phase 2: Waiting for Guest SSH ($VMIP)..."
    if ! timeout 2 bash -c "</dev/tcp/$VMIP/22" 2>/dev/null; then
        echo "  [!] SSH Unreachable. Skipping."
        continue
    fi

    # 3. MEMTEST & GRUB CHECK
    echo "[*] Phase 3: Internal Config Check..."
    sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no root@"$VMIP" "[ -f /boot/efi/EFI/memtest/memtest.efi ]" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "  [OK] MemTest is already present."
    else
        echo "  [!] Config missing. Applying updates..."
        # If it's self, just run it locally
        if [ "$IS_SELF" = "true" ]; then
            ./enable-verbose-boot.sh
        else
            sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no enable-verbose-boot.sh root@"$VMIP":/tmp/
            sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no root@"$VMIP" "chmod +x /tmp/enable-verbose-boot.sh && /tmp/enable-verbose-boot.sh && reboot"
        fi
        echo "  [SUCCESS] Configuration applied to $VMNAME."
    fi
done
