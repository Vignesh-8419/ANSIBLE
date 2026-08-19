# Foreman Rocky Linux 8 Provisioning

## Overview

This Ansible automation provisions Rocky Linux 8 hosts using NetBox, ESXi, Technitium DNS, and Foreman.

The main playbook is:

```bash
Foreman_provision_hosts_el8.yml
```

It runs the following playbooks in order:

```text
1. ensure_vm_exists.yml
2. provision_hosts_dns.yml
3. provision_hosts_el8.yml
4. bootorder_uefi_el8.yml
```

## Prerequisites

Run the playbook from a system where Ansible and the required VMware collections are installed.

The following systems must be reachable:

* ESXi
* NetBox
* Technitium DNS
* Foreman
* PXE/TFTP services

## Playbook Location

```bash
~/ANSIBLE/provision_hosts_el8/Foreman_provision_hosts_el8.yml
```

## Run Command

### Single Disk Installation

```bash
ansible-playbook ~/ANSIBLE/provision_hosts_el8/Foreman_provision_hosts_el8.yml -e "target_hosts=rocky-08-01 foreman_server=1 hostgroup=1"
```

### RAID Installation

```bash
ansible-playbook ~/ANSIBLE/provision_hosts_el8/Foreman_provision_hosts_el8.yml -e "target_hosts=rocky-08-01 foreman_server=1 hostgroup=2"
```

## Parameters

### target_hosts

Specify the hostname to provision.

Example:

```bash
target_hosts=rocky-08-01
```

Multiple hosts can be specified using commas:

```bash
target_hosts=rocky-08-01,rocky-08-02
```

Example:

```bash
ansible-playbook ~/ANSIBLE/provision_hosts_el8/Foreman_provision_hosts_el8.yml -e "target_hosts=rocky-08-01,rocky-08-02 foreman_server=1 hostgroup=1"
```

### foreman_server

Select the Foreman server.

| Value | Foreman Server                |
| ----- | ----------------------------- |
| `1`   | `https://rocky-08-01.vgs.com` |
| `2`   | `https://cent-07-01.vgs.com`  |

### hostgroup

Select the installation and disk configuration.

| Value | Configuration             |
| ----- | ------------------------- |
| `1`   | RockyLinux8.10-SingleDisk |
| `2`   | RockyLinux8.10-RAID       |

## Examples

### Example 1: Single Disk

Provision `rocky-08-01` using Foreman Server 1:

```bash
ansible-playbook ~/ANSIBLE/provision_hosts_el8/Foreman_provision_hosts_el8.yml -e "target_hosts=rocky-08-01 foreman_server=1 hostgroup=1"
```

### Example 2: RAID

Provision `rocky-08-01` using Foreman Server 1 with RAID:

```bash
ansible-playbook ~/ANSIBLE/provision_hosts_el8/Foreman_provision_hosts_el8.yml -e "target_hosts=rocky-08-01 foreman_server=1 hostgroup=2"
```

### Example 3: Multiple Hosts

Provision multiple hosts:

```bash
ansible-playbook ~/ANSIBLE/provision_hosts_el8/Foreman_provision_hosts_el8.yml -e "target_hosts=rocky-08-01,rocky-08-02 foreman_server=1 hostgroup=1"
```

## Provisioning Workflow

The automation performs the following operations:

### Step 1: Ensure VM Exists

Playbook:

```text
ensure_vm_exists.yml
```

The playbook:

* Retrieves selected devices from NetBox.
* Checks whether each VM exists on ESXi.
* Creates the VM if it does not exist.
* Configures CPU, memory, disk, network, and EFI firmware.
* Powers on the VM to obtain the MAC address.
* Powers off the VM.

### Step 2: Create DNS Records

Playbook:

```text
provision_hosts_dns.yml
```

The playbook:

* Retrieves the host IP address from NetBox.
* Creates an A record in Technitium DNS.
* Creates a PTR record.
* Verifies forward DNS.
* Verifies reverse DNS.

### Step 3: Create or Update Foreman Host

Playbook:

```text
provision_hosts_el8.yml
```

The playbook:

* Retrieves host information from NetBox.
* Retrieves the VM MAC address from ESXi.
* Retrieves the IP address from NetBox.
* Checks whether the host already exists in Foreman.
* Creates the host if it does not exist.
* Updates the existing host configuration.
* Configures the selected Host Group.
* Configures the operating system.
* Configures the installation medium.
* Configures the partition table.
* Configures Katello Content View and Lifecycle Environment.
* Enables build mode.
* Configures the Grub2 UEFI PXE loader.

### Step 4: Configure UEFI PXE Boot

Playbook:

```text
bootorder_uefi_el8.yml
```

The playbook:

* Powers off the VM.
* Configures EFI firmware.
* Sets PXE network boot first.
* Powers on the VM.
* Starts the Foreman provisioning process.
* Restores disk-first boot order.
* Waits for SSH port 22.
* Removes old SSH host keys.
* Accepts the new SSH host key.
* Verifies hostname.
* Verifies uptime.
* Verifies kernel.
* Verifies the installed operating system.

## Quick Reference

### Single Disk

```bash
ansible-playbook ~/ANSIBLE/provision_hosts_el8/Foreman_provision_hosts_el8.yml -e "target_hosts=HOSTNAME foreman_server=1 hostgroup=1"
```

### RAID

```bash
ansible-playbook ~/ANSIBLE/provision_hosts_el8/Foreman_provision_hosts_el8.yml -e "target_hosts=HOSTNAME foreman_server=1 hostgroup=2"
```

Replace `HOSTNAME` with the required NetBox hostname.

## Notes

* The hostname must exist in the configured NetBox cluster.
* The hostname should match the NetBox device name.
* Multiple hosts must be comma-separated.
* `hostgroup=1` provisions the Single Disk configuration.
* `hostgroup=2` provisions the RAID configuration.
* The VM is configured for UEFI boot.
* PXE boot is temporarily configured as the first boot device for provisioning.
* After provisioning starts, the boot order is restored to Disk first.
