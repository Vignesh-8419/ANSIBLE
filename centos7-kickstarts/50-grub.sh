#!/bin/bash
#==============================================================================
# 50-grub.sh
#------------------------------------------------------------------------------
# CentOS 7 Enterprise Golden Image
# UEFI + GPT + Software RAID1 + LVM
#
# Responsibilities
#   • Detect installation disks
#   • Detect EFI partitions dynamically
#   • Synchronize EFI partitions
#   • Install fallback bootloader
#   • Register UEFI boot entries
#   • Save mdadm configuration
#   • Rebuild initramfs
#
# Compatible With
#   • VMware ESXi
#   • VMware Workstation
#   • Physical Servers
#   • SATA / SCSI / NVMe
#==============================================================================

set -euo pipefail

echo
echo "=============================================================="
echo " CentOS 7 Dual UEFI Boot Configuration"
echo "=============================================================="
echo

###############################################################################
# Verify UEFI Environment
###############################################################################

if [ ! -d /sys/firmware/efi ]; then
    echo "ERROR: System is not running in UEFI mode."
    exit 1
fi

###############################################################################
# Detect Installation Disks
###############################################################################

echo "Detecting installation disks..."

DISKS=()

while read -r DEV
do
    case "$DEV" in
        /dev/sr*|/dev/loop*|/dev/ram*|/dev/fd*)
            continue
            ;;
    esac

    DISKS+=("$DEV")

done < <(lsblk -dn -o NAME | sed 's#^#/dev/#')

if [ "${#DISKS[@]}" -ne 2 ]; then
    echo
    echo "ERROR: Expected exactly two installation disks."
    printf '%s\n' "${DISKS[@]}"
    exit 1
fi

DISK1="${DISKS[0]}"
DISK2="${DISKS[1]}"

echo
echo "Primary Disk   : $DISK1"
echo "Secondary Disk : $DISK2"

###############################################################################
# Partition Naming
###############################################################################

partition_suffix() {

    case "$1" in
        *nvme*|*mmcblk*)
            echo "p"
            ;;
        *)
            echo ""
            ;;
    esac
}

SFX1=$(partition_suffix "$DISK1")
SFX2=$(partition_suffix "$DISK2")

BOOT1="${DISK1}${SFX1}2"
BOOT2="${DISK2}${SFX2}2"

ROOT1="${DISK1}${SFX1}3"
ROOT2="${DISK2}${SFX2}3"

echo
echo "Boot RAID Members"
echo "-----------------"
echo "$BOOT1"
echo "$BOOT2"

echo
echo "LVM RAID Members"
echo "----------------"
echo "$ROOT1"
echo "$ROOT2"

###############################################################################
# Verify RAID Member Partitions
###############################################################################

for PART in \
    "$BOOT1" \
    "$BOOT2" \
    "$ROOT1" \
    "$ROOT2"
do

    if [ ! -b "$PART" ]; then
        echo "ERROR: Missing partition $PART"
        exit 1
    fi

done

###############################################################################
# Detect EFI Partitions
###############################################################################

echo
echo "Locating EFI System Partitions..."

mkdir -p /boot/efi
mkdir -p /mnt/efi-secondary

EFI_MOUNTED_BY_SCRIPT=0

PRIMARY_EFI=$(mount | awk '$3=="/boot/efi"{print $1}' | head -1)

if [ -z "$PRIMARY_EFI" ]; then

    PRIMARY_EFI=""

    for dev in $(blkid -t TYPE=vfat -o device)
    do
        mount "$dev" /boot/efi 2>/dev/null || continue
    
        if [ -f /boot/efi/EFI/centos/shimx64.efi ]
        then
            PRIMARY_EFI="$dev"
            break
        fi
    
        umount /boot/efi
    
    done
    
    [ -z "$PRIMARY_EFI" ] && {
        echo "No valid EFI partition found."
        exit 1
    }

fi

SECONDARY_EFI=$(blkid -t TYPE=vfat -o device \
    | grep -v "^${PRIMARY_EFI}$" \
    | head -1)

if [ -z "$PRIMARY_EFI" ]; then
    echo
    echo "ERROR: Unable to locate primary EFI partition."
    blkid
    exit 1
fi

if [ -z "$SECONDARY_EFI" ]; then
    echo
    echo "ERROR: Unable to locate secondary EFI partition."
    blkid
    exit 1
fi

echo
echo "Primary EFI   : $PRIMARY_EFI"
echo "Secondary EFI : $SECONDARY_EFI"

if ! mountpoint -q /boot/efi; then
    mount "$PRIMARY_EFI" /boot/efi
    EFI_MOUNTED_BY_SCRIPT=1
fi

if ! mountpoint -q /mnt/efi-secondary; then
    mount "$SECONDARY_EFI" /mnt/efi-secondary
fi

echo
echo "EFI partitions mounted successfully."

###############################################################################
# Verify EFI Bootloader
###############################################################################

echo
echo "Verifying EFI bootloader..."

if [ ! -f /boot/efi/EFI/centos/shimx64.efi ]; then
    echo "ERROR: shimx64.efi not found."
    exit 1
fi

if [ ! -f /boot/efi/EFI/centos/grubx64.efi ]; then
    echo "ERROR: grubx64.efi not found."
    exit 1
fi

###############################################################################
# Synchronize Secondary EFI Partition
###############################################################################

