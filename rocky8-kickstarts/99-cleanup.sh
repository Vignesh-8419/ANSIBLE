#!/bin/bash
#==============================================================================
# 99-cleanup.sh
#
# Rocky Linux 8.10 Golden Image
# Post-Build Deployment Sanitization & Generalization Matrix
#==============================================================================

set -euo pipefail

LOG=/root/99-cleanup.log
exec > >(tee -a "$LOG") 2>&1

echo
echo "========================================================"
echo "Golden Image Cleanup"
echo "========================================================"

################################################################################
# Save RAID Configuration
################################################################################
echo
echo "Saving mdadm configuration..."
mkdir -p /etc/mdadm
mdadm --detail --scan >/etc/mdadm.conf

################################################################################
# Rebuild initramfs
################################################################################
echo
echo "Rebuilding initramfs..."
dracut -f --regenerate-all

################################################################################
# Rebuild GRUB Configuration
################################################################################
echo
echo "Updating GRUB configuration..."
# Fixed: UEFI systems must update the active layout under the EFI directory hierarchy
if [ -d /boot/efi/EFI/rocky ]; then
    grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg
fi

################################################################################
# Remove Installer Logs
################################################################################
echo "Removing intermediate installer artifacts..."
rm -rf /root/anaconda*
rm -rf /tmp/*
rm -rf /var/tmp/*

################################################################################
# Clear Bash History
################################################################################
echo "Clearing terminal command histories..."
history -c || true
history -w || true
rm -f /root/.bash_history

################################################################################
# Remove SSH Host Keys
################################################################################
echo "Stripping local cryptographic host key pairs..."
rm -f /etc/ssh/ssh_host_*

################################################################################
# Reset Machine ID
################################################################################
echo "Generalizing platform machine identifier signatures..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

################################################################################
# Remove Random Seed
################################################################################
rm -f /var/lib/systemd/random-seed

################################################################################
# Remove Persistent Network Rules
################################################################################
rm -f /etc/udev/rules.d/70-persistent-net.rules

################################################################################
# Remove Old Crash Dumps
################################################################################
rm -rf /var/crash/*

################################################################################
# Clean Logs Safely
################################################################################
echo "Sanitizing system transaction log blocks..."
# Fixed: Exclude running orchestration log streams to prevent terminal pipe breaks
find /var/log -type f ! -name "99-cleanup.log" ! -name "50-grub.log" ! -name "30-postinstall.log" ! -name "anaconda-post.log" -exec truncate -s 0 {} \;

################################################################################
# Clean DNF
################################################################################
echo "Purging package transaction metadata stores..."
dnf clean all
rm -rf /var/cache/dnf/*

################################################################################
# Sync Filesystems
################################################################################
echo "Flushing file system buffer caches to underlying block storage..."
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
