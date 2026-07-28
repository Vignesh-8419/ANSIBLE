# Rocky Linux 8.10 RAID1 Recovery SOP
## Scenario 1 - SDA Disk Failure Recovery
### UEFI + GPT + Software RAID1 + LVM

-------------------------------------------------------------------------------
PURPOSE
-------------------------------------------------------------------------------

Recover a failed /dev/sda disk while preserving the operating system,
bootloader, RAID arrays, and UEFI redundancy.

This SOP has been validated on Rocky Linux 8.10.

-------------------------------------------------------------------------------
PREREQUISITES
-------------------------------------------------------------------------------

Current Status

Healthy Disk:
/dev/sdb

Failed Disk:
/dev/sda

New Replacement Disk:
/dev/sda

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

Verify remaining disks.

lsblk

Verify VMware SCSI slots.

lsscsi -g

IMPORTANT

Linux device names can change after a disk failure.

Always verify the healthy disk before continuing.

-------------------------------------------------------------------------------
STEP 2 - Restore GPT Partition Table
-------------------------------------------------------------------------------

Clone partition table from healthy disk.

sgdisk -R=/dev/sda /dev/sdb

Generate new GPT GUIDs.

sgdisk -G /dev/sda

Reload partition table.

partprobe /dev/sda

Verify.

lsblk

Expected

sda1 600M
sda2 1G
sda3 Remaining Space

-------------------------------------------------------------------------------
STEP 3 - Rebuild RAID Arrays
-------------------------------------------------------------------------------

Add Boot RAID.

mdadm --manage /dev/md0 --add /dev/sda2

Add LVM RAID.

mdadm --manage /dev/md1 --add /dev/sda3

Ignore messages such as

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

or check periodically

cat /proc/mdstat

-------------------------------------------------------------------------------
STEP 5 - Recreate EFI Filesystem
-------------------------------------------------------------------------------

Create a FAT32 filesystem.

mkfs.vfat -F32 /dev/sda1

-------------------------------------------------------------------------------
STEP 6 - Restore EFI Boot Files
-------------------------------------------------------------------------------

Create mount points.

mkdir -p /mnt/efi_old
mkdir -p /mnt/efi_new

Mount healthy EFI.

mount /dev/sdb1 /mnt/efi_old

Mount replacement EFI.

mount /dev/sda1 /mnt/efi_new

Copy boot files.

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

efibootmgr -v > /root/efibootmgr.before

-------------------------------------------------------------------------------
STEP 8 - Remove Old Rocky Boot Entries
-------------------------------------------------------------------------------

List entries.

efibootmgr -v

Delete ALL old Rocky entries.

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

Boot000X Rocky Disk1

Boot000Y Rocky Disk2

Verify PARTUUIDs.

blkid /dev/sda1
blkid /dev/sdb1

The PARTUUID values must match those shown in efibootmgr -v.

-------------------------------------------------------------------------------
STEP 11 - Configure Boot Order
-------------------------------------------------------------------------------

Example

efibootmgr -o 0006,0005,000D,000E,000F,0010

Adjust the boot numbers based on the output from efibootmgr.

Verify.

efibootmgr

Expected

BootOrder:
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

EFI Virtual Disk

-------------------------------------------------------------------------------
STEP 13 - Verify RAID
-------------------------------------------------------------------------------

cat /proc/mdstat

Expected

md0 [UU]

md1 [UU]

Verify

lsblk

-------------------------------------------------------------------------------
STEP 14 - Validate Disk Failover
-------------------------------------------------------------------------------

Power OFF VM.

Remove Disk1 (/dev/sda).

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

System should boot normally.

-------------------------------------------------------------------------------
STEP 15 - Restore Redundancy
-------------------------------------------------------------------------------

Reconnect Disk1.

Repeat this SOP.

Wait for RAID rebuild.

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

[✓] BootCurrent uses Rocky entry

[✓] RAID healthy

[✓] Server boots after SDA failure

Recovery Complete.