echo
echo "Synchronizing EFI partitions..."

rsync -a --delete \
    /boot/efi/ \
    /mnt/efi-secondary/

sync


###############################################################################
# Create Fallback Bootloader
###############################################################################

echo
echo "Creating fallback EFI bootloader..."

mkdir -p /boot/efi/EFI/BOOT
mkdir -p /mnt/efi-secondary/EFI/BOOT


cp -af \
    /boot/efi/EFI/centos/shimx64.efi \
    /boot/efi/EFI/BOOT/BOOTX64.EFI

cp -af \
    /boot/efi/EFI/centos/grubx64.efi \
    /boot/efi/EFI/BOOT/grubx64.efi

cp -af \
    /mnt/efi-secondary/EFI/centos/shimx64.efi \
    /mnt/efi-secondary/EFI/BOOT/BOOTX64.EFI

cp -af \
    /mnt/efi-secondary/EFI/centos/grubx64.efi \
    /mnt/efi-secondary/EFI/BOOT/grubx64.efi

sync

###############################################################################
# Save RAID Configuration
###############################################################################

echo
echo "Saving mdadm configuration..."

mdadm --detail --scan > /etc/mdadm.conf

###############################################################################
# Configure Verbose Boot
###############################################################################

echo
echo "Configuring verbose boot..."

# Backup GRUB defaults
if [ -f /etc/default/grub ]; then
    cp -an /etc/default/grub /etc/default/grub.bak
fi

# Remove graphical boot arguments
if [ -f /etc/default/grub ]; then
    sed -i \
        -e 's/\<rhgb\>//g' \
        -e 's/\<quiet\>//g' \
        -e 's/  */ /g' \
        -e 's/" "/"/g' \
        /etc/default/grub
fi

# Ensure GRUB timeout is visible
if grep -q '^GRUB_TIMEOUT=' /etc/default/grub; then
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub
else
    echo 'GRUB_TIMEOUT=5' >> /etc/default/grub
fi

# Regenerate GRUB configuration
if [ -d /sys/firmware/efi ]; then
    mountpoint -q /boot/efi || mount "$PRIMARY_EFI" /boot/efi
	grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
else
    grub2-mkconfig -o /boot/grub2/grub.cfg
fi

# Update all installed kernels
grubby --update-kernel=ALL --remove-args="rhgb quiet" || true

###############################################################################
# Rebuild initramfs
###############################################################################

echo
echo "Rebuilding initramfs..."

if [ -d /lib/modules ]; then
    KERNEL=$(ls /lib/modules | sort -V | tail -1)

    if [ -f "/lib/modules/${KERNEL}/modules.dep" ]; then
        dracut -f "/boot/initramfs-${KERNEL}.img" "${KERNEL}" || \
            echo "WARNING: dracut failed."
    else
        echo "Skipping dracut (modules.dep not yet available)."
    fi
fi

###############################################################################
# Verification
###############################################################################

echo
echo "=============================================================="
echo " Verification"
echo "=============================================================="

echo
echo "Current RAID Status"
cat /proc/mdstat || true

echo
echo "Block Devices"
lsblk -f || true

echo
echo "Mounted Filesystems"
mount | grep -E 'boot|efi|md' || true

echo
echo "EFI Boot Entries"
efibootmgr -v || true

echo
echo "Primary EFI Contents"
find /boot/efi/EFI -maxdepth 3 -type f | sort || true

echo
echo "Secondary EFI Contents"
find /mnt/efi-secondary/EFI -maxdepth 3 -type f | sort || true

###############################################################################
# Verify EFI Synchronization
###############################################################################

echo
echo "Verifying EFI synchronization..."

if diff -rq /boot/efi /mnt/efi-secondary >/dev/null
then
    echo "EFI synchronization verified."
else
    echo "WARNING: EFI partitions differ!"
fi

###############################################################################
# Flush Filesystems
###############################################################################

echo
echo "Synchronizing filesystems..."

sync
sync

###############################################################################
# Cleanup
###############################################################################

echo
echo "Cleaning up..."

# Unmount temporary mount point
if mountpoint -q /mnt/efi-secondary; then
    umount /mnt/efi-secondary || true
fi

# Unmount /boot/efi if we mounted it
if [ "$EFI_MOUNTED_BY_SCRIPT" -eq 1 ]; then
    umount /boot/efi || true
fi
rmdir /mnt/efi-secondary 2>/dev/null || true

sync


###############################################################################
# Final Summary
###############################################################################

echo
echo "=============================================================="
echo " Dual UEFI Boot Configuration Completed Successfully"
echo "=============================================================="

echo
echo "Installation Disks"
echo "------------------"
echo "Primary Disk   : $DISK1"
echo "Secondary Disk : $DISK2"

echo
echo "EFI Partitions"
echo "--------------"
echo "Primary EFI    : $PRIMARY_EFI"
echo "Secondary EFI  : $SECONDARY_EFI"

echo
echo "RAID Status"
echo "-----------"
cat /proc/mdstat || true

echo
echo "Boot Order"
echo "----------"
efibootmgr | grep BootOrder || true

echo
echo "CentOS Boot Entries"
echo "-------------------"
efibootmgr | grep "CentOS RAID1" || true


echo
echo "GRUB configuration completed successfully."

exit 0
