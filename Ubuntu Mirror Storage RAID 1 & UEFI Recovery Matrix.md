# Ubuntu 24.04 RAID1 Recovery & Validation Guide

This document describes the complete recovery procedure for a two-disk RAID1 Ubuntu 24.04 system using:

- UEFI Boot
- Dual EFI System Partitions
- RAID1 `/boot`
- RAID1 LVM
- Root filesystem on LVM

---

# Recovery Architecture

```
Disk 1 (sda)                     Disk 2 (sdb)

EFI (FAT32)                      EFI (FAT32)
      │                                │
      └──────── Boot Failover ─────────┘

/boot (RAID1 md0)         /boot (RAID1 md0)

LVM PV (RAID1 md1)        LVM PV (RAID1 md1)
        │
        ▼
     Ubuntu VG
        │
        ├── /
        └── swap
```

The EFI partition is **NOT** part of RAID1 because UEFI firmware cannot read Linux Software RAID.

Instead, both EFI partitions contain identical boot files.

---

# Scenario 1 – Disk 1 (sda) Failure and Recovery

## Initial State

- Booted successfully using **Disk 2**
- RAID degraded
- Disk 1 replaced with a new blank disk

---

## Step 1 - Detect New Disk

Rescan the SCSI bus.

```bash
for host in /sys/class/scsi_host/host*; do
    echo "- - -" > "$host/scan"
done
```

Verify:

```bash
lsblk
```

Expected:

```
sda   <-- New Disk
sdb   <-- Existing Disk
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
├── sda1
├── sda2
└── sda3
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

Monitor:

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

### Mount EFI Partitions

Since the server is booted from **Disk 2**, mount the healthy EFI from **sdb1**.

```bash
mkdir -p /boot/efi
mount /dev/sdb1 /boot/efi

mkdir -p /mnt/efi2
mount /dev/sda1 /mnt/efi2
```

Verify:

```bash
mount | grep efi
```

Expected:

```
/dev/sdb1 on /boot/efi
/dev/sda1 on /mnt/efi2
```

---

### Verify Source EFI

```bash
find /boot/efi -maxdepth 3 -type f
```

Expected output similar to:

```
/boot/efi/EFI/BOOT/BOOTX64.EFI
```

or

```
/boot/efi/EFI/ubuntu/shimx64.efi
/boot/efi/EFI/ubuntu/grubx64.efi
```

If no files are displayed, stop and verify the correct EFI partition is mounted.

---

### Install GRUB

```bash
grub-install \
    --target=x86_64-efi \
    --efi-directory=/mnt/efi2 \
    --bootloader-id=ubuntu \
    --removable \
    --recheck
```

Verify:

```bash
find /mnt/efi2/EFI -maxdepth 2 -type f
```

---

### Synchronize EFI

```bash
rsync -aHAX --delete /boot/efi/ /mnt/efi2/
```

Flush writes.

```bash
sync
```

Verify:

```bash
diff -rq /boot/efi /mnt/efi2
```

Expected:

```
(no output)
```

Cleanup:

```bash
umount /mnt/efi2
umount /boot/efi
```

---

## Step 6 - Validation

Verify RAID.

```bash
cat /proc/mdstat
```

Expected:

```
md0 [UU]

md1 [UU]
```

Verify Boot Entries.

```bash
efibootmgr -v
```

---

## Step 7 - Boot Validation

Shutdown.

```bash
shutdown -h now
```

Disconnect **Disk 2**.

Boot the VM.

Verify:

```bash
lsblk

cat /proc/mdstat

efibootmgr -v
```

Expected:

```
md0 [U_]

md1 [U_]
```

Boot Successful = PASS

---

# Scenario 2 – Disk 2 (sdb) Failure and Recovery

## Initial State

- Booted successfully using **Disk 1**
- RAID degraded
- Disk 2 replaced with new blank disk

---

## Step 1 - Detect New Disk

```bash
for host in /sys/class/scsi_host/host*; do
    echo "- - -" > "$host/scan"
done
```

Verify.

```bash
lsblk
```

Expected:

```
sda <-- Existing Disk

sdb <-- New Disk
```

---

## Step 2 - Clone GPT

```bash
sgdisk --backup=/tmp/sda-gpt.bin /dev/sda

sgdisk --load-backup=/tmp/sda-gpt.bin /dev/sdb

sgdisk -G /dev/sdb

partprobe /dev/sdb
```

Verify.

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

Monitor.

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

### Mount EFI Partitions

Since the server is booted from **Disk 1**, mount the healthy EFI from **sda1**.

```bash
mkdir -p /boot/efi
mount /dev/sda1 /boot/efi

mkdir -p /mnt/efi2
mount /dev/sdb1 /mnt/efi2
```

Verify.

```bash
mount | grep efi
```

Expected:

```
/dev/sda1 on /boot/efi
/dev/sdb1 on /mnt/efi2
```

---

### Verify Source EFI

```bash
find /boot/efi -maxdepth 3 -type f
```

Expected output similar to:

```
/boot/efi/EFI/BOOT/BOOTX64.EFI
```

or

```
/boot/efi/EFI/ubuntu/shimx64.efi
/boot/efi/EFI/ubuntu/grubx64.efi
```

---

### Install GRUB

```bash
grub-install \
    --target=x86_64-efi \
    --efi-directory=/mnt/efi2 \
    --bootloader-id=ubuntu \
    --removable \
    --recheck
```

Verify:

```bash
find /mnt/efi2/EFI -maxdepth 2 -type f
```

---

### Synchronize EFI

```bash
rsync -aHAX --delete /boot/efi/ /mnt/efi2/
```

Flush writes.

```bash
sync
```

Verify.

```bash
diff -rq /boot/efi /mnt/efi2
```

Expected:

```
(no output)
```

Cleanup.

```bash
umount /mnt/efi2
umount /boot/efi
```

---

## Step 6 - Validation

Verify RAID.

```bash
cat /proc/mdstat
```

Expected:

```
md0 [UU]

md1 [UU]
```

Verify Boot Entries.

```bash
efibootmgr -v
```

---

## Step 7 - Boot Validation

Shutdown.

```bash
shutdown -h now
```

Disconnect **Disk 1**.

Boot the VM.

Verify:

```bash
lsblk

cat /proc/mdstat

efibootmgr -v
```

Expected:

```
md0 [_U]

md1 [_U]
```

Boot Successful = PASS

---

# Final Validation Checklist

| Check | Expected |
|--------|----------|
| RAID Healthy | md0 [UU], md1 [UU] |
| EFI Mounted Correctly | PASS |
| Source EFI Contains Boot Files | PASS |
| GRUB Installed Successfully | PASS |
| EFI Synchronization (`diff -rq`) | PASS |
| UEFI Boot Entries Present | PASS |
| Boot with only Disk 1 | PASS |
| Boot with only Disk 2 | PASS |
| RAID Rebuild Completed | PASS |
| Full Recovery Validated | PASS |

---

# Important Notes

- Never copy EFI files before RAID rebuild has completed.
- Always mount the healthy EFI partition explicitly.
- Do **not** rely on `/etc/fstab` during recovery.
- Always verify the source EFI contains boot files before running `rsync`.
- Always run `sync` before unmounting the EFI partition.
- Verify synchronization using:

```bash
diff -rq /boot/efi /mnt/efi2
```

No output indicates both EFI partitions are identical.
