# Foreman Provisioning Configuration Guide

This document describes the Foreman configuration used for PXE-based provisioning of CentOS 7 and Rocky Linux 8 systems across the infrastructure.

---

## Environment Details

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

## Installation Media Configuration

Navigate to: `Hosts → Provisioning Setup → Installation Media`

The following installation media have been configured:

### CentOS 7 Remote

| Parameter | Value |
|------------|---------|
| Name | CentOS 7 Remote |
| Path | http://192.168.253.136/repo/centos/ |
| OS Family | Red Hat |
| Operating System | CentOSLinux 7 |

* **Purpose:** Used as the package source during CentOS 7 operating system installation.

### Rocky 8 Remote

| Parameter | Value |
|------------|---------|
| Name | Rocky 8 Remote |
| Path | http://192.168.253.130/repo/rocky8/ |
| OS Family | Red Hat |
| Operating System | RockyLinux 8.10 |

* **Purpose:** Used as the package repository for Rocky Linux 8 provisioning.

---

## Operating Systems Configuration

Navigate to: `Hosts → Provisioning Setup → Operating Systems`

`Operating Systems 
        |
Name: RockyLinux
        |
Major Version: 8.10
        |
Family: Redhat
        |`

`Partition Tables -> Partition Tables: Kickstart Default`
`Installation Media -> Installation Media: CentOS 07 Remote`
`submit (After submit again select CentOS 07 Remoet from Operating system and got to template tab select PXEGrub2 template: PXEGrub2 CentOS UEFI Static Kickstart)`

Configured operating systems:

| Operating System | Hosts Assigned |
|------------------|----------------|
| CentOSLinux 7 | 1 |
| Rocky Linux 8.10 | 2 |

* **Note:** Host count indicates systems currently associated with each operating system entry.

---

## PXE Provisioning Templates

Navigate to: `Hosts → Templates → Provisioning Templates`
*Filtered using keyword: `UEFI`*

### PXEGrub2 CentOS UEFI Static Kickstart

| Parameter | Value |
|------------|---------|
| Kind | PXEGrub2 Template |
| Locked | No |
| Snippet | No |

* **Purpose:** Provides UEFI PXE boot instructions for CentOS 7 automated installations.

### pxegrub2_mac

| Parameter | Value |
|------------|---------|
| Type | Snippet |
| Locked | Yes |

* **Purpose:** Reusable PXE template snippet utilized by other provisioning templates.

### PXEGrub2 Rocky8 UEFI Static Kickstart

| Parameter | Value |
|------------|---------|
| Kind | PXEGrub2 Template |
| Locked | No |
| Snippet | No |

* **Purpose:** Supplies UEFI PXE boot configuration for Rocky Linux 8 kickstart deployments Please find readme file on Vignesh-8419/ANSIBLE - Foreman PXE UEFI Kickstart Templates.md.

---

## Smart Proxy Configuration

Navigate to: `Infrastructure → Smart Proxies`

### Smart Proxy: rocky-08-01.vgs.com

| Parameter | Value |
|------------|---------|
| Location | Default Location |
| Organization | Default Organization |
| Status | Healthy |

* **Enabled Features:** DHCP, TFTP, Templates, Logs, Pulpcore
* **Purpose:** Acts as the provisioning proxy for CentOS-based deployments.

### Smart Proxy: rocky-08-02.vgs.com

| Parameter | Value |
|------------|---------|
| Location | Default Location |
| Organization | Default Organization |
| Status | Healthy |

* **Enabled Features:** Container Gateway, DHCP, DNS, Logs, Pulpcore, Additional proxy services
* **Purpose:** Provides provisioning and content management services for Rocky Linux deployments.

---

## Subnet Configuration

Navigate to: `Infrastructure → Subnets`

### vgs-subnet-centos

