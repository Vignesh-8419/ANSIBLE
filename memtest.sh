#!/bin/bash

# 1. Detect Version
EL_VERSION=$(grep -oE '[0-9]' /etc/redhat-release | head -1)
echo "Detected Enterprise Linux Version: $EL_VERSION"

# 2. Download Binary (Common for all)
wget -O /tmp/mt86plus https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/mt86plus
mkdir -p /boot/efi/EFI/memtest/
mv /tmp/mt86plus /boot/efi/EFI/memtest/memtest.efi
chmod 755 /boot/efi/EFI/memtest/memtest.efi

# 3. Create Custom GRUB Entry
cat <<EOF > /etc/grub.d/40_custom
#!/bin/sh
exec tail -n +3 \$0

menuentry "MemTest86+ (Self-Compiled)" --class memtest86 {
    insmod part_gpt
    insmod fat
    set root='hd0,gpt1'
    linux /EFI/memtest/memtest.efi
}
EOF
chmod +x /etc/grub.d/40_custom

# 4. Version-Specific Execution
if [ "$EL_VERSION" -eq "7" ]; then
    echo "Configuring for EL7..."
    # CentOS 7 UEFI path
    grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
else
    echo "Configuring for EL8/9..."
    # Modern EL path (Rocky/CentOS/RHEL 8 & 9)
    # We update the main grub2 path; the EFI stub handles the rest
    grub2-mkconfig -o /boot/grub2/grub.cfg
    
    # Optional: Force update the EFI path if the stub is missing
    [ -f /boot/efi/EFI/rocky/grub.cfg ] && grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg
    [ -f /boot/efi/EFI/centos/grub.cfg ] && grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
fi

echo "Done! Please reboot and disable Secure Boot if necessary."
