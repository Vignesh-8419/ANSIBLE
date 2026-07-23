# Ubuntu24_RAID1_Recovery_SDB_Failure.md

# Ubuntu 24.04 LTS RAID1 Disk Recovery SOP
## Scenario 2 - Disk 2 (sdb) Failure

---

# Document Information

| Item | Value |
|------|-------|
| Operating System | Ubuntu Server 24.04.3 LTS |
| Boot Mode | UEFI |
| RAID | Linux Software RAID1 (mdadm) |
| Partition Table | GPT |
| Boot Loader | GRUB2 |
| Volume Manager | LVM2 |
| Tested Platform | VMware ESXi / VMware Workstation |
| Tested Kernel | 6.8.x |

---

# Purpose

This document describes the complete recovery procedure when **Disk 2 (sdb)** fails in a dual-disk Ubuntu 24.04 RAID1 server.

The procedure restores:

- GPT Partition Table
- EFI System Partition
- RAID1 /boot
- RAID1 LVM PV
- GRUB Bootloader
- EFI boot files

The procedure has been fully validated on Ubuntu 24.04.3 LTS.

---

# Storage Layout

## Original Configuration

```
                Ubuntu 24 RAID1

             +----------------------+
             |      UEFI BIOS       |
             +----------+-----------+
                        |
                EFI System Partition
                        |
                     GRUB2
                        |
                  RAID1 (/boot)
                    md0 (1.0)
                        |
                  Linux Kernel
                        |
                 RAID1 PV (md1)
                    Metadata 1.2
                        |
                      LVM VG
                        |
         +--------------+-------------+
         |                            |
       Root LV                    Swap LV
```

---

## Physical Disk Layout

### Disk1

```
sda
├── sda1   EFI
├── sda2   RAID1 (/boot)
└── sda3   RAID1 (LVM PV)
```

### Disk2

```
sdb
├── sdb1   EFI
├── sdb2   RAID1 (/boot)
└── sdb3   RAID1 (LVM PV)
```

---

# Failure Scenario

Disk2 fails completely.

```
Before Failure

sda
├── sda1
├── sda2
└── sda3

sdb
├── sdb1
├── sdb2
└── sdb3
```

↓

```
After Failure

sda
├── sda1
├── sda2
└── sda3

sdb
FAILED / REMOVED
```

↓

Server boots successfully using **Disk1 (sda)**.

↓

A new replacement disk is inserted.

↓

Linux detects

```
sda
├── sda1
├── sda2
└── sda3

sdb
(New Blank Disk)
```

This SOP begins from this point.

---

# Preconditions

Before beginning recovery, ensure:

- Ubuntu has booted successfully.
- Login as root.
- One RAID member is healthy.
- Replacement disk is equal to or larger than the failed disk.
- Replacement disk contains no required data.
- Current backups exist.

---

# Verify Current Status

Verify disks.

```bash
lsblk
```

Expected

```text
sda
├── sda1
├── sda2
└── sda3

sdb
```

---

Verify RAID.

```bash
cat /proc/mdstat
```

Expected

```text
md0
[U_]

md1
[U_]
```

or

```text
md0
[_U]

md1
[_U]
```

depending on which member is active.

---

Verify boot mode.

```bash
[ -d /sys/firmware/efi ] && echo UEFI || echo BIOS
```

Expected

```
UEFI
```

---

Verify /boot.

```bash
findmnt /boot
```

Expected

```
/dev/md0
```

---

Verify EFI mount.

```bash
mount | grep /boot/efi
```

Expected

```text
/dev/sda1 on /boot/efi
```

If nothing is returned, the EFI partition is not mounted and will be mounted later.

---

Recovery Phases

1. Detect replacement disk
2. Mount EFI
3. Clone GPT
4. Create EFI filesystem
5. Rebuild RAID
6. Restore EFI
7. Install GRUB
8. Synchronize EFI
9. Validate
10. Boot failover test

# Part 2 – Disk Replacement and RAID Recovery

---

# Phase 1 - Detect the Replacement Disk

Rescan the SCSI bus.

```bash
for host in /sys/class/scsi_host/host*; do
    echo "- - -" > "$host/scan"
done

partprobe
```

Verify.

```bash
lsblk
```

Expected

```text
NAME
sda
├── sda1
├── sda2
└── sda3

sdb
```

The replacement disk should appear as an empty disk.

---

# Phase 2 - Mount the EFI Partition

Check whether the EFI partition is already mounted.

```bash
mount | grep /boot/efi
```

---

## Case 1

Output

```text
/dev/sda1 on /boot/efi
```

The EFI partition is already mounted.

Continue to the next phase.

---

## Case 2

No output.

Identify the available EFI partition.

```bash
blkid | grep 'TYPE="vfat"'
```

