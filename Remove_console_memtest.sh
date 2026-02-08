# 1. Clean the 'Ghost' MemTest entry from all possible EFI locations
sed -i '/menuentry "MemTest86+/,/}/d' /boot/efi/EFI/*/grub.cfg 2>/dev/null

# 2. Extract current working LVM/Root parameters and strip out console settings
PARAMS=$(cat /proc/cmdline | sed 's/BOOT_IMAGE=[^ ]* //; s/console=ttyS0,[0-9]*//g; s/console=tty0//g' | xargs)

# 3. Update /etc/default/grub with clean parameters
sed -i '/GRUB_CMDLINE_LINUX=/d' /etc/default/grub
echo "GRUB_CMDLINE_LINUX=\"$PARAMS\"" >> /etc/default/grub

# 4. Detect OS and update the CORRECT grub.cfg
if [ -f /etc/rocky-release ] || [ -f /etc/redhat-release ] && grep -q "Rocky" /etc/redhat-release; then
    echo "Updating Rocky Linux..."
    grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg
elif [ -f /etc/centos-release ] || grep -q "CentOS" /etc/redhat-release; then
    echo "Updating CentOS..."
    grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
else
    echo "Falling back to standard EFI path..."
    grub2-mkconfig -o /boot/efi/EFI/BOOT/grub.cfg
fi
