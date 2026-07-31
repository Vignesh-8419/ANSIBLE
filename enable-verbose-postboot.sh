#!/bin/bash
#==============================================================================
# enable-verbose-boot.sh
#
# Universal EL7/EL8/EL9 Verbose Boot Configuration
# Supports:
#   - CentOS 7
#   - Rocky Linux 8/9
#   - AlmaLinux
#   - Oracle Linux
#   - RHEL
#
# Works even when /boot/efi is NOT present in /etc/fstab
#==============================================================================

set -euo pipefail

echo
echo "========================================================"
echo "Enable Verbose Boot"
echo "========================================================"

###############################################################################
# Configure kernel arguments
###############################################################################

echo
echo "Updating kernel arguments..."

grubby --update-kernel=ALL \
    --remove-args="rhgb quiet loglevel systemd.show_status console=tty0 console=ttyS0,9600 console" || true

grubby --update-kernel=ALL \
    --args="loglevel=5 systemd.show_status=true console=ttyS0,9600 console=tty0"

###############################################################################
# Detect UEFI or BIOS
###############################################################################

if [ -d /sys/firmware/efi ]; then

    echo
    echo "UEFI system detected."

    mkdir -p /boot/efi

    EFI_MOUNTED_BY_SCRIPT=0

    if ! mountpoint -q /boot/efi; then

        EFI_DEV=""

        for dev in $(blkid -t TYPE=vfat -o device); do

            mount "$dev" /boot/efi 2>/dev/null || continue

            if [ -d /boot/efi/EFI ]; then
                EFI_DEV="$dev"
                EFI_MOUNTED_BY_SCRIPT=1
                break
            fi

            umount /boot/efi

        done

        if [ -z "$EFI_DEV" ]; then
            echo "ERROR: Unable to locate EFI System Partition."
            exit 1
        fi
    fi

    EFI_DIR=""

    for d in /boot/efi/EFI/*; do
        [ -d "$d" ] || continue

        case "$(basename "$d")" in
            BOOT)
                ;;
            *)
                if [ -f "$d/grub.cfg" ]; then
                    EFI_DIR="$d"
                    break
                fi
                ;;
        esac
    done

    if [ -z "$EFI_DIR" ]; then
        echo "ERROR: Unable to locate EFI bootloader directory."
        exit 1
    fi

    echo
    echo "Using EFI directory:"
    echo "$EFI_DIR"

    grub2-mkconfig -o "$EFI_DIR/grub.cfg"

    if [ "$EFI_MOUNTED_BY_SCRIPT" -eq 1 ]; then
        umount /boot/efi
    fi

else

    echo
    echo "Legacy BIOS system detected."

    grub2-mkconfig -o /boot/grub2/grub.cfg

fi

###############################################################################
# Show Result
###############################################################################

echo
echo "Current kernel arguments:"
grubby --info=DEFAULT | grep '^args='

sync

echo
echo "========================================================"
echo "Verbose boot enabled successfully."
echo "Reboot to apply the changes."
echo "========================================================"
