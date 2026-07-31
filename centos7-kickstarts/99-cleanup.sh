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
mdadm --detail --scan >/etc/mdadm.conf


################################################################################
# Make EFI Mount Non-Fatal
################################################################################

echo
echo "Configuring EFI mount as optional..."

cp -an /etc/fstab /etc/fstab.backup

if grep -qE '[[:space:]]/boot/efi[[:space:]]' /etc/fstab; then

    sed -i \
        -e '/[[:space:]]\/boot\/efi[[:space:]]/ s/,nofail//g' \
        -e '/[[:space:]]\/boot\/efi[[:space:]]/ s/,x-systemd.device-timeout=[^, ]*//g' \
        -e '/[[:space:]]\/boot\/efi[[:space:]]/ s/defaults/defaults,nofail,x-systemd.device-timeout=1/' \
        /etc/fstab

fi

echo
echo "Updated EFI entry:"
grep '/boot/efi' /etc/fstab || echo "No /boot/efi entry present (expected)."

################################################################################
# Rebuild GRUB Configuration (CentOS Path Shift Fixed)
################################################################################
echo "Updating GRUB configuration..."
if [ -d /boot/efi/EFI/centos ]; then
    grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
fi

################################################################################
# Remove Temporary Files
################################################################################
echo "Cleaning temporary files..."
rm -rf /var/tmp/*
find /tmp -mindepth 1 -delete || true

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
truncate -s 0 /etc/machine-id || true
if [ -f /var/lib/dbus/machine-id ]; then
    rm -f /var/lib/dbus/machine-id
    ln -sf /etc/machine-id /var/lib/dbus/machine-id
fi

################################################################################
# Remove Random Seed
################################################################################
rm -f /var/lib/systemd/random-seed

################################################################################
# Remove Persistent Network Rules (CentOS 7 Legacy Interface Anchor Protection)
###############################################################################
rm -f /etc/udev/rules.d/70-persistent-net.rules
rm -f /etc/udev/rules.d/70-persistent-ipoib.rules

################################################################################
# Remove Old Crash Dumps
################################################################################
rm -rf /var/crash/*

################################################################################
# Clean Logs Safely
################################################################################
echo "Sanitizing system transaction log blocks..."
find /var/log -type f ! -name "99-cleanup.log" ! -name "50-grub.log" ! -name "30-postinstall.log" ! -name "anaconda-post.log" -exec truncate -s 0 {} \;

################################################################################
# Clean Package Engine Caches (CentOS 7 Yum and DNF Parallel Protection)
################################################################################
echo "Purging package transaction metadata stores..."
yum clean all || true
if command -v dnf >/dev/null 2>&1; then dnf clean all || true; fi
rm -rf /var/cache/yum/* /var/cache/dnf/*

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
