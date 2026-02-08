#!/bin/bash

# 1. Delete MemTest binary
rm -rf /boot/efi/EFI/memtest/

# 2. Delete ALL MemTest source scripts and backups from /etc/grub.d/
grep -l "MemTest" /etc/grub.d/* 2>/dev/null | xargs rm -f

# 3. Regenerate GRUB
if [ -f /boot/efi/EFI/rocky/grub.cfg ]; then
    TARGET="/boot/efi/EFI/rocky/grub.cfg"
elif [ -f /boot/efi/EFI/centos/grub.cfg ]; then
    TARGET="/boot/efi/EFI/centos/grub.cfg"
else
    TARGET="/boot/grub2/grub.cfg"
fi

grub2-mkconfig -o "$TARGET"
echo "MemTest removed. GRUB restored."
