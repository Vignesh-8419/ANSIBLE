# Golden Template Deployment Commands

## Deploy all three

```bash
ansible-playbook deploy_golden_templates.yml
```

## Deploy only CentOS 7

```bash
ansible-playbook deploy_golden_templates.yml \
  -e 'deploy_templates=["CENTOS_07"]'
```

## Deploy only Rocky 8

```bash
ansible-playbook deploy_golden_templates.yml \
  -e 'deploy_templates=["ROCKYOS_08"]'
```

## Deploy only Rocky 9

```bash
ansible-playbook deploy_golden_templates.yml \
  -e 'deploy_templates=["ROCKYOS_09"]'
```

# ============================================================
#                    ANSIBLE LAB SHORTCUTS
# ============================================================

ESXI-01() {
    ansible-playbook ~/ANSIBLE/install_esxi_workstation.yml "$@"
}

GOLDEN-DEPLOY() {
    ansible-playbook ~/ANSIBLE/deploy_golden_templates.yml "$@"
}

LAB-POWER() {
    ansible-playbook ~/ANSIBLE/vmware_lab_power.yml "$@"
}

ESXI-POWER() {
    ansible-playbook ~/ANSIBLE/esxi_vm_power.yml "$@"
}

ROCKY08-DEPLOY() {
    ansible-playbook ~/ANSIBLE/deploy_rocky08_servers.yml "$@"
}

MANAGE-ESXI() {
    ansible-playbook ~/ANSIBLE/manage_esxi_vcenter_host.yml "$@"
}

CONVERT-TEMPLATE() {
    ansible-playbook ~/ANSIBLE/convert_golden_vms_to_templates.yml "$@"
}

ansible-banner() {
    echo
    echo "=============================================================="
    echo "                 ANSIBLE LAB PLAYBOOK SHORTCUTS"
    echo "=============================================================="
    echo
    printf "%-22s %s\n" "KEYWORD"          "PLAYBOOK"
    echo "--------------------------------------------------------------"
    printf "%-22s %s\n" "ESXI-01"          "install_esxi_workstation.yml"
    printf "%-22s %s\n" "GOLDEN-DEPLOY"    "deploy_golden_templates.yml"
    printf "%-22s %s\n" "LAB-POWER"        "vmware_lab_power.yml"
    printf "%-22s %s\n" "ESXI-POWER"       "esxi_vm_power.yml"
    printf "%-22s %s\n" "ROCKY08-DEPLOY"   "deploy_rocky08_servers.yml"
    printf "%-22s %s\n" "MANAGE-ESXI"      "manage_esxi_vcenter_host.yml"
    printf "%-22s %s\n" "CONVERT-TEMPLATE" "convert_golden_vms_to_templates.yml"
    echo "=============================================================="
    echo
}

export ANSIBLE_CONFIG=~/ansible.cfg
