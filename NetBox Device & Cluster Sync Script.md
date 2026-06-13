# NetBox Device & Cluster Sync Script

## Overview

This Bash script automates the synchronization of Linux servers into NetBox using the NetBox REST API.

The script can:

* Discover server details automatically through SSH
* Accept manual server information input
* Create or update devices in NetBox
* Create or reuse Cluster Types
* Create or reuse Cluster Groups
* Create or reuse Clusters
* Create and maintain network interfaces
* Assign MAC addresses
* Assign IP addresses
* Configure Primary IP on devices
* Clean up stale interfaces automatically

---

## Features

### Device Management

* Checks if a device already exists
* Creates a new device if missing
* Updates existing devices

### Cluster Management

Supports:

1. Existing NetBox clusters
2. New cluster creation

Automatically creates:

* Cluster Types
* Cluster Groups
* Clusters

when they do not already exist.

### Network Interface Management

* Creates interfaces when missing
* Removes stale interfaces from NetBox
* Keeps only the active interface

### MAC Address Management

* Creates MAC address objects
* Updates existing MAC assignments
* Sets interface primary MAC

### IP Address Management

* Creates IP objects
* Updates assignments
* Sets Device Primary IPv4

---

## Requirements

### Packages

Install required packages:

```bash
dnf install -y jq curl sshpass
```

or

```bash
apt install -y jq curl sshpass
```

### NetBox Requirements

The following must already exist:

* Site
* Device Type
* Device Role

Default values used:

| Setting       | Value |
| ------------- | ----- |
| SITE_ID       | 1     |
| DEVICETYPE_ID | 1     |
| DEVICEROLE_ID | 1     |

Adjust these IDs to match your environment.

---

## Configuration

Modify the following section:

```bash
NETBOX_URL="https://192.168.253.143/api"
NETBOX_TOKEN="YOUR_TOKEN"

SSH_USER="root"
SSH_PASS="Root@123"

SITE_ID=1
DEVICETYPE_ID=1
DEVICEROLE_ID=1
```

---

## Usage

Make executable:

```bash
chmod +x netbox_sync.sh
```

Run:

```bash
./netbox_sync.sh
```

---

## Workflow

### Step 1

Choose data source:

```text
1) Fetch automatically via SSH
2) Type manually
```

### Step 2

Choose cluster mode:

```text
1) Pick from existing NetBox clusters
2) Add to a specific/new cluster setup
```

### Step 3

Script performs:

* Device Sync
* Interface Sync
* MAC Sync
* IP Sync
* Cluster Assignment

### Step 4

Completion output:

```text
✅ Finished! hostname is updated.
Linked to Cluster ID: X
```

---

## Security Notes

Current script stores credentials in plain text:

```bash
SSH_PASS="Root@123"
NETBOX_TOKEN="xxxxxxxx"
```

Recommended improvements:

* Use environment variables
* Use SSH keys instead of passwords
* Store NetBox token securely
* Restrict API permissions

---

## Example NetBox Objects Created

### Device

```text
server01
```

### Interface

```text
ens192
```

### MAC Address

```text
00:50:56:AA:BB:CC
```

### IP Address

```text
192.168.253.100/24
```

### Cluster

```text
VMware-Production
```

---

# Script

```bash
awx-manage shell <<'EOF'
from awx.main.models import Project, JobTemplate

project = Project.objects.get(name="Inventory-Git-Repo")

jt, created = JobTemplate.objects.get_or_create(
    name="bootstrap-rocky-8-python"
)

jt.project = project
jt.playbook = "bootstrap-rocky-8-python.yml"
jt.job_type = "run"

from awx.main.models import Inventory

inventory = Inventory.objects.get(name="rocky-8-servers")

jt.inventory = inventory
jt.ask_inventory_on_launch = False

jt.save()

# Sync project
project.update()

if created:
    print("DONE: Job Template created with inventory prompt enabled.")
else:
    print("DONE: Job Template updated with inventory prompt enabled.")
EOF
```
