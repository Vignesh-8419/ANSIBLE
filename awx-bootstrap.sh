#!/bin/bash
# ==============================================================================
# AWX Infrastructure Bootstrap
# ==============================================================================
#
# Purpose:
#   Bootstrap an entire AWX environment from scratch.
#
# This script automatically creates:
#
#   • Credential Types
#   • Credentials
#   • Inventories
#   • Inventory Sources
#   • Git Projects
#   • Job Templates
#   • Workflow Templates
#   • Survey Definitions
#   • Verification Reports
#
# Supported Operating Systems
#   • CentOS 7
#   • Rocky Linux 8
#   • Rocky Linux 9
#
# Requirements
#   • kubectl configured
#   • Running AWX Operator deployment
#   • awx-server-task pod available
#   • GitHub repository accessible
#
# Idempotent:
#   Safe to execute multiple times.
#
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Console Colors
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

NAMESPACE="awx"
CONTAINER="awx-server-task"

# ==============================================================================
# AWX Infrastructure Bootstrap
# ==============================================================================

echo
echo -e "${BLUE}==========================================================${NC}"
echo -e "${WHITE}${BOLD}         AWX INFRASTRUCTURE BOOTSTRAP${NC}"
echo -e "${BLUE}==========================================================${NC}"

# ==============================================================================
# Prerequisites
# ==============================================================================

echo
echo -e "${CYAN}==========================================================${NC}"
echo -e "${WHITE}${BOLD} Verifying Prerequisites${NC}"
echo -e "${CYAN}==========================================================${NC}"

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

# Console Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

echo
echo "Running AWX Bootstrap..."
echo

# ==============================================================================
# Credential Types
# ==============================================================================

echo
echo -e "${CYAN}==========================================================${NC}"
echo -e "${WHITE}${BOLD} Creating Credential Types${NC}"
echo -e "${CYAN}==========================================================${NC}"

# --------------------------------------------------------------
# NetBox API Token Credential Type
# --------------------------------------------------------------

echo
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo -e "${WHITE} Creating NetBox API Token Credential Type${NC}"
echo -e "${YELLOW}----------------------------------------------------------${NC}"

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

# ==============================================================================
# Credentials
# ==============================================================================

echo
echo -e "${CYAN}==========================================================${NC}"
echo -e "${WHITE}${BOLD} Creating Credentials${NC}"
echo -e "${CYAN}==========================================================${NC}"

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
            "netbox_url":"https://netbox.vgs.com/",
            "netbox_token":"83fb0cec1adff8ff4f36c9185df6b9e2f07c7fcd"
        }
    }
)

print(
    "Credential",
    "created" if created else "already exists"
)
EOF

# --------------------------------------------------------------
# Linux Root Credential
# --------------------------------------------------------------

echo
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Linux Root Credential${NC}"
echo -e "${YELLOW}----------------------------------------------------------${NC}"

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
echo "Linux Root Credential configuration completed."


# Linux Root Credential
# --------------------------------------------------------------

echo
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Linux Admin Credential${NC}"
echo -e "${YELLOW}----------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import (
    Credential,
    CredentialType,
    Organization
)

org = Organization.objects.get(name="Default")

ctype = CredentialType.objects.get(kind="ssh")

cred, created = Credential.objects.get_or_create(
    name="Linux Admin Credential",
    organization=org,
    credential_type=ctype,
    defaults={
        "inputs":{
            "username":"admin",
            "password":"Vigneshv12$"
        }
    }
)

print(
    f"Linux Credential {'created' if created else 'already exists'}"
)
EOF

echo
echo "Linux Admin Credential configuration completed."

# ==============================================================================
# Inventories
# ==============================================================================

echo
echo -e "${CYAN}==========================================================${NC}"
echo -e "${WHITE}${BOLD} Creating Inventories${NC}"
echo -e "${CYAN}==========================================================${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Organization

org = Organization.objects.get(name="Default")

inventories = [
    "centos-07-servers",
    "rocky-8-servers",
    "rocky-9-servers"
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


# ==============================================================================
# Projects
# ==============================================================================

echo
echo -e "${CYAN}==========================================================${NC}"
echo -e "${WHITE}${BOLD} Creating Projects${NC}"
echo -e "${CYAN}==========================================================${NC}"

# --------------------------------------------------------------
# Inventory Git Repository
# --------------------------------------------------------------

echo
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Inventory Git Repository${NC}"
echo -e "${YELLOW}----------------------------------------------------------${NC}"

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

# --------------------------------------------------------------
# SCM Inventory Sources
# --------------------------------------------------------------

echo
echo -e "${CYAN}==========================================================${NC}"
echo -e "${WHITE}${BOLD} Creating Inventory Sources${NC}"
echo -e "${CYAN}==========================================================${NC}"

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
    ),
    (
        "rocky-9-servers",
        "rocky-9-servers_inventory.yml"
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
            "source": "scm",
            "source_project": project,
            "source_path": inv_file,
            "overwrite": True,
            "update_on_launch": True,
            "update_cache_timeout": 300
        }
    )

    source.source = "scm"
    source.source_project = project
    source.source_path = inv_file
    source.overwrite = True
    source.update_on_launch = True
    source.update_cache_timeout = 300
    source.save()

    print(
        f"Inventory Source '{inv_name}' "
        f"{'created' if created else 'updated'}"
    )

print("\nInventory Sources configured successfully.")
EOF

# ==============================================================================
# Inventory Source Schedules
# ==============================================================================

#echo
#echo -e "${CYAN}==========================================================${NC}"
#echo -e "${WHITE}${BOLD} Creating Inventory Source Schedules${NC}"
#echo -e "${CYAN}==========================================================${NC}"
#
#awx-manage shell <<'EOF'
#from awx.main.models import InventorySource
#from awx.main.models.schedules import Schedule
#
#sources = [
#    "centos-07-servers",
#    "rocky-8-servers",
#    "rocky-9-servers"
#]
#
#rrule = (
#    "DTSTART:20260704T000000Z\n"
#    "RRULE:FREQ=MINUTELY;INTERVAL=5"
#)
#
#for name in sources:
#
#    source = InventorySource.objects.get(name=name)
#
#    schedule, created = Schedule.objects.get_or_create(
#        name=f"{name}-5min-sync",
#        unified_job_template=source,
#        defaults={
#            "rrule": rrule,
#            "enabled": True,
#        }
#    )
#
#    schedule.rrule = rrule
#    schedule.enabled = True
#    schedule.save()
#
#    print(
#        f"Schedule '{schedule.name}' "
#        f"{'created' if created else 'updated'}"
#    )
#
#print("\nInventory Source schedules configured successfully.")
#EOF

# ==============================================================================
# Localhost Configuration
# ==============================================================================

echo
echo -e "${CYAN}==========================================================${NC}"
echo -e "${WHITE}${BOLD} Configuring Localhost${NC}"
echo -e "${CYAN}==========================================================${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Host

