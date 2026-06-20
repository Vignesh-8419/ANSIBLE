# NetBox Configuration Context Deployment Guide

## Overview

This document describes the process of creating NetBox Tags and Configuration Contexts using the NetBox REST API.

These configuration contexts are used by:

* AWX / Ansible Automation
* VMware Provisioning
* PXE Deployments
* Repository Configuration
* CentOS to Rocky Migration
* EL8 Patch Management

The contexts provide centralized configuration data that can be dynamically consumed by NetBox, AWX, and automation workflows.

---

# Environment Details

| Parameter      | Value                       |
| -------------- | --------------------------- |
| NetBox Server  | 192.168.253.143             |
| API Endpoint   | https://192.168.253.143/api |
| Authentication | API Token                   |
| Context Type   | Configuration Context       |
| Scope          | Global via Tags             |

---

# Configuration Contexts Created

The following NetBox Configuration Contexts are deployed:

| Context Name          | Purpose                             |
| --------------------- | ----------------------------------- |
| vmware-awx-context    | VMware & AWX Provisioning           |
| pxe-centos-context    | CentOS PXE Installation             |
| pxe-rockyos-context   | Rocky Linux PXE Installation        |
| patch-context         | EL7 Patch Repository Configuration  |
| repo-config-context   | Repository Server Configuration     |
| centostorocky-context | CentOS 7 to Rocky Linux 8 Migration |
| patch-el8-context     | Rocky Linux 8 Patch Management      |

---

# Step 1 - Create NetBox Tags

Each configuration context requires a matching tag.

## Create All Tags

```bash
for TAG in \
"vmware-awx-context" \
"pxe-centos-context" \
"pxe-rockyos-context" \
"patch-context" \
"repo-config-context" \
"centostorocky-context" \
"patch-el8-context"
do
  curl -X POST -k \
    -H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
    -H "Content-Type: application/json" \
    https://192.168.253.143/api/extras/tags/ \
    -d "{\"name\": \"$TAG\", \"slug\": \"$TAG\"}"
done
```

---

# Step 2 - Create VMware AWX Context

## Purpose

Provides:

* vCenter details
* ESXi details
* DNS configuration
* Network configuration
* Golden Template references
* VM credentials

## API Request

```bash
curl -X POST -k \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
https://192.168.253.143/api/extras/config-contexts/ \
-d '{
    "name": "vmware-awx-context",
    "weight": 1000,
    "tags": ["vmware-awx-context"],
    "data": {
        "centos_template_name": "GOLDENTEMPLATE_CENTOS_07",
        "datacenter_name": "Datacenter",
        "datastore": "datastore1",
        "dns_primary": "192.168.253.1",
        "dns_servers": ["192.168.253.1","8.8.8.8"],
        "folder": "vm",
        "gateway": "192.168.253.2",
        "guest_domain": "vgs.com",
        "infra_dns_pass": "Root@123",
        "infra_dns_user": "root",
        "netmask": "255.255.255.0",
        "vcenter_hostname": "192.168.253.129",
        "vcenter_password": "Vigneshv12$",
        "vcenter_username": "administrator@vsphere.local",
        "vm_network": "VM Network",
        "exsi_hostname": "192.168.253.128",
        "exsi_password": "admin$22",
        "exsi_username": "root",
        "vm_root_password": "Root@123",
        "ansible_password": "Root@123",
        "vm_root_user": "root"
    }
}'
```

---

# Step 3 - Create PXE CentOS Context

## Purpose

Stores:

* CentOS Kickstart URL
* PXE Directory
* Golden Template Name
* VM Credentials

## API Request

