# CentOS 7 UEFI RAID1 Recovery SOP
## Enterprise Golden Image Recovery Guide

**Platform:** CentOS 7.9  
**Boot Mode:** UEFI  
**Partition Table:** GPT  
**RAID:** mdadm RAID1  
**Volume Manager:** LVM

> **IMPORTANT**
>
> - EFI System Partition (ESP) is **NOT RAID**.
> - Both disks must contain their own FAT32 EFI partition.
> - `/boot` and LVM are RAID1.
> - Never run recovery commands while replacing the currently running system disk.
> - Perform disk replacement only after shutdown or when booted from the surviving disk.

---

# Scenario 1 - Disk 1 (sda) Failed

## Step 1 - Verify RAID

```bash
lsblk
cat /proc/mdstat
```

Expected:

```
md0 : [U_]
md1 : [U_]
```

or

```
md0 : [_U]
md1 : [_U]
```

depending on which member failed.

---

## Step 2 - Shutdown

```bash
shutdown -h now
```

Replace the failed **Disk 1 (sda)** with a new disk of equal or larger capacity.

Power on the system.

---

## Step 3 - Verify New Disk

```bash
lsblk
```

Example

```
sda   100G
sdb   100G
```

The replacement disk should contain no partitions.

---

## Step 4 - Clone GPT from Good Disk

Good disk = **sdb**

Destination = **sda**

```bash
sgdisk --replicate=/dev/sda /dev/sdb
```

Assign a new GPT disk GUID.

```bash
sgdisk -G /dev/sda
```

Reload the partition table.

```bash
partprobe /dev/sda
udevadm settle
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

## Step 5 - Rebuild RAID

```bash
mdadm --add /dev/md0 /dev/sda2
mdadm --add /dev/md1 /dev/sda3
```

Monitor rebuild.

```bash
watch cat /proc/mdstat
```

Wait until

```
md0 : [UU]
md1 : [UU]
```

---

## Step 6 - Create EFI Partition

```bash
mkfs.vfat -F32 /dev/sda1
```

---

## Step 7 - Copy EFI Files

Create mount points.

```bash
mkdir -p /mnt/efi-src
mkdir -p /mnt/efi-dst
```

Mount the working ESP.

```bash
mount /dev/sdb1 /mnt/efi-src
```

Mount the new ESP.

```bash
mount /dev/sda1 /mnt/efi-dst
```

Copy the EFI files.

```bash
cp -a /mnt/efi-src/EFI /mnt/efi-dst/
sync
```

Verify.

```bash
find /mnt/efi-dst/EFI -type f | sort
```

Unmount.

```bash
umount /mnt/efi-src
umount /mnt/efi-dst
```

---

## Step 8 - Install GRUB on New EFI Partition

Mount the new ESP.

```bash
mount /dev/sda1 /boot/efi
```

Install GRUB.

```bash
grub2-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=CentOS \
    --recheck
```

Generate configuration.

```bash
grub2-mkconfig -o /boot/grub2/grub.cfg
```

Unmount.

```bash
umount /boot/efi
```

---

## Step 9 - Create UEFI Boot Entry

```bash
efibootmgr \
    -c \
    -d /dev/sda \
    -p 1 \
    -L "CentOS RAID1 Disk 1" \
    -l '\EFI\centos\shimx64.efi'
```

Verify.

```bash
efibootmgr -v
```

---

## Step 10 - Save RAID Configuration

```bash
mdadm --detail --scan > /etc/mdadm.conf
```

---

# Scenario 2 - Disk 2 (sdb) Failed

## Step 1 - Verify RAID

```bash
lsblk
cat /proc/mdstat
```

---

## Step 2 - Shutdown

```bash
shutdown -h now
```

Replace failed **Disk 2 (sdb)**.

Power on the system.

---

## Step 3 - Verify New Disk

```bash
lsblk
```

The new disk should contain no partitions.

---

## Step 4 - Clone GPT

Good disk = **sda**

Destination = **sdb**

```bash
sgdisk --replicate=/dev/sdb /dev/sda
```

Generate new GPT GUID.

```bash
sgdisk -G /dev/sdb
```

Reload.

```bash
partprobe /dev/sdb
udevadm settle
```

Verify.

```bash
lsblk
```

Expected

```
sdb1
sdb2
sdb3
```

---

## Step 5 - Rebuild RAID

```bash
mdadm --add /dev/md0 /dev/sdb2
mdadm --add /dev/md1 /dev/sdb3
```

Monitor.

```bash
watch cat /proc/mdstat
```

Wait until

```
md0 : [UU]
md1 : [UU]
```

---

## Step 6 - Create EFI Filesystem

```bash
mkfs.vfat -F32 /dev/sdb1
```

---

## Step 7 - Copy EFI Files

```bash
mkdir -p /mnt/efi-src
mkdir -p /mnt/efi-dst
```

Mount the working ESP.

```bash
mount /dev/sda1 /mnt/efi-src
```

Mount the new ESP.

```bash
mount /dev/sdb1 /mnt/efi-dst
```

Copy.

```bash
cp -a /mnt/efi-src/EFI /mnt/efi-dst/
sync
```

Verify.

```bash
find /mnt/efi-dst/EFI -type f | sort
```

Unmount.

```bash
umount /mnt/efi-src
umount /mnt/efi-dst
```

---

## Step 8 - Install GRUB

```bash
mount /dev/sdb1 /boot/efi

grub2-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=CentOS \
    --recheck

grub2-mkconfig -o /boot/grub2/grub.cfg

umount /boot/efi
```

---

## Step 9 - Create UEFI Boot Entry

```bash
efibootmgr \
    -c \
    -d /dev/sdb \
    -p 1 \
    -L "CentOS RAID1 Disk 2" \
    -l '\EFI\centos\shimx64.efi'
```

Verify.

```bash
efibootmgr -v
```

---

## Step 10 - Save RAID Configuration

```bash
mdadm --detail --scan > /etc/mdadm.conf
```

---

# Post Recovery Validation

## RAID

```bash
cat /proc/mdstat
```

Expected

```
md0 : [UU]
md1 : [UU]
```

---

## Block Devices

```bash
lsblk
```

---

## EFI Partitions

```bash
mkdir -p /mnt/test

mount /dev/sda1 /mnt/test
find /mnt/test/EFI -type f | sort
umount /mnt/test

mount /dev/sdb1 /mnt/test
find /mnt/test/EFI -type f | sort
umount /mnt/test
```

---

## UEFI Entries

```bash
efibootmgr -v
```

Verify that both disks have boot entries.

---

## RAID Detail

```bash
mdadm --detail /dev/md0
mdadm --detail /dev/md1
```

---

## Enable Verbose Boot

```bash
mkdir -p /root/scripts

curl --retry 5 --retry-delay 2 -fsSL \
-o /root/scripts/enable-verbose-boot.sh \
"https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/enable-verbose-boot.sh?$(date +%s)"

chmod +x /root/scripts/enable-verbose-boot.sh

/root/scripts/enable-verbose-boot.sh
```

---

## LVM

```bash
pvs
vgs
lvs
```

---

## Filesystems

```bash
df -h
```

---

# Recovery Completed

Recovery is successful when:

- ✅ GPT exists on both disks
- ✅ Both EFI partitions are FAT32
- ✅ Both EFI partitions contain bootloader files
- ✅ GRUB is installed on both EFI partitions
- ✅ UEFI boot entries exist for both disks
- ✅ md0 shows `[UU]`
- ✅ md1 shows `[UU]`
- ✅ LVM is healthy
- ✅ System boots successfully with either disk removed
