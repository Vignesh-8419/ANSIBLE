# CentOS 7.9 RAID1 Recovery SOP
## Scenario - Disk Failure Recovery (SDA or SDB)
### UEFI + GPT + Software RAID1 + LVM

---

# Purpose

This document describes the complete recovery procedure when either RAID1 disk fails and is replaced with a new blank disk.

The procedure restores:

- GPT Partition Table
- Software RAID1
- LVM
- EFI System Partition
- GRUB2 (UEFI)
- UEFI Boot Entries
- Boot Order

This SOP has been validated on CentOS 7.9 running on VMware with UEFI firmware.

---

# Environment

| Item | Value |
|------|-------|
| Operating System | CentOS Linux 7.9 |
| Boot Mode | UEFI |
| Partition Table | GPT |
| RAID | mdadm RAID1 |
| Volume Manager | LVM |
| Bootloader | GRUB2 EFI |

---

# Storage Layout

```
sda
├── sda1   EFI System Partition (600 MB)
├── sda2   RAID1 (/boot)
└── sda3   RAID1 (LVM PV)

sdb
├── sdb1   EFI System Partition (600 MB)
├── sdb2   RAID1 (/boot)
└── sdb3   RAID1 (LVM PV)
```

---

# IMPORTANT

- EFI System Partitions are **NOT RAID**.
- `/boot` and the LVM PV are RAID1.
- Replace only the failed disk.
- Verify which disk is healthy before running any command.
- Linux device names may change after disk replacement.

---

# Step 1 - Verify RAID Status

```bash
cat /proc/mdstat
lsblk
lsscsi -g
```

Expected:

```
md0 [2/1]
md1 [2/1]
```

or

```
md0 [U_]
md1 [U_]
```

or

```
md0 [_U]
md1 [_U]
```

---

# Step 2 - Identify the Healthy Disk

Determine which disk is still healthy.

| Failed Disk | Healthy Disk |
|-------------|--------------|
| sda | sdb |
| sdb | sda |

---

# Step 3 - Clone GPT Partition Table

## If replacing Disk1 (sda)

```bash
sgdisk -R=/dev/sda /dev/sdb
sgdisk -G /dev/sda
partprobe /dev/sda
udevadm settle
```

## If replacing Disk2 (sdb)

```bash
sgdisk -R=/dev/sdb /dev/sda
sgdisk -G /dev/sdb
partprobe /dev/sdb
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

or

sdb1
sdb2
sdb3
```

---

# Step 4 - Add RAID Members

## If replacing sda

```bash
mdadm --manage /dev/md0 --add /dev/sda2
mdadm --manage /dev/md1 --add /dev/sda3
```

## If replacing sdb

```bash
mdadm --manage /dev/md0 --add /dev/sdb2
mdadm --manage /dev/md1 --add /dev/sdb3
```

Monitor RAID rebuild.

```bash
watch cat /proc/mdstat
```

Wait until:

```
md0 [UU]
md1 [UU]
```

---

# Step 5 - Create EFI Filesystem

## If replacing sda

```bash
mkfs.vfat -F32 /dev/sda1
```

## If replacing sdb

```bash
mkfs.vfat -F32 /dev/sdb1
```

---

# Step 6 - Restore EFI Boot Files

Create temporary mount points.

```bash
mkdir -p /mnt/efi_old
mkdir -p /mnt/efi_new
```

---

## If replacing sda

```bash
mount /dev/sdb1 /mnt/efi_old
mount /dev/sda1 /mnt/efi_new
```

---

## If replacing sdb

```bash
mount /dev/sda1 /mnt/efi_old
mount /dev/sdb1 /mnt/efi_new
```

---

Synchronize the EFI contents.

```bash
rsync -aHAX --delete /mnt/efi_old/ /mnt/efi_new/

sync
```

Verify.

```bash
find /mnt/efi_new/EFI -maxdepth 3 -type f | sort
```

Expected:

```
EFI/BOOT/BOOTX64.EFI
EFI/centos/shimx64.efi
EFI/centos/grubx64.efi
EFI/centos/grub.cfg
```

Unmount.

```bash
umount /mnt/efi_old
umount /mnt/efi_new
```

---

# Step 7 - Backup Existing UEFI Boot Entries

