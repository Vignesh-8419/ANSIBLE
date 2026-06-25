# Windows Repository Server using Nginx (Technitium DNS + Offline Repository)

## Overview

This guide explains how to configure a Windows laptop to host:

* **Technitium DNS Server**
* **Offline Repository Server using Nginx**
* **Separate IP addresses on the same machine**
* **Permanent HTTP repository for AWX, Foreman, Katello and PXE**

---

# Lab Architecture

```
                   Windows Laptop
        ┌─────────────────────────────────────┐
        │                                     │
        │ 192.168.253.1                       │
        │ Technitium DNS                      │
        │ HTTP Port 80                        │
        │                                     │
        ├─────────────────────────────────────┤
        │                                     │
        │ 192.168.253.136                     │
        │ Nginx Repository Server             │
        │ HTTP Port 80                        │
        │ Repository Root                     │
        │ E:\repo                             │
        │                                     │
        └─────────────────────────────────────┘

                 Linux / AWX / Foreman
                         │
                         ▼

          http://repo.vgs.com/
```

---

# Step 1 - Add Secondary IP Address

Open

```
ncpa.cpl
```

Right-click

```
VMware Network Adapter VMnet0
```

Select

```
Properties
```

Choose

```
Internet Protocol Version 4 (TCP/IPv4)
```

Click

```
Properties
```

Click

```
Advanced
```

Under **IP Addresses**

Click

```
Add
```

Add

```
IP Address : 192.168.253.136
Subnet Mask: 255.255.255.0
```

Click OK.

Verify

```
ipconfig
```

Expected

```
192.168.253.1
192.168.253.136
```

---

# Step 2 - Verify Connectivity

```
ping 192.168.253.136
```

Expected

```
Reply from 192.168.253.136
```

---

# Step 3 - Repository Structure

```
E:\
└── repo
    ├── rocky8
    ├── centos
    ├── installed_rhel7
    ├── installed_rhel8
    ├── elevate
    ├── ansible
    └── netbox_offline_repo
```

---

# Step 4 - Download Nginx

Download the Windows ZIP package from:

https://nginx.org/en/download.html

Download

```
nginx-x.x.x.zip
```

**Do NOT download**

* Source Code
* tar.gz
* tar.xz

---

# Step 5 - Extract Nginx

Extract to

```
C:\nginx
```

Verify

```
C:\nginx
├── conf
├── html
├── logs
├── nginx.exe
```

---

# Step 6 - Configure Nginx

Edit

```
C:\nginx\conf\nginx.conf
```

Replace the entire file with:

```nginx
worker_processes 1;

events {
    worker_connections 1024;
}

http {

    include       mime.types;
    default_type  application/octet-stream;

    sendfile on;
    keepalive_timeout 65;

    access_log logs/access.log;
    error_log logs/error.log;

    server {

        listen 192.168.253.136:80;

        server_name _;

        root E:/repo;

        index index.html;

        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;

        client_max_body_size 20G;

        location / {
            autoindex on;
            try_files $uri $uri/ =404;
        }

        error_page 500 502 503 504 /50x.html;

        location = /50x.html {
            root html;
        }
    }
}
```

---

# Step 7 - Test Configuration

```
cd C:\nginx

.\nginx.exe -t
```

Expected

```
syntax is ok

test is successful
```

---

# Step 8 - Start Nginx

```
cd C:\nginx

.\nginx.exe
```

---

# Step 9 - Verify Listening Port

```
netstat -ano | findstr :80
```

Expected

```
192.168.253.136:80 LISTENING
```

---

# Step 10 - Test Repository

Open

```
http://192.168.253.136/
```

Expected

```
ansible/
centos/
rocky8/
installed_rhel7/
installed_rhel8/
elevate/
```

---

# Step 11 - Configure Technitium DNS

Create an **A Record**

```
repo.vgs.com
```

↓

```
192.168.253.136
```

Verify

```
nslookup repo.vgs.com 192.168.253.1
```

Expected

```
repo.vgs.com
192.168.253.136
```

---

# Step 12 - Verify Repository

```
curl http://repo.vgs.com/
```

or

```
curl http://192.168.253.136/
```

---

# Step 13 - Stop Nginx

```
taskkill /IM nginx.exe /F
```

or

```
cd C:\nginx

.\nginx.exe -s stop
```

