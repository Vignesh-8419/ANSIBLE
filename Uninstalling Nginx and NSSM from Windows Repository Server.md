# Uninstalling Nginx and NSSM from Windows Repository Server

## Overview

This document describes the steps performed to completely remove the existing Nginx and NSSM installation from the Windows Repository Server before performing a fresh installation.

The objective was to remove:

* Nginx Windows Service
* NSSM (Non-Sucking Service Manager)
* Running Nginx processes
* Installation directories
* Existing Windows Service registration
* Verify that port 80 is available for the new installation

---

# Step 1 - Stop the Nginx Service

Open **Command Prompt as Administrator**.

Stop the service:

```cmd
net stop Nginx
```

If the above command fails, use:

```cmd
sc stop Nginx
```

Verify the service status:

```cmd
sc query Nginx
```

Expected output:

```
STATE : STOPPED
```

---

# Step 2 - Remove the Windows Service

Since Nginx was installed using NSSM, remove the service registration.

Using NSSM:

```cmd
C:\nssm\win32\nssm.exe remove Nginx confirm
```

Alternatively:

```cmd
sc delete Nginx
```

Verify removal:

```cmd
sc query Nginx
```

Expected output:

```
[SC] OpenService FAILED 1060:

The specified service does not exist as an installed service.
```

---

# Step 3 - Stop Remaining Nginx Processes

Terminate any running Nginx processes.

```cmd
taskkill /F /IM nginx.exe
```

Verify:

```cmd
tasklist | findstr nginx
```

No output should be returned.

---

# Step 4 - Remove the Nginx Installation

Delete the Nginx installation directory.

```cmd
rmdir /S /Q C:\nginx
```

Alternatively, delete the folder manually using File Explorer.

Expected folder removed:

```
C:\nginx
```

---

# Step 5 - Remove NSSM

Delete the NSSM installation directory.

```cmd
rmdir /S /Q C:\nssm
```

Alternatively, remove it manually.

Expected folder removed:

```
C:\nssm
```

---

# Step 6 - Verify Port 80

Check whether any application is still listening on TCP port 80.

```cmd
netstat -ano | findstr :80
```

If no output is returned, the port is free.

If a process is still listening, identify it.

Example:

```
TCP    192.168.253.136:80    0.0.0.0:0    LISTENING    1234
```

Determine the owning process:

```cmd
tasklist /FI "PID eq 1234"
```

---

# Step 7 - Stop IIS (If Required)

If IIS or HTTP.sys is using port 80, stop the IIS services.

Open PowerShell as Administrator.

Stop IIS services:

```powershell
Stop-Service W3SVC -Force
Stop-Service WAS -Force
```

Disable automatic startup:

```powershell
Set-Service W3SVC -StartupType Disabled
Set-Service WAS -StartupType Disabled
```

Verify:

```powershell
Get-Service W3SVC,WAS
```

Expected output:

```
Status   Name
------   ----
Stopped  W3SVC
Stopped  WAS
```

Startup type should be **Disabled**.

---

# Step 8 - Verify HTTP.sys

Check whether HTTP.sys still owns port 80.

```cmd
netsh http show servicestate
```

Review the output for any URL reservations bound to port 80.

If URL registrations still exist, ensure IIS has been completely stopped or restart the server before reinstalling Nginx.

---

# Step 9 - Final Verification

Verify that the Nginx service has been removed.

```cmd
sc query Nginx
```

Expected:

```
The specified service does not exist.
```

Verify that no Nginx processes remain.

```cmd
tasklist | findstr nginx
```

No output should be returned.

Verify that port 80 is available.

```cmd
netstat -ano | findstr :80
```

Port 80 should not be owned by Nginx.

---

# Uninstallation Summary

The following components were successfully removed:

* Nginx Windows Service
* NSSM Service Registration
* Running Nginx Processes
* `C:\nginx` Installation Directory
* `C:\nssm` Installation Directory

Additionally:

* Verified that the Nginx service no longer exists.
* Confirmed that no `nginx.exe` processes were running.
* Checked that TCP port 80 was available for a fresh installation.
* Ensured IIS services were stopped and disabled if they were occupying port 80.

The system is now ready for a clean installation of Nginx and NSSM.
