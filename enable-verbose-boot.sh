#!/bin/bash
#
# setup_grub_dual_safe.sh
#

set -euo pipefail

echo "=========================================================="
echo " Safe GRUB Console Configuration"
echo "=========================================================="

#
# Update existing kernel entries
#

grubby --update-kernel=ALL \
  --remove-args="rhgb quiet \
                 ignore_loglevel \
                 systemd.log_level \
                 systemd.log_target \
                 udev.log_level \
                 loglevel \
                 systemd.show_status \
                 console"

grubby --update-kernel=ALL \
  --args="loglevel=5 systemd.show_status=true console=ttyS0,9600 console=tty0"

#
# Update /etc/default/grub without removing existing arguments
#

CURRENT=$(grep '^GRUB_CMDLINE_LINUX=' /etc/default/grub | cut -d'"' -f2)

NEW="$CURRENT"

for ARG in \
    rhgb \
    quiet \
    ignore_loglevel \
    systemd.log_level=debug \
    systemd.log_target=console \
    udev.log_level=debug
do
    NEW=$(echo "$NEW" | sed "s#${ARG}##g")
done

NEW=$(echo "$NEW" \
    | sed -E \
        -e 's/loglevel=[^ ]*//g' \
        -e 's/systemd\.show_status=[^ ]*//g' \
        -e 's/console=[^ ]*//g' \
        | xargs)

NEW="$NEW loglevel=5 systemd.show_status=true console=ttyS0,9600 console=tty0"

sed -i \
"s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$NEW\"|" \
/etc/default/grub

#
# Regenerate grub.cfg
#

if [ -d /sys/firmware/efi ]; then
    TARGET=$(find /boot/efi/EFI -name grub.cfg | head -1)
else
    TARGET="/boot/grub2/grub.cfg"
fi

echo
echo "Generating $TARGET"

grub2-mkconfig -o "$TARGET"

echo
echo "=========================================================="
echo "Kernel command line:"
grubby --info=DEFAULT | grep '^args='
echo "=========================================================="

echo
echo "/etc/default/grub:"
grep '^GRUB_CMDLINE_LINUX' /etc/default/grub

echo
echo "Completed successfully."
