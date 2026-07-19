# RAID1 Disk Replacement SOP (UEFI + GPT + LVM)

## Overview

This SOP describes the recovery procedure for replacing a failed disk in a Linux server configured with:

- UEFI Boot
- GPT Partition Table
- Software RAID1 (mdadm)
- LVM
- Dual EFI Partitions
- Rocky Linux / CentOS

---

## Disk Layout

| Disk | Partition | Purpose |
|------|-----------|---------|
| sda1 | EFI System Partition | EFI Boot |
| sda2 | RAID1 Member | /boot (md1) |
| sda3 | RAID1 Member | LVM PV (md0) |
| sdb1 | EFI System Partition | EFI Boot |
| sdb2 | RAID1 Member | /boot (md1) |
| sdb3 | RAID1 Member | LVM PV (md0) |

---

## RAID Layout

| RAID Device | Level | Mount |
|-------------|-------|-------|
| md1 | RAID1 | /boot |
| md0 | RAID1 | LVM PV |

---

## LVM Layout

```
md0
 └── vg_root
      ├── root
      ├── swap
      └── home
```

---

# SOP 1 - Replace Failed Disk (/dev/sda)

## Step 1 - Verify RAID Status

```bash
cat /proc/mdstat

mdadm --detail /dev/md0

mdadm --detail /dev/md1
```

Expected:

```
md0 [_U]

md1 [_U]
```

---

## Step 2 - Replace the failed disk

Replace **/dev/sda** with a new blank disk.

Verify:

```bash
lsblk
```

---

## Step 3 - Remove Existing Signatures

```bash
wipefs -a /dev/sda

sgdisk --zap-all /dev/sda
```

---

## Step 4 - Clone Partition Table

Clone from healthy disk (**sdb**).

```bash
sgdisk --replicate=/dev/sda /dev/sdb

sgdisk --randomize-guids /dev/sda
```

---

## Step 5 - Reload Partition Table

```bash
partprobe /dev/sda

partx -u /dev/sda

udevadm settle
```

Verify:

```bash
lsblk

fdisk -l /dev/sda
```

Expected:

```
sda1
sda2
sda3
```

---

## Step 6 - Add RAID Members

```bash
mdadm --add /dev/md1 /dev/sda2

mdadm --add /dev/md0 /dev/sda3
```

---

## Step 7 - Monitor RAID Rebuild

```bash
watch cat /proc/mdstat
```

Wait until:

```
md0 [UU]

md1 [UU]
```

---

## Step 8 - Restore EFI Bootloader

Rocky 8/9 Golden Image:

```bash
/usr/local/sbin/sync-esp.sh
```

---

## Step 9 - Verify EFI Entries

```bash
efibootmgr -v
```

---

## Step 10 - Verify System

```bash
mdadm --detail /dev/md0

mdadm --detail /dev/md1

lsblk

pvs

vgs

lvs
```

---

# SOP 2 - Replace Failed Disk (/dev/sdb)

## Step 1 - Verify RAID Status

```bash
cat /proc/mdstat

mdadm --detail /dev/md0

mdadm --detail /dev/md1
```

Expected:

```
md0 [_U]

md1 [_U]
```

---

## Step 2 - Replace the failed disk

Replace **/dev/sdb** with a new blank disk.

Verify:

```bash
lsblk
```

---

## Step 3 - Remove Existing Signatures

```bash
wipefs -a /dev/sdb

sgdisk --zap-all /dev/sdb
```

---

## Step 4 - Clone Partition Table

Clone from healthy disk (**sda**).

```bash
sgdisk --replicate=/dev/sdb /dev/sda

sgdisk --randomize-guids /dev/sdb
```

---

## Step 5 - Reload Partition Table

```bash
partprobe /dev/sdb

partx -u /dev/sdb

udevadm settle
```

Verify:

```bash
lsblk

fdisk -l /dev/sdb
```

Expected:

```
sdb1
sdb2
sdb3
```

---

## Step 6 - Add RAID Members

```bash
mdadm --add /dev/md1 /dev/sdb2

mdadm --add /dev/md0 /dev/sdb3
```

---

## Step 7 - Monitor RAID Rebuild

```bash
watch cat /proc/mdstat
```

Wait until:

```
md0 [UU]

md1 [UU]
```

---

## Step 8 - Restore EFI Bootloader

Rocky 8/9 Golden Image:

```bash
/usr/local/sbin/sync-esp.sh
```

---

## Step 9 - Verify EFI Entries

```bash
efibootmgr -v
```

---

## Step 10 - Verify System

```bash
mdadm --detail /dev/md0

mdadm --detail /dev/md1

lsblk

pvs

vgs

lvs
```

---

# Recovery Flow

```
Disk Failure
      │
      ▼
Replace Disk
      │
      ▼
wipefs
      │
      ▼
sgdisk --zap-all
      │
      ▼
sgdisk --replicate
      │
      ▼
sgdisk --randomize-guids
      │
      ▼
partprobe
partx
udevadm settle
      │
      ▼
mdadm --add md1
      │
      ▼
mdadm --add md0
      │
      ▼
RAID Rebuild
      │
      ▼
sync-esp.sh
      │
      ▼
Verify mdadm
Verify EFI
Verify LVM
```

---

# Quick Reference

| Failed Disk | Clone Command | Add /boot RAID | Add LVM RAID |
|-------------|---------------|----------------|--------------|
| **sda** | `sgdisk --replicate=/dev/sda /dev/sdb` | `mdadm --add /dev/md1 /dev/sda2` | `mdadm --add /dev/md0 /dev/sda3` |
| **sdb** | `sgdisk --replicate=/dev/sdb /dev/sda` | `mdadm --add /dev/md1 /dev/sdb2` | `mdadm --add /dev/md0 /dev/sdb3` |

---

# Validation Checklist

- [ ] New disk detected
- [ ] GPT cloned successfully
- [ ] New GUID generated
- [ ] All partitions visible
- [ ] md1 rebuilt
- [ ] md0 rebuilt
- [ ] Both arrays show **[UU]**
- [ ] EFI synchronized (`sync-esp.sh`)
- [ ] EFI boot entries verified
- [ ] LVM volumes healthy
- [ ] System boots successfully with either disk removed