Example

```text
/dev/sda1: UUID="9966-1547" TYPE="vfat"
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

```text
/dev/sda1 on /boot/efi
```

---

# Phase 3 - Clone the GPT Partition Table

Create a backup of the healthy disk's partition table.

```bash
sgdisk --backup=/tmp/gpt.bin /dev/sda
```

Restore it to the replacement disk.

```bash
sgdisk --load-backup=/tmp/gpt.bin /dev/sdb
```

Generate a new GPT Disk GUID.

```bash
sgdisk -G /dev/sdb
```

Reload the partition table.

```bash
partprobe /dev/sdb
```

Verify.

```bash
lsblk
```

Expected

```text
sda
├── sda1
├── sda2
└── sda3

sdb
├── sdb1
├── sdb2
└── sdb3
```

---

# Phase 4 - Create the EFI Filesystem

Format the EFI System Partition.

```bash
mkfs.vfat -F32 /dev/sdb1
```

Verify.

```bash
blkid /dev/sdb1
```

Expected

```text
TYPE="vfat"
```

---

# Phase 5 - Add RAID Members

Add the /boot RAID member.

```bash
mdadm --add /dev/md0 /dev/sdb2
```

Add the LVM RAID member.

```bash
mdadm --add /dev/md1 /dev/sdb3
```

---

# Phase 6 - Monitor RAID Synchronization

Monitor the rebuild.

```bash
watch cat /proc/mdstat
```

Wait until both arrays become healthy.

Expected

```text
md0 [UU]

md1 [UU]
```

Do **not** continue until the rebuild is complete.

---

Verify RAID.

```bash
cat /proc/mdstat
```

Expected

```text
Personalities : [raid1]

md0 : active raid1 sdb2 sda2
      [2/2] [UU]

md1 : active raid1 sdb3 sda3
      [2/2] [UU]
```

---

Verify storage.

```bash
lsblk
```

Expected

```text
sda
├── sda1
├── sda2
│   └── md0
└── sda3
    └── md1

sdb
├── sdb1
├── sdb2
│   └── md0
└── sdb3
    └── md1
```

---

At this stage:

- The replacement disk has been partitioned.
- The EFI partition has been formatted.
- Both RAID arrays have been rebuilt successfully.
- The new disk is synchronized with the RAID arrays.

# Part 3 – EFI Recovery and GRUB Installation

---

# Phase 7 - Restore the EFI Partition

At this point:

- RAID rebuilding has completed.
- `/dev/sdb1` contains a newly formatted FAT32 filesystem.
- `/dev/sda1` contains the working EFI System Partition.
- `/boot/efi` should be mounted from `/dev/sda1`.

Verify the current EFI mount.

```bash
mount | grep /boot/efi
```

Expected

```text
/dev/sda1 on /boot/efi
```

If there is **no output**, mount the EFI partition manually.

```bash
blkid | grep 'TYPE="vfat"'
```

Example

```text
/dev/sda1: UUID="9966-1547" TYPE="vfat"
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

```text
/dev/sda1 on /boot/efi
```

---

# Phase 8 - Mount the Replacement EFI Partition

Create a temporary mount point.

```bash
mkdir -p /mnt/efi2
```

Mount the replacement EFI partition.

```bash
mount /dev/sdb1 /mnt/efi2
```

Verify both mounts.

```bash
mount | grep efi
```

Expected

```text
/dev/sda1 on /boot/efi

/dev/sdb1 on /mnt/efi2
```

---

## IMPORTANT

Always verify that the source and destination are different.

Run

```bash
findmnt /boot/efi

findmnt /mnt/efi2
```

Expected

```text
TARGET      SOURCE
/boot/efi   /dev/sda1

TARGET      SOURCE
/mnt/efi2   /dev/sdb1
```

If both mount points reference the same block device,

STOP.

Unmount the incorrect mount and mount the correct partition.

---

# Phase 9 - Verify the Source EFI

Before installing GRUB, ensure that the source EFI contains boot files.

```bash
find /boot/efi -maxdepth 3 -type f
```

Expected

```text
EFI/BOOT/BOOTX64.EFI
EFI/BOOT/mmx64.efi
EFI/BOOT/fbx64.efi

EFI/ubuntu/grub.cfg
EFI/ubuntu/grubx64.efi
EFI/ubuntu/shimx64.efi
EFI/ubuntu/mmx64.efi
EFI/ubuntu/BOOTX64.CSV
```

If no files are displayed,

STOP.

The incorrect EFI partition is mounted.

---

# Phase 10 - Install GRUB

Install GRUB to the replacement EFI partition.

```bash
grub-install \
    --target=x86_64-efi \
    --efi-directory=/mnt/efi2 \
    --bootloader-id=ubuntu \
    --removable \
    --recheck
```

