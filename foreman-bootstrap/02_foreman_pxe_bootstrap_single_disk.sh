#!/bin/bash
###############################################################################
# 02 - Foreman PXE Bootstrap (Single Disk)
###############################################################################

FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"
HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"

cat >/tmp/centos-singledisk.erb <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- CentOSLinux
%>
set default=0
set timeout=5
menuentry 'Install CentOS 7 (Single Disk)' {
 linuxefi /centos/vmlinuz inst.stage2=http://192.168.253.136/repo/centos/ inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/centos7-kickstarts/CentOS7_Golden_SingleDisk_Minimal.cfg inst.text BOOTIF=01-${net_default_mac} hostname=<%= @host.name %>
 initrdefi /centos/initrd.img
}
EOF

cat >/tmp/rocky8-singledisk.erb <<'EOF'
<%#
name: PXEGrub2 Rocky8 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5
menuentry 'Install Rocky Linux 8.10 (Single Disk)' {
 linuxefi /rocky8/vmlinuz inst.stage2=http://192.168.253.136/repo/rocky8/ inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky8-kickstarts/Rocky8_Golden_SingleDisk_Minimal.cfg inst.text BOOTIF=01-${net_default_mac} hostname=<%= @host.name %>
 initrdefi /rocky8/initrd.img
}
EOF

cat >/tmp/rocky98-singledisk.erb <<'EOF'
<%#
name: PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5
menuentry 'Install Rocky Linux 9.8 (Single Disk)' {
 linuxefi /rocky9/vmlinuz ip=dhcp inst.repo=http://192.168.253.136/repo/rocky9/ inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/Rocky9_Golden_SingleDisk_Minimal.cfg inst.text hostname=<%= @host.name %>
 initrdefi /rocky9/initrd.img
}
EOF

cat >/tmp/rocky92-singledisk.erb <<'EOF'
<%#
name: PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5
menuentry 'Install Rocky Linux 9.2 (Single Disk)' {
 linuxefi /rocky92/vmlinuz ip=dhcp BOOTIF=01-${net_default_mac} inst.repo=http://192.168.253.136/repo/rocky9.2/ inst.ks=http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/Rocky9_2_Golden_SingleDisk_Minimal.cfg inst.text inst.ks.device=bootif hostname=<%= @host.name %>
 initrdefi /rocky92/initrd.img
}
EOF

$HAMMER template create --name "PXEGrub2 CentOS UEFI SingleDisk Kickstart" --type PXEGrub2 --file /tmp/centos-singledisk.erb 2>/dev/null || true
$HAMMER template create --name "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" --type PXEGrub2 --file /tmp/rocky8-singledisk.erb 2>/dev/null || true
$HAMMER template create --name "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart" --type PXEGrub2 --file /tmp/rocky98-singledisk.erb 2>/dev/null || true
$HAMMER template create --name "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart" --type PXEGrub2 --file /tmp/rocky92-singledisk.erb 2>/dev/null || true

$HAMMER os add-provisioning-template --title "CentOSLinux 7" --provisioning-template "PXEGrub2 CentOS UEFI SingleDisk Kickstart" 2>/dev/null || true
$HAMMER os add-provisioning-template --title "RockyLinux 8.10" --provisioning-template "PXEGrub2 Rocky8 UEFI SingleDisk Kickstart" 2>/dev/null || true
$HAMMER os add-provisioning-template --title "RockyLinux 9.8" --provisioning-template "PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart" 2>/dev/null || true
$HAMMER os add-provisioning-template --title "RockyLinux 9.2" --provisioning-template "PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart" 2>/dev/null || true

echo "Single Disk PXE templates created."
