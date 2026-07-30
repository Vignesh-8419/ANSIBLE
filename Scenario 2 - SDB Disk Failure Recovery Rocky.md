# Rocky Linux 8.10 UEFI + GPT + Software RAID1 Recovery SOP
## SDB Failure Recovery (Disk2 Replacement)

---

# Purpose

This SOP describes the complete recovery procedure when **Disk2 (/dev/sdb)** has failed and has been replaced with a new disk.

This procedure has been validated on:

- Rocky Linux 8.10
- UEFI Boot
- GPT Partition Table
- Software RAID1 (mdadm)
- LVM
- VMware ESXi

---

# Storage Layout

| Disk | Partition | Purpose |
|------|-----------|---------|
| sda1 | EFI System Partition | FAT32 |
| sda2 | RAID1 (/boot) | md0 |
| sda3 | RAID1 (LVM PV) | md1 |
| sdb1 | EFI System Partition | FAT32 |
| sdb2 | RAID1 (/boot) | md0 |
| sdb3 | RAID1 (LVM PV) | md1 |

---

# Step 1 - Verify RAID Status

```bash
cat /proc/mdstat

mdadm --detail /dev/md0

mdadm --detail /dev/md1

lsblk
```

Expected

- md0 degraded
- md1 degraded

---

# Step 2 - Verify Replacement Disk

```bash
lsblk

fdisk -l

lsscsi -g
```

Verify the new replacement disk is visible.

---

# Step 3 - Clone Partition Table

Copy the GPT partition table.

```bash
sgdisk -R=/dev/sdb /dev/sda
```

Generate new GPT GUIDs.

```bash
sgdisk -G /dev/sdb
```

Reload partition table.

```bash
partprobe /dev/sdb

udevadm settle
```

Verify

```bash
fdisk -l /dev/sdb

lsblk
```

---

# Step 4 - Rebuild RAID Arrays

Add /boot member.

```bash
mdadm --manage /dev/md0 --add /dev/sdb2
```

Add LVM member.

```bash
mdadm --manage /dev/md1 --add /dev/sdb3
```

Monitor rebuild.

```bash
watch cat /proc/mdstat
```

Wait until

```
[UU]
```

Verify

```bash
cat /proc/mdstat

mdadm --detail /dev/md0

mdadm --detail /dev/md1
```

---

# Step 5 - Create EFI Filesystem

Format the EFI partition.

```bash
mkfs.vfat -F32 -n EFI-SYSTEM /dev/sdb1
```

Verify.

```bash
blkid /dev/sdb1
```

Expected

```
TYPE="vfat"
```

---

# Step 6 - Copy EFI Boot Files

Create mount points.

```bash
mkdir -p /mnt/sda1

mkdir -p /mnt/sdb1
```

Mount both EFI partitions.

```bash
mount /dev/sda1 /mnt/sda1

mount /dev/sdb1 /mnt/sdb1
```

Copy files.

```bash
cp -a /mnt/sda1/* /mnt/sdb1/
```

Flush writes.

```bash
sync
```

Verify.

```bash
find /mnt/sdb1/EFI
```

Expected

```
EFI/BOOT

EFI/rocky

shimx64.efi

grubx64.efi
```

Unmount.

```bash
umount /mnt/sda1

umount /mnt/sdb1
```

---

# Step 7 - Configure /boot/efi Mount (IMPORTANT)

Verify if EFI is mounted.

```bash
findmnt /boot/efi
```

If nothing is returned:

Obtain the UUID.

```bash
blkid /dev/sda1
```

Edit fstab.

```bash
vi /etc/fstab
```

Add the following entry.

```fstab
UUID=<UUID_of_sda1> /boot/efi vfat umask=0077,shortname=winnt,nofail,x-systemd.device-timeout=1s 0 2
```

Example

```fstab
UUID=C642-C512 /boot/efi vfat umask=0077,shortname=winnt,nofail,x-systemd.device-timeout=1s 0 2
```

Reload systemd.

```bash
systemctl daemon-reload
```

Create mount point.

```bash
mkdir -p /boot/efi
```

Mount.

```bash
mount -a
```

Verify.

```bash
findmnt /boot/efi
```

Expected

```
TARGET      SOURCE

/boot/efi   /dev/sda1
```

---

# Why "nofail" is Required

The two EFI System Partitions have different FAT filesystem UUIDs.

Example

```
Disk1 EFI

UUID=C642-C512

Disk2 EFI

UUID=7A78-D0E7
```

Only one UUID can exist in `/etc/fstab`.

During a disk failure, the configured EFI partition may not be present.

Without:

```
nofail,x-systemd.device-timeout=1s
```

systemd treats the missing EFI partition as a boot failure and enters Emergency Mode.

Adding these options allows the system to continue booting normally while the RAID arrays operate in degraded mode.

This behaviour has been validated by testing a single-disk boot after removing Disk1.

---

# Step 8 - Verify UEFI Boot Entries

Display firmware entries.

```bash
efibootmgr -v
```

Verify

- Rocky Linux boot entries exist.
- Loader path is

```
\EFI\rocky\shimx64.efi
```

Display partition identifiers.

```bash
blkid /dev/sda1

blkid /dev/sdb1
```

Remove mismatch entries 

Example

```bash
efibootmgr -b 000*,000*
```


If a Rocky boot entry is missing, recreate it.

Disk1

```bash
efibootmgr \
-c \
-d /dev/sda \
-p 1 \
-L "Rocky Linux Disk1" \
-l '\EFI\rocky\shimx64.efi'
```

Disk2

```bash
efibootmgr \
-c \
-d /dev/sdb \
-p 1 \
-L "Rocky Linux Disk2" \
-l '\EFI\rocky\shimx64.efi'
```

Set boot order if required.

Example

```bash
efibootmgr -o 0006,0007
```

Replace with your actual Boot IDs.

Verify.

```bash
efibootmgr -v
```

---

# Step 9 - Final Verification

```bash
cat /proc/mdstat

lsblk

blkid

findmnt /boot/efi

efibootmgr -v
```

Expected

```
md0 [UU]

md1 [UU]
```

EFI mounted.

```
/boot/efi
```

Rocky boot entries present.

---

# Step 10 - Functional Validation

## Test Disk2 Failure

Remove Disk2.

Boot the server.

Verify

```bash
cat /proc/mdstat
```

Expected

```
md0 [U_]

md1 [U_]
```

Server boots successfully.

---

## Test Disk1 Failure

Reconnect Disk2.

Remove Disk1.

Boot the server.

Verify

```bash
cat /proc/mdstat
```

Expected

```
md0 [U_]

md1 [U_]
```

Server boots successfully.

No Emergency Mode should occur because `/boot/efi` is configured with:

```
nofail,x-systemd.device-timeout=1s
```

---

# Recovery Completed

Recovery is successful when:

- GPT partition table cloned successfully.
- New GPT GUID generated.
- RAID rebuilt.
- md0 healthy.
- md1 healthy.
- EFI filesystem recreated.
- EFI files copied.
- /boot/efi configured in `/etc/fstab`.
- `/boot/efi` uses:
  - `nofail`
  - `x-systemd.device-timeout=1s`
- EFI mounts successfully.
- Rocky boot entries exist.
- System boots with Disk1 removed.
- System boots with Disk2 removed.
- RAID operates correctly in degraded mode.
- No Emergency Mode occurs during single-disk boot.

---

**Document Version:** 1.1  
**Operating System:** Rocky Linux 8.10  
**Boot Mode:** UEFI  
**Storage:** GPT + Software RAID1 + LVM  
**Validation:** Tested with simulated Disk2 replacement and single-disk boot failover.
