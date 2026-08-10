# Foreman Bootstrap Scripts

## 01_foreman_pxe_bootstrap.sh

```bash
export FOREMAN_USER=admin
export FOREMAN_PASSWORD='zqs977dXzqfEvTML'
./01_foreman_pxe_bootstrap.sh
```

## 02_foreman_katello_bootstrap.sh

```bash
export FOREMAN_USER=admin
export FOREMAN_PASSWORD='zqs977dXzqfEvTML'
./02_foreman_katello_bootstrap.sh
```

## 02_foreman_pxe_bootstrap_single_disk.sh

```bash
export FOREMAN_USER=admin
export FOREMAN_PASSWORD='zqs977dXzqfEvTML'
./02_foreman_pxe_bootstrap_single_disk.sh
```

## 03_foreman_hostgroup_bootstrap_raid.sh

```bash
export FOREMAN_USER=admin
export FOREMAN_PASSWORD='zqs977dXzqfEvTML'
./03_foreman_hostgroup_bootstrap_raid.sh
```

## 03_foreman_hostgroup_bootstrap_single_disk.sh

```bash
export FOREMAN_USER=admin
export FOREMAN_PASSWORD='zqs977dXzqfEvTML'
./03_foreman_hostgroup_bootstrap_single_disk.sh
```

## 04-bootstrap-el7toel8.sh

```bash
export FOREMAN_USER=admin
export FOREMAN_PASSWORD='zqs977dXzqfEvTML'
./04-bootstrap-el7toel8.sh
```

## 05-bootstrap-el8toel9.sh

### Rocky Linux 9.2

```bash
export FOREMAN_USER=admin
export FOREMAN_PASSWORD='zqs977dXzqfEvTML'
export TARGET_VERSION=9.2
./05-bootstrap-el8toel9.sh
```

### Rocky Linux 9.8

```bash
export FOREMAN_USER=admin
export FOREMAN_PASSWORD='zqs977dXzqfEvTML'
export TARGET_VERSION=9.8
./05-bootstrap-el8toel9.sh
```
