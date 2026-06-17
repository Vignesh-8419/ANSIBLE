# PXE Boot Server Configuration for Rocky Linux 8 Automated Deployment

## Overview

This document describes the complete configuration of a PXE Boot Server using:

* DHCP Server
* TFTP Server
* GRUB2 UEFI Network Boot
* HTTP Repository Server
* Rocky Linux 8 Kickstart Installation
* Per-Host GRUB Configuration

This setup enables fully automated unattended Rocky Linux deployments based on the client's MAC address.

---

# Architecture

```text
PXE Client
     |
     | DHCP Request
     v
DHCP Server (192.168.253.160)
     |
     | grubx64.efi
     v
TFTP Server
     |
     | grub.cfg-MAC
     v
GRUB2 UEFI
     |
     | HTTP
     v
Repository Server (192.168.253.136)
     |
     | vmlinuz
     | initrd.img
     | kickstart
     v
Automated Rocky Linux Installation
```

---

# Server Information

| Component         | IP Address       |
| ----------------- | ---------------- |
| PXE Server        | 192.168.253.160  |
| Repository Server | 192.168.253.136  |
| Network           | 192.168.253.0/24 |

---

# 1. Install Required Packages

```bash
yum install -y \
tftp-server \
syslinux \
dhcp-server \
grub2-efi-x64 \
shim-x64 \
sshpass
```

Verify installation:

```bash
rpm -qa | egrep 'tftp|syslinux|dhcp|grub2|shim'
```

---

# 2. Prepare TFTP Directory Structure

Create required directories:

```bash
mkdir -p /var/lib/tftpboot/pxelinux.cfg
mkdir -p /var/lib/tftpboot/grub2
```

Verify:

```bash
tree /var/lib/tftpboot
```

Expected:

```text
/var/lib/tftpboot
├── grub2
└── pxelinux.cfg
```

---

# 3. Copy PXE and UEFI Boot Files

Copy Syslinux boot files:

```bash
cp -v /usr/share/syslinux/{pxelinux.0,ldlinux.c32,menu.c32,libutil.c32} \
/var/lib/tftpboot/
```

Copy GRUB UEFI binaries:

```bash
cp -v /usr/share/grub2/grubx64.efi \
/var/lib/tftpboot/grub2/
```

Copy Shim EFI:

```bash
cp -v /usr/share/shim/shimx64.efi \
/var/lib/tftpboot/grub2/
```

Verify:

```bash
ls -lh /var/lib/tftpboot/grub2
```

---

# 4. Configure DHCP Server

Edit:

```bash
vi /etc/dhcp/dhcpd.conf
```

Configuration:

```conf
subnet 192.168.253.0 netmask 255.255.255.0 {

  option routers 192.168.253.2;
  option subnet-mask 255.255.255.0;

  filename "grub2/grubx64.efi";
  next-server 192.168.253.160;
}

# BEGIN ANSIBLE test-server-01
host test-server-01 {
  hardware ethernet 00:50:56:20:bb:4e;
  fixed-address 192.168.253.161;
  option host-name "test-server-01";
}
# END ANSIBLE test-server-01

# BEGIN ANSIBLE test-server-02
host test-server-02 {
  hardware ethernet 00:50:56:3b:19:ea;
  fixed-address 192.168.253.162;
  option host-name "test-server-02";
}
# END ANSIBLE test-server-02
```

Restart DHCP:

```bash
systemctl restart dhcpd
systemctl enable dhcpd
```

Validate:

```bash
systemctl status dhcpd
```

---

# 5. Configure Firewall

Allow DHCP and TFTP services:

```bash
firewall-cmd --add-service=tftp --permanent
firewall-cmd --add-service=dhcp --permanent
firewall-cmd --reload
```

Verify:

```bash
firewall-cmd --list-services
```

Expected:

```text
dhcp tftp
```

---

# 6. Create GRUB Dispatcher

Create:

```bash
vi /var/lib/tftpboot/grub2/grub.cfg
```

Content:

```cfg
set timeout=0
set default=0

if [ -f $prefix/grub.cfg-$net_default_mac ]; then
    configfile $prefix/grub.cfg-$net_default_mac
fi

echo "No per-host GRUB config found"
sleep 5
```

Purpose:

* Detect PXE client MAC address
* Load matching GRUB configuration
* Support per-host automated deployment

---

# 7. Copy Kernel and Initrd from Repository Server

Copy Rocky Linux kernel:

