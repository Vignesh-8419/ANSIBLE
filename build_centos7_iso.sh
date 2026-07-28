#!/bin/bash
#==============================================================================
# CentOS 7 Enterprise Golden ISO Builder - Pure Network Routing Mode
# Bypasses local file validation loops to fetch configurations via HTTP
#==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"
ISO_ROOT="${SCRIPT_DIR}/centos7-golden"

ISO_NAME="${SCRIPT_DIR}/CentOS7_Golden_RAID.iso"
VOLID="CENTOS7_GOLDEN"

# Centralized HTTP asset repository endpoint target
REPO_URL="http://192.168.253"

cd "${ISO_ROOT}"

echo
echo "==========================================================="
echo " CentOS 7 Enterprise Golden ISO Builder (Network Routing)"
echo "==========================================================="
echo
echo "ISO Staging Root Directory: ${ISO_ROOT}"
echo "Remote Asset Repository   : ${REPO_URL}"
echo "Destination ISO Location  : ${ISO_NAME}"
echo

##############################################################################
# Validate Required Baseline Tree Frameworks (CentOS 7 Core Directives)
##############################################################################
DIRS=(
EFI
images
isolinux
LiveOS
Packages
repodata
)

for d in "${DIRS[@]}"
do
    if [ ! -d "$d" ]; then
        echo "ERROR : Missing baseline directory structure inside staging root: $d"
        exit 1
    fi
done

##############################################################################
# Validate Core Optical Bootloader Files Only (CentOS 7 Media Layout Sync)
##############################################################################
FILES=(
isolinux/isolinux.bin
isolinux/vmlinuz
isolinux/initrd.img
images/efiboot.img
LiveOS/squashfs.img   # Fixed: Matched directly to your extracted DVD structure
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

menu title CentOS 7 Enterprise Golden Installer System

label auto
  menu label Install CentOS 7 (Enforced Sector Parity RAID1)
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=${VOLID} inst.ks=${REPO_URL}/centos7.cfg ip=dhcp quiet
EOF

##############################################################################
# UEFI Menu Compilation (CentOS 7 Compatible Tags & Network Routing)
##############################################################################
echo "Compiling master GRUB UEFI definitions (Network Routing Mode)..."
cat > EFI/BOOT/grub.cfg <<EOF
set default=0
set timeout=5

menuentry 'Install CentOS 7 (Enforced Sector Parity RAID1)' {
    # Fixed: Uses standard 'linux' and 'initrd' path tags for CentOS 7 compatibility
    linux /isolinux/vmlinuz inst.stage2=hd:LABEL=${VOLID} inst.ks=${REPO_URL}/centos7.cfg ip=dhcp quiet
    initrd /isolinux/initrd.img
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
    echo "SUCCESS: Monolithic Network-Bootable ISO compiled cleanly."
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
