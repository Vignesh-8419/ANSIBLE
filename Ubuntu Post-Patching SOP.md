# Ubuntu 24 RAID1 + Dual EFI
# Post-Patching SOP

## Overview

This server uses:

- Dual EFI System Partitions
  - `/dev/sda1`
  - `/dev/sdb1`
- `/boot` on RAID1 (`md0`)
- LVM on RAID1 (`md1`)

The EFI System Partition is **not** part of RAID1 because UEFI firmware cannot read Linux software RAID.

Instead, both EFI partitions contain identical boot files.

---

# Why is this required?

When Ubuntu installs or updates:

- Linux Kernel
- GRUB
- Shim
- EFI boot files

only the **mounted EFI partition** (`/boot/efi`) is updated.

The second EFI partition is **not automatically updated**.

To maintain boot failover, the secondary EFI partition must be synchronized after GRUB/EFI-related updates.

---

# Scenario 1 – Regular Package Updates

Example:

```bash
apt update
apt upgrade -y
```

If the update **does not** install:

- Linux Kernel
- GRUB
- Shim
- EFI packages

No further action is required.

---

# Scenario 2 – Kernel / GRUB / EFI Update

Example:

```bash
apt update
apt full-upgrade -y
```

If any of the following packages were updated:

- linux-image-*
- linux-generic*
- grub-efi-amd64*
- grub-common
- shim-signed
- grub2
- EFI bootloader packages

Perform the following steps.

---

# Step 1 - Ensure Primary EFI is Mounted

```bash
mount /boot/efi
```

Verify:

```bash
mount | grep /boot/efi
```

---

# Step 2 - Synchronize Secondary EFI

Run:

```bash
/usr/local/bin/sync-efi.sh
```

The script performs:

- Mount primary EFI
- Mount secondary EFI
- Install GRUB on secondary EFI
- Copy all EFI files
- Create BOOTX64.EFI fallback
- Unmount partitions

---

# Step 3 - Verify Synchronization

Mount the second EFI:

```bash
mkdir -p /mnt/efi2
mount /dev/sdb1 /mnt/efi2
```

Compare both EFI partitions:

```bash
diff -rq /boot/efi /mnt/efi2
```

Expected output:

```
(no output)
```

Unmount:

```bash
umount /mnt/efi2
```

---

# Step 4 - Verify RAID

```bash
cat /proc/mdstat
```

Expected:

```
md0 : active raid1 [UU]
md1 : active raid1 [UU]
```

---

# Step 5 - Verify Boot Entries

```bash
efibootmgr
```

Example:

```
Boot0005 Ubuntu
Boot0006 Ubuntu-SDB
```

---

# Optional Boot Validation

If maintenance permits:

1. Shutdown VM
2. Disconnect Disk 1
3. Boot from Disk 2
4. Verify successful boot
5. Reconnect Disk 1

This confirms boot failover remains functional.

---

# AWX / Ansible Recommendation

After patching, add the following task to your patching playbook:

```yaml
- name: Synchronize secondary EFI
  command: /usr/local/bin/sync-efi.sh
```

This ensures both EFI partitions remain synchronized after every kernel or GRUB update.

---

# Maintenance Checklist

| Task | Status |
|------|--------|
| Apply system updates | ☐ |
| Run `sync-efi.sh` (if Kernel/GRUB updated) | ☐ |
| Verify EFI synchronization (`diff -rq`) | ☐ |
| Verify RAID (`cat /proc/mdstat`) | ☐ |
| Verify UEFI boot entries (`efibootmgr`) | ☐ |
| Perform boot failover test (optional) | ☐ |

---

# Summary

| Update Type | Action Required |
|-------------|-----------------|
| Regular application packages | No action |
| Kernel update | Run `sync-efi.sh` |
| GRUB update | Run `sync-efi.sh` |
| Shim update | Run `sync-efi.sh` |
| EFI bootloader update | Run `sync-efi.sh` |
| Disk replacement | Rebuild RAID + Run `sync-efi.sh` |
