# Ubuntu 24.04 RAID1 Recovery & Validation Guide

This document describes the complete recovery procedure for a two-disk Ubuntu 24.04 system configured with:

- UEFI Boot
- Dual EFI System Partitions
- RAID1 `/boot`
- RAID1 LVM
- Root filesystem on LVM

---

# Architecture

```
                Ubuntu 24.04 RAID1 Layout

             +-------------------------------+
             |         UEFI Firmware         |
             +---------------+---------------+
                             |
         +-------------------+-------------------+
         |                                       |
     Disk 1 (sda)                           Disk 2 (sdb)
         |                                       |
    EFI (FAT32)                            EFI (FAT32)
         |                                       |
         +---------- Boot Failover --------------+
                       (Identical EFI)

    /boot (RAID1 md0)                  /boot (RAID1 md0)

    LVM PV (RAID1 md1)                 LVM PV (RAID1 md1)
              |                                  |
              +---------------+------------------+
                              |
                        Ubuntu Volume Group
                              |
                      +-------+--------+
                      |                |
                     Root             Swap
```

The EFI System Partition (ESP) is **NOT** part of RAID1 because UEFI firmware cannot read Linux Software RAID.

Instead, each disk has its own FAT32 EFI partition containing identical bootloader files.

---

# Recovery Workflow

The recovery procedure is identical regardless of whether **Disk 1 (sda)** or **Disk 2 (sdb)** fails.

Simply replace the failed disk and substitute the correct device names.

---

# Scenario 1

Recovering **Disk 1 (sda)**

Healthy disk:

```
sdb
```

Replacement disk:

```
sda
```

---

# Scenario 2

Recovering **Disk 2 (sdb)**

Healthy disk:

```
sda
```

Replacement disk:

```
sdb
```

---

# Step 1 - Detect Replacement Disk

Rescan the SCSI bus.

```bash
for host in /sys/class/scsi_host/host*; do
    echo "- - -" > "$host/scan"
done
```

Verify.

```bash
lsblk
```

Example:

```
sda
sdb
```

---

# Step 2 - Clone GPT

Clone the partition table from the healthy disk.

## Recovering sda

```bash
sgdisk --backup=/tmp/sdb-gpt.bin /dev/sdb
sgdisk --load-backup=/tmp/sdb-gpt.bin /dev/sda
sgdisk -G /dev/sda
partprobe /dev/sda
```

## Recovering sdb

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

# Step 3 - Create EFI Filesystem

Recovering **sda**

```bash
mkfs.vfat -F32 /dev/sda1
```

Recovering **sdb**

```bash
mkfs.vfat -F32 /dev/sdb1
```

---

# Step 4 - Rebuild RAID

Recovering **sda**

```bash
mdadm --add /dev/md0 /dev/sda2
mdadm --add /dev/md1 /dev/sda3
```

Recovering **sdb**

```bash
mdadm --add /dev/md0 /dev/sdb2
mdadm --add /dev/md1 /dev/sdb3
```

Monitor rebuild.

```bash
watch cat /proc/mdstat
```

Continue only when:

```
md0 [UU]

md1 [UU]
```

---

# Step 5 - Restore EFI

## 5.1 Verify Existing EFI Mounts

```bash
mount | grep efi
```

Typical output:

```
/dev/sda1 on /boot/efi
```

or

```
/dev/sdb1 on /boot/efi
```

If `/boot/efi` is already mounted, **do not mount it again**.

---

## 5.2 Mount Replacement EFI

Create mount point.

```bash
mkdir -p /mnt/efi2
```

Recovering **sda**

```bash
mount /dev/sda1 /mnt/efi2
```

Recovering **sdb**

```bash
mount /dev/sdb1 /mnt/efi2
```

Verify.

```bash
mount | grep efi
```

Expected:

```
/boot/efi
/mnt/efi2
```

---

## 5.3 Verify Source EFI

Ensure the source EFI contains boot files.

```bash
find /boot/efi -maxdepth 3 -type f
```

Expected example:

```
/boot/efi/EFI/BOOT/BOOTX64.EFI
```

or

```
/boot/efi/EFI/ubuntu/shimx64.efi
/boot/efi/EFI/ubuntu/grubx64.efi
```

If no files are listed, stop and investigate before continuing.

---

## 5.4 Install GRUB

```bash
grub-install \
    --target=x86_64-efi \
    --efi-directory=/mnt/efi2 \
    --bootloader-id=ubuntu \
    --removable \
    --recheck
```

Verify.

```bash
find /mnt/efi2/EFI -maxdepth 2 -type f
```

---

## 5.5 Synchronize EFI

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

---

## 5.6 Cleanup

```bash
umount /mnt/efi2
```

> Do **not** unmount `/boot/efi` if it was already mounted by the operating system.

---

# Step 6 - Validation

Verify RAID.

```bash
cat /proc/mdstat
```

Expected:

```
md0 [UU]

md1 [UU]
```

Verify boot entries.

```bash
efibootmgr -v
```

Verify disks.

```bash
lsblk
```

---

# Step 7 - Boot Failover Validation

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

efibootmgr -v
```

Expected:

Recovering **sda**

```
md0 [U_]

md1 [U_]
```

Recovering **sdb**

```
md0 [_U]

md1 [_U]
```

If the system boots successfully, the recovery is complete.

---

# Post-Patch EFI Synchronization

Whenever Ubuntu updates any of the following:

- Linux Kernel
- GRUB
- shim
- EFI bootloader packages

Synchronize the secondary EFI partition.

Verify current mounts.

```bash
mount | grep efi
```

Mount the secondary EFI if required.

```bash
mkdir -p /mnt/efi2
mount /dev/sdb1 /mnt/efi2
```

(or `/dev/sda1` depending on which disk is secondary)

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

diff -rq /boot/efi /mnt/efi2

umount /mnt/efi2
```

No output from `diff` indicates both EFI partitions are identical.

---

# Final Validation Checklist

| Validation | Expected |
|------------|----------|
| RAID Healthy | md0 [UU], md1 [UU] |
| EFI Source Mounted | PASS |
| EFI Destination Mounted | PASS |
| Source EFI Contains Boot Files | PASS |
| GRUB Installed Successfully | PASS |
| EFI Synchronization | PASS |
| `diff -rq` Returns No Output | PASS |
| UEFI Boot Entries Present | PASS |
| Boot Using Disk 1 Only | PASS |
| Boot Using Disk 2 Only | PASS |
| RAID Rebuild Successful | PASS |
| Full Recovery Validated | PASS |

---

# Important Notes

- Always wait for RAID rebuild to complete before restoring EFI.
- Never assume `/boot/efi` is unmounted. Check first using `mount | grep efi`.
- Never assume the bootloader is stored under `EFI/ubuntu`; some installations use only `EFI/BOOT`.
- Always verify the source EFI contains boot files before running `rsync`.
- Always run `sync` before unmounting the destination EFI.
- Always verify synchronization using:

```bash
diff -rq /boot/efi /mnt/efi2
```

No output indicates both EFI partitions are identical.
