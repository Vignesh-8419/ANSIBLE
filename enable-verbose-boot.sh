#!/bin/bash
# setup_grub.sh

# 1. Configure /etc/default/grub
cat <<EOF > /etc/default/grub
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=9600 --unit=0 --word=8 --parity=no --stop=1"
# IMPORTANT: ttyS0 is LAST so it gets the [ OK ] messages
GRUB_CMDLINE_LINUX="rd.lvm.lv=rl/root rd.lvm.lv=rl/swap resume=/dev/mapper/rl-swap loglevel=7 systemd.show_status=true console=tty1 console=ttyS0,9600"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
EOF

# 2. Apply to all kernels using grubby
# We force remove all 'console' entries first to prevent duplicates
grubby --update-kernel=ALL --remove-args="rhgb quiet console"
# We re-add them with ttyS0 at the very end
grubby --update-kernel=ALL --args="loglevel=7 systemd.show_status=true console=tty1 console=ttyS0,9600"

# 3. Regenerate the GRUB config
if [ -d /sys/firmware/efi ]; then
    TARGET=$(find /boot/efi/EFI -name grub.cfg | grep -E 'rocky|centos|redhat' | head -n 1)
else
    TARGET="/boot/grub2/grub.cfg"
fi

grub2-mkconfig -o "$TARGET"