```bash
curl -X POST -k \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
https://192.168.253.143/api/extras/config-contexts/ \
-d '{
    "name": "pxe-centos-context",
    "weight": 1000,
    "tags": ["pxe-centos-context"],
    "data": {
        "centos_kickstart_url": "http://192.168.253.136/repo/centos/kickstart/centos.cfg",
        "centos_template_name": "GOLDENTEMPLATE_CENTOS_07",
        "http_server": "192.168.253.136",
        "pxe_folder": "/var/lib/tftpboot",
        "vm_root_password": "Root@123",
        "vm_root_user": "root"
    }
}'
```

---

# Step 4 - Create PXE Rocky Linux Context

## Purpose

Stores:

* Rocky Linux Kickstart URL
* PXE Boot Configuration
* Golden Template Mapping

## API Request

```bash
curl -X POST -k \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
https://192.168.253.143/api/extras/config-contexts/ \
-d '{
    "name": "pxe-rockyos-context",
    "weight": 1000,
    "tags": ["pxe-rockyos-context"],
    "data": {
        "http_server": "192.168.253.136",
        "rockyos_kickstart_url": "http://192.168.253.136/repo/rocky8/kickstart/rockyos.cfg",
        "pxe_folder": "/var/lib/tftpboot",
        "rockyos_template_name": "GOLDENTEMPLATE_ROCKYOS_08",
        "vm_root_password": "Root@123",
        "vm_root_user": "root"
    }
}'
```

---

# Step 5 - Create Patch Context

## Purpose

Provides EL7 patch repository information.

## API Request

```bash
curl -X POST -k \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
https://192.168.253.143/api/extras/config-contexts/ \
-d '{
    "name": "patch-context",
    "weight": 1000,
    "tags": ["patch-context"],
    "data": {
        "dns_primary": "192.168.253.1",
        "guest_domain": "vgs.com",
        "httpd_server_url": "http://192.168.253.136/repo/",
        "iso_share_pass": "Vigneshv12$",
        "iso_share_user": "vigne",
        "repo_mount_path": "//192.168.29.241/ISO",
        "repo_mount_point": "/var/www/html/repo",
        "repositories": [
            {
                "folder": "centos",
                "id": "base",
                "name": "CentOS Base Repo"
            },
            {
                "folder": "installed_rhel7",
                "id": "patch",
                "name": "CentOS Patch Repo"
            }
        ]
    }
}'
```

---

# Step 6 - Create Repository Configuration Context

## Purpose

Provides repository mount information.

## API Request

```bash
curl -X POST -k \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
https://192.168.253.143/api/extras/config-contexts/ \
-d '{
    "name": "repo-config-context",
    "weight": 1000,
    "tags": ["repo-config-context"],
    "data": {
        "repo_mount_path": "//192.168.31.87/ISO",
        "repo_mount_point": "/var/www/html/repo",
        "iso_share_user": "vigne",
        "iso_share_pass": "Vigneshv12$",
        "http_server_ip": "192.168.253.136"
    }
}'
```

---

# Step 7 - Create CentOS to Rocky Migration Context

## Purpose

Used by migration playbooks to:

* Convert CentOS 7 systems
* Configure Vault repositories
* Enable Rocky Linux repositories

## API Request

```bash
curl -X POST -k \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
https://192.168.253.143/api/extras/config-contexts/ \
-d '{
    "name": "centostorocky-context",
    "weight": 1000,
    "tags": ["centostorocky-context"],
    "data": {
        "ansible_hostname": "ansible-server-01.vgs.com",
        "dns_primary": "192.168.253.1",
        "guest_domain": "vgs.com",
        "httpd_server_url": "http://192.168.253.136/repo/",
        "vault_repositories": [
            {
                "id": "base",
                "name": "CentOS Vault Base",
                "url": "https://vault.centos.org/7.9.2009/os/x86_64/"
            },
            {
                "id": "updates",
                "name": "CentOS Vault Updates",
                "url": "https://vault.centos.org/7.9.2009/updates/x86_64/"
            },
            {
                "id": "extras",
                "name": "CentOS Vault Extras",
                "url": "https://vault.centos.org/7.9.2009/extras/x86_64/"
            }
        ],
        "rocky8_repos": [
            {
                "id": "rocky8-baseos",
                "name": "Rocky Linux 8 - BaseOS",
                "folder": "rocky8/BaseOS/"
            },
            {
                "id": "rocky8-appstream",
                "name": "Rocky Linux 8 - AppStream",
                "folder": "rocky8/AppStream/"
            }
        ]
    }
}'
```

