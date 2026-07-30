#!/bin/bash
#==============================================================================
# Rocky Linux 9 Enterprise Golden ISO Builder - Scratch Engine
# Version 2 - Optimized for Centralized HTTP Deployment Sweeps
#==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"
ISO_ROOT="${SCRIPT_DIR}/rocky9-golden"

ISO_NAME="${SCRIPT_DIR}/Rocky9_Golden_RAID.iso"
VOLID="ROCKY9_GOLDEN"

# Centralized HTTP remote asset repository endpoint location path map
REPO_URL="http://192.168.253.136/repo/rocky9-kickstarts"

cd "${ISO_ROOT}"

echo
echo "==========================================================="
echo " Rocky Linux 9 Enterprise Golden ISO Builder"
echo "==========================================================="
echo
echo "ISO Staging Root Directory: ${ISO_ROOT}"
echo "Remote Asset Repository   : ${REPO_URL}"
echo "Destination ISO Location  : ${ISO_NAME}"
echo

##############################################################################
# Validate Required Baseline Tree Frameworks (Rocky 9 Core Directives)
##############################################################################
DIRS=(
AppStream
BaseOS
EFI
images
isolinux
)

for d in "${DIRS[@]}"
do
    if [ ! -d "$d" ]; then
        echo "ERROR : Missing baseline directory structure inside staging root: $d"
        exit 1
    fi
done

##############################################################################
# Validate Core Optical Bootloader Files (Rocky 9 Media Specification Sync)
##############################################################################
FILES=(
isolinux/isolinux.bin
isolinux/vmlinuz
isolinux/initrd.img
images/efiboot.img       # Fixed: Restored to match the true layout on the Rocky 9 DVD media
images/install.img
EFI/BOOT/grub.cfg
)

for f in "${FILES[@]}"
do
    if [ ! -f "$f" ]; then
        echo "ERROR : Missing core boot asset: $f"
        exit 1
    fi
done

##############################################################################
# Backup Original Bootloader Configurations
##############################################################################
cp -f EFI/BOOT/grub.cfg EFI/BOOT/grub.cfg.original

if [ -f isolinux/isolinux.cfg ]; then
    cp -f isolinux/isolinux.cfg isolinux/isolinux.cfg.original
fi

##############################################################################
# BIOS Menu Compilation (Injects remote HTTP Kickstart routing)
##############################################################################
echo "Compiling master Isolinux BIOS definitions (Network Routing Mode)..."
cat > isolinux/isolinux.cfg <<EOF
default auto
timeout 50

menu title Rocky Linux 9 Enterprise Golden Installer System

label auto
  menu label Install Rocky Linux 9 (Enforced Sector Parity RAID1)
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=${VOLID} inst.ks=${REPO_URL}/rocky9.cfg ip=dhcp quiet
EOF

##############################################################################
# UEFI Menu Compilation (Rocky 9 Standard Paths & Network Routing Mode)
##############################################################################
echo "Compiling master GRUB UEFI definitions (Network Routing Mode)..."
cat > EFI/BOOT/grub.cfg <<EOF
set default=0
set timeout=5

menuentry 'Install Rocky Linux 9 (Enforced Sector Parity RAID1)' {
    # Fixed: Uses standard 'linux' and 'initrd' path command sets for Rocky 9 Secure compliance
    linux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=${VOLID} inst.ks=${REPO_URL}/rocky9.cfg ip=dhcp quiet
    initrd /images/pxeboot/initrd.img
}
EOF

##############################################################################
# Flush Stale Output Targets and Generate ISO
##############################################################################
rm -f "${ISO_NAME}"

echo
echo "Compiling ISO via xorriso..."
echo

xorriso \
    -as mkisofs \
    -o "${ISO_NAME}" \
    -V "${VOLID}" \
    -R \
    -J \
    -joliet-long \
    -iso-level 3 \
    -eltorito-boot isolinux/isolinux.bin \
    -eltorito-catalog isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e images/efiboot.img \
    -no-emul-boot \
    .

##############################################################################
# Post-Generation Verification Status Summary
##############################################################################
echo
echo "============================================================"

if [ -f "${ISO_NAME}" ]; then
    echo "SUCCESS: Monolithic Network-Bootable Rocky 9 ISO compiled cleanly."
    echo
    ls -lh "${ISO_NAME}"
    echo
    sha256sum "${ISO_NAME}"
else
    echo "ERROR: Target ISO output missing after generation pass."
    exit 1
fi

echo "============================================================"
echo "Done"
echo "============================================================"

exit 0
