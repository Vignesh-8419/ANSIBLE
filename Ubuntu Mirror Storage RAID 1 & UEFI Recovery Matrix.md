# Ubuntu 24.04 RAID1 Disk Recovery SOP

> Assumption:
> - The system has successfully booted from the healthy disk.
> - `/boot/efi` is already mounted from the healthy disk.
> - Replace `<NEW_DISK>` with `sda` or `sdb` depending on which disk failed.

---

# 1. Detect New Disk

```bash
for host in /sys/class/scsi_host/host*; do
    echo "- - -" > "$host/scan"
done

lsblk
```

---

# 2. Clone Partition Table

## If replacing sda

```bash
sgdisk --backup=/tmp/sdb-gpt.bin /dev/sdb
sgdisk --load-backup=/tmp/sdb-gpt.bin /dev/sda
sgdisk -G /dev/sda
partprobe /dev/sda
```

## If replacing sdb

```bash
sgdisk --backup=/tmp/sda-gpt.bin /dev/sda
sgdisk --load-backup=/tmp/sda-gpt.bin /dev/sdb
sgdisk -G /dev/sdb
partprobe /dev/sdb
```

Verify:

```bash
lsblk
```

---

# 3. Create EFI Filesystem

## If replacing sda

```bash
mkfs.vfat -F32 /dev/sda1
```

## If replacing sdb

```bash
mkfs.vfat -F32 /dev/sdb1
```

---

# 4. Rebuild RAID

## If replacing sda

```bash
mdadm --add /dev/md0 /dev/sda2
mdadm --add /dev/md1 /dev/sda3
```

## If replacing sdb

```bash
mdadm --add /dev/md0 /dev/sdb2
mdadm --add /dev/md1 /dev/sdb3
```

Monitor rebuild:

```bash
watch cat /proc/mdstat
```

Continue only after RAID rebuild completes:

```
md0 [UU]
md1 [UU]
```

---

# 5. Verify EFI Mount

```bash
mount | grep /boot/efi
```

Expected:

```
/dev/sda1 on /boot/efi
```

or

```
/dev/sdb1 on /boot/efi
```

If `/boot/efi` is **not** mounted, stop and mount the healthy EFI partition before continuing.

---

# 6. Mount Replacement EFI

```bash
mkdir -p /mnt/efi2
```

## If replacing sda

```bash
mount /dev/sda1 /mnt/efi2
```

## If replacing sdb

```bash
mount /dev/sdb1 /mnt/efi2
```

Verify:

```bash
mount | grep efi
```

Expected:

```
/boot/efi
/mnt/efi2
```

---

# 7. Verify Source EFI

```bash
find /boot/efi -maxdepth 3 -type f
```

If this returns no files, stop and investigate.

---

# 8. Install GRUB on Replacement EFI

```bash
grub-install \
    --target=x86_64-efi \
    --efi-directory=/mnt/efi2 \
    --bootloader-id=ubuntu \
    --removable \
    --recheck
```

---

# 9. Synchronize EFI

```bash
rsync -aHAX --delete /boot/efi/ /mnt/efi2/

sync
```

---

# 10. Verify EFI Synchronization

```bash
diff -rq /boot/efi /mnt/efi2
```

Expected:

```
(no output)
```

---

# 11. Cleanup

```bash
umount /mnt/efi2
```

---

# 12. Verify RAID

```bash
cat /proc/mdstat
```

Expected:

```
md0 [UU]
md1 [UU]
```

---

# 13. Verify Boot Entries

```bash
efibootmgr -v
```

---

# 14. Boot Failover Test

Shutdown:

```bash
shutdown -h now
```

Disconnect the healthy disk and boot using only the recovered disk.

Verify:

```bash
lsblk

cat /proc/mdstat

efibootmgr -v
```

Expected:

If booting from **sda**:

```
md0 [U_]
md1 [U_]
```

If booting from **sdb**:

```
md0 [_U]
md1 [_U]
```

Boot successful = Recovery completed.

---

# Post-Patch EFI Synchronization

Run this only after updates that include:

- Linux Kernel
- GRUB
- shim
- EFI bootloader packages

```bash
mkdir -p /mnt/efi2
```

Mount the secondary EFI partition:

```bash
mount /dev/sdb1 /mnt/efi2
```

(or `/dev/sda1` if booted from Disk 2)

Update GRUB:

```bash
grub-install \
    --target=x86_64-efi \
    --efi-directory=/mnt/efi2 \
    --bootloader-id=ubuntu \
    --removable \
    --recheck
```

Synchronize:

```bash
rsync -aHAX --delete /boot/efi/ /mnt/efi2/

sync

diff -rq /boot/efi /mnt/efi2

umount /mnt/efi2
```

Expected:

```
(no output)
```