---

# Step 8 - Create EL8 Patch Context

## Purpose

Used for Rocky Linux 8 patching and repository management.

## API Request

```bash
curl -X POST -k \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
https://192.168.253.143/api/extras/config-contexts/ \
-d '{
    "name": "patch-el8-context",
    "weight": 1000,
    "tags": ["patch-el8-context"],
    "data": {
        "httpd_server_url": "http://192.168.253.136/repo/",
        "repositories": [
            {
                "id": "rocky8-baseos",
                "name": "Rocky Linux 8 BaseOS",
                "folder": "rocky8/BaseOS"
            },
            {
                "id": "rocky8-appstream",
                "name": "Rocky Linux 8 AppStream",
                "folder": "rocky8/Appstream"
            },
            {
                "id": "rocky8-rhel-installed",
                "name": "Rocky Linux 8 Installed RHEL",
                "folder": "installed_rhel8"
            }
        ]
    }
}'
```

---

# Verification Commands

## Verify Tags

```bash
curl -k \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
https://192.168.253.143/api/extras/tags/
```

## Verify Configuration Contexts

```bash
curl -k \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
https://192.168.253.143/api/extras/config-contexts/
```

## Verify Specific Context

```bash
curl -k \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
https://192.168.253.143/api/extras/config-contexts/?name=vmware-awx-context
```

# NetBox Custom Fields for Inventory Sync

## Overview

Create the following custom fields in NetBox to store hardware and operating system information collected by the inventory sync script.

---

## 1. CPU Count

```bash
curl -sk -X POST \
https://192.168.253.143/api/extras/custom-fields/ \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
-d '{
  "name":"cpu_count",
  "label":"CPU Count",
  "type":"integer",
  "object_types":["dcim.device"]
}'
```

---

## 2. RAM (GB)

```bash
curl -sk -X POST \
https://192.168.253.143/api/extras/custom-fields/ \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
-d '{
  "name":"ram_gb",
  "label":"RAM (GB)",
  "type":"integer",
  "object_types":["dcim.device"]
}'
```

---

## 3. Disk Size

```bash
curl -sk -X POST \
https://192.168.253.143/api/extras/custom-fields/ \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
-d '{
  "name":"disk_gb",
  "label":"Disk Size",
  "type":"text",
  "object_types":["dcim.device"]
}'
```

---

## 4. VM Type

```bash
curl -sk -X POST \
https://192.168.253.143/api/extras/custom-fields/ \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
-d '{
  "name":"vm_type",
  "label":"VM Type",
  "type":"text",
  "object_types":["dcim.device"]
}'
```

---

## 5. Kernel

```bash
curl -sk -X POST \
https://192.168.253.143/api/extras/custom-fields/ \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
-d '{
  "name":"kernel",
  "label":"Kernel",
  "type":"text",
  "object_types":["dcim.device"]
}'
```

---

# Script Modification

After device creation/update and after obtaining `DEVICE_ID`, add the following block to update NetBox custom fields automatically:

```bash
curl -sk -X PATCH \
"$NETBOX_URL/dcim/devices/$DEVICE_ID/" \
-H "$HDR" \
-H "Authorization: Token $NETBOX_TOKEN" \
-d "{
  \"custom_fields\": {
    \"cpu_count\": $CPU_COUNT,
    \"ram_gb\": $RAM_GB,
    \"disk_gb\": \"$DISK_SIZE\",
    \"vm_type\": \"$VMTYPE\",
    \"kernel\": \"$KERNEL\"
  }
}" >/dev/null
```

