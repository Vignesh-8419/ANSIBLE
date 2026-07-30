# CentOS 7 UEFI RAID1 Recovery SOP
## Enterprise Golden Image Recovery Guide
**Platform:** CentOS 7.9
**Boot Mode:** UEFI
**Partitioning:** GPT
**RAID:** Software RAID1 (mdadm)
**Volume Manager:** LVM

---

# Scenario 1: Disk 1 (sda) Failure Recovery

## Step 1 - Verify Failed Disk

```bash
lsblk
cat /proc/mdstat
```

Expected:

```
md0 : [_U]
md1 : [_U]
```

or

```
md0 : [U_]
md1 : [U_]
```

depending on which disk failed.

---

## Step 2 - Shutdown VM

```bash
shutdown -h now
```

Replace the failed **Disk 1 (sda)** with a new disk of equal or larger capacity.

Power on the VM.

---

## Step 3 - Verify New Disk

```bash
lsblk
```

Example:

```
sda   100G
sdb   100G
```

New disk should have no partitions.

---

## Step 4 - Replicate Partition Table

```bash
sgdisk --replicate=/dev/sda /dev/sdb
```

---

## Step 5 - Generate New Disk GUID

```bash
sgdisk -G /dev/sda
```

---

## Step 6 - Reload Partition Table

```bash
partprobe /dev/sda
udevadm settle
```

Verify:

```bash
lsblk
```

Expected:

```
sda1
sda2
sda3
```

---

## Step 7 - Add RAID Members

```bash
mdadm --add /dev/md0 /dev/sda2
mdadm --add /dev/md1 /dev/sda3
```

---

## Step 8 - Create EFI Filesystem

```bash
mkfs.vfat -F32 /dev/sda1
```

---

## Step 9 - Copy EFI Bootloader

Create mount points:

```bash
mkdir -p /mnt/efi-src
mkdir -p /mnt/efi-dst
```

Mount working EFI partition:

```bash
mount /dev/sdb1 /mnt/efi-src
```

Mount new EFI partition:

```bash
mount /dev/sda1 /mnt/efi-dst
```

Copy EFI files:

```bash
cp -a /mnt/efi-src/EFI /mnt/efi-dst/
sync
```

Verify:

```bash
find /mnt/efi-dst/EFI -type f | sort
```

---

## Step 10 - Monitor RAID Rebuild

```bash
watch cat /proc/mdstat
```

Wait until:

```
md0 : [UU]
md1 : [UU]
```

---

## Step 11 - Save RAID Configuration

```bash
mdadm --detail --scan > /etc/mdadm.conf
```

---

## Step 12 - Verify

```bash
lsblk
cat /proc/mdstat
efibootmgr -v
```

Expected:

```
md0 : [UU]
md1 : [UU]
```

Both disks synchronized.

---

# Scenario 2: Disk 2 (sdb) Failure Recovery

## Step 1 - Verify Failed Disk

```bash
lsblk
cat /proc/mdstat
```

Expected:

```
md0 : [_U]
md1 : [_U]
```

or

```
md0 : [U_]
md1 : [U_]
```

---

## Step 2 - Shutdown VM

```bash
shutdown -h now
```

Replace failed **Disk 2 (sdb)**.

Power on VM.

---

## Step 3 - Verify New Disk

```bash
lsblk
```

Expected:

```
sdb
```

without partitions.

---

## Step 4 - Replicate Partition Table

```bash
sgdisk --replicate=/dev/sdb /dev/sda
```

---

## Step 5 - Generate New Disk GUID

```bash
sgdisk -G /dev/sdb
```

---

## Step 6 - Reload Partition Table

```bash
partprobe /dev/sdb
udevadm settle
```

Verify:

```bash
lsblk
```

Expected:

```
sdb1
sdb2
sdb3
```

---

## Step 7 - Add RAID Members

```bash
mdadm --add /dev/md0 /dev/sdb2
mdadm --add /dev/md1 /dev/sdb3
```

---

## Step 8 - Create EFI Filesystem

```bash
mkfs.vfat -F32 /dev/sdb1
```

---

## Step 9 - Copy EFI Bootloader

Create mount points:

```bash
mkdir -p /mnt/efi-src
mkdir -p /mnt/efi-dst
```

Mount working EFI partition:

```bash
mount /dev/sda1 /mnt/efi-src
```

Mount new EFI partition:

```bash
mount /dev/sdb1 /mnt/efi-dst
```

Copy EFI:

```bash
cp -a /mnt/efi-src/EFI /mnt/efi-dst/
sync
```

Verify:

```bash
find /mnt/efi-dst/EFI -type f | sort
```

---

## Step 10 - Monitor RAID Rebuild

```bash
watch cat /proc/mdstat
```

Wait until:

```
md0 : [UU]
md1 : [UU]
```

---

## Step 11 - Save RAID Configuration

```bash
mdadm --detail --scan > /etc/mdadm.conf
```

---

## Step 12 - Verify

```bash
lsblk
cat /proc/mdstat
efibootmgr -v
```

Expected:

```
md0 : [UU]
md1 : [UU]
```

---

# Post-Recovery Validation

Verify RAID:

```bash
cat /proc/mdstat
```

Expected:

```
md0 : [UU]
md1 : [UU]
```

Verify disks:

```bash
lsblk
```

Verify EFI contents:

```bash
mkdir -p /mnt/test

mount /dev/sda1 /mnt/test
find /mnt/test/EFI -type f | sort
umount /mnt/test

mount /dev/sdb1 /mnt/test
find /mnt/test/EFI -type f | sort
umount /mnt/test
```

Verify boot entries:

```bash
efibootmgr -v
```

Verify mdadm:

```bash
mdadm --detail /dev/md0
mdadm --detail /dev/md1
```

Verify LVM:

```bash
pvs
vgs
lvs
```

Verify Filesystems:

```bash
df -h
```

---

# Recovery Completed Successfully

Successful recovery is confirmed when:

- ✅ Both RAID arrays show `[UU]`
- ✅ Both EFI partitions contain identical bootloader files
- ✅ Both disks have GPT partition tables
- ✅ LVM volumes are active
- ✅ System boots successfully with either disk removed
- ✅ `efibootmgr -v` shows valid UEFI boot entries
- ✅ `/boot`, `/`, `/home`, `/var`, and `swap` are functioning normally