| Tab | Parameter | Value |
|:---|:---|:---|
| **Subnet** | Name | vgs-subnet-centos |
| | Network Address | 192.168.253.0 |
| | Network Prefix | 24 |
| | Netmask | 255.255.255.0 |
| | Gateway Address | 192.168.253.2 |
| | Primary DNS Server | 192.168.253.151 |
| | IPAM | DHCP |
| | Start of IP Range | 192.168.253.10 |
| | End of IP Range | 192.168.253.240 |
| | Boot Mode | DHCP |
| **Domains**| Selected Domains | vgs.com |
| **Proxies**| DHCP Proxy | rocky-08-01.vgs.com |
| | TFTP Proxy | rocky-08-01.vgs.com |
| | Reverse DNS Proxy | *None (Empty)* |
| | Template Proxy | rocky-08-01.vgs.com |

### vgs-subnet-rocky

| Tab | Parameter | Value |
|:---|:---|:---|
| **Subnet** | Name | vgs-subnet-rocky |
| | Network Address | 192.168.253.0 |
| | Network Prefix | 24 |
| | Netmask | 255.255.255.0 |
| | Gateway Address | 192.168.253.2 |
| | Primary DNS Server | 192.168.253.151 |
| | IPAM | DHCP |
| | Start of IP Range | 192.168.253.10 |
| | End of IP Range | 192.168.253.240 |
| | Boot Mode | DHCP |
| **Domains**| Selected Domains | vgs.com |
| **Proxies**| DHCP Proxy | rocky-08-02.vgs.com |
| | TFTP Proxy | rocky-08-02.vgs.com |
| | Reverse DNS Proxy | *None (Empty)* |
| | Template Proxy | rocky-08-02.vgs.com |

---

## Host Groups Configuration

Navigate to: `Configure → Host Groups`

### VGS HOSTS CENTOS 7

| Tab | Parameter | Value |
|:---|:---|:---|
| **Host Group** | Name | VGS HOSTS CENTOS 7 |
| | Content Source | rocky-08-01.vgs.com |
| **Network** | Domain | vgs.com |
| | IPv4 Subnet | vgs-subnet-centos |
| **Operating System**| Architecture | x86_64 |
| | Operating System | CentOSLinux 7 |
| | Root Password | \*\*\*\*\*\*\*\* |

### VGS HOSTS ROCKY 8

| Tab | Parameter | Value |
|:---|:---|:---|
| **Host Group** | Name | VGS HOSTS ROCKY 8 |
| | Content Source | rocky-08-01.vgs.com |
| **Network** | Domain | vgs.com |
| | IPv4 Subnet | vgs-subnet-rocky |
| **Operating System**| Architecture | x86_64 |
| | Operating System | RockyLinux 8.10 |
| | Root Password | \*\*\*\*\*\*\*\* |

---

## Provisioning Workflow

The system provisioning process follows the sequential operations sequence below:

```
Host Boot
    ↓
DHCP Assignment (Allocated from Pool range .10 - .240)
    ↓
Smart Proxy Selection (rocky-08-01 vs rocky-08-02)
    ↓
TFTP/PXE Boot
    ↓
PXEGrub2 UEFI Template Execution
    ↓
Kickstart Configuration Processing
    ↓
Installation Media Repository Call
    ↓
Automated Operating System Deployment
```

---

## Validation Checklist

- [x] Subnets (`vgs-subnet-centos`, `vgs-subnet-rocky`) defined with matching IPAM ranges.
- [x] DHCP, TFTP, and Template proxies correctly mapped per subnet sub-tab.
- [x] Host Groups (`VGS HOSTS CENTOS 7` and `VGS HOSTS ROCKY 8`) configured for automated deployment.
- [x] Installation media configured and reachable for CentOS and Rocky Linux.
- [x] Operating systems configured in Foreman.
- [x] UEFI PXE templates verified and ready.
- [x] Smart Proxies registered and running healthy status flags.

---

## Conclusion

The Foreman environment is fully configured to provision CentOS 7 and Rocky Linux 8.10 systems using UEFI PXE boot, Kickstart automation, installation media repositories, Smart Proxies, and subnet-specific DHCP services. This setup enables centralized, controlled, and repeatable operating system deployments across the enterprise network.
