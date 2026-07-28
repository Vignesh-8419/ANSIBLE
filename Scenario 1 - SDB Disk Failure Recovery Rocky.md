# Rocky Linux 8.10 RAID1 Recovery SOP
## Scenario 2 - SDB Disk Failure Recovery
### UEFI + GPT + Software RAID1 + LVM

-------------------------------------------------------------------------------
PURPOSE
-------------------------------------------------------------------------------

Recover a failed /dev/sdb disk while preserving the operating system,
bootloader, RAID arrays, and UEFI redundancy.

This SOP has been validated on Rocky Linux 8.10.

-------------------------------------------------------------------------------
PREREQUISITES
-------------------------------------------------------------------------------

Current Status

Healthy Disk:
/dev/sda

Failed Disk:
/dev/sdb

New Replacement Disk:
/dev/sdb

Expected Layout

sda
 ├── sda1   EFI (600MB)
 ├── sda2   RAID1 (/boot)
 └── sda3   RAID1 (LVM)

sdb
 ├── sdb1   EFI (600MB)
 ├── sdb2   RAID1 (/boot)
 └── sdb3   RAID1 (LVM)

-------------------------------------------------------------------------------
STEP 1 - Verify Current RAID Status
-------------------------------------------------------------------------------

Check RAID.

cat /proc/mdstat

Expected

md0 [2/1]
md1 [2/1]

Example

md0 [U_]

md1 [U_]

or

md0 [_U]

md1 [_U]

Verify disks.

lsblk

Verify VMware SCSI Slots.

lsscsi -g

IMPORTANT

Linux device names can change after disk failures.

Always verify the healthy disk before continuing.

-------------------------------------------------------------------------------
STEP 2 - Restore GPT Partition Table
-------------------------------------------------------------------------------

Clone partition table from the healthy disk.

sgdisk -R=/dev/sdb /dev/sda

Generate new GPT GUIDs.

sgdisk -G /dev/sdb

Reload partition table.

partprobe /dev/sdb

Verify.

lsblk

Expected

sdb1 600M
sdb2 1G
sdb3 Remaining Space

-------------------------------------------------------------------------------
STEP 3 - Rebuild RAID Arrays
-------------------------------------------------------------------------------

Add Boot RAID.

mdadm --manage /dev/md0 --add /dev/sdb2

Add LVM RAID.

mdadm --manage /dev/md1 --add /dev/sdb3

Ignore warnings such as

Value "localhost.localdomain:0" cannot be set as name.

These are harmless.

-------------------------------------------------------------------------------
STEP 4 - Wait For RAID Synchronization
-------------------------------------------------------------------------------

watch cat /proc/mdstat

Wait until

md0 [UU]

and

md1 [UU]

or periodically check

cat /proc/mdstat

-------------------------------------------------------------------------------
STEP 5 - Recreate EFI Filesystem
-------------------------------------------------------------------------------

Create a FAT32 filesystem.

mkfs.vfat -F32 /dev/sdb1

-------------------------------------------------------------------------------
STEP 6 - Restore EFI Boot Files
-------------------------------------------------------------------------------

Create mount points.

mkdir -p /mnt/efi_old
mkdir -p /mnt/efi_new

Mount healthy EFI.

mount /dev/sda1 /mnt/efi_old

Mount replacement EFI.

mount /dev/sdb1 /mnt/efi_new

Copy EFI boot files.

cp -a /mnt/efi_old/. /mnt/efi_new/

Flush writes.

sync

Verify.

find /mnt/efi_new

Expected

EFI/
EFI/BOOT/
EFI/BOOT/BOOTX64.EFI
EFI/BOOT/fbx64.efi

EFI/rocky/
EFI/rocky/grub.cfg
EFI/rocky/grubenv
EFI/rocky/grubx64.efi
EFI/rocky/shimx64.efi
EFI/rocky/mmx64.efi

Unmount.

umount /mnt/efi_old
umount /mnt/efi_new

-------------------------------------------------------------------------------
STEP 7 - Backup Existing Boot Entries
-------------------------------------------------------------------------------

Backup current UEFI entries.

efibootmgr -v > /root/efibootmgr.before

-------------------------------------------------------------------------------
STEP 8 - Remove Old Rocky Boot Entries
-------------------------------------------------------------------------------

List entries.

efibootmgr -v

Delete all old Rocky entries.

Example

efibootmgr -b 0005 -B
efibootmgr -b 0006 -B
efibootmgr -b 0007 -B
efibootmgr -b 0011 -B
efibootmgr -b 0012 -B
efibootmgr -b 0013 -B

Leave VMware entries untouched.

-------------------------------------------------------------------------------
STEP 9 - Create Fresh UEFI Boot Entries
-------------------------------------------------------------------------------

Create boot entry for Disk1.

efibootmgr \
    --create \
    --disk /dev/sda \
    --part 1 \
    --label "Rocky Disk1" \
    --loader '\EFI\rocky\shimx64.efi'

Create boot entry for Disk2.

efibootmgr \
    --create \
    --disk /dev/sdb \
    --part 1 \
    --label "Rocky Disk2" \
    --loader '\EFI\rocky\shimx64.efi'

-------------------------------------------------------------------------------
STEP 10 - Verify Boot Entries
-------------------------------------------------------------------------------

efibootmgr -v

Verify

BootXXXX Rocky Disk1

BootYYYY Rocky Disk2

Verify PARTUUID values.

blkid /dev/sda1
blkid /dev/sdb1

Ensure the PARTUUID values exactly match those displayed in
efibootmgr -v.

-------------------------------------------------------------------------------
STEP 11 - Configure Boot Order
-------------------------------------------------------------------------------

Example

efibootmgr -o 0006,0005,000D,000E,000F,0010

Adjust boot numbers according to your system.

Verify.

efibootmgr

Expected

BootOrder

Rocky Disk2

Rocky Disk1

-------------------------------------------------------------------------------
STEP 12 - Reboot
-------------------------------------------------------------------------------

reboot

After login verify.

efibootmgr

Expected

BootCurrent

Rocky Disk1

or

Rocky Disk2

NOT

EFI Virtual disk

-------------------------------------------------------------------------------
STEP 13 - Verify RAID
-------------------------------------------------------------------------------

cat /proc/mdstat

Expected

md0 [UU]

md1 [UU]

Verify disks.

lsblk

-------------------------------------------------------------------------------
STEP 14 - Validate Disk Failover
-------------------------------------------------------------------------------

Power OFF VM.

Remove Disk2 (/dev/sdb).

Power ON.

Verify

efibootmgr

Expected

BootCurrent changes to remaining disk.

Verify RAID.

cat /proc/mdstat

Expected

md0 [U_]

md1 [U_]

System boots successfully.

-------------------------------------------------------------------------------
STEP 15 - Restore Redundancy
-------------------------------------------------------------------------------

Reconnect Disk2.

Repeat this SOP.

Wait for RAID synchronization.

Verify

md0 [UU]

md1 [UU]

-------------------------------------------------------------------------------
FINAL VALIDATION CHECKLIST
-------------------------------------------------------------------------------

[✓] Replacement disk detected

[✓] GPT partition table restored

[✓] New GPT GUID generated

[✓] RAID /boot rebuilt

[✓] RAID LVM rebuilt

[✓] RAID synchronized

[✓] FAT32 EFI recreated

[✓] EFI boot files restored

[✓] Old UEFI boot entries removed

[✓] New UEFI boot entries created

[✓] Boot order configured

[✓] BootCurrent uses Rocky boot entry

[✓] RAID healthy

[✓] Server boots after SDB failure

Recovery Complete.
