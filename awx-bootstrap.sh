#!/bin/bash
# ==============================================================
# AWX Bootstrap Script - Part 1 (Chunk 1)
# Description:
#   - Detect AWX Task Pod
#   - Enter AWX Container
#   - Create NetBox Credential Type
#   - Create NetBox Production Credential
#   - Create Linux Root Credential
# ==============================================================

set -euo pipefail

NAMESPACE="awx"
CONTAINER="awx-server-task"

echo "========================================================="
echo "           AWX BOOTSTRAP - PART 1"
echo "========================================================="

# --------------------------------------------------------------
# Check kubectl
# --------------------------------------------------------------
if ! command -v kubectl >/dev/null 2>&1; then
    echo "[ERROR] kubectl is not installed."
    exit 1
fi

# --------------------------------------------------------------
# Locate AWX Task Pod
# --------------------------------------------------------------
POD=$(kubectl get pods -n ${NAMESPACE} \
    --no-headers \
    | awk '/awx-server-task/ {print $1; exit}')

if [ -z "$POD" ]; then
    echo "[ERROR] Unable to locate AWX task pod."
    exit 1
fi

echo
echo "Using AWX Pod : $POD"
echo

# --------------------------------------------------------------
# Execute inside AWX Container
# --------------------------------------------------------------
kubectl exec -i "$POD" \
    -n "$NAMESPACE" \
    -c "$CONTAINER" \
    -- bash <<'CONTAINER'

set -e

echo
echo "Running AWX Bootstrap..."
echo

# ==============================================================
# NetBox Credential Type
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import CredentialType

ctype, created = CredentialType.objects.get_or_create(
    name="Netbox API Token",
    defaults={
        "kind":"cloud",
        "inputs":{
            "fields":[
                {
                    "id":"netbox_url",
                    "type":"string",
                    "label":"NetBox URL"
                },
                {
                    "id":"netbox_token",
                    "type":"string",
                    "label":"NetBox API Token",
                    "secret":True
                }
            ],
            "required":[
                "netbox_token"
            ]
        },
        "injectors":{
            "env":{
                "NETBOX_API":"{{ netbox_url }}",
                "NETBOX_TOKEN":"{{ netbox_token }}"
            }
        }
    }
)

print(
    "Credential Type",
    "created" if created else "already exists"
)
EOF

# ==============================================================
# NetBox Production Credential
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import (
    Credential,
    CredentialType,
    Organization
)

org = Organization.objects.get(name="Default")

ctype = CredentialType.objects.get(
    name="Netbox API Token"
)

cred, created = Credential.objects.get_or_create(
    name="Netbox Production Credential",
    defaults={
        "credential_type":ctype,
        "organization":org,
        "inputs":{
            "netbox_url":"https://rocky-08-03.vgs.com/",
            "netbox_token":"83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd"
        }
    }
)

print(
    "Credential",
    "created" if created else "already exists"
)
EOF

# ==============================================================
# Linux Root Credential
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import (
    Credential,
    CredentialType,
    Organization
)

org = Organization.objects.get(name="Default")

ctype = CredentialType.objects.get(kind="ssh")

cred, created = Credential.objects.get_or_create(
    name="Linux Root Credential",
    organization=org,
    credential_type=ctype,
    defaults={
        "inputs":{
            "username":"root",
            "password":"Root@123"
        }
    }
)

print(
    f"Linux Credential {'created' if created else 'already exists'}"
)
EOF

echo
echo "Credential configuration completed."

# ----- Chunk 1 Ends Here -----

# ==============================================================
# Create Inventories
# ==============================================================

awx-manage shell <<'EOF'
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
        f"{'created' if created else 'already exists'}"
    )
EOF


# ==============================================================
# Create Inventory Git Project
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import Project, Organization

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

project.organization = org
project.scm_type = "git"
project.scm_url = repo_url
project.scm_update_on_launch = False
project.save()

print(
    f"Project '{project.name}' "
    f"{'created' if created else 'updated'}"
)
EOF