---

## Data Stored in NetBox

| Field     | Example Value                  |
| --------- | ------------------------------ |
| CPU Count | 4                              |
| RAM (GB)  | 3                              |
| Disk Size | 100 GB                         |
| VM Type   | vmware                         |
| Kernel    | 4.18.0-553.134.1.el8_10.x86_64 |

---

## Verification

Verify custom field values for a device:

```bash
curl -sk \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
"https://192.168.253.143/api/dcim/devices/?name=ansible-server-01.vgs.com" \
| jq '.results[0].custom_fields'
```

Example output:

```json
{
  "cpu_count": 4,
  "disk_gb": "100 GB",
  "kernel": "4.18.0-553.134.1.el8_10.x86_64",
  "ram_gb": 3,
  "vm_type": "vmware"
}
```

# NetBox Cluster ID Reset Procedure

## Objective

Recreate NetBox clusters so that:

| Cluster Name      | Desired ID |
| ----------------- | ---------- |
| rocky-8-servers   | 1          |
| centos-07-servers | 2          |

> **Note:** This procedure is intended for lab environments only.

---

## Step 1: Check Devices Attached to Cluster

```bash
curl -sk \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
"https://192.168.253.143/api/dcim/devices/?cluster_id=3" \
| jq '.count'
```

If devices exist, either:

* Move them to another cluster
* Or note the device names before deleting clusters

---

## Step 2: Delete Existing Clusters

```bash
curl -sk -X DELETE \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
https://192.168.253.143/api/virtualization/clusters/3/
```

```bash
curl -sk -X DELETE \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
https://192.168.253.143/api/virtualization/clusters/4/
```

---

## Step 3: Connect to PostgreSQL

```bash
sudo -u postgres psql
```

Connect to the NetBox database:

```sql
\c netbox
```

---

## Step 4: Reset Cluster ID Sequence

```sql
ALTER SEQUENCE virtualization_cluster_id_seq RESTART WITH 1;
```

Exit PostgreSQL:

```sql
\q
```

---

## Step 5: Verify Sequence Name (Recommended)

Before resetting the sequence, verify the exact sequence name:

```bash
sudo -u postgres psql -d netbox -c "\ds *cluster*"
```

Example output:

```text
public | virtualization_cluster_id_seq | sequence | netbox
```

If the sequence name differs, use the actual sequence name returned by PostgreSQL.

---

## Step 6: Recreate rocky-8-servers First

```bash
curl -sk -X POST \
https://192.168.253.143/api/virtualization/clusters/ \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
-d '{
  "name":"rocky-8-servers",
  "type":1,
  "group":2,
  "site":1
}'
```

Expected Result:

```text
rocky-8-servers -> ID 1
```

---

## Step 7: Recreate centos-07-servers

```bash
curl -sk -X POST \
https://192.168.253.143/api/virtualization/clusters/ \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
-H "Content-Type: application/json" \
-d '{
  "name":"centos-07-servers",
  "type":1,
  "group":1,
  "site":1
}'
```

Expected Result:

```text
centos-07-servers -> ID 2
```

---

## Verification

List all clusters:

```bash
curl -sk \
-H "Authorization: Token 83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd" \
https://192.168.253.143/api/virtualization/clusters/ \
| jq '.results[] | {id,name}'
```

Expected Output:

```json
{
  "id": 1,
  "name": "rocky-8-servers"
}
{
  "id": 2,
  "name": "centos-07-servers"
}
```


---

# Summary

This configuration establishes a centralized NetBox Configuration Context repository that provides automation data for:

* VMware Provisioning
* AWX Deployments
* PXE Boot Automation
* Repository Management
* EL7 Patch Automation
* EL8 Patch Automation
* CentOS-to-Rocky Migration Workflows

Using NetBox Configuration Contexts ensures that all automation platforms consume a consistent source of truth for infrastructure configuration.
