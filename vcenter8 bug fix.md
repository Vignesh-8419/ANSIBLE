# VMware vCenter Server Appliance (VCSA) 8.0.1 Stage 2 Installation Fix

## Overview

While deploying **VMware vCenter Server Appliance (VCSA) 8.0.1 (Build 21560480)**, the installation failed consistently during **Stage 2** at approximately **69%**.

Although the vCenter UI was partially accessible, the installation was incomplete because the **vLCM (VMware Lifecycle Manager)** service failed to initialize.

The root cause was an OVF property that was not user configurable.

This document explains the complete workaround from extracting the OVA to successfully deploying VCSA.

---

# Environment

| Component | Version |
|-----------|----------|
| ESXi | 7.0 U3 |
| vCenter | 8.0.1 |
| Build | 21560480 |
| Deployment | OVF |
| Host OS | Windows |

---

# Symptoms

During Stage 2 installation:

- Installation stopped around **69%**
- Message displayed:
  - Install Stage 2 Failed
- vCenter UI was accessible
- Lifecycle Manager (vLCM) service failed to start

Checking the logs showed:

```
Install-parameter upgrade.import.directory not set
```

and

```
Failed to initialize Service Config
```

The following file was never created:

```
/etc/vmware-vlcm/vlcm_db/vlcm.properties
```

---

# Root Cause

The OVF contains the following property:

```xml
<Property
    ovf:key="guestinfo.cis.upgrade.import.directory"
    ovf:type="string"
    ovf:userConfigurable="false"
```

Since this property is **not user configurable**, the installer never populates the required value during deployment.

As a result:

- Stage 2 fails
- vLCM initialization fails
- Installation stops around 69%

---

# Solution

Instead of deploying the original OVA, convert it into an OVF, modify one property, and deploy the modified OVF.

---

# Prerequisites

- VMware VCSA 8.0.1 OVA
- OVFTool
- Windows Machine

Example folder structure:

```
E:\
└── vmware
    ├── VMware-VCSA-all-8.0.1-21560480.iso
    └── vcsa
        ├── VMware-vCenter-Server-Appliance-8.0.1.00000-21560480_OVF10.ova
        └── ovftool
            └── win32
                └── ovftool.exe
```

---

# Step 1 - Enable File Extensions in Windows

Before editing the OVF file, make sure Windows displays file extensions.

Open **File Explorer**

Select:

```
View
```

or

```
View → Show
```

Enable:

```
✓ File name extensions
```

On older Windows versions:

```
View → Options

Uncheck

Hide extensions for known file types
```

Click **Apply** and **OK**.

---

# Step 2 - Open Command Prompt

Open **Command Prompt**.

Example:

```
Start
```

Search

```
cmd
```

Open Command Prompt.

---

# Step 3 - Navigate to OVFTool

Example:

```cmd
cd E:\vmware\vcsa\ovftool\win32
```

---

# Step 4 - Convert the OVA to an OVF

Run:

```cmd
ovftool.exe ^
E:\vmware\vcsa\VMware-vCenter-Server-Appliance-8.0.1.00000-21560480_OVF10.ova ^
E:\vmware\VMware-vCenter-Server-Appliance-8.0.1.00000-21560480_OVF10.ovf
```

Expected output:

```
Opening OVA source...
The manifest validates

Transfer Completed

Completed successfully
```

This creates:

```
VMware-vCenter-Server-Appliance-8.0.1.00000-21560480_OVF10.ovf
```

along with

```
.mf
.vmdk
.nvram
```

files.

---

# Step 5 - Delete the Manifest File

Delete the original manifest file.

Example:

```
VMware-vCenter-Server-Appliance-8.0.1.00000-21560480_OVF10.mf
```

This is required because the OVF will be modified and the checksum inside the manifest will no longer match.

---

# Step 6 - Edit the OVF

Open

```
VMware-vCenter-Server-Appliance-8.0.1.00000-21560480_OVF10.ovf
```

using:

- Notepad++
- VS Code
- Notepad

Search for:

```
guestinfo.cis.upgrade.import.directory
```

You will find:

```xml
<Property
    ovf:key="guestinfo.cis.upgrade.import.directory"
    ovf:type="string"
    ovf:userConfigurable="false"
```

Change

```xml
ovf:userConfigurable="false"
```

to

```xml
ovf:userConfigurable="true"
```

Save the file.

---

# Step 7 - Deploy the Modified OVF

Open

```
vSphere Client
```

Select

```
Deploy OVF Template
```

Choose the modified

```
VMware-vCenter-Server-Appliance-8.0.1.00000-21560480_OVF10.ovf
```

Continue the deployment normally.

---

# Step 8 - Complete Stage 2

Open

```
https://<VCSA-IP>:5480
```

Complete Stage 2 installation.

The installation should now proceed beyond the previous failure point.

Expected result:

```
Install - Stage 2 : Complete

You have successfully setup this vCenter Server.
```

---

# Verification

Login to the VCSA shell and verify all services.

```bash
service-control --status --all
```

Verify that:

```
vlcm
vmware-updatemgr
vmware-vpxd
vsphere-ui
```

are running.

Verify the configuration directory:

```bash
ls -l /etc/vmware-vlcm/vlcm_db
```

The following file should exist:

```
vlcm.properties
```

---

# Result

After modifying the OVF and redeploying:

- ✅ Stage 2 completed successfully
- ✅ vCenter installation completed
- ✅ vLCM initialized successfully
- ✅ All services started successfully
- ✅ vCenter UI accessible
- ✅ Lifecycle Manager working

---

# Summary

The issue is caused by the following OVF property being marked as non-user configurable:

```xml
<Property
ovf:key="guestinfo.cis.upgrade.import.directory"
ovf:userConfigurable="false"
```

Changing it to:

```xml
ovf:userConfigurable="true"
```

allows the installer to populate the required installation parameter, enabling the vLCM first boot process to complete successfully.

This workaround resolves the VCSA 8.0.1 Stage 2 installation failure observed at approximately 69%.
