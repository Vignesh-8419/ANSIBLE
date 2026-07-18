#!/bin/bash
set -e

echo "Configuring verbose boot..."

grubby --update-kernel=ALL \
    --remove-args="rhgb quiet loglevel systemd.show_status console"

grubby --update-kernel=ALL \
    --args="loglevel=5 systemd.show_status=true console=ttyS0,9600 console=tty0"

echo
echo "Current kernel arguments:"
grubby --info=DEFAULT | grep '^args='

echo
echo "Done. Reboot to apply changes."
