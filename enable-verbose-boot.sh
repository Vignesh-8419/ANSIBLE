#!/bin/bash
# setup_grub_dual.sh

set -e

echo "========================================================"
echo " Configuring GRUB for Dual Console (Moderate Verbosity)"
echo "========================================================"

# -----------------------------------------------------------------------------
# Capture current LVM and Resume arguments
# -----------------------------------------------------------------------------

LVM_VARS=$(grep -o "rd.lvm.lv=[^ ]*" /proc/cmdline | tr '\n' ' ')
RESUME_VAR=$(grep -o "resume=[^ ]*" /proc/cmdline)

echo "Detected kernel parameters:"
echo "  LVM    : $LVM_VARS"
echo "  Resume : $RESUME_VAR"

# -----------------------------------------------------------------------------
# Configure /etc/default/grub
# -----------------------------------------------------------------------------

cat <<EOF >/etc/default/grub
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="\$(sed 's, release .*\$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=9600 --unit=0 --word=8 --parity=no --stop=1"
GRUB_CMDLINE_LINUX="$LVM_VARS $RESUME_VAR loglevel=6 systemd.show_status=true console=ttyS0,9600 console=tty0"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
EOF

echo "[OK] Updated /etc/default/grub"

# -----------------------------------------------------------------------------
# Remove unwanted kernel arguments
# -----------------------------------------------------------------------------

echo "Removing old kernel arguments..."

grubby --update-kernel=ALL \
    --remove-args="rhgb quiet console loglevel systemd.show_status"

# -----------------------------------------------------------------------------
# Apply new kernel arguments
# -----------------------------------------------------------------------------

echo "Applying new kernel arguments..."

grubby --update-kernel=ALL \
    --args="loglevel=6 systemd.show_status=true console=ttyS0,9600 console=tty0"

# -----------------------------------------------------------------------------
# Rebuild GRUB configuration
# -----------------------------------------------------------------------------

if [ -d /sys/firmware/efi ]; then
    TARGET=$(find /boot/efi/EFI -name grub.cfg | grep -E 'rocky|redhat|centos' | head -n1)
else
    TARGET="/boot/grub2/grub.cfg"
fi

echo "Generating GRUB configuration..."
grub2-mkconfig -o "$TARGET"

echo
echo "========================================================"
echo "Current Default Kernel Arguments"
echo "========================================================"
grubby --info=DEFAULT | grep "^args="

echo
echo "========================================================"
echo "Configuration completed successfully."
echo
echo "Boot configuration:"
echo "  • VMware Console : Enabled (Primary)"
echo "  • Serial Console : ttyS0 @ 9600"
echo "  • Kernel Log Level: 6 (Informational)"
echo "  • Systemd Status : Enabled"
echo "========================================================"
echo
echo "Please reboot the system to apply the changes."
