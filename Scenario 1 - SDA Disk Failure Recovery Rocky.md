# Rocky Linux 8.10 RAID1 Recovery SOP
## Scenario 1 - SDA Disk Failure Recovery
### UEFI + GPT + Software RAID1 + LVM

---

# Purpose

This document describes the complete recovery procedure when the **primary disk (/dev/sda)** fails and has been replaced with a new blank disk.

This procedure restores:

- GPT Partition Table
- Software RAID1
- LVM
- EFI Partition
- UEFI Boot Entries
- Boot Order

This SOP has been validated on Rocky Linux 8.10 running on VMware with UEFI firmware.

---

# Environment

| Item | Value |
|------|-------|
| Failed Disk | `/dev/sda` |
| Healthy Disk | `/dev/sdb` |
| Replacement Disk | `/dev/sda` |
| Boot Mode | UEFI |
| Partition Table | GPT |
| RAID | Software RAID1 |
| Filesystem | XFS |
| Bootloader | GRUB2 (UEFI) |

---

# Expected Disk Layout

```
sda
├── sda1   EFI (600 MB)
├── sda2   RAID1 (/boot)
└── sda3   RAID1 (LVM)

sdb
├── sdb1   EFI (600 MB)
├── sdb2   RAID1 (/boot)
└── sdb3   RAID1 (LVM)
```

---

# Step 1 - Verify RAID Status

Check RAID status.

```bash
cat /proc/mdstat
```

Expected

```
md0 [2/1]
md1 [2/1]
```

or

```
md0 [U_]
md1 [U_]
```

Verify disks.

```bash
lsblk
```

Verify VMware SCSI mapping.

```bash
lsscsi -g
```

> **Important**
>
> Linux device names (`/dev/sda`, `/dev/sdb`) may change after replacing a disk.
> Always verify which disk is healthy before proceeding.

---

# Step 2 - Restore GPT Partition Table

Clone the partition table from the healthy disk.

```bash
sgdisk -R=/dev/sda /dev/sdb
```

Generate new GPT GUIDs.

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

```
sda1
sda2
sda3
```

---

# Step 3 - Rebuild RAID

Add the new partitions back into RAID.

```bash
mdadm --manage /dev/md0 --add /dev/sda2

mdadm --manage /dev/md1 --add /dev/sda3
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

---

# Step 4 - Recreate EFI Filesystem

Create a new FAT32 EFI filesystem.

```bash
mkfs.vfat -F32 /dev/sda1
```

---

# Step 5 - Restore EFI Boot Files

Create mount points.

```bash
mkdir -p /mnt/efi_old
mkdir -p /mnt/efi_new
```

Mount the healthy EFI partition.

```bash
mount /dev/sdb1 /mnt/efi_old
```

Mount the replacement EFI partition.

```bash
mount /dev/sda1 /mnt/efi_new
```

Copy EFI files.

```bash
cp -a /mnt/efi_old/. /mnt/efi_new/
```

Flush pending writes.

```bash
sync
```

Verify copied files.

```bash
find /mnt/efi_new
```

Expected folders

```
EFI/
EFI/BOOT/
EFI/rocky/
```

Unmount.

```bash
umount /mnt/efi_old

umount /mnt/efi_new
```

---

# Step 6 - Backup Existing Boot Entries

Before making changes, save the current boot configuration.

```bash
efibootmgr -v > /root/efibootmgr.before
```

---

# Step 7 - Identify Current and Old UEFI Boot Entries

## Display Current EFI Partition GUIDs

```bash
blkid /dev/sda1

blkid /dev/sdb1
```

Example

```
/dev/sda1
PARTUUID="B1E8C18E-XXXX"

/dev/sdb1
PARTUUID="3AD7E0F9-XXXX"
```

---

## Display Existing Boot Entries

```bash
efibootmgr -v
```

Example

```
Boot0005* Rocky Disk1
HD(1,GPT,B1E8C18E-XXXX,...)

Boot0006* Rocky Disk2
HD(1,GPT,3AD7E0F9-XXXX,...)