# ==============================================================
# Create SCM Inventory Sources
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import (
    Inventory,
    InventorySource,
    Project,
    Organization
)

org = Organization.objects.get(name="Default")

project = Project.objects.get(
    name="Inventory-Git-Repo"
)

configs = [
    (
        "rocky-8-servers",
        "rocky-8-servers_inventory.yml"
    ),
    (
        "centos-07-servers",
        "centos-07-servers_inventory.yml"
    )
]

for inv_name, inv_file in configs:

    inventory = Inventory.objects.get(
        name=inv_name,
        organization=org
    )

    source, created = InventorySource.objects.get_or_create(
        name=inv_name,
        inventory=inventory,
        defaults={
            "source":"scm",
            "source_project":project,
            "source_path":inv_file,
            "overwrite":True,
            "update_on_launch":False
        }
    )

    source.source = "scm"
    source.source_project = project
    source.source_path = inv_file
    source.overwrite = True
    source.update_on_launch = False
    source.save()

    print(
        f"Inventory Source '{inv_name}' "
        f"{'created' if created else 'updated'}"
    )
EOF


# ==============================================================
# Add localhost to both inventories
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Host

inventories = [
    "centos-07-servers",
    "rocky-8-servers"
]

for inv_name in inventories:

    inventory = Inventory.objects.get(
        name=inv_name
    )

    host, created = Host.objects.get_or_create(
        name="localhost",
        inventory=inventory,
        defaults={
            "variables":
                "ansible_connection: local\n"
                "ansible_python_interpreter: /usr/bin/python3"
        }
    )

    if not created:
        host.variables = (
            "ansible_connection: local\n"
            "ansible_python_interpreter: /usr/bin/python3"
        )
        host.save()

    print(
        f"{inv_name}: localhost "
        f"{'created' if created else 'updated'}"
    )
EOF

echo
echo "---------------------------------------------------------"
echo "Part 1 - Chunk 2 completed successfully."
echo "---------------------------------------------------------"

# ==============================================================
# ROCKYOS-VM-TEMPLATE Job Template
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-8-servers")

jt, created = JobTemplate.objects.get_or_create(
    name="ROCKYOS-VM-TEMPLATE",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "ROCKYOS-VM-TEMPLATE/ROCKYOS-VM-TEMPLATE.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": True
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "ROCKYOS-VM-TEMPLATE/ROCKYOS-VM-TEMPLATE.yml"
jt.ask_inventory_on_launch = False
jt.ask_limit_on_launch = True
jt.save()

print(f"ROCKYOS-VM-TEMPLATE {'created' if created else 'updated'}")
EOF


# ==============================================================
# CENTOS-VM-TEMPLATE Job Template
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="centos-07-servers")

jt, created = JobTemplate.objects.get_or_create(
    name="CENTOS-VM-TEMPLATE",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "CENTOS-VM-TEMPLATE/CENTOS-VM-TEMPLATE.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": True
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "CENTOS-VM-TEMPLATE/CENTOS-VM-TEMPLATE.yml"
jt.ask_inventory_on_launch = False
jt.ask_limit_on_launch = True
jt.save()

print(f"CENTOS-VM-TEMPLATE {'created' if created else 'updated'}")
EOF


# ==============================================================
# Local_DNS Job Template
# ==============================================================

awx-manage shell <<'EOF'
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

jt.project = project
jt.playbook = "Local_DNS.yml"
jt.inventory = None
jt.ask_inventory_on_launch = True
jt.ask_limit_on_launch = True
jt.save()

print(f"Local_DNS {'created' if created else 'updated'}")
EOF


# ==============================================================
# Verify Resources
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import (
    Inventory,
    Project,
    JobTemplate,
    Credential
)

print("\n========== INVENTORIES ==========")
for i in Inventory.objects.all():
    print(" -", i.name)

print("\n========== PROJECTS ==========")
for p in Project.objects.all():
    print(" -", p.name)

print("\n========== JOB TEMPLATES ==========")
for j in JobTemplate.objects.all():
    print(" -", j.name)

print("\n========== CREDENTIALS ==========")
for c in Credential.objects.all():
    print(" -", c.name)
EOF


echo
echo "=========================================================="
echo " Part 1 Completed Successfully"
echo "=========================================================="

echo "Created:"
echo "  ✓ NetBox Credential Type"
echo "  ✓ NetBox Production Credential"
echo "  ✓ Linux Root Credential"
echo "  ✓ Inventories"
echo "  ✓ Inventory Git Project"
echo "  ✓ SCM Inventory Sources"
echo "  ✓ Localhost"
echo "  ✓ ROCKYOS-VM-TEMPLATE"
echo "  ✓ CENTOS-VM-TEMPLATE"
echo "  ✓ Local_DNS"

# ==============================================================
# Offline_Patching_el7
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="centos-07-servers")
credential = Credential.objects.get(name="Linux Root Credential")

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

