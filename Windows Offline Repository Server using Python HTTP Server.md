# Windows Offline Repository Server using Python HTTP Server

## Overview

This guide configures a Windows laptop to act as an offline HTTP repository server while continuing to run Technitium DNS Server on the same machine.

### Final Architecture

| Service                    | IP Address      | Port |
| -------------------------- | --------------- | ---- |
| Technitium DNS Web Console | 192.168.253.1   | 80   |
| Python HTTP Repository     | 192.168.253.136 | 80   |

Repository Root:

```text
E:\
```

Repository URL:

```text
http://192.168.253.136/repo/
```

Example:

```text
http://192.168.253.136/repo/rocky8/
```

---

# Step 1 - Configure Secondary IP Address

Open:

```text
Win + R
```

Run:

```text
ncpa.cpl
```

Navigate to:

```text
VMware Network Adapter VMnet0
→ Properties
→ Internet Protocol Version 4 (TCP/IPv4)
→ Properties
→ Advanced
```

Add a secondary IP:

```text
IP Address : 192.168.253.136
Subnet Mask: 255.255.255.0
```

The adapter should now contain:

```text
192.168.253.1
192.168.253.136
```

---

# Step 2 - Configure Technitium DNS

Open:

```text
http://192.168.253.1
```

Navigate to:

```text
Settings
→ Web Service
```

Change:

```text
Web Service Local Addresses

[::]
```

to:

```text
192.168.253.1
```

Click:

```text
Save Settings
```

Restart the DNS Server.

Verify:

```cmd
netstat -ano | findstr :80
```

Expected:

```text
TCP    192.168.253.1:80    LISTENING
```

Technitium now listens only on:

```text
192.168.253.1:80
```

---

# Step 3 - Start Python HTTP Server

Open Git Bash.

Change directory:

```bash
cd /e
```

Start the repository server:

```bash
py -m http.server 80 --bind 192.168.253.136
```

Expected:

```text
Serving HTTP on 192.168.253.136 port 80
```

---

# Step 4 - Verify Repository

Open browser:

```text
http://192.168.253.136/repo/
```

Example repository:

```text
http://192.168.253.136/repo/rocky8/
```

Verify from Linux:

```bash
curl http://192.168.253.136/repo/rocky8/
```

---

# Step 5 - Configure DNS

Create an A Record:

| Record       | Value           |
| ------------ | --------------- |
| repo.vgs.com | 192.168.253.136 |

Repository becomes:

```text
http://repo.vgs.com/repo/rocky8/
```

---

# Step 6 - Make Repository Start Automatically

Open:

```text
taskschd.msc
```

Create Task:

## General

Name:

```text
RepoHTTP
```

Enable:

```text
Run whether user is logged on or not

Run with highest privileges
```

---

## Trigger

Create trigger:

```text
At Startup
```

(Optional)

```text
At Log On
```

---

## Action

Program:

```text
C:\Users\vigne\AppData\Local\Programs\Python\Launcher\py.exe
```

Arguments:

```text
-m http.server 80 --bind 192.168.253.136
```

Start In:

```text
E:\
```

---

## Conditions

Disable:

```text
Start the task only if the computer is on AC power
```

---

## Settings

Enable:

```text
Allow task to be run on demand

Run task as soon as possible after a scheduled start is missed

Restart task if it fails
```

Save the task.

---

# Verify After Reboot

Repository:

```text
http://192.168.253.136/repo/
```

Technitium:

```text
http://192.168.253.1
```

Both services should start automatically after Windows boots.

---

# Final Lab Architecture

```text
                   Windows Laptop
             ┌───────────────────────────┐
             │                           │
             │ 192.168.253.1             │
             │ Technitium DNS            │
             │ HTTP Port 80              │
             │                           │
             ├───────────────────────────┤
             │                           │
             │ 192.168.253.136           │
             │ Python HTTP Repository    │
             │ E:\repo                   │
             │ HTTP Port 80              │
             │                           │
             └───────────────────────────┘

                 Linux / AWX / Foreman
                          │
                          ▼

      http://repo.vgs.com/repo/rocky8/
```

---

# Repository Structure

```text
E:\
└── repo
    ├── rocky8
    ├── centos
    ├── installed_rhel7
    ├── installed_rhel8
    ├── elevate
    └── ansible
```

---

# Useful Commands

Start Repository:

```bash
cd /e
py -m http.server 80 --bind 192.168.253.136
```

Verify Listening Port:

```cmd
netstat -ano | findstr :80
```

Verify Repository:

```bash
curl http://192.168.253.136/repo/rocky8/
```

Verify DNS:

```cmd
nslookup repo.vgs.com 192.168.253.1
```
