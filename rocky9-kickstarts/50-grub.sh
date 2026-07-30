#!/bin/bash
#==============================================================================
# 50-grub.sh
#
# Configure Dual UEFI Bootloader (Rocky 9 Unified Engine Edition)
# Hardened version with Direct Parent Disk Enumeration Order
#==============================================================================

set -euo pipefail

echo
echo "============================================================"
echo "Installing GRUB on Both EFI Partitions"
echo "============================================================"

##############################################################################
# Detect Physical Installation Disks
##############################################################################

DISKS=()

while read -r NAME TYPE
do
    [ "$TYPE" = "disk" ] || continue

    case "$NAME" in
        loop*|ram*|fd*|sr*|zram*|md*|dm-*)
            continue
            ;;
    esac

    DISKS+=("/dev/$NAME")

done < <(lsblk -dn -o NAME,TYPE)

echo "Detected disks: ${DISKS[*]}"
echo "Disk count: ${#DISKS[@]}"

if [ ${#DISKS[@]} -lt 2 ]; then
    echo "ERROR: Less than two installation disks detected."
    exit 1
fi

DISK1="${DISKS[0]}"
DISK2="${DISKS[1]}"

echo "Disk1=$DISK1"
echo "Disk2=$DISK2"

###############################################################################
# Resolve Partition Suffix Rules Safely
###############################################################################
D1_BASE=$(basename "$DISK1")
D2_BASE=$(basename "$DISK2")

if [[ "$D1_BASE" =~ ^nvme ]] || [[ "$D1_BASE" =~ ^mmcblk ]]; then
    P1="p1"
else
    P1="1"
fi

EFI1="/dev/${D1_BASE}${P1}"
EFI2="/dev/${D2_BASE}${P1}"

echo "Primary EFI Target    : $EFI1"
echo "Secondary EFI Target  : $EFI2"

###############################################################################
# Verify and Format Filesystem Layouts
###############################################################################
FSTYPE1=$(blkid -o value -s TYPE "$EFI1" || echo "vfat")

###############################################################################
# Verify Secondary EFI Filesystem
###############################################################################

echo "Checking secondary EFI partition..."

udevadm settle

# Unmount if it was mounted somewhere
umount "$EFI2" 2>/dev/null || true

FSTYPE2=$(blkid -o value -s TYPE "$EFI2" || true)

if [[ -z "$FSTYPE2" ]]; then
    echo "ERROR: Unable to determine filesystem type of $EFI2"
    exit 1
fi

if [[ "$FSTYPE2" != "vfat" ]]; then
    echo "ERROR: $EFI2 is not FAT32 (detected: $FSTYPE2)"
    exit 1
fi

echo "Secondary EFI filesystem verified."

if [[ "$FSTYPE1" != "vfat" ]]; then
    echo "ERROR: $EFI1 is not a FAT EFI partition (found: $FSTYPE1)"
    exit 1
fi

if [[ "$FSTYPE2" != "vfat" ]]; then
    echo "ERROR: $EFI2 is not a FAT EFI partition (found: $FSTYPE2)"
    exit 1
fi

###############################################################################
# Mount EFI Partitions
###############################################################################

# Create mount point if missing
mkdir -p /boot/efi2

# Mount primary EFI if required
if ! mountpoint -q /boot/efi; then
    mkdir -p /boot/efi
    mount "$EFI1" /boot/efi
fi

# Unmount secondary EFI if mounted elsewhere
mount | awk -v dev="$EFI2" '$1==dev {print $3}' | while read -r mp
do
    umount "$mp" 2>/dev/null || true
done

# Ensure mount directory exists
mkdir -p /boot/efi2

# Mount secondary EFI
mount "$EFI2" /boot/efi2 || {
    echo "ERROR: Failed to mount $EFI2"
    exit 1
}

mountpoint -q /boot/efi2 || {
    echo "ERROR: Secondary EFI mount verification failed."
    exit 1
}
###############################################################################
# Verify Existing EFI Bootloader (Rocky 9 Path Adaptive Logic Check)
###############################################################################
echo "Using EFI bootloader installed by Anaconda..."

# Rocky 9 defaults to standard unified fallback pathing formats
if [ ! -f "/boot/efi/EFI/BOOT/BOOTX64.EFI" ] && [ ! -f "/boot/efi/EFI/rocky/shimx64.efi" ]; then
    echo "ERROR: Rocky 9 core EFI loader binaries missing."
    exit 1
fi

echo "EFI bootloader verified."

###############################################################################
# Synchronize EFI Partitions
###############################################################################
echo "Copying complete EFI partition..."

rsync -aH --delete /boot/efi/ /boot/efi2/

sync

echo "Verifying EFI synchronization..."

if diff -rq /boot/efi /boot/efi2; then
    echo "EFI synchronization verified."
else
    echo "ERROR: EFI partitions differ."
    exit 1
fi

###############################################################################
# Create Standard UEFI Fallback Pathing
###############################################################################
mkdir -p /boot/efi/EFI/BOOT
mkdir -p /boot/efi2/EFI/BOOT

if [ -d /boot/efi/EFI/rocky ]; then
    cp -a /boot/efi/EFI/rocky /boot/efi2/EFI/
fi

if [ -f /boot/efi/EFI/rocky/shimx64.efi ]; then
    cp -f /boot/efi/EFI/rocky/shimx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI
    cp -f /boot/efi/EFI/rocky/shimx64.efi /boot/efi2/EFI/BOOT/BOOTX64.EFI
elif [ -f /boot/efi/EFI/BOOT/BOOTX64.EFI ]; then
    cp -f /boot/efi/EFI/BOOT/BOOTX64.EFI /boot/efi2/EFI/BOOT/BOOTX64.EFI
fi

PARTNUM1="1"
PARTNUM2="1"

echo "Disk1 EFI Partition Number : $PARTNUM1"
echo "Disk2 EFI Partition Number : $PARTNUM2"

###############################################################################
# Remove Existing Motherboard NVRAM Entries (Refined Robust Parsing)
###############################################################################
while read -r ID
do
    echo "Purging old profile matching ID: $ID"
    efibootmgr -b "$ID" -B || true
done < <(
    efibootmgr |
    awk '/Rocky Linux Disk1/ {gsub(/Boot|\*/,"",$1); print $1}'
)

while read -r ID
do
    echo "Purging old profile matching ID: $ID"
    efibootmgr -b "$ID" -B || true
done < <(
    efibootmgr |
    awk '/Rocky Linux Disk2/ {gsub(/Boot|\*/,"",$1); print $1}'
)

###############################################################################
# Configure EFI Boot Entries
###############################################################################


efibootmgr -c \
    -d "$DISK1" \
    -p 1 \
    -L "Rocky Linux Disk1" \
    -l '\EFI\rocky\shimx64.efi' || true

efibootmgr -c \
    -d "$DISK2" \
    -p 1 \
    -L "Rocky Linux Disk2" \
    -l '\EFI\rocky\shimx64.efi' || true

###############################################################################
# Configure Boot Order
###############################################################################
ID1=$(
efibootmgr |
awk '/Rocky Linux Disk1/{
gsub(/Boot|\*/,"",$1)
print $1
}' || true
)

ID2=$(
efibootmgr |
awk '/Rocky Linux Disk2/{
gsub(/Boot|\*/,"",$1)
print $1
}' || true
)

