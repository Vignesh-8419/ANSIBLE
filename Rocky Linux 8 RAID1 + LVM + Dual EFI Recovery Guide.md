# Rocky Linux 8.10 Dual-Disk High-Availability Rebuild & Recovery Runbook

This guide contains the exact technical steps executed to test, recover, and permanently harden your dual-disk setup (UEFI + Software RAID1 + LVM). Use this document as your production Standard Operating Procedure (SOP) for disk failure simulations and bare-metal disaster recovery scenarios.

---

## 🚨 CASE 1: Primary Drive (`sda`) Fails & Rebuild Flow

Follow these steps if the primary drive (`sda`) suffers a hardware failure, or to simulate a primary drive disaster.

### Phase 1: Simulate/Identify Primary Failure
1. Mark the primary disk partitions as faulty inside the running Software RAID 1 arrays:
   ```bash
   mdadm /dev/md1 --fail /dev/sda2
   mdadm /dev/md0 --fail /dev/sda3
   ```
2. Verify the array degradation status (`[_U]` mask confirms `sdb` is running solo):
   ```bash
   cat /proc/mdstat
   ```
3. Power down the virtual machine instance gracefully:
   ```bash
   poweroff
   ```
4. **Hypervisor Action:** Go into your VMware settings panel, select **Hard Disk 1 (`sda`)**, completely disconnect/remove it from the VM, and power the VM back on.

### Phase 2: Next-Boot Survivability Verification
The system will skip the missing slot, initialize from the `sdb2` backup EFI block using the `sync-esp.sh` standalone GRUB instructions, and load into Rocky Linux. Log back in via SSH.

### Phase 3: Hot-Add Rebuild Steps
1. **Hypervisor Action:** Go to VMware settings and add a brand new **100G Hard Disk** as your primary storage slot (`sda`).
2. Clone the exact GPT partition table boundaries from the healthy surviving drive (`sdb`) to the fresh blank drive (`sda`):
   ```bash
   sgdisk /dev/sdb -R /dev/sda
   ```
3. Randomize the disk and partition UUIDs on the target drive to prevent layout tracking collisions:
   ```bash
   sgdisk -G /dev/sda
   ```
4. Force the Linux operating system kernel to refresh its block memory tracking maps instantly:
   ```bash
   partprobe /dev/sda
   ```
5. Re-add the size-matching partitions back into their corresponding RAID arrays:
   ```bash
   # Rebuild the /boot 2G filesystem array (sda1 paired with sdb1)
   mdadm /dev/md1 --add /dev/sda1
   
   # Rebuild the core root LVM 97.4G storage engine array (sda3 paired with sdb3)
   mdadm /dev/md0 --add /dev/sda3
   ```
6. Monitor the background reconstruction data sync process until both arrays hit **`[UU]`**:
   ```bash
   cat /proc/mdstat
   ```

### Phase 4: Resolving the `rsync: change_dir` Directory Error
After the RAID arrays finish syncing, we clean-formatted the new primary EFI partition (`sda2`) and mounted it to its native production home directory:
```bash
mkfs.vfat -F32 -n "EFI-SYSTEM" /dev/sda2
mount /dev/sda2 /boot/efi
```

#### 🔍 Why it fails without manual sync:
Running `systemctl start sync-esp.service` right now will fail with `rsync: change_dir "/boot/efi/EFI" failed: No such file or directory (2)`. This occurs because `/dev/sda2` was completely blanked by `mkfs`. The script assumes you booted from the primary disk and tries to copy files *from* `sda2` *to* `sdb2`. Because `sda2` is empty, it crashes. Your active bootloader files are actually sitting on **`/dev/sdb2`** (mounted to `/boot/efi2`).

#### 🛠️ The Fix:
Manually copy the master EFI binaries from the working backup drive over onto the fresh primary drive to re-prime the environment, then unmount the backup disk:
```bash
cp -r /boot/efi2/EFI /boot/efi/
umount /boot/efi2
```

### Phase 5: Fixing `/etc/fstab` and Final Validation
Because we ran `mkfs.vfat` on the EFI partition during the rebuild, **it received a brand-new unique UUID signature**. The old entry inside `/etc/fstab` is dead, which will cause systemd boot timeouts on the next restart.

1. Query the active filesystem UUIDs of the newly generated blocks:
   ```bash
   blkid | grep -E '(sda2|sdb2)'
   ```
