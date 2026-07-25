# 🛠️ Rocky Linux 8 High-Availability Post-Installation Recovery Guide

This guide provides step-by-step restoration and mirror rebuilding procedures for your enterprise Software RAID1 system. Use these instructions when a physical disk fails or is replaced with a fresh, blank 100GB drive.

---

## 📋 Scenario A: Rebuilding when Drive 2 (`sdb`) Fails or is Replaced

*Use these instructions if your system is running safely on the primary disk (`sda`) and you have inserted a fresh, blank drive into the second slot (`sdb`).*

### Step 1: Clone Partition Table Structure from `sda` to `sdb`
Replicate the exact GUID Partition Table (GPT) geometry from the surviving disk to the blank disk and randomize the unique GUIDs.
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
Add the matching partition slices back into the degraded RAID pools to trigger an immediate online data resynchronization.
```bash
# 1. Re-add sdb2 to the /boot RAID1 array (md1)
mdadm --manage /dev/md1 --add /dev/sdb2

# 2. Re-add sdb3 to the main LVM storage RAID1 array (md0)
mdadm --manage /dev/md0 --add /dev/sdb3
```

### Step 3: Monitor Data Rebuild Progress
Track the live background replication progress until the percentage indicators drop off completely.
```bash
watch -n 1 cat /proc/mdstat
```
*Wait until both arrays show a healthy `[UU]` matrix block and the recovery lines are gone.*

### Step 4: Format and Synchronize the Secondary Backup EFI Payload
Clear the block layer cache, format the standalone 600MB slice (`sdb1`) as FAT32, and trigger the synchronization utility.
```bash
# 1. CRITICAL: Purge low-level block layer device caches and drop phantom memory locks
blkid -g
blockdev --rereadpt /dev/sdb
partprobe /dev/sdb
udevadm settle
wipefs -af /dev/sdb1

# 2. Format the sdb1 partition fresh as a clean FAT32 filesystem
mkfs.vfat -F32 -s 2 -n "EFI-BACKUP" /dev/sdb1

# 3. Run the system sync script manually to mirror the boot directory and removable path fallback
/usr/local/sbin/sync-esp.sh
```

### Step 5: Restore Motherboard UEFI NVRAM Boot Pointers
Clear out older ghost markers and register a single clean pointer for your backup drive targeting partition index 1.
```bash
if [ -d /sys/firmware/efi/efivars ]; then
    # Clear out any stale duplicate backup entries if present
    efibootmgr -b 0005 -B || true
    efibootmgr -b 0006 -B || true
    efibootmgr -b 0007 -B || true
    efibootmgr -b 0008 -B || true
    
    # Register the single clean tracking entry pointing to sdb1
    efibootmgr -c -d /dev/sdb -p 1 -L "Rocky Backup" -l '\EFI\rocky\shimx64.efi' || true
    
    # Ensure correct boot priority (Primary Drive first, Fallback Drive second)
    efibootmgr -o 0001,\$(efibootmgr | awk '/Rocky Backup/ {print substr(\$1,5,4)}'),0000,0002,0003,0004 || true
fi

# Restart the background tracking service state cleanly
systemctl reset-failed sync-esp.service
systemctl restart sync-esp.service
systemctl status sync-esp.service
```

---

## 📋 Scenario B: Rebuilding when Drive 1 (`sda`) Fails or is Replaced

*Use these instructions if your primary drive (`sda`) failed or was pulled, the system automatically booted hands-free from the backup disk, and you have inserted a fresh, blank drive into the primary slot.*

### Step 1: Clone Partition Table Structure from `sdb` to `sda`
Replicate the exact GPT schema from your surviving drive over to the new primary drive.
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
Rebuild the storage blocks across your operating system and data plane arrays.
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
Because the system is running off the backup drive, your active EFI directory tree is currently mounted directly at `/boot/efi2`. Format your new `sda1` slice and seed it.
```bash
# 1. CRITICAL: Purge low-level block layer device caches and drop phantom memory locks
blkid -g
blockdev --rereadpt /dev/sda
partprobe /dev/sda
udevadm settle
wipefs -af /dev/sda1

# 2. Format sda1 fresh as a standard FAT32 filesystem
mkfs.vfat -F32 -s 2 -n "EFI-SYSTEM" /dev/sda1

# 3. Mount it temporarily to seed bootloader binaries
mkdir -p /tmp/sda1
mount -t vfat /dev/sda1 /tmp/sda1

# 4. Copy the clean bootloader directory tree over from your live /boot/efi2 mount path
mkdir -p /tmp/sda1/EFI
rsync -ahrlptD --delete /boot/efi2/EFI/ /tmp/sda1/EFI/

# 5. Unmount the recovery mountpoint cleanly
sync
umount /tmp/sda1
rmdir /tmp/sda1
```

### Step 5: Restore Motherboard UEFI Primary Boot Option Pointers
Re-register your primary boot variable to partition index 1 on `sda` and reset your automated high-availability sequence.
```bash
if [ -d /sys/firmware/efi/efivars ]; then
    # Clear out any stale primary entries if present
    efibootmgr -b 0001 -B || true
    
    # Register the primary track target pointing to sda1
    efibootmgr -c -d /dev/sda -p 1 -L "Rocky Linux" -l '\EFI\rocky\shimx64.efi'
    
    # Secure the correct priority order
    efibootmgr -o \$(efibootmgr | awk '/Rocky Linux/ {print substr(\$1,5,4)}'),0005,0000,0002,0003,0004 || true
fi
```

---

## 🔍 Post-Recovery Health Check Matrix
Always run these two verification commands to guarantee your high-availability storage plane is completely healthy:
```bash
# Must return optimal [UU] status on all arrays
cat /proc/mdstat

# Must display both "Rocky Linux" and "Rocky Backup" paths side-by-side
efibootmgr -v
```
