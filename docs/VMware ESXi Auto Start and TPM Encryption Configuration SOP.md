# VMware ESXi Auto Start and TPM Encryption Configuration SOP

![VMware](https://img.shields.io/badge/VMware-ESXi-blue)
![Security](https://img.shields.io/badge/Security-TPM-green)
![Automation](https://img.shields.io/badge/VM_Auto_Start-orange)

---

# Overview

This SOP covers:

* Configuring ESXi VM Auto Start
* Defining VM Startup Order
* Enabling TPM-Based Encryption
* Enforcing Secure Boot
* Backing Up ESXi Configuration
* Retrieving Recovery Keys

---

# Prerequisites

| Requirement | Description                      |
| ----------- | -------------------------------- |
| ESXi Host   | ESXi 7.x / 8.x                   |
| TPM Module  | Installed and recognized by ESXi |
| Secure Boot | Supported by hardware            |
| SSH Access  | Enabled on ESXi Host             |
| Root Access | Required                         |

---

# Section 1 – Configure Virtual Machine Auto Start

---

## Step 1 – View Current Auto Start Configuration

### Purpose

Displays the current ESXi auto-start configuration.

### Command

```bash
vim-cmd hostsvc/autostartmanager/get_defaults
```

### Expected Result

Displays current startup and shutdown policies.

Example:

```text
Enabled: false
Start Delay: 120
Stop Delay: 120
```

---

## Step 2 – Enable Auto Start

### Purpose

Enables automatic startup of VMs when the ESXi host boots.

### Command

```bash
vim-cmd hostsvc/autostartmanager/enable_autostart 1
```

### Verification

```bash
vim-cmd hostsvc/autostartmanager/get_defaults
```

Expected:

```text
Enabled: true
```

---

## Step 3 – List All Virtual Machines

### Purpose

Retrieve VM IDs required for startup ordering.

### Command

```bash
vim-cmd vmsvc/getallvms
```

### Example Output

```text
Vmid   Name
----   ----------------
3      vCenter
5      AWX
7      NetBox
```

> [!NOTE]
> Record the VM IDs because they are required for startup order configuration.

---

## Step 4 – Configure Startup Order

### Purpose

Configure VM startup and shutdown sequence.

### Configuration

| VM ID | Startup Order |
| ----- | ------------- |
| 3     | 1             |
| 5     | 2             |

### Commands

#### Configure VM ID 3

```bash
vim-cmd hostsvc/autostartmanager/update_autostartentry \
3 \
PowerOn \
120 \
1 \
GuestShutdown \
120 \
systemDefault
```

#### Configure VM ID 5

```bash
vim-cmd hostsvc/autostartmanager/update_autostartentry \
5 \
PowerOn \
120 \
2 \
GuestShutdown \
120 \
systemDefault
```

### Parameter Explanation

| Parameter     | Description                  |
| ------------- | ---------------------------- |
| PowerOn       | Power on VM during host boot |
| 120           | Startup delay in seconds     |
| 1 / 2         | Startup order                |
| GuestShutdown | Graceful guest OS shutdown   |
| 120           | Shutdown delay               |
| systemDefault | Use ESXi defaults            |

---

## Validation

After configuration:

```bash
vim-cmd hostsvc/autostartmanager/get_defaults
```

Confirm Auto Start remains enabled.

---

# Section 2 – Enable TPM Encryption and Secure Boot

---

## Overview

This section configures:

* TPM Mode Encryption
* Secure Boot Enforcement
* Recovery Key Generation

---

## Step 1 – Enable TPM Encryption Mode

### Purpose

Configure ESXi to protect configuration data using TPM.

### Command

```bash
esxcli system settings encryption set --mode=TPM
```

### Verification

```bash
esxcli system settings encryption get
```

Expected:

```text
Mode: TPM
```

---

## Step 2 – Require Secure Boot

### Purpose

Ensure ESXi boots only trusted and signed components.

### Command

```bash
esxcli system settings encryption set --require-secure-boot=T
```

### Verification

```bash
esxcli system settings encryption get
```

Expected:

```text
Require Secure Boot: true
```

---

## Step 3 – Save ESXi Configuration

### Purpose

Commit encryption configuration changes.

### Command

```bash
/bin/backup.sh 0
```

### Example Output

```text
Saving current state in /bootbank
Creating ConfigStore Backup
Locking esx.conf
Creating archive
Unlocked esx.conf
Using key ID
xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
to encrypt
Clock updated.
```

### Expected Result

Configuration successfully written to bootbank.

---

## Step 4 – Verify Encryption Settings

### Command

```bash
esxcli system settings encryption get
```

### Expected Output

```text
Mode: TPM
Require Executables Only From Installed VIBs: false
Require Secure Boot: true
```

---

## Step 5 – Retrieve Recovery Key

### Purpose

Generate and store recovery information required for disaster recovery.

### Command

```bash
esxcli system settings encryption recovery list
```

### Example Output

```text
Recovery ID                             Key
--------------------------------------  ---
{A9A16DEF-4E63-4AD5-AF39-3D14B391A939}  XXXXX-XXXXX-XXXXX-XXXXX
```

> [!WARNING]
> Store the Recovery ID and Recovery Key in a secure password vault. Loss of the recovery key may prevent recovery of encrypted ESXi configuration data.

---

# Security Recommendations

## Store Recovery Keys Securely

Recommended locations:

* Enterprise Password Vault
* CyberArk
* HashiCorp Vault
* Bitwarden Enterprise
* Secure Offline Documentation

---

## Verify TPM Status

Run:

```bash
esxcli hardware trustedboot get
```

Expected:

```text
Drtm Enabled: true
Tpm Present: true
```

---

## Verify Secure Boot Status

Run:

```bash
esxcli system settings encryption get
```

Confirm:

```text
Require Secure Boot: true
```

---

# Validation Checklist

## VM Auto Start

* [ ] Auto Start Enabled
* [ ] Startup Order Configured
* [ ] VM IDs Verified
* [ ] Startup Delays Configured

## TPM Encryption

* [ ] TPM Detected
* [ ] TPM Mode Enabled
* [ ] Secure Boot Enabled
* [ ] Configuration Saved

## Recovery

* [ ] Recovery ID Recorded
* [ ] Recovery Key Stored Securely
* [ ] Backup Completed Successfully

---

# Completion Criteria

The implementation is complete when:

* ESXi Auto Start is enabled.
* VM startup order is configured.
* TPM encryption is enabled.
* Secure Boot enforcement is enabled.
* ESXi configuration is saved successfully.
* Recovery key is securely stored.
* Host successfully reboots with TPM and Secure Boot enabled.
