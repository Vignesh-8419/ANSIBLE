# VMware Lab Power ON and Power OFF Commands

## Power ON ESXi Host

```bash
ansible-playbook vmware_lab_power.yml -e "target_vm=esxi power=on"
```

## Power OFF ESXi Host

```bash
ansible-playbook vmware_lab_power.yml -e "target_vm=esxi power=off"
```

## Power ON vCenter

```bash
ansible-playbook vmware_lab_power.yml -e "target_vm=vcenter power=on"
```

## Power OFF vCenter

```bash
ansible-playbook vmware_lab_power.yml -e "target_vm=vcenter power=off"
```

## Power ON Both ESXi and vCenter

```bash
ansible-playbook vmware_lab_power.yml -e "target_vm=all power=on"
```

## Power OFF Both ESXi and vCenter

```bash
ansible-playbook vmware_lab_power.yml -e "target_vm=all power=off"
```
