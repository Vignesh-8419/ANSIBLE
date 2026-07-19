# CentOS7_Golden_RAID.iso

# Kickstart CD ROM

```text
install
cdrom
text

lang en_US.UTF-8
keyboard us
timezone Asia/Kolkata --isUtc

rootpw --plaintext Root@123
network --bootproto=dhcp --device=link --activate
firewall --enabled --service=ssh
selinux --enforcing
services --enabled=NetworkManager,sshd

# Standard UEFI target declaration
bootloader --boot-drive=sda

zerombr
clearpart --none
ignoredisk --only-use=sda,sdb

# Imports dynamically built partition mapping
%include /tmp/part-include

# RAID1 PV (Handles OS & Data Redundancy)
raid pv.01 --device=md0 --level=1 raid.01 raid.02

# LVM Configuration
volgroup vg_root pv.01
logvol / --vgname=vg_root --name=root --fstype=xfs --grow --size=20480
logvol swap --vgname=vg_root --name=swap --fstype=swap --size=2048
logvol /home --vgname=vg_root --name=home --fstype=xfs --size=4096

%packages
@core
@base
vim
wget
efibootmgr
parted
shim
grub2-efi-x64
mdadm
lvm2
rsync
%end

###############################################################################
# %pre Script: Structural disk partitioning for sda and sdb
###############################################################################
%pre --interpreter=/bin/bash
set -e  
exec < /dev/tty3 > /dev/tty3 2>&1
chvt 3

echo "Pre-install: Preparing sda and sdb..."

USE_PARTED=0
for cmd in sgdisk wipefs partprobe; do
    if ! command -v $cmd &>/dev/null; then
        echo "Required utility '$cmd' missing from image environment. Enforcing parted path."
        USE_PARTED=1
        break
    fi
done

if [ "$USE_PARTED" -eq 1 ]; then
    for disk in /dev/sda /dev/sdb; do
        DISK_SECTORS=$(blockdev --getsz $disk 2>/dev/null || echo 0)
        if [ "$DISK_SECTORS" -gt 40960 ]; then
            dd if=/dev/zero of=$disk bs=1M count=10 conv=notrunc
            seek_pos=$((DISK_SECTORS - 20480))
            dd if=/dev/zero of=$disk bs=512 seek=$seek_pos count=20480 conv=notrunc
        else
            dd if=/dev/zero of=$disk bs=512 count=2048 conv=notrunc
        fi
        
        parted -s $disk mklabel gpt
        parted -s $disk mkpart primary fat32 1MiB 601MiB
        parted -s $disk set 1 esp on
        parted -s $disk mkpart primary 601MiB 2649MiB
        parted -s $disk set 2 raid on
        parted -s $disk mkpart primary 2649MiB 100%
        parted -s $disk set 3 raid on
        
        partprobe $disk
    done
    udevadm settle
else
    for disk in /dev/sda /dev/sdb; do
        wipefs -a -f $disk
        sgdisk --zap-all $disk
        sgdisk -o $disk
        sgdisk -n 1:0:+600M -t 1:ef00 -c 1:"EFI System" $disk
        sgdisk -n 2:0:+2048M -t 2:fd00 -c 2:"Boot RAID" $disk
        sgdisk -n 3:0:0 -t 3:fd00 -c 3:"LVM RAID" $disk
        partprobe $disk
    done
    udevadm settle
fi

chvt 1

cat << 'EOF' > /tmp/part-include
part /boot/efi --fstype=efi --onpart=sda1

part raid.boot01 --onpart=sda2
part raid.boot02 --onpart=sdb2
raid /boot --device=md1 --level=1 --fstype=xfs raid.boot01 raid.boot02

part raid.01 --onpart=sda3
part raid.02 --onpart=sdb3
EOF
%end

###############################################################################
# %post Script: Redundancy Alignment and Boot Persistence Mechanics
###############################################################################
%post --nochroot --log=/mnt/sysimage/root/ks-post-grub.log
set -e 

echo "Configuring Verbose Boot inside target kernel parameters..."
chroot /mnt/sysimage /usr/sbin/grubby --update-kernel=ALL --remove-args="rhgb quiet"
chroot /mnt/sysimage /usr/sbin/grubby --update-kernel=ALL --args="loglevel=7 systemd.show_status=true"

# Generate canonical main config mapping
chroot /mnt/sysimage /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg
chroot /mnt/sysimage /usr/sbin/dracut -f

# Verify primary ESP filesystem is mounted cleanly before parsing it
if ! mountpoint -q /mnt/sysimage/boot/efi; then
    echo "CRITICAL ERROR: Primary ESP filesystem (/boot/efi) is not mounted!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

echo "Setting up proper UEFI Redundancy on /dev/sdb1..."

TARGET_MNT="/mnt/sysimage/boot/efi2"
mkdir -p "$TARGET_MNT"

cleanup() {
    echo "Executing filesystem mount safety cleanup sequence..."
    mountpoint -q "$TARGET_MNT" && umount "$TARGET_MNT"
    mountpoint -q "/mnt/sysimage/sys/firmware/efi/efivars" && umount "/mnt/sysimage/sys/firmware/efi/efivars"
    rmdir "$TARGET_MNT" 2>/dev/null || true
}
trap cleanup EXIT

# Ensure /dev/sdb1 is formatted and clean
if ! blkid /dev/sdb1 | grep -q "vfat"; then
    mkfs.vfat -F 32 -n "EFI-SDB" /dev/sdb1
fi

if ! mount /dev/sdb1 "$TARGET_MNT"; then
    echo "CRITICAL ERROR: Failed to mount secondary ESP storage /dev/sdb1" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

if ! mountpoint -q "$TARGET_MNT"; then
    echo "CRITICAL ERROR: Target mountpoint validation check failed!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Safety guard checking for EFI execution context presence before binding variables path
if [ -d /sys/firmware/efi/efivars ]; then
    mkdir -p /mnt/sysimage/sys/firmware/efi/efivars
    mount --bind /sys/firmware/efi/efivars /mnt/sysimage/sys/firmware/efi/efivars || true
fi

# Execute bootloader installation inside the chroot pointing to the valid efi2 directory mount point
if ! chroot /mnt/sysimage /usr/sbin/grub2-install --target=x86_64-efi --efi-directory=/boot/efi2 --bootloader-id=centos --recheck; then
    echo "CRITICAL ERROR: grub2-install execution on secondary ESP failed!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Verify grub2-install output binaries exist on secondary disk rather than trusting exit code status alone
if [ ! -f "$TARGET_MNT/EFI/centos/grubx64.efi" ] && \
   [ ! -f "$TARGET_MNT/EFI/centos/shimx64.efi" ]; then
    echo "CRITICAL ERROR: No EFI bootloader created on secondary ESP!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Re-map standard fallback directories
mkdir -p /mnt/sysimage/boot/efi/EFI/BOOT
mkdir -p "$TARGET_MNT/EFI/BOOT"

# Safe Secure Boot vs Non-Secure Boot identification
if [ -f /mnt/sysimage/boot/efi/EFI/centos/shimx64.efi ]; then
    echo "Secure Boot chain detected. Synchronizing matching shims..."
    cp /mnt/sysimage/boot/efi/EFI/centos/shimx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI
    cp /mnt/sysimage/boot/efi/EFI/centos/grubx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/grubx64.efi
    
    cp "$TARGET_MNT/EFI/centos/shimx64.efi" "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI"
    cp "$TARGET_MNT/EFI/centos/grubx64.efi" "$TARGET_MNT/EFI/BOOT/grubx64.efi"
    BOOT_TARGET="shimx64.efi"
else
    echo "Standard system configurations detected. Generating raw binary fallback entries..."
    cp /mnt/sysimage/boot/efi/EFI/centos/grubx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI
    cp "$TARGET_MNT/EFI/centos/grubx64.efi" "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI"
    BOOT_TARGET="grubx64.efi"
fi

if [ -f /mnt/sysimage/boot/efi/EFI/centos/BOOTX64.CSV ]; then
    cp /mnt/sysimage/boot/efi/EFI/centos/BOOTX64.CSV "$TARGET_MNT/EFI/centos/BOOTX64.CSV"
fi

# Ensure the second ESP has its own forwarded stub directing to /boot/grub2/grub.cfg
chroot /mnt/sysimage /usr/sbin/grub2-mkconfig -o /boot/efi2/EFI/centos/grub.cfg

# Handle efibootmgr hardware/VM integration faults gracefully using explicit error capture
if [ -d /sys/firmware/efi/efivars ]; then
    echo "Registering alternative secondary paths inside hardware NVRAM..."
    if ! efibootmgr -c -d /dev/sdb -p 1 -L "CentOS Backup Boot (sdb)" -l "\\EFI\\centos\\${BOOT_TARGET}"; then
        echo "NOTICE: NVRAM generation dropped or un-writable in installer context. Falling back cleanly to BOOTX64.EFI." >> /mnt/sysimage/root/ks-post-errors.log
    fi
fi

# Run target verification loop pipelines
echo "=== STORAGE ENVIRONMENT LAYER AUDIT ===" >> /mnt/sysimage/root/storage_validation.log
lsblk -o NAME,FSTYPE,MOUNTPOINT,SIZE >> /mnt/sysimage/root/storage_validation.log

if [ ! -f /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI ]; then
    echo "ERROR: Target fallback executable is missing from sda1!" >> /mnt/sysimage/root/ks-post-errors.log
fi

if [ ! -f "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI" ]; then
    echo "ERROR: Target fallback executable is missing from sdb1!" >> /mnt/sysimage/root/ks-post-errors.log
fi

echo "=== VOLUME GROUP & METADATA VERIFICATION ===" >> /mnt/sysimage/root/storage_validation.log
cat /proc/mdstat >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage pvs >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage vgs >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage lvs >> /mnt/sysimage/root/storage_validation.log

cleanup
trap - EXIT

# Deploy static standalone synchronization tool script
cat << 'EOF' > /mnt/sysimage/usr/local/sbin/sync-esp.sh
#!/bin/bash
set -e
if [ -d /boot/efi/EFI/centos ] && [ -b /dev/sdb1 ]; then
    TMP_SYNC=$(mktemp -d)
    if mount /dev/sdb1 "$TMP_SYNC"; then
        mkdir -p "$TMP_SYNC/EFI/centos"
        mkdir -p "$TMP_SYNC/EFI/BOOT"

        rsync -a --delete /boot/efi/EFI/centos/ "$TMP_SYNC/EFI/centos/"
        rsync -a --delete /boot/efi/EFI/BOOT/ "$TMP_SYNC/EFI/BOOT/"

        if [ -f /boot/efi/EFI/centos/shimx64.efi ]; then
            cp /boot/efi/EFI/centos/shimx64.efi "$TMP_SYNC/EFI/BOOT/BOOTX64.EFI"
        else
            cp /boot/efi/EFI/centos/grubx64.efi "$TMP_SYNC/EFI/BOOT/BOOTX64.EFI"
        fi

        umount "$TMP_SYNC"
    fi
    rm -rf "$TMP_SYNC"
fi
EOF

chmod +x /mnt/sysimage/usr/local/sbin/sync-esp.sh

# Perform the initial synchronization immediately
chroot /mnt/sysimage /usr/local/sbin/sync-esp.sh

%end

reboot
```