---

# Step 14 - Reload Configuration

```
cd C:\nginx

.\nginx.exe -s reload
```

---

# Step 15 - Restart Nginx

```
cd C:\nginx

.\nginx.exe -s stop

.\nginx.exe
```

---

# Step 16 - Install Nginx as Windows Service

Download NSSM

https://nssm.cc/download

Extract

```
C:\Tools\nssm
```

Run

```
C:\Tools\nssm\win64\nssm.exe install Nginx
```

Application

```
Path

C:\nginx\nginx.exe
```

Startup Directory

```
C:\nginx
```

Arguments

```
Leave Blank
```

Click

```
Install Service
```

---

# Step 17 - Start Service

```
net start Nginx
```

Configure automatic startup

```
sc config Nginx start= auto
```

Verify

```
sc query Nginx
```

---

# Step 18 - Verify After Reboot

Open

```
http://192.168.253.136/
```

Verify

```
http://repo.vgs.com/
```

Both should work automatically.

---

# Useful Commands

### Test Configuration

```
cd C:\nginx

.\nginx.exe -t
```

### Start

```
.\nginx.exe
```

### Stop

```
.\nginx.exe -s stop
```

### Reload

```
.\nginx.exe -s reload
```

### Verify Port

```
netstat -ano | findstr :80
```

### Verify Repository

```
curl http://192.168.253.136/
```

### Verify DNS

```
nslookup repo.vgs.com
```

# Step 17 - Install Nginx as a Windows Service (NSSM)

NSSM (Non-Sucking Service Manager) allows Nginx to run as a native Windows service so that it starts automatically after every system reboot without requiring a user to log in.

---

## Verify NSSM

Extract NSSM to:

```text
C:\nssm
```

Verify the executable exists:

```powershell
Get-ChildItem C:\nssm\win32
```

Expected:

```text
nssm.exe
```

> **Note:** The downloaded `win64\nssm.exe` was corrupted (0 bytes), so the working `win32\nssm.exe` was used. The 32-bit version of NSSM works correctly on 64-bit Windows.

---

## Install Nginx Service

Run Command Prompt or PowerShell as **Administrator**.

Execute:

```cmd
C:\nssm\win32\nssm.exe install Nginx
```

Configure the following values:

| Field                 | Value                |
| --------------------- | -------------------- |
| **Application Path**  | `C:\nginx\nginx.exe` |
| **Startup Directory** | `C:\nginx`           |
| **Arguments**         | *(Leave Blank)*      |

Click **Install Service**.

Expected:

```text
Service "Nginx" installed successfully!
```

---

# Step 18 - Start the Service

Start the Nginx service:

```cmd
net start Nginx
```

Expected:

```text
The Nginx service was started successfully.
```

---

# Step 19 - Configure Automatic Startup

Configure the service to start automatically whenever Windows boots.

```cmd
sc config Nginx start= auto
```

Expected:

```text
[SC] ChangeServiceConfig SUCCESS
```

---

# Step 20 - Verify Service Status

Check the status of the Nginx service:

```cmd
sc query Nginx
```

Expected:

```text
SERVICE_NAME: Nginx
STATE              : 4  RUNNING
```

---

# Step 21 - Verify Listening Port

Confirm that Nginx is listening on the repository IP address.

```cmd
netstat -ano | findstr 192.168.253.136:80
```

Expected:

```text
TCP    192.168.253.136:80    LISTENING
```

---

# Step 22 - Verify Repository Access

Open the repository in a web browser:

```text
http://192.168.253.136/
```

or

```text
http://repo.vgs.com/
```

The repository should display the contents of the `E:\repo` directory.

---

# Step 23 - Verify After Reboot

Restart the Windows machine.

After the system boots, verify that the Nginx service is running automatically:

```cmd
sc query Nginx
```

Expected:

```text
STATE : 4 RUNNING
```

Verify the listening port:

```cmd
netstat -ano | findstr 192.168.253.136:80
```

Open the repository:

```text
http://repo.vgs.com/
```

No manual intervention should be required after a reboot.

---

# Useful Service Commands

### Start Nginx

```cmd
net start Nginx
```

### Stop Nginx

```cmd
net stop Nginx
```

### Restart Nginx

```cmd
net stop Nginx
net start Nginx
```

### Check Service Status

