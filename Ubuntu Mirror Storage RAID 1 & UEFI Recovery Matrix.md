# Ubuntu 24.04 RAID1 Recovery SOP

## Prerequisites

- Replace the failed disk.
- Boot the server from the remaining healthy disk.
- Login as root.

---

# Step 1 - Detect the New Disk

Rescan storage.

```bash
for host in /sys/class/scsi_host/host*; do
    echo "- - -" > "$host/scan"
done

partprobe

lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
```

Identify:

- Healthy disk
- New replacement disk

---

# Step 2 - Identify Current EFI

```bash
mount | grep /boot/efi
```

Example:

```
/dev/sda1 on /boot/efi
```

This is your **healthy EFI**.

Remember this device.

---

# Step 3 - Clone GPT

Assume

Healthy disk = /dev/<HEALTHY_DISK>

Replacement disk = /dev/<NEW_DISK>

```bash
sgdisk --backup=/tmp/gpt.bin /dev/<HEALTHY_DISK>

sgdisk --load-backup=/tmp/gpt.bin /dev/<NEW_DISK>

sgdisk -G /dev/<NEW_DISK>

partprobe /dev/<NEW_DISK>
```

Verify

```bash
lsblk
```

---

# Step 4 - Create EFI Filesystem

```bash
mkfs.vfat -F32 /dev/<NEW_DISK>1
```

---

# Step 5 - Add RAID Members

```bash
mdadm --add /dev/md0 /dev/<NEW_DISK>2

mdadm --add /dev/md1 /dev/<NEW_DISK>3
```

Monitor rebuild

```bash
watch cat /proc/mdstat
```

Continue only after

```
md0 [UU]

md1 [UU]
```

---

# Step 6 - Mount Replacement EFI

Create mount point

```bash
mkdir -p /mnt/efi2
```

Mount the replacement EFI

```bash
mount /dev/<NEW_DISK>1 /mnt/efi2
```

Verify

```bash
mount | grep efi
```

Expected

```
/boot/efi
/mnt/efi2
```

---

# Step 7 - Verify Healthy EFI

```bash
find /boot/efi -maxdepth 3 -type f
```

If no files are displayed, stop and investigate.

---

# Step 8 - Install GRUB

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

# Step 9 - Synchronize EFI

```bash
rsync -aHAX --delete /boot/efi/ /mnt/efi2/

sync
```

---

# Step 10 - Verify Synchronization

```bash
diff -rq /boot/efi /mnt/efi2
```

Expected

```
(no output)
```

---

# Step 11 - Cleanup

```bash
umount /mnt/efi2
```

---

# Step 12 - Verify RAID

```bash
cat /proc/mdstat
```

Expected

```
md0 [UU]

md1 [UU]
```

---

# Step 13 - Verify Boot Entries

```bash
efibootmgr -v
```

---

# Step 14 - Boot Validation

Shutdown

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

System boots successfully
```

Recovery completed.

---

# Post Patch EFI Synchronization

Run after updating:

- Linux Kernel
- GRUB
- shim
- EFI packages

Identify the secondary EFI partition.

```bash
lsblk -f
```

Mount it.

```bash
mkdir -p /mnt/efi2

mount /dev/<SECONDARY_EFI> /mnt/efi2
```

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
```

Cleanup.

```bash
umount /mnt/efi2
```

---

# Final Validation

```bash
cat /proc/mdstat

efibootmgr -v

lsblk

diff -rq /boot/efi /mnt/efi2
```

Expected

- RAID Healthy
- No diff output
- GRUB installed
- Boot entries present
- Both disks independently bootable
