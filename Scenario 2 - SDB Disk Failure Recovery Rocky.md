# Rocky Linux 8.10 UEFI + Software RAID1 Recovery SOP
## SDB Failure Recovery (Disk2 Replacement)

---

# Purpose

This SOP describes the complete recovery procedure when **Disk2 (/dev/sdb)** has failed and has been replaced with a new disk.

Environment

- Rocky Linux 8.10
- UEFI Boot
- GPT Partition Table
- Software RAID1 (mdadm)
- LVM
- VMware ESXi / Physical Server

Disk Layout

| Disk | Partition | Purpose |
|------|-----------|---------|
| sda1 | EFI System Partition | FAT32 |
| sda2 | RAID1 (/boot) | md0 |
| sda3 | RAID1 (LVM PV) | md1 |
| sdb1 | EFI System Partition | FAT32 |
| sdb2 | RAID1 (/boot) | md0 |
| sdb3 | RAID1 (LVM PV) | md1 |

---

# Step 1 - Verify RAID Status

```bash
cat /proc/mdstat

mdadm --detail /dev/md0

mdadm --detail /dev/md1

lsblk
```

Expected

- md0 degraded
- md1 degraded
- /dev/sdb is missing or replaced

---

# Step 2 - Verify New Disk

```bash
lsblk

fdisk -l

lsscsi -g
```

Confirm

```
/dev/sda
/dev/sdb
```

are present.

---

# Step 3 - Copy Partition Table

Clone the GPT layout from Disk1.

```bash
sgdisk -R=/dev/sdb /dev/sda
```

Generate new GPT GUIDs on the replacement disk.

```bash
sgdisk -G /dev/sdb
```

Reload partition table.

```bash
partprobe /dev/sdb

udevadm settle
```

Verify

```bash
lsblk

fdisk -l /dev/sdb
```

---

# Step 4 - Rebuild RAID

Add boot partition.

```bash
mdadm --manage /dev/md0 --add /dev/sdb2
```

Add LVM partition.

```bash
mdadm --manage /dev/md1 --add /dev/sdb3
```

Monitor rebuild.

```bash
watch cat /proc/mdstat
```

Wait until:

```
[UU]
```

appears for both arrays.

Verify

```bash
cat /proc/mdstat

mdadm --detail /dev/md0

mdadm --detail /dev/md1
```

---

# Step 5 - Create EFI Filesystem

Format the EFI partition.

```bash
mkfs.vfat -F32 -n EFI-SYSTEM /dev/sdb1
```

Verify

```bash
blkid /dev/sdb1
```

Expected

```
TYPE="vfat"
```

---

# Step 6 - Copy EFI Files

Create mount points.

```bash
mkdir -p /mnt/sda1
mkdir -p /mnt/sdb1
```

Mount partitions.

```bash
mount /dev/sda1 /mnt/sda1

mount /dev/sdb1 /mnt/sdb1
```

Copy EFI files.

```bash
cp -a /mnt/sda1/* /mnt/sdb1/
```

Sync

```bash
sync
```

Verify.

```bash
find /mnt/sdb1/EFI
```

Expected

```
EFI/BOOT

EFI/rocky

shimx64.efi

grubx64.efi
```

Unmount.

```bash
umount /mnt/sda1

umount /mnt/sdb1
```

---

# Step 7 - Verify EFI Mount

Check if Linux has mounted the EFI System Partition.

```bash
findmnt /boot/efi
```

If nothing is returned:

Get the UUID of the primary EFI partition.

```bash
blkid /dev/sda1
```

Example

```
UUID="C642-C512"
```

Edit `/etc/fstab`.

```bash
vi /etc/fstab
```

Add

```fstab
UUID=C642-C512 /boot/efi vfat umask=0077,shortname=winnt 0 2
```

Reload systemd.

```bash
systemctl daemon-reload
```

Mount.

```bash
mkdir -p /boot/efi

mount -a
```

Verify.

```bash
findmnt /boot/efi
```

Expected

```
TARGET    SOURCE

/boot/efi /dev/sda1
```

---

# Step 8 - Verify UEFI Boot Entries

Display firmware boot entries.

```bash
efibootmgr -v
```

Verify that:

- Rocky Linux boot entries exist.
- Loader path points to:

```
\EFI\rocky\shimx64.efi
```

Check EFI partition identifiers.

```bash
blkid /dev/sda1

blkid /dev/sdb1
```

If a boot entry is missing completely, recreate it.

Example for Disk1:

```bash
efibootmgr \
-c \
-d /dev/sda \
-p 1 \
-L "Rocky Linux Disk1" \
-l '\EFI\rocky\shimx64.efi'
```

Example for Disk2:

```bash
efibootmgr \
-c \
-d /dev/sdb \
-p 1 \
-L "Rocky Linux Disk2" \
-l '\EFI\rocky\shimx64.efi'
```

Set boot order.

```bash
efibootmgr -o 0006,0007
```

(Replace the numbers with the actual boot entry IDs on your system.)

Verify.

```bash
efibootmgr -v
```

---

# Step 9 - Final RAID Verification

```bash
cat /proc/mdstat

lsblk

blkid

findmnt /boot/efi

efibootmgr -v
```

Expected

```
md0 [UU]

md1 [UU]
```

EFI mounted.

```
/boot/efi
```

Rocky boot entries present.

---

# Step 10 - Functional Boot Validation

## Test 1 - Boot from Disk1

1. Power off the VM/server.
2. Remove or disconnect Disk2 (/dev/sdb).
3. Boot the system.

Verify:

- System boots successfully.
- Login is possible.
- RAID is degraded as expected.

```bash
cat /proc/mdstat
```

---

## Test 2 - Boot from Disk2

1. Reconnect Disk2.
2. Disconnect Disk1 (/dev/sda).
3. Boot the system.

Verify:

- System boots successfully.
- Login is possible.
- RAID is degraded as expected.

```bash
cat /proc/mdstat
```

---

# Recovery Completed

Recovery is successful when:

- GPT copied successfully.
- New GUID generated.
- RAID rebuilt.
- md0 shows [UU].
- md1 shows [UU].
- EFI filesystem recreated.
- EFI files copied successfully.
- /boot/efi mounts successfully.
- Rocky UEFI boot entries exist.
- System boots using Disk1 only.
- System boots using Disk2 only.
- No RAID errors remain.

---
**Document Version:** 1.0  
**OS:** Rocky Linux 8.10  
**Boot Mode:** UEFI  
**Storage:** GPT + Software RAID1 + LVM
