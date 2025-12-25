#!/bin/bash
# PXE Boot Setup Script
# Author: Vasantha Prabu K (Vignesh)
# Purpose: Automate PXE/TFTP/DHCP setup for BIOS + UEFI boot

set -e

# Variables
TFTP_DIR="/var/lib/tftpboot"
REPO_SERVER="192.168.253.136"
NEXT_SERVER="192.168.253.160"
SSH_PASS="Root@123"
SSH_USER="root"
SSH_HOST="localhost"   # adjust if copying from remote host

echo "[INFO] Installing required packages..."
yum install -y tftp-server syslinux dhcp-server grub2-efi-x64 shim-x64 sshpass

echo "[INFO] Creating TFTP directories..."
mkdir -p ${TFTP_DIR}/pxelinux.cfg
mkdir -p ${TFTP_DIR}/grub
mkdir -p ${TFTP_DIR}/grub2

echo "[INFO] Copying PXE bootloader files..."
cp -v /usr/share/syslinux/{pxelinux.0,menu.c32,ldlinux.c32,libutil.c32} ${TFTP_DIR}/

echo "[INFO] Configuring BIOS PXE menu..."
cat > ${TFTP_DIR}/pxelinux.cfg/default <<EOF
DEFAULT menu.c32
PROMPT 0
TIMEOUT 100
MENU TITLE PXE Boot Menu

LABEL centos7
  MENU LABEL Install CentOS 7 (generic)
  KERNEL http://${REPO_SERVER}/repo/centos/images/pxeboot/vmlinuz
  INITRD http://${REPO_SERVER}/repo/centos/images/pxeboot/initrd.img
  APPEND inst.repo=http://${REPO_SERVER}/repo/centos ks=http://${REPO_SERVER}/repo/centos/kickstart/centos.cfg

LABEL rocky8
  MENU LABEL Install Rocky Linux 8 (generic)
  KERNEL http://${REPO_SERVER}/repo/rocky8/images/pxeboot/vmlinuz
  INITRD http://${REPO_SERVER}/repo/rocky8/images/pxeboot/initrd.img
  APPEND inst.repo=http://${REPO_SERVER}/repo/rocky8 ks=http://${REPO_SERVER}/repo/rocky8/kickstart/rockyos.cfg
EOF

echo "[INFO] Configuring UEFI GRUB menu..."
cat > ${TFTP_DIR}/grub/grub.cfg <<EOF
set default=0
set timeout=5

insmod efinet
insmod net
insmod http
net_bootp

menuentry 'Install Rocky Linux 8 UEFI' {
    linuxefi vmlinuz inst.repo=http://${REPO_SERVER}/repo/rocky8 ks=http://${REPO_SERVER}/repo/rocky8/kickstart/rockyos.cfg
    initrdefi initrd.img
}
EOF

echo "[INFO] Configuring DHCP server..."
cat > /etc/dhcp/dhcpd.conf <<EOF
subnet 192.168.253.0 netmask 255.255.255.0 {
  option routers 192.168.253.2;
  option subnet-mask 255.255.255.0;

  filename "grub2/grubx64.efi";
  next-server 192.168.253.160;
}


EOF

echo "[INFO] Adjusting firewall rules..."
firewall-cmd --add-service={tftp,dhcp} --permanent
firewall-cmd --reload

echo "[INFO] Copying kernel/initrd images..."
sshpass -p 'Root@123' scp -o StrictHostKeyChecking=no root@192.168.253.136:/var/www/html/rocky8/isolinux/vmlinuz /var/lib/tftpboot/
sshpass -p 'Root@123' scp -o StrictHostKeyChecking=no root@192.168.253.136:/var/www/html/rocky8/isolinux/initrd.img /var/lib/tftpboot/

echo "[INFO] PXE setup completed successfully!"
