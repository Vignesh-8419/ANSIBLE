#setup_grub.sh
#!/bin/bash
set -e

echo "==== Enable Verbose Boot + Serial Console (EL7 / EL8) ===="

# Detect OS major version
OS_MAJOR=$(rpm -E %rhel 2>/dev/null || echo 0)

if [[ "$OS_MAJOR" -ne 7 && "$OS_MAJOR" -ne 8 ]]; then
    echo "Unsupported OS version: RHEL $OS_MAJOR"
    exit 1
fi

echo "Detected RHEL / EL version: $OS_MAJOR"

GRUB_DEFAULT_FILE="/etc/default/grub"

if [[ ! -f $GRUB_DEFAULT_FILE ]]; then
    echo "ERROR: $GRUB_DEFAULT_FILE not found"
    exit 1
fi

# Backup grub file
BACKUP="/etc/default/grub.$(date +%F_%H%M%S).bak"
cp -a "$GRUB_DEFAULT_FILE" "$BACKUP"
echo "Backup created: $BACKUP"

# Remove rhgb and quiet
sed -i 's/\brhgb\b//g' "$GRUB_DEFAULT_FILE"
sed -i 's/\bquiet\b//g' "$GRUB_DEFAULT_FILE"

# Ensure console settings
if ! grep -q 'console=ttyS0' "$GRUB_DEFAULT_FILE"; then
    sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200 /' \
        "$GRUB_DEFAULT_FILE"
fi

# Normalize spacing
sed -i 's/  */ /g' "$GRUB_DEFAULT_FILE"

echo
echo "Updated GRUB_CMDLINE_LINUX:"
grep GRUB_CMDLINE_LINUX "$GRUB_DEFAULT_FILE"

# Determine firmware type
if [[ -d /sys/firmware/efi ]]; then
    FIRMWARE="UEFI"
else
    FIRMWARE="BIOS"
fi

echo "Firmware detected: $FIRMWARE"

# Regenerate GRUB config based on OS + firmware
if [[ "$OS_MAJOR" -eq 7 ]]; then
    echo "Generating GRUB config for EL7"

    if [[ "$FIRMWARE" == "UEFI" ]]; then
        grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
    else
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi

elif [[ "$OS_MAJOR" -eq 8 ]]; then
    echo "Generating GRUB config for EL8"

    if [[ "$FIRMWARE" == "UEFI" ]]; then
        grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg 2>/dev/null || \
        grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg
    else
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
fi

echo
echo "SUCCESS: Verbose boot + serial console enabled"
echo "Reboot the system to apply changes"
