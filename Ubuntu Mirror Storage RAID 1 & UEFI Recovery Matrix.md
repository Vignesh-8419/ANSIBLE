# Ubuntu 24.04 RAID1 Disk Recovery SOP

## Purpose

Recover a failed disk in an Ubuntu 24.04 server configured with:

- UEFI Boot
- Software RAID1
- Dual EFI System Partitions
- RAID1 /boot
- RAID1 LVM PV
- LVM Root Filesystem

---

# Storage Layout

Disk 1

sda1  EFI (FAT32)
sda2  md0 (/boot)
sda3  md1 (LVM)

Disk 2

sdb1  EFI (FAT32)
sdb2  md0 (/boot)
sdb3  md1 (LVM)

---

# Phase 1 - Detect Replacement Disk

Rescan disks

```bash
for host in /sys/class/scsi_host/host*; do
    echo "- - -" > "$host/scan"
done

partprobe
```

Verify

```bash
lsblk
```

If the replacement disk has no partitions, continue to Phase 2.

---

# Phase 2 - Clone GPT

Determine the healthy disk.

```bash
mount | grep /boot/efi
```

If mounted from

```
/dev/sda1
```

Healthy disk

```
sda
```

Replacement disk

```
sdb
```

Clone GPT

```bash
sgdisk --backup=/tmp/gpt.bin /dev/sda

sgdisk --load-backup=/tmp/gpt.bin /dev/sdb

sgdisk -G /dev/sdb

partprobe /dev/sdb
```

If mounted from

```
/dev/sdb1
```

Healthy disk

```
sdb
```

Replacement disk

```
sda
```

Clone GPT

```bash
sgdisk --backup=/tmp/gpt.bin /dev/sdb

sgdisk --load-backup=/tmp/gpt.bin /dev/sda

sgdisk -G /dev/sda

partprobe /dev/sda
```

Verify

```bash
lsblk
```

Expected

```
sda1
sda2
sda3

sdb1
sdb2
sdb3
```

---

# Phase 3 - Prepare Replacement Disk

Create EFI filesystem.

If replacement disk is sdb

```bash
mkfs.vfat -F32 /dev/sdb1
```

If replacement disk is sda

```bash
mkfs.vfat -F32 /dev/sda1
```

Verify

```bash
blkid
```

The replacement EFI should show

```
TYPE="vfat"
```

Add RAID members.

Example (replacement disk sdb)

```bash
mdadm --add /dev/md0 /dev/sdb2

mdadm --add /dev/md1 /dev/sdb3
```

Monitor rebuild

```bash
watch cat /proc/mdstat
```

Wait until BOTH arrays show

```
md0 [UU]

md1 [UU]
```

Do not continue until rebuild completes.

---

# Phase 4 - Restore EFI

Determine active EFI.

```bash
mount | grep /boot/efi
```

If active EFI is

```
/dev/sda1
```

Mount replacement EFI

```bash
mkdir -p /mnt/efi2

mount /dev/sdb1 /mnt/efi2
```

If active EFI is

```
/dev/sdb1
```

Mount replacement EFI

```bash
mkdir -p /mnt/efi2

mount /dev/sda1 /mnt/efi2
```

Verify the mount.

```bash
mount | grep efi
```

Expected

```
/dev/sda1 on /boot/efi

/dev/sdb1 on /mnt/efi2
```

(or vice versa)

**IMPORTANT**

Verify `/mnt/efi2` is mounted from the replacement EFI partition before continuing.

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

Verify

```bash
find /mnt/efi2/EFI -maxdepth 3 -type f
```

---

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

Unmount.

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

Verify storage.

```bash
lsblk
```

Verify EFI entries.

```bash
efibootmgr -v
```

Expected

At least one Ubuntu boot entry.

---

# Phase 6 - Boot Failover Test

Power off.

```bash
shutdown -h now
```

Disconnect the healthy disk.

Boot using only the recovered disk.

Verify

```bash
lsblk

cat /proc/mdstat

mount | grep /boot/efi

efibootmgr -v
```

Expected

- System boots successfully.
- RAID is degraded (expected).
- Ubuntu boot entry exists.

Reconnect the healthy disk.

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

After updating any of the following:

- Linux kernel
- GRUB
- shim
- EFI packages

Determine the active EFI.

```bash
mount | grep /boot/efi
```

Mount the inactive EFI.

Verify

```bash
mount | grep efi
```

Ensure:

- `/boot/efi` = active EFI
- `/mnt/efi2` = inactive EFI

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
- [ ] RAID rebuild complete (`md0 [UU]`, `md1 [UU]`)
- [ ] Replacement EFI mounted correctly
- [ ] GRUB installed on replacement EFI
- [ ] EFI synchronized
- [ ] `diff -rq` returns no output
- [ ] `efibootmgr` shows Ubuntu entry
- [ ] Boot tested using recovered disk only
- [ ] Recovery completed
