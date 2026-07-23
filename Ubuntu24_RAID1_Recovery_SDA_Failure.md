# Ubuntu24_RAID1_Recovery_SDA_Failure.md

# Ubuntu 24.04 LTS RAID1 Disk Recovery SOP
## Scenario 1 - Disk 1 (sda) Failure

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
| Tested Platform | VMware ESXi / Workstation |
| Tested Kernel | 6.8.x |

---

# Purpose

This document describes the complete recovery procedure when **Disk 1 (sda)** fails in a dual-disk Ubuntu 24.04 RAID1 server.

The procedure restores:

- GPT partition table
- EFI System Partition
- RAID1 /boot
- RAID1 LVM PV
- GRUB Bootloader
- EFI boot files

The procedure has been validated on Ubuntu 24.04.3 LTS.

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

### Disk 1

```
sda
├── sda1   EFI System Partition (FAT32)
├── sda2   RAID1 (/boot)
└── sda3   RAID1 (LVM PV)
```

### Disk 2

```
sdb
├── sdb1   EFI System Partition (FAT32)
├── sdb2   RAID1 (/boot)
└── sdb3   RAID1 (LVM PV)
```

---

# Failure Scenario

Disk 1 fails completely.

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

sda    FAILED / REMOVED

sdb
├── sdb1
├── sdb2
└── sdb3
```

↓

Server boots successfully using Disk2.

↓

A new replacement disk is inserted.

↓

Linux detects:

```

```
sda    New Empty Disk

sdb
├── sdb1
├── sdb2
└── sdb3
```

This document starts from this point.

---

# Preconditions

Before starting recovery ensure:

- Server has booted successfully.
- Login as root.
- One RAID member is healthy.
- Replacement disk size is equal to or larger than the failed disk.
- Replacement disk contains no required data.
- A backup exists.

---

# Verify Current Status

Check storage.

```bash
lsblk
```

Example

```text
NAME
sda

sdb
├── sdb1
├── sdb2
└── sdb3
```

---

Check RAID.

```bash
cat /proc/mdstat
```

Example

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

Both indicate degraded RAID.

---

Check boot mode.

```bash
[ -d /sys/firmware/efi ] && echo UEFI || echo BIOS
```

Expected

```
UEFI
```

---

Check current boot disk.

```bash
findmnt /boot
```

Example

```
/dev/md0
```

---

Check EFI mount.

```bash
mount | grep /boot/efi
```

Possible Output

```
/dev/sdb1 on /boot/efi
```

OR

No output.

Both are valid.

If no output is returned, the EFI partition is not mounted and will be mounted later in this procedure.

---

Recovery Phases

1. Detect replacement disk
2. Mount EFI (if required)
3. Clone GPT
4. Create EFI filesystem
5. Rebuild RAID
6. Restore EFI
7. Install GRUB
8. Synchronize EFI
9. Validate
10. Boot failover test

---

# Part 2 – Disk Replacement and RAID Recovery

---

# Phase 1 - Detect the Replacement Disk

Rescan all SCSI hosts.

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
sdb
├── sdb1
├── sdb2
└── sdb3
```

The replacement disk should appear as an empty disk.

---

# Phase 2 - Mount the EFI Partition

Check whether EFI is already mounted.

```bash
mount | grep /boot/efi
```

---

## Case 1

Output

```text
/dev/sdb1 on /boot/efi
```

EFI is already mounted.

Continue to Phase 3.

---

## Case 2

No output

Determine the available EFI partition.

```bash
blkid | grep 'TYPE="vfat"'
```

Example

```text
/dev/sdb1: UUID="E4C6-C128" TYPE="vfat"
```

Mount it.

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

---

# Phase 3 - Clone the GPT Partition Table

Copy the partition table from the healthy disk.

```bash
sgdisk --backup=/tmp/gpt.bin /dev/sdb
```

Restore it onto the replacement disk.

```bash
sgdisk --load-backup=/tmp/gpt.bin /dev/sda
```

Generate a new GPT Disk GUID.

```bash
sgdisk -G /dev/sda
```

Reload the partition table.

```bash
partprobe /dev/sda
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

Format the EFI partition.