# Rocky8_Golden_RAID.iso

# Kickstart

```text
# Rocky Linux 8.10 Automated Unattended Installation Profile
cdrom
text

lang en_US.UTF-8
keyboard us
timezone Asia/Kolkata --isUtc

rootpw --plaintext Root@123
network --bootproto=dhcp --device=link --activate
firewall --enabled --service=ssh
selinux --enforcing
services --enabled=NetworkManager,sshd

# Standard EL8 UEFI Target
bootloader --boot-drive=sda

zerombr
clearpart --none
ignoredisk --only-use=sda,sdb

# Imports dynamically built partition mapping from %pre
%include /tmp/part-include

# RAID1 PV (Handles OS & Data Redundancy)
raid pv.01 --device=md0 --level=1 raid.01 raid.02

# LVM Configuration
volgroup vg_root pv.01
logvol / --vgname=vg_root --name=root --fstype=xfs --grow --size=20480
logvol swap --vgname=vg_root --name=swap --fstype=swap --size=2048
logvol /home --vgname=vg_root --name=home --fstype=xfs --size=4096

%packages
@^server-product-environment
vim
wget
efibootmgr
parted
shim-x64
grub2-efi-x64
mdadm
lvm2
rsync
%end

###############################################################################
# %pre Script: Structural disk partitioning for sda and sdb
###############################################################################
%pre --interpreter=/bin/bash
set -e  
exec < /dev/tty3 > /dev/tty3 2>&1
chvt 3

echo "Pre-install: Structuring layouts for sda and sdb..."

USE_PARTED=0
for cmd in sgdisk wipefs partprobe; do
    if ! command -v $cmd &>/dev/null; then
        echo "Required utility '$cmd' missing from image environment. Enforcing parted path."
        USE_PARTED=1
        break
    fi
done

if [ "$USE_PARTED" -eq 1 ]; then
    for disk in /dev/sda /dev/sdb; do
        DISK_SECTORS=$(blockdev --getsz $disk 2>/dev/null || echo 0)
        if [ "$DISK_SECTORS" -gt 40960 ]; then
            dd if=/dev/zero of=$disk bs=1M count=10 conv=notrunc
            seek_pos=$((DISK_SECTORS - 20480))
            dd if=/dev/zero of=$disk bs=512 seek=$seek_pos count=20480 conv=notrunc
        else
            dd if=/dev/zero of=$disk bs=512 count=2048 conv=notrunc
        fi
        
        parted -s $disk mklabel gpt
        parted -s $disk mkpart primary fat32 1MiB 601MiB
        parted -s $disk set 1 esp on
        parted -s $disk mkpart primary 601MiB 2649MiB
        parted -s $disk set 2 raid on
        parted -s $disk mkpart primary 2649MiB 100%
        parted -s $disk set 3 raid on
        
        partprobe $disk
    done
    udevadm settle
else
    for disk in /dev/sda /dev/sdb; do
        wipefs -a -f $disk
        sgdisk --zap-all $disk
        sgdisk -o $disk
        sgdisk -n 1:0:+600M -t 1:ef00 -c 1:"EFI System" $disk
        sgdisk -n 2:0:+2048M -t 2:fd00 -c 2:"Boot RAID" $disk
        sgdisk -n 3:0:0 -t 3:fd00 -c 3:"LVM RAID" $disk
        partprobe $disk
    done
    udevadm settle
fi

chvt 1

cat << 'EOF' > /tmp/part-include
part /boot/efi --fstype=efi --onpart=sda1

part raid.boot01 --onpart=sda2
part raid.boot02 --onpart=sdb2
raid /boot --device=md1 --level=1 --fstype=xfs raid.boot01 raid.boot02

part raid.01 --onpart=sda3
part raid.02 --onpart=sdb3
EOF
%end

###############################################################################
# %post Script: Redundancy Alignment and Boot Persistence Mechanics
###############################################################################
%post --nochroot --log=/mnt/sysimage/root/ks-post-grub.log
set -e 

echo "Configuring Verbose Boot inside target kernel parameters..."
chroot /mnt/sysimage /usr/sbin/grubby --update-kernel=ALL --remove-args="rhgb quiet"
chroot /mnt/sysimage /usr/sbin/grubby --update-kernel=ALL --args="loglevel=7 systemd.show_status=true"

# Generate canonical main config mapping for Rocky 8 (Stored in /boot/grub2/)
chroot /mnt/sysimage /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg
chroot /mnt/sysimage /usr/sbin/dracut -f

# Verify primary ESP filesystem is mounted cleanly before parsing it
if ! mountpoint -q /mnt/sysimage/boot/efi; then
    echo "CRITICAL ERROR: Primary ESP filesystem (/boot/efi) is not mounted!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

echo "Setting up proper UEFI Redundancy on /dev/sdb1..."

TARGET_MNT="/mnt/sysimage/boot/efi2"
mkdir -p "$TARGET_MNT"

cleanup() {
    echo "Executing filesystem mount safety cleanup sequence..."
    mountpoint -q "$TARGET_MNT" && umount "$TARGET_MNT"
    mountpoint -q "/mnt/sysimage/sys/firmware/efi/efivars" && umount "/mnt/sysimage/sys/firmware/efi/efivars"
    rmdir "$TARGET_MNT" 2>/dev/null || true
}
trap cleanup EXIT

# Ensure /dev/sdb1 is formatted and clean
if ! blkid /dev/sdb1 | grep -q "vfat"; then
    mkfs.vfat -F 32 -n "EFI-SDB" /dev/sdb1
fi

if ! mount /dev/sdb1 "$TARGET_MNT"; then
    echo "CRITICAL ERROR: Failed to mount secondary ESP storage /dev/sdb1" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

if ! mountpoint -q "$TARGET_MNT"; then
    echo "CRITICAL ERROR: Target mountpoint validation check failed!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Safety guard checking for EFI execution context presence before binding variables path
if [ -d /sys/firmware/efi/efivars ]; then
    mkdir -p /mnt/sysimage/sys/firmware/efi/efivars
    mount --bind /sys/firmware/efi/efivars /mnt/sysimage/sys/firmware/efi/efivars || true
fi

# Execute bootloader installation inside the chroot pointing to the valid efi2 directory mount point
if ! chroot /mnt/sysimage /usr/sbin/grub2-install --target=x86_64-efi --efi-directory=/boot/efi2 --bootloader-id=rocky --recheck; then
    echo "CRITICAL ERROR: grub2-install execution on secondary ESP failed!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Verify grub2-install output binaries exist on secondary disk rather than trusting exit code status alone
if [ ! -f "$TARGET_MNT/EFI/rocky/grubx64.efi" ] && \
   [ ! -f "$TARGET_MNT/EFI/rocky/shimx64.efi" ]; then
    echo "CRITICAL ERROR: No EFI bootloader found on secondary ESP!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Re-map standard fallback directories
mkdir -p /mnt/sysimage/boot/efi/EFI/BOOT
mkdir -p "$TARGET_MNT/EFI/BOOT"

# Safe Secure Boot vs Non-Secure Boot identification for Rocky
if [ -f /mnt/sysimage/boot/efi/EFI/rocky/shimx64.efi ]; then
    echo "Secure Boot chain detected. Synchronizing matching shims..."
    cp /mnt/sysimage/boot/efi/EFI/rocky/shimx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI
    cp /mnt/sysimage/boot/efi/EFI/rocky/grubx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/grubx64.efi
    
    cp "$TARGET_MNT/EFI/rocky/shimx64.efi" "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI"
    cp "$TARGET_MNT/EFI/rocky/grubx64.efi" "$TARGET_MNT/EFI/BOOT/grubx64.efi"
    BOOT_TARGET="shimx64.efi"
else
    echo "Standard system configurations detected. Generating raw binary fallback entries..."
    cp /mnt/sysimage/boot/efi/EFI/rocky/grubx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI
    cp "$TARGET_MNT/EFI/rocky/grubx64.efi" "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI"
    BOOT_TARGET="grubx64.efi"
fi

if [ -f /mnt/sysimage/boot/efi/EFI/rocky/BOOTX64.CSV ]; then
    cp /mnt/sysimage/boot/efi/EFI/rocky/BOOTX64.CSV "$TARGET_MNT/EFI/rocky/BOOTX64.CSV"
fi

# Ensure the second ESP has its own forwarded stub directing to /boot/grub2/grub.cfg
chroot /mnt/sysimage /usr/sbin/grub2-mkconfig -o /boot/efi2/EFI/rocky/grub.cfg

# Handle efibootmgr hardware/VM integration faults gracefully using explicit error capture
if [ -d /sys/firmware/efi/efivars ]; then
    echo "Registering alternative secondary paths inside hardware NVRAM..."
    if ! efibootmgr -c -d /dev/sdb -p 1 -L "Rocky Backup Boot (sdb)" -l "\\EFI\\rocky\\${BOOT_TARGET}"; then
        echo "NOTICE: NVRAM generation dropped or un-writable in installer context. Falling back cleanly to BOOTX64.EFI." >> /mnt/sysimage/root/ks-post-errors.log
    fi
fi

# Run target verification loop pipelines
echo "=== STORAGE ENVIRONMENT LAYER AUDIT ===" >> /mnt/sysimage/root/storage_validation.log
lsblk -o NAME,FSTYPE,MOUNTPOINT,SIZE >> /mnt/sysimage/root/storage_validation.log

if [ ! -f /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI ]; then
    echo "ERROR: Target fallback executable is missing from sda1!" >> /mnt/sysimage/root/ks-post-errors.log
fi

if [ ! -f "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI" ]; then
    echo "ERROR: Target fallback executable is missing from sdb1!" >> /mnt/sysimage/root/ks-post-errors.log
fi

echo "=== VOLUME GROUP & METADATA VERIFICATION ===" >> /mnt/sysimage/root/storage_validation.log
cat /proc/mdstat >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage pvs >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage vgs >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage lvs >> /mnt/sysimage/root/storage_validation.log

cleanup
trap - EXIT

# Deploy static standalone synchronization tool script
cat << 'EOF' > /mnt/sysimage/usr/local/sbin/sync-esp.sh
#!/bin/bash
set -e
if [ -d /boot/efi/EFI/rocky ] && [ -b /dev/sdb1 ]; then
    TMP_SYNC=$(mktemp -d)
    if mount /dev/sdb1 "$TMP_SYNC"; then
        mkdir -p "$TMP_SYNC/EFI/rocky"
        mkdir -p "$TMP_SYNC/EFI/BOOT"
        rsync -a --delete /boot/efi/EFI/rocky/ "$TMP_SYNC/EFI/rocky/"
        rsync -a --delete /boot/efi/EFI/BOOT/ "$TMP_SYNC/EFI/BOOT/"
        if [ -f /boot/efi/EFI/rocky/shimx64.efi ]; then
            cp /boot/efi/EFI/rocky/shimx64.efi "$TMP_SYNC/EFI/BOOT/BOOTX64.EFI"
        else
            cp /boot/efi/EFI/rocky/grubx64.efi "$TMP_SYNC/EFI/BOOT/BOOTX64.EFI"
        fi
        umount "$TMP_SYNC"
    fi
    rm -rf "$TMP_SYNC"
fi
EOF
chmod +x /mnt/sysimage/usr/local/sbin/sync-esp.sh

# Initial synchronization of the secondary ESP
chroot /mnt/sysimage /usr/local/sbin/sync-esp.sh

%end

reboot
```