jt.project = project
jt.inventory = inventory
jt.playbook = "offline_patching_el7/offline-patch-el7.yml"
jt.ask_inventory_on_launch = False
jt.ask_limit_on_launch = True
jt.save()

jt.credentials.clear()
jt.credentials.add(credential)

print(f"Offline_Patching_el7 {'created' if created else 'updated'}")
EOF


# ==============================================================
# Offline_Patching_el8
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-8-servers")
credential = Credential.objects.get(name="Linux Root Credential")

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

jt.project = project
jt.inventory = inventory
jt.playbook = "offline_patching_el8/offline-patch-el8.yml"
jt.ask_inventory_on_launch = False
jt.ask_limit_on_launch = True
jt.save()

jt.credentials.clear()
jt.credentials.add(credential)

print(f"Offline_Patching_el8 {'created' if created else 'updated'}")
EOF

echo
echo "Offline patching templates completed."

# ==============================================================
# Disable_SELinux_el7
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="centos-07-servers")
credential = Credential.objects.get(name="Linux Root Credential")

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

jt.project = project
jt.inventory = inventory
jt.playbook = "Disable_SELinux_el7.yml"
jt.ask_inventory_on_launch = False
jt.ask_limit_on_launch = True
jt.save()

jt.credentials.clear()
jt.credentials.add(credential)

print(
    f"Job Template 'Disable_SELinux_el7' "
    f"{'created' if created else 'updated'} successfully."
)
print(f"Credential assigned: {credential.name}")
EOF


# ==============================================================
# Disable_SELinux_el8
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-8-servers")
credential = Credential.objects.get(name="Linux Root Credential")

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

jt.project = project
jt.inventory = inventory
jt.playbook = "Disable_SELinux_el8.yml"
jt.ask_inventory_on_launch = False
jt.ask_limit_on_launch = True
jt.save()

jt.credentials.clear()
jt.credentials.add(credential)

print(
    f"Job Template 'Disable_SELinux_el8' "
    f"{'created' if created else 'updated'} successfully."
)
print(f"Credential assigned: {credential.name}")
EOF


# ==============================================================
# Verify Job Templates
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import JobTemplate

templates = [
    "Offline_Patching_el7",
    "Offline_Patching_el8",
    "Disable_SELinux_el7",
    "Disable_SELinux_el8"
]

print("\nVerification\n")

for name in templates:
    try:
        jt = JobTemplate.objects.get(name=name)
        print(f"✓ {jt.name}")
    except JobTemplate.DoesNotExist:
        print(f"✗ {name} NOT FOUND")
EOF

echo
echo "========================================================"
echo "Part 2 - Chunk 2 completed."
echo "========================================================"

# ==============================================================
# Workflow : CENTOS-VM-TEMPLATE-WF
# ==============================================================

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

# Remove existing workflow nodes
wf.workflow_job_template_nodes.all().delete()

wf.inventory = inv
wf.ask_limit_on_launch = True
wf.ask_inventory_on_launch = True
wf.ask_credential_on_launch = True
wf.save()

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

