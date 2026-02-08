#!/bin/bash

# 1. Detect Version
EL_VERSION=$(grep -oE '[0-9]' /etc/redhat-release | head -1)
echo "Detected Enterprise Linux Version: $EL_VERSION"

# Determine if we need 'linux' or 'linuxefi'
# EL7 usually requires linuxefi; EL8/9 works best with linux
if [ "$EL_VERSION" -eq "7" ]; then
    LINUX_CMD="linuxefi"
else
    LINUX_CMD="linux"
fi

# 2. Download Binary
mkdir -p /boot/efi/EFI/memtest/
wget -O /boot/efi/EFI/memtest/memtest.efi https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/mt86plus
chmod 755 /boot/efi/EFI/memtest/memtest.efi

# 3. Create Custom GRUB Entry with SERIAL REDIRECTION
cat <<EOF > /etc/grub.d/40_custom
#!/bin/sh
exec tail -n +3 \$0

menuentry "MemTest86+ (Self-Compiled)" --class memtest86 {
    insmod part_gpt
    insmod fat
    set root='hd0,gpt1'
    $LINUX_CMD /EFI/memtest/memtest.efi console=ttyS0,115200
}
EOF
chmod +x /etc/grub.d/40_custom

# 4. Version-Specific Execution
echo "Updating GRUB configuration..."
if [ "$EL_VERSION" -eq "7" ]; then
    grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
else
    # Check for Rocky specifically, then fallback to standard paths
    if [ -f /boot/efi/EFI/rocky/grub.cfg ]; then
        grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg
    elif [ -f /boot/efi/EFI/centos/grub.cfg ]; then
        grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
    else
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
fi

echo "Done! Serial console redirection applied. Please reboot and select MemTest86+."
