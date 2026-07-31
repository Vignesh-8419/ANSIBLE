#!/bin/bash
#==============================================================================
# 99-cleanup.sh
#
# CentOS 7 Golden Image
# Post-Build Deployment Sanitization & Generalization Matrix
#==============================================================================

set -euo pipefail

LOG=/root/99-cleanup.log
exec > >(tee -a "$LOG") 2>&1

echo
echo "========================================================"
echo "CentOS Golden Image Cleanup"
echo "========================================================"

################################################################################
# Save RAID Configuration
################################################################################
echo
echo "Saving mdadm configuration..."
mkdir -p /etc/mdadm
mdadm --detail --scan > /etc/mdadm.conf

################################################################################
# Remove EFI Entry From fstab
################################################################################

echo
echo "Removing EFI entry from /etc/fstab..."

cp -an /etc/fstab /etc/fstab.backup

# Remove any EFI (vfat) entry regardless of mount point
sed -i '/^[^#].*[[:space:]]vfat[[:space:]].*umask=0077/d' /etc/fstab

systemctl daemon-reload || true

echo
echo "Current /etc/fstab:"
cat /etc/fstab

################################################################################
# Rebuild GRUB Configuration
################################################################################
echo
echo "Updating GRUB configuration..."

if mountpoint -q /boot/efi && [ -d /boot/efi/EFI/centos ]; then
    grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
elif [ -f /boot/grub2/grub.cfg ]; then
    grub2-mkconfig -o /boot/grub2/grub.cfg
fi

################################################################################
# Remove Temporary Files
################################################################################
echo
echo "Cleaning temporary files..."
rm -rf /var/tmp/*
find /tmp -mindepth 1 -delete || true

################################################################################
# Clear Bash History
################################################################################
echo
echo "Clearing terminal command histories..."
history -c || true
history -w || true
rm -f /root/.bash_history

################################################################################
# Remove SSH Host Keys
################################################################################
echo
echo "Stripping local cryptographic host key pairs..."
rm -f /etc/ssh/ssh_host_*

################################################################################
# Reset Machine ID
################################################################################
echo
echo "Generalizing platform machine identifier signatures..."
truncate -s 0 /etc/machine-id || true

if [ -f /var/lib/dbus/machine-id ]; then
    rm -f /var/lib/dbus/machine-id
    ln -sf /etc/machine-id /var/lib/dbus/machine-id
fi

################################################################################
# Remove Random Seed
################################################################################
echo
echo "Removing system random seed..."
rm -f /var/lib/systemd/random-seed

################################################################################
# Remove Persistent Network Rules
################################################################################
echo
echo "Removing persistent network rules..."
rm -f /etc/udev/rules.d/70-persistent-net.rules
rm -f /etc/udev/rules.d/70-persistent-ipoib.rules

################################################################################
# Remove Old Crash Dumps
################################################################################
echo
echo "Removing crash dumps..."
rm -rf /var/crash/*

################################################################################
# Clean Logs Safely
################################################################################
echo
echo "Sanitizing system transaction log blocks..."

find /var/log -type f \
    ! -name "99-cleanup.log" \
    ! -name "50-grub.log" \
    ! -name "30-postinstall.log" \
    ! -name "anaconda-post.log" \
    -exec truncate -s 0 {} \;

################################################################################
# Clean Package Engine Caches
################################################################################
echo
echo "Purging package transaction metadata stores..."

yum clean all || true

if command -v dnf >/dev/null 2>&1; then
    dnf clean all || true
fi

rm -rf /var/cache/yum/*
rm -rf /var/cache/dnf/*

################################################################################
# Sync Filesystems
################################################################################
echo
echo "Flushing filesystem buffers..."
sync

################################################################################
# Display Final Status
################################################################################
echo
echo "========================================================"
echo "Final RAID Status"
echo "========================================================"
cat /proc/mdstat

echo
echo "========================================================"
echo "LVM"
echo "========================================================"
pvs && echo
vgs && echo
lvs

echo
echo "========================================================"
echo "EFI Entries"
echo "========================================================"
efibootmgr -v || true

echo
echo "========================================================"
echo "Block Devices"
echo "========================================================"
lsblk

echo
echo "========================================================"
echo "Cleanup Completed Successfully"
echo "========================================================"

exit 0
