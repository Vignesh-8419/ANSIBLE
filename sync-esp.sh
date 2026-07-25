#!/bin/bash
#==============================================================================
# Universal Resilient EFI Sync Engine (Rocky 8 Tree-Stripped Layer)
# Safely handles list graphics formatting on NVMe and SCSI devices
#==============================================================================
set -e

# 1. Grab the first two primary operating disks cleanly
PRIMARY_DISK=$(lsblk -dnno NAME,TYPE | awk '$2=="disk" {print $1}' | grep -E '^(sd|nvme)' | head -n 1)
SECONDARY_DISK=$(lsblk -dnno NAME,TYPE | awk '$2=="disk" {print $1}' | grep -E '^(sd|nvme)' | head -n 2 | tail -n 1)

if [ -z "$SECONDARY_DISK" ] || [ "$PRIMARY_DISK" == "$SECONDARY_DISK" ]; then
    echo "ERROR: Dynamic secondary disk verification failed."
    exit 1
fi

# 2. FIXED: Added -l flag to force list formatting and strip out ├─ tree elements
TARGET_PART=$(lsblk -lnno NAME,FSTYPE "/dev/$SECONDARY_DISK" | awk '$2=="vfat" {print $1}')

if [ -z "$TARGET_PART" ]; then
    echo "ERROR: No VFAT/EFI backup partition found on /dev/$SECONDARY_DISK"
    exit 1
fi

# Ensure full structural block prefix routing
TARGET_PART="/dev/$TARGET_PART"
echo "Targeting verified secondary EFI layer: $TARGET_PART"

# 3. Handle mounting environment checks cleanly
mkdir -p /boot/efi2
WE_MOUNTED=0

if mountpoint -q /boot/efi2; then
    echo "/boot/efi2 is already active. Processing sync tasks..."
else
    mount -t vfat "$TARGET_PART" /boot/efi2
    WE_MOUNTED=1
fi

# 4. Synchronize core bootloader binary configurations
rsync -ahrlptD --delete /boot/efi/EFI/ /boot/efi2/EFI/

# 5. Populate automated removable device directory fallbacks
mkdir -p /boot/efi2/EFI/BOOT
if [ -f /boot/efi2/EFI/rocky/shimx64.efi ]; then
    cp /boot/efi2/EFI/rocky/shimx64.efi /boot/efi2/EFI/BOOT/BOOTX64.EFI
    cp /boot/efi2/EFI/rocky/grubx64.efi /boot/efi2/EFI/BOOT/grubx64.efi
    cp /boot/efi2/EFI/rocky/grub.cfg /boot/efi2/EFI/BOOT/grub.cfg
else
    cp /boot/efi2/EFI/rocky/grubx64.efi /boot/efi2/EFI/BOOT/BOOTX64.EFI
    cp /boot/efi2/EFI/rocky/grub.cfg /boot/efi2/EFI/BOOT/grub.cfg
fi

# 6. Adjust GRUB firmware targets for decoupled standalone booting
if [ -f /boot/efi2/EFI/rocky/grub.cfg ]; then
    sed -i "s|hd0,gpt1|hd1,gpt1|g" /boot/efi2/EFI/rocky/grub.cfg || true
    sed -i "s|hd0,gpt1|hd1,gpt1|g" /boot/efi2/EFI/BOOT/grub.cfg || true
fi

sync

if [ "$WE_MOUNTED" -eq 1 ]; then
    umount /boot/efi2
fi
echo "EFI Sync Operation Completed Successfully."
