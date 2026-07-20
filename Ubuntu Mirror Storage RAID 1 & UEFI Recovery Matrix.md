# Ubuntu Mirror Storage RAID 1 & UEFI Recovery Matrix

This document provides immediate, actionable steps to restore storage parity and boot redundancy after replacing a failed disk drive.

---

## 🚨 Pre-Recovery System Verification

Before executing any commands, verify the system's current block device names and array mapping configuration.

```bash
# Verify active/missing block partitions
lsblk

# Check the status of degraded RAID arrays
cat /proc/mdstat
```

> **IMPORTANT ASSUMPTION:** In the procedures below, `/dev/sda` represents the surviving healthy drive, and `/dev/sdb` represents the newly installed replacement drive. If your system identifies them differently, swap the names accordingly.

---

## 📂 Scenario A: Replacing Drive `sdb` (Secondary Drive Failed)
*The primary active partition (`/dev/sda1` mounted at `/boot/efi`) is running normally. The system booted successfully from the primary disk.*

### Execution Commands

```bash
# 1. Clone the working partition map from sda directly over to sdb
sfdisk -d /dev/sda | sfdisk /dev/sdb

# 2. Re-attach the new raw space blocks back to the active RAID paths
mdadm --manage /dev/md0 --add /dev/sdb2
mdadm --manage /dev/md1 --add /dev/sdb3

# 3. Provision a clean FAT32 filesystem table layer onto the new EFI space
mkfs.vfat -F32 /dev/sdb1

# 4. Copy the primary boot configuration files onto the secondary target
dd if=/dev/sda1 of=/dev/sdb1 bs=4M status=progress

# 5. Deploy boot records onto the new hardware tracking block
grub-install /dev/sdb
update-grub

# 6. Re-map the non-blocking /etc/fstab entry with the new drive's unique signature
NEW_UUID=$(blkid -s UUID -o value /dev/sdb1)
sed -i "/\/boot\/efi2/c\UUID=${NEW_UUID} /boot/efi2 vfat defaults,nofail 0 2" /etc/fstab
```

---

## 📂 Scenario B: Replacing Drive `sda` (Primary Drive Failed)
*The primary drive died. The system used the fallback paths to boot from the secondary drive. In this state, the surviving drive typically maps to `/dev/sda` inside the operating system, and the new replacement drive shows up as `/dev/sdb`.*

### Execution Commands

```bash
# 1. Copy the layout map from the surviving drive over to the replacement drive
sfdisk -d /dev/sda | sfdisk /dev/sdb

# 2. Add the new partitions to the degraded RAID arrays
mdadm --manage /dev/md0 --add /dev/sdb2
mdadm --manage /dev/md1 --add /dev/sdb3

# 3. Format the replacement EFI partition to FAT32
mkfs.vfat -F32 /dev/sdb1

# 4. Clone the active boot tracks onto the new partition
dd if=/dev/sda1 of=/dev/sdb1 bs=4M status=progress

# 5. Install the GRUB bootloader components to the new drive
grub-install /dev/sdb
update-grub

# 6. Update the /etc/fstab UUID tracking rule to match the new hardware signature
NEW_UUID=$(blkid -s UUID -o value /dev/sdb1)
sed -i "/\/boot\/efi2/c\UUID=${NEW_UUID} /boot/efi2 vfat defaults,nofail 0 2" /etc/fstab
```

---

## ⏳ Rebuild Tracking & Status Verification

Once added, data mirroring runs asynchronously in the background. Performance may be slightly impacted until synchronization completes.

Monitor progress using:
```bash
watch -n 1 cat /proc/mdstat
```

**Expected Healthy Output Example:**
```text
md0 : active raid1 sda2[0] sdb2[1]
      2094080 blocks super 1.2 [2/2] [UU]

md1 : active raid1 sda3[0] sdb3[1]
      100596736 blocks super 1.2 [2/2] [UU]
```
*(The `[UU]` token verifies that both storage segments are running in an optimal, mirrored state).*
