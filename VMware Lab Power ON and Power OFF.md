# VMware Lab Power ON and Power OFF

## Power ON ESXi Host

```bash
ansible-playbook vmware_lab_power.yml -e "target_vm=esxi action=on"
```

## Power OFF ESXi Host

```bash
ansible-playbook vmware_lab_power.yml -e "target_vm=esxi action=off"
```

## Power ON vCenter

```bash
ansible-playbook vmware_lab_power.yml -e "target_vm=vcenter action=on"
```

## Power OFF vCenter

```bash
ansible-playbook vmware_lab_power.yml -e "target_vm=vcenter action=off"
```

## Power ON Both ESXi and vCenter

```bash
ansible-playbook vmware_lab_power.yml -e "target_vm=all action=on"
```

Power ON sequence:

```text
ESXi Host
   ↓
vCenter
```

## Power OFF Both ESXi and vCenter

```bash
ansible-playbook vmware_lab_power.yml -e "target_vm=all action=off"
```

Power OFF sequence:

```text
vCenter
   ↓
ESXi Host
```
