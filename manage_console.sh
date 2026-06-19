#!/bin/bash

ACTION=$1  # Accept 'enable' or 'disable'

# 1. Extract current working LVM/Root parameters
# This strips existing console settings to prevent duplication
PARAMS=$(cat /proc/cmdline | sed 's/BOOT_IMAGE=[^ ]* //; s/console=ttyS0,[0-9]*//g; s/console=tty0//g' | awk '{$1=$1;print}')

if [ "$ACTION" == "enable" ]; then
    echo "Enabling Serial Console..."
    NEW_CMDLINE="GRUB_CMDLINE_LINUX=\"$PARAMS console=tty0 console=ttyS0,115200 rhgb quiet\""
    
    sed -i '/GRUB_TERMINAL/d' /etc/default/grub
    sed -i '/GRUB_SERIAL_COMMAND/d' /etc/default/grub
    sed -i '/GRUB_CMDLINE_LINUX=/d' /etc/default/grub
    
    echo "$NEW_CMDLINE" >> /etc/default/grub
    echo 'GRUB_TERMINAL="serial console"' >> /etc/default/grub
    echo 'GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"' >> /etc/default/grub

elif [ "$ACTION" == "disable" ]; then
    echo "Disabling Serial Console (Standard Video Only)..."
    NEW_CMDLINE="GRUB_CMDLINE_LINUX=\"$PARAMS rhgb quiet\""
    
    sed -i '/GRUB_TERMINAL/d' /etc/default/grub
    sed -i '/GRUB_SERIAL_COMMAND/d' /etc/default/grub
    sed -i '/GRUB_CMDLINE_LINUX=/d' /etc/default/grub
    
    echo "$NEW_CMDLINE" >> /etc/default/grub
    echo 'GRUB_TERMINAL_OUTPUT="console"' >> /etc/default/grub
else
    echo "Usage: $0 [enable|disable]"
    exit 1
fi

# 2. Detect OS and Regenerate
if [ -f /boot/efi/EFI/rocky/grub.cfg ]; then TARGET="/boot/efi/EFI/rocky/grub.cfg"
elif [ -f /boot/efi/EFI/centos/grub.cfg ]; then TARGET="/boot/efi/EFI/centos/grub.cfg"
else TARGET="/boot/grub2/grub.cfg"; fi

grub2-mkconfig -o "$TARGET"
echo "Done. Changes applied to $TARGET."
