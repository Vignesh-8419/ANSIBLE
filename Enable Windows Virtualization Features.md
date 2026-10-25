# Enable Windows Virtualization Features

Enable the following Windows Features:

- Hyper-V
- Virtual Machine Platform
- Windows Hypervisor Platform

## Disable Hypervisor Launch

Open PowerShell as Administrator and run:

```powershell
bcdedit /set hypervisorlaunchtype off