Expected

```text
Installing for x86_64-efi platform.

Installation finished. No error reported.
```

---

# Phase 11 - Verify GRUB Installation

Verify that GRUB files have been created.

```bash
find /mnt/efi2/EFI -maxdepth 3 -type f
```

Expected

```text
EFI/ubuntu/grubx64.efi
EFI/ubuntu/shimx64.efi
EFI/ubuntu/mmx64.efi
EFI/ubuntu/grub.cfg

EFI/BOOT/BOOTX64.EFI
EFI/BOOT/grubx64.efi
EFI/BOOT/mmx64.efi
```

---

# Phase 12 - Synchronize the EFI Partitions

Copy all EFI files from the healthy EFI to the replacement EFI.

```bash
rsync -aHAX --delete /boot/efi/ /mnt/efi2/

sync
```

---

# Phase 13 - Validate Synchronization

Compare both EFI partitions.

```bash
diff -rq /boot/efi /mnt/efi2
```

Expected

```text
(no output)
```

No output indicates that both EFI partitions are identical.

---

# Phase 14 - Cleanup

Unmount the temporary EFI mount.

```bash
umount /mnt/efi2
```

Verify.

```bash
mount | grep efi
```

Expected

```text
/dev/sda1 on /boot/efi
```

Only the active EFI partition should remain mounted.

---

# Phase 15 - Final Validation

Verify RAID.

```bash
cat /proc/mdstat
```

Expected

```text
md0 [UU]

md1 [UU]
```

Verify storage.

```bash
lsblk
```

Expected

```text
sda
├── sda1
├── sda2
└── sda3

sdb
├── sdb1
├── sdb2
└── sdb3
```

Verify UEFI boot entries.

```bash
efibootmgr -v
```

Expected

```text
Boot0000* ubuntu
```

or another valid Ubuntu boot entry.

At this point:

- GPT has been restored.
- The EFI System Partition has been recreated.
- GRUB has been installed.
- RAID has been rebuilt.
- The replacement disk is fully bootable.

# Part 4 – Boot Failover Testing, Troubleshooting, Post-Patch EFI Synchronization & Appendix

---

# Phase 16 - Boot Failover Test

The purpose of this test is to verify that the recovered **Disk2 (sdb)** can independently boot the operating system.

---

## Step 1 - Shutdown the Server

```bash
shutdown -h now
```

---

## Step 2 - Disconnect the Healthy Disk

Temporarily disconnect:

```
Disk1 (/dev/sda)
```

Leave only the recovered disk connected.

```
Connected

sdb

Disconnected

sda
```

---

## Step 3 - Boot the Server

Power on the server.

The server should boot normally from the recovered disk.

---

## Step 4 - Verify RAID Status

After login,

Run

```bash
cat /proc/mdstat
```

Expected

```text
md0
[U_]

md1
[U_]
```

or

```text
md0
[_U]

md1
[_U]
```

A degraded RAID is expected because only one disk is connected.

---

# Phase 17 - Verify EFI Mount

Run

```bash
mount | grep /boot/efi
```

---

## Case 1

Output

```text
/dev/sdb1 on /boot/efi
```

Everything is correct.

Proceed to validation.

---

## Case 2

No Output

This is a common situation after replacing the EFI partition because the UUID of the new FAT32 filesystem is different from the UUID stored in `/etc/fstab`.

Locate the EFI partition.

```bash
blkid | grep 'TYPE="vfat"'
```

Example

```text
/dev/sdb1: UUID="F090-25ED"
```

Mount it manually.

```bash
mkdir -p /boot/efi

mount /dev/sdb1 /boot/efi
```

Verify.

```bash
mount | grep /boot/efi
```

Expected

```text
/dev/sdb1 on /boot/efi
```

If required, update the UUID in `/etc/fstab` to ensure automatic mounting on future boots.

---

# Phase 18 - Verify EFI Contents

Verify that the EFI partition contains all required boot files.

```bash
find /boot/efi -maxdepth 3 -type f
```

Expected

```text
EFI/BOOT/BOOTX64.EFI

EFI/ubuntu/grub.cfg

EFI/ubuntu/grubx64.efi

EFI/ubuntu/shimx64.efi

EFI/ubuntu/mmx64.efi
```

---

# Phase 19 - Verify UEFI Boot Entries

Run

```bash
efibootmgr -v
```

Expected

```text
Boot0000* ubuntu
```

or another valid Ubuntu boot entry pointing to the recovered disk.

---

# Phase 20 - Verify Storage

Run

```bash
lsblk
```

Expected

```text
sdb
├── sdb1
├── sdb2
│   └── md0
└── sdb3
    └── md1
```

Verify RAID.

