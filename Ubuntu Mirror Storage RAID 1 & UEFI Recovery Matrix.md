# Ubuntu 24.04 LTS RAID 1 + LVM Manual Recovery Runbook

This guide covers the exact manual command sequences required to hot-plug a new disk and restore full mirror redundancy on an Ubuntu 24.04 LTS dual-disk system.

---

## ⚠️ Crucial Note on Kernel Device Mapping
When **Disk 1 (`sda`)** completely fails or is removed, the virtual motherboard shifts boot operations over to **Disk 2 (`sdb`)**. Upon entering the live operating system, **the surviving second disk automatically shifts into the primary `/dev/sda` device slot.** 

Because of this kernel reallocation behavior, in **both** failure scenarios, your brand-new, empty replacement hard drive will always register inside the OS as **`/dev/sdb`**.

---

## Scenario A: Disk 1 (`sda`) Failed & Is Replaced

Use this exact command sequence if `cat /proc/mdstat` shows a degraded state of **`[_U]`**, indicating that the first disk is missing or dead.

```bash
# 1. Force the SCSI bus to scan and detect the hot-plugged replacement disk live
for host in /sys/class/scsi_host/host*; do echo "- - -" > \${host}/scan; done

# 2. Verify that the new blank drive appears on your screen as 'sdb'
lsblk

# 3. Clone the exact partition layout structure from sda over to sdb
sfdisk -d /dev/sda | sfdisk /dev/sdb

# 4. Add the new partition tracks back into your active RAID arrays
mdadm --manage /dev/md0 --add /dev/sdb2
mdadm --manage /dev/md1 --add /dev/sdb3

# 5. Format the new partition into a clean FAT32 EFI track configuration
mkfs.vfat -F32 /dev/sdb1

# 6. Mount the secondary EFI directory target path
mount /dev/sdb1 /boot/efi2

# 7. Mirror your active boot configuration tracking files onto the new blocks
cp -a /boot/efi/. /boot/efi2/

# 8. Dynamically rewrite the /etc/fstab entry to map the new disk's unique UUID
NEW_UUID=\$(blkid -s UUID -o value /dev/sdb1)
sed -i "/\/boot\/efi2/c\UUID=\${NEW_UUID} /boot/efi2 vfat defaults,nofail 0 2" /etc/fstab

# 9. Install standalone fallback GRUB records to make the new drive self-bootable
grub-install --removable /dev/sdb
update-grub
```

---

## Scenario B: Disk 2 (`sdb`) Failed & Is Replaced

Use this exact command sequence if `cat /proc/mdstat` shows a degraded state of **`[U_]`**, indicating that the second disk is missing or dead.

```bash
# 1. Force the SCSI bus to scan and detect the hot-plugged replacement disk live
for host in /sys/class/scsi_host/host*; do echo "- - -" > \${host}/scan; done

# 2. Verify that the new blank drive appears on your screen as 'sdb'
lsblk

# 3. Clone the exact partition layout structure from sda over to sdb
sfdisk -d /dev/sda | sfdisk /dev/sdb

# 4. Add the new partition tracks back into your active RAID arrays
mdadm --manage /dev/md0 --add /dev/sdb2
mdadm --manage /dev/md1 --add /dev/sdb3

# 5. Format the new partition into a clean FAT32 EFI track configuration
mkfs.vfat -F32 /dev/sdb1

# 6. Mount the secondary EFI directory target path
mount /dev/sdb1 /boot/efi2

# 7. Mirror your active boot configuration tracking files onto the new blocks
cp -a /boot/efi/. /boot/efi2/

# 8. Dynamically rewrite the /etc/fstab entry to map the new disk's unique UUID
NEW_UUID=\$(blkid -s UUID -o value /dev/sdb1)
sed -i "/\/boot\/efi2/c\UUID=\${NEW_UUID} /boot/efi2 vfat defaults,nofail 0 2" /etc/fstab

# 9. Install standalone fallback GRUB records to make the new drive self-bootable
grub-install --removable /dev/sdb
update-grub
```

---

## ⏳ Step 3: Monitor Data Resynchronization Progress

Once the recovery loop for either scenario is executed, the background block-level mirroring initiates instantly. Monitor the live rebuild progress by running:

```bash
watch -n 1 cat /proc/mdstat
```

When the reconstruction percentage counters reach 100% and disappear, the array flags will transition completely back into the optimal mirrored state of **`[2/2] [UU]`**.
