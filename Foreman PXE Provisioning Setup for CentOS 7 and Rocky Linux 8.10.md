# Foreman PXE Provisioning Setup for CentOS 7 and Rocky Linux 8.10

## 1. Create Installation Media

### CentOS 7

```bash
hammer --username admin --password 'zqs977dXzqfEvTML' medium create --name "CentOS 7 Remote" --path "http://192.168.253.136/repo/centos/" --os-family "Redhat"
```

### Rocky Linux 8.10

```bash
hammer --username admin --password 'zqs977dXzqfEvTML' medium create --name "Rocky 8 Remote" --path "http://192.168.253.136/repo/rocky8/" --os-family "Redhat"
```

---

## 2. Create Operating Systems

### CentOS Linux 7

```bash
hammer --username admin --password 'zqs977dXzqfEvTML' os create \
--name CentOSLinux \
--major 7 \
--family Redhat \
--architectures x86_64 \
--partition-tables "Kickstart default" \
--media "CentOS 7 Remote"
```

### Rocky Linux 8.10

```bash
hammer --username admin --password 'zqs977dXzqfEvTML' os create \
--name RockyLinux \
--major 8 \
--minor 10 \
--family Redhat \
--architectures x86_64 \
--partition-tables "Kickstart default" \
--media "Rocky 8 Remote"
```

---

## 3. Create PXEGrub2 Provisioning Templates

### Rocky Linux PXEGrub2 Template

```bash
cat > /tmp/rocky-pxegrub2.erb <<'EOF'
<%#
name: PXEGrub2 RockyOS UEFI Static Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5
menuentry 'Install RockyOS via Kickstart' {
    linuxefi /rockyos/vmlinuz inst.stage2=http://192.168.253.136/repo/rocky8/ inst.ks=http://192.168.253.136/repo/rocky8/kickstart/rockyos.cfg inst.text inst.default_fstype=ext4 inst.ks.device=bootif BOOTIF=01-${net_default_mac} hostname=<%= @host.name %>
    initrdefi /rockyos/initrd.img
}
EOF
```

```bash
hammer --username admin --password 'zqs977dXzqfEvTML' template create \
--name "PXEGrub2 RockyOS UEFI Static Kickstart" \
--type PXEGrub2 \
--file /tmp/rocky-pxegrub2.erb
```

```bash
hammer --username admin --password 'zqs977dXzqfEvTML' os add-provisioning-template \
--title "RockyLinux 8.10" \
--provisioning-template "PXEGrub2 RockyOS UEFI Static Kickstart"
```

### CentOS PXEGrub2 Template

```bash
cat > /tmp/centos-pxegrub2.erb <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI Static Kickstart
kind: PXEGrub2
oses:
- CentOSLinux
%>
set default=0
set timeout=5
menuentry 'Install CentOS via Kickstart' {
    linuxefi /centos/vmlinuz inst.stage2=http://192.168.253.136/repo/centos/ inst.ks=http://192.168.253.136/repo/centos/kickstart/centos.cfg inst.text inst.default_fstype=ext4 inst.ks.device=bootif BOOTIF=01-${net_default_mac} hostname=<%= @host.name %>
    initrdefi /centos/initrd.img
}
EOF
```

```bash
hammer --username admin --password 'zqs977dXzqfEvTML' template create \
--name "PXEGrub2 CentOS UEFI Static Kickstart" \
--type PXEGrub2 \
--file /tmp/centos-pxegrub2.erb
```

```bash
hammer --username admin --password 'zqs977dXzqfEvTML' os add-provisioning-template \
--title "CentOSLinux 7" \
--provisioning-template "PXEGrub2 CentOS UEFI Static Kickstart"
```

---

## 4. Create Subnets

### CentOS Subnet

```bash
hammer --username admin --password 'zqs977dXzqfEvTML' subnet create \
--name vgs-subnet-centos \
--network 192.168.253.0 \
--mask 255.255.255.0 \
--gateway 192.168.253.2 \
--dns-primary 192.168.253.1 \
--from 192.168.253.10 \
--to 192.168.253.240 \
--ipam DHCP \
--boot-mode DHCP \
--mtu 1500 \
--domains vgs.com \
--dhcp cent-07-01.vgs.com \
--tftp cent-07-01.vgs.com
```

### Rocky Linux Subnet

```bash
hammer --username admin --password 'zqs977dXzqfEvTML' subnet create \
--name vgs-subnet-rockyos \
--network 192.168.253.0 \
--mask 255.255.255.0 \
--gateway 192.168.253.2 \
--dns-primary 192.168.253.1 \
--from 192.168.253.10 \
--to 192.168.253.240 \
--ipam DHCP \
--boot-mode DHCP \
--mtu 1500 \
--domains vgs.com \
--dhcp cent-07-02.vgs.com \
--tftp cent-07-02.vgs.com
```

---

## 5. Create Host Groups

### CentOS 7 Host Group

```bash
hammer --username admin --password 'zqs977dXzqfEvTML' hostgroup create \
--organization "Default Organization" \
--name "VGS HOSTS CENTOS 7" \
--architecture x86_64 \
--operatingsystem "CentOSLinux 7" \
--medium "CentOS 7 Remote" \
--partition-table "Kickstart default" \
--pxe-loader "Grub2 UEFI" \
--domain "vgs.com" \
--subnet "vgs-subnet-centos" \
--content-source "cent-07-01.vgs.com" \
--content-view "Default Organization View" \
--lifecycle-environment "Library"
```

### Rocky Linux 8 Host Group

```bash
hammer --username admin --password 'zqs977dXzqfEvTML' hostgroup create \
--organization "Default Organization" \
--name "VGS HOSTS ROCKY 8" \
--architecture x86_64 \
--operatingsystem "RockyLinux 8.10" \
--medium "Rocky 8 Remote" \
--partition-table "Kickstart default" \
--pxe-loader "Grub2 UEFI" \
--domain "vgs.com" \
--subnet "vgs-subnet-rockyos" \
--content-source "cent-07-01.vgs.com" \
--content-view "Default Organization View" \
--lifecycle-environment "Library"
```

---

## 6. Set Default PXEGrub2 Templates

### CentOS Linux 7

```bash
hammer --username admin --password 'zqs977dXzqfEvTML' os set-default-template \
--id 2 \
--provisioning-template-id 175
```

### Rocky Linux 8.10

```bash
hammer --username admin --password 'zqs977dXzqfEvTML' os set-default-template \
--id 3 \
--provisioning-template-id 174
```

---

## Operating System IDs

```text
2 = CentOSLinux 7
3 = RockyLinux 8.10
```

## PXEGrub2 Template IDs

```text
174 = PXEGrub2 RockyOS UEFI Static Kickstart
175 = PXEGrub2 CentOS UEFI Static Kickstart
```
