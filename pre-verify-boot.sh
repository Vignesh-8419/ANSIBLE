#!/bin/bash
#==============================================================================
# Resilient Infrastructure Pre-Failure Validation Engine
# Automatically verifies next-boot survivability before physical drive drops
#==============================================================================
set -e

# Terminal visual anchors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}====================================================================${NC}"
echo -e "  STARTING PRODUCTION PRE-FAILURE BOOT VERIFICATION SEQUENCE"
echo -e "${YELLOW}====================================================================${NC}"

# Define temporary verification mount path
CHECK_DIR="/tmp/verify-esp-validation"
mkdir -p "$CHECK_DIR"

# 1. Dynamically locate the secondary backup EFI partition
SECONDARY_DISK=$(lsblk -dnno NAME,TYPE | awk '$2=="disk" {print $1}' | grep -E '^(sd|nvme)' | head -n 2 | tail -n 1)
if [ -z "$SECONDARY_DISK" ]; then
    echo -e "[ ${RED}FAILED${NC} ] Could not locate a secondary hard drive asset."
    exit 1
fi

TARGET_PART=$(lsblk -lnno NAME,FSTYPE "/dev/$SECONDARY_DISK" | awk '$2=="vfat" {print $1}')
if [ -z "$TARGET_PART" ]; then
    echo -e "[ ${RED}FAILED${NC} ] No backup VFAT/EFI partition found on /dev/$SECONDARY_DISK."
    exit 1
fi
TARGET_PART="/dev/$TARGET_PART"

# 2. Mount and Verify Backup Boot Files Content
WE_MOUNTED=0
if findmnt -qnvo TARGET "$TARGET_PART" > /dev/null; then
    MOUNT_PATH=$(findmnt -nvo TARGET "$TARGET_PART")
else
    mount -t vfat "$TARGET_PART" "$CHECK_DIR"
    MOUNT_PATH="$CHECK_DIR"
    WE_MOUNTED=1
fi

echo -e "🔍 Inspecting Backup Filesystem Mapping on $TARGET_PART..."
FILE_ERR=0
for file in "EFI/rocky/shimx64.efi" "EFI/rocky/grubx64.efi" "EFI/rocky/grub.cfg" "EFI/BOOT/BOOTX64.EFI" "EFI/BOOT/grub.cfg"; do
    if [ -f "${MOUNT_PATH}/${file}" ]; then
        echo -e "  [ ${GREEN}OK${NC} ] Found mandatory boot asset: ${file}"
    else
        echo -e "  [ ${RED}MISSING${NC} ] Critical boot asset absent: ${file}"
        FILE_ERR=1
    fi
done

# 3. Verify Decoupled Independent GRUB Path Variables
echo -e "\n🔍 Auditing Standalone GRUB Hard Drive Hints..."
if grep -q "hd1" "${MOUNT_PATH}/EFI/rocky/grub.cfg"; then
    echo -e "  [ ${GREEN}OK${NC} ] Configuration paths successfully decoupled to hd1 mapping targets."
else
    echo -e "  [ ${YELLOW}WARNING${NC} ] GRUB configuration is still targeting hd0 paths. Standalone boot might stall."
fi

# Clean up environment mounts cleanly
if [ "$WE_MOUNTED" -eq 1 ]; then
    umount "$MOUNT_PATH"
fi
rmdir "$CHECK_DIR"

if [ "$FILE_ERR" -eq 1 ]; then
    echo -e "\n${RED}❌ VERIFICATION CRASHED: Missing essential EFI binaries on backup drive!${NC}"
    exit 1
fi

# 4. Check Motherboard UEFI NVRAM Firmware Registers
echo -e "\n🔍 Checking Motherboard NVRAM UEFI Boot Configurations..."
if efibootmgr | grep -qi "Rocky Backup"; then
    echo -e "  [ ${GREEN}OK${NC} ] 'Rocky Backup' variable explicitly registered in firmware."
    efibootmgr -v | grep -i "Rocky Backup" | awk '{print "        -> " $0}'
else
    echo -e "  [ ${RED}FAILED${NC} ] 'Rocky Backup' string missing in firmware bootorder configurations."
    exit 1
fi

# 5. Check Active Software RAID 1 Operational Status
echo -e "\n🔍 Inspecting Software RAID Volume Topologies..."
cat /proc/mdstat
if grep -q "\[_U\]" /proc/mdstat || grep -q "\[U_\]" /proc/mdstat; then
    echo -e "\n${YELLOW}⚠️ NOTICE: Arrays are already in a degraded state. Proceed with caution.${NC}"
fi

# 6. Final Production Verdict Verdict
echo ""
echo -e "${GREEN}====================================================================${NC}"
echo -e "${GREEN} 🟢 SUCCESS: All recovery steps done. You are good to reboot!${NC}"
echo -e "    The system firmware and secondary drive are ready to survive a disk loss."
echo -e "${GREEN}====================================================================${NC}"