if [[ -n "$ID1" && -n "$ID2" ]]; then
    echo
    echo "Setting BootOrder: ${ID1},${ID2}"
    efibootmgr -o "${ID1},${ID2}" || true
fi

###############################################################################
# Save mdadm Configurations
###############################################################################
echo "Saving RAID configuration..."
mdadm --detail --scan > /etc/mdadm.conf

###############################################################################
# Rebuild initramfs Execution Layer
###############################################################################
echo "Rebuilding initramfs..."
if ! dracut -f; then
    echo "WARNING: dracut failed."
fi

###############################################################################
# Verification Diagnostics Summary
###############################################################################
echo "============================================================"
echo "Verification Data Summary"
echo "============================================================"
cat /proc/mdstat

efibootmgr -v || true

lsblk

###############################################################################
# Cleanup Mounts Safely
###############################################################################
sync
mountpoint -q /boot/efi2 && umount /boot/efi2 || true
rmdir /boot/efi2 2>/dev/null || true

###############################################################################
# Update /etc/fstab (Manual Mount Policy Configuration Enforced)
###############################################################################
##############################################################################
# Remove permanent EFI mount
##############################################################################

echo "Removing /boot/efi from /etc/fstab..."

sed -i '\|[[:space:]]/boot/efi[[:space:]]|d' /etc/fstab

systemctl daemon-reload || true

echo "Current /etc/fstab:"
cat /etc/fstab
echo "============================================================"
echo "GRUB installation completed successfully."
echo "============================================================"
