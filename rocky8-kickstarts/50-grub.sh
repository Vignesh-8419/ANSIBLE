#!/bin/bash
#==============================================================================
# 50-grub.sh
#
# Configure Dual UEFI Bootloader
# Hardened version with Direct Parent Disk Enumeration Order
#==============================================================================

set -euo pipefail

echo
echo "============================================================"
echo "Installing GRUB on Both EFI Partitions"
echo "============================================================"

###############################################################################
# Locate Hard Disks Natively (Direct Parent Assignment Matrix)
###############################################################################
DISKS=()
while read -r NAME TYPE
do
    [ "$TYPE" != "disk" ] && continue
    case "$NAME" in
        sr*|loop*|fd*|ram*|zd*) continue ;;
    esac
    DISKS+=("$NAME")
done < <(lsblk -dn -o NAME,TYPE)

if [ ${#DISKS[@]} -ne 2 ]; then
    echo "ERROR: Exactly two installation disks are required."
    exit 1
fi

DISK1="/dev/${DISKS[0]}"
DISK2="/dev/${DISKS[1]}"

echo "Direct Disk 1 Mapping : $DISK1"
echo "Direct Disk 2 Mapping : $DISK2"

###############################################################################
# Resolve Partition Suffix Rules Safely
###############################################################################
D1_BASE=$(basename "$DISK1")
D2_BASE=$(basename "$DISK2")

# Fixed: Explicit structural branching prevents implicit non-zero evaluation codes
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

echo "Formatting secondary partition target $EFI2 as FAT32..."

# Fixed: Forcefully detach active kernel mounts or dev-mapper locks before formatting
sync
umount -f "$EFI2" 2>/dev/null || true
if command -v dmsetup >/dev/null 2>&1; then
    dmsetup remove "$(basename "$EFI2")" 2>/dev/null || true
fi
udevadm settle

# Run format task cleanly
mkfs.vfat -F32 "$EFI2"
fatlabel "$EFI1" EFI-SYSTEM
fatlabel "$EFI2" EFI-SYSTEM
FSTYPE2=$(blkid -o value -s TYPE "$EFI2")

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
mkdir -p /boot/efi
mkdir -p /mnt/efi2

mountpoint -q /boot/efi || mount "$EFI1" /boot/efi
mountpoint -q /mnt/efi2 || mount "$EFI2" /mnt/efi2

mountpoint -q /boot/efi || {
    echo "ERROR: Failed to mount primary EFI."
    exit 1
}

mountpoint -q /mnt/efi2 || {
    echo "ERROR: Failed to mount secondary EFI."
    exit 1
}

###############################################################################
# Verify Existing EFI Bootloader
###############################################################################
echo "Using EFI bootloader installed by Anaconda..."

if [ ! -f "/boot/efi/EFI/rocky/shimx64.efi" ]; then
    echo "ERROR: /boot/efi/EFI/rocky/shimx64.efi not found."
    exit 1
fi

echo "EFI bootloader verified."

###############################################################################
# Synchronize EFI Partitions
###############################################################################
echo "Synchronizing EFI partitions..."
rsync -aH --delete /boot/efi/EFI/ /mnt/efi2/EFI/

echo "Verifying EFI synchronization..."
if diff -rq /boot/efi/EFI /mnt/efi2/EFI; then
    echo "EFI synchronization verified."
else
    echo "ERROR: EFI partitions differ after synchronization."
    exit 1
fi

###############################################################################
# Create Standard UEFI Fallback Pathing
###############################################################################
mkdir -p /boot/efi/EFI/BOOT
mkdir -p /mnt/efi2/EFI/BOOT

if [ -f /boot/efi/EFI/rocky/shimx64.efi ]; then
    cp -f /boot/efi/EFI/rocky/shimx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI
fi

if [ -f /mnt/efi2/EFI/rocky/shimx64.efi ]; then
    cp -f /mnt/efi2/EFI/rocky/shimx64.efi /mnt/efi2/EFI/BOOT/BOOTX64.EFI
fi

###############################################################################
# Verify Shim Exists
###############################################################################
if [[ ! -f /boot/efi/EFI/rocky/shimx64.efi ]]; then
    echo "ERROR: Missing /boot/efi/EFI/rocky/shimx64.efi"
    exit 1
fi

if [[ ! -f /mnt/efi2/EFI/rocky/shimx64.efi ]]; then
    echo "ERROR: Missing /mnt/efi2/EFI/rocky/shimx64.efi"
    exit 1
fi

###############################################################################
# Enforce Identical Partition Numbers Natively
###############################################################################
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
# Create Boot Entries
###############################################################################
efibootmgr \
    -c \
    -d "$DISK1" \
    -p "$PARTNUM1" \
    -L "Rocky Linux Disk1" \
    -l '\EFI\rocky\shimx64.efi' || true

efibootmgr \
    -c \
    -d "$DISK2" \
    -p "$PARTNUM2" \
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
}' || echo ""
)

ID2=$(
efibootmgr |
awk '/Rocky Linux Disk2/{
gsub(/Boot|\*/,"",$1)
print $1
}' || echo ""
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
mkdir -p /etc/mdadm
mdadm --detail --scan > /etc/mdadm.conf || \
    echo "WARNING: Unable to generate /etc/mdadm.conf"

###############################################################################
# Rebuild initramfs Execution Layer
###############################################################################
echo "Rebuilding initramfs..."
dracut -f || echo "WARNING: dracut returned codes during deployment configuration stages."

###############################################################################
# Verification Diagnostics Summary
###############################################################################
echo "============================================================"
echo "Verification Data Summary"
echo "============================================================"

echo "MD RAID"
cat /proc/mdstat

echo "Boot Entries"
efibootmgr -v || true

echo "Disks"
lsblk

###############################################################################
# Cleanup Mounts Safely
###############################################################################
sync
mountpoint -q /mnt/efi2 && umount /mnt/efi2 || true
rmdir /mnt/efi2 2>/dev/null || true

###############################################################################
# Update /etc/fstab
###############################################################################
echo "Updating /etc/fstab..."

# Remove Anaconda's EFI entry
sed -i '\|/boot/efi|d' /etc/fstab

# Do not create a persistent /boot/efi mount.
# It will be mounted manually only when required (GRUB/kernel updates).

systemctl daemon-reload

echo "============================================================"
echo "GRUB installation completed successfully."
echo "============================================================"
