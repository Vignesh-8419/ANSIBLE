# Ubuntu 24.04 RAID1 Recovery SOP

## Assumptions

- The failed disk has been replaced.
- The system has booted successfully from the healthy disk.
- RAID rebuild has completed (`md0 [UU]`, `md1 [UU]`).

---

# Step 1 - Detect Disks

```bash
for host in /sys/class/scsi_host/host*; do
    echo "- - -" > "$host/scan"
done

partprobe

lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
```

---

# Step 2 - Verify RAID

```bash
cat /proc/mdstat
```

Continue only if

```
md0 [UU]

md1 [UU]
```

---

# Step 3 - Identify the Active EFI

Run

```bash
mount | grep /boot/efi
```

You will get **ONE** of these outputs.

---

## CASE 1

Output:

```
/dev/sda1 on /boot/efi
```

This means

- Healthy EFI = **sda1**
- Replacement EFI = **sdb1**

Run:

```bash
mkdir -p /mnt/efi2

mount /dev/sdb1 /mnt/efi2
```

Verify

```bash
mount | grep efi
```

Expected

```
/dev/sda1 on /boot/efi
/dev/sdb1 on /mnt/efi2
```

Proceed to **Step 4**.

---

## CASE 2

Output:

```
/dev/sdb1 on /boot/efi
```

This means

- Healthy EFI = **sdb1**
- Replacement EFI = **sda1**

Run

```bash
mkdir -p /mnt/efi2

mount /dev/sda1 /mnt/efi2
```

Verify

```bash
mount | grep efi
```

Expected

```
/dev/sdb1 on /boot/efi
/dev/sda1 on /mnt/efi2
```

Proceed to **Step 4**.

---

# Step 4 - Verify Healthy EFI

```bash
find /boot/efi -maxdepth 3 -type f
```

Expected

```
EFI/BOOT/BOOTX64.EFI
```

or

```
EFI/ubuntu/shimx64.efi
EFI/ubuntu/grubx64.efi
```

If nothing is displayed,

STOP.

Wrong EFI partition is mounted.

---

# Step 5 - Install GRUB

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

# Step 6 - Synchronize EFI

```bash
rsync -aHAX --delete /boot/efi/ /mnt/efi2/

sync
```

---

# Step 7 - Verify Synchronization

```bash
diff -rq /boot/efi /mnt/efi2
```

Expected

```
(no output)
```

---

# Step 8 - Cleanup

```bash
umount /mnt/efi2
```

---

# Step 9 - Verify

```bash
cat /proc/mdstat

efibootmgr -v

lsblk
```

Expected

```
md0 [UU]

md1 [UU]
```

---

# Step 10 - Boot Test

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

System should boot successfully.

Recovery completed.

---

# Post-Patch EFI Synchronization

After any

- Kernel update
- GRUB update
- shim update

Run

```bash
mount | grep /boot/efi
```

---

## If output is

```
/dev/sda1 on /boot/efi
```

Run

```bash
mkdir -p /mnt/efi2

mount /dev/sdb1 /mnt/efi2
```

---

## If output is

```
/dev/sdb1 on /boot/efi
```

Run

```bash
mkdir -p /mnt/efi2

mount /dev/sda1 /mnt/efi2
```

Then execute

```bash
grub-install \
    --target=x86_64-efi \
    --efi-directory=/mnt/efi2 \
    --bootloader-id=ubuntu \
    --removable \
    --recheck

rsync -aHAX --delete /boot/efi/ /mnt/efi2/

sync

diff -rq /boot/efi /mnt/efi2

umount /mnt/efi2
```

Expected

```
(no output)
```