```bash
efibootmgr -v > /root/efibootmgr.before
```

---

# Step 8 - Verify Current EFI PARTUUIDs

## If replacing sda

```bash
blkid /dev/sda1
blkid /dev/sdb1
```

## If replacing sdb

```bash
blkid /dev/sda1
blkid /dev/sdb1
```

Example:

```
/dev/sda1
PARTUUID="11111111-AAAA"

/dev/sdb1
PARTUUID="22222222-BBBB"
```

---

Display current boot entries.

```bash
efibootmgr -v
```

Compare every PARTUUID shown in:

```
HD(1,GPT,...)
```

with the output of `blkid`.

Keep only entries matching the current EFI partitions.

Delete stale CentOS entries.

Example:

```bash
efibootmgr -b 0012 -B
efibootmgr -b 0013 -B
```

Never delete:

- EFI Virtual Disk
- EFI DVD
- EFI Network

---

# Step 9 - Create New Boot Entry

## If replacing sda

```bash
efibootmgr \
--create \
--disk /dev/sda \
--part 1 \
--label "CentOS Disk1" \
--loader '\EFI\centos\shimx64.efi'
```

---

## If replacing sdb

```bash
efibootmgr \
--create \
--disk /dev/sdb \
--part 1 \
--label "CentOS Disk2" \
--loader '\EFI\centos\shimx64.efi'
```

---

Verify.

```bash
efibootmgr -v
```

Confirm the PARTUUID matches `blkid`.

---

# Step 10 - Configure Boot Order

Display boot entries.

```bash
efibootmgr
```

Example:

```
Boot0007 CentOS Disk1
Boot0008 CentOS Disk2
```

Configure boot order using the current boot IDs.

Example:

```bash
efibootmgr -o 0008,0007
```

Verify.

```bash
efibootmgr
```

---

# Step 11 - Save RAID Configuration

```bash
mdadm --detail --scan > /etc/mdadm.conf
```

(Optional but recommended)

Rebuild initramfs.

```bash
dracut -f
```

---

# Step 12 - Reboot

```bash
reboot
```

---

# Step 13 - Validate Recovery

Verify active boot entry.

```bash
efibootmgr
```

Expected:

```
BootCurrent
CentOS Disk1

or

CentOS Disk2
```

Verify RAID.

```bash
cat /proc/mdstat
```

Expected:

```
md0 [UU]
md1 [UU]
```

Verify storage.

```bash
lsblk
```

Verify LVM.

```bash
pvs
vgs
lvs
```

Verify filesystems.

```bash
df -h
```

(Optional) Re-enable verbose boot.

```bash
mkdir -p /root/scripts

curl --retry 5 --retry-delay 2 -fsSL \
-o /root/scripts/enable-verbose-boot.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/enable-verbose-boot.sh?$(date +%s)"

chmod +x /root/scripts/enable-verbose-boot.sh

/root/scripts/enable-verbose-boot.sh
```

---

# Step 14 - Boot Failover Test

Power off the VM.

Disconnect one disk.

Boot the server.

Verify:

```bash
efibootmgr
cat /proc/mdstat
lsblk
```

Expected:

```
md0 [U_]
md1 [U_]
```

or

```
md0 [_U]
md1 [_U]
```

Reconnect the removed disk.

Verify RAID returns to:

```
md0 [UU]
md1 [UU]
```

---

# Recovery Checklist

- [ ] Failed disk replaced
- [ ] GPT restored
- [ ] New GPT GUID generated
- [ ] RAID members added
- [ ] RAID synchronized
- [ ] EFI filesystem recreated
- [ ] EFI contents synchronized
- [ ] Current EFI PARTUUID verified
- [ ] Stale UEFI boot entries removed
- [ ] New UEFI boot entry created
- [ ] Boot order configured
- [ ] BootCurrent verified
- [ ] RAID healthy
- [ ] LVM healthy
- [ ] Filesystems healthy
- [ ] Boot tested using either disk

---

# Recovery Complete

Recovery is successful when:

- ✅ GPT exists on both disks.
- ✅ Both EFI partitions contain identical bootloader files.
- ✅ RAID arrays show **[UU]**.
- ✅ LVM is healthy.
- ✅ Valid UEFI boot entries exist for both disks.
- ✅ The system boots successfully using either disk independently.
