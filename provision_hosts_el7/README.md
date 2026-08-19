# Foreman CentOS 7 Provisioning

## Overview

This Ansible automation provisions CentOS 7 hosts using NetBox, ESXi, Technitium DNS, and Foreman.

The main playbook is:

```bash
Foreman_provision_hosts_el7.yml
```

It runs the following playbooks in order:

```text
1. ensure_vm_exists.yml
2. provision_hosts_dns.yml
3. provision_hosts_el7.yml
4. bootorder_uefi_el7.yml
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
~/ANSIBLE/provision_hosts_el7/Foreman_provision_hosts_el7.yml
```

## Run Command

### Single Disk Installation

```bash
ansible-playbook ~/ANSIBLE/provision_hosts_el7/Foreman_provision_hosts_el7.yml -e "target_hosts=cent-07-02 foreman_server=1 hostgroup=1"
```

### RAID Installation

```bash
ansible-playbook ~/ANSIBLE/provision_hosts_el7/Foreman_provision_hosts_el7.yml -e "target_hosts=cent-07-02 foreman_server=1 hostgroup=2"
```

## Parameters

### target_hosts

Specify the hostname to provision.

Example:

```bash
target_hosts=cent-07-02
```

Multiple hosts can be specified using commas:

```bash
target_hosts=cent-07-02,cent-07-03
```

Example:

```bash
ansible-playbook ~/ANSIBLE/provision_hosts_el7/Foreman_provision_hosts_el7.yml -e "target_hosts=cent-07-02,cent-07-03 foreman_server=1 hostgroup=1"
```

### foreman_server

Select the Foreman server.

| Value | Foreman Server |
| ----- | -------------- |
| `1` | `https://rocky-08-01.vgs.com` |
| `2` | `https://cent-07-01.vgs.com` |

### hostgroup

Select the installation and disk configuration.

| Value | Configuration |
| ----- | ------------- |
| `1` | CentOSLinux7-SingleDisk |
| `2` | CentOSLinux7-RAID |

## Examples

### Example 1: Single Disk

Provision `cent-07-02` using Foreman Server 1:

```bash
ansible-playbook ~/ANSIBLE/provision_hosts_el7/Foreman_provision_hosts_el7.yml -e "target_hosts=cent-07-02 foreman_server=1 hostgroup=1"
```

### Example 2: RAID

Provision `cent-07-02` using Foreman Server 1 with RAID:

```bash
ansible-playbook ~/ANSIBLE/provision_hosts_el7/Foreman_provision_hosts_el7.yml -e "target_hosts=cent-07-02 foreman_server=1 hostgroup=2"
```

### Example 3: Multiple Hosts

Provision multiple hosts:

```bash
ansible-playbook ~/ANSIBLE/provision_hosts_el7/Foreman_provision_hosts_el7.yml -e "target_hosts=cent-07-02,cent-07-03 foreman_server=1 hostgroup=1"
```

## Provisioning Workflow

The automation performs the following operations:

### Step 1: Ensure VM Exists

Playbook:

```text
ensure_vm_exists.yml
```

The playbook:

* Retrieves selected devices from the `centos-07-servers` cluster in NetBox.
* Checks whether each VM exists on ESXi.
* Creates the VM if it does not exist.
* Configures CPU, memory, disk, network, and EFI firmware.
* Powers on the VM to obtain the MAC address.
* Waits for ESXi to assign the MAC address.
* Powers off the VM.
* Retrieves and displays the VM information.

### Step 2: Create DNS Records

Playbook:

```text
provision_hosts_dns.yml
```

The playbook:

* Retrieves the host IP address from NetBox.
* Uses the hostname to create the FQDN with the `vgs.com` domain.
* Creates an A record in Technitium DNS.
* Creates a PTR record.
* Verifies forward DNS.
* Verifies reverse DNS.

### Step 3: Create or Update Foreman Host

Playbook:

```text
provision_hosts_el7.yml
```

The playbook:

* Retrieves selected host information from NetBox.
* Retrieves the VM MAC address from ESXi.
* Retrieves the IP address from NetBox.
* Checks whether the host already exists in Foreman.
* Resolves the `vgs-subnet-centos` subnet from Foreman.
* Creates the host if it does not exist.
* Updates the existing host configuration.
* Configures the selected Host Group.
* Configures the operating system.
* Configures the installation medium.
* Configures the partition table.
* Configures Katello Content View and Lifecycle Environment.
* Enables build mode.
* Configures the Grub2 UEFI PXE loader.
* Verifies the final Foreman host configuration.

### Step 4: Configure UEFI PXE Boot

Playbook:

```text
bootorder_uefi_el7.yml
```

The playbook:

* Retrieves selected VMs from the `centos-07-servers` cluster in NetBox.
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
ansible-playbook ~/ANSIBLE/provision_hosts_el7/Foreman_provision_hosts_el7.yml -e "target_hosts=HOSTNAME foreman_server=1 hostgroup=1"
```

### RAID

```bash
ansible-playbook ~/ANSIBLE/provision_hosts_el7/Foreman_provision_hosts_el7.yml -e "target_hosts=HOSTNAME foreman_server=1 hostgroup=2"
```

Replace `HOSTNAME` with the required NetBox hostname.

## Notes

* The hostname must exist in the `centos-07-servers` NetBox cluster.
* The hostname should match the short hostname of the NetBox device.
* For example, a NetBox device named `cent-07-02.vgs.com` is selected using `target_hosts=cent-07-02`.
* Multiple hosts must be comma-separated.
* `hostgroup=1` provisions the CentOSLinux7-SingleDisk configuration.
* `hostgroup=2` provisions the CentOSLinux7-RAID configuration.
* The VM is configured for UEFI boot.
* PXE boot is temporarily configured as the first boot device for provisioning.
* After provisioning starts, the boot order is restored to Disk first.
* The Foreman host is configured with the `Grub2 UEFI` PXE loader.
* The automation waits up to 3600 seconds for SSH to become available.
