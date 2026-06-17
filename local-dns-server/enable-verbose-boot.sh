#!/bin/bash
# setup_grub_dual.sh

# 1. Capture current LVM and Resume arguments
LVM_VARS=$(grep -o "rd.lvm.lv=[^ ]*" /proc/cmdline | tr '\n' ' ')
RESUME_VAR=$(grep -o "resume=[^ ]*" /proc/cmdline)

# 2. Configure /etc/default/grub
# NOTICE: We put console=tty0 LAST. 
# This makes the VMware screen the "Primary" but still sends output to ttyS0.
cat <<EOF > /etc/default/grub
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

# 3. Clean and Update Kernel Entries
grubby --update-kernel=ALL --remove-args="rhgb quiet console"

# 4. Apply Dual Console arguments
# Again, tty0 is last to ensure the local VM screen always works
grubby --update-kernel=ALL --args="loglevel=7 systemd.show_status=true console=ttyS0,9600 console=tty0"

# 5. Build final GRUB configuration
if [ -d /sys/firmware/efi ]; then
    TARGET=$(find /boot/efi/EFI -name grub.cfg | grep -E 'rocky|centos|redhat' | head -n 1)
else
    TARGET="/boot/grub2/grub.cfg"
fi

grub2-mkconfig -o "$TARGET"

echo "Done. Order set to ttyS0 then tty0 (Primary)."
