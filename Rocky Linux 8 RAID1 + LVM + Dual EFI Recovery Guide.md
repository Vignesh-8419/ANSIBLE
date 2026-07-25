# 🛠️ Rocky Linux 8 RAID1 + LVM + Dual EFI Recovery Guide

This document provides step-by-step restoration instructions for both failure scenarios: when the secondary disk (`sdb`) is blank/replaced, or when the primary disk (`sda`) is blank/replaced.

---

## 📋 Scenario A: Rebuilding when Drive 2 (`sdb`) Fails / Replaced

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
# 1. CRITICAL: Force drop block layer metadata caches and clear installer signatures
partprobe /dev/sdb
udevadm settle
wipefs -af /dev/sdb1

# 2. Zero out block headers completely with direct sync options to delete phantom flags
dd if=/dev/zero of=/dev/sdb1 bs=512 count=20480 conv=fdatasync

# 3. Format the sdb1 partition fresh as a clean FAT32 filesystem
mkfs.vfat -F32 -s 2 -n "EFI-BACKUP" /dev/sdb1

# 4. Run the system sync script manually to mirror the boot directory
/usr/local/sbin/sync-esp.sh

# 5. Force-register the "Rocky Backup" entry into the motherboard NVRAM (targeting partition 1)
if [ -d /sys/firmware/efi/efivars ]; then
    # Clear out any stale duplicate backup entries if present
    efibootmgr -b 0006 -B || true
    efibootmgr -b 0007 -B || true
    efibootmgr -b 0008 -B || true
    
    # Register the single clean tracking entry
    efibootmgr -c -d /dev/sdb -p 1 -L "Rocky Backup" -l '\EFI\rocky\shimx64.efi' || true
    
    # Ensure correct boot priority (Primary Drive first, Fallback Drive second)
    efibootmgr -o 0005,0006,0000,0001,0002,0003,0004 || true
fi

# 6. Restart the tracking service state to ensure it resets cleanly
systemctl reset-failed sync-esp.service
systemctl restart sync-esp.service
systemctl status sync-esp.service
```

---

## 📋 Scenario B: Rebuilding when Drive 1 (`sda`) Fails / Replaced

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
*Wait until both arrays return to a healthy `[UU]` state.*

### Step 4: Format and Setup the New Primary EFI Partition
Because the system is running off `sdb`, your active EFI directory tree is currently mounted directly at `/boot/efi2` instead of `/boot/efi`.
```bash
# 1. CRITICAL: Force drop block layer metadata caches and clear installer signatures
partprobe /dev/sda
udevadm settle
wipefs -af /dev/sda1

# 2. Zero out block headers completely with direct sync options to delete phantom flags
dd if=/dev/zero of=/dev/sda1 bs=512 count=20480 conv=fdatasync

# 3. Format sda1 as FAT32
mkfs.vfat -F32 -s 2 -n "EFI-SYSTEM" /dev/sda1

# 4. Mount it temporarily to seed bootloader binaries
mkdir -p /tmp/sda1
mount /dev/sda1 /tmp/sda1

# 5. Copy the clean bootloader files from the active /boot/efi2 mount path
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
    # Clear out any stale entries if present
    efibootmgr -b 0005 -B || true
    
    # Register primary track target
    efibootmgr -c -d /dev/sda -p 1 -L "Rocky Linux" -l '\EFI\rocky\shimx64.efi'
    
    # Secure priority order
    efibootmgr -o 0005,0006,0000,0001,0002,0003,0004 || true
fi
```

---

## 🔍 Post-Recovery Health Check Matrix
```bash
# Must return [UU] status on all arrays
cat /proc/mdstat

# Must display both "Rocky Linux" (sda1) and "Rocky Backup" (sdb1)
efibootmgr -v
```