# Link nodes
n1.success_nodes.add(n2)
n2.success_nodes.add(n3)

print(f"Workflow '{wf.name}' {'created' if created else 'updated'}")
print("Execution Order:")
print(f"  {jt1.name}")
print("      ↓")
print(f"  {jt2.name}")
print("      ↓")
print(f"  {jt3.name}")
EOF

echo
echo "CENTOS Workflow created successfully."

# ==============================================================
# Workflow : ROCKYOS-VM-TEMPLATE-WF
# ==============================================================

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

# Remove existing workflow nodes
wf.workflow_job_template_nodes.all().delete()

wf.inventory = inv
wf.ask_inventory_on_launch = True
wf.ask_limit_on_launch = True
wf.ask_credential_on_launch = True
wf.save()

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

# Success flow
n1.success_nodes.add(n2)
n2.success_nodes.add(n3)

print(f"Workflow '{wf.name}' {'created' if created else 'updated'}")
print()
print("Execution Order")
print("----------------")
print(jt1.name)
print("   |")
print("   v")
print(jt2.name)
print("   |")
print("   v")
print(jt3.name)
EOF


# ==============================================================
# Verify Workflows
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import WorkflowJobTemplate

print("\n========== Workflow Verification ==========\n")

for wf in WorkflowJobTemplate.objects.all():
    print(f"Workflow : {wf.name}")

print("\nVerification Completed.")
EOF


echo
echo "==========================================================="
echo " PART 2 COMPLETED SUCCESSFULLY"
echo "==========================================================="

echo
echo "Created:"
echo "  ✓ Offline_Patching_el7"
echo "  ✓ Offline_Patching_el8"
echo "  ✓ Disable_SELinux_el7"
echo "  ✓ Disable_SELinux_el8"
echo "  ✓ CENTOS-VM-TEMPLATE-WF"
echo "  ✓ ROCKYOS-VM-TEMPLATE-WF"

echo
echo "Proceed to Part 3."

# ==============================================================
# Subscription_Patching_EL7
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import (
    Inventory,
    Project,
    JobTemplate,
    Credential
)

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="centos-07-servers")
credential = Credential.objects.get(name="Linux Root Credential")

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

print(
    f"Subscription_Patching_EL7 "
    f"{'created' if created else 'updated'}"
)
EOF


# ==============================================================
# Verify EL7 Subscription Template
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import JobTemplate

jt = JobTemplate.objects.get(
    name="Subscription_Patching_EL7"
)

print()
print("Template :", jt.name)
print("Survey   :", jt.survey_enabled)
print("Playbook :", jt.playbook)
print("Inventory:", jt.inventory.name)
print("Credential(s):")
for c in jt.credentials.all():
    print("  -", c.name)
EOF

echo
echo "Subscription_Patching_EL7 completed."

# ==============================================================
# Subscription_Patching_EL8
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import (
    Inventory,
    Project,
    JobTemplate,
    Credential
)

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-8-servers")
credential = Credential.objects.get(name="Linux Root Credential")

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

print(
    f"Subscription_Patching_EL8 "
    f"{'created' if created else 'updated'}"
)
EOF


# ==============================================================
# Verify EL8 Subscription Template
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import JobTemplate

jt = JobTemplate.objects.get(
    name="Subscription_Patching_EL8"
)

print()
print("Template :", jt.name)
print("Survey   :", jt.survey_enabled)
print("Playbook :", jt.playbook)
print("Inventory:", jt.inventory.name)
print("Credential(s):")
for c in jt.credentials.all():
    print("  -", c.name)
EOF

echo
echo "Subscription_Patching_EL8 completed."