# Rocky9_Golden_RAID.iso

# Kickstart 

```text
#version=RHEL9
cdrom
text

lang en_US.UTF-8
keyboard us
timezone Asia/Kolkata --utc

network --bootproto=dhcp --device=link --activate
rootpw --plaintext Root@123
firewall --enabled --service=ssh
selinux --enforcing
services --enabled=NetworkManager,sshd

# Standard EL9 UEFI Target Declaration
bootloader --boot-drive=sda --append="crashkernel=auto"

ignoredisk --only-use=sda,sdb
zerombr

# Clear target drive schemas to unlock metadata allocations
clearpart --all --initlabel --drives=sda,sdb

# Imports dynamically built partition mapping from %pre
%include /tmp/part-include

# FIXED: Aligned identifiers with the %pre block definition
raid pv.01 --device=md0 --level=1 raid.pv1 raid.pv2

# Volume Group Configuration
volgroup vg_root pv.01

# Logical Volumes
logvol / --fstype=xfs --name=root --vgname=vg_root --size=20480 --grow
logvol /home --fstype=xfs --name=home --vgname=vg_root --size=4096
logvol swap --fstype=swap --name=swap --vgname=vg_root --size=2048

%packages
@^minimal-environment
mdadm
lvm2
xfsprogs
efibootmgr
parted
shim-x64
grub2-efi-x64
vim
wget
curl
bash-completion
tar
gzip
rsync
net-tools
gdisk
%end

###############################################################################
# %pre Script: Structural disk partitioning for sda and sdb
###############################################################################
%pre --interpreter=/bin/bash
set -e
exec < /dev/tty3 > /dev/tty3 2>&1
chvt 3

echo "Pre-install: Preparing sda and sdb for Rocky 9.8..."

USE_PARTED=0
for cmd in sgdisk wipefs partprobe; do
    if ! command -v $cmd &>/dev/null; then
        echo "Required utility '$cmd' missing from image environment. Enforcing parted path."
        USE_PARTED=1
        break
    fi
done

if [ "$USE_PARTED" -eq 1 ]; then
    for disk in /dev/sda /dev/sdb; do
        DISK_SECTORS=$(blockdev --getsz $disk 2>/dev/null || echo 0)
        if [ "$DISK_SECTORS" -gt 40960 ]; then
            dd if=/dev/zero of=$disk bs=1M count=10 conv=notrunc
            seek_pos=$((DISK_SECTORS - 20480))
            dd if=/dev/zero of=$disk bs=512 seek=$seek_pos count=20480 conv=notrunc
        else
            dd if=/dev/zero of=$disk bs=512 count=2048 conv=notrunc
        fi

        parted -s $disk mklabel gpt
        parted -s $disk mkpart primary fat32 1MiB 601MiB
        parted -s $disk set 1 esp on
        parted -s $disk mkpart primary 601MiB 2649MiB
        parted -s $disk set 2 raid on
        parted -s $disk mkpart primary 2649MiB 100%
        parted -s $disk set 3 raid on

        partprobe $disk
    done
    udevadm settle
else
    for disk in /dev/sda /dev/sdb; do
        wipefs -a -f $disk
        sgdisk --zap-all $disk
        sgdisk -o $disk
        sgdisk -n 1:0:+600M -t 1:ef00 -c 1:"EFI System" $disk
        sgdisk -n 2:0:+2048M -t 2:fd00 -c 2:"Boot RAID" $disk
        sgdisk -n 3:0:0 -t 3:fd00 -c 3:"LVM RAID" $disk
        partprobe $disk
    done
    udevadm settle
fi

chvt 1

cat << 'EOF' > /tmp/part-include
part /boot/efi --fstype=efi --size=600 --ondisk=sda --fsoptions="umask=0077,shortname=winnt"
part raid.boot1 --fstype=mdmember --size=2048 --ondisk=sda
part raid.boot2 --fstype=mdmember --size=2048 --ondisk=sdb
raid /boot --device=md1 --level=1 --fstype=xfs raid.boot1 raid.boot2
part raid.pv1 --fstype=mdmember --size=1 --grow --ondisk=sda
part raid.pv2 --fstype=mdmember --size=1 --grow --ondisk=sdb
EOF
%end

###############################################################################
# Configure SSH
###############################################################################
%post --log=/root/ks-post-ssh.log
set -e
echo "Configuring SSH..."
SSHD_CONFIG=/etc/ssh/sshd_config

sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "$SSHD_CONFIG"
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"

grep -q "^UseDNS" "$SSHD_CONFIG" \
    && sed -i 's/^UseDNS.*/UseDNS no/' "$SSHD_CONFIG" \
    || echo "UseDNS no" >> "$SSHD_CONFIG"

grep -q "^UsePAM" "$SSHD_CONFIG" \
    && sed -i 's/^UsePAM.*/UsePAM yes/' "$SSHD_CONFIG"

systemctl enable sshd
echo "SSH configuration completed."
%end

###############################################################################
# Configure Verbose Boot & Mirror Alignment Redundancy Mechanics
###############################################################################
%post --nochroot --log=/mnt/sysimage/root/ks-post-grub.log
set -e

echo "Configuring verbose boot..."
chroot /mnt/sysimage /usr/sbin/grubby --update-kernel=ALL --remove-args="rhgb quiet"
chroot /mnt/sysimage /usr/sbin/grubby --update-kernel=ALL --args="loglevel=7 systemd.show_status=true"

# Rebuild original config structure
chroot /mnt/sysimage /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg
chroot /mnt/sysimage /usr/sbin/dracut -f

# Verify primary ESP filesystem is mounted cleanly before parsing it
if ! mountpoint -q /mnt/sysimage/boot/efi; then
    echo "CRITICAL ERROR: Primary ESP filesystem (/boot/efi) is not mounted!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

echo "Setting up proper UEFI Redundancy on /dev/sdb1..."
TARGET_MNT="/mnt/sysimage/boot/efi2"
mkdir -p "$TARGET_MNT"

cleanup() {
    echo "Executing filesystem mount safety cleanup sequence..."
    mountpoint -q "$TARGET_MNT" && umount "$TARGET_MNT"
    mountpoint -q "/mnt/sysimage/sys/firmware/efi/efivars" && umount "/mnt/sysimage/sys/firmware/efi/efivars"
    rmdir "$TARGET_MNT" 2>/dev/null || true
}
trap cleanup EXIT

# Ensure /dev/sdb1 is clean and ready
if ! blkid /dev/sdb1 | grep -q "vfat"; then
    mkfs.vfat -F 32 -n "EFI-SDB" /dev/sdb1
fi

if ! mount /dev/sdb1 "$TARGET_MNT"; then
    echo "CRITICAL ERROR: Failed to mount secondary ESP storage /dev/sdb1" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

if ! mountpoint -q "$TARGET_MNT"; then
    echo "CRITICAL ERROR: Target mountpoint validation check failed!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

if [ -d /sys/firmware/efi/efivars ]; then
    mkdir -p /mnt/sysimage/sys/firmware/efi/efivars
    mount --bind /sys/firmware/efi/efivars /mnt/sysimage/sys/firmware/efi/efivars || true
fi

# Run grub2-install into chroot using target path mount boundaries
if ! chroot /mnt/sysimage /usr/sbin/grub2-install --target=x86_64-efi --efi-directory=/boot/efi2 --bootloader-id=rocky --recheck; then
    echo "CRITICAL ERROR: grub2-install execution on secondary ESP failed!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Verify binary output layer explicitly
if [ ! -f "$TARGET_MNT/EFI/rocky/grubx64.efi" ]; then
    echo "CRITICAL ERROR: grub2-install completed but output binary is missing on secondary partition!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Re-map standard fallback directories
mkdir -p /mnt/sysimage/boot/efi/EFI/BOOT
mkdir -p "$TARGET_MNT/EFI/BOOT"

# Safe Secure Boot vs Non-Secure Boot identification for Rocky 9
if [ -f /mnt/sysimage/boot/efi/EFI/rocky/shimx64.efi ]; then
    echo "Secure Boot chain detected. Synchronizing matching shims..."
    cp /mnt/sysimage/boot/efi/EFI/rocky/shimx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI
    cp /mnt/sysimage/boot/efi/EFI/rocky/grubx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/grubx64.efi

    cp "$TARGET_MNT/EFI/rocky/shimx64.efi" "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI"
    cp "$TARGET_MNT/EFI/rocky/grubx64.efi" "$TARGET_MNT/EFI/BOOT/grubx64.efi"
    BOOT_TARGET="shimx64.efi"
else
    echo "Standard system configurations detected. Generating raw binary fallback entries..."
    cp /mnt/sysimage/boot/efi/EFI/rocky/grubx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI
    cp "$TARGET_MNT/EFI/rocky/grubx64.efi" "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI"
    BOOT_TARGET="grubx64.efi"
fi

if [ -f /mnt/sysimage/boot/efi/EFI/rocky/BOOTX64.CSV ]; then
    cp /mnt/sysimage/boot/efi/EFI/rocky/BOOTX64.CSV "$TARGET_MNT/EFI/rocky/BOOTX64.CSV"
fi

# Forward second stub directly to primary configuration space /boot/grub2/grub.cfg
chroot /mnt/sysimage /usr/sbin/grub2-mkconfig -o /boot/efi2/EFI/rocky/grub.cfg

# Register alternative paths cleanly inside NVRAM
if [ -d /sys/firmware/efi/efivars ]; then
    echo "Registering alternative secondary paths inside hardware NVRAM..."
    if ! efibootmgr -c -d /dev/sdb -p 1 -L "Rocky Backup Boot (sdb)" -l "\\EFI\\rocky\\${BOOT_TARGET}"; then
        echo "NOTICE: NVRAM generation dropped or un-writable in installer context. Falling back cleanly to BOOTX64.EFI." >> /mnt/sysimage/root/ks-post-errors.log
    fi
fi

# Run target verification loop pipelines
echo "=== STORAGE ENVIRONMENT LAYER AUDIT ===" >> /mnt/sysimage/root/storage_validation.log
lsblk -o NAME,FSTYPE,MOUNTPOINT,SIZE >> /mnt/sysimage/root/storage_validation.log

if [ ! -f /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI ]; then
    echo "ERROR: Target fallback executable is missing from sda1!" >> /mnt/sysimage/root/ks-post-errors.log
fi

if [ ! -f "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI" ]; then
    echo "ERROR: Target fallback executable is missing from sdb1!" >> /mnt/sysimage/root/ks-post-errors.log
fi

echo "=== VOLUME GROUP & METADATA VERIFICATION ===" >> /mnt/sysimage/root/storage_validation.log
cat /proc/mdstat >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage pvs >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage vgs >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage lvs >> /mnt/sysimage/root/storage_validation.log

cleanup
trap - EXIT

# Deploy static standalone synchronization tool script
cat << 'EOF' > /mnt/sysimage/usr/local/sbin/sync-esp.sh
#!/bin/bash
set -e
if [ -d /boot/efi/EFI/rocky ] && [ -b /dev/sdb1 ]; then
    TMP_SYNC=$(mktemp -d)
    if mount /dev/sdb1 "$TMP_SYNC"; then
        mkdir -p "$TMP_SYNC/EFI/rocky"
        mkdir -p "$TMP_SYNC/EFI/BOOT"
        rsync -a --delete /boot/efi/EFI/rocky/ "$TMP_SYNC/EFI/rocky/"
        rsync -a --delete /boot/efi/EFI/BOOT/ "$TMP_SYNC/EFI/BOOT/"
        if [ -f /boot/efi/EFI/rocky/shimx64.efi ]; then
            cp /boot/efi/EFI/rocky/shimx64.efi "$TMP_SYNC/EFI/BOOT/BOOTX64.EFI"
        else
            cp /boot/efi/EFI/rocky/grubx64.efi "$TMP_SYNC/EFI/BOOT/BOOTX64.EFI"
        fi
        umount "$TMP_SYNC"
    fi
    rm -rf "$TMP_SYNC"
fi
EOF
chmod +x /mnt/sysimage/usr/local/sbin/sync-esp.sh

# Initial synchronization of the secondary ESP
chroot /mnt/sysimage /usr/local/sbin/sync-esp.sh

%end

reboot
```


