#!/bin/bash
set -e

echo "== Enabling verbose boot and serial console =="

GRUB_DEFAULT_FILE="/etc/default/grub"

if [[ ! -f $GRUB_DEFAULT_FILE ]]; then
    echo "ERROR: $GRUB_DEFAULT_FILE not found"
    exit 1
fi

# Backup
BACKUP="/etc/default/grub.$(date +%F_%H%M%S).bak"
cp -a "$GRUB_DEFAULT_FILE" "$BACKUP"
echo "Backup created: $BACKUP"

# Remove rhgb and quiet
sed -i 's/\brhgb\b//g' "$GRUB_DEFAULT_FILE"
sed -i 's/\bquiet\b//g' "$GRUB_DEFAULT_FILE"

# Ensure console parameters exist
if ! grep -q 'console=ttyS0' "$GRUB_DEFAULT_FILE"; then
    sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200 /' \
        "$GRUB_DEFAULT_FILE"
fi

# Clean up extra spaces
sed -i 's/  */ /g' "$GRUB_DEFAULT_FILE"

echo "Updated GRUB_CMDLINE_LINUX:"
grep GRUB_CMDLINE_LINUX "$GRUB_DEFAULT_FILE"

# Detect firmware type and regenerate grub config
if [[ -d /sys/firmware/efi ]]; then
    echo "UEFI system detected"
    GRUB_CFG="/boot/efi/EFI/rocky/grub.cfg"
else
    echo "BIOS system detected"
    GRUB_CFG="/boot/grub2/grub.cfg"
fi

echo "Regenerating GRUB config: $GRUB_CFG"
grub2-mkconfig -o "$GRUB_CFG"

echo
echo "SUCCESS: Verbose boot + serial console enabled"
echo "Reboot required to take effect"
