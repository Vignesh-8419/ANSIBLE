#!/bin/bash

# 1. FORCE REMOVE the MemTest block from the physical config file
# This deletes everything from the menuentry line to the closing bracket }
sed -i '/menuentry "MemTest86+/,/}/d' /boot/efi/EFI/centos/grub.cfg 2>/dev/null
sed -i '/menuentry "MemTest86+/,/}/d' /boot/efi/EFI/rocky/grub.cfg 2>/dev/null

# 2. Extract CURRENT working parameters from the running Kernel
# This ensures we keep your LVM paths but strip the serial console
PARAMS=$(cat /proc/cmdline | sed 's/BOOT_IMAGE=[^ ]* //; s/console=ttyS0,[0-9]*//g; s/console=tty0//g' | xargs)

# 3. Wipe and Rebuild the GRUB default file to remove Serial redirection
sed -i '/GRUB_TERMINAL/d' /etc/default/grub
sed -i '/GRUB_SERIAL_COMMAND/d' /etc/default/grub
sed -i '/GRUB_CMDLINE_LINUX=/d' /etc/default/grub
echo "GRUB_CMDLINE_LINUX=\"$PARAMS\"" >> /etc/default/grub
echo "GRUB_TERMINAL_OUTPUT=\"console\"" >> /etc/default/grub

# 4. OS Detection and Final Config Generation
if [ -f /boot/efi/EFI/rocky/grub.cfg ]; then
    echo "Processing Rocky Linux..."
    grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg
elif [ -f /boot/efi/EFI/centos/grub.cfg ]; then
    echo "Processing CentOS..."
    grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
fi

# 5. VERIFICATION
echo "--- Post-Cleanup Check ---"
grep -i "memtest" /boot/efi/EFI/*/grub.cfg
grep "console=ttyS0" /etc/default/grub