# ==============================================================
# Provision_Hosts_el7
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import (
    Inventory,
    Project,
    JobTemplate,
    Credential
)

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="centos-07-servers")
credential = Credential.objects.get(name="Linux Root Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="Provision_Hosts_el7",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "provision_hosts_el7/Foreman_provision_hosts_el7.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "limit": "localhost"
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "provision_hosts_el7/Foreman_provision_hosts_el7.yml"
jt.ask_inventory_on_launch = False
jt.ask_limit_on_launch = False
jt.limit = "localhost"

jt.save()

jt.credentials.clear()
jt.credentials.add(credential)

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
    f"Provision_Hosts_el7 "
    f"{'created' if created else 'updated'} successfully."
)
print(f"Credential assigned: {credential.name}")
print("Default Limit: localhost")
print("Survey enabled.")
EOF


# ==============================================================
# Verify Provision_Hosts_el7
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import JobTemplate

jt = JobTemplate.objects.get(name="Provision_Hosts_el7")

print()
print("Template :", jt.name)
print("Playbook :", jt.playbook)
print("Inventory:", jt.inventory.name)
print("Limit    :", jt.limit)
print("Survey   :", jt.survey_enabled)

print("\nCredentials")
for c in jt.credentials.all():
    print(" -", c.name)
EOF

echo
echo "Provision_Hosts_el7 completed successfully."

# ==============================================================
# Provision_Hosts_el8
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import (
    Inventory,
    Project,
    JobTemplate,
    Credential
)

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-8-servers")
credential = Credential.objects.get(name="Linux Root Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="Provision_Hosts_el8",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "provision_hosts_el8/Foreman_provision_hosts_el8.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "limit": "localhost"
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "provision_hosts_el8/Foreman_provision_hosts_el8.yml"

# Always run the playbook on localhost
jt.ask_inventory_on_launch = False
jt.ask_limit_on_launch = False
jt.limit = "localhost"

jt.credentials.clear()
jt.credentials.add(credential)

survey_spec = {
    "name": "target_hosts",
    "description": "Specify target hosts/group to provision.",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Inventory host/group to provision",
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
    f"Provision_Hosts_el8 "
    f"{'created' if created else 'updated'} successfully."
)
print(f"Credential assigned: {credential.name}")
print("Default Limit : localhost")
print(f"Ask Limit     : {jt.ask_limit_on_launch}")
print("Survey enabled.")
EOF


# ==============================================================
# Verify Provision_Hosts_el8
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import JobTemplate

jt = JobTemplate.objects.get(name="Provision_Hosts_el8")

print()
print("Template  :", jt.name)
print("Playbook  :", jt.playbook)
print("Inventory :", jt.inventory.name)
print("Limit     :", jt.limit)
print("Ask Limit :", jt.ask_limit_on_launch)
print("Survey    :", jt.survey_enabled)

print("\nCredentials")
for c in jt.credentials.all():
    print(" -", c.name)
EOF

echo
echo "Provision_Hosts_el8 completed successfully."

# ==============================================================
# Workflow : Provision_Hosts_el7_Subscription_Patching_EL7
# ==============================================================

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
WORKFLOW_NAME = "Provision_Hosts_el7_Subscription_Patching_EL7"

JT1_NAME = "Provision_Hosts_el7"
JT2_NAME = "Subscription_Patching_EL7"

CREDENTIAL_NAME = "Linux Root Credential"
INVENTORY_NAME = "centos-07-servers"

org = Organization.objects.get(name=ORG_NAME)

jt1 = JobTemplate.objects.get(name=JT1_NAME)
jt2 = JobTemplate.objects.get(name=JT2_NAME)

cred = Credential.objects.get(name=CREDENTIAL_NAME)
inv = Inventory.objects.get(name=INVENTORY_NAME)

wf, created = WorkflowJobTemplate.objects.get_or_create(
    name=WORKFLOW_NAME,
    organization=org
)

# --------------------------------------------------------------
# Remove existing workflow nodes
# --------------------------------------------------------------
wf.workflow_job_template_nodes.all().delete()

# --------------------------------------------------------------
# Workflow Configuration
# --------------------------------------------------------------
wf.inventory = inv
wf.ask_inventory_on_launch = False
wf.ask_limit_on_launch = False
wf.ask_credential_on_launch = False
wf.ask_variables_on_launch = True
wf.limit = "localhost"

# --------------------------------------------------------------
# Workflow Survey
# --------------------------------------------------------------
wf.survey_enabled = True
wf.survey_spec = {
    "name": "target_hosts",
    "description": "Provision Hosts + Subscription Patching (EL7)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Enter host(s) to provision and patch",
            "variable": "target_hosts",
            "required": True,
            "default": "cent-07-*",
            "min": 1,
            "max": 1024
        }
    ]
}

