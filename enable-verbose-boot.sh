#!/bin/bash
# setup_grub_dual_verbose.sh

set -e

echo "Configuring GRUB for maximum boot verbosity..."

# -----------------------------------------------------------------------------
# Capture existing kernel parameters
# -----------------------------------------------------------------------------

LVM_VARS=$(grep -o "rd.lvm.lv=[^ ]*" /proc/cmdline | tr '\n' ' ')
RESUME_VAR=$(grep -o "resume=[^ ]*" /proc/cmdline)

echo "Detected:"
echo "  LVM   : $LVM_VARS"
echo "  Resume: $RESUME_VAR"

# -----------------------------------------------------------------------------
# Write /etc/default/grub
# -----------------------------------------------------------------------------

cat <<EOF >/etc/default/grub
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="\$(sed 's, release .*\$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=9600 --unit=0 --word=8 --parity=no --stop=1"
GRUB_CMDLINE_LINUX="$LVM_VARS $RESUME_VAR loglevel=7 ignore_loglevel systemd.show_status=true systemd.log_level=debug systemd.log_target=console udev.log_level=debug console=ttyS0,9600 console=tty0"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
EOF

echo "Updated /etc/default/grub"

# -----------------------------------------------------------------------------
# Remove quiet boot options
# -----------------------------------------------------------------------------

echo "Removing rhgb, quiet and existing console options..."

grubby --update-kernel=ALL \
    --remove-args="rhgb quiet console loglevel systemd.show_status ignore_loglevel systemd.log_level systemd.log_target udev.log_level"

# -----------------------------------------------------------------------------
# Apply verbose kernel arguments
# -----------------------------------------------------------------------------

echo "Applying verbose kernel arguments..."

grubby --update-kernel=ALL \
    --args="loglevel=7 ignore_loglevel systemd.show_status=true systemd.log_level=debug systemd.log_target=console udev.log_level=debug console=ttyS0,9600 console=tty0"

# -----------------------------------------------------------------------------
# Rebuild GRUB
# -----------------------------------------------------------------------------

if [ -d /sys/firmware/efi ]; then
    TARGET=$(find /boot/efi/EFI -name grub.cfg | grep -E 'rocky|redhat|centos' | head -n1)
else
    TARGET="/boot/grub2/grub.cfg"
fi

echo "Generating $TARGET"

grub2-mkconfig -o "$TARGET"

echo
echo "========================================================"
echo "Current Kernel Arguments:"
grubby --info=DEFAULT | grep args
echo "========================================================"
echo
echo "Reboot the server to see verbose boot messages."
