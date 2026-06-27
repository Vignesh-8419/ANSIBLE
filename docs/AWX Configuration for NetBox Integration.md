# AWX NetBox Integration, Inventory Management & Golden Template SOP

![AWX](https://img.shields.io/badge/AWX-Automation-blue)
![NetBox](https://img.shields.io/badge/NetBox-Integration-green)
![Ansible](https://img.shields.io/badge/Ansible-Automation-red)

---

## Overview

This document configures the following AWX components:

* Custom NetBox Credential Type
* NetBox Production Credential
* AWX Inventories
* SCM Inventory Sources
* Git-Based Projects
* Job Templates
* Inventory Prompting at Launch
* Optional Hardcoded Inventory Assignment

---

## Architecture

```text
GitHub Repository
        │
        ▼
 Inventory-Git-Repo Project
        │
        ▼
 Inventory Sources
        │
        ▼
 AWX Inventories
        │
        ▼
 Job Templates
        │
        ▼
 Managed Servers
```

---

## Prerequisites

| Requirement       | Value                                   |
| ----------------- | --------------------------------------- |
| AWX               | Running in Kubernetes                   |
| Git Repository    | https://github.com/Vignesh-8419/ANSIBLE |
| NetBox URL        | https://rocky-08-03.vgs.com/            |
| NetBox API Token  | Valid API Token                         |
| Kubernetes Access | kubectl configured                      |

---

# Step 1 - Connect to AWX Task Pod

## Command

```bash
kubectl exec -it awx-server-task-76cf8b6c9f-8vgfj \
-n awx \
-c awx-server-task \
-- bash
```
## (OR)

```bash
kubectl exec -it $(kubectl get pods -n awx --no-headers | awk '/awx-server-task/ {print $1; exit}') \
-n awx -c awx-server-task -- bash
```

## Expected Result

You should receive a shell prompt inside the AWX task container.

---

# Step 2 - Create NetBox Credential Type and Credential

## Purpose

Creates:

* Credential Type: Netbox API Token
* Credential: Netbox Production Credential

## Command

```bash
awx-manage shell <<EOF
from awx.main.models import CredentialType, Credential, Organization

ctype, created = CredentialType.objects.get_or_create(
    name="Netbox API Token",
    defaults={
        "kind": "cloud",
        "inputs": {
            "fields": [
                {"id": "netbox_url", "type": "string", "label": "NetBox URL"},
                {"id": "netbox_token", "type": "string", "label": "NetBox API Token", "secret": True}
            ],
            "required": ["netbox_token"]
        },
        "injectors": {
            "env": {
                "NETBOX_API": "{{ netbox_url }}",
                "NETBOX_TOKEN": "{{ netbox_token }}"
            }
        }
    }
)

print(f"Credential Type {'created' if created else 'already exists'}.")

org = Organization.objects.get(name="Default")

cred, created = Credential.objects.get_or_create(
    name="Netbox Production Credential",
    defaults={
        "credential_type": ctype,
        "organization": org,
        "inputs": {
            "netbox_url": "https://rocky-08-03.vgs.com/",
            "netbox_token": "83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd"
        }
    }
)

print(f"Credential {'created' if created else 'already exists'}.")
EOF
```

## Verification

Navigate to:

```text
Resources → Credentials
```

Verify:

* Netbox API Token
* Netbox Production Credential

## Machine Credential

```bash
awx-manage shell <<'EOF'
from awx.main.models import Credential, CredentialType, Organization

org = Organization.objects.get(name="Default")
ctype = CredentialType.objects.get(kind="ssh")

cred, created = Credential.objects.get_or_create(
    name="Linux Root Credential",
    organization=org,
    credential_type=ctype,
    defaults={
        "inputs": {
            "username": "root",
            "password": "Root@123"
        }
    }
)

print(f"Credential {'created' if created else 'already exists'}: {cred.name}")
EOF
```

## Verification

Navigate to:

```text
Resources → Credentials
```
---

# Step 3 - Create AWX Inventories

## Inventories

* rocky-8-servers
* centos-07-servers

## Command

```bash
awx-manage shell <<EOF
from awx.main.models import Inventory, Organization

org = Organization.objects.get(name="Default")

inventories = [
    "centos-07-servers",
    "rocky-8-servers"
]

for inv_name in inventories:
    inv, created = Inventory.objects.get_or_create(
        name=inv_name,
        organization=org
    )

    print(
        f"Inventory '{inv_name}' "
        f"{'created' if created else 'already exists'}."
    )
EOF
```

## Verification

```text
Resources → Inventories
```

Confirm:

* rocky-8-servers
* centos-07-servers

---

# Step 4 - Configure SCM Inventory Sources

## Repository

```text
https://github.com/Vignesh-8419/ANSIBLE
```

## Inventory Mapping

| Inventory         | Inventory File                  |
| ----------------- | ------------------------------- |
| rocky-8-servers   | rocky-8-servers_inventory.yml   |
| centos-07-servers | centos-07-servers_inventory.yml |

## Command

```bash
awx-manage shell <<EOF
from awx.main.models import Inventory, InventorySource, Project, Organization

org = Organization.objects.get(name="Default")

repo_url = "https://github.com/Vignesh-8419/ANSIBLE"

project, created = Project.objects.get_or_create(
    name="Inventory-Git-Repo",
    defaults={
        "organization": org,
        "scm_type": "git",
        "scm_url": repo_url,
        "scm_update_on_launch": False
    }
)

# Disable Update Revision on Launch
project.scm_update_on_launch = False
project.save()

print("Project 'Inventory-Git-Repo' configured.")
print(f"Update Revision on Launch = {project.scm_update_on_launch}")

configs = [
    {
        "inv_name": "rocky-8-servers",
        "file": "rocky-8-servers_inventory.yml"
    },
    {
        "inv_name": "centos-07-servers",
        "file": "centos-07-servers_inventory.yml"
    }
]

for cfg in configs:
    inv = Inventory.objects.get(
        name=cfg["inv_name"],
        organization=org
    )

    source, created = InventorySource.objects.get_or_create(
        name=cfg["inv_name"],
        inventory=inv,
        defaults={
            "source": "scm",
            "source_project": project,
            "source_path": cfg["file"],
            "overwrite": True,
            "update_on_launch": False
        }
    )

    # Disable Update on Launch
    source.source = "scm"
    source.source_project = project
    source.source_path = cfg["file"]
    source.overwrite = True
    source.update_on_launch = False
    source.save()

    print(
        f"Source for {cfg['inv_name']} configured. "
        f"Update on Launch = {source.update_on_launch}"
    )

EOF
```

# Create localhost in both inventories

```text
awx-manage shell <<'EOF'
from awx.main.models import Inventory, Host

for inventory_name in ["centos-07-servers", "rocky-8-servers"]:
    inventory = Inventory.objects.get(name=inventory_name)

    host, created = Host.objects.get_or_create(
        name="localhost",
        inventory=inventory,
        defaults={
            "variables": "ansible_connection: local\nansible_python_interpreter: /usr/bin/python3"
        }
    )

    if not created:
        host.variables = "ansible_connection: local\nansible_python_interpreter: /usr/bin/python3"
        host.save()

    print(f"{inventory_name}: localhost {'created' if created else 'updated'}")
EOF
```

---

# Step 5 - Create Golden Template Project and Job Template

## Project

```text
ROCKYOS-VM-TEMPLATE
```

## Playbook

```text
ROCKYOS-VM-TEMPLATE/ROCKYOS-VM-TEMPLATE.yml
```

## Command

```text
awx-manage shell <<EOF
from awx.main.models import Inventory, Project, JobTemplate

# 1. Fetch existing dependencies
try:
    project = Project.objects.get(name="Inventory-Git-Repo")
    inventory = Inventory.objects.get(name="rocky-8-servers")
except (Project.DoesNotExist, Inventory.DoesNotExist) as e:
    print(f"Error: Missing required dependency. {e}")
    exit(1)

# 2. Create or Update the Job Template
jt, created = JobTemplate.objects.get_or_create(
    name="ROCKYOS-VM-TEMPLATE",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "ROCKYOS-VM-TEMPLATE/ROCKYOS-VM-TEMPLATE.yml",
        "ask_inventory_on_launch": False,  # As per Step 6 (Hardcoded option)
        "ask_limit_on_launch": True
    }
)

# 3. Update attributes if it already existed
if not created:
    jt.project = project
    jt.inventory = inventory
    jt.playbook = "ROCKYOS-VM-TEMPLATE/ROCKYOS-VM-TEMPLATE.yml"
    jt.ask_inventory_on_launch = False
    jt.ask_limit_on_launch = True
    jt.save()

print(f"Job Template 'ROCKYOS-VM-TEMPLATE' {'created' if created else 'updated'} successfully.")
EOF
```

## Project

```text
CENTOS-VM-TEMPLATE
```

## Playbook

```text
CENTOS-VM-TEMPLATE/CENTOS-VM-TEMPLATE.yml
```

```text
awx-manage shell <<EOF
from awx.main.models import Inventory, Project, JobTemplate

# 1. Fetch existing dependencies
try:
    project = Project.objects.get(name="Inventory-Git-Repo")
    inventory = Inventory.objects.get(name="centos-07-servers")
except (Project.DoesNotExist, Inventory.DoesNotExist) as e:
    print(f"Error: Missing required dependency. {e}")
    exit(1)

# 2. Create or Update the Job Template
jt, created = JobTemplate.objects.get_or_create(
    name="CENTOS-VM-TEMPLATE",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "CENTOS-VM-TEMPLATE/CENTOS-VM-TEMPLATE.yml",
        "ask_inventory_on_launch": False,  # As per Step 6 (Hardcoded option)
        "ask_limit_on_launch": True
    }
)

# 3. Update attributes if it already existed
if not created:
    jt.project = project
    jt.inventory = inventory
    jt.playbook = "CENTOS-VM-TEMPLATE/CENTOS-VM-TEMPLATE.yml"
    jt.ask_inventory_on_launch = False
    jt.ask_limit_on_launch = True
    jt.save()

print(f"Job Template 'CENTOS-VM-TEMPLATE' {'created' if created else 'updated'} successfully.")
EOF
```

## Inventory Prompt

``` text
awx-manage shell <<EOF
from awx.main.models import Project, JobTemplate

project = Project.objects.get(name="Inventory-Git-Repo")

jt, created = JobTemplate.objects.get_or_create(
    name="Local_DNS",
    defaults={
        "project": project,
        "playbook": "Local_DNS.yml",
        "ask_inventory_on_launch": True,
        "ask_limit_on_launch": True
    }
)

if not created:
    jt.project = project
    jt.playbook = "Local_DNS.yml"
    jt.inventory = None
    jt.ask_inventory_on_launch = True
    jt.ask_limit_on_launch = True
    jt.save()

print("Done")
EOF
```

## Patching

## el7 Patching

```text
awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

# Dependencies
try:
    project = Project.objects.get(name="Inventory-Git-Repo")
    inventory = Inventory.objects.get(name="centos-07-servers")
    credential = Credential.objects.get(name="Linux Root Credential")
except (Project.DoesNotExist,
        Inventory.DoesNotExist,
        Credential.DoesNotExist) as e:
    print(f"Error: Missing required dependency. {e}")
    exit(1)

# Create or Update Job Template
jt, created = JobTemplate.objects.get_or_create(
    name="Offline_Patching_el7",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "offline_patching_el7/offline-patch-el7.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": True
    }
)

if not created:
    jt.project = project
    jt.inventory = inventory
    jt.playbook = "offline_patching_el7/offline-patch-el7.yml"
    jt.ask_inventory_on_launch = False
    jt.ask_limit_on_launch = True
    jt.save()

# Assign Credential
jt.credentials.clear()
jt.credentials.add(credential)

print(
    f"Job Template 'Offline_Patching_el7' "
    f"{'created' if created else 'updated'} successfully."
)
print(f"Credential assigned: {credential.name}")
EOF
```

## el8 Patching

```text
awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

# Dependencies
try:
    project = Project.objects.get(name="Inventory-Git-Repo")
    inventory = Inventory.objects.get(name="rocky-8-servers")
    credential = Credential.objects.get(name="Linux Root Credential")
except (Project.DoesNotExist,
        Inventory.DoesNotExist,
        Credential.DoesNotExist) as e:
    print(f"Error: Missing required dependency. {e}")
    exit(1)

# Create or Update Job Template
jt, created = JobTemplate.objects.get_or_create(
    name="Offline_Patching_el8",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "offline_patching_el8/offline-patch-el8.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": True
    }
)

if not created:
    jt.project = project
    jt.inventory = inventory
    jt.playbook = "offline_patching_el8/offline-patch-el8.yml"
    jt.ask_inventory_on_launch = False
    jt.ask_limit_on_launch = True
    jt.save()

# Assign Credential
jt.credentials.clear()
jt.credentials.add(credential)

print(
    f"Job Template 'Offline_Patching_el8' "
    f"{'created' if created else 'updated'} successfully."
)
print(f"Credential assigned: {credential.name}")
EOF
```

## SELINUX

## Disable_SELinux_el7

```text

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

# Dependencies
try:
    project = Project.objects.get(name="Inventory-Git-Repo")
    inventory = Inventory.objects.get(name="centos-07-servers")
    credential = Credential.objects.get(name="Linux Root Credential")
except (Project.DoesNotExist,
        Inventory.DoesNotExist,
        Credential.DoesNotExist) as e:
    print(f"Error: Missing required dependency. {e}")
    exit(1)

# Create or Update Job Template
jt, created = JobTemplate.objects.get_or_create(
    name="Disable_SELinux_el7",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "Disable_SELinux_el7.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": True
    }
)

if not created:
    jt.project = project
    jt.inventory = inventory
    jt.playbook = "Disable_SELinux_el7.yml"
    jt.ask_inventory_on_launch = False
    jt.ask_limit_on_launch = True
    jt.save()

# Assign Credential
jt.credentials.clear()
jt.credentials.add(credential)

print(
    f"Job Template 'Disable_SELinux_el7' "
    f"{'created' if created else 'updated'} successfully."
)
print(f"Credential assigned: {credential.name}")
EOF
```

## SELINUX

## Disable_SELinux_el8

```text
awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

# Dependencies
try:
    project = Project.objects.get(name="Inventory-Git-Repo")
    inventory = Inventory.objects.get(name="rocky-8-servers")
    credential = Credential.objects.get(name="Linux Root Credential")
except (Project.DoesNotExist,
        Inventory.DoesNotExist,
        Credential.DoesNotExist) as e:
    print(f"Error: Missing required dependency. {e}")
    exit(1)

# Create or Update Job Template
jt, created = JobTemplate.objects.get_or_create(
    name="Disable_SELinux_el8",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "Disable_SELinux_el8.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": True
    }
)

if not created:
    jt.project = project
    jt.inventory = inventory
    jt.playbook = "Disable_SELinux_el8.yml"
    jt.ask_inventory_on_launch = False
    jt.ask_limit_on_launch = True
    jt.save()

# Assign Credential
jt.credentials.clear()
jt.credentials.add(credential)

print(
    f"Job Template 'Disable_SELinux_el8' "
    f"{'created' if created else 'updated'} successfully."
)
print(f"Credential assigned: {credential.name}")
EOF
```

## Workflow

## CENTOS-VM-TEMPLATE-WF

```text
awx-manage shell <<'EOF'
from awx.main.models import (
    WorkflowJobTemplate,
    WorkflowJobTemplateNode,
    JobTemplate,
    Credential,
    Inventory,
    Organization
)

ORG_NAME = "Default"
WORKFLOW_NAME = "CENTOS-VM-TEMPLATE-WF"

JT1_NAME = "CENTOS-VM-TEMPLATE"
JT2_NAME = "Disable_SELinux_el7"
JT3_NAME = "Offline_Patching_el7"

CREDENTIAL_NAME = "Linux Root Credential"
INVENTORY_NAME = "centos-07-servers"

org = Organization.objects.get(name=ORG_NAME)

jt1 = JobTemplate.objects.get(name=JT1_NAME)
jt2 = JobTemplate.objects.get(name=JT2_NAME)
jt3 = JobTemplate.objects.get(name=JT3_NAME)

cred = Credential.objects.get(name=CREDENTIAL_NAME)
inv = Inventory.objects.get(name=INVENTORY_NAME)

wf, created = WorkflowJobTemplate.objects.get_or_create(
    name=WORKFLOW_NAME,
    organization=org
)

# Remove existing nodes if re-running
wf.workflow_job_template_nodes.all().delete()

# Default inventory
wf.inventory = inv

# Prompt on launch
wf.ask_limit_on_launch = True
wf.ask_credential_on_launch = True
wf.ask_inventory_on_launch = True

wf.save()

# Attach default credential
wf.credentials.clear()
wf.credentials.add(cred)

# Create workflow nodes
n1 = WorkflowJobTemplateNode.objects.create(
    workflow_job_template=wf,
    unified_job_template=jt1
)

n2 = WorkflowJobTemplateNode.objects.create(
    workflow_job_template=wf,
    unified_job_template=jt2
)

n3 = WorkflowJobTemplateNode.objects.create(
    workflow_job_template=wf,
    unified_job_template=jt3
)

# Success path
n1.success_nodes.add(n2)
n2.success_nodes.add(n3)

print(f"Workflow '{wf.name}' created/updated successfully.")
print(f"Inventory: {inv.name}")
print(f"Credential: {cred.name}")
print(f"J1 -> {jt1.name}")
print(f"J2 -> {jt2.name}")
print(f"J3 -> {jt3.name}")
print()
print("Execution Order:")
print(f"  {jt1.name}")
print("        │")
print("        ▼")
print(f"  {jt2.name}")
print("        │")
print("        ▼")
print(f"  {jt3.name}")
print()
print("Prompt on Launch:")
print("  Inventory  = True")
print("  Limit      = True")
print("  Credential = True")

EOF
```

## ROCKYOS-VM-TEMPLATE-WF

```text
awx-manage shell <<'EOF'
from awx.main.models import (
    WorkflowJobTemplate,
    WorkflowJobTemplateNode,
    JobTemplate,
    Credential,
    Inventory,
    Organization
)

ORG_NAME = "Default"
WORKFLOW_NAME = "ROCKYOS-VM-TEMPLATE-WF"

JT1_NAME = "ROCKYOS-VM-TEMPLATE"
JT2_NAME = "Disable_SELinux_el8"
JT3_NAME = "Offline_Patching_el8"

CREDENTIAL_NAME = "Linux Root Credential"
INVENTORY_NAME = "rocky-8-servers"

org = Organization.objects.get(name=ORG_NAME)

jt1 = JobTemplate.objects.get(name=JT1_NAME)
jt2 = JobTemplate.objects.get(name=JT2_NAME)
jt3 = JobTemplate.objects.get(name=JT3_NAME)

cred = Credential.objects.get(name=CREDENTIAL_NAME)
inv = Inventory.objects.get(name=INVENTORY_NAME)

wf, created = WorkflowJobTemplate.objects.get_or_create(
    name=WORKFLOW_NAME,
    organization=org
)

# Remove existing nodes if re-running
wf.workflow_job_template_nodes.all().delete()

# Default inventory
wf.inventory = inv

# Prompt on launch
wf.ask_limit_on_launch = True
wf.ask_credential_on_launch = True
wf.ask_inventory_on_launch = True

wf.save()

# Attach default credential
wf.credentials.clear()
wf.credentials.add(cred)

# Create workflow nodes
n1 = WorkflowJobTemplateNode.objects.create(
    workflow_job_template=wf,
    unified_job_template=jt1
)

n2 = WorkflowJobTemplateNode.objects.create(
    workflow_job_template=wf,
    unified_job_template=jt2
)

n3 = WorkflowJobTemplateNode.objects.create(
    workflow_job_template=wf,
    unified_job_template=jt3
)

# Success path
n1.success_nodes.add(n2)
n2.success_nodes.add(n3)

print(f"Workflow '{wf.name}' created/updated successfully.")
print(f"Inventory: {inv.name}")
print(f"Credential: {cred.name}")
print(f"J1 -> {jt1.name}")
print(f"J2 -> {jt2.name}")
print(f"J3 -> {jt3.name}")
print()
print("Execution Order:")
print(f"  {jt1.name}")
print("        │")
print("        ▼")
print(f"  {jt2.name}")
print("        │")
print("        ▼")
print(f"  {jt3.name}")
print()
print("Prompt on Launch:")
print("  Inventory  = True")
print("  Limit      = True")
print("  Credential = True")

EOF
```

# EL7 Job Template

```python
awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

try:
    project = Project.objects.get(name="Inventory-Git-Repo")
    inventory = Inventory.objects.get(name="centos-07-servers")
    credential = Credential.objects.get(name="Linux Root Credential")
except (Project.DoesNotExist,
        Inventory.DoesNotExist,
        Credential.DoesNotExist) as e:
    print(f"Error: {e}")
    exit(1)

jt, created = JobTemplate.objects.get_or_create(
    name="Subscription_Patching_EL7",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "subscription_patching/patch-el7.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "subscription_patching/patch-el7.yml"
jt.ask_inventory_on_launch = False
jt.ask_limit_on_launch = False

jt.credentials.clear()
jt.credentials.add(credential)

survey_spec = {
    "name": "target_hosts",
    "description": "CentOS 7 Subscription Patching",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Enter host or host pattern",
            "variable": "target_hosts",
            "required": True,
            "default": "cent-07-*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.survey_enabled = True
jt.survey_spec = survey_spec

jt.save()

print(f"Job Template '{jt.name}' {'created' if created else 'updated'} successfully.")
EOF
```

# EL8 Job Template

```python
awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

try:
    project = Project.objects.get(name="Inventory-Git-Repo")
    inventory = Inventory.objects.get(name="rocky-8-servers")
    credential = Credential.objects.get(name="Linux Root Credential")
except (Project.DoesNotExist,
        Inventory.DoesNotExist,
        Credential.DoesNotExist) as e:
    print(f"Error: {e}")
    exit(1)

jt, created = JobTemplate.objects.get_or_create(
    name="Subscription_Patching_EL8",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "subscription_patching/patch-el8.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "subscription_patching/patch-el8.yml"
jt.ask_inventory_on_launch = False
jt.ask_limit_on_launch = False

jt.credentials.clear()
jt.credentials.add(credential)

survey_spec = {
    "name": "target_hosts",
    "description": "Rocky Linux 8 Subscription Patching",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Enter host or host pattern",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-08-*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.survey_enabled = True
jt.survey_spec = survey_spec

jt.save()

print(f"Job Template '{jt.name}' {'created' if created else 'updated'} successfully.")
EOF
```


---

# Step 6 - Configure Inventory Prompt

## Enable Prompt on Launch

```python
jt.ask_inventory_on_launch = True
jt.inventory = None
```

## Result

The user is prompted to choose:

* rocky-8-servers
* centos-07-servers
* Any other available inventory

---

# Optional: Hardcode Inventory

> [!NOTE]
> Use this only if the template should always target a single inventory.

### Remove

```python
jt.ask_inventory_on_launch = True
jt.inventory = None
```

### Replace With

```python
from awx.main.models import Inventory

inventory = Inventory.objects.get(
    name="rocky-8-servers"
)

jt.inventory = inventory
jt.ask_inventory_on_launch = False
```

# Provision Hosts el7

```text
awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential
import json

# Dependencies
try:
    project = Project.objects.get(name="Inventory-Git-Repo")
    inventory = Inventory.objects.get(name="centos-07-servers")
    credential = Credential.objects.get(name="Linux Root Credential")
except (Project.DoesNotExist,
        Inventory.DoesNotExist,
        Credential.DoesNotExist) as e:
    print(f"Error: Missing required dependency. {e}")
    exit(1)

# Create or Update Job Template
jt, created = JobTemplate.objects.get_or_create(
    name="Provision_Hosts_el7",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "provision_hosts_el7/Foreman_provision_hosts_el7.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": True,
        "limit": "localhost"
    }
)

if not created:
    jt.project = project
    jt.inventory = inventory
    jt.playbook = "provision_hosts_el7/Foreman_provision_hosts_el7.yml"
    jt.ask_inventory_on_launch = False
    jt.ask_limit_on_launch = True
    jt.limit = "localhost"

# Assign Credential
jt.save()
jt.credentials.clear()
jt.credentials.add(credential)

# Survey Specification
survey_spec = {
    "name": "target_hosts",
    "description": "Specify target hosts/group to provision.",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Inventory host/group to run against",
            "variable": "target_hosts",
            "required": True,
            "default": "cent-07-*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.survey_enabled = True
jt.survey_spec = survey_spec
jt.save()

print(
    f"Job Template 'Provision_Hosts_el7' "
    f"{'created' if created else 'updated'} successfully."
)
print(f"Credential assigned: {credential.name}")
print("Default Limit: localhost")
print("Survey 'target_hosts' configured and enabled.")
EOF
```

# Provision Hosts el8

```text
awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential
import json

# Dependencies
try:
    project = Project.objects.get(name="Inventory-Git-Repo")
    inventory = Inventory.objects.get(name="rocky-8-servers")
    credential = Credential.objects.get(name="Linux Root Credential")
except (Project.DoesNotExist,
        Inventory.DoesNotExist,
        Credential.DoesNotExist) as e:
    print(f"Error: Missing required dependency. {e}")
    exit(1)

# Create or Update Job Template
jt, created = JobTemplate.objects.get_or_create(
    name="Provision_Hosts_el8",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "provision_hosts_el8/Foreman_provision_hosts_el8.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": True,
        "limit": "localhost"
    }
)

if not created:
    jt.project = project
    jt.inventory = inventory
    jt.playbook = "provision_hosts_el8/Foreman_provision_hosts_el8.yml"
    jt.ask_inventory_on_launch = False
    jt.ask_limit_on_launch = True
    jt.limit = "localhost"

# Assign Credential
jt.save()
jt.credentials.clear()
jt.credentials.add(credential)

# Survey Specification
survey_spec = {
    "name": "target_hosts",
    "description": "Specify target hosts/group to provision.",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Inventory host/group to run against",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-08-*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.survey_enabled = True
jt.survey_spec = survey_spec
jt.save()

print(
    f"Job Template 'Provision_Hosts_el8' "
    f"{'created' if created else 'updated'} successfully."
)
print(f"Credential assigned: {credential.name}")
print("Default Limit: localhost")
print("Survey 'target_hosts' configured and enabled.")
EOF
```

---

# Validation Checklist

## Credentials

* [ ] Netbox API Token
* [ ] Netbox Production Credential

## Projects

* [ ] Inventory-Git-Repo
* [ ] GOLDENTEMPLATE_ROCKYOS-08

## Inventories

* [ ] rocky-8-servers
* [ ] centos-07-servers

## Inventory Sources

* [ ] rocky-8-servers_inventory.yml
* [ ] centos-07-servers_inventory.yml

## Job Templates

* [ ] Netbox-AWX-GOLDENTEMPLATE_ROCKYOS_08
* [ ] GOLDENTEMPLATE_ROCKYOS_08

## Final Validation

* [ ] Project Sync Successful
* [ ] Inventory Sync Successful
* [ ] Playbook Launch Successful
* [ ] Inventory Selection Working

---

# Completion Criteria

The implementation is complete when:

* Credential Type exists.
* Credential exists.
* Inventories exist.
* Inventory Sources synchronize successfully.
* Projects synchronize successfully.
* Job Templates are available.
* Inventory selection works as expected.
* Playbooks execute successfully.
