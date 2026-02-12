#!/bin/bash
# setup_grub_final.sh

echo "Starting Serial Console and Verbose Boot Configuration..."

# 1. Capture current LVM and Resume arguments to ensure the system remains bootable
LVM_VARS=$(grep -o "rd.lvm.lv=[^ ]*" /proc/cmdline | tr '\n' ' ')
RESUME_VAR=$(grep -o "resume=[^ ]*" /proc/cmdline)

# 2. Re-create /etc/default/grub with strict ordering
# console=ttyS0 MUST be the very last argument for [ OK ] messages to show in PuTTY
cat <<EOF > /etc/default/grub
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Rocky Linux"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=9600 --unit=0 --word=8 --parity=no --stop=1"
GRUB_CMDLINE_LINUX="$LVM_VARS $RESUME_VAR loglevel=7 systemd.show_status=true console=tty1 console=ttyS0,9600"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
EOF

echo "Synchronizing kernel boot entries using grubby..."

# 3. Clean up ALL existing console, quiet, and splash arguments
# This prevents 'console=tty1' from accidentally being appended at the end
grubby --update-kernel=ALL --remove-args="rhgb quiet console"

# 4. Apply the new verbose and serial arguments
# Placing console=ttyS0,9600 last is what enables the [ OK ] status logs in PuTTY
grubby --update-kernel=ALL --args="loglevel=7 systemd.show_status=true console=tty1 console=ttyS0,9600"

# 5. Disable the graphical boot splash (Plymouth) which can interfere with serial output
systemctl mask plymouth-start.service 2>/dev/null

# 6. Regenerate the GRUB configuration file
if [ -d /sys/firmware/efi ]; then
    # Handles Rocky, CentOS, and RHEL EFI paths
    TARGET=$(find /boot/efi/EFI -name grub.cfg | grep -E 'rocky|centos|redhat' | head -n 1)
else
    TARGET="/boot/grub2/grub.cfg"
fi

if [ -n "$TARGET" ]; then
    echo "Regenerating GRUB config at $TARGET..."
    grub2-mkconfig -o "$TARGET"
else
    echo "ERROR: Could not find grub.cfg location!"
    exit 1
fi

echo "----------------------------------------------------------------"
echo "DONE! Please follow these final steps before rebooting:"
echo "1. In vSphere, ensure Serial Port 1 is 'Connected'."
echo "2. Open PuTTY to ESXi Host IP on Port 2001 (Connection: Telnet)."
echo "3. Reboot the VM."
echo "----------------------------------------------------------------"
