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
```bash
# 1. Rebuild the /boot array partition
mdadm --manage /dev/md1 --add /dev/sdb1

# 2. Rebuild the root LVM storage array partition
mdadm --manage /dev/md0 --add /dev/sdb3
```

### Step 3: Monitor Data Rebuild Progress
```bash
watch -n 1 cat /proc/mdstat
```
*Wait until both arrays show `[UU]` and the status reads `active` with no recovery percentage lines remaining.*

### Step 4: Re-Synchronize the Secondary Backup EFI Payload
```bash
# 1. Run the system sync script manually
/usr/local/sbin/sync-esp.sh

# 2. Force-register the "Rocky Backup" motherboard variable if it dropped out
if [ -d /sys/firmware/efi/efivars ]; then
    efibootmgr -c -d /dev/sdb -p 2 -L "Rocky Backup" -l '\EFI\rocky\shimx64.efi' || true
fi

# 3. Restart the tracking service state to ensure it resets cleanly
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
```bash
# 1. Format sda1 as FAT32
mkfs.vfat -F32 -n "EFI-SYSTEM" /dev/sda1

# 2. Mount it temporarily to seed bootloader binaries
mkdir -p /tmp/sda1
mount /dev/sda1 /tmp/sda1

# 3. Copy the clean bootloader directory path tree over from your live sdb2 mount
mkdir -p /tmp/sda1/EFI
rsync -ahrlptD --delete /boot/efi/EFI/ /tmp/sda1/EFI/

# 4. Unmount the recovery mountpoint cleanly
sync
umount /tmp/sda1
rmdir /tmp/sda1
```

### Step 5: Restore Motherboard UEFI Primary Boot Option Pointers
```bash
if [ -d /sys/firmware/efi/efivars ]; then
    efibootmgr -c -d /dev/sda -p 1 -L "Rocky Linux" -l '\EFI\rocky\shimx64.efi'
fi
```

---

## 🔍 Post-Recovery Health Check Matrix
```bash
# Must return [UU] status on all arrays
cat /proc/mdstat

# Must display both "Rocky Linux" (sda1) and "Rocky Backup" (sdb2)
efibootmgr -v
```
