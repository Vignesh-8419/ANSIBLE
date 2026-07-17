#!/bin/bash
#
# setup_grub_dual_console.sh
#

set -e

echo "=========================================================="
echo " Configuring GRUB (Safe Mode)"
echo "=========================================================="

#
# Remove only unwanted options
#

grubby --update-kernel=ALL \
    --remove-args="rhgb quiet loglevel systemd.show_status console"

#
# Add required options
#

grubby --update-kernel=ALL \
    --args="loglevel=6 systemd.show_status=true console=ttyS0,9600 console=tty0"

#
# Update /etc/default/grub only for future kernels
#

CURRENT_CMDLINE=$(grep '^GRUB_CMDLINE_LINUX=' /etc/default/grub \
    | cut -d'"' -f2)

NEW_CMDLINE=$(echo "$CURRENT_CMDLINE" \
    | sed -E \
      -e 's/\<rhgb\>//g' \
      -e 's/\<quiet\>//g' \
      -e 's/loglevel=[^ ]*//g' \
      -e 's/systemd\.show_status=[^ ]*//g' \
      -e 's/console=[^ ]*//g' \
      | xargs)

NEW_CMDLINE="$NEW_CMDLINE loglevel=6 systemd.show_status=true console=ttyS0,9600 console=tty0"

sed -i \
    "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$NEW_CMDLINE\"|" \
    /etc/default/grub

#
# Rebuild grub.cfg
#

if [ -d /sys/firmware/efi ]; then
    TARGET=$(find /boot/efi/EFI -name grub.cfg | grep -E 'rocky|redhat|centos' | head -n1)
else
    TARGET="/boot/grub2/grub.cfg"
fi

grub2-mkconfig -o "$TARGET"

echo
echo "Current kernel args:"
grubby --info=DEFAULT | grep '^args='

echo
echo "Done."
