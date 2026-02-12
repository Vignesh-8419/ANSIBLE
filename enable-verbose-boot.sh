#!/bin/bash
# setup_grub.sh

# 1. Configure /etc/default/grub
# We define the order strictly here: tty1 first, ttyS0 LAST.
cat <<EOF > /etc/default/grub
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=9600 --unit=0 --word=8 --parity=no --stop=1"
GRUB_CMDLINE_LINUX="rd.lvm.lv=rl/root rd.lvm.lv=rl/swap resume=/dev/mapper/rl-swap loglevel=7 systemd.show_status=true console=tty1 console=ttyS0,9600"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
EOF

echo "Cleaning up old console arguments and setting ttyS0 as primary..."

# 2. Critical Step: Remove ALL existing console/quiet/rhgb arguments first
# This prevents 'console=tty1' from appearing after 'ttyS0' in the final boot string.
grubby --update-kernel=ALL --remove-args="rhgb quiet console"

# 3. Re-add them in the specific order: tty1 then ttyS0
grubby --update-kernel=ALL --args="loglevel=7 systemd.show_status=true console=tty1 console=ttyS0,9600"

# 4. Disable graphical splash
systemctl mask plymouth-start.service 2>/dev/null

# 5. Build final GRUB configuration
if [ -d /sys/firmware/efi ]; then
    TARGET=$(find /boot/efi/EFI -name grub.cfg | grep -E 'rocky|centos|redhat' | head -n 1)
else
    TARGET="/boot/grub2/grub.cfg"
fi

if [ -n "$TARGET" ]; then
    echo "Regenerating GRUB at $TARGET..."
    grub2-mkconfig -o "$TARGET"
else
    echo "Error: Could not find grub.cfg."
    exit 1
fi

echo "Done. Please reboot and check your PuTTY window (Port 2001)."
