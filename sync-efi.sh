#!/bin/bash
set -euo pipefail

mkdir -p /boot/efi
mkdir -p /boot/efi2

# Mount the primary EFI if it isn't already mounted
if ! mountpoint -q /boot/efi; then
    mount /boot/efi
    MOUNTED_EFI=1
else
    MOUNTED_EFI=0
fi

# Mount the secondary EFI
mount /dev/sdb1 /boot/efi2

# Install GRUB to the second EFI partition
grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi2 \
    --bootloader-id=ubuntu \
    --removable \
    --recheck

# Synchronize EFI contents
rsync -aHAX --delete /boot/efi/ /boot/efi2/

# Ensure fallback bootloader exists
mkdir -p /boot/efi2/EFI/BOOT
cp -f /boot/efi2/EFI/ubuntu/shimx64.efi /boot/efi2/EFI/BOOT/BOOTX64.EFI
cp -f /boot/efi2/EFI/ubuntu/mmx64.efi /boot/efi2/EFI/BOOT/

sync

umount /boot/efi2

# Unmount the primary EFI only if this script mounted it
if [ "$MOUNTED_EFI" -eq 1 ]; then
    umount /boot/efi
fi

systemctl disable sync-efi.service