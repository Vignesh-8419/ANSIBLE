# Ubuntu 24.04 RAID1 Recovery & Validation Guide

This document describes the complete recovery procedure for a two-disk RAID1 Ubuntu 24.04 system using UEFI, RAID1 `/boot`, RAID1 LVM, and dual EFI partitions.

---

# Scenario 1: Disk 1 (sda) Failure and Recovery

## Initial State

- Booted successfully with **only sdb connected**
- RAID degraded
- Replace failed disk with a new blank 100GB disk

---

## Step 1 - Rescan SCSI Bus

```bash
for host in /sys/class/scsi_host/host*; do
    echo "- - -" > "$host/scan"
done
```

Verify new disk:

```bash
lsblk
```

Expected:

```
sda   <-- new blank disk
sdb   <-- existing RAID member
```

---

## Step 2 - Clone Partition Table

```bash
sgdisk --backup=/tmp/sdb-gpt.bin /dev/sdb
sgdisk --load-backup=/tmp/sdb-gpt.bin /dev/sda
sgdisk -G /dev/sda
partprobe /dev/sda
```

Verify:

```bash
lsblk
```

Expected:

```
sda
├─sda1
├─sda2
└─sda3
```

---

## Step 3 - Create EFI Filesystem

```bash
mkfs.vfat -F32 /dev/sda1
```

---

## Step 4 - Rebuild RAID

```bash
mdadm --add /dev/md0 /dev/sda2
mdadm --add /dev/md1 /dev/sda3
```

Monitor rebuild:

```bash
watch cat /proc/mdstat
```

Wait until:

```
md0 [UU]
md1 [UU]
```

---

## Step 5 - Restore EFI

Mount both EFI partitions:

```bash
mount /boot/efi

mkdir -p /mnt/efi2

mount /dev/sda1 /mnt/efi2
```

Install GRUB:

```bash
grub-install \
    --target=x86_64-efi \
    --efi-directory=/mnt/efi2 \
    --bootloader-id=ubuntu \
    --removable \
    --recheck
```

Synchronize EFI:

```bash
rsync -aHAX --delete /boot/efi/ /mnt/efi2/
```

Create fallback bootloader:

```bash
mkdir -p /mnt/efi2/EFI/BOOT

cp -f /mnt/efi2/EFI/ubuntu/shimx64.efi \
      /mnt/efi2/EFI/BOOT/BOOTX64.EFI

cp -f /mnt/efi2/EFI/ubuntu/mmx64.efi \
      /mnt/efi2/EFI/BOOT/
```

Sync:

```bash
sync
```

Verify:

```bash
diff -rq /boot/efi /mnt/efi2
```

No output means success.

Unmount:

```bash
umount /mnt/efi2
```

---

## Step 6 - Validation

RAID

```bash
cat /proc/mdstat
```

Expected:

```
md0 [UU]
md1 [UU]
```

Verify EFI mount

```bash
mount | grep /boot/efi
```

Verify boot entries

```bash
efibootmgr -v
```

---

## Step 7 - Boot Validation

Shutdown

```bash
shutdown -h now
```

Disconnect **Disk 2 (sdb)**

Boot VM.

Verify:

```bash
lsblk

cat /proc/mdstat

mount | grep /boot/efi

efibootmgr -v
```

Expected:

```
md0 [U_]
md1 [U_]
```

Boot successful = PASS

---

# Scenario 2: Disk 2 (sdb) Failure and Recovery

## Initial State

- Booted successfully with **only sda connected**
- RAID degraded
- Replace failed disk with new blank disk

---

## Step 1 - Rescan

```bash
for host in /sys/class/scsi_host/host*; do
    echo "- - -" > "$host/scan"
done
```

Verify

```bash
lsblk
```

Expected

```
sda <-- existing disk

sdb <-- new blank disk
```

---

## Step 2 - Clone GPT

```bash
sgdisk --backup=/tmp/sda-gpt.bin /dev/sda
sgdisk --load-backup=/tmp/sda-gpt.bin /dev/sdb
sgdisk -G /dev/sdb
partprobe /dev/sdb
```

Verify

```bash
lsblk
```

---

## Step 3 - Create EFI

```bash
mkfs.vfat -F32 /dev/sdb1
```

---

## Step 4 - Rebuild RAID

```bash
mdadm --add /dev/md0 /dev/sdb2

mdadm --add /dev/md1 /dev/sdb3
```

Monitor

```bash
watch cat /proc/mdstat
```

Wait until

```
md0 [UU]

md1 [UU]
```

---

## Step 5 - Restore EFI

Mount

```bash
mount /boot/efi

mkdir -p /mnt/efi2

mount /dev/sdb1 /mnt/efi2
```

Install GRUB

```bash
grub-install \
    --target=x86_64-efi \
    --efi-directory=/mnt/efi2 \
    --bootloader-id=ubuntu \
    --removable \
    --recheck
```

Synchronize EFI

```bash
rsync -aHAX --delete /boot/efi/ /mnt/efi2/
```

Create fallback

```bash
mkdir -p /mnt/efi2/EFI/BOOT

cp -f /mnt/efi2/EFI/ubuntu/shimx64.efi \
      /mnt/efi2/EFI/BOOT/BOOTX64.EFI

cp -f /mnt/efi2/EFI/ubuntu/mmx64.efi \
      /mnt/efi2/EFI/BOOT/
```

Flush

```bash
sync
```

Validate

```bash
diff -rq /boot/efi /mnt/efi2
```

No output = PASS

Unmount

```bash
umount /mnt/efi2
```

---

## Step 6 - Validation

```bash
cat /proc/mdstat
```

Expected

```
md0 [UU]

md1 [UU]
```

EFI

```bash
mount | grep /boot/efi
```

Boot entries

```bash
efibootmgr -v
```

---

## Step 7 - Boot Validation

Shutdown

```bash
shutdown -h now
```

Disconnect **Disk 1 (sda)**

Boot VM

Verify

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

Boot successful = PASS

---

# Final Validation Checklist

| Check | Expected |
|--------|----------|
| RAID Status | md0 [UU], md1 [UU] |
| EFI Files | `diff -rq` returns no output |
| GRUB Installed | `grub-install` completed successfully |
| Boot Entries | Present in `efibootmgr -v` |
| Boot with only sda | PASS |
| Boot with only sdb | PASS |
| RAID rebuild | PASS |
| EFI synchronization | PASS |
| Single disk boot | PASS |
| Full recovery validated | PASS |

---

# Notes

- Always run `sync` before unmounting the EFI partition.
- Wait for RAID rebuild to complete before restoring EFI.
- If `/boot/efi` is not mounted, mount it before running `rsync`.
- After modifying `/etc/fstab`, run:

```bash
systemctl daemon-reload
```

to reload the updated configuration.