```cmd
sc query Nginx
```

### Configure Automatic Startup

```cmd
sc config Nginx start= auto
```

### Verify Listening Port

```cmd
netstat -ano | findstr 192.168.253.136:80
```

### Verify Repository

```cmd
curl http://192.168.253.136/
```

or

```cmd
curl http://repo.vgs.com/
```

---

# Final Result

* **Technitium DNS Server:** `192.168.253.1`
* **Nginx Repository Server:** `192.168.253.136`
* **Repository Root:** `E:\repo`
* **Service Name:** `Nginx`
* **Startup Type:** Automatic
* **Repository URL:** `http://repo.vgs.com/`

The Nginx repository server now runs as a native Windows service and starts automatically after every Windows boot without requiring a user to log in or manually launch Nginx.


---

# Final Architecture

```
                    Windows Laptop
         ┌──────────────────────────────────┐
         │                                  │
         │ 192.168.253.1                    │
         │ Technitium DNS                   │
         │ Port 80                          │
         │                                  │
         ├──────────────────────────────────┤
         │                                  │
         │ 192.168.253.136                  │
         │ Nginx Repository                 │
         │ E:\repo                          │
         │ Port 80                          │
         │                                  │
         └──────────────────────────────────┘

                AWX / Foreman / PXE
                        │
                        ▼

              http://repo.vgs.com/
```

## Notes

* Technitium DNS remains bound to **192.168.253.1:80**.
* Nginx serves the repository from **192.168.253.136:80**.
* The repository root is **E:\repo**, so the repository is accessed as:

```
http://192.168.253.136/
```

or

```
http://repo.vgs.com/
```

without needing `/repo` in the URL.

# Post-Reboot Fix Steps

## Step 1 - Identify Port 80 Owner

Checked which process was listening on port 80.

```cmd
netstat -ano | findstr :80
```

Found:

```text
0.0.0.0:80 LISTENING PID 4
```

---

## Step 2 - Verify HTTP.sys Registration

Checked the HTTP service state.

```powershell
netsh http show servicestate
```

Found that IIS had registered:

```text
DefaultAppPool
HTTP://192.168.253.136:80/
```

---

## Step 3 - Stop IIS

Stopped IIS services.

```powershell
Stop-Service W3SVC -Force
Stop-Service WAS -Force
```

---

## Step 4 - Disable IIS

Prevented IIS from starting after reboot.

```powershell
Set-Service W3SVC -StartupType Disabled
Set-Service WAS -StartupType Disabled
```

Verified:

```powershell
Get-Service W3SVC,WAS
```

---

## Step 5 - Verify HTTP.sys Released Port 80

```powershell
netsh http show servicestate
```

Confirmed that no HTTP URLs were registered.

---

## Step 6 - Verify Nginx Service Configuration

Checked the service configuration.

```cmd
sc.exe qc Nginx
```

Found:

```text
BINARY_PATH_NAME : C:\nssm\win64\nssm.exe
```

The `win64\nssm.exe` executable was corrupted (0 bytes).

---

## Step 7 - Remove Existing Nginx Service

```cmd
C:\nssm\win32\nssm.exe remove Nginx confirm
```

---

## Step 8 - Reinstall Nginx Service

```cmd
C:\nssm\win32\nssm.exe install Nginx
```

Configured:

| Field             | Value                |
| ----------------- | -------------------- |
| Application       | `C:\nginx\nginx.exe` |
| Startup Directory | `C:\nginx`           |
| Arguments         | *(Blank)*            |

---

## Step 9 - Start Nginx Service

```cmd
net start Nginx
```

---

## Step 10 - Verify Service Configuration

```cmd
sc.exe qc Nginx
```

Confirmed:

```text
BINARY_PATH_NAME : C:\nssm\win32\nssm.exe
```

---

## Step 11 - Verify Nginx Process

```cmd
tasklist | findstr nginx
```

Expected:

```text
nginx.exe
nginx.exe
```

---

## Step 12 - Verify Listening Port

```cmd
netstat -ano | findstr :80
```

Confirmed:

```text
TCP 192.168.253.136:80 LISTENING
```

---

## Result

* IIS no longer reserves port 80.
* HTTP.sys no longer blocks Nginx.
* Nginx runs as a Windows service.
* Repository is available after every reboot.
* No manual startup is required.