```bash
sshpass -p 'Root@123' scp \
-o StrictHostKeyChecking=no \
root@192.168.253.136:/var/www/html/rocky8/isolinux/vmlinuz \
/var/lib/tftpboot/grub2/
```

Copy initrd:

```bash
sshpass -p 'Root@123' scp \
-o StrictHostKeyChecking=no \
root@192.168.253.136:/var/www/html/rocky8/isolinux/initrd.img \
/var/lib/tftpboot/grub2/
```

Copy EFI boot loader:

```bash
sshpass -p 'Root@123' scp \
-o StrictHostKeyChecking=no \
root@192.168.253.136:/var/www/html/repo/rocky8/EFI/BOOT/grubx64.efi \
/var/lib/tftpboot/grub2/
```

Verify:

```bash
ls -lh /var/lib/tftpboot/grub2
```

---

# 8. Create Per-Host GRUB Configurations

## Host: test-server-01

Create:

```bash
vi /var/lib/tftpboot/grub2/grub.cfg-01-00-50-56-20-bb-4e
```

Configuration:

```cfg
set default=0
set timeout=5

insmod efinet
insmod net
insmod http

dhcp

menuentry "Install Rocky Linux 8 - test-server-01" {

    linuxefi http://192.168.253.136/repo/rocky8/images/pxeboot/vmlinuz \
    inst.repo=http://192.168.253.136/repo/rocky8/ \
    inst.stage2=http://192.168.253.136/repo/rocky8/ \
    ks=http://192.168.253.136/repo/rocky8/kickstart/rockyos.cfg \
    inst.text \
    inst.default_fstype=ext4 \
    console=tty0

    initrdefi http://192.168.253.136/repo/rocky8/images/pxeboot/initrd.img
}
```

---

## Host: test-server-02

Create:

```bash
vi /var/lib/tftpboot/grub2/grub.cfg-01-00-50-56-3b-19-ea
```

Configuration:

```cfg
set default=0
set timeout=5

insmod efinet
insmod net
insmod http

dhcp

menuentry "Install Rocky Linux 8 - test-server-02" {

    linuxefi http://192.168.253.136/repo/rocky8/images/pxeboot/vmlinuz \
    inst.repo=http://192.168.253.136/repo/rocky8/ \
    inst.stage2=http://192.168.253.136/repo/rocky8/ \
    ks=http://192.168.253.136/repo/rocky8/kickstart/rockyos.cfg \
    inst.text \
    inst.default_fstype=ext4 \
    console=tty0

    initrdefi http://192.168.253.136/repo/rocky8/images/pxeboot/initrd.img
}
```

---

# 9. Service Validation

## Verify DHCP Leases

```bash
tail -f /var/log/messages
```

Expected:

```text
DHCPDISCOVER
DHCPOFFER
DHCPREQUEST
DHCPACK
```

---

## Verify TFTP Downloads

```bash
journalctl -u tftp -f
```

Expected:

```text
grubx64.efi
grub.cfg
grub.cfg-01-00-50-56-20-bb-4e
```

---

## Verify HTTP Repository

```bash
curl -I http://192.168.253.136/repo/rocky8/
```

Expected:

```text
HTTP/1.1 200 OK
```

---

## Verify PXE Boot Flow

Expected sequence:

```text
PXE Client
  ↓
DHCP Discover
  ↓
DHCP Offer
  ↓
Download grubx64.efi
  ↓
Download grub.cfg
  ↓
Download MAC-specific grub.cfg
  ↓
Load Rocky Linux Kernel
  ↓
Load Initrd
  ↓
Download Kickstart
  ↓
Automated Installation
```

---

# Troubleshooting

## DHCP Not Responding

```bash
systemctl status dhcpd
journalctl -xeu dhcpd
```

---

## TFTP Download Failure

```bash
systemctl status tftp.socket
```

Verify files:

```bash
ls -lh /var/lib/tftpboot/grub2
```

---

## HTTP Repository Unreachable

```bash
curl -I http://192.168.253.136/repo/rocky8/
```

---

## GRUB Configuration Not Loading

Verify MAC format:

```bash
ip link
```

Expected format:

```text
01-00-50-56-20-bb-4e
```

Must match filename exactly.

---

# Summary

This PXE infrastructure provides:

* DHCP-based host provisioning
* UEFI GRUB network boot
* Per-host deployment menus
* HTTP-based Rocky Linux installation
* Kickstart unattended installation
* Scalable bare-metal and VM provisioning

Suitable for lab, development, and automated server deployment environments.