# Grub

# Path: EFI -> BOOT ->Grub.cfg

```text
set default="0"
set timeout=1

search --no-floppy --set=root -l 'updated_rocky9'

menuentry 'Install Rocky Linux 9 (Automatic RAID1)' {
    linuxefi /images/pxeboot/vmlinuz \
        inst.stage2=hd:LABEL=updated_rocky9 \
        inst.ks=cdrom:/kickstart/rockyos.cfg \
        inst.text

    initrdefi /images/pxeboot/initrd.img
}
```


# ISO LINUX

# Path: isolinux -> isolinux.cfg

```text
default auto
timeout 1

display boot.msg

menu clear
menu title Rocky Linux 9 Automatic Installation

label auto
    menu label ^Install Rocky Linux 9 (Automatic RAID1)
    kernel vmlinuz
    append initrd=initrd.img inst.stage2=hd:LABEL=updated_rocky9 inst.ks=cdrom:/kickstart/rockyos.cfg inst.text
```

## PXE Kickstarts

## ROCKY 9

```text
#version=RHEL9
url --url="http://192.168.253.136/repo/rocky9/"
text

# System language and keyboard
lang en_US.UTF-8
keyboard us

# Timezone
timezone Asia/Kolkata --utc

# Network configuration (hostname will come from kernel arg)
network --bootproto=dhcp --device=link --activate

# Root password
rootpw --plaintext Root@123

firewall --enabled --service=ssh
selinux --enforcing
services --enabled=NetworkManager,sshd

# Standard EL9 UEFI target declaration
bootloader --boot-drive=sda --append="crashkernel=auto"

###############################################################################
# Storage Configuration (UEFI + RAID1 + LVM)
###############################################################################
ignoredisk --only-use=sda,sdb
zerombr
clearpart --none

# Imports dynamically built partition mapping from %pre
%include /tmp/part-include

# RAID1 PV (Handles OS & Data Redundancy)
raid pv.01 --device=md0 --level=1 raid.pv1 raid.pv2

# Volume Group
volgroup rockyos pv.01

###############################################################################
# Logical Volumes
###############################################################################
logvol / --fstype=xfs --name=root --vgname=rockyos --size=8192 --grow
logvol /home --fstype=xfs --name=home --vgname=rockyos --size=4096
logvol swap --fstype=swap --name=swap --vgname=rockyos --size=2048

# Package selection
%packages
@^server
xfsprogs
efibootmgr
parted
shim-x64
grub2-efi-x64
mdadm
lvm2
rsync
e2fsprogs
-plymouth
-plymouth-core-libs
%end

###############################################################################
# %pre Script: Dynamic Disk Partitioning Framework
###############################################################################
%pre --interpreter=/bin/bash
set -e  
exec < /dev/tty3 > /dev/tty3 2>&1
chvt 3

echo "Pre-install: Structuring layouts for sda and sdb..."

USE_PARTED=0
for cmd in sgdisk wipefs partprobe; do
    if ! command -v $cmd &>/dev/null; then
        echo "Required utility '$cmd' missing from image environment. Enforcing parted path."
        USE_PARTED=1
        break
    fi
done

if [ "$USE_PARTED" -eq 1 ]; then
    for disk in /dev/sda /dev/sdb; do
        DISK_SECTORS=$(blockdev --getsz $disk 2>/dev/null || echo 0)
        if [ "$DISK_SECTORS" -gt 40960 ]; then
            dd if=/dev/zero of=$disk bs=1M count=10 conv=notrunc
            seek_pos=$((DISK_SECTORS - 20480))
            dd if=/dev/zero of=$disk bs=512 seek=$seek_pos count=20480 conv=notrunc
        else
            dd if=/dev/zero of=$disk bs=512 count=2048 conv=notrunc
        fi
        
        parted -s $disk mklabel gpt
        parted -s $disk mkpart primary fat32 1MiB 601MiB
        parted -s $disk set 1 esp on
        parted -s $disk mkpart primary 601MiB 2649MiB
        parted -s $disk set 2 raid on
        parted -s $disk mkpart primary 2649MiB 100%
        parted -s $disk set 3 raid on
        
        partprobe $disk
    done
    udevadm settle
else
    for disk in /dev/sda /dev/sdb; do
        wipefs -a -f $disk
        sgdisk --zap-all $disk
        sgdisk -o $disk
        sgdisk -n 1:0:+600M -t 1:ef00 -c 1:"EFI System" $disk
        sgdisk -n 2:0:+2048M -t 2:fd00 -c 2:"Boot RAID" $disk
        sgdisk -n 3:0:0 -t 3:fd00 -c 3:"LVM RAID" $disk
        partprobe $disk
    done
    udevadm settle
fi

chvt 1

# Generate kickstart partition configuration dynamically matching your exact sizing specs
cat << 'EOF' > /tmp/part-include
part /boot/efi --fstype=efi --size=600 --ondisk=sda --fsoptions="umask=0077,shortname=winnt"
part raid.boot1 --fstype=mdmember --size=2048 --ondisk=sda
part raid.boot2 --fstype=mdmember --size=2048 --ondisk=sdb
raid /boot --device=md1 --level=1 --fstype=xfs raid.boot1 raid.boot2
part raid.pv1 --fstype=mdmember --size=1 --grow --ondisk=sda
part raid.pv2 --fstype=mdmember --size=1 --grow --ondisk=sdb
EOF
%end

###############################################################################
# Set hostname from kernel parameter
###############################################################################
%post --log=/root/ks-post.log
HOSTNAME=$(grep -oP '(?<=hostname=)[^\s]+' /proc/cmdline)
if [ -n "$HOSTNAME" ]; then
    echo "$HOSTNAME" >/etc/hostname
    hostnamectl set-hostname "$HOSTNAME"
    echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
fi
%end

###############################################################################
# Configure DNS
###############################################################################
%post
cat >/etc/resolv.conf <<EOF
nameserver 192.168.253.1
search vgs.com
EOF
%end

###############################################################################
# Prevent DHCP from overwriting hostname and DNS
###############################################################################
%post
mkdir -p /etc/NetworkManager/conf.d

cat >/etc/NetworkManager/conf.d/10-dhcp-hostname.conf <<EOF
[main]
hostname-mode=none
EOF

cat >/etc/NetworkManager/conf.d/10-dhcp-dns.conf <<EOF
[main]
dns=none
EOF
%end

###############################################################################
# Configure SSH
###############################################################################
%post --log=/root/ks-post-ssh.log
echo "Configuring SSH..."
cat >> /etc/ssh/sshd_config <<EOF

PermitRootLogin yes
PasswordAuthentication yes
EOF
systemctl enable sshd
%end

###############################################################################
# Create Admin User
###############################################################################
%post --log=/root/ks-post-admin.log
echo "Creating admin user..."
useradd -m -s /bin/bash admin
echo "admin:Vigneshv12$" | chpasswd
usermod -aG wheel admin

cat > /etc/sudoers.d/admin <<EOF
admin ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/admin
echo "Admin user created successfully."
%end

###############################################################################
# Configure Verbose Boot, Rebuild Configs, Align Dual ESP Redundancy
###############################################################################
%post --nochroot --log=/mnt/sysimage/root/ks-post-grub.log
set -e

echo "Configuring Verbose Console Boot..."

# 1. Capture LVM and Resume arguments 
LVM_VARS=$(grep -o "rd.lvm.lv=[^ ]*" /proc/cmdline | tr '\n' ' ')
RESUME_VAR=$(grep -o "resume=[^ ]*" /proc/cmdline)

# 2. Configure /etc/default/grub (Canonical EL9 framework format)
cat >/mnt/sysimage/etc/default/grub <<EOF
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Rocky Linux"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=9600 --unit=0 --word=8 --parity=no --stop=1"
GRUB_CMDLINE_LINUX="$LVM_VARS $RESUME_VAR loglevel=7 systemd.show_status=true console=ttyS0,9600 console=tty0"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
EOF

# 3. Kill Plymouth
chroot /mnt/sysimage /usr/bin/systemctl mask plymouth-start.service

# 4. Update Kernel Entries via grubby
chroot /mnt/sysimage /usr/sbin/grubby --update-kernel=ALL --remove-args="rhgb quiet console"
chroot /mnt/sysimage /usr/sbin/grubby --update-kernel=ALL --args="loglevel=7 systemd.show_status=true console=ttyS0,9600 console=tty0"

# 5. Build final canonical GRUB configuration for Rocky 9 (Stored directly in /boot/grub2/)
chroot /mnt/sysimage /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg
chroot /mnt/sysimage /usr/sbin/dracut -f

# Verify primary ESP filesystem is mounted cleanly before reading it
if ! mountpoint -q /mnt/sysimage/boot/efi; then
    echo "CRITICAL ERROR: Primary ESP filesystem (/boot/efi) is not mounted!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

echo "Setting up proper UEFI Redundancy on /dev/sdb1..."
TARGET_MNT="/mnt/sysimage/boot/efi2"
mkdir -p "$TARGET_MNT"

cleanup() {
    echo "Executing filesystem mount safety cleanup sequence..."
    mountpoint -q "$TARGET_MNT" && umount "$TARGET_MNT"
    mountpoint -q "/mnt/sysimage/sys/firmware/efi/efivars" && umount "/mnt/sysimage/sys/firmware/efi/efivars"
    rmdir "$TARGET_MNT" 2>/dev/null || true
}
trap cleanup EXIT

# Ensure /dev/sdb1 has a clean FAT32 layout
if ! blkid /dev/sdb1 | grep -q "vfat"; then
    mkfs.vfat -F 32 -n "EFI-SDB" /dev/sdb1
fi

if ! mount /dev/sdb1 "$TARGET_MNT"; then
    echo "CRITICAL ERROR: Failed to mount secondary ESP storage /dev/sdb1" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

if ! mountpoint -q "$TARGET_MNT"; then
    echo "CRITICAL ERROR: Target mountpoint validation check failed!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Verify physical EFI execution variables are exposed before writing to motherboard NVRAM
if [ -d /sys/firmware/efi/efivars ]; then
    mkdir -p /mnt/sysimage/sys/firmware/efi/efivars
    mount --bind /sys/firmware/efi/efivars /mnt/sysimage/sys/firmware/efi/efivars || true
fi

# Run grub2-install into chroot context pointing to the valid internal efi2 path boundary
if ! chroot /mnt/sysimage /usr/sbin/grub2-install --target=x86_64-efi --efi-directory=/boot/efi2 --bootloader-id=rocky --recheck; then
    echo "CRITICAL ERROR: grub2-install execution on secondary ESP failed!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Double check that the target output layout binary was built
if [ ! -f "$TARGET_MNT/EFI/rocky/grubx64.efi" ]; then
    echo "CRITICAL ERROR: grub2-install completed but output binary is missing on secondary partition!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Re-map standard fallback structures
mkdir -p /mnt/sysimage/boot/efi/EFI/BOOT
mkdir -p "$TARGET_MNT/EFI/BOOT"

# Safe Secure Boot vs Non-Secure Boot identification for Rocky 9
if [ -f /mnt/sysimage/boot/efi/EFI/rocky/shimx64.efi ]; then
    echo "Secure Boot chain detected. Synchronizing matching shims..."
    cp /mnt/sysimage/boot/efi/EFI/rocky/shimx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI
    cp /mnt/sysimage/boot/efi/EFI/rocky/grubx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/grubx64.efi
    
    cp "$TARGET_MNT/EFI/rocky/shimx64.efi" "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI"
    cp "$TARGET_MNT/EFI/rocky/grubx64.efi" "$TARGET_MNT/EFI/BOOT/grubx64.efi"
    BOOT_TARGET="shimx64.efi"
else
    echo "Standard system configurations detected. Generating raw binary fallback entries..."
    cp /mnt/sysimage/boot/efi/EFI/rocky/grubx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI
    cp "$TARGET_MNT/EFI/rocky/grubx64.efi" "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI"
    BOOT_TARGET="grubx64.efi"
fi

if [ -f /mnt/sysimage/boot/efi/EFI/rocky/BOOTX64.CSV ]; then
    cp /mnt/sysimage/boot/efi/EFI/rocky/BOOTX64.CSV "$TARGET_MNT/EFI/rocky/BOOTX64.CSV"
fi

# Forward second stub directly to primary configuration space /boot/grub2/grub.cfg
chroot /mnt/sysimage /usr/sbin/grub2-mkconfig -o /boot/efi2/EFI/rocky/grub.cfg

# Register alternative paths cleanly inside hardware boot entries list
if [ -d /sys/firmware/efi/efivars ]; then
    echo "Registering alternative secondary paths inside hardware NVRAM..."
    if ! efibootmgr -c -d /dev/sdb -p 1 -L "Rocky Backup Boot (sdb)" -l "\\EFI\\rocky\\${BOOT_TARGET}"; then
        echo "NOTICE: NVRAM entry dropped or un-writable in installer context. Falling back cleanly to BOOTX64.EFI." >> /mnt/sysimage/root/ks-post-errors.log
    fi
fi

# Run target verification loop pipelines
echo "=== STORAGE ENVIRONMENT LAYER AUDIT ===" >> /mnt/sysimage/root/storage_validation.log
lsblk -o NAME,FSTYPE,MOUNTPOINT,SIZE >> /mnt/sysimage/root/storage_validation.log

if [ ! -f /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI ]; then
    echo "ERROR: Target fallback executable is missing from sda1!" >> /mnt/sysimage/root/ks-post-errors.log
fi

if [ ! -f "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI" ]; then
    echo "ERROR: Target fallback executable is missing from sdb1!" >> /mnt/sysimage/root/ks-post-errors.log
fi

echo "=== VOLUME GROUP & METADATA VERIFICATION ===" >> /mnt/sysimage/root/storage_validation.log
cat /proc/mdstat >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage pvs >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage vgs >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage lvs >> /mnt/sysimage/root/storage_validation.log

cleanup
trap - EXIT

# Deploy standalone runtime sync-esp tracking script inside the OS filesystem
cat << 'EOF' > /mnt/sysimage/usr/local/sbin/sync-esp.sh
#!/bin/bash
if [ -d /boot/efi/EFI/rocky ] && [ -b /dev/sdb1 ]; then
    TMP_SYNC=$(mktemp -d)
    if mount /dev/sdb1 "$TMP_SYNC"; then
        mkdir -p "$TMP_SYNC/EFI/rocky"
        mkdir -p "$TMP_SYNC/EFI/BOOT"
        rsync -a --delete /boot/efi/EFI/rocky/ "$TMP_SYNC/EFI/rocky/"
        rsync -a --delete /boot/efi/EFI/BOOT/ "$TMP_SYNC/EFI/BOOT/"
        if [ -f /boot/efi/EFI/rocky/shimx64.efi ]; then
            cp /boot/efi/EFI/rocky/shimx64.efi "$TMP_SYNC/EFI/BOOT/BOOTX64.EFI"
        else
            cp /boot/efi/EFI/rocky/grubx64.efi "$TMP_SYNC/EFI/BOOT/BOOTX64.EFI"
        fi
        umount "$TMP_SYNC"
    fi
    rm -rf "$TMP_SYNC"
fi
EOF
chmod +x /mnt/sysimage/usr/local/sbin/sync-esp.sh

# Deploy native systemd kernel-install plugin hook layout for Rocky 9.8
# Rocky 9 natively uses drop-in scripts inside /etc/kernel/install.d/ to process kernel addition updates.
# By setting up this clean hook script, the synchronization engine triggers automatically on any subsequent transaction.
mkdir -p /mnt/sysimage/etc/kernel/install.d
cat << 'EOF' > /mnt/sysimage/etc/kernel/install.d/99-sync-esp.install
#!/bin/bash
# Rocky 9 systemd kernel-install hook logic
COMMAND="$1"
KERNEL_VERSION="$2"
BOOT_DIR_ABS="$3"
KERNEL_IMAGE="$4"

export PATH=/sbin:/usr/sbin:/bin:/usr/bin

# Fire tracking synchronizer script immediately upon package addition updates
if [ -x /usr/local/sbin/sync-esp.sh ]; then
    /usr/local/sbin/sync-esp.sh >/dev/null 2>&1 || true
fi
exit 0
EOF
chmod +x /mnt/sysimage/etc/kernel/install.d/99-sync-esp.install

echo "Verbose console configuration complete."
%end

reboot
```

