#!/bin/bash

# --- CONFIGURATION ---
ESXI_IP="192.168.253.128"
ESXI_PASS='admin$22'
VM_PASS='Root@123'

# --- THE LIST OF POTENTIAL TARGETS ---
VMLIST="ipa-server-01 ansible-server-01 rocky-08-02 http-server-01 cert-server-01 cent-07-01 cent-07-02 tftp-server-01 tftp-server-02"

# --- GENERATE THE LOCAL GRUB SCRIPT ---
cat << 'EOF' > enable-verbose-boot.sh
#!/bin/bash
# Logic to configure MemTest and Serial Console
mkdir -p /boot/efi/EFI/memtest
curl -L -f -o /boot/efi/EFI/memtest/memtest.efi https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/mt86plus || exit 1
chmod 755 /boot/efi/EFI/memtest/memtest.efi
EFI_UUID=$(lsblk -no UUID $(df /boot/efi | tail -1 | awk '{print $1}'))
CURRENT_PARAMS=$(grep '^GRUB_CMDLINE_LINUX' /etc/default/grub | cut -d'"' -f2 | sed 's/console=ttyS0,[0-9]*//g' | sed 's/console=tty0//g' | xargs)
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

if [ -f /boot/efi/EFI/rocky/grub.cfg ]; then grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg
elif [ -f /boot/efi/EFI/centos/grub.cfg ]; then grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
else grub2-mkconfig -o /boot/grub2/grub.cfg; fi
EOF
chmod +x enable-verbose-boot.sh

# --- INTERACTIVE PROCESSING LOOP ---
for VMNAME in $VMLIST; do
    echo "----------------------------------------------------------"
    read -p "Perform action on $VMNAME? (y/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Skipping $VMNAME."
        continue
    fi

    # 1. HARDWARE AUDIT ON ESXi
    echo "[*] Checking ESXi Hardware for $VMNAME..."
    sshpass -p "$ESXI_PASS" ssh -o StrictHostKeyChecking=no root@$ESXI_IP bash -s <<ESX_EOF
        VMID=\$(vim-cmd vmsvc/getallvms | grep " $VMNAME " | awk '{print \$1}')
        if [ -z "\$VMID" ]; then echo "[!] VM $VMNAME not found."; exit; fi
        VMX_PATH=\$(find /vmfs/volumes/ -name "${VMNAME}.vmx" | head -n 1)
        
        if ! grep -q "serial0.present = \"TRUE\"" "\$VMX_PATH"; then
            echo "[!] Fixing Hardware for $VMNAME..."
            WID=\$(localcli vm process list | grep -A 1 "$VMNAME" | grep "World ID" | awk '{print \$3}')
            [ ! -z "\$WID" ] && localcli vm process kill --type=force --world-id=\$WID && sleep 2
            sed -i '/serial0/d' "\$VMX_PATH"
            VPORT=\$((2000 + \$VMID))
            cat <<EOL >> "\$VMX_PATH"
serial0.present = "TRUE"
serial0.yieldOnPoll = "TRUE"
serial0.fileType = "network"
serial0.fileName = "telnet://:\$VPORT"
serial0.network.endPoint = "server"
EOL
            vim-cmd vmsvc/reload \$VMID
            vim-cmd vmsvc/power.on \$VMID
        else
            echo "[OK] Hardware looks good."
        fi
ESX_EOF

    # 2. GUEST OS AUDIT
    VMIP=$(nslookup "$VMNAME" | grep -A 1 "Name:" | grep "Address" | awk '{print $2}' | head -n 1)
    if [ -z "$VMIP" ]; then echo "[!] DNS Error for $VMNAME"; continue; fi

    echo "[*] Checking Guest OS at $VMIP..."
    if ! timeout 2 bash -c "</dev/tcp/$VMIP/22" 2>/dev/null; then
        echo " [!] $VMNAME is OFFLINE."
        continue
    fi

    MEM_CHECK=$(sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no root@"$VMIP" "[ -f /boot/efi/EFI/memtest/memtest.efi ] && echo 'FOUND'" 2>/dev/null)

    if [ -z "$MEM_CHECK" ]; then
        echo "  -> [!] Updating GRUB and rebooting..."
        sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no enable-verbose-boot.sh root@"$VMIP":/tmp/
        sshpass -p "$VM_PASS" ssh -o StrictHostKeyChecking=no root@"$VMIP" "chmod +x /tmp/enable-verbose-boot.sh && /tmp/enable-verbose-boot.sh && reboot"
    else
        echo "  -> [OK] MemTest already configured."
    fi
done

echo "=========================================================="
echo "INTERACTIVE AUDIT COMPLETE"
echo "=========================================================="