2. Update `/etc/fstab` using `vi /etc/fstab` to match your active disk UUID signatures:
   ```text
   UUID=<NEW_SDA2_UUID>      /boot/efi               vfat    defaults,nofail,uid=0,gid=0,umask=077,shortname=winnt 0 2
   UUID=<NEW_SDB2_UUID>      efi2                    vfat    umask=0077,shortname=winnt 0 0
   ```
3. Reload systemd and verify execution:
   ```bash
   systemctl daemon-reload
   systemctl start sync-esp.service
   /usr/local/sbin/pre-verify-boot.sh
   ```

---

## 🚨 CASE 2: Secondary Drive (`sdb`) Fails & Rebuild Flow

Follow these steps if the secondary drive (`sdb`) suffers a hardware failure, or to simulate a secondary drive disaster.

### Phase 1: Simulate/Identify Secondary Failure
1. Mark the secondary disk partitions as faulty inside the running Software RAID 1 arrays:
   ```bash
   mdadm /dev/md1 --fail /dev/sdb1
   mdadm /dev/md0 --fail /dev/sdb3
   ```
2. Verify the array degradation status (`[U_]` mask confirms `sda` is running solo):
   ```bash
   cat /proc/mdstat
   ```
3. Power down the virtual machine instance gracefully:
   ```bash
   poweroff
   ```
4. **Hypervisor Action:** Go into your VMware settings panel, select **Hard Disk 2 (`sdb`)**, completely disconnect/remove it from the VM, and power the VM back on.

### Phase 2: Next-Boot Survivability Verification
The system will initialize from the primary `sda2` EFI block, pass control over to the single running `sda` RAID array, and boot smoothly. Log back in via SSH.

### Phase 3: Hot-Add Rebuild Steps
1. **Hypervisor Action:** Go to VMware settings and add a brand new **100G Hard Disk** as your secondary storage slot (`sdb`).
2. Clone the exact GPT partition table boundaries from the healthy surviving drive (`sda`) to the fresh blank drive (`sdb`):
   ```bash
   sgdisk /dev/sda -R /dev/sdb
   ```
3. Randomize the disk and partition UUIDs on the target drive to prevent collisions:
   ```bash
   sgdisk -G /dev/sdb
   ```
4. Force the Linux operating system kernel to refresh its block memory tracking maps instantly:
   ```bash
   partprobe /dev/sdb
   ```
5. Re-add the partitions back into their corresponding RAID arrays:
   ```bash
   # Rebuild the /boot 2G filesystem array (sdb1 paired with sda1)
   mdadm /dev/md1 --add /dev/sdb1
   
   # Rebuild the core root LVM 97.4G storage engine array (sdb3 paired with sda3)
   mdadm /dev/md0 --add /dev/sdb3
   ```
6. Monitor the background reconstruction data sync process until both arrays hit **`[UU]`**:
   ```bash
   cat /proc/mdstat
   ```

### Phase 4: Restoring the Secondary EFI Mirror
Since you are booted from the primary disk, your working bootloader files are safely active inside `/boot/efi` (`sda2`). We just need to format the fresh backup drive slot and trigger the sync engine.

1. Format the clean 600M backup partition on `sdb2`:
   ```bash
   mkfs.vfat -F32 -n "EFI-BACKUP" /dev/sdb2
   ```
2. Because we ran `mkfs.vfat`, `sdb2` has received a brand-new unique UUID signature. Query it:
   ```bash
   blkid | grep /dev/sdb2
   ```
3. Update `/etc/fstab` using `vi /etc/fstab` to match the new `efi2` UUID signature:
   ```text
   UUID=<NEW_SDB2_UUID>      efi2                    vfat    umask=0077,shortname=winnt 0 0
   ```
4. Reload the systemd configuration engine:
   ```bash
   systemctl daemon-reload
   ```
5. Fire your synchronization script to copy the bootloader files across drives cleanly:
   ```bash
   systemctl start sync-esp.service
   ```
6. Run the master verification runbook script to confirm total high-availability compliance:
   ```bash
   /usr/local/sbin/pre-verify-boot.sh
   ```

### 🏁 Final Production Verdict
When the script returns the green success block on either scenario, your infrastructure validation is complete:
```text
====================================================================
 🟢 SUCCESS: All recovery steps done. You are good to reboot!
====================================================================
```