```bash
cat /proc/mdstat
```

Expected

```text
md0 [U_]

md1 [U_]
```

or

```text
md0 [_U]

md1 [_U]
```

This degraded state is expected because only one disk is connected.

---

# Phase 21 - Reconnect the Original Disk

Power off the server.

Reconnect **Disk1 (sda)**.

Power on the server.

Verify RAID synchronization.

```bash
cat /proc/mdstat
```

Expected

```text
md0 [UU]

md1 [UU]
```

Verify storage.

```bash
lsblk
```

Expected

```text
sda
├── sda1
├── sda2
│   └── md0
└── sda3
    └── md1

sdb
├── sdb1
├── sdb2
│   └── md0
└── sdb3
    └── md1
```

---

# Troubleshooting

---

## grub-install reports

```
doesn't look like an EFI partition
```

### Cause

The target partition is either:

- Not formatted as FAT32
- Not mounted correctly
- The wrong partition has been mounted

### Verify

```bash
blkid /dev/sdb1
```

Expected

```text
TYPE="vfat"
```

If necessary,

```bash
mkfs.vfat -F32 /dev/sdb1
```

Mount again.

```bash
mount /dev/sdb1 /mnt/efi2
```

---

## rsync copies nothing

### Cause

The wrong source EFI partition is mounted.

Verify.

```bash
find /boot/efi
```

If no files are displayed,

the wrong partition is mounted.

Mount the healthy EFI partition and repeat the synchronization.

---

## grub-install succeeds but the recovered disk does not boot

Possible causes:

- EFI files were not synchronized.
- Wrong EFI partition mounted.
- Missing `BOOTX64.EFI`.
- GRUB installed to the wrong EFI partition.

Verify.

```bash
find /mnt/efi2
```

Compare both EFI partitions.

```bash
diff -rq /boot/efi /mnt/efi2
```

No output should be returned.

---

## Both mount points reference the same partition

Incorrect example:

```text
/boot/efi

↓

/dev/sda1

/mnt/efi2

↓

/dev/sda1
```

In this case, `rsync` simply copies the partition onto itself.

Always verify before copying.

```bash
findmnt /boot/efi

findmnt /mnt/efi2
```

Expected

```text
/boot/efi  -> /dev/sda1

/mnt/efi2  -> /dev/sdb1
```

The source and destination **must** be different devices.

---

## /boot/efi is not mounted after reboot

This usually occurs because the UUID of the new EFI partition differs from the UUID stored in `/etc/fstab`.

Identify the EFI partition.

```bash
blkid | grep 'TYPE="vfat"'
```

Mount it.

```bash
mount /dev/sdb1 /boot/efi
```

Update `/etc/fstab` if automatic mounting is required.

---

# Post-Patch EFI Synchronization

Updates to packages such as:

- grub-efi-amd64
- grub2
- shim
- shim-signed
- linux-image
- linux-generic

typically update **only the mounted EFI partition**.

After these updates, synchronize the second EFI partition.

Using the automation script:

```bash
/usr/local/bin/sync-efi.sh
```

Or manually:

```bash
mkdir -p /mnt/efi2

mount /dev/sdb1 /mnt/efi2

rsync -aHAX --delete /boot/efi/ /mnt/efi2/

sync

umount /mnt/efi2
```

Validate the synchronization.

```bash
diff -rq /boot/efi /mnt/efi2
```

Expected

```text
(no output)
```

---

# Recovery Checklist

## Hardware

- [ ] Failed disk replaced
- [ ] Replacement disk detected

---

## Partition Table

- [ ] GPT cloned
- [ ] New GPT Disk GUID generated

---

## EFI

- [ ] FAT32 filesystem created
- [ ] EFI partition mounted
- [ ] GRUB installed successfully
- [ ] BOOTX64.EFI present
- [ ] Ubuntu EFI directory present

---

## RAID

- [ ] md0 rebuilt
- [ ] md1 rebuilt
- [ ] RAID status is healthy (`[UU]`)

---

## Validation

- [ ] EFI synchronized
- [ ] `diff -rq` returned no output
- [ ] `efibootmgr` verified
- [ ] Boot tested using only the recovered disk
- [ ] RAID verified after reconnecting the original disk

---

# Document Summary

This procedure restores a failed **Disk2 (sdb)** in an Ubuntu Server 24.04.3 LTS system configured with:

- UEFI Boot
- GPT Partitioning
- Linux Software RAID1 (mdadm)
- LVM2
- Dual EFI System Partitions
- GRUB2 Bootloader

The recovery process restores the complete replacement disk, including the GPT partition table, EFI System Partition, RAID members, GRUB bootloader, and synchronized EFI contents. After completion, either disk can independently boot the operating system while maintaining full RAID1 redundancy.
