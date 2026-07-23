# Ubuntu 24.04 LTS RAID1 Disk Recovery SOP (UEFI + Software RAID1 + LVM)

## Purpose

This document describes the complete procedure to recover a failed disk on an Ubuntu 24.04 server configured with:

- UEFI Boot
- Dual EFI System Partitions
- Software RAID1 (/boot)
- Software RAID1 (LVM PV)
- LVM Root Filesystem

This SOP has been fully validated on Ubuntu 24.04.3 LTS.

---

# Storage Layout

```
Disk 1 (Healthy)
----------------
sda1    EFI (FAT32)
sda2    md0 (/boot)
sda3    md1 (LVM)

Disk 2 (Replacement)
--------------------
sdb1    EFI (FAT32)
sdb2    md0 (/boot)
sdb3    md1 (LVM)
```

---

# Phase 1 - Detect Replacement Disk

Rescan storage.

```bash
for host in /sys/class/scsi_host/host*; do
    echo "- - -" > "$host/scan"
done

partprobe
```

Verify disks.

```bash
lsblk
```

Example immediately after replacing Disk2

```
NAME
sda
├── sda1
├── sda2
└── sda3

sdb
```

If the replacement disk has no partitions, continue.

---

# Phase 2 - Identify Healthy and Replacement Disk

Determine which EFI partition is currently mounted.

```bash
mount | grep /boot/efi
```

If nothing is returned,

the EFI partition is **not mounted**.

This can happen after booting with only one disk because the UUID stored in
`/etc/fstab` belongs to the old disk.

Determine the EFI partition.

```bash
blkid | grep vfat
```

Example

```
/dev/sda1
```

Mount it.

```bash
mkdir -p /boot/efi

mount /dev/sda1 /boot/efi
```

Verify.

```bash
mount | grep /boot/efi
```

Expected

```
/dev/sda1 on /boot/efi
```

---

Now determine disks.

If

```
/dev/sda1
```

is mounted,

Healthy disk

```
sda
```

Replacement disk

```
sdb
```

If

```
/dev/sdb1
```

is mounted,

Healthy disk

```
sdb
```

Replacement disk

```
sda
```

---

# Phase 3 - Clone GPT

Example (healthy disk = sda)

```bash
sgdisk --backup=/tmp/gpt.bin /dev/sda

sgdisk --load-backup=/tmp/gpt.bin /dev/sdb

sgdisk -G /dev/sdb

partprobe /dev/sdb
```

Verify.

```bash
lsblk
```

Expected

```
sdb1
sdb2
sdb3
```

---

# Phase 4 - Prepare Replacement Disk

Create EFI filesystem.

Example

```bash
mkfs.vfat -F32 /dev/sdb1
```

Verify.

```bash
blkid /dev/sdb1
```

Expected

```
TYPE="vfat"
```

---

Add RAID members.

```bash
mdadm --add /dev/md0 /dev/sdb2

mdadm --add /dev/md1 /dev/sdb3
```

Monitor rebuild.

```bash
watch cat /proc/mdstat
```

Wait until

```
md0 [UU]

md1 [UU]
```

Verify.

```bash
cat /proc/mdstat
```

Expected

```
md0 [UU]

md1 [UU]
```

Do **NOT** continue until rebuild finishes.

---

# Phase 5 - Restore EFI

Determine active EFI.

```bash
mount | grep /boot/efi
```

If active EFI is

```
/dev/sda1
```

Mount replacement EFI.

```bash
mkdir -p /mnt/efi2

mount /dev/sdb1 /mnt/efi2
```

If active EFI is

```
/dev/sdb1
```

Mount replacement EFI.

```bash
mkdir -p /mnt/efi2

mount /dev/sda1 /mnt/efi2
```

---

Verify the mount.

```bash
mount | grep efi
```

Expected

```
/dev/sda1 on /boot/efi

/dev/sdb1 on /mnt/efi2
```

**STOP** if both mount points refer to the same device.

---

Verify source EFI.

```bash
find /boot/efi -maxdepth 3 -type f
```

Expected