# Rocky 8

```text
# System language and keyboard
lang en_US.UTF-8
keyboard us

# Timezone
timezone Asia/Kolkata --utc

# Network configuration (hostname will come from kernel arg)
network --bootproto=dhcp --device=link --activate

# Installation source
url --url="http://192.168.253.136/repo/rocky8/"

# Root password
rootpw --plaintext Root@123

firewall --enabled --service=ssh
selinux --enforcing
services --enabled=NetworkManager,sshd

# Standard EL8 UEFI target declaration
bootloader --boot-drive=sda

###############################################################################
# Storage Configuration (UEFI + RAID1 + LVM)
###############################################################################
ignoredisk --only-use=sda,sdb
zerombr
clearpart --none

# Imports dynamically built partition mapping from %pre
%include /tmp/part-include

# RAID1 PV (Handles OS & Data Redundancy)
raid pv.01 --device=md0 --level=1 raid.pv1 raid.pv2

# LVM
volgroup rockyos pv.01

###############################################################################
# Logical Volumes
###############################################################################
logvol / --fstype=xfs --name=root --vgname=rockyos --size=8192 --grow
logvol /home --fstype=xfs --name=home --vgname=rockyos --size=4096
logvol swap --fstype=swap --name=swap --vgname=rockyos --size=2048

# Package selection
%packages
@^server
xfsprogs
efibootmgr
parted
shim-x64
grub2-efi-x64
mdadm
lvm2
rsync
e2fsprogs
%end

###############################################################################
# %pre Script: Dynamic Disk Partitioning Framework
###############################################################################
%pre --interpreter=/bin/bash
set -e  
exec < /dev/tty3 > /dev/tty3 2>&1
chvt 3

echo "Pre-install: Structuring layouts for sda and sdb..."

USE_PARTED=0
for cmd in sgdisk wipefs partprobe; do
    if ! command -v $cmd &>/dev/null; then
        echo "Required utility '$cmd' missing from image environment. Enforcing parted path."
        USE_PARTED=1
        break
    fi
done

if [ "$USE_PARTED" -eq 1 ]; then
    for disk in /dev/sda /dev/sdb; do
        DISK_SECTORS=$(blockdev --getsz $disk 2>/dev/null || echo 0)
        if [ "$DISK_SECTORS" -gt 40960 ]; then
            dd if=/dev/zero of=$disk bs=1M count=10 conv=notrunc
            seek_pos=$((DISK_SECTORS - 20480))
            dd if=/dev/zero of=$disk bs=512 seek=$seek_pos count=20480 conv=notrunc
        else
            dd if=/dev/zero of=$disk bs=512 count=2048 conv=notrunc
        fi
        
        parted -s $disk mklabel gpt
        parted -s $disk mkpart primary fat32 1MiB 513MiB
        parted -s $disk set 1 esp on
        parted -s $disk mkpart primary 513MiB 2561MiB
        parted -s $disk set 2 raid on
        parted -s $disk mkpart primary 2561MiB 100%
        parted -s $disk set 3 raid on
        
        partprobe $disk
    done
    udevadm settle
else
    for disk in /dev/sda /dev/sdb; do
        wipefs -a -f $disk
        sgdisk --zap-all $disk
        sgdisk -o $disk
        sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System" $disk
        sgdisk -n 2:0:+2048M -t 2:fd00 -c 2:"Boot RAID" $disk
        sgdisk -n 3:0:0 -t 3:fd00 -c 3:"LVM RAID" $disk
        partprobe $disk
    done
    udevadm settle
fi

chvt 1

# Generate kickstart partition configuration dynamically
cat << 'EOF' > /tmp/part-include
part /boot/efi --fstype=efi --size=512 --ondisk=sda --fsoptions="defaults"
part raid.boot1 --fstype=mdmember --size=2048 --ondisk=sda
part raid.boot2 --fstype=mdmember --size=2048 --ondisk=sdb
raid /boot --device=md1 --level=1 --fstype=xfs raid.boot1 raid.boot2
part raid.pv1 --fstype=mdmember --size=1 --grow --ondisk=sda
part raid.pv2 --fstype=mdmember --size=1 --grow --ondisk=sdb
EOF
%end

###############################################################################
# Post-install configuration: Set hostname from kernel arg
###############################################################################
%post --log=/root/ks-post.log
HOSTNAME=$(grep -oP '(?<=hostname=)[^\s]+' /proc/cmdline)
if [ -n "$HOSTNAME" ]; then
    echo "$HOSTNAME" > /etc/hostname
    hostnamectl set-hostname "$HOSTNAME"
    echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
fi
%end

###############################################################################
# Post-install: Set DNS servers
###############################################################################
%post
echo "nameserver 192.168.253.1" > /etc/resolv.conf
echo "search vgs.com" >> /etc/resolv.conf
%end

###############################################################################
# Prevent DHCP from overriding hostname and DNS on reboot
###############################################################################
%post
mkdir -p /etc/NetworkManager/conf.d

# Disable DHCP hostname override
cat > /etc/NetworkManager/conf.d/10-dhcp-hostname.conf <<'EOF'
[main]
hostname-mode=none
EOF

# Disable DHCP DNS override
cat > /etc/NetworkManager/conf.d/10-dhcp-dns.conf <<'EOF'
[main]
dns=none
EOF
%end

###############################################################################
# Create Admin User
###############################################################################
%post --log=/root/ks-post-admin.log

echo "Creating admin user..."
useradd -m -s /bin/bash admin
echo "admin:Vigneshv12$" | chpasswd
usermod -aG wheel admin

cat > /etc/sudoers.d/admin <<EOF
admin ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/admin

echo "Admin user created successfully."
%end

###############################################################################
# Configure Dual Console Verbose Boot & Dynamic UEFI Mirror Redundancy
###############################################################################
%post --nochroot --log=/mnt/sysimage/root/ks-post-grub.log
set -e

echo "Configuring Dual Console Verbose Boot..."

# 1. Capture LVM and Resume arguments 
LVM_VARS=$(grep -o "rd.lvm.lv=[^ ]*" /proc/cmdline | tr '\n' ' ')
RESUME_VAR=$(grep -o "resume=[^ ]*" /proc/cmdline)

# 2. Configure /etc/default/grub (Canonical EL8 format)
cat <<EOF > /mnt/sysimage/etc/default/grub
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Rocky Linux"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=9600 --unit=0 --word=8 --parity=no --stop=1"
GRUB_CMDLINE_LINUX="$LVM_VARS $RESUME_VAR loglevel=7 systemd.show_status=true console=ttyS0,9600 console=tty0"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
EOF

# 3. Kill Plymouth (ensures text-only boot)
chroot /mnt/sysimage /usr/bin/systemctl mask plymouth-start.service

# 4. Update Kernel Entries via grubby
chroot /mnt/sysimage /usr/sbin/grubby --update-kernel=ALL --remove-args="rhgb quiet console"
chroot /mnt/sysimage /usr/sbin/grubby --update-kernel=ALL --args="loglevel=7 systemd.show_status=true console=ttyS0,9600 console=tty0"

# 5. Build final canonical GRUB configuration for Rocky 8 (Stored directly in /boot/grub2/)
chroot /mnt/sysimage /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg
chroot /mnt/sysimage /usr/sbin/dracut -f

# Verify primary ESP filesystem is mounted cleanly before reading it
if ! mountpoint -q /mnt/sysimage/boot/efi; then
    echo "CRITICAL ERROR: Primary ESP filesystem (/boot/efi) is not mounted!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

echo "Setting up proper UEFI Redundancy on /dev/sdb1..."
TARGET_MNT="/mnt/sysimage/boot/efi2"
mkdir -p "$TARGET_MNT"

cleanup() {
    echo "Executing filesystem mount safety cleanup sequence..."
    mountpoint -q "$TARGET_MNT" && umount "$TARGET_MNT"
    mountpoint -q "/mnt/sysimage/sys/firmware/efi/efivars" && umount "/mnt/sysimage/sys/firmware/efi/efivars"
    rmdir "$TARGET_MNT" 2>/dev/null || true
}
trap cleanup EXIT

# Ensure /dev/sdb1 has a clean FAT32 layout
if ! blkid /dev/sdb1 | grep -q "vfat"; then
    mkfs.vfat -F 32 -n "EFI-SDB" /dev/sdb1
fi

if ! mount /dev/sdb1 "$TARGET_MNT"; then
    echo "CRITICAL ERROR: Failed to mount secondary ESP storage /dev/sdb1" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

if ! mountpoint -q "$TARGET_MNT"; then
    echo "CRITICAL ERROR: Target mountpoint validation check failed!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Verify physical EFI execution variables are exposed before writing to motherboard NVRAM
if [ -d /sys/firmware/efi/efivars ]; then
    mkdir -p /mnt/sysimage/sys/firmware/efi/efivars
    mount --bind /sys/firmware/efi/efivars /mnt/sysimage/sys/firmware/efi/efivars || true
fi

# Run grub2-install into chroot context pointing to the valid internal efi2 path boundary
if ! chroot /mnt/sysimage /usr/sbin/grub2-install --target=x86_64-efi --efi-directory=/boot/efi2 --bootloader-id=rocky --recheck; then
    echo "CRITICAL ERROR: grub2-install execution on secondary ESP failed!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Double check that the target output layout binary was built
if [ ! -f "$TARGET_MNT/EFI/rocky/grubx64.efi" ]; then
    echo "CRITICAL ERROR: grub2-install completed but output binary is missing on secondary partition!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Re-map standard fallback structures
mkdir -p /mnt/sysimage/boot/efi/EFI/BOOT
mkdir -p "$TARGET_MNT/EFI/BOOT"

# Safe Secure Boot vs Non-Secure Boot identification for Rocky 8
if [ -f /mnt/sysimage/boot/efi/EFI/rocky/shimx64.efi ]; then
    echo "Secure Boot chain detected. Synchronizing matching shims..."
    cp /mnt/sysimage/boot/efi/EFI/rocky/shimx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI
    cp /mnt/sysimage/boot/efi/EFI/rocky/grubx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/grubx64.efi
    
    cp "$TARGET_MNT/EFI/rocky/shimx64.efi" "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI"
    cp "$TARGET_MNT/EFI/rocky/grubx64.efi" "$TARGET_MNT/EFI/BOOT/grubx64.efi"
    BOOT_TARGET="shimx64.efi"
else
    echo "Standard system configurations detected. Generating raw binary fallback entries..."
    cp /mnt/sysimage/boot/efi/EFI/rocky/grubx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI
    cp "$TARGET_MNT/EFI/rocky/grubx64.efi" "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI"
    BOOT_TARGET="grubx64.efi"
fi

if [ -f /mnt/sysimage/boot/efi/EFI/rocky/BOOTX64.CSV ]; then
    cp /mnt/sysimage/boot/efi/EFI/rocky/BOOTX64.CSV "$TARGET_MNT/EFI/rocky/BOOTX64.CSV"
fi

# Forward second stub directly to primary configuration space /boot/grub2/grub.cfg
chroot /mnt/sysimage /usr/sbin/grub2-mkconfig -o /boot/efi2/EFI/rocky/grub.cfg

# Register alternative paths cleanly inside hardware boot entries list
if [ -d /sys/firmware/efi/efivars ]; then
    echo "Registering alternative secondary paths inside hardware NVRAM..."
    if ! efibootmgr -c -d /dev/sdb -p 1 -L "Rocky Backup Boot (sdb)" -l "\\EFI\\rocky\\${BOOT_TARGET}"; then
        echo "NOTICE: NVRAM entry dropped or un-writable in installer context. Falling back cleanly to BOOTX64.EFI." >> /mnt/sysimage/root/ks-post-errors.log
    fi
fi

# Run target verification loop pipelines
echo "=== STORAGE ENVIRONMENT LAYER AUDIT ===" >> /mnt/sysimage/root/storage_validation.log
lsblk -o NAME,FSTYPE,MOUNTPOINT,SIZE >> /mnt/sysimage/root/storage_validation.log

if [ ! -f /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI ]; then
    echo "ERROR: Target fallback executable is missing from sda1!" >> /mnt/sysimage/root/ks-post-errors.log
fi

if [ ! -f "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI" ]; then
    echo "ERROR: Target fallback executable is missing from sdb1!" >> /mnt/sysimage/root/ks-post-errors.log
fi

echo "=== VOLUME GROUP & METADATA VERIFICATION ===" >> /mnt/sysimage/root/storage_validation.log
cat /proc/mdstat >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage pvs >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage vgs >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage lvs >> /mnt/sysimage/root/storage_validation.log

cleanup
trap - EXIT

# Deploy standalone runtime sync-esp tracking script inside the OS filesystem
cat << 'EOF' > /mnt/sysimage/usr/local/sbin/sync-esp.sh
#!/bin/bash
if [ -d /boot/efi/EFI/rocky ] && [ -b /dev/sdb1 ]; then
    TMP_SYNC=$(mktemp -d)
    if mount /dev/sdb1 "$TMP_SYNC"; then
        mkdir -p "$TMP_SYNC/EFI/rocky"
        mkdir -p "$TMP_SYNC/EFI/BOOT"
        rsync -a --delete /boot/efi/EFI/rocky/ "$TMP_SYNC/EFI/rocky/"
        rsync -a --delete /boot/efi/EFI/BOOT/ "$TMP_SYNC/EFI/BOOT/"
        if [ -f /boot/efi/EFI/rocky/shimx64.efi ]; then
            cp /boot/efi/EFI/rocky/shimx64.efi "$TMP_SYNC/EFI/BOOT/BOOTX64.EFI"
        else
            cp /boot/efi/EFI/rocky/grubx64.efi "$TMP_SYNC/EFI/BOOT/BOOTX64.EFI"
        fi
        umount "$TMP_SYNC"
    fi
    rm -rf "$TMP_SYNC"
fi
EOF
chmod +x /mnt/sysimage/usr/local/sbin/sync-esp.sh

# Deploy native documented systemd kernel-install extension hook point for Rocky 8
# Because Rocky 8 executes hook scripts out of /etc/kernel/postinst.d/ on every single kernel 
# addition or update, this robust wrapper receives the kernel parameters cleanly and forces 
# our standalone rsync engine to keep sda1 and sdb1 100% mirrored.
mkdir -p /mnt/sysimage/etc/kernel/postinst.d
cat << 'EOF' > /mnt/sysimage/etc/kernel/postinst.d/95-sync-esp.install
#!/bin/bash
# Rocky 8 kernel-install positional arguments: $1 = kernel-version, $2 = boot-path
KERNEL_VERSION="$1"
BOOT_PATH="$2"

export PATH=/sbin:/usr/sbin:/bin:/usr/bin

# Force block replication synchronization immediately across the partitions
if [ -x /usr/local/sbin/sync-esp.sh ]; then
    /usr/local/sbin/sync-esp.sh >/dev/null 2>&1 || true
fi
EOF
chmod +x /mnt/sysimage/etc/kernel/postinst.d/95-sync-esp.install

echo "Dual Console configuration complete. Output directed to ttyS0 and tty0."
%end

# Reboot after installation
reboot
```

