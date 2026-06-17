# Rocky Linux Bare-Metal Recovery and XFS Restore SOP

![Rocky Linux](https://img.shields.io/badge/RockyLinux-8.x-green)
![XFS](https://img.shields.io/badge/XFS-Backup%20%26%20Restore-blue)
![LVM](https://img.shields.io/badge/LVM-Recovery-orange)
![Disaster Recovery](https://img.shields.io/badge/Disaster-Recovery-red)

---

# Overview

This SOP documents the complete recovery process for a Rocky Linux server using:

* XFS Backup (`xfsdump`)
* XFS Restore (`xfsrestore`)
* GPT Partitioning
* LVM Recreation
* EFI Boot Recovery
* GRUB Reinstallation
* SELinux Relabel

This procedure is typically used when:

* Migrating to a new disk
* Rebuilding a failed server
* Recovering a corrupted operating system
* Restoring a server from a full XFS backup

---

# Important Notes

> [!WARNING]
> This procedure completely erases the target disk.

> [!WARNING]
> Verify the target disk (`/dev/sda`) before executing any wipe or partition commands.

> [!NOTE]
> The examples below assume:
>
> * Source backup file: `root_backup.dump`
> * Target disk: `/dev/sda`
> * Volume Group: `rl`
> * Rocky Linux EFI Boot

---

# Architecture

```text
Source Server
     |
     | xfsdump
     v
root_backup.dump
     |
     | CIFS Share
     v
Target Server
     |
     | xfsrestore
     v
Rocky Linux Recovered System
```

---

# Prerequisites

| Component      | Requirement          |
| -------------- | -------------------- |
| Recovery Media | Rocky Linux ISO      |
| Backup File    | root_backup.dump     |
| Network Access | CIFS/SMB Share       |
| Root Access    | Required             |
| Target Disk    | Empty or replaceable |

---

# Section 1 – Create Full XFS Backup

---

## Purpose

Create a full filesystem backup of the root filesystem.

### Create Backup Directory

```bash
mkdir -p /backup
```

### Create Full Backup

```bash
xfsdump \
  -l 0 \
  -L root_full_backup \
  -M root_full_backup \
  -f /backup/root_backup.dump \
  /
```

### Verification

```bash
ls -lh /backup/root_backup.dump
```

Expected:

```text
-rw------- root root xxG root_backup.dump
```

---

# Section 2 – Prepare Target Disk

---

## Step 1 – Wipe Existing Disk

> [!WARNING]
> This permanently destroys all data on the disk.

```bash
wipefs -a /dev/sda
```

---

## Step 2 – Create GPT Partition Layout

### Create Partition Table

```bash
parted /dev/sda --script mklabel gpt
```

### Create EFI Partition

```bash
parted /dev/sda --script mkpart EFI fat32 1MiB 601MiB
parted /dev/sda --script set 1 esp on
```

### Create Boot Partition

```bash
parted /dev/sda --script mkpart BOOT xfs 601MiB 1601MiB
```

### Create LVM Partition

```bash
parted /dev/sda --script mkpart LVM 1601MiB 100%
```

### Verify Layout

```bash
parted /dev/sda print
```

Expected:

| Partition | Purpose |
| --------- | ------- |
| sda1      | EFI     |
| sda2      | Boot    |
| sda3      | LVM     |

---

# Section 3 – Format Filesystems

---

## EFI

```bash
mkfs.vfat -F32 /dev/sda1
```

## Boot

```bash
mkfs.xfs -f /dev/sda2
```

---

# Section 4 – Create LVM Layout

---

## Create Physical Volume

```bash
pvcreate /dev/sda3
```

## Create Volume Group

```bash
vgcreate rl /dev/sda3
```

## Create Logical Volumes

### Swap

```bash
lvcreate -L 4G -n swap rl
```

### Home

```bash
lvcreate -L 31G -n home rl
```

### Root

```bash
lvcreate -l 100%FREE -n root rl
```

---

## Create Filesystems

```bash
mkfs.xfs /dev/rl/root
mkfs.xfs /dev/rl/home
mkswap /dev/rl/swap
```

---

## Verification

```bash
lvs
vgs
pvs
```

---

# Section 5 – Mount Target Filesystems

---

## Mount Root

```bash
mount /dev/rl/root /mnt/sysimage
```

## Create Directories

```bash
mkdir -p /mnt/sysimage/home
mkdir -p /mnt/sysimage/boot
mkdir -p /mnt/sysimage/boot/efi
```

## Mount Home

```bash
mount /dev/rl/home /mnt/sysimage/home
```

## Mount Boot

```bash
mount /dev/sda2 /mnt/sysimage/boot
```

## Mount EFI

```bash
mount /dev/sda1 /mnt/sysimage/boot/efi
```

---

# Section 6 – Restore Backup

---

## Mount CIFS Share

```bash
mkdir -p /mnt/samba

mount -t cifs //192.168.29.241/ISO /mnt/samba \
-o username=vigne,password=Vigneshv12$
```

> [!WARNING]
> Replace credentials with environment-specific values.

---

## Restore Filesystem

```bash
xfsrestore -f /mnt/samba/root_backup.dump /mnt/sysimage
```

### Verification

```bash
ls /mnt/sysimage
```

Expected:

```text
bin
boot
etc
home
usr
var
...
```

---

# Section 7 – Prepare Chroot Environment

---

## Bind Mount System Directories

```bash
mount --bind /dev  /mnt/sysimage/dev
mount --bind /proc /mnt/sysimage/proc
mount --bind /sys  /mnt/sysimage/sys
mount --bind /run  /mnt/sysimage/run
```

---

## Enter Chroot

```bash
chroot /mnt/sysimage
```

---

# Section 8 – Rebuild /etc/fstab

---

## Configure Filesystem Mounts

```bash
cat > /etc/fstab << EOF
/dev/mapper/rl-root  /          xfs  defaults 0 0
/dev/sda2            /boot      xfs  defaults 0 0
/dev/sda1            /boot/efi  vfat defaults,uid=0,gid=0,umask=077 0 2
/dev/mapper/rl-home  /home      xfs  defaults 0 0
/dev/mapper/rl-swap  swap       swap defaults 0 0
EOF
```

---

# Section 9 – Rebuild GRUB Configuration

---

## Configure GRUB Defaults

```bash
cat > /etc/default/grub << EOF
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Rocky Linux"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=9600 --unit=0 --word=8 --parity=no --stop=1"
GRUB_CMDLINE_LINUX="root=/dev/mapper/rl-root ro rhgb quiet console=tty0 console=ttyS0,115200"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
EOF
```

---

# Section 10 – Install Kernel and LVM Packages

---

```bash
dnf install -y \
  lvm2 \
  kernel \
  kernel-core \
  kernel-modules
```

---

# Section 11 – Rebuild Initramfs

---

```bash
dracut -f --regenerate-all
```

### Verification

```bash
ls -l /boot/initramfs*
```

---

# Section 12 – Reinstall EFI GRUB

---

## Install Required Packages

```bash
dnf reinstall -y \
  grub2-common \
  grub2-tools \
  grub2-tools-efi \
  grub2-efi-x64 \
  shim
```

---

## Generate GRUB Configuration

```bash
grub2-mkconfig -o /boot/grub2/grub.cfg
```

```bash
grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg
```

---

# Section 13 – Register EFI Boot Entry

---

## Create UEFI Boot Entry

```bash
efibootmgr --create \
  --disk /dev/sda \
  --part 1 \
  --label "RockyLinux" \
  --loader '\EFI\rocky\shimx64.efi'
```

### Verify

```bash
efibootmgr -v
```

Expected:

```text
Boot0001* RockyLinux
```

---

# Section 14 – Trigger SELinux Relabel

---

```bash
touch /.autorelabel
```

This ensures SELinux contexts are rebuilt during first boot.

---

# Section 15 – Exit and Reboot

---

## Exit Chroot

```bash
exit
```

## Unmount Filesystems

```bash
umount -R /mnt/sysimage
```

If busy:

```bash
umount -l /mnt/sysimage
```

---

## Reboot

```bash
reboot
```

---

# Post-Recovery Validation

## Verify Filesystems

```bash
df -h
```

## Verify LVM

```bash
lvs
vgs
pvs
```

## Verify Boot Mode

```bash
efibootmgr -v
```

## Verify SELinux

```bash
getenforce
```

## Verify Kernel

```bash
uname -r
```

---

# Validation Checklist

## Backup

* [ ] XFS Backup Completed
* [ ] Backup File Accessible

## Disk Preparation

* [ ] Disk Wiped
* [ ] GPT Layout Created
* [ ] Filesystems Created

## Restore

* [ ] Backup Restored Successfully
* [ ] Chroot Entered Successfully

## Boot Recovery

* [ ] fstab Rebuilt
* [ ] GRUB Reconfigured
* [ ] Initramfs Rebuilt
* [ ] EFI Entry Created

## Final Validation

* [ ] System Boots Successfully
* [ ] SELinux Relabel Completed
* [ ] LVM Volumes Available
* [ ] Services Start Normally

---

# Completion Criteria

Recovery is complete when:

* System boots successfully.
* Root filesystem is restored.
* EFI boot entry is registered.
* GRUB loads correctly.
* LVM volumes are active.
* SELinux relabel completes successfully.
* Server functionality matches the original system state.