```bash
mkfs.vfat -F32 /dev/sda1
```

Verify.

```bash
blkid /dev/sda1
```

Expected

```text
TYPE="vfat"
```

---

# Phase 5 - Add RAID Members

Add /boot RAID member.

```bash
mdadm --add /dev/md0 /dev/sda2
```

Add LVM RAID member.

```bash
mdadm --add /dev/md1 /dev/sda3
```

---

# Phase 6 - Monitor RAID Rebuild

Watch rebuild progress.

```bash
watch cat /proc/mdstat
```

Do not continue until both arrays show

```text
md0 [UU]

md1 [UU]
```

Verify.

```bash
cat /proc/mdstat
```

Expected

```text
Personalities : [raid1]

md0 : active raid1 sda2 sdb2
      [2/2] [UU]

md1 : active raid1 sda3 sdb3
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

Recovery of the RAID arrays is now complete.

# Part 3 – EFI Recovery and GRUB Installation

---

# Phase 7 - Restore the EFI Partition

At this point:

- RAID has completed rebuilding.
- `/dev/sda1` contains a new FAT32 filesystem.
- `/dev/sdb1` contains the working EFI partition.
- `/boot/efi` should be mounted from `/dev/sdb1`.

Verify.

```bash
mount | grep /boot/efi
```

Expected

```text
/dev/sdb1 on /boot/efi
```

If nothing is returned,

mount the EFI partition manually.

```bash
blkid | grep 'TYPE="vfat"'

mount /dev/sdb1 /boot/efi
```

Verify again.

```bash
mount | grep /boot/efi
```

---

# Phase 8 - Mount the Replacement EFI

Create a temporary mount point.

```bash
mkdir -p /mnt/efi2
```

Mount the replacement EFI.

```bash
mount /dev/sda1 /mnt/efi2
```

Verify.

```bash
mount | grep efi
```

Expected

```text
/dev/sdb1 on /boot/efi

/dev/sda1 on /mnt/efi2
```

## IMPORTANT

Verify that the source and destination are different.

Run

```bash
findmnt /boot/efi

findmnt /mnt/efi2
```

Expected

```text
TARGET      SOURCE
/boot/efi   /dev/sdb1

TARGET      SOURCE
/mnt/efi2   /dev/sda1
```

If both mount points reference the same device,

STOP.

Unmount and mount the correct partition.

---

# Phase 9 - Verify Source EFI

Verify the source EFI contains the required boot files.

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

If no files are listed,

STOP.

The wrong EFI partition is mounted.

---

# Phase 10 - Install GRUB

Install GRUB on the replacement EFI.

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

Verify the EFI directory.

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

# Phase 12 - Synchronize EFI

Copy all EFI files.

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

This confirms both EFI partitions are identical.

---

# Phase 14 - Cleanup

Unmount the temporary EFI.

```bash
umount /mnt/efi2
```

Verify.

```bash
mount | grep efi
```

Expected

```text
/dev/sdb1 on /boot/efi
```

There should no longer be a mount for `/mnt/efi2`.

---

# Phase 15 - Validate Boot Configuration

Verify RAID.

```bash
cat /proc/mdstat
```

Expected

```text
md0 [UU]

md1 [UU]
```

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
├── sdb1
├── sdb2
└── sdb3
```

Verify boot entries.

```bash
efibootmgr -v
```

Expected

```text
Boot0000* ubuntu
```

or similar Ubuntu boot entry.

At this point:

- GPT has been restored.
- EFI partition has been restored.
- GRUB has been installed.
- RAID has been rebuilt.
- The replacement disk is bootable.

# Part 4 – Boot Failover Testing, Troubleshooting, Post-Patch Synchronization & Appendix

---

# Phase 16 - Boot Failover Test

The purpose of this test is to verify that the recovered disk can independently boot the operating system.

---

## Step 1 - Shutdown the Server

```bash
shutdown -h now
```

---

## Step 2 - Disconnect the Healthy Disk

Temporarily disconnect:

```
Disk2 (/dev/sdb)
```

Leave only the recovered disk connected.

```
Connected

sda

Disconnected

sdb
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
/dev/sda1 on /boot/efi
```

Everything is correct.