inventories = [
    "centos-07-servers",
    "rocky-8-servers",
    "rocky-9-servers"
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

# ==============================================================================
# Job Templates
# ==============================================================================

echo
echo -e "${CYAN}==========================================================${NC}"
echo -e "${WHITE}${BOLD} Creating Job Templates${NC}"
echo -e "${CYAN}==========================================================${NC}"

# --------------------------------------------------------------
# Enable_Passwordless_SSH
# --------------------------------------------------------------

echo
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Enable_Passwordless_SSH${NC}"
echo -e "${YELLOW}----------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="Enable_Passwordless_SSH",
    defaults={
        "project": project,
        "playbook": "enable_passwordless_ssh/enable_passwordless_ssh.yml",
        "ask_inventory_on_launch": True,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = None                    # No fixed inventory
jt.playbook = "enable_passwordless_ssh/enable_passwordless_ssh.yml"

# Prompt for Inventory
jt.ask_inventory_on_launch = True

# Disable Limit
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Select Inventory and enter target hosts",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: cent-07-01, rocky-08-01, rocky-09-01 or *",
            "variable": "target_hosts",
            "required": True,
            "default": "*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

jt.credentials.clear()
jt.credentials.add(credential)

print(
    f"Enable_Passwordless_SSH "
    f"{'created' if created else 'updated'} successfully."
)
print("Inventory: Prompt on Launch")
print(f"Credential assigned: {credential.name}")
EOF

echo
echo "Enable_Passwordless_SSH template completed successfully."

# --------------------------------------------------------------
# create_admin_ssh
# --------------------------------------------------------------

echo
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo -e "${WHITE} Creating create_admin_ssh ${NC}"
echo -e "${YELLOW}----------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="CREATE-ADMIN-SSH",
    defaults={
        "project": project,
        "playbook": "ssh-admin/create_admin.yml",
        "ask_inventory_on_launch": True,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = None                    # No fixed inventory
jt.playbook = "ssh-admin/create_admin.yml"

# Prompt for Inventory
jt.ask_inventory_on_launch = True

# Disable Limit
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Select Inventory and enter target hosts",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: cent-07-01, rocky-08-01, rocky-09-01 or *",
            "variable": "target_hosts",
            "required": True,
            "default": "*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

jt.credentials.clear()
jt.credentials.add(credential)

print(
    f"create_admin_ssh "
    f"{'created' if created else 'updated'} successfully."
)
print("Inventory: Prompt on Launch")
print(f"Credential assigned: {credential.name}")
EOF

echo
echo "create_admin_ssh template completed successfully."

echo
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo -e "${WHITE} Creating RHEL_Hardening${NC}"
echo -e "${YELLOW}----------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="RHEL_Hardening",
    defaults={
        "project": project,
        "playbook": "rhel-hardening/playbooks/01_rhel_hardening.yml",
        "ask_inventory_on_launch": True,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = None
jt.playbook = "rhel-hardening/playbooks/01_rhel_hardening.yml"

jt.ask_inventory_on_launch = True
jt.ask_limit_on_launch = False
jt.survey_enabled = True

jt.survey_spec = {
    "name": "RHEL Hardening",
    "description": "Select Inventory and Target Hosts",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: cent-07-01, rocky-08-01, rocky-09-01 or *",
            "variable": "target_hosts",
            "required": True,
            "default": "*",
            "min": 1,
            "max": 1024,
            "new_question": True
        },
        {
            "type": "multiplechoice",
            "question_name": "Reboot After Hardening",
            "question_description": "Reboot the server after applying hardening?",
            "variable": "reboot_after_hardening",
            "required": True,
            "default": "Yes",
            "choices": "Yes\nNo",
            "new_question": True
        }
    ]
}

jt.save()

jt.credentials.clear()
jt.credentials.add(credential)

print(
    f"RHEL_Hardening {'created' if created else 'updated'} successfully."
)
print("Inventory: Prompt on Launch")
print(f"Credential assigned: {credential.name}")

EOF

echo
echo "RHEL_Hardening template completed successfully."

# --------------------------------------------------------------
# ROCKYOS-VM-TEMPLATE
# --------------------------------------------------------------

echo
echo -e "${CYAN}==========================================================${NC}"
echo -e "${WHITE}${BOLD} Creating ROCKYOS-VM-TEMPLATE${NC}"
echo -e "${CYAN}==========================================================${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate
import json

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-8-servers")

jt, created = JobTemplate.objects.get_or_create(
    name="ROCKYOS-VM-TEMPLATE",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "ROCKYOS-VM-TEMPLATE/ROCKYOS-VM-TEMPLATE.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "ROCKYOS-VM-TEMPLATE/ROCKYOS-VM-TEMPLATE.yml"

# No inventory prompt
jt.ask_inventory_on_launch = False

# Disable Limit prompt
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more Rocky Linux hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: rocky-08-01 or rocky-08-01,rocky-08-02 or rocky-08-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-08-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

print(f"ROCKYOS-VM-TEMPLATE {'created' if created else 'updated'}")
EOF

# --------------------------------------------------------------
# CENTOS-VM-TEMPLATE
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating CENTOS-VM-TEMPLATE${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

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
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "CENTOS-VM-TEMPLATE/CENTOS-VM-TEMPLATE.yml"

# Inventory is fixed
jt.ask_inventory_on_launch = False

# Do not use Limit
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more CentOS 7 hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: cent-07-01 or cent-07-01,cent-07-02 or cent-07-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "cent-07-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

print(f"CENTOS-VM-TEMPLATE {'created' if created else 'updated'}")
EOF

# --------------------------------------------------------------
# ROCKY9-VM-TEMPLATE
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating ROCKY9-VM-TEMPLATE${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-9-servers")

jt, created = JobTemplate.objects.get_or_create(
    name="ROCKY9-VM-TEMPLATE",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "ROCKY9-VM-TEMPLATE/ROCKY9-VM-TEMPLATE.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "ROCKY9-VM-TEMPLATE/ROCKY9-VM-TEMPLATE.yml"

# No inventory prompt
jt.ask_inventory_on_launch = False

# Disable Limit prompt
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more Rocky Linux 9 hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: rocky-09-01 or rocky-09-01,rocky-09-02 or rocky-09-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-09-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

print(f"ROCKY9-VM-TEMPLATE {'created' if created else 'updated'}")
EOF

# --------------------------------------------------------------
# Local_DNS
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Local_DNS${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Project, JobTemplate

project = Project.objects.get(name="Inventory-Git-Repo")

jt, created = JobTemplate.objects.get_or_create(
    name="Local_DNS",
    defaults={
        "project": project,
        "playbook": "Local_DNS.yml",
        "inventory": None,
        "ask_inventory_on_launch": True,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.playbook = "Local_DNS.yml"

# Inventory selected at launch (or inherited from Workflow)
jt.inventory = None
jt.ask_inventory_on_launch = True

# Do not use Limit
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more target hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: cent-07-01, rocky-08-01, cent-07-01,cent-07-02, rocky-08-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

print(f"Local_DNS {'created' if created else 'updated'}")
EOF


# ==============================================================================
# Resource Verification
# ==============================================================================

echo
echo -e "${MAGENTA}==========================================================${NC}"
echo -e "${WHITE}${BOLD} Verifying AWX Resources${NC}"
echo -e "${MAGENTA}==========================================================${NC}"

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

echo "Created:"
echo "  ✓ NetBox Credential Type"
echo "  ✓ NetBox Production Credential"
echo "  ✓ Linux Root Credential"
echo "  ✓ Linux Admin Credential"
echo "  ✓ Inventories"
echo "  ✓ Inventory Git Project"
echo "  ✓ SCM Inventory Sources"
echo "  ✓ Localhost"
echo "  ✓ ROCKYOS-VM-TEMPLATE"
echo "  ✓ CENTOS-VM-TEMPLATE"
echo "  ✓ Local_DNS"

# --------------------------------------------------------------
# Offline_Patching_el7
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Offline_Patching_el7${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="centos-07-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="Offline_Patching_el7",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "offline_patching_el7/offline-patch-el7.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "offline_patching_el7/offline-patch-el7.yml"

# Fixed inventory
jt.ask_inventory_on_launch = False

# Disable Limit
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more CentOS 7 hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: cent-07-01 or cent-07-01,cent-07-02 or cent-07-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "cent-07-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

jt.credentials.clear()
jt.credentials.add(credential)

print(f"Offline_Patching_el7 {'created' if created else 'updated'}")
EOF

# --------------------------------------------------------------
# Offline_Patching_el8
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Offline_Patching_el8${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-8-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="Offline_Patching_el8",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "offline_patching_el8/offline-patch-el8.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "offline_patching_el8/offline-patch-el8.yml"

# Fixed inventory
jt.ask_inventory_on_launch = False

# Disable Limit
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more Rocky Linux 8 hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: rocky-08-01 or rocky-08-01,rocky-08-02 or rocky-08-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-08-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

jt.credentials.clear()
jt.credentials.add(credential)

print(f"Offline_Patching_el8 {'created' if created else 'updated'}")
EOF

echo
echo "Offline patching templates completed."

# --------------------------------------------------------------
# Offline_Patching_el9
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Offline_Patching_el9${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-9-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="Offline_Patching_el9",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "offline_patching_el9/offline-patch-el9.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "offline_patching_el9/offline-patch-el9.yml"

# Fixed inventory
jt.ask_inventory_on_launch = False

# Disable Limit
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more Rocky Linux 9 hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: rocky-09-01 or rocky-09-01,rocky-09-02 or rocky-09-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-09-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

jt.credentials.clear()
jt.credentials.add(credential)

print(f"Offline_Patching_el9 {'created' if created else 'updated'}")
EOF

echo
echo "Offline patching EL9 template completed."

# --------------------------------------------------------------
# Disable_SELinux_el7
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Disable_SELinux_el7${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="centos-07-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="Disable_SELinux_el7",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "Disable_SELinux_el7.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "Disable_SELinux_el7.yml"

# Fixed inventory
jt.ask_inventory_on_launch = False

# Disable Limit
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more CentOS 7 hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: cent-07-01 or cent-07-01,cent-07-02 or cent-07-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "cent-07-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

jt.credentials.clear()
jt.credentials.add(credential)

print(
    f"Job Template 'Disable_SELinux_el7' "
    f"{'created' if created else 'updated'} successfully."
)
print(f"Credential assigned: {credential.name}")
EOF


# --------------------------------------------------------------
# Disable_SELinux_el8
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Disable_SELinux_el8${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-8-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="Disable_SELinux_el8",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "Disable_SELinux_el8.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "Disable_SELinux_el8.yml"

# Fixed inventory
jt.ask_inventory_on_launch = False

# Disable Limit
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more Rocky Linux 8 hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: rocky-08-01 or rocky-08-01,rocky-08-02 or rocky-08-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-08-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

jt.credentials.clear()
jt.credentials.add(credential)

print(
    f"Job Template 'Disable_SELinux_el8' "
    f"{'created' if created else 'updated'} successfully."
)
print(f"Credential assigned: {credential.name}")
EOF

# --------------------------------------------------------------
# Disable_SELinux_el9
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Disable_SELinux_el9${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-9-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="Disable_SELinux_el9",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "Disable_SELinux_el9.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "Disable_SELinux_el9.yml"

# Fixed inventory
jt.ask_inventory_on_launch = False

# Disable Limit
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more Rocky Linux 9 hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: rocky-09-01 or rocky-09-01,rocky-09-02 or rocky-09-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-09-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

jt.credentials.clear()
jt.credentials.add(credential)

print(
    f"Job Template 'Disable_SELinux_el9' "
    f"{'created' if created else 'updated'} successfully."
)
print(f"Credential assigned: {credential.name}")
EOF

# ==============================================================================
# Verify Job Templates
# ==============================================================================

echo
echo -e "${MAGENTA}==========================================================${NC}"
echo -e "${WHITE}${BOLD} Verifying Job Templates${NC}"
echo -e "${MAGENTA}==========================================================${NC}"

awx-manage shell <<'EOF'
from awx.main.models import JobTemplate

templates = [
    "Offline_Patching_el7",
    "Offline_Patching_el8",
    "Offline_Patching_el9",
    "Disable_SELinux_el7",
    "Disable_SELinux_el8",
    "Disable_SELinux_el9"
]

print("\nVerification\n")

for name in templates:
    try:
        jt = JobTemplate.objects.get(name=name)
        print(f"✓ {jt.name}")
    except JobTemplate.DoesNotExist:
        print(f"✗ {name} NOT FOUND")
EOF

# --------------------------------------------------------------
# Rocky-8 Post Migration
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Rocky-8 Post Migration${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="centos-07-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="Rocky-8 Post Migration",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "Rocky8_Post_Migration_Cleanup.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "Rocky8_Post_Migration_Cleanup.yml"

# Inventory is fixed
jt.ask_inventory_on_launch = False

# Do not use Limit
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more CentOS 7 hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: cent-07-01 or cent-07-01,cent-07-02 or cent-07-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "cent-07-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

# Attach Linux Admin Credential
jt.credentials.clear()
jt.credentials.add(credential)

print(f"Rocky-8 Post Migration {'created' if created else 'updated'}")
EOF

# --------------------------------------------------------------
# Rocky-9 Post Migration
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Rocky-8 Post Migration${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-8-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="Rocky-9 Post Migration",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "ROCKY8TOROCKY9/Rocky9_Post_Migration_Cleanup.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "ROCKY8TOROCKY9/Rocky9_Post_Migration_Cleanup.yml"

# Inventory is fixed
jt.ask_inventory_on_launch = False

# Do not use Limit
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more CentOS 7 hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: rocky-08-01 or rocky-08-01,rocky-08-02 or rocky-08-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-08-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

# Attach Linux Admin Credential
jt.credentials.clear()
jt.credentials.add(credential)

print(f"Rocky-9 Post Migration {'created' if created else 'updated'}")
EOF


# --------------------------------------------------------------
# Leapp Preupgrade Fixes
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Leapp Preupgrade Fixes${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-8-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="Leapp Preupgrade Fixes",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "ROCKY8TOROCKY9/Leapp_Preupgrade_Fixes.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "ROCKY8TOROCKY9/Leapp_Preupgrade_Fixes.yml"

# Inventory is fixed
jt.ask_inventory_on_launch = False

# Do not use Limit
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more Rocky Linux 8 hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: rocky-08-01 or rocky-08-01,rocky-08-02 or rocky-08-*",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-08-*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

# Attach Linux Admin Credential
jt.credentials.clear()
jt.credentials.add(credential)

print(f"Leapp Preupgrade Fixes {'created' if created else 'updated'}")
EOF

# --------------------------------------------------------------
# REPAIR-RESCUE
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating REPAIR-RESCUE${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-8-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="REPAIR-RESCUE",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "03_repair_rescue.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "03_repair_rescue.yml"

# Inventory
jt.ask_inventory_on_launch = False

# Disable Limit prompt
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more Rocky Linux 8 hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: rocky-08-01 or rocky-08-01,rocky-08-02 or rocky-08-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-08-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

# Attach Linux Admin Credential
jt.credentials.clear()
jt.credentials.add(credential)

print(f"REPAIR-RESCUE {'created' if created else 'updated'}")
EOF

# ==============================================================================
# Workflow Templates
# ==============================================================================

echo
echo -e "${CYAN}==========================================================${NC}"
echo -e "${WHITE}${BOLD} Creating Workflow Templates${NC}"
echo -e "${CYAN}==========================================================${NC}"

# --------------------------------------------------------------
# Workflow : CENTOS-VM-TEMPLATE-WF
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Workflow: CENTOS-VM-TEMPLATE-WF${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

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
JT2_NAME = "RHEL_Hardening"
JT3_NAME = "Offline_Patching_el7"

CREDENTIAL_NAME = "Linux Admin Credential"
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

# Fixed inventory and credential
wf.inventory = inv

# Disable prompts at workflow launch
wf.ask_inventory_on_launch = False
wf.ask_limit_on_launch = False
wf.ask_credential_on_launch = False

# Enable survey so target_hosts is prompted once
wf.survey_enabled = True
wf.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more CentOS 7 hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: cent-07-01 or cent-07-01,cent-07-02 or cent-07-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "cent-07-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

wf.save()

# Attach credential to workflow
wf.credentials.clear()
wf.credentials.add(cred)

# ------------------------------------------------------------------
# Create Workflow Nodes
# ------------------------------------------------------------------

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

# ------------------------------------------------------------------
# Workflow Order
# ------------------------------------------------------------------

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
# --------------------------------------------------------------
# Workflow : ROCKYOS-VM-TEMPLATE (WITH PATCHING)
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Workflow: ROCKYOS-VM-TEMPLATE (WITH PATCHING)${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

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
WORKFLOW_NAME = "ROCKYOS-VM-TEMPLATE (WITH PATCHING)"

JT1_NAME = "ROCKYOS-VM-TEMPLATE"
JT2_NAME = "RHEL_Hardening"
JT3_NAME = "Offline_Patching_el8"

CREDENTIAL_NAME = "Linux Admin Credential"
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

# Fixed inventory and credential
wf.inventory = inv

# Disable launch prompts
wf.ask_inventory_on_launch = False
wf.ask_limit_on_launch = False
wf.ask_credential_on_launch = False

# Enable survey
wf.survey_enabled = True
wf.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more Rocky Linux 8 hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: rocky-08-01 or rocky-08-01,rocky-08-02 or rocky-08-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-08-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

wf.save()

# Attach credential
wf.credentials.clear()
wf.credentials.add(cred)

# ------------------------------------------------------------------
# Create Workflow Nodes
# ------------------------------------------------------------------

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

# ------------------------------------------------------------------
# Workflow Order
# ------------------------------------------------------------------

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

echo
echo "ROCKY Workflow created successfully."

# --------------------------------------------------------------
# Workflow : ROCKYOS-VM-TEMPLATE (WITHOUT PATCHING)
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Workflow: ROCKYOS-VM-TEMPLATE (WITHOUT PATCHING)${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

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
WORKFLOW_NAME = "ROCKYOS-VM-TEMPLATE (WITHOUT PATCHING)"

JT1_NAME = "ROCKYOS-VM-TEMPLATE"
JT2_NAME = "RHEL_Hardening"

CREDENTIAL_NAME = "Linux Admin Credential"
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

# Remove existing workflow nodes
wf.workflow_job_template_nodes.all().delete()

# Fixed inventory and credential
wf.inventory = inv

# Disable launch prompts
wf.ask_inventory_on_launch = False
wf.ask_limit_on_launch = False
wf.ask_credential_on_launch = False

# Enable survey
wf.survey_enabled = True
wf.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more Rocky Linux 8 hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: rocky-08-01 or rocky-08-01,rocky-08-02 or rocky-08-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-08-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

wf.save()

# Attach credential
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

# Execution order
n1.success_nodes.add(n2)

print(f"Workflow '{wf.name}' {'created' if created else 'updated'}")
print()
print("Execution Order")
print("----------------")
print(jt1.name)
print("   |")
print("   v")
print(jt2.name)

EOF

echo
echo "ROCKY Workflow created successfully."

# --------------------------------------------------------------
# Workflow : ROCKY9-VM-TEMPLATE-WF
# --------------------------------------------------------------

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Workflow: ROCKY9-VM-TEMPLATE-WF${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

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
WORKFLOW_NAME = "ROCKY9-VM-TEMPLATE-WF"

JT1_NAME = "ROCKY9-VM-TEMPLATE"
JT2_NAME = "RHEL_Hardening"
JT3_NAME = "Disable_SELinux_el9"
JT4_NAME = "Offline_Patching_el9"

CREDENTIAL_NAME = "Linux Admin Credential"
INVENTORY_NAME = "rocky-9-servers"

org = Organization.objects.get(name=ORG_NAME)

jt1 = JobTemplate.objects.get(name=JT1_NAME)
jt2 = JobTemplate.objects.get(name=JT2_NAME)
jt3 = JobTemplate.objects.get(name=JT3_NAME)
jt4 = JobTemplate.objects.get(name=JT4_NAME)

cred = Credential.objects.get(name=CREDENTIAL_NAME)
inv = Inventory.objects.get(name=INVENTORY_NAME)

wf, created = WorkflowJobTemplate.objects.get_or_create(
    name=WORKFLOW_NAME,
    organization=org
)

# Remove existing workflow nodes
wf.workflow_job_template_nodes.all().delete()

# Fixed inventory and credential
wf.inventory = inv

# Disable launch prompts
wf.ask_inventory_on_launch = False
wf.ask_limit_on_launch = False
wf.ask_credential_on_launch = False

# Enable survey
wf.survey_enabled = True
wf.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more Rocky Linux 9 hosts (without .vgs.com)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: rocky-09-01 or rocky-09-01,rocky-09-02 or rocky-09-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-09-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

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

n4 = WorkflowJobTemplateNode.objects.create(
    workflow_job_template=wf,
    unified_job_template=jt4
)

# Execution order
n1.success_nodes.add(n2)
n2.success_nodes.add(n3)
n3.success_nodes.add(n4)

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
print("   |")
print("   v")
print(jt4.name)
EOF

echo
echo "ROCKY 9 Workflow created successfully."


# ==============================================================================
# Verify Workflow Templates
# ==============================================================================

echo
echo -e "${MAGENTA}==========================================================${NC}"
echo -e "${WHITE}${BOLD} Verifying Workflow Templates${NC}"
echo -e "${MAGENTA}==========================================================${NC}"

awx-manage shell <<'EOF'
from awx.main.models import WorkflowJobTemplate

print("\n========== Workflow Verification ==========\n")

for wf in WorkflowJobTemplate.objects.all():
    print(f"Workflow : {wf.name}")

print("\nVerification Completed.")
EOF


echo
echo -e "${GREEN}===========================================================${NC}"
echo -e "${WHITE}${BOLD} Workflow Templates Completed${NC}"
echo -e "${GREEN}===========================================================${NC}"

echo
echo "Created:"
echo " ✓ Offline_Patching_el7"
echo " ✓ Offline_Patching_el8 "
echo " ✓ Offline_Patching_el9 "
echo " ✓ Disable_SELinux_el7 "
echo " ✓ Disable_SELinux_el8 "
echo " ✓ Disable_SELinux_el9 "
echo " ✓ Rocky-8 Post Migration "
echo " ✓ Rocky-9 Post Migration "
echo " ✓ Leapp Preupgrade Fixes "
echo " ✓ REPAIR-RESCUE "
echo " ✓ CENTOS-VM-TEMPLATE-WF "
echo " ✓ ROCKYOS-VM-TEMPLATE-WF "
echo " ✓ ROCKY9-VM-TEMPLATE-WF "

# ==============================================================================
# Subscription_Patching_EL7
# ==============================================================================

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Subscription_Patching_EL7${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import (
    Inventory,
    Project,
    JobTemplate,
    Credential
)

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="centos-07-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

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

# ==============================================================================
# Subscription_Patching_EL8
# ==============================================================================

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Subscription_Patching_EL8${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import (
    Inventory,
    Project,
    JobTemplate,
    Credential
)

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-8-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

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

# ==============================================================================
# Subscription_Patching_EL9
# ==============================================================================

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Subscription_Patching_EL9${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import (
    Inventory,
    Project,
    JobTemplate,
    Credential
)

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-9-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="Subscription_Patching_EL9",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "subscription_patching/patch-el9.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "subscription_patching/patch-el9.yml"
jt.ask_inventory_on_launch = False
jt.ask_limit_on_launch = False

jt.credentials.clear()
jt.credentials.add(credential)

survey_spec = {
    "name": "target_hosts",
    "description": "Rocky Linux 9 Subscription Patching",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Enter host or host pattern",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-09-*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.survey_enabled = True
jt.survey_spec = survey_spec

jt.save()

print(
    f"Subscription_Patching_EL9 "
    f"{'created' if created else 'updated'}"
)
EOF

awx-manage shell <<'EOF'
from awx.main.models import JobTemplate

jt = JobTemplate.objects.get(
    name="Subscription_Patching_EL9"
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

# ==============================================================================
# CENTOSTOROCKY
# ==============================================================================

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating CENTOSTOROCKY${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="centos-07-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="CENTOSTOROCKY",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "CENTOSTOROCKY/CENTOSTOROCKY.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "CENTOSTOROCKY/CENTOSTOROCKY.yml"

# Fixed inventory
jt.ask_inventory_on_launch = False

# Disable Limit
jt.ask_limit_on_launch = False

# Enable Survey
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more CentOS 7 hosts (without domain name)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: cent-07-01 or cent-07-01,cent-07-02 or cent-07-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "cent-07-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

jt.save()

jt.credentials.clear()
jt.credentials.add(credential)

print(
    f"Job Template 'CENTOSTOROCKY' "
    f"{'created' if created else 'updated'} successfully."
)
print(f"Credential assigned: {credential.name}")
EOF

# ==============================================================================
# Workflow : CENTOSTOROCKY-WF
# ==============================================================================

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Workflow: CENTOSTOROCKY-WF${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

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
WORKFLOW_NAME = "CENTOSTOROCKY-WF"

JT1_NAME = "Offline_Patching_el7"
JT2_NAME = "CENTOSTOROCKY"

CREDENTIAL_NAME = "Linux Admin Credential"
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

# Remove existing workflow nodes
wf.workflow_job_template_nodes.all().delete()

# Fixed inventory
wf.inventory = inv

# Disable prompts at workflow launch
wf.ask_inventory_on_launch = False
wf.ask_limit_on_launch = False
wf.ask_credential_on_launch = False

# Enable survey so target_hosts is prompted once
wf.survey_enabled = True
wf.survey_spec = {
    "name": "Target Host Selection",
    "description": "Enter one or more CentOS 7 hosts (without domain name)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: cent-07-01 or cent-07-01,cent-07-02 or cent-07-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "cent-07-0*",
            "min": 1,
            "max": 1024
        }
    ]
}

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

# Execution order
n1.success_nodes.add(n2)

print(f"Workflow '{wf.name}' {'created' if created else 'updated'}")
print("Execution Order:")
print(f"  {jt1.name}")
print("      ↓")
print(f"  {jt2.name}")
EOF

echo
echo "CENTOSTOROCKY Workflow created successfully."

# ==============================================================================
# ROCKY8TOROCKY9
# ==============================================================================

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating ROCKY8TOROCKY9${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import Inventory, Project, JobTemplate, Credential

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-8-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="ROCKY8TOROCKY9",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "ROCKY8TOROCKY9/ROCKY8TOROCKY9.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "survey_enabled": True,
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "ROCKY8TOROCKY9/ROCKY8TOROCKY9.yml"

jt.ask_inventory_on_launch = False
jt.ask_limit_on_launch = False
jt.survey_enabled = True

jt.survey_spec = {
    "name": "Rocky Linux Migration",
    "description": "Select target hosts and Rocky Linux repository version.",
    "spec": [

        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: rocky-08-01 or rocky-08-01,rocky-08-02 or rocky-08-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-08-0*",
            "min": 1,
            "max": 1024
        },

        {
            "type": "multiplechoice",
            "question_name": "Target Rocky Linux Repository",
            "question_description": "Select the offline Rocky Linux repository to use.",
            "variable": "target_os",
            "required": True,
            "default": "rocky9",
            "choices": "rocky9\nrocky9.2"
        }

    ]
}

jt.save()

jt.credentials.clear()
jt.credentials.add(credential)

print(
    f"Job Template 'ROCKY8TOROCKY9' "
    f"{'created' if created else 'updated'} successfully."
)
print(f"Credential assigned: {credential.name}")

EOF

# ==============================================================================
# Workflow : ROCKY8TOROCKY9-PATCHING-WF
# ==============================================================================

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Workflow: ROCKY8TOROCKY9-PATCHING-WF${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

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
WORKFLOW_NAME = "ROCKY8TOROCKY9-PATCHING-WF"

JT1_NAME = "Offline_Patching_el8"
JT2_NAME = "ROCKY8TOROCKY9"
JT3_NAME = "REPAIR-RESCUE"

CREDENTIAL_NAME = "Linux Admin Credential"
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

# --------------------------------------------------------------------------
# Remove existing workflow nodes
# --------------------------------------------------------------------------

wf.workflow_job_template_nodes.all().delete()

# --------------------------------------------------------------------------
# Workflow configuration
# --------------------------------------------------------------------------

wf.inventory = inv

wf.ask_inventory_on_launch = False
wf.ask_limit_on_launch = False
wf.ask_credential_on_launch = False

# --------------------------------------------------------------------------
# Workflow Survey
# --------------------------------------------------------------------------

wf.survey_enabled = True
wf.survey_spec = {
    "name": "Rocky Linux 8 to Rocky Linux 9 Migration",
    "description": "Select target hosts and target Rocky Linux repository.",
    "spec": [

        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: rocky-08-01 or rocky-08-01,rocky-08-02 or rocky-08-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-08-0*",
            "min": 1,
            "max": 1024
        },

        {
            "type": "multiplechoice",
            "question_name": "Target Rocky Linux Repository",
            "question_description": "Select the target Rocky Linux repository.",
            "variable": "target_os",
            "required": True,
            "default": "9",
            "choices": "9\n9.2"
        }

    ]
}

wf.save()

# --------------------------------------------------------------------------
# Assign credential
# --------------------------------------------------------------------------

wf.credentials.clear()
wf.credentials.add(cred)

# --------------------------------------------------------------------------
# Create workflow nodes
# --------------------------------------------------------------------------

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

# --------------------------------------------------------------------------
# Workflow execution order
# --------------------------------------------------------------------------

n1.success_nodes.add(n2)
n2.success_nodes.add(n3)

print(f"Workflow '{wf.name}' {'created' if created else 'updated'} successfully.")
print("")
print("Execution Order:")
print(f"  {jt1.name}")
print("      ↓")
print(f"  {jt2.name}")
print("      ↓")
print(f"  {jt3.name}")

EOF

echo
echo -e "${GREEN}ROCKY8TOROCKY9-PATCHING-WF created successfully.${NC}"

# ==============================================================================
# Workflow : ROCKY8TOROCKY9-WF
# ==============================================================================

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Workflow: ROCKY8TOROCKY9-WF${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

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
WORKFLOW_NAME = "ROCKY8TOROCKY9-WF"

JT1_NAME = "ROCKY8TOROCKY9"
JT2_NAME = "REPAIR-RESCUE"

CREDENTIAL_NAME = "Linux Admin Credential"
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

# --------------------------------------------------------------------------
# Remove existing workflow nodes
# --------------------------------------------------------------------------

wf.workflow_job_template_nodes.all().delete()

# --------------------------------------------------------------------------
# Workflow configuration
# --------------------------------------------------------------------------

wf.inventory = inv

wf.ask_inventory_on_launch = False
wf.ask_limit_on_launch = False
wf.ask_credential_on_launch = False

# --------------------------------------------------------------------------
# Workflow Survey
# --------------------------------------------------------------------------

wf.survey_enabled = True
wf.survey_spec = {
    "name": "Rocky Linux 8 to Rocky Linux 9 Migration",
    "description": "Select target hosts and target Rocky Linux repository.",
    "spec": [

        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Examples: rocky-08-01 or rocky-08-01,rocky-08-02 or rocky-08-0*",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-08-0*",
            "min": 1,
            "max": 1024
        },

        {
            "type": "multiplechoice",
            "question_name": "Target Rocky Linux Repository",
            "question_description": "Select the target Rocky Linux repository.",
            "variable": "target_os",
            "required": True,
            "default": "9",
            "choices": "9\n9.2"
        }

    ]
}

wf.save()

# --------------------------------------------------------------------------
# Assign credential
# --------------------------------------------------------------------------

wf.credentials.clear()
wf.credentials.add(cred)

# --------------------------------------------------------------------------
# Create workflow nodes
# --------------------------------------------------------------------------

n1 = WorkflowJobTemplateNode.objects.create(
    workflow_job_template=wf,
    unified_job_template=jt1
)

n2 = WorkflowJobTemplateNode.objects.create(
    workflow_job_template=wf,
    unified_job_template=jt2
)

# --------------------------------------------------------------------------
# Workflow execution order
# --------------------------------------------------------------------------

n1.success_nodes.add(n2)

print(f"Workflow '{wf.name}' {'created' if created else 'updated'} successfully.")
print("")
print("Execution Order:")
print(f"  {jt1.name}")
print("      ↓")
print(f"  {jt2.name}")

EOF

echo
echo -e "${GREEN}ROCKY8TOROCKY9-WF created successfully.${NC}"

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

# ==============================================================================
# Provision_Hosts_el7
# ==============================================================================

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Provision_Hosts_el7${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import (
    Inventory,
    Project,
    JobTemplate,
    Credential
)

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="centos-07-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

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

jt.credentials.clear()
jt.credentials.add(credential)

survey_spec = {
    "name": "Provision_Hosts_el7",
    "description": "Provision EL7 Hosts",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Hostname(s) or wildcard (example: cent-07-01,cent-07-05 or cent-07-*)",
            "variable": "target_hosts",
            "required": True,
            "default": "cent-07-*",
            "min": 1,
            "max": 1024
        },
        {
            "type": "integer",
            "question_name": "Foreman Server",
            "question_description": "1 = Frontend (rocky-08-01), 2 = Backend (cent-07-01)",
            "variable": "foreman_server",
            "required": False,
            "default": 1,
            "min": 1,
            "max": 2
        },
        {
            "type": "integer",
            "question_name": "Host Group",
            "question_description": "1 = CentOS (Default), 2 = Rocky 8, 3 = Rocky 9.2, 4 = Rocky 9.8",
            "variable": "hostgroup",
            "required": False,
            "default": 1,
            "min": 1,
            "max": 4
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

print("\nSurvey Variables")
for q in jt.survey_spec["spec"]:
    print(f" - {q['variable']} (default={q.get('default')})")
EOF

echo
echo "Provision_Hosts_el7 completed successfully."

# ==============================================================================
# Provision_Hosts_el8
# ==============================================================================

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Provision_Hosts_el8${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import (
    Inventory,
    Project,
    JobTemplate,
    Credential
)

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-8-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

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

jt.ask_inventory_on_launch = False
jt.ask_limit_on_launch = False
jt.limit = "localhost"

jt.credentials.clear()
jt.credentials.add(credential)

survey_spec = {
    "name": "Provision_Hosts_el8",
    "description": "Provision EL8 Hosts",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Hostname(s) or wildcard (example: rocky-08-01,rocky-08-03 or rocky-08-*)",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-08-*",
            "min": 1,
            "max": 1024
        },
        {
            "type": "integer",
            "question_name": "Foreman Server",
            "question_description": "1 = Frontend (rocky-08-01), 2 = Backend (cent-07-01)",
            "variable": "foreman_server",
            "required": False,
            "default": 1,
            "min": 1,
            "max": 2
        },
        {
            "type": "integer",
            "question_name": "Host Group",
            "question_description": "1 = CentOS (Default), 2 = Rocky 8, 3 = Rocky 9.2, 4 = Rocky 9.8",
            "variable": "hostgroup",
            "required": False,
            "default": 1,
            "min": 1,
            "max": 4
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
print("Default Limit: localhost")
print("Survey enabled.")
EOF


# ==============================================================
# Verify Provision_Hosts_el8
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import JobTemplate

jt = JobTemplate.objects.get(name="Provision_Hosts_el8")

print()
print("Template :", jt.name)
print("Playbook :", jt.playbook)
print("Inventory:", jt.inventory.name)
print("Limit    :", jt.limit)
print("Survey   :", jt.survey_enabled)

print("\nCredentials")
for c in jt.credentials.all():
    print(" -", c.name)

print("\nSurvey Variables")
for q in jt.survey_spec["spec"]:
    print(f" - {q['variable']} (default={q.get('default')})")
EOF

echo
echo "Provision_Hosts_el8 completed successfully."

# ==============================================================================
# Provision_Hosts_el9
# ==============================================================================

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Provision_Hosts_el9${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

awx-manage shell <<'EOF'
from awx.main.models import (
    Inventory,
    Project,
    JobTemplate,
    Credential
)

project = Project.objects.get(name="Inventory-Git-Repo")
inventory = Inventory.objects.get(name="rocky-9-servers")
credential = Credential.objects.get(name="Linux Admin Credential")

jt, created = JobTemplate.objects.get_or_create(
    name="Provision_Hosts_el9",
    defaults={
        "project": project,
        "inventory": inventory,
        "playbook": "provision_hosts_el9/Foreman_provision_hosts_el9.yml",
        "ask_inventory_on_launch": False,
        "ask_limit_on_launch": False,
        "limit": "localhost"
    }
)

jt.project = project
jt.inventory = inventory
jt.playbook = "provision_hosts_el9/Foreman_provision_hosts_el9.yml"

jt.ask_inventory_on_launch = False
jt.ask_limit_on_launch = False
jt.limit = "localhost"

jt.credentials.clear()
jt.credentials.add(credential)

survey_spec = {
    "name": "Provision_Hosts_el9",
    "description": "Provision EL9 Hosts",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Hostname(s) or wildcard (example: rocky-09-01,rocky-09-03 or rocky-09-*)",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-09-*",
            "min": 1,
            "max": 1024
        },
        {
            "type": "integer",
            "question_name": "Foreman Server",
            "question_description": "1 = Frontend (rocky-08-01), 2 = Backend (cent-07-01)",
            "variable": "foreman_server",
            "required": False,
            "default": 1,
            "min": 1,
            "max": 2
        },
        {
            "type": "integer",
            "question_name": "Host Group",
            "question_description": "1 = CentOS (Default), 2 = Rocky 8, 3 = Rocky 9.2, 4 = Rocky 9.8",
            "variable": "hostgroup",
            "required": False,
            "default": 1,
            "min": 1,
            "max": 4
        }
    ]
}

jt.survey_enabled = True
jt.survey_spec = survey_spec

jt.save()

print(
    f"Provision_Hosts_el9 "
    f"{'created' if created else 'updated'} successfully."
)
print(f"Credential assigned: {credential.name}")
print("Default Limit: localhost")
print("Survey enabled.")
EOF


# ==============================================================
# Verify Provision_Hosts_el9
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import JobTemplate

jt = JobTemplate.objects.get(name="Provision_Hosts_el9")

print()
print("Template :", jt.name)
print("Playbook :", jt.playbook)
print("Inventory:", jt.inventory.name)
print("Limit    :", jt.limit)
print("Survey   :", jt.survey_enabled)

print("\nCredentials")
for c in jt.credentials.all():
    print(" -", c.name)

print("\nSurvey Variables")
for q in jt.survey_spec["spec"]:
    print(f" - {q['variable']} (default={q.get('default')})")
EOF

echo
echo "Provision_Hosts_el9 completed successfully."

# ==============================================================================
# Workflow : Provision_Hosts_el7_Subscription_Patching_EL7
# ==============================================================================

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Workflow: Provision_Hosts_el7_Subscription_Patching_EL7${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

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
JT2_NAME = "RHEL_Hardening"
JT3_NAME = "Subscription_Patching_EL7"

CREDENTIAL_NAME = "Linux Admin Credential"
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
    "name": "Provision_Hosts_el7_Subscription_Patching_EL7",
    "description": "Provision Hosts + Hardening + Subscription Patching (EL7)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Hostname(s) or wildcard (example: cent-07-01,cent-07-05 or cent-07-*)",
            "variable": "target_hosts",
            "required": True,
            "default": "cent-07-*",
            "min": 1,
            "max": 1024
        },
        {
            "type": "integer",
            "question_name": "Foreman Server",
            "question_description": "1 = Frontend (rocky-08-01), 2 = Backend (cent-07-01)",
            "variable": "foreman_server",
            "required": False,
            "default": 1,
            "min": 1,
            "max": 2
        },
        {
            "type": "integer",
            "question_name": "Host Group",
            "question_description": "1 = CentOS (Default), 2 = Rocky 8, 3 = Rocky 9.2, 4 = Rocky 9.8",
            "variable": "hostgroup",
            "required": False,
            "default": 1,
            "min": 1,
            "max": 4
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

n3 = WorkflowJobTemplateNode.objects.create(
    workflow_job_template=wf,
    unified_job_template=jt3
)

# --------------------------------------------------------------
# Execution Flow
# --------------------------------------------------------------
n1.success_nodes.add(n2)
n2.success_nodes.add(n3)

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
print("   |")
print("   v")
print(jt3.name)
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

# ==============================================================================
# Workflow : Provision_Hosts_el8_Subscription_Patching_EL8
# ==============================================================================

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Workflow: Provision_Hosts_el8_Subscription_Patching_EL8${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

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
JT2_NAME = "RHEL_Hardening"
JT3_NAME = "Subscription_Patching_EL8"

CREDENTIAL_NAME = "Linux Admin Credential"
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
    "name": "Provision_Hosts_el8_Subscription_Patching_EL8",
    "description": "Provision Hosts + Hardening + Subscription Patching (EL8)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Hostname(s) or wildcard (example: rocky-08-01,rocky-08-05 or rocky-08-*)",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-08-*",
            "min": 1,
            "max": 1024
        },
        {
            "type": "integer",
            "question_name": "Foreman Server",
            "question_description": "1 = Frontend (rocky-08-01), 2 = Backend (cent-07-01)",
            "variable": "foreman_server",
            "required": False,
            "default": 1,
            "min": 1,
            "max": 2
        },
        {
            "type": "integer",
            "question_name": "Host Group",
            "question_description": "1 = CentOS, 2 = Rocky 8 (Default), 3 = Rocky 9.2, 4 = Rocky 9.8",
            "variable": "hostgroup",
            "required": False,
            "default": 2,
            "min": 1,
            "max": 4
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

n3 = WorkflowJobTemplateNode.objects.create(
    workflow_job_template=wf,
    unified_job_template=jt3
)

# --------------------------------------------------------------
# Execution Flow
# --------------------------------------------------------------
n1.success_nodes.add(n2)
n2.success_nodes.add(n3)

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
print("   |")
print("   v")
print(jt3.name)
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

# ==============================================================================
# Workflow : Provision_Hosts_el9_Subscription_Patching_EL9
# ==============================================================================

echo
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"
echo -e "${WHITE} Creating Workflow: Provision_Hosts_el9_Subscription_Patching_EL9${NC}"
echo -e "${YELLOW}------------------------------------------------------------------------------${NC}"

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
WORKFLOW_NAME = "Provision_Hosts_el9_Subscription_Patching_EL9"

JT1_NAME = "Provision_Hosts_el9"
JT2_NAME = "RHEL_Hardening"
JT3_NAME = "Subscription_Patching_EL9"

CREDENTIAL_NAME = "Linux Admin Credential"
INVENTORY_NAME = "rocky-9-servers"

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
    "name": "Provision_Hosts_el9_Subscription_Patching_EL9",
    "description": "Provision Hosts + Hardening + Subscription Patching (EL9)",
    "spec": [
        {
            "type": "text",
            "question_name": "Target Hosts",
            "question_description": "Hostname(s) or wildcard (example: rocky-09-01,rocky-09-05 or rocky-09-*)",
            "variable": "target_hosts",
            "required": True,
            "default": "rocky-09-*",
            "min": 1,
            "max": 1024
        },
        {
            "type": "integer",
            "question_name": "Foreman Server",
            "question_description": "1 = Frontend (rocky-08-01), 2 = Backend (cent-07-01)",
            "variable": "foreman_server",
            "required": False,
            "default": 1,
            "min": 1,
            "max": 2
        },
        {
            "type": "integer",
            "question_name": "Host Group",
            "question_description": "1 = CentOS, 2 = Rocky 8, 3 = Rocky 9.2, 4 = Rocky 9.8 (Default)",
            "variable": "hostgroup",
            "required": False,
            "default": 4,
            "min": 1,
            "max": 4
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

n3 = WorkflowJobTemplateNode.objects.create(
    workflow_job_template=wf,
    unified_job_template=jt3
)

# --------------------------------------------------------------
# Execution Flow
# --------------------------------------------------------------
n1.success_nodes.add(n2)
n2.success_nodes.add(n3)

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
print("   |")
print("   v")
print(jt3.name)
EOF


# ==============================================================
# Verify Provision_Hosts_el9_Subscription_Patching_EL9
# ==============================================================

awx-manage shell <<'EOF'
from awx.main.models import WorkflowJobTemplate

wf = WorkflowJobTemplate.objects.get(
    name="Provision_Hosts_el9_Subscription_Patching_EL9"
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
echo "Provision_Hosts_el9_Subscription_Patching_EL9 workflow completed successfully."

# ==============================================================================
# Final Verification
# ==============================================================================

echo
echo -e "${MAGENTA}==========================================================${NC}"
echo -e "${WHITE}${BOLD} Running Final Verification${NC}"
echo -e "${MAGENTA}==========================================================${NC}"

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

# ==============================================================================
# Bootstrap Summary
# ==============================================================================

echo
echo -e "${GREEN}==========================================================${NC}"
echo -e "${WHITE}${BOLD} Bootstrap Summary${NC}"
echo -e "${GREEN}==========================================================${NC}"

echo
echo "Credential Types:"
echo "  ✓ NetBox API Token"

echo
echo "Credentials:"
echo "  ✓ NetBox Production Credential"
echo "  ✓ Linux Root Credential"

echo
echo "Inventories:"
echo "  ✓ centos-07-servers"
echo "  ✓ rocky-8-servers"
echo "  ✓ rocky-9-servers"

echo
echo "Projects:"
echo "  ✓ Inventory-Git-Repo"

echo
echo "Inventory Sources:"
echo "  ✓ centos-07-servers"
echo "  ✓ rocky-8-servers"
echo "  ✓ rocky-9-servers"

echo
echo "Job Templates:"
echo "  ✓ Enable_Passwordless_SSH"
echo "  ✓ create_admin_ssh"
echo "  ✓ RHEL_Hardening"
echo "  ✓ Local_DNS"
echo "  ✓ CENTOS-VM-TEMPLATE"
echo "  ✓ ROCKYOS-VM-TEMPLATE"
echo "  ✓ ROCKY9-VM-TEMPLATE"
echo "  ✓ Disable_SELinux_el7"
echo "  ✓ Disable_SELinux_el8"
echo "  ✓ Disable_SELinux_el9"
echo " ✓ Rocky-8 Post Migration "
echo " ✓ Rocky-9 Post Migration "
echo " ✓ Leapp Preupgrade Fixes "
echo " ✓ REPAIR-RESCUE "
echo "  ✓ Offline_Patching_el7"
echo "  ✓ Offline_Patching_el8"
echo "  ✓ Offline_Patching_el9"
echo "  ✓ Subscription_Patching_EL7"
echo "  ✓ Subscription_Patching_EL8"
echo "  ✓ Subscription_Patching_EL9"
echo "  ✓ CENTOSTOROCKY"
echo " ✓ ROCKY8TOROCKY9"
echo "  ✓ Provision_Hosts_el7"
echo "  ✓ Provision_Hosts_el8"
echo "  ✓ Provision_Hosts_el9"

echo
echo "Workflow Templates:"
echo "  ✓ CENTOS-VM-TEMPLATE-WF"
echo "  ✓ ROCKYOS-VM-TEMPLATE-WF"
echo "  ✓ ROCKY9-VM-TEMPLATE-WF"
echo "  ✓ CENTOSTOROCKY-WF"
echo " ✓ ROCKY8TOROCKY9-WF"
echo "  ✓ Provision_Hosts_el7_Subscription_Patching_EL7"
echo "  ✓ Provision_Hosts_el8_Subscription_Patching_EL8"
echo "  ✓ Provision_Hosts_el9_Subscription_Patching_EL9"

echo
echo -e "${GREEN}==========================================================${NC}"
echo -e "${WHITE}${BOLD} AWX Bootstrap Completed Successfully${NC}"
echo -e "${GREEN}==========================================================${NC}"
CONTAINER

echo
echo "Bootstrap completed successfully."
