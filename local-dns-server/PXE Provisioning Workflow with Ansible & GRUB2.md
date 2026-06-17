# PXE Provisioning Workflow with Ansible & GRUB2

## Overview

This document describes an automated PXE provisioning workflow using:

* AWX / Ansible Automation Platform
* DHCP Server
* TFTP Server
* GRUB2 UEFI Boot
* HTTP Repository Server
* Rocky Linux 8 Kickstart Installation
* Per-Host PXE Configuration

The solution allows administrators to provision multiple servers through AWX surveys while dynamically generating PXE boot configurations based on hostname, IP address, and MAC address.

---

# Purpose

The primary objectives of this solution are:

* Automate bare-metal and virtual machine deployments
* Eliminate manual PXE configuration
* Generate host-specific GRUB boot menus
* Support unattended Rocky Linux installations
* Integrate provisioning into AWX workflows
* Simplify large-scale server deployments

---

# Architecture

```text
                +------------------+
                |       AWX        |
                | Survey Inputs    |
                +--------+---------+
                         |
                         v
                +------------------+
                | Ansible Playbook |
                +--------+---------+
                         |
                         v
                +------------------+
                | PXE Provisioning |
                |      Role        |
                +--------+---------+
                         |
          +--------------+--------------+
          |                             |
          v                             v
+-------------------+      +-----------------------+
| DHCP Configuration|      | GRUB Configuration    |
+-------------------+      +-----------------------+
          |                             |
          +-------------+---------------+
                        |
                        v
              +------------------+
              | TFTP Server      |
              | grubx64.efi      |
              | grub.cfg         |
              +--------+---------+
                       |
                       v
              +------------------+
              | PXE Client       |
              +--------+---------+
                       |
                       v
              +------------------+
              | HTTP Repository  |
              | Kernel/Initrd    |
              | Kickstart File   |
              +--------+---------+
                       |
                       v
              +------------------+
              | Rocky Linux 8    |
              | Installation     |
              +------------------+
```

---

# Prerequisites

## Infrastructure Requirements

### PXE/TFTP Server

Required services:

* dhcpd
* tftp-server
* grub2-efi-x64
* shim-x64

### Repository Server

Repository Server:

```text
192.168.253.136
```

Hosting:

```text
/repo/rocky8/
/repo/rocky8/images/pxeboot/
/repo/rocky8/kickstart/
```

### AWX / Ansible

Requirements:

* AWX installed and operational
* Survey-enabled Job Template
* Access to TFTP server
* Access to DHCP server

### ESXi Environment (Optional)

Used when provisioning virtual machines.

```text
ESXi Host: 192.168.253.128
Username : root
```

---

# Project Structure

```text
roles/
└── pxe_provision/
    ├── defaults/
    │   └── main.yml
    │
    ├── handlers/
    │   └── main.yml
    │
    ├── tasks/
    │   ├── main.yml
    │   └── per_server.yml
    │
    └── templates/
        ├── grub-rocky8.j2
        └── grub-dispatcher.j2

playbooks/
└── os_install.yml
```

---

# Templates

## grub-rocky8.j2

Purpose:

* Creates host-specific Rocky Linux installation menu
* Loads kernel and initrd from HTTP repository
* Uses Kickstart for unattended deployment

```cfg
set default=0
set timeout=5

insmod efinet
insmod net
insmod http

dhcp

menuentry "Install Rocky Linux 8" {

    linuxefi http://{{ http_server }}/repo/rocky8/images/pxeboot/vmlinuz \
        ip=dhcp \
        inst.repo=http://{{ http_server }}/repo/rocky8/ \
        inst.stage2=http://{{ http_server }}/repo/rocky8/ \
        inst.ks=http://{{ http_server }}/repo/rocky8/kickstart/rockyos.cfg \
        inst.text inst.default_fstype=ext4 console=tty0

    initrdefi http://{{ http_server }}/repo/rocky8/images/pxeboot/initrd.img
}
```

---

## grub-dispatcher.j2

Purpose:

* Detect PXE client MAC address
* Load matching host configuration
* Prevent incorrect installations

```cfg
set timeout=0
set default=0

if [ -f $prefix/grub.cfg-$net_default_mac ]; then
    configfile $prefix/grub.cfg-$net_default_mac
fi

echo "No per-host GRUB config found"
sleep 5
```

---

# Defaults Configuration

File:

```text
roles/pxe_provision/defaults/main.yml
```

```yaml
http_server: "192.168.253.136"

esxi_host: "192.168.253.128"
esxi_user: "root"
esxi_pass: "admin$22"

servers: []
```

Variable Description:

| Variable    | Description                  |
| ----------- | ---------------------------- |
| http_server | Repository Server            |
| esxi_host   | ESXi Host                    |
| esxi_user   | ESXi Username                |
| esxi_pass   | ESXi Password                |
| servers     | Survey-generated server list |

---

# Task Files

## tasks/main.yml

Purpose:

* Deploy GRUB dispatcher
* Process server inventory
* Call per-server provisioning

```yaml
- name: Ensure GRUB dispatcher exists
  template:
    src: grub-dispatcher.j2
    dest: /var/lib/tftpboot/grub2/grub.cfg
    mode: '0644'
  delegate_to: tftp-server-01
  run_once: true

- name: Provision PXE servers
  include_tasks: per_server.yml
  loop: "{{ servers }}"
  loop_control:
    loop_var: server
```

---