Proceed to validation.

---

## Case 2

No Output

This is a common situation after disk replacement because the UUID of the newly formatted EFI partition differs from the UUID stored in `/etc/fstab`.

Identify the EFI partition.

```bash
blkid | grep 'TYPE="vfat"'
```

Example

```text
/dev/sda1: UUID="F090-25ED"
```

Mount it manually.

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

# Phase 18 - Verify Boot Files

Run

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

# Phase 19 - Verify GRUB

```bash
efibootmgr -v
```

Expected

Ubuntu boot entry.

Example

```text
Boot0000* ubuntu
```

---

# Phase 20 - Verify RAID Devices

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
```

---

# Phase 21 - Reconnect the Second Disk

Power off.

Reconnect Disk2.

Power on.

Verify RAID.

```bash
cat /proc/mdstat
```

Expected

```text
md0
[UU]

md1
[UU]
```

---

# Troubleshooting

---

## grub-install reports

```
doesn't look like an EFI partition
```

Cause

The partition is not formatted as FAT32 or not mounted correctly.

Verify

```bash
blkid /dev/sda1
```

Expected

```text
TYPE="vfat"
```

If necessary

```bash
mkfs.vfat -F32 /dev/sda1
```

Mount again

```bash
mount /dev/sda1 /mnt/efi2
```

---

## rsync copies nothing

Cause

Wrong source partition mounted.

Verify

```bash
find /boot/efi
```

If empty

Wrong EFI mounted.

Mount the healthy EFI first.

---

## grub-install succeeds but the recovered disk does not boot

Possible causes

- EFI files not synchronized
- Wrong EFI mounted
- Missing BOOTX64.EFI
- GRUB installed to the wrong partition

Verify

```bash
find /mnt/efi2
```

Compare

```bash
diff -rq /boot/efi /mnt/efi2
```

---

## Both mount points reference the same partition

Wrong

```text
/boot/efi

↓

/dev/sdb1

/mnt/efi2

↓

/dev/sdb1
```

This copies the EFI partition onto itself.

Always verify

```bash
findmnt /boot/efi

findmnt /mnt/efi2
```

They must reference different block devices.

---

## /boot/efi is not mounted after reboot

This usually occurs because the new EFI partition has a different UUID than the one stored in `/etc/fstab`.

Identify the correct EFI partition.

```bash
blkid | grep 'TYPE="vfat"'
```

Mount it manually.

```bash
mount /dev/sda1 /boot/efi
```

Update `/etc/fstab` with the new UUID if permanent automatic mounting is required.

---

# Post-Patch EFI Synchronization

Ubuntu updates that modify any of the following packages update only the mounted EFI partition.

Examples

- grub-efi-amd64
- grub2
- shim
- shim-signed
- linux-image
- linux-generic

After these updates, synchronize the second EFI partition.

Example

```bash
/usr/local/bin/sync-efi.sh
```

or manually

```bash
mount /dev/sda1 /mnt/efi2

rsync -aHAX --delete /boot/efi/ /mnt/efi2/

sync

umount /mnt/efi2
```

Verify

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
- [ ] New disk GUID generated

---

## EFI

- [ ] FAT32 created
- [ ] EFI mounted
- [ ] GRUB installed
- [ ] BOOTX64.EFI present
- [ ] Ubuntu EFI directory present

---

## RAID

- [ ] md0 rebuilt
- [ ] md1 rebuilt
- [ ] RAID healthy

---

## Validation

- [ ] EFI synchronized
- [ ] diff -rq clean
- [ ] efibootmgr verified
- [ ] Boot verified using recovered disk only
- [ ] RAID verified after reconnecting second disk

---

# Document Summary

This procedure restores a failed **Disk 1 (sda)** in an Ubuntu 24.04.3 LTS server configured with:

- UEFI Boot
- GPT Partitioning
- Software RAID1 (mdadm)
- LVM2
- Dual EFI System Partitions
- GRUB2 Bootloader

The recovery process restores the complete disk, including the GPT, EFI System Partition, RAID members, GRUB bootloader, and synchronized EFI contents, ensuring that either disk can independently boot the operating system while maintaining full RAID redundancy.

