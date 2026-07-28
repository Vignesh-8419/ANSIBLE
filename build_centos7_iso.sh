#!/bin/bash
#==============================================================================
# CentOS 7 Enterprise Golden ISO Builder
# Optimized for 100% Symmetrical Block RAID 1 Deployments
#==============================================================================

set -euo pipefail

##############################################################################
# Configuration Variables
##############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO_ROOT="${SCRIPT_DIR}/centos7-golden"

ISO_NAME="${SCRIPT_DIR}/CentOS7_Golden_RAID.iso"
VOLID="CENTOS7_GOLDEN"

##############################################################################
# Environment Setup
##############################################################################
cd "${ISO_ROOT}"

echo
echo "==========================================================="
echo " CentOS 7 Enterprise Golden ISO Builder"
echo "============================================================"
echo
echo "ISO Root Target Directory: ${ISO_ROOT}"
echo "Destination ISO Location : ${ISO_NAME}"
echo

##############################################################################
# Validate Required Directory Frameworks
##############################################################################
DIRS=(
EFI
images
isolinux
kickstart
scripts
)

for d in "${DIRS[@]}"
do
    if [ ! -d "$d" ]; then
        echo "ERROR : Missing baseline installation structural directory: $d"
        exit 1
    fi
done

##############################################################################
# Validate Required File Matrix Elements (Slimmed to optimized 3-script layout)
##############################################################################
FILES=(
kickstart/centos7.cfg

scripts/30-postinstall.sh
scripts/50-grub.sh
scripts/99-cleanup.sh

isolinux/isolinux.bin
isolinux/vmlinuz
isolinux/initrd.img

images/efiboot.img
images/install.img

EFI/BOOT/grub.cfg
)

for f in "${FILES[@]}"
do
    if [ ! -f "$f" ]; then
        echo
        echo "CRITICAL DEFECT: Missing mandatory deployment tracking file asset:"
        echo "   $f"
        exit 1
    fi
done

##############################################################################
# Safeguard and Backup Factory Default Boot Configuration Profiles
##############################################################################
cp -f EFI/BOOT/grub.cfg EFI/BOOT/grub.cfg.original

if [ -f isolinux/isolinux.cfg ]; then
    cp -f isolinux/isolinux.cfg isolinux/isolinux.cfg.original
fi

##############################################################################
# Compile Legacy BIOS System boot Target Menu Profile Configuration
##############################################################################
echo "Compiling master Isolinux BIOS layout definitions..."
cat > isolinux/isolinux.cfg <<EOF
default auto
timeout 50

menu title CentOS 7 Enterprise Golden Installer System

label auto
  menu label Install CentOS 7 (Enforced Sector Parity RAID1)
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=${VOLID} inst.ks=hd:LABEL=${VOLID}:/kickstart/centos7.cfg ip=dhcp quiet
EOF

##############################################################################
# Compile UEFI System Boot Target Menu Configuration (CentOS 7 Compatible Paths)
##############################################################################
echo "Compiling master GRUB UEFI layout definitions..."
cat > EFI/BOOT/grub.cfg <<EOF
set default=0
set timeout=5

menuentry 'Install CentOS 7 (Enforced Sector Parity RAID1)' {
    # Fixed: CentOS 7 UEFI requires standard native 'linux' and 'initrd' path commands
    linux /isolinux/vmlinuz inst.stage2=hd:LABEL=${VOLID} inst.ks=hd:LABEL=${VOLID}:/kickstart/centos7.cfg ip=dhcp quiet
    initrd /isolinux/initrd.img
}
EOF

##############################################################################
# Enforce Core Boundary File Execution Permissions
##############################################################################
chmod +x scripts/*.sh

##############################################################################
# Flush and Purge Stale Deployment Block References
##############################################################################
rm -f "${ISO_NAME}"

##############################################################################
# Build Monolithic Bootable Hybrid Optical Enterprise Installation ISO File
##############################################################################
echo
echo "Executing xorriso generation sweep..."
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
# Post-Generation Verification Statistics Summary Tracking pass
##############################################################################
echo
echo "==========================================================="

if [ -f "${ISO_NAME}" ]; then
    echo "SUCCESS: Monolithic bootable image built cleanly."
    echo
    ls -lh "${ISO_NAME}"
    echo
    sha256sum "${ISO_NAME}"
else
    echo "ERROR: Image output targets missing from file array mapping layers."
    exit 1
fi

echo
echo "==========================================================="
echo "Done"
echo "============================================================"
