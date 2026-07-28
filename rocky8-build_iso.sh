#!/bin/bash
#==============================================================================
# Rocky Linux 8.10 Golden ISO Builder
# Version 2
#==============================================================================

set -euo pipefail

##############################################################################
# Configuration
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO_ROOT="${SCRIPT_DIR}/rocky8-golden"

ISO_NAME="${SCRIPT_DIR}/Rocky8_Golden_RAID.iso"
VOLID="ROCKY8_GOLDEN"

##############################################################################
# Working Directory
##############################################################################

cd "${ISO_ROOT}"

echo
echo "==========================================================="
echo " Rocky Linux 8.10 Golden ISO Builder"
echo "==========================================================="
echo
echo "ISO Root : ${ISO_ROOT}"
echo

##############################################################################
# Required Directories
##############################################################################

DIRS=(
AppStream
BaseOS
EFI
images
isolinux
kickstart
scripts
)

for d in "${DIRS[@]}"
do
    if [ ! -d "$d" ]; then
        echo "ERROR : Missing directory $d"
        exit 1
    fi
done

##############################################################################
# Required Files
##############################################################################

FILES=(
kickstart/rockyos.cfg

scripts/00-disk-discovery.sh
scripts/10-partition.sh
scripts/20-storage.sh
scripts/30-postinstall.sh
scripts/40-dual-efi.sh
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
        echo "Missing file:"
        echo "   $f"
        exit 1
    fi
done

##############################################################################
# Backup Existing Boot Menus
##############################################################################

cp -f EFI/BOOT/grub.cfg EFI/BOOT/grub.cfg.original

if [ -f isolinux/isolinux.cfg ]; then
    cp -f isolinux/isolinux.cfg isolinux/isolinux.cfg.original
fi

##############################################################################
# BIOS Menu
##############################################################################

cat > isolinux/isolinux.cfg <<EOF
default auto
timeout 5

menu title Rocky Linux 8.10 Enterprise Golden Installer

label auto
  menu label Install Rocky Linux 8.10 (Automatic RAID1)

  kernel vmlinuz

  append initrd=initrd.img \
         inst.stage2=hd:LABEL=${VOLID} \
         inst.ks=http://192.168.253.136/repo/rocky8-kickstarts/rockyos.cfg \
         ip=dhcp \
         quiet
EOF

##############################################################################
# UEFI Menu
##############################################################################

cat > EFI/BOOT/grub.cfg <<EOF
set default=0
set timeout=5

menuentry 'Install Rocky Linux 8.10 (Automatic RAID1)' {

    linuxefi /images/pxeboot/vmlinuz \
        inst.stage2=hd:LABEL=${VOLID} \
        inst.ks=http://192.168.253.136/repo/rocky8-kickstarts/rockyos.cfg \
        ip=dhcp \
        quiet

    initrdefi /images/pxeboot/initrd.img
}
EOF

##############################################################################
# Permissions
##############################################################################

chmod +x scripts/*.sh

##############################################################################
# Remove Previous ISO
##############################################################################

rm -f "${ISO_NAME}"

##############################################################################
# Build ISO
##############################################################################

echo
echo "Building ISO..."
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
# Verification
##############################################################################

echo
echo "==========================================================="

if [ -f "${ISO_NAME}" ]; then

    echo "ISO Created Successfully"

    echo

    ls -lh "${ISO_NAME}"

    echo

    sha256sum "${ISO_NAME}"

else

    echo "ISO creation failed."

    exit 1

fi

echo
echo "==========================================================="
echo "Done"
echo "==========================================================="