## tasks/per_server.yml

Purpose:

* Generate MAC-specific GRUB files

```yaml
- name: Ensure GRUB dispatcher exists
  template:
    src: grub-dispatcher.j2
    dest: /var/lib/tftpboot/grub2/grub.cfg
    mode: '0644'
  delegate_to: tftp-server-01
  run_once: true

- name: Provision PXE servers
  template:
    src: grub-rocky8.j2
    dest: "/var/lib/tftpboot/grub2/grub.cfg-{{ server.mac }}"
    mode: '0644'
  delegate_to: tftp-server-01
```

---

# Handlers

File:

```text
roles/pxe_provision/handlers/main.yml
```

Purpose:

* Restart DHCP after configuration changes

```yaml
- name: restart dhcpd
  service:
    name: dhcpd
    state: restarted
  delegate_to: tftp-server-01
```

---

# Playbook

File:

```text
playbooks/os_install.yml
```

Purpose:

* Collect survey inputs
* Validate data
* Generate provisioning list
* Execute PXE role

```yaml
- name: Provision servers via PXE
  hosts: localhost
  gather_facts: false

  vars:
    hostnames: ""
    ips: ""
    macs: ""

  tasks:

    - name: Normalize survey inputs
      set_fact:
        host_list: "{{ hostnames.replace('\"','').strip().split(',') }}"
        ip_list: "{{ ips.replace('\"','').strip().split(',') }}"
        mac_list: "{{ macs.replace('\"','').strip().split(',') }}"

    - name: Validate input lengths
      assert:
        that:
          - host_list | length == ip_list | length
          - host_list | length == mac_list | length
        fail_msg: "Survey input count mismatch"

    - name: Build servers list
      set_fact:
        servers: "{{ servers | default([]) + [ {
          'hostname': item.0.strip(),
          'ip': item.1.strip(),
          'mac': item.2.strip() | lower
        } ] }}"
      loop: "{{ host_list | zip(ip_list, mac_list) | list }}"

    - name: Run PXE provisioning role
      include_role:
        name: roles/pxe_provision
```

---

# AWX Survey Configuration

Example Survey Inputs:

| Field         | Example                                   |
| ------------- | ----------------------------------------- |
| Hostnames     | server01,server02                         |
| IP Addresses  | 192.168.253.161,192.168.253.162           |
| MAC Addresses | 01-00-50-56-20-bb-4e,01-00-50-56-3b-19-ea |

Generated Output:

```text
grub.cfg-01-00-50-56-20-bb-4e
grub.cfg-01-00-50-56-3b-19-ea
```

---

# Execution Flow

## Step 1

User launches AWX Job Template.

---

## Step 2

Survey collects:

```text
Hostname
IP Address
MAC Address
```

---

## Step 3

Playbook validates survey inputs.

---

## Step 4

Ansible builds:

```yaml
servers:
  - hostname: server01
    ip: 192.168.253.161
    mac: 01-00-50-56-20-bb-4e

  - hostname: server02
    ip: 192.168.253.162
    mac: 01-00-50-56-3b-19-ea
```

---

## Step 5

Role deploys:

```text
/var/lib/tftpboot/grub2/grub.cfg
```

Dispatcher.

---

## Step 6

Role creates:

```text
/var/lib/tftpboot/grub2/grub.cfg-<MAC>
```

Per-host GRUB configuration.

---

## Step 7

PXE Client boots.

---

## Step 8

DHCP assigns IP.

---

## Step 9

TFTP downloads:

```text
grubx64.efi
grub.cfg
```

---

## Step 10

Dispatcher loads:

```text
grub.cfg-<MAC>
```

---

## Step 11

GRUB downloads:

```text
vmlinuz
initrd.img
```

from HTTP repository.

---

## Step 12

Kickstart executes unattended installation.

---

# Validation

## Verify DHCP

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

## Verify TFTP Activity

```bash
journalctl -f
```

Expected:

```text
grubx64.efi
grub.cfg
grub.cfg-01-xx-xx-xx
```

---

## Verify HTTP Downloads

```bash
tail -f /var/log/httpd/access_log
```

Expected:

```text
vmlinuz
initrd.img
rockyos.cfg
```

---

## Verify Installation

Expected Flow:

```text
PXE Boot
↓
DHCP
↓
GRUB EFI
↓
GRUB Dispatcher
↓
Per-Host Config
↓
Kernel
↓
Initrd
↓
Kickstart
↓
Rocky Linux Installation
```

---

# Troubleshooting

## Survey Input Mismatch

Error:

```text
Survey input count mismatch
```

Cause:

```text
Hostname count != IP count != MAC count
```

Fix:

Ensure all survey fields contain the same number of entries.

---

## Missing GRUB File

Verify:

```bash
ls -lh /var/lib/tftpboot/grub2/
```

---

## DHCP Not Assigning IP

```bash
systemctl status dhcpd
journalctl -xeu dhcpd
```

---

## TFTP Failure

```bash
systemctl status tftp.socket
```

---

## HTTP Repository Unreachable

```bash
curl -I http://192.168.253.136/repo/rocky8/
```

---

# Summary

This PXE provisioning framework integrates AWX, Ansible, DHCP, TFTP, GRUB2, and Kickstart to provide a scalable, automated, and repeatable operating system deployment solution. The workflow dynamically generates host-specific PXE configurations using survey input and supports unattended Rocky Linux installations with minimal administrator intervention.
