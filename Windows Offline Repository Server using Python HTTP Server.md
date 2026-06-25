# Windows Repository Server using Nginx (Persistent After Reboot)

## Overview

This document describes how to configure a Windows machine as a persistent HTTP Repository Server using **Nginx** instead of Python's built-in HTTP server.

### Repository Server

| Item            | Value                     |
| --------------- | ------------------------- |
| Repository Root | `E:\repo`                 |
| Repository URL  | `http://192.168.253.136/` |
| HTTP Server     | Nginx                     |
| Service Manager | NSSM                      |
| Startup         | Automatic                 |

---

# Why Nginx?

Initially the repository was served using Python:

```cmd
python -m http.server 80 --bind 192.168.253.136
```

Problems:

* Stops when CMD window closes
* Stops after reboot
* Task Scheduler was unreliable
* Not suitable for production

Therefore Nginx was selected.

---

# Step 1 - Download Nginx

Download the Windows version of Nginx.

Extract to:

```
C:\nginx
```

Expected structure:

```
C:\nginx
 ├── conf
 ├── html
 ├── logs
 ├── nginx.exe
```

---

# Step 2 - Configure nginx.conf

Edit:

```
C:\nginx\conf\nginx.conf
```

Replace the default configuration with:

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

    server {

        listen 192.168.253.136:80;

        server_name _;

        root E:/repo;

        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;

        location / {
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

# Step 3 - Validate Configuration

```powershell
cd C:\nginx

.\nginx.exe -t
```

Expected:

```
syntax is ok

test is successful
```

---

# Step 4 - Start Nginx

```powershell
.\nginx.exe
```

Verify:

```powershell
netstat -ano | findstr :80
```

Expected:

```
192.168.253.136:80 LISTENING
```

Repository URL:

```
http://192.168.253.136/
```

---

# Step 5 - Install NSSM

Download NSSM.

Extract to:

```
C:\nssm
```

Use the **32-bit** executable.

---

# Step 6 - Install Nginx as Windows Service

Open Command Prompt as Administrator.

Install:

```cmd
C:\nssm\win32\nssm.exe install Nginx
```

Configure:

Application

```
Application:
C:\nginx\nginx.exe
```

Startup directory

```
C:\nginx
```

Arguments

```
(blank)
```

Click

```
Install Service
```

---

# Step 7 - Start Service

```cmd
net start Nginx
```

Configure automatic startup:

```cmd
sc config Nginx start= auto
```

Verify:

```cmd
sc query Nginx
```

Expected:

```
STATE : RUNNING
```

---

# Step 8 - Verify

Check service:

```cmd
tasklist | findstr nginx
```

Expected:

```
nginx.exe
nginx.exe
```

Check listening port:

```cmd
netstat -ano | findstr 192.168.253.136:80
```

Expected:

```
LISTENING
```

---

# Troubleshooting After Reboot

## Problem

After reboot:

* Repository inaccessible
* IIS occupied port 80
* Nginx service appeared running but could not bind

---

## Investigation

Check port 80:

```powershell
netstat -ano | findstr :80
```

Found:

```
PID 4
```

Meaning HTTP.sys was owning port 80.

---

Check HTTP Service State:

```powershell
netsh http show servicestate
```

Result:

```
Default Web Site
192.168.253.136:80
```

IIS had registered the URL reservation.

---

# Resolution

Stop IIS

```powershell
Stop-Service W3SVC -Force
```

Stop WAS

```powershell
Stop-Service WAS -Force
```

Disable IIS

```powershell
Set-Service W3SVC -StartupType Disabled
Set-Service WAS -StartupType Disabled
```

Verify:

```powershell
Get-Service W3SVC,WAS
```

Both should be:

```
Stopped
Disabled
```

---

Verify HTTP Reservations

```powershell
netsh http show servicestate
```

Expected:

```
No registered URLs
```

---

Restart Nginx

```cmd
net start Nginx
```

Verify:

```cmd
tasklist | findstr nginx
```

Verify:

```cmd
netstat -ano | findstr :80
```

Expected:

```
192.168.253.136:80 LISTENING
```

---

# NSSM Configuration

Verify application:

```cmd
C:\nssm\win32\nssm.exe get Nginx Application
```

Expected:

```
C:\nginx\nginx.exe
```

Verify working directory:

```cmd
C:\nssm\win32\nssm.exe get Nginx AppDirectory
```

Expected:

```
C:\nginx
```

---

# Final Verification

Repository:

```
http://192.168.253.136/
```

Should display:

```
ansible/
centos/
rocky8/
installed_rhel7/
installed_rhel8/
...
```

---

# Technitium DNS Server Findings

The DNS service is running correctly.

Verify:

```powershell
Get-Service DnsService
```

Result:

```
Running
```

The DNS Web Console is **not** using port 80.

Listening ports:

```powershell
Get-NetTCPConnection | Where-Object {$_.OwningProcess -eq 5496}
```

Result:

```
53
5380
```

Therefore:

DNS Service

```
53
```

DNS Web Console

```
5380
```

Open using:

```
http://192.168.253.1:5380
```

instead of:

```
http://192.168.253.1
```

---

# Final Architecture

```
                    Windows Repository Server

                 +----------------------------+
                 |          Nginx             |
                 |      Windows Service       |
                 +-------------+--------------+
                               |
                               |
                192.168.253.136:80
                               |
                               |
                         E:\repo
        -----------------------------------------
        ansible/
        centos/
        rocky8/
        installed_rhel7/
        installed_rhel8/
        GOLDENTEMPLATE_*/
        ISO Images
        -----------------------------------------

                Technitium DNS Server

                DNS Service : Port 53
                Web Console : Port 5380

                URL:
                http://192.168.253.1:5380
```

---

# No Manual Steps Required After Reboot

Because:

* Nginx is installed as a Windows Service
* Startup type is Automatic
* NSSM launches Nginx automatically

No manual commands are required after a system reboot.

Only verify if necessary:

```cmd
sc query Nginx

tasklist | findstr nginx

netstat -ano | findstr :80
```