wf.save()

# --------------------------------------------------------------
# Assign Credential
# --------------------------------------------------------------
wf.credentials.clear()
wf.credentials.add(cred)

# --------------------------------------------------------------
# Create Workflow Nodes
# --------------------------------------------------------------
n1 = WorkflowJobTemplateNode.objects.create(
    workflow_job_template=wf,
    unified_job_template=jt1
)

n2 = WorkflowJobTemplateNode.objects.create(
    workflow_job_template=wf,
    unified_job_template=jt2
)

# --------------------------------------------------------------
# Execution Flow
# --------------------------------------------------------------
n1.success_nodes.add(n2)

print(
    f"Workflow '{wf.name}' "
    f"{'created' if created else 'updated'} successfully."
)

print()
print("Execution Order")
print("----------------")
print(jt1.name)
print("   |")
print("   v")
print(jt2.name)
EOF


# ==============================================================
# Verify Provision_Hosts_el7_Subscription_Patching_EL7
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import WorkflowJobTemplate

wf = WorkflowJobTemplate.objects.get(
    name="Provision_Hosts_el7_Subscription_Patching_EL7"
)

print()
print("Workflow   :", wf.name)
print("Inventory  :", wf.inventory.name)
print("Limit      :", wf.limit)
print("Ask Limit  :", wf.ask_limit_on_launch)
print("Survey     :", wf.survey_enabled)

print("\nWorkflow Nodes")
for node in wf.workflow_job_template_nodes.all():
    print(" -", node.unified_job_template.name)
EOF

echo
echo "Provision_Hosts_el7_Subscription_Patching_EL7 workflow completed successfully."

# ==============================================================
# Workflow : Provision_Hosts_el8_Subscription_Patching_EL8
# ==============================================================

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
WORKFLOW_NAME = "Provision_Hosts_el8_Subscription_Patching_EL8"

JT1_NAME = "Provision_Hosts_el8"
JT2_NAME = "Subscription_Patching_EL8"

CREDENTIAL_NAME = "Linux Root Credential"
INVENTORY_NAME = "rocky-8-servers"

org = Organization.objects.get(name=ORG_NAME)

jt1 = JobTemplate.objects.get(name=JT1_NAME)
jt2 = JobTemplate.objects.get(name=JT2_NAME)

cred = Credential.objects.get(name=CREDENTIAL_NAME)
inv = Inventory.objects.get(name=INVENTORY_NAME)

wf, created = WorkflowJobTemplate.objects.get_or_create(
    name=WORKFLOW_NAME,
    organization=org
)

# --------------------------------------------------------------
# Remove existing workflow nodes
# --------------------------------------------------------------
wf.workflow_job_template_nodes.all().delete()

# --------------------------------------------------------------
# Workflow Configuration
# --------------------------------------------------------------
wf.inventory = inv
wf.ask_inventory_on_launch = False
wf.ask_limit_on_launch = False
wf.ask_credential_on_launch = False
wf.ask_variables_on_launch = True
wf.limit = "localhost"

# --------------------------------------------------------------
# Workflow Survey
# --------------------------------------------------------------
wf.survey_enabled = True
wf.survey_spec = {
    "name": "target_hosts",
    "description": "Provision Hosts + Subscription Patching (EL8)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Enter host(s) to provision and patch",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-08-*",
            "min": 1,
            "max": 1024
        }
    ]
}

