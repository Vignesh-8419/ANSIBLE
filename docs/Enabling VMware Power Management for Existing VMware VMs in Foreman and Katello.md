# README.md

# Enabling VMware Power Management for Existing VMware VMs in Foreman/Katello

## Overview

This document describes the troubleshooting and resolution process for enabling VMware power management options in Foreman/Katello for existing VMware virtual machines.

### Environment

| Component               | Version             |
| ----------------------- | ------------------- |
| Foreman                 | 3.12.1              |
| Katello                 | 4.14.3              |
| Operating System        | Rocky Linux 8       |
| Virtualization Platform | VMware              |
| Host Example            | rocky-08-01.vgs.com |

---

## Problem Statement

The following message was displayed in Foreman:

> Power options are not enabled on this host

The affected host:

```
rocky-08-01.vgs.com
```

was running as a VMware virtual machine.

---

## Initial Investigation

### Verify Host Status

Execute:

```bash
hammer -u admin -p '<password>' host info \
  --name rocky-08-01.vgs.com | egrep "Managed|Compute"
```

Output:

```text
Managed:                  no
```

Observation:

* Host was unmanaged.
* No Compute Resource was associated.

---

## Verify Existing Compute Resources

Execute:

```bash
hammer -u admin -p '<password>' compute-resource list
```

Output:

```text
---|------|---------
ID | NAME | PROVIDER
---|------|---------
```

Observation:

* No Compute Resources were configured.

---

## UI Symptoms

In Foreman:

```
Infrastructure
→ Compute Resources
→ Create Compute Resource
```

The Provider dropdown was empty.

---

## Verify Available Providers

### Hammer CLI

Execute:

```bash
hammer compute-resource create --help
```

Output included VMware-related parameters:

```text
--server VALUE
--user VALUE
--password VALUE
--caching-enabled BOOLEAN
```

Observation:

* Hammer recognized VMware support.

---

## Check Compute Providers from Rails Console

Execute:

```bash
foreman-rake console
```

Run:

```ruby
ComputeResource.providers
```

Initial Output:

```ruby
{}
```

Observation:

* Foreman had no registered compute providers.

---

## Verify VMware Gems

Execute:

```bash
rpm -q rubygem-fog-vsphere
```

Output:

```text
package rubygem-fog-vsphere is not installed
```

Check repository availability:

```bash
dnf provides '*fog-vsphere*'
```

Output:

```text
rubygem-fog-vsphere-3.7.0-1.el8.noarch
Repo : foreman
```

---

## Install VMware Support

Install VMware provider gem:

```bash
dnf install -y rubygem-fog-vsphere
```

Restart Foreman services:

```bash
foreman-maintain service restart
```

---

## Enable Compute Providers

Check installer options:

```bash
foreman-installer --full-help | grep -i compute
```

Output:

```text
--[no-]enable-foreman-compute-vmware
--[no-]enable-foreman-compute-libvirt
```

Observation:

* Compute providers were disabled.

Enable required providers:

```bash
foreman-installer \
  --enable-foreman-compute-vmware \
  --enable-foreman-compute-libvirt
```

Allow installer execution to complete successfully.

---

## Verify Compute Providers

Execute:

```bash
foreman-rake console
```

Run:

```ruby
ComputeResource.providers
```

Expected Output:

```ruby
{
  "Libvirt"=>"Foreman::Model::Libvirt",
  "Vmware"=>"Foreman::Model::Vmware"
}
```

Observation:

* VMware and Libvirt providers successfully registered.

Exit console:

```ruby
exit
```

---

## Optional Console Warning

The following warning may appear:

```text
Errno::EACCES:
Permission denied @ rb_sysopen -
/usr/share/foreman/config/irbrc_history
```

This warning is harmless and does not affect Foreman functionality.

Optional fix:

```bash
touch /usr/share/foreman/config/irbrc_history
chown foreman:foreman /usr/share/foreman/config/irbrc_history
chmod 664 /usr/share/foreman/config/irbrc_history
```

---

# Configure VMware Compute Resource

Navigate to:

```
Infrastructure
→ Compute Resources
→ Create Compute Resource
```

Provider:

```
VMware
```

---

## vCenter Configuration

Populate the following fields:

| Field      | Value                                                             |
| ---------- | ----------------------------------------------------------------- |
| Name       | VMware                                                            |
| Provider   | VMware                                                            |
| Server     | vCenter FQDN/IP                                                   |
| User       | [administrator@vsphere.local](mailto:administrator@vsphere.local) |
| Password   | VMware password                                                   |
| Datacenter | VMware Datacenter Name                                            |

---

## Standalone ESXi Configuration

Populate the following fields:

| Field      | Value            |
| ---------- | ---------------- |
| Name       | ESXi             |
| Provider   | VMware           |
| Server     | ESXi Hostname/IP |
| User       | root             |
| Password   | ESXi password    |
| Datacenter | ha-datacenter    |

---

# Import Existing VMware Virtual Machines

After saving the Compute Resource, navigate to:

```
Infrastructure
→ Compute Resources
→ VMware
→ Virtual Machines
→ Import
```

Select the existing VM:

```
rocky-08-01
```

Import the virtual machine into Foreman.

## Bulk import

``` text
#!/bin/bash

USER="admin"
PASS="password"
CR_ID=1

for VM in server01 server02 server03; do
    echo "Importing $VM..."

    hammer host create \
        --name "$VM" \
        --compute-resource-id "$CR_ID" \
        --managed true \
        --organization "Default Organization" \
        --location "Default Location"
done
```

---

# Verify Host Association

Execute:

```bash
hammer -u admin -p '<password>' host info \
  --name rocky-08-01.vgs.com | egrep "Managed|Compute"
```

Expected Output:

```text
Managed:                  yes
Compute resource:         VMware
```

---

# Result

After importing the VM and associating it with the VMware Compute Resource:

* Power On becomes available.
* Power Off becomes available.
* Reboot becomes available.
* VMware lifecycle operations can be performed directly from Foreman.

---

# Root Cause

The issue occurred because:

1. The VMware VM was imported as an unmanaged host.
2. No Compute Resources were configured in Foreman.
3. VMware compute provider support was disabled during the original Foreman/Katello installation.
4. Foreman therefore had no registered compute providers.

---

# Resolution Summary

```text
Issue:
Power options are not enabled on this host.

Cause:
VMware compute providers were disabled and no Compute Resource existed.

Resolution:
Install VMware gem, enable VMware compute support using foreman-installer,
configure VMware Compute Resource, and import the existing VM.
```