```
EFI/BOOT/BOOTX64.EFI

EFI/ubuntu/shimx64.efi

EFI/ubuntu/grubx64.efi
```

If nothing is displayed,

STOP.

---

Install GRUB.

```bash
grub-install \
    --target=x86_64-efi \
    --efi-directory=/mnt/efi2 \
    --bootloader-id=ubuntu \
    --removable \
    --recheck
```

Expected

```
Installation finished. No error reported.
```

Verify.

```bash
find /mnt/efi2/EFI -maxdepth 3 -type f
```

Synchronize.

```bash
rsync -aHAX --delete /boot/efi/ /mnt/efi2/

sync
```

Verify.

```bash
diff -rq /boot/efi /mnt/efi2
```

Expected

```
(no output)
```

Cleanup.

```bash
umount /mnt/efi2
```

---

# Phase 6 - Final Verification

Verify RAID.

```bash
cat /proc/mdstat
```

Expected

```
md0 [UU]

md1 [UU]
```

Verify storage.

```bash
lsblk
```

Verify EFI entries.

```bash
efibootmgr -v
```

Expected

Ubuntu boot entry.

---

# Phase 7 - Boot Failover Test

Shutdown.

```bash
shutdown -h now
```

Disconnect the healthy disk.

Boot using only the recovered disk.

Verify.

```bash
lsblk

cat /proc/mdstat

mount | grep /boot/efi

efibootmgr -v
```

Expected

```
md0 [_U]

md1 [_U]
```

or

```
md0 [U_]

md1 [U_]
```

Both are normal.

---

## IMPORTANT

After booting with only one disk,

Ubuntu **may not automatically mount** `/boot/efi`.

Check.

```bash
mount | grep /boot/efi
```

If nothing is returned,

identify the EFI partition.

```bash
blkid | grep vfat
```

Mount it manually.

Example

```bash
mount /dev/sda1 /boot/efi
```

Verify.

```bash
mount | grep /boot/efi
```

Then continue verification.

Reconnect the healthy disk.

Boot normally.

Verify.

```bash
cat /proc/mdstat
```

Expected

```
md0 [UU]

md1 [UU]
```

Recovery completed.

---

# Post-Patch EFI Synchronization

Run after updating:

- Kernel
- GRUB
- shim
- EFI packages

Verify `/boot/efi` is mounted.

```bash
mount | grep /boot/efi
```

If not mounted,

identify the EFI partition.

```bash
blkid | grep vfat
```

Mount it.

Example

```bash
mount /dev/sda1 /boot/efi
```

Determine inactive EFI.

If active EFI is

```
/dev/sda1
```

Mount

```bash
mkdir -p /mnt/efi2

mount /dev/sdb1 /mnt/efi2
```

If active EFI is

```
/dev/sdb1
```

Mount

```bash
mkdir -p /mnt/efi2

mount /dev/sda1 /mnt/efi2
```

Verify.

```bash
mount | grep efi
```

Install GRUB.

```bash
grub-install \
    --target=x86_64-efi \
    --efi-directory=/mnt/efi2 \
    --bootloader-id=ubuntu \
    --removable \
    --recheck
```

Synchronize.

```bash
rsync -aHAX --delete /boot/efi/ /mnt/efi2/

sync
```

Verify.

```bash
diff -rq /boot/efi /mnt/efi2
```

Expected

```
(no output)
```

Cleanup.

```bash
umount /mnt/efi2
```

---

# Recovery Checklist

- [ ] Replacement disk detected
- [ ] GPT cloned
- [ ] EFI filesystem created
- [ ] Replacement EFI verified as FAT32
- [ ] RAID rebuilt (`md0 [UU]`, `md1 [UU]`)
- [ ] `/boot/efi` mounted
- [ ] Replacement EFI mounted on `/mnt/efi2`
- [ ] Verified `/boot/efi` and `/mnt/efi2` are different devices
- [ ] GRUB installed on replacement EFI
- [ ] EFI synchronized
- [ ] `diff -rq` shows no differences
- [ ] `efibootmgr` shows Ubuntu boot entry
- [ ] Boot tested with recovered disk only
- [ ] Recovery completed successfully
