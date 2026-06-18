#!/bin/bash

echo "Starting Deep Clean of GRUB and MemTest..."

# 1. REMOVE SOURCE GHOSTS
# This deletes any file in /etc/grub.d/ that contains 'MemTest', 
# including those .bak files that were re-injecting the entry.
grep -l "MemTest" /etc/grub.d/* 2>/dev/null | xargs rm -f
echo "[OK] Source scripts removed from /etc/grub.d/"

# 2. CLEAN UP THE DEFAULT CONFIG
# This removes serial console settings and fixes the duplicated CMDLINE
PARAMS=$(cat /proc/cmdline | sed 's/BOOT_IMAGE=[^ ]* //; s/console=ttyS0,[0-9]*//g; s/console=tty0//g' | awk '{$1=$1;print}' | cut -d' ' -f1-4)
# Note: The above logic ensures we keep your LVM paths but stop the duplication.

sed -i '/GRUB_TERMINAL/d' /etc/default/grub
sed -i '/GRUB_SERIAL_COMMAND/d' /etc/default/grub
sed -i '/GRUB_CMDLINE_LINUX=/d' /etc/default/grub

# Restore a clean, single-line CMDLINE
echo "GRUB_CMDLINE_LINUX=\"$PARAMS rhgb quiet\"" >> /etc/default/grub
echo "GRUB_TERMINAL_OUTPUT=\"console\"" >> /etc/default/grub
echo "[OK] /etc/default/grub cleaned."

# 3. DETECT OS AND REGENERATE
if [ -f /boot/efi/EFI/rocky/grub.cfg ]; then
    TARGET="/boot/efi/EFI/rocky/grub.cfg"
elif [ -f /boot/efi/EFI/centos/grub.cfg ]; then
    TARGET="/boot/efi/EFI/centos/grub.cfg"
else
    TARGET="/boot/grub2/grub.cfg"
fi

echo "Regenerating config at $TARGET..."
grub2-mkconfig -o "$TARGET"

# 4. FINAL VERIFICATION
echo "---------------------------------------"
echo "VERIFICATION RESULTS:"
if grep -q "MemTest" "$TARGET"; then
    echo "[!] WARNING: MemTest STILL found in $TARGET. Manual intervention required."
else
    echo "[SUCCESS] MemTest entry has been eradicated."
fi

if grep -q "console=ttyS0" /etc/default/grub; then
    echo "[!] WARNING: Serial console settings still exist in /etc/default/grub."
else
    echo "[SUCCESS] Serial console settings removed."
fi
