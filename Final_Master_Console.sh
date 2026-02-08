#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'
MY_HOSTNAME=$(hostname)

# --- STEP 0: FETCH ALL VMs FROM ESXI ---
echo "[*] Fetching ALL VMs from ESXi ($ESXI_IP)..."
VMLIST=$(sshpass -p "$ESXI_PASS" ssh -o StrictHostKeyChecking=no root@$ESXI_IP "vim-cmd vmsvc/getallvms" | awk 'NR>1 {print $2}')

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

    IS_SELF="false"
    [[ "$VMNAME" == "$MY_HOSTNAME" ]] && IS_SELF="true"

    # 1. HARDWARE AUDIT
    echo "[*] Phase 1: ESXi Hardware Check for $VMNAME..."
    HW_STATUS=$(sshpass -p "$ESXI_PASS" ssh -o StrictHostKeyChecking=no root@$ESXI_IP "sh -s" <<ESX_EOF
        VMID=\$(vim-cmd vmsvc/getallvms | grep " $VMNAME " | awk '{print \$1}')
        if [ -z "\$VMID" ]; then echo "NOT_FOUND"; exit; fi
        VMX_PATH=\$(find /vmfs/volumes/ -name "${VMNAME}.vmx" | head -n 1)
        
        if ! grep -q "serial0.present = \"TRUE\"" "\$VMX_PATH"; then
            if [ "$IS_SELF" = "true" ]; then
                echo "HARDWARE_MISSING_SELF"
            else
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
        else echo "HARDWARE_OK"; fi
        vim-cmd vmsvc/power.on \$VMID >/dev/null 2>&1
ESX_EOF
    )
    echo "  -> ESXi Status: $HW_STATUS"

    # 2. IP RESOLUTION (The Safety Fix)
    if [ "$IS_SELF" = "true" ]; then
        VMIP="127.0.0.1"
    else
        # Try to get the IP, but don't default to 127.0.0.1 if it fails
        VMIP=$(getent hosts "$VMNAME" | awk '{print $1}' | head -n 1)
        if [ -z "$VMIP" ]; then
            VMIP=$(nslookup "$VMNAME" 2>/dev/null | grep -A 1 "Name:" | grep "Address" | awk '{print $2}' | head -n 1)
        fi
    fi

    if [ -z "$VMIP" ]; then
        echo "  [!] ERROR: Could not find IP for $VMNAME. Skipping."
        continue
    fi

    # 3. GUEST OS AUDIT
    echo "[*] Phase 2: Waiting for SSH on $VMNAME ($VMIP)..."
    if ! timeout 5 bash -c "</dev/tcp/$VMIP/22" 2>/dev/null; then
        echo "  [!] SSH Unreachable. Skipping."
        continue
    fi

    # 4. INTERNAL CONFIG
    if [ "$IS_SELF" = "true" ]; then
        echo "  [*] Updating Local DNS Server..."
        ./enable-verbose-boot.sh
        echo "  [SUCCESS] Local config updated. Rebooting manually is recommended later."
    else
        echo "  [*] Updating Remote $VMNAME..."
        sshpass -p "$VM_PASS" sco -o StrictHostKeyChecking=no enable-verbose-boot.sh root@"$VMIP":/tmp/
        sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no root@"$VMIP" "bash /tmp/enable-verbose-boot.sh && reboot"
        echo "  [SUCCESS] $VMNAME updated and rebooting."
    fi
done
