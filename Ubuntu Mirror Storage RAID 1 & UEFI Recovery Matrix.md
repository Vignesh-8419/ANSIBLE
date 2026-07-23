# Ubuntu 24.04 RAID1 Disk Recovery SOP

## Purpose

This SOP describes how to recover a failed disk in an Ubuntu 24.04 server configured with:

- UEFI Boot
- Software RAID1
- Dual EFI System Partitions
- RAID1 `/boot`
- RAID1 LVM Physical Volume
- LVM Root Filesystem

---

# Storage Layout

| Partition | Purpose | RAID |
|------------|---------|------|
| Partition 1 | EFI System Partition | No |
| Partition 2 | /boot | RAID1 (md0) |
| Partition 3 | LVM PV | RAID1 (md1) |

Example:

```
Disk 1
-------
sda1   EFI
sda2   md0
sda3   md1

Disk 2
-------
sdb1   EFI
sdb2   md0
sdb3   md1
```

---

# Prerequisites

- Failed disk has been physically replaced.
- Server is booted successfully using the remaining healthy disk.
- Login as root.

---

# Phase 1 - Detect the Replacement Disk

Rescan the SCSI bus.

```bash
for host in /sys/class/scsi_host/host*; do
    echo "- - -" > "$host/scan"
done

partprobe
```

Display disks.

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
```

Example immediately after replacing Disk2:

```
NAME
sda
├── sda1
├── sda2
└── sda3

sdb
```

If the replacement disk shows **no partitions**, continue to Phase 2.

If partitions already exist (`sdb1`, `sdb2`, `sdb3`), skip to Phase 4.

---

# Phase 2 - Clone the GPT Partition Table

## Step 2.1 - Identify the Healthy Disk

Display mounted EFI.

```bash
mount | grep /boot/efi
```

If output is:

```
/dev/sda1 on /boot/efi
```

then

Healthy disk

```
sda
```

Replacement disk

```
sdb
```

---

If output is

```
/dev/sdb1 on /boot/efi
```

then

Healthy disk

```
sdb
```

Replacement disk

```
sda
```

---

## Step 2.2 - Clone GPT

### If healthy disk is sda

```bash
sgdisk --backup=/tmp/gpt.bin /dev/sda

sgdisk --load-backup=/tmp/gpt.bin /dev/sdb

sgdisk -G /dev/sdb

partprobe /dev/sdb
```

---

### If healthy disk is sdb

```bash
sgdisk --backup=/tmp/gpt.bin /dev/sdb

sgdisk --load-backup=/tmp/gpt.bin /dev/sda

sgdisk -G /dev/sda

partprobe /dev/sda
```

---

Verify.

```bash
lsblk
```

Expected

```
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

# Phase 3 - Prepare the Replacement Disk

## Create the EFI Filesystem

### If replacement disk is sdb

```bash
mkfs.vfat -F32 /dev/sdb1
```

---

### If replacement disk is sda

```bash
mkfs.vfat -F32 /dev/sda1
```

---

## Add RAID Members

### If replacement disk is sdb

```bash
mdadm --add /dev/md0 /dev/sdb2

mdadm --add /dev/md1 /dev/sdb3
```

---

### If replacement disk is sda

```bash
mdadm --add /dev/md0 /dev/sda2

mdadm --add /dev/md1 /dev/sda3
```

---

Monitor rebuild.

```bash
watch cat /proc/mdstat
```

Wait until

```
md0 [UU]

md1 [UU]
```

Do **NOT** continue until RAID rebuild completes.

---

# Phase 4 - Restore the EFI Bootloader

## Step 4.1 - Identify Active EFI

Run

```bash
mount | grep /boot/efi
```

---

### CASE 1

Output

```
/dev/sda1 on /boot/efi
```

This means

Healthy EFI

```
sda1
```

Replacement EFI

```
sdb1
```

Mount replacement EFI.

```bash
mkdir -p /mnt/efi2

mount /dev/sdb1 /mnt/efi2
```

---

### CASE 2

Output

```
/dev/sdb1 on /boot/efi
```

This means

Healthy EFI

```
sdb1
```

Replacement EFI

```
sda1
```

Mount replacement EFI.

```bash
mkdir -p /mnt/efi2

mount /dev/sda1 /mnt/efi2
```

---

Verify.

```bash
mount | grep efi
```

Expected

```
/boot/efi
/mnt/efi2
```

---

## Step 4.2 - Verify Source EFI

```bash
find /boot/efi -maxdepth 3 -type f
```

Expected files such as

```
EFI/BOOT/BOOTX64.EFI

EFI/ubuntu/shimx64.efi

EFI/ubuntu/grubx64.efi
```

If nothing is displayed,

STOP.

Wrong EFI partition is mounted.

---

## Step 4.3 - Install GRUB

```bash
grub-install \
    --target=x86_64-efi \
    --efi-directory=/mnt/efi2 \
    --bootloader-id=ubuntu \
    --removable \
    --recheck
```

Verify

```bash
find /mnt/efi2/EFI -maxdepth 3 -type f
```

---

## Step 4.4 - Synchronize EFI

```bash
rsync -aHAX --delete /boot/efi/ /mnt/efi2/

sync
```

---

## Step 4.5 - Verify Synchronization

```bash
diff -rq /boot/efi /mnt/efi2
```

Expected

```
(no output)
```

---

## Step 4.6 - Cleanup

```bash
umount /mnt/efi2
```

---

# Phase 5 - Final Verification

Verify RAID.

```bash
cat /proc/mdstat
```

Expected

```
md0 [UU]

md1 [UU]
```

---

Verify disks.

```bash
lsblk
```

---

Verify EFI entries.

```bash
efibootmgr -v
```

Expected

At least one Ubuntu boot entry.

---

# Phase 6 - Boot Failover Test

Shutdown.

```bash
shutdown -h now
```

Disconnect the healthy disk.

Boot using only the recovered disk.

Verify

```bash
lsblk

cat /proc/mdstat

efibootmgr -v
```

Expected

```
md0 degraded

md1 degraded
```

System should boot successfully.

Reconnect the original disk.

Boot normally.

Verify

```bash
cat /proc/mdstat
```

Expected

```
md0 [UU]

md1 [UU]
```

Recovery completed successfully.

---

# Post-Patch EFI Synchronization

Run this only after updates involving:

- Linux Kernel
- GRUB
- shim
- EFI packages

---

Determine the active EFI.

```bash
mount | grep /boot/efi
```

---

If mounted from

```
/dev/sda1
```

then

```bash
mkdir -p /mnt/efi2

mount /dev/sdb1 /mnt/efi2
```

---

If mounted from

```
/dev/sdb1
```

then

```bash
mkdir -p /mnt/efi2

mount /dev/sda1 /mnt/efi2
```

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

Synchronize EFI.

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
- [ ] RAID rebuilt (`md0 [UU]`, `md1 [UU]`)
- [ ] GRUB installed on replacement EFI
- [ ] EFI synchronized
- [ ] `diff -rq` returns no output
- [ ] `efibootmgr` shows Ubuntu entry
- [ ] Boot tested using recovered disk only
- [ ] Recovery completed successfully
