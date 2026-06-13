# Foreman PXE UEFI Kickstart Templates

This repository contains custom Foreman PXE GRUB2 templates for automated Rocky Linux and CentOS installations using Kickstart over HTTP.

## Templates Included

### 1. PXEGrub2 RockyOS UEFI Static Kickstart

* OS: Rocky Linux
* Boot Mode: UEFI
* Kickstart Source:

  ```
  http://192.168.253.131/repo/rocky8/kickstart/rockyos.cfg
  ```
* Installation Repository:

  ```
  http://192.168.253.131/repo/rocky8/
  ```

```erb
<%#
name: PXEGrub2 RockyOS UEFI Static Kickstart
kind: PXEGrub2
oses:
- RockyOS
%>

set default=0
set timeout=5

menuentry 'Install RockyOS via Kickstart' {
    linuxefi /rockyos/vmlinuz \
        inst.stage2=http://192.168.253.131/repo/rocky8/ \
        inst.ks=http://192.168.253.131/repo/rocky8/kickstart/rockyos.cfg \
        inst.text inst.default_fstype=ext4 \
        inst.ks.device=bootif BOOTIF=01-${net_default_mac} \
        hostname=<%= @host.name %>
    initrdefi /rockyos/initrd.img
}
```

---

### 2. PXEGrub2 CentOS UEFI Static Kickstart

* OS: CentOS
* Boot Mode: UEFI
* Kickstart Source:

  ```
  http://192.168.253.136/repo/centos/kickstart/centos.cfg
  ```
* Installation Repository:

  ```
  http://192.168.253.136/repo/centos/
  ```

```erb
<%#
name: PXEGrub2 CentOS UEFI Static Kickstart
kind: PXEGrub2
oses:
- CentOS
%>

set default=0
set timeout=5

menuentry 'Install CentOS via Kickstart' {
    linuxefi /centos/vmlinuz \
        inst.stage2=http://192.168.253.136/repo/centos/ \
        inst.ks=http://192.168.253.136/repo/centos/kickstart/centos.cfg \
        inst.text inst.default_fstype=ext4 \
        inst.ks.device=bootif BOOTIF=01-${net_default_mac} \
        hostname=<%= @host.name %>
    initrdefi /centos/initrd.img
}
```

---

## Requirements

### HTTP Repository Server

Ensure the following repositories are accessible:

```text
http://192.168.253.131/repo/rocky8/
http://192.168.253.136/repo/centos/
```

### Required Boot Files

Rocky Linux:

```text
/var/lib/tftpboot/rockyos/vmlinuz
/var/lib/tftpboot/rockyos/initrd.img
```

CentOS:

```text
/var/lib/tftpboot/centos/vmlinuz
/var/lib/tftpboot/centos/initrd.img
```

### Foreman Settings

1. Import the templates into Foreman.
2. Associate the template with the appropriate Operating System.
3. Ensure PXE Loader is configured for UEFI hosts.
4. Build hosts using the matching OS template.
5. Verify DHCP, TFTP, and HTTP services are reachable from target hosts.

---

## Network Flow

```text
Client PXE Boot
      │
      ▼
DHCP Server
      │
      ▼
TFTP Server
      │
      ▼
GRUB2 UEFI Template
      │
      ▼
Kickstart File (HTTP)
      │
      ▼
OS Repository (HTTP)
      │
      ▼
Automated Installation
```

---

## Notes

* Uses MAC-based BOOTIF detection:

  ```text
  inst.ks.device=bootif
  ```

* Automatically passes the Foreman hostname:

  ```text
  hostname=<%= @host.name %>
  ```

* Installation runs in text mode:

  ```text
  inst.text
  ```

* Default filesystem:

  ```text
  ext4
  ```

* Compatible with UEFI PXE boot environments.
