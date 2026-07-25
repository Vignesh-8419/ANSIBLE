# Rocky Linux 8.10 Dual-Disk High-Availability Rebuild & Recovery Runbook

This guide contains the exact chronological steps executed to test, recover, and permanently harden your dual-disk setup (UEFI + Software RAID1 + LVM). Use this document as your production Standard Operating Procedure (SOP) for disk failure simulations and bare-metal disaster recovery scenarios.

---

## 🚨 Phase 1: Simulating Primary Drive (`sda`) Failure

To test if the server could survive a loss of the primary disk without crashing, we manually failed the drives and pulled them from the hypervisor.

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

4. **Hypervisor Action:** Go into your VMware vSphere/Workstation settings panel, select **Hard Disk 1 (`sda`)**, completely disconnect/remove it from the virtual machine, and power the virtual machine back on.

---

## 🔍 Phase 2: Next-Boot Survivability Verification

The system successfully skipped the missing slot, initialized from the `sdb2` backup EFI block using the `sync-esp.sh` standalone GRUB instructions, and loaded into Rocky Linux.

Upon logging back in, running `lsblk` showed that the hypervisor automatically shifted the surviving active drive to the generic block table name `sdb` or `sda` based on the active hardware configuration. The arrays were fully operational but running in a degraded state.

---

## 🛠️ Phase 3: Rebuilding the Replaced Drive

After confirming next-boot survivability, a fresh 100G replacement drive was attached to the VM.

1. Clone the exact GPT partition table boundaries from the healthy surviving drive (`sdb`) to the fresh blank drive (`sda`):
   ```bash
   sgdisk /dev/sdb -R /dev/sda
   ```

2. Randomize the disk and partition UUIDs on the target drive to prevent layout tracking collisions:
   ```bash
   sgdisk -G /dev/sda
   ```

3. Force the Linux operating system kernel to refresh its block memory tracking maps instantly:
   ```bash
   partprobe /dev/sda
   ```

4. Re-add the size-matching partitions back into their corresponding RAID arrays. 
   *Note: Because of Anaconda's initial partition sorting behaviors, always pair partitions by their **exact size**, not their sequence numbers:*
   ```bash
   # Rebuild the /boot 2G filesystem array (sda1 paired with sdb1)
   mdadm /dev/md1 --add /dev/sda1
   
   # Rebuild the core root LVM 97.4G storage engine array (sda3 paired with sdb3)
   mdadm /dev/md0 --add /dev/sda3
   ```

5. Monitor the background reconstruction data sync process until both arrays hit **`[UU]`**:
   ```bash
   cat /proc/mdstat
   ```

---

## 🩹 Phase 4: Resolving the `rsync: change_dir` Directory Error

After the RAID arrays finished syncing, we clean-formatted the new primary EFI partition (`sda2`) and mounted it to its native production home directory:
```bash
mkfs.vfat -F32 -n "EFI-SYSTEM" /dev/sda2
mount /dev/sda2 /boot/efi
```

### 🔍 The Problem
When running `systemctl start sync-esp.service` right after, it failed with the following error:
> `rsync: change_dir "/boot/efi/EFI" failed: No such file or directory (2)`

This occurred because `/dev/sda2` was completely blank from the fresh `mkfs` command. The `sync-esp.sh` script assumed the server had booted from the primary disk, meaning it expected `/boot/efi` to contain the source files to copy *to* `sdb2`. Instead, your active bootloader was sitting on **`/dev/sdb2`** (which was mounted to `/boot/efi2`).

### 🛠️ The Fix
We manually restored the boot files from the working backup drive over onto the fresh primary drive to re-prime the directory architecture before clearing the tracking layout:

```bash
# Manually copy the master EFI binaries from the backup path to the empty primary path
cp -r /boot/efi2/EFI /boot/efi/

# Unmount the temporary secondary partition path to clear the layout
umount /boot/efi2
```

---

## 🔐 Phase 5: Fixing `/etc/fstab` and Final Validation

Because we ran `mkfs.vfat` on the EFI partitions during our rebuild testing, **both partitions received brand-new unique UUID signatures**. The old UUID entries inside `/etc/fstab` were dead, which would cause systemd boot timeouts on the next restart.

1. Query the active filesystem UUIDs of the newly generated blocks:
   ```bash
   blkid | grep -E '(sda2|sdb2)'
   ```
   *Output returned your fresh production signatures:*
   * `/dev/sda2` \(\rightarrow\) `UUID="42B8-C824"`
   * `/dev/sdb2` \(\rightarrow\) `UUID="C58B-B83F"`

2. Update `/etc/fstab` to target these new immutable identifiers:
   ```bash
   vi /etc/fstab
   ```
   *Modify the file to update the stale UUID values with these exact parameters:*
   ```text
   UUID=42B8-C824          /boot/efi               vfat    defaults,nofail,uid=0,gid=0,umask=077,shortname=winnt 0 2
   UUID=C58B-B83F          efi2                    vfat    umask=0077,shortname=winnt 0 0
   ```

3. Reload the systemd configuration engine to apply the storage rules instantly:
   ```bash
   systemctl daemon-reload
   ```

4. Trigger your background synchronization daemon to lock files securely across both tracking zones:
   ```bash
   systemctl start sync-esp.service
   ```

5. Execute the master verification runbook script to confirm total high-availability compliance:
   ```bash
   /usr/local/sbin/pre-verify-boot.sh
   ```

### 🏁 Final Production Verdict
The verification engine successfully returned the master validation banner:
```text
====================================================================
 🟢 SUCCESS: All recovery steps done. You are good to reboot!
    The system firmware and secondary drive are ready to survive a disk loss.
====================================================================
```
Your Rocky Linux 8.10 infrastructure is now fully production-hardened.
