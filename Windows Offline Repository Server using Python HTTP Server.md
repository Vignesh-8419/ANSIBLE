# Windows Offline Repository Server Setup using Python HTTP Server

## Overview

This guide explains how to configure a Windows laptop as an offline HTTP repository server while continuing to run Technitium DNS Server on the same system.

The repository will be accessible using:

```text
http://192.168.253.136/repo/
```

or

```text
http://repo.vgs.com/repo/
```

---

# Lab Architecture

| Service                | IP Address      | Port |
| ---------------------- | --------------- | ---- |
| Technitium DNS Server  | 192.168.253.1   | 80   |
| Python HTTP Repository | 192.168.253.136 | 80   |

Repository Root:

```text
E:\
```

Repository URL:

```text
http://192.168.253.136/repo/
```

---

# Step 1 - Install Python

Download Python from:

```text
https://www.python.org/downloads/windows/
```

During installation enable:

* ✔ Add Python to PATH
* ✔ Install launcher for all users

Verify installation:

```cmd
py --version
```

Expected:

```text
Python 3.13.x
```

---

# Step 2 - Configure VMware VMnet0 Secondary IP Address

Open Run:

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

Click:

```text
Add
```

Primary IP:

```text
192.168.253.1
255.255.255.0
```

Secondary IP:

```text
192.168.253.136
255.255.255.0
```

Click **OK** on every dialog.

Verify:

```cmd
ping 192.168.253.136
```

Expected:

```text
Reply from 192.168.253.136
```

---

# Step 3 - Configure Technitium DNS Web Service

Open:

```text
http://192.168.253.1
```

Navigate to:

```text
Settings
→ Web Service
```

Current:

```text
[::]
```

Replace with:

```text
192.168.253.1
```

Click:

```text
Save Settings
```

Restart Technitium DNS Server.

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

# Step 4 - Repository Directory Structure

Create the repository layout:

```text
E:\
└── repo
    ├── rocky8
    ├── centos
    ├── elevate
    ├── installed_rhel7
    ├── installed_rhel8
    └── ansible
```

---

# Step 5 - Start Python HTTP Repository

Open Git Bash.

Change directory:

```bash
cd /e
```

Start Repository:

```bash
py -m http.server 80 --bind 192.168.253.136
```

Expected:

```text
Serving HTTP on 192.168.253.136 port 80
```

---

# Step 6 - Verify Repository

Open browser:

```text
http://192.168.253.136/repo/
```

Example:

```text
http://192.168.253.136/repo/rocky8/
```

Verify from Linux:

```bash
curl http://192.168.253.136/repo/rocky8/
```

Verify Repository Metadata:

```bash
curl http://192.168.253.136/repo/rocky8/repodata/repomd.xml
```

---

# Step 7 - Configure DNS Record

Create an A Record in Technitium.

| Name         | Type | IP Address      |
| ------------ | ---- | --------------- |
| repo.vgs.com | A    | 192.168.253.136 |

Verify:

```cmd
nslookup repo.vgs.com 192.168.253.1
```

Expected:

```text
Name: repo.vgs.com
Address: 192.168.253.136
```

Repository URL:

```text
http://repo.vgs.com/repo/
```

---

# Step 8 - Make Repository Start Automatically

Open:

```text
Win + R
```

Run:

```text
taskschd.msc
```

Click:

```text
Create Task
```

> Do NOT use **Create Basic Task**.

---

## General Tab

Name:

```text
RepoHTTP
```

Enable:

* ☑ Run whether user is logged on or not
* ☑ Run with highest privileges

Configure for:

```text
Windows 10
```

or

```text
Windows 11
```

---

## Triggers

Click:

```text
New
```

Configure:

```text
Begin the task:
At startup
```

Click **OK**.

(Optional)

Create another trigger:

```text
Begin the task:
At log on
```

---

## Actions

Click:

```text
New
```

Action:

```text
Start a program
```

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

Click **OK**.

---

## Conditions

Disable:

```text
Start the task only if the computer is on AC power
```

---

## Settings

Enable:

* ☑ Allow task to be run on demand
* ☑ Run task as soon as possible after a scheduled start is missed
* ☑ If the task fails, restart every 1 minute
* Restart attempts: 3

Click **OK**.

Windows will prompt for your login password.

---

# Step 9 - Test Scheduled Task

Open:

```text
Task Scheduler
```

Locate:

```text
Task Scheduler Library
└── RepoHTTP
```

Right-click:

```text
Run
```

Verify:

```cmd
netstat -ano | findstr :80
```

Expected:

```text
TCP    192.168.253.1:80      LISTENING
TCP    192.168.253.136:80    LISTENING
```

---

# Step 10 - Verify After Reboot

Restart Windows.

Verify Repository:

```text
http://192.168.253.136/repo/
```

or

```text
http://repo.vgs.com/repo/
```

Verify Technitium:

```text
http://192.168.253.1
```

Both services should start automatically after Windows boots.

---

# Final Lab Architecture

```text
                   Windows Laptop
         ┌────────────────────────────────────┐
         │                                    │
         │ 192.168.253.1                      │
         │ Technitium DNS Server              │
         │ Web Console (Port 80)              │
         │                                    │
         ├────────────────────────────────────┤
         │                                    │
         │ 192.168.253.136                    │
         │ Python HTTP Repository             │
         │ Repository Root : E:\              │
         │ HTTP Port 80                       │
         │                                    │
         └────────────────────────────────────┘
                      ▲
                      │
        Linux / Foreman / Katello / AWX
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
    ├── elevate
    ├── installed_rhel7
    ├── installed_rhel8
    └── ansible
```

---

# Useful Commands

## Start Repository Manually

```bash
cd /e
py -m http.server 80 --bind 192.168.253.136
```

---

## Verify Listening Ports

```cmd
netstat -ano | findstr :80
```

---

## Verify Repository

```bash
curl http://192.168.253.136/repo/rocky8/
```

---

## Verify Repository Metadata

```bash
curl http://192.168.253.136/repo/rocky8/repodata/repomd.xml
```

---

## Verify DNS

```cmd
nslookup repo.vgs.com 192.168.253.1
```

---

## Verify from Linux

```bash
curl http://repo.vgs.com/repo/rocky8/
```

---

# Result

After completing this guide:

* ✔ Technitium DNS runs on **192.168.253.1:80**
* ✔ Python Repository runs on **192.168.253.136:80**
* ✔ Repository starts automatically at Windows startup using Task Scheduler.
* ✔ Linux servers, Foreman, AWX, and Katello can access the repository using:

```text
http://repo.vgs.com/repo/
```

or

```text
http://192.168.253.136/repo/
```
