#!/bin/bash
# PXE/GRUB2 Setup Script

set -e

# 1. Install required packages
yum install -y tftp-server syslinux dhcp-server grub2-efi-x64 shim-x64 sshpass

# 2. Prepare TFTP directories
mkdir -p /var/lib/tftpboot/pxelinux.cfg
mkdir -p /var/lib/tftpboot/grub2

# 3. Copy PXE/GRUB binaries
cp -v /usr/share/syslinux/{pxelinux.0,ldlinux.c32,menu.c32,libutil.c32} /var/lib/tftpboot/
cp -v /usr/share/grub2/grubx64.efi /var/lib/tftpboot/grub2/ || true
cp -v /usr/share/shim/shimx64.efi /var/lib/tftpboot/grub2/ || true

# 4. Configure firewall
firewall-cmd --add-service={tftp,dhcp} --permanent
firewall-cmd --reload

# 5. Configure DHCP
cat > /etc/dhcp/dhcpd.conf <<'EOF'
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
EOF

systemctl restart dhcpd
systemctl enable dhcpd

# 6. Create GRUB dispatcher
cat > /var/lib/tftpboot/grub2/grub.cfg <<'EOF'
set timeout=0
set default=0

if [ -f $prefix/grub.cfg-$net_default_mac ]; then
    configfile $prefix/grub.cfg-$net_default_mac
fi

echo "No per-host GRUB config found"
sleep 5
EOF

# 7. Copy kernel/initrd from repo server
sshpass -p 'Root@123' scp -o StrictHostKeyChecking=no \
  root@192.168.253.136:/var/www/html/rocky8/isolinux/vmlinuz /var/lib/tftpboot/grub2/

sshpass -p 'Root@123' scp -o StrictHostKeyChecking=no \
  root@192.168.253.136:/var/www/html/rocky8/isolinux/initrd.img /var/lib/tftpboot/grub2/

sshpass -p 'Root@123' scp -o StrictHostKeyChecking=no \
  root@192.168.253.136:/var/www/html/repo/rocky8/EFI/BOOT/grubx64.efi /var/lib/tftpboot/grub2/

# 8. Example per-host GRUB configs
cat > /var/lib/tftpboot/grub2/grub.cfg-01-00-50-56-20-bb-4e <<'EOF'
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
        inst.text inst.default_fstype=ext4 console=tty0
    initrdefi http://192.168.253.136/repo/rocky8/images/pxeboot/initrd.img
}
EOF

cat > /var/lib/tftpboot/grub2/grub.cfg-01-00-50-56-3b-19-ea <<'EOF'
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
        inst.text inst.default_fstype=ext4 console=tty0
    initrdefi http://192.168.253.136/repo/rocky8/images/pxeboot/initrd.img
}
EOF

echo "PXE/GRUB2 setup complete."
