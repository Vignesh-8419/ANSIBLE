#!/bin/bash

# 1. Detect OS Version for correct loader command
EL_VERSION=$(grep -oE '[0-9]' /etc/redhat-release | head -1)
LINUX_CMD=$([ "$EL_VERSION" -eq "7" ] && echo "linuxefi" || echo "linux")

# 2. Setup MemTest Directory and Binary
mkdir -p /boot/efi/EFI/memtest/
wget -qO /boot/efi/EFI/memtest/memtest.efi https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/mt86plus
chmod 755 /boot/efi/EFI/memtest/memtest.efi

# 3. Create Custom GRUB Entry (No OS Console Changes)
cat <<EOF > /etc/grub.d/40_custom
#!/bin/sh
exec tail -n +3 \$0

menuentry "MemTest86+ (Self-Compiled)" --class memtest86 {
    insmod part_gpt
    insmod fat
    set root='hd0,gpt1'
    $LINUX_CMD /EFI/memtest/memtest.efi
}
EOF
chmod +x /etc/grub.d/40_custom

# 4. Identify correct GRUB config path and update
if [ -f /boot/efi/EFI/rocky/grub.cfg ]; then
    TARGET="/boot/efi/EFI/rocky/grub.cfg"
elif [ -f /boot/efi/EFI/centos/grub.cfg ]; then
    TARGET="/boot/efi/EFI/centos/grub.cfg"
else
    TARGET="/boot/grub2/grub.cfg"
fi

echo "Updating GRUB at $TARGET..."
grub2-mkconfig -o "$TARGET"
echo "Done! MemTest86+ added to boot menu. (OS Console settings untouched)"
