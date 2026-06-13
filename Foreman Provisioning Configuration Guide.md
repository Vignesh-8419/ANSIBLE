# Foreman Provisioning Configuration Guide

This document describes the Foreman configuration used for PXE-based provisioning of CentOS 7 and Rocky Linux 8 systems.

---

# Environment Details

| Component | Value |
|-----------|---------|
| Foreman Server | rocky-08-01.vgs.com |
| Smart Proxy (CentOS) | rocky-08-01.vgs.com |
| Smart Proxy (Rocky) | rocky-08-02.vgs.com |
| Organization | Default Organization |
| Location | Default Location |
| Domain | vgs.com |
| Network | 192.168.253.0/24 |

---

# Installation Media Configuration

Navigate to:

```
Hosts → Provisioning Setup → Installation Media
```

The following installation media have been configured.

## CentOS 7 Remote

| Parameter | Value |
|------------|---------|
| Name | CentOS 7 Remote |
| Path | http://192.168.253.136/repo/centos/ |
| OS Family | Red Hat |
| Operating System | CentOSLinux 7 |

### Purpose

Used as the package source during CentOS 7 operating system installation.

---

## Rocky 8 Remote

| Parameter | Value |
|------------|---------|
| Name | Rocky 8 Remote |
| Path | http://192.168.253.130/repo/rocky8/ |
| OS Family | Red Hat |
| Operating System | RockyLinux 8.10 |

### Purpose

Used as the package repository for Rocky Linux 8 provisioning.

---

# Operating Systems Configuration

Navigate to:

```
Hosts → Provisioning Setup → Operating Systems
```

Configured operating systems:

| Operating System | Hosts Assigned |
|------------------|----------------|
| CentOSLinux 7 | 1 |
| Rocky Linux 8.10 | 2 |
| Rocky Linux 8.10 | 0 |

## Notes

- CentOS Linux 7 is available for provisioning.
- Rocky Linux 8.10 definitions exist for multiple provisioning scenarios.
- Host count indicates systems currently associated with each operating system entry.

---

# PXE Provisioning Templates

Navigate to:

```
Hosts → Templates → Provisioning Templates (available on Foreman PXE UEFI Kickstart Templates.md)
```

Filtered using keyword:

```
UEFI
```

Configured templates:

---

## PXEGrub2 CentOS UEFI Static Kickstart

| Parameter | Value |
|------------|---------|
| Kind | PXEGrub2 Template |
| Locked | No |
| Snippet | No |

### Purpose

Provides UEFI PXE boot instructions for CentOS 7 automated installations.

---

## pxegrub2_mac

| Parameter | Value |
|------------|---------|
| Type | Snippet |
| Locked | Yes |

### Purpose

Reusable PXE template snippet utilized by other provisioning templates.

---

## PXEGrub2 Rocky8 UEFI Static Kickstart

| Parameter | Value |
|------------|---------|
| Kind | PXEGrub2 Template |
| Locked | No |
| Snippet | No |

### Purpose

Supplies UEFI PXE boot configuration for Rocky Linux 8 kickstart deployments.

---

# Smart Proxy Configuration

Navigate to:

```
Infrastructure → Smart Proxies
```

Two Smart Proxies have been configured.

---

## Smart Proxy: rocky-08-01.vgs.com

| Parameter | Value |
|------------|---------|
| Location | Default Location |
| Organization | Default Organization |
| Status | Healthy |

### Enabled Features

- DHCP
- TFTP
- Templates
- Logs
- Pulpcore

### Purpose

Acts as the provisioning proxy for CentOS-based deployments.

---

## Smart Proxy: rocky-08-02.vgs.com

| Parameter | Value |
|------------|---------|
| Location | Default Location |
| Organization | Default Organization |
| Status | Healthy |

### Enabled Features

- Container Gateway
- DHCP
- DNS
- Logs
- Pulpcore
- Additional proxy services

### Purpose

Provides provisioning and content management services for Rocky Linux deployments.

---

# Subnet Configuration

Navigate to:

```
Infrastructure → Subnets
```

Configured subnets:

---

## vgs-subnet-centos

| Parameter | Value |
|------------|---------|
| Network Address | 192.168.253.0/24 |
| Domain | vgs.com |
| DHCP Proxy | rocky-08-01.vgs.com |
| Hosts | 1 |

### Purpose

Subnet dedicated to CentOS provisioning activities.

---

## vgs-subnet-rocky

| Parameter | Value |
|------------|---------|
| Network Address | 192.168.253.0/24 |
| Domain | vgs.com |
| DHCP Proxy | rocky-08-02.vgs.com |
| Hosts | 0 |

### Purpose

Subnet associated with Rocky Linux provisioning.

---

# Provisioning Workflow

The provisioning process follows the sequence below:

```
Host Boot
    ↓
DHCP Assignment
    ↓
Smart Proxy Selection
    ↓
TFTP/PXE Boot
    ↓
PXEGrub2 UEFI Template
    ↓
Kickstart Configuration
    ↓
Installation Media Repository
    ↓
Automated Operating System Deployment
```

---

# Validation Checklist

- [x] Installation media configured for CentOS and Rocky Linux.
- [x] Operating systems created in Foreman.
- [x] UEFI PXE templates available.
- [x] Smart Proxies registered and healthy.
- [x] DHCP proxies assigned to subnets.
- [x] Repository URLs accessible.
- [x] Foreman ready for automated PXE provisioning.

---

# Conclusion

The Foreman environment is configured to provision CentOS 7 and Rocky Linux 8.10 systems using UEFI PXE boot, Kickstart automation, installation media repositories, Smart Proxies, and subnet-specific DHCP services. This setup enables centralized and repeatable operating system deployments across the infrastructure.