# CENTOS

```text
# System language and keyboard
lang en_US.UTF-8
keyboard us

# Timezone
timezone Asia/Kolkata --utc

# Network configuration (hostname will come from kernel arg)
network --bootproto=dhcp --device=link --activate

# Installation source
url --url="http://192.168.253.136/repo/centos7"

# Root password
rootpw --plaintext Root@123

firewall --enabled --service=ssh
selinux --enforcing
services --enabled=NetworkManager,sshd

# Standard UEFI target declaration
bootloader --boot-drive=sda

###############################################################################
# Storage Configuration (UEFI + RAID1 + LVM)
###############################################################################
ignoredisk --only-use=sda,sdb
zerombr
clearpart --none

# Imports dynamically built partition mapping from %pre
%include /tmp/part-include

# RAID1 PV (Handles OS & Data Redundancy)
raid pv.01 --device=md0 --level=1 raid.pv1 raid.pv2

# LVM
volgroup centos pv.01

logvol / --fstype=xfs --name=root --vgname=centos --size=8192 --grow
logvol /home --fstype=xfs --name=home --vgname=centos --size=4096
logvol swap --fstype=swap --name=swap --vgname=centos --size=2048

# Package selection
%packages
@^infrastructure-server-environment
xfsprogs
efibootmgr
parted
shim
grub2-efi-x64
mdadm
lvm2
rsync
e2fsprogs
%end

###############################################################################
# %pre Script: Dynamic Disk Partitioning Framework
###############################################################################
%pre --interpreter=/bin/bash
set -e  
exec < /dev/tty3 > /dev/tty3 2>&1
chvt 3

echo "Pre-install: Structuring layouts for sda and sdb..."

USE_PARTED=0
for cmd in sgdisk wipefs partprobe; do
    if ! command -v $cmd &>/dev/null; then
        echo "Required utility '$cmd' missing from image environment. Enforcing parted path."
        USE_PARTED=1
        break
    fi
done

if [ "$USE_PARTED" -eq 1 ]; then
    for disk in /dev/sda /dev/sdb; do
        DISK_SECTORS=$(blockdev --getsz $disk 2>/dev/null || echo 0)
        if [ "$DISK_SECTORS" -gt 40960 ]; then
            dd if=/dev/zero of=$disk bs=1M count=10 conv=notrunc
            seek_pos=$((DISK_SECTORS - 20480))
            dd if=/dev/zero of=$disk bs=512 seek=$seek_pos count=20480 conv=notrunc
        else
            dd if=/dev/zero of=$disk bs=512 count=2048 conv=notrunc
        fi
        
        parted -s $disk mklabel gpt
        parted -s $disk mkpart primary fat32 1MiB 513MiB
        parted -s $disk set 1 esp on
        parted -s $disk mkpart primary 513MiB 1537MiB
        parted -s $disk set 2 raid on
        parted -s $disk mkpart primary 1537MiB 100%
        parted -s $disk set 3 raid on
        
        partprobe $disk
    done
    udevadm settle
else
    for disk in /dev/sda /dev/sdb; do
        wipefs -a -f $disk
        sgdisk --zap-all $disk
        sgdisk -o $disk
        sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System" $disk
        sgdisk -n 2:0:+1024M -t 2:fd00 -c 2:"Boot RAID" $disk
        sgdisk -n 3:0:0 -t 3:fd00 -c 3:"LVM RAID" $disk
        partprobe $disk
    done
    udevadm settle
fi

chvt 1

# Generate kickstart partition configuration dynamically
cat << 'EOF' > /tmp/part-include
part /boot/efi --fstype=efi --size=512 --ondisk=sda
part raid.boot1 --fstype=mdmember --size=1024 --ondisk=sda
part raid.boot2 --fstype=mdmember --size=1024 --ondisk=sdb
raid /boot --device=md1 --level=1 --fstype=xfs raid.boot1 raid.boot2
part raid.pv1 --fstype=mdmember --size=1 --grow --ondisk=sda
part raid.pv2 --fstype=mdmember --size=1 --grow --ondisk=sdb
EOF
%end

###############################################################################
# Post-install configuration: Set hostname and DNS
###############################################################################
%post --log=/root/ks-post.log
# Set hostname from kernel cmdline
HOSTNAME=$(grep -oP '(?<=hostname=)[^\s]+' /proc/cmdline)
if [ -n "$HOSTNAME" ]; then
    echo "$HOSTNAME" > /etc/hostname
    hostnamectl set-hostname "$HOSTNAME"
    echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
fi

# Find primary interface config file
IFCFG=$(ls /etc/sysconfig/network-scripts/ifcfg-* | grep -v ifcfg-lo | head -n 1)

# Disable DHCP DNS and set static DNS
sed -i '/^PEERDNS/d' $IFCFG
echo 'PEERDNS=no' >> $IFCFG
echo 'DNS1=192.168.253.1' >> $IFCFG

# Set DNS search domain
echo "search vgs.com" > /etc/resolv.conf
echo "nameserver 192.168.253.1" >> /etc/resolv.conf

# Make resolv.conf immutable
chattr +i /etc/resolv.conf
%end

###############################################################################
# Create Admin User
###############################################################################
%post --log=/root/ks-post-admin.log

echo "Creating admin user..."
useradd -m -s /bin/bash admin
echo "admin:Vigneshv12$" | chpasswd
usermod -aG wheel admin

cat > /etc/sudoers.d/admin <<EOF
admin ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 /etc/sudoers.d/admin

echo "Admin user created successfully."
%end

###############################################################################
# Configure Verbose Boot, Rebuild Configs, Align Dual ESP Redundancy
###############################################################################
%post --nochroot --log=/mnt/sysimage/root/ks-verbose-boot.log
set -e

echo "Configuring verbose boot..."

# 1. Standardize GRUB defaults (Fixing the VG name to 'centos')
cat <<EOF > /mnt/sysimage/etc/default/grub
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="\$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="console=tty1 debug loglevel=7 systemd.show_status=true crashkernel=auto resume=/dev/mapper/centos-swap rd.lvm.lv=centos/root rd.lvm.lv=centos/swap"
GRUB_DISABLE_RECOVERY="true"
EOF

# 2. Use grubby (It is safer and won't hang like mkconfig)
chroot /mnt/sysimage /usr/sbin/grubby --update-kernel=ALL --remove-args="rhgb quiet"
chroot /mnt/sysimage /usr/sbin/grubby --update-kernel=ALL --args="debug loglevel=7 systemd.show_status=true console=tty1"

# 3. Disable Plymouth
chroot /mnt/sysimage /usr/bin/systemctl mask plymouth-start.service

# 4. Correct GRUB update (Canonical CentOS 7 paths)
chroot /mnt/sysimage /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg
chroot /mnt/sysimage /usr/sbin/dracut -f

# Verify primary ESP filesystem is mounted cleanly before parsing it
if ! mountpoint -q /mnt/sysimage/boot/efi; then
    echo "CRITICAL ERROR: Primary ESP filesystem (/boot/efi) is not mounted!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

echo "Setting up proper UEFI Redundancy on /dev/sdb1..."
TARGET_MNT="/mnt/sysimage/boot/efi2"
mkdir -p "$TARGET_MNT"

cleanup() {
    echo "Executing filesystem mount safety cleanup sequence..."
    mountpoint -q "$TARGET_MNT" && umount "$TARGET_MNT"
    mountpoint -q "/mnt/sysimage/sys/firmware/efi/efivars" && umount "/mnt/sysimage/sys/firmware/efi/efivars"
    rmdir "$TARGET_MNT" 2>/dev/null || true
}
trap cleanup EXIT

# Ensure /dev/sdb1 has a clean FAT32 layout
if ! blkid /dev/sdb1 | grep -q "vfat"; then
    mkfs.vfat -F 32 -n "EFI-SDB" /dev/sdb1
fi

if ! mount /dev/sdb1 "$TARGET_MNT"; then
    echo "CRITICAL ERROR: Failed to mount secondary ESP storage /dev/sdb1" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

if ! mountpoint -q "$TARGET_MNT"; then
    echo "CRITICAL ERROR: Target mountpoint validation check failed!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Verify physical EFI execution variables are exposed before writing to motherboard NVRAM
if [ -d /sys/firmware/efi/efivars ]; then
    mkdir -p /mnt/sysimage/sys/firmware/efi/efivars
    mount --bind /sys/firmware/efi/efivars /mnt/sysimage/sys/firmware/efi/efivars || true
fi

mkdir -p /mnt/sysimage/boot/efi2

# Run grub2-install into chroot context pointing to the valid internal efi2 path boundary
if ! chroot /mnt/sysimage /usr/sbin/grub2-install --target=x86_64-efi --efi-directory=/boot/efi2 --bootloader-id=centos --recheck; then
    echo "CRITICAL ERROR: grub2-install execution on secondary ESP failed!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Double check that the target output layout binary was built
if [ ! -f "$TARGET_MNT/EFI/centos/grubx64.efi" ]; then
    echo "CRITICAL ERROR: grub2-install completed but output binary is missing on secondary partition!" >> /mnt/sysimage/root/ks-post-errors.log
    exit 1
fi

# Re-map standard fallback structures
mkdir -p /mnt/sysimage/boot/efi/EFI/BOOT
mkdir -p "$TARGET_MNT/EFI/BOOT"

# Safe Secure Boot vs Non-Secure Boot identification
if [ -f /mnt/sysimage/boot/efi/EFI/centos/shimx64.efi ]; then
    echo "Secure Boot chain detected. Synchronizing matching shims..."
    cp /mnt/sysimage/boot/efi/EFI/centos/shimx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI
    cp /mnt/sysimage/boot/efi/EFI/centos/grubx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/grubx64.efi
    
    cp "$TARGET_MNT/EFI/centos/shimx64.efi" "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI"
    cp "$TARGET_MNT/EFI/centos/grubx64.efi" "$TARGET_MNT/EFI/BOOT/grubx64.efi"
    BOOT_TARGET="shimx64.efi"
else
    echo "Standard system configurations detected. Generating raw binary fallback entries..."
    cp /mnt/sysimage/boot/efi/EFI/centos/grubx64.efi /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI
    cp "$TARGET_MNT/EFI/centos/grubx64.efi" "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI"
    BOOT_TARGET="grubx64.efi"
fi

if [ -f /mnt/sysimage/boot/efi/EFI/centos/BOOTX64.CSV ]; then
    cp /mnt/sysimage/boot/efi/EFI/centos/BOOTX64.CSV "$TARGET_MNT/EFI/centos/BOOTX64.CSV"
fi

# Forward second stub directly to primary configuration space /boot/grub2/grub.cfg
chroot /mnt/sysimage /usr/sbin/grub2-mkconfig -o /boot/efi2/EFI/centos/grub.cfg

# Register alternative paths cleanly inside hardware boot entries list
if [ -d /sys/firmware/efi/efivars ]; then
    echo "Registering alternative secondary paths inside hardware NVRAM..."
    if ! efibootmgr -c -d /dev/sdb -p 1 -L "CentOS Backup Boot (sdb)" -l "\\EFI\\centos\\${BOOT_TARGET}"; then
        echo "NOTICE: NVRAM entry dropped or un-writable in installer context. Falling back cleanly to BOOTX64.EFI." >> /mnt/sysimage/root/ks-post-errors.log
    fi
fi

# Run target verification loop pipelines
echo "=== STORAGE ENVIRONMENT LAYER AUDIT ===" >> /mnt/sysimage/root/storage_validation.log
lsblk -o NAME,FSTYPE,MOUNTPOINT,SIZE >> /mnt/sysimage/root/storage_validation.log

if [ ! -f /mnt/sysimage/boot/efi/EFI/BOOT/BOOTX64.EFI ]; then
    echo "ERROR: Target fallback executable is missing from sda1!" >> /mnt/sysimage/root/ks-post-errors.log
fi

if [ ! -f "$TARGET_MNT/EFI/BOOT/BOOTX64.EFI" ]; then
    echo "ERROR: Target fallback executable is missing from sdb1!" >> /mnt/sysimage/root/ks-post-errors.log
fi

echo "=== VOLUME GROUP & METADATA VERIFICATION ===" >> /mnt/sysimage/root/storage_validation.log
cat /proc/mdstat >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage pvs >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage vgs >> /mnt/sysimage/root/storage_validation.log
chroot /mnt/sysimage lvs >> /mnt/sysimage/root/storage_validation.log

cleanup
trap - EXIT

# Deploy standalone runtime sync-esp tracking script inside the OS filesystem
cat << 'EOF' > /mnt/sysimage/usr/local/sbin/sync-esp.sh
#!/bin/bash
set -e
if [ -d /boot/efi/EFI/centos ] && [ -b /dev/sdb1 ]; then
    TMP_SYNC=$(mktemp -d)
    if mount /dev/sdb1 "$TMP_SYNC"; then
        mkdir -p "$TMP_SYNC/EFI/centos"
        mkdir -p "$TMP_SYNC/EFI/BOOT"
        rsync -a --delete /boot/efi/EFI/centos/ "$TMP_SYNC/EFI/centos/"
        rsync -a --delete /boot/efi/EFI/BOOT/ "$TMP_SYNC/EFI/BOOT/"
        if [ -f /boot/efi/EFI/centos/shimx64.efi ]; then
            cp /boot/efi/EFI/centos/shimx64.efi "$TMP_SYNC/EFI/BOOT/BOOTX64.EFI"
        else
            cp /boot/efi/EFI/centos/grubx64.efi "$TMP_SYNC/EFI/BOOT/BOOTX64.EFI"
        fi
        umount "$TMP_SYNC"
    fi
    rm -rf "$TMP_SYNC"
fi
EOF
chmod +x /mnt/sysimage/usr/local/sbin/sync-esp.sh

# Deploy persistent background systemd synchronization service to map kernel updates on CentOS 7
cat << 'EOF' > /mnt/sysimage/etc/systemd/system/sync-esp.service
[Unit]
Description=CentOS 7 Persistent ESP Synchronizer Engine
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sync-esp.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

chroot /mnt/sysimage /usr/bin/systemctl daemon-reload
chroot /mnt/sysimage /usr/bin/systemctl enable sync-esp.service

echo "Verbose boot configuration completed."
%end

# Reboot after installation
reboot
```