Boot0011* rocky
HD(1,GPT,2AEB77D2-XXXX,...)

Boot0012* rocky
HD(1,GPT,07A8559A-XXXX,...)
```

---

## How to Identify Old Boot Entries

Compare the PARTUUID values.

### Keep

Boot entries whose PARTUUID matches either

```
blkid /dev/sda1

or

blkid /dev/sdb1
```

Example

```
Current PARTUUIDs

sda1 = B1E8C18E

sdb1 = 3AD7E0F9

Boot0005 -> B1E8C18E  ✅ Keep

Boot0006 -> 3AD7E0F9  ✅ Keep
```

---

### Delete

Delete any Rocky boot entry whose PARTUUID **does not match** either EFI partition.

Example

```
Boot0011 -> 2AEB77D2  ❌ Delete

Boot0012 -> 07A8559A  ❌ Delete
```

> **Important**
>
> Never identify old entries by `Boot0005`, `Boot0006`, etc.
>
> Boot numbers change after reinstallations and disk replacements.
>
> Always compare the **PARTUUID**.

---

# Step 8 - Delete Old Rocky Boot Entries

Delete only the stale Rocky entries.

Example

```bash
efibootmgr -b 0011 -B

efibootmgr -b 0012 -B
```

Do **NOT** delete:

- EFI Virtual Disk
- EFI DVD/CDROM
- EFI Network

---

# Step 9 - Create New Boot Entries

Create the entry for Disk 1.

```bash
efibootmgr \
--create \
--disk /dev/sda \
--part 1 \
--label "Rocky Disk1" \
--loader '\EFI\rocky\shimx64.efi'
```

Create the entry for Disk 2.

```bash
efibootmgr \
--create \
--disk /dev/sdb \
--part 1 \
--label "Rocky Disk2" \
--loader '\EFI\rocky\shimx64.efi'
```

---

# Step 10 - Verify Boot Entries

Display the boot entries.

```bash
efibootmgr -v
```

Verify that the PARTUUID values match.

```bash
blkid /dev/sda1

blkid /dev/sdb1
```

The PARTUUID values shown in `efibootmgr -v` should match the output of `blkid`.

---

# Step 11 - Configure Boot Order

List the current boot IDs.

```bash
efibootmgr
```

Example

```
Boot0005 Rocky Disk1

Boot0006 Rocky Disk2
```

Set the boot order.

```bash
efibootmgr -o 0006,0005
```

Adjust the boot numbers based on your system.

Verify.

```bash
efibootmgr
```

---

# Step 12 - Reboot

```bash
reboot
```

After login, verify the active boot entry.

```bash
efibootmgr
```

Expected

```
BootCurrent

Rocky Disk1

or

Rocky Disk2
```

It should **not** show only

```
EFI Virtual Disk
```

---

# Step 13 - Verify RAID

```bash
cat /proc/mdstat
```

Expected

```
md0 [UU]

md1 [UU]
```

Verify disks.

```bash
lsblk
```

---

# Step 14 - Validate Disk Failover

Power off the VM.

Remove Disk1 (`/dev/sda`).

Power on the VM.

Verify the boot entry.

```bash
efibootmgr
```

Verify RAID.

```bash
cat /proc/mdstat
```

Expected

```
md0 [U_]

md1 [U_]
```

The server should boot successfully.

---

# Recovery Validation Checklist

- [ ] Replacement disk detected
- [ ] GPT partition table restored
- [ ] New GPT GUID generated
- [ ] RAID rebuilt
- [ ] RAID synchronized
- [ ] EFI filesystem recreated
- [ ] EFI boot files restored
- [ ] Current EFI PARTUUID verified
- [ ] Old UEFI boot entries removed
- [ ] New UEFI boot entries created
- [ ] Boot order configured
- [ ] BootCurrent uses Rocky boot entry
- [ ] RAID healthy
- [ ] Server boots successfully after SDA failure

---

# Recovery Complete

The RAID1 array has been fully restored, UEFI boot redundancy has been re-established, and the system has been validated to boot successfully after an SDA disk failure.
