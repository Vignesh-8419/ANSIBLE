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
