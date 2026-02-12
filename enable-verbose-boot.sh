#!/bin/bash
# setup_grub.sh

# 1. Grab current LVM/Resume settings to maintain boot stability
LVM_VARS=$(grep -o "rd.lvm.lv=[^ ]*" /proc/cmdline | tr '\n' ' ')
RESUME_VAR=$(grep -o "resume=[^ ]*" /proc/cmdline)

# 2. Configure /etc/default/grub
cat <<EOF > /etc/default/grub
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=9600 --unit=0 --word=8 --parity=no --stop=1"
# We put ttyS0 LAST so it becomes the 'primary' console for systemd status
GRUB_CMDLINE_LINUX="rd.lvm.lv=rl/root rd.lvm.lv=rl/swap resume=/dev/mapper/rl-swap loglevel=7 systemd.show_status=true console=tty1 console=ttyS0,9600"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
EOF

echo "Updating GRUB defaults..."

# 3. Apply to all kernels
# We must include BOTH consoles here as well
grubby --update-kernel=ALL --remove-args="rhgb quiet console"
grubby --update-kernel=ALL --args="loglevel=7 systemd.show_status=true console=tty1 console=ttyS0,9600"

# 4. Disable the graphical splash screen to prevent it from hiding logs
systemctl mask plymouth-start.service 2>/dev/null

# 5. Build the final GRUB configuration
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

echo "Done. On reboot, you will see dmesg followed by [ OK ] status on your serial console."
