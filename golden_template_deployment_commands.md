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