wf.save()

# --------------------------------------------------------------
# Assign Credential
# --------------------------------------------------------------
wf.credentials.clear()
wf.credentials.add(cred)

# --------------------------------------------------------------
# Create Workflow Nodes
# --------------------------------------------------------------
n1 = WorkflowJobTemplateNode.objects.create(
    workflow_job_template=wf,
    unified_job_template=jt1
)

n2 = WorkflowJobTemplateNode.objects.create(
    workflow_job_template=wf,
    unified_job_template=jt2
)

# --------------------------------------------------------------
# Execution Flow
# --------------------------------------------------------------
n1.success_nodes.add(n2)

print(
    f"Workflow '{wf.name}' "
    f"{'created' if created else 'updated'} successfully."
)

print()
print("Execution Order")
print("----------------")
print(jt1.name)
print("   |")
print("   v")
print(jt2.name)
EOF


# ==============================================================
# Verify Provision_Hosts_el8_Subscription_Patching_EL8
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import WorkflowJobTemplate

wf = WorkflowJobTemplate.objects.get(
    name="Provision_Hosts_el8_Subscription_Patching_EL8"
)

print()
print("Workflow   :", wf.name)
print("Inventory  :", wf.inventory.name)
print("Limit      :", wf.limit)
print("Ask Limit  :", wf.ask_limit_on_launch)
print("Survey     :", wf.survey_enabled)

print("\nWorkflow Nodes")
for node in wf.workflow_job_template_nodes.all():
    print(" -", node.unified_job_template.name)
EOF

echo
echo "Provision_Hosts_el8_Subscription_Patching_EL8 workflow completed successfully."


# ==============================================================
# Final Verification
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import (
    Inventory,
    Project,
    Credential,
    JobTemplate,
    WorkflowJobTemplate
)

print("\n==============================")
print(" AWX BOOTSTRAP VERIFICATION")
print("==============================")

print("\nInventories")
for obj in Inventory.objects.all():
    print("  ✓", obj.name)

print("\nProjects")
for obj in Project.objects.all():
    print("  ✓", obj.name)

print("\nCredentials")
for obj in Credential.objects.all():
    print("  ✓", obj.name)

print("\nJob Templates")
for obj in JobTemplate.objects.all():
    print("  ✓", obj.name)

print("\nWorkflow Templates")
for obj in WorkflowJobTemplate.objects.all():
    print("  ✓", obj.name)

print("\nBootstrap verification completed.")
EOF

echo
echo "=========================================================="
echo "        AWX BOOTSTRAP COMPLETED SUCCESSFULLY"
echo "=========================================================="

echo
echo "Resources Created:"
echo "  ✓ NetBox Credential Type"
echo "  ✓ NetBox Production Credential"
echo "  ✓ Linux Root Credential"
echo "  ✓ centos-07-servers Inventory"
echo "  ✓ rocky-8-servers Inventory"
echo "  ✓ Inventory-Git-Repo Project"
echo "  ✓ SCM Inventory Sources"
echo "  ✓ localhost Host"
echo "  ✓ ROCKYOS-VM-TEMPLATE"
echo "  ✓ CENTOS-VM-TEMPLATE"
echo "  ✓ Local_DNS"
echo "  ✓ Offline_Patching_el7"
echo "  ✓ Offline_Patching_el8"
echo "  ✓ Disable_SELinux_el7"
echo "  ✓ Disable_SELinux_el8"
echo "  ✓ Subscription_Patching_EL7"
echo "  ✓ Subscription_Patching_EL8"
echo "  ✓ Provision_Hosts_el7"
echo "  ✓ Provision_Hosts_el8"
echo "  ✓ CENTOS-VM-TEMPLATE-WF"
echo "  ✓ ROCKYOS-VM-TEMPLATE-WF"

echo
echo "=========================================================="
echo "AWX Bootstrap Completed"
echo "=========================================================="

CONTAINER

echo
echo "Bootstrap completed successfully."
