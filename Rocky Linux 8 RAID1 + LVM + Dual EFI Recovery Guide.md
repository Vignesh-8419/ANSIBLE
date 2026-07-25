# 🛠️ Rocky Linux 8 RAID1 + LVM + Dual EFI Recovery Guide

This document provides step-by-step restoration instructions for both failure scenarios: when the secondary disk (`sdb`) is blank/replaced, or when the primary disk (`sda`) is blank/replaced.

---

## 📋 Scenario A: Rebuilding when Drive 2 (`sdb`) Fails or is Replaced

*Use these instructions if `sda` is active, and `sdb` is a raw, blank drive.*

### Step 1: Copy Partition Table Structure from `sda` to `sdb`
```bash
# 1. Replicate GPT layout from sda to sdb
sgdisk /dev/sda -R /dev/sdb

# 2. Randomize GUIDs on the newly partitioned sdb drive
sgdisk -G /dev/sdb

# 3. Inform the kernel of the new partition map
partprobe /dev/sdb
udevadm settle
```

### Step 2: Re-add Partitions to the Active Software RAID Arrays
Due to Anaconda's partition slot assignments, you must add **sdb2** to the `/boot` array (`md1`) and **sdb3** to the root LVM storage array (`md0`).
```bash
# 1. Rebuild the /boot array partition using sdb2
mdadm --manage /dev/md1 --add /dev/sdb2

# 2. Rebuild the root LVM storage array partition using sdb3
mdadm --manage /dev/md0 --add /dev/sdb3
```

### Step 3: Monitor Data Rebuild Progress
```bash
watch -n 1 cat /proc/mdstat
```
*Wait until both arrays show `[UU]` and the status reads `active` with no recovery percentage lines remaining.*

### Step 4: Format and Synchronize the Secondary Backup EFI Payload
On this layout, `sdb1` is the raw 600M standalone partition slice that holds your backup bootloader files.

```bash
# 1. CRITICAL: Purge low-level block layer device caches and drop phantom memory locks
umount -l /boot/efi2 2>/dev/null || true
blkid -g
partprobe /dev/sdb
udevadm settle
wipefs -af /dev/sdb1

# 2. Format the sdb1 partition fresh as a clean FAT32 filesystem
mkfs.vfat -F32 -s 2 -n "EFI-BACKUP" /dev/sdb1

# 3. FIXED: Ensure the master primary EFI partition is mounted and populated before running sync
if ! mountpoint -q /boot/efi; then
    mount -t vfat /dev/sda1 /boot/efi
fi

# 4. FIXED: If the directory tree was dropped during failure, regenerate files from system cache
if [ ! -d /boot/efi/EFI/rocky ]; then
    mkdir -p /boot/efi/EFI/rocky /boot/efi/EFI/BOOT
    dnf reinstall -y grub2-efi-x64 shim-x64
    cp /boot/efi/EFI/rocky/shimx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI
    cp /boot/efi/EFI/rocky/grubx64.efi /boot/efi/EFI/BOOT/grubx64.efi
    cp /boot/grub2/grub.cfg /boot/efi/EFI/rocky/
fi

# 5. Run the system sync script manually to mirror the boot directory and removable path fallback
/usr/local/sbin/sync-esp.sh
```

### Step 5: Restore Motherboard UEFI NVRAM Boot Pointers
```bash
if [ -d /sys/firmware/efi/efivars ]; then
    # Clear out any stale duplicate backup entries if present
    efibootmgr -b 0005 -B || true
    efibootmgr -b 0006 -B || true
    efibootmgr -b 0007 -B || true
    efibootmgr -b 0008 -B || true
    
    # Register the single clean tracking entry pointing to sdb1
    efibootmgr -c -d /dev/sdb -p 1 -L "Rocky Backup" -l '\EFI\rocky\shimx64.efi' || true
    
    # Enforce correct priority boot path ordering
    efibootmgr -o 0001,\$(efibootmgr | awk '/Rocky Backup/ {print substr(\$1,5,4); exit}'),0000,0002,0003,0004 || true
fi

# Restart the background tracking service state cleanly
systemctl reset-failed sync-esp.service
systemctl restart sync-esp.service
systemctl status sync-esp.service
```

---

## 📋 Scenario B: Rebuilding when Drive 1 (`sda`) Fails or is Replaced

*Use these instructions if the system booted automatically from `sdb`, and `sda` is a raw, blank drive.*

### Step 1: Copy Partition Table Structure from `sdb` to `sda`
```bash
# 1. Replicate GPT layout from sdb to sda
sgdisk /dev/sdb -R /dev/sda

# 2. Randomize GUIDs on the newly partitioned sda drive
sgdisk -G /dev/sda

# 3. Force kernel partition re-read
partprobe /dev/sda
udevadm settle
```

### Step 2: Re-add Partitions to the Active Software RAID Arrays
On `sda`, the partition mapping dictates that **sda2** joins the `/boot` array and **sda3** joins the root LVM storage array.
```bash
# 1. Re-add sda2 to the /boot RAID1 array (md1)
mdadm --manage /dev/md1 --add /dev/sda2

# 2. Re-add sda3 to the LVM storage RAID1 array (md0)
mdadm --manage /dev/md0 --add /dev/sda3
```

### Step 3: Monitor Data Rebuild Progress
```bash
watch -n 1 cat /proc/mdstat
```
*Wait until both arrays return to a healthy, fully operational `[UU]` state.*

### Step 4: Format and Setup the New Primary EFI Partition
Because the system is running off the backup drive, your active EFI directory tree is currently mounted directly at `/boot/efi2`.
```bash
# 1. CRITICAL: Purge low-level block layer device caches and drop phantom memory locks
blkid -g
blockdev --rereadpt /dev/sda
partprobe /dev/sda
udevadm settle
wipefs -af /dev/sda1

# 2. Format sda1 fresh as a standard FAT32 filesystem
mkfs.vfat -F32 -n "EFI-SYSTEM" /dev/sda1

# 3. Mount it temporarily to seed bootloader binaries
mkdir -p /tmp/sda1
mount -t vfat /dev/sda1 /tmp/sda1

# 4. FIXED: Verify master files exist on the active mount before replication
if [ ! -d /boot/efi2/EFI ]; then
    mount -t vfat /dev/sdb1 /boot/efi2 || true
fi

# 5. Copy the clean bootloader directory tree over from your live mount path
mkdir -p /tmp/sda1/EFI
rsync -ahrlptD --delete /boot/efi2/EFI/ /tmp/sda1/EFI/

# 6. Unmount the recovery mountpoint cleanly
sync
umount /tmp/sda1
rmdir /tmp/sda1
```

### Step 5: Restore Motherboard UEFI Primary Boot Option Pointers
```bash
if [ -d /sys/firmware/efi/efivars ]; then
    # Clear out any stale primary entries if present
    efibootmgr -b 0001 -B || true
    
    # Register the primary track target pointing to sda1
    efibootmgr -c -d /dev/sda -p 1 -L "Rocky Linux" -l '\EFI\rocky\shimx64.efi'
    
    # Enforce correct priority boot path ordering
    efibootmgr -o \$(efibootmgr | awk '/Rocky Linux/ {print substr(\$1,5,4); exit}'),0005,0000,0002,0003,0004 || true
fi
```

---

## 🔍 Post-Recovery Health Check Matrix
```bash
# Must return optimal [UU] status on all arrays
cat /proc/mdstat

# Must display both "Rocky Linux" and "Rocky Backup" paths side-by-side
efibootmgr -v
```
