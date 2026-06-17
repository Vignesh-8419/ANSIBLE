# NetBox Service Memory Issue Fix SOP

![NetBox](https://img.shields.io/badge/NetBox-v4.x-green)
![Systemd](https://img.shields.io/badge/Systemd-Service-blue)
![Gunicorn](https://img.shields.io/badge/Gunicorn-Tuning-orange)
![Performance](https://img.shields.io/badge/Performance-Memory_Optimization-red)

---

# Overview

This SOP documents how to troubleshoot and resolve NetBox service instability, memory exhaustion, Gunicorn worker crashes, and timeout issues by optimizing the NetBox systemd service configuration.

Common symptoms include:

* NetBox UI becomes slow or unresponsive
* HTTP 502 / 504 errors
* Gunicorn worker crashes
* Out-of-memory (OOM) events
* NetBox service restarts unexpectedly
* Long-running requests timing out
* Excessive CPU and memory utilization

---

# Environment

| Component       | Value                                |
| --------------- | ------------------------------------ |
| Application     | NetBox                               |
| Service Manager | systemd                              |
| WSGI Server     | Gunicorn                             |
| Service File    | `/etc/systemd/system/netbox.service` |
| OS              | Rocky Linux / RHEL                   |

---

# Symptoms

## Check NetBox Service Status

```bash
systemctl status netbox
```

Example:

```text
Worker timeout
Worker exited unexpectedly
Killed process (OOM)
502 Bad Gateway
```

---

## Review NetBox Logs

```bash
journalctl -u netbox -f
```

Example:

```text
Worker timeout (pid:12345)
Worker exiting
Booting worker with pid:12350
```

---

## Check Memory Utilization

```bash
free -h
```

```bash
top
```

```bash
htop
```

---

# Existing Configuration

## Review Current Service Configuration

```bash
cat /etc/systemd/system/netbox.service
```

Current configuration:

```ini
[Unit]
Description=NetBox WSGI Service
After=network.target

[Service]
WorkingDirectory=/opt/netbox/netbox

ExecStart=/opt/netbox/venv/bin/gunicorn --bind 127.0.0.1:8001 --timeout 120 --workers 3 netbox.wsgi
ExecStart=/opt/netbox/venv/bin/gunicorn --bind 127.0.0.1:8001 --timeout 300 --workers 3 --worker-class gthread --threads 2 netbox.wsgi

Restart=always

[Install]
WantedBy=multi-user.target
```

---

# Root Cause Analysis

The service file contains **multiple ExecStart directives**.

```ini
ExecStart=/opt/netbox/venv/bin/gunicorn --bind 127.0.0.1:8001 --timeout 120 --workers 3 netbox.wsgi

ExecStart=/opt/netbox/venv/bin/gunicorn --bind 127.0.0.1:8001 --timeout 300 --workers 3 --worker-class gthread --threads 2 netbox.wsgi
```

Potential issues:

* Service startup failures
* Worker management problems
* Higher memory utilization
* Unexpected Gunicorn behavior
* Increased restart frequency

---

# Recommended Fix

## Backup Existing Service File

```bash
cp /etc/systemd/system/netbox.service \
   /etc/systemd/system/netbox.service.bak
```

---

## Edit Service File

```bash
vi /etc/systemd/system/netbox.service
```

Replace the existing configuration with:

```ini
[Unit]
Description=NetBox WSGI Service
After=network.target

[Service]
WorkingDirectory=/opt/netbox/netbox

ExecStart=/opt/netbox/venv/bin/gunicorn \
  --bind 127.0.0.1:8001 \
  --timeout 300 \
  --workers 2 \
  --worker-class gthread \
  --threads 4 \
  netbox.wsgi

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

---

# Configuration Explanation

| Parameter    | Value          | Purpose                    |
| ------------ | -------------- | -------------------------- |
| bind         | 127.0.0.1:8001 | Gunicorn listener          |
| timeout      | 300            | Prevent request timeout    |
| workers      | 2              | Lower memory consumption   |
| worker-class | gthread        | Threaded worker model      |
| threads      | 4              | Handle concurrent requests |
| Restart      | always         | Auto recovery              |
| RestartSec   | 10             | Restart delay              |

---

# Apply Changes

## Reload systemd

```bash
systemctl daemon-reload
```

---

## Restart NetBox

```bash
systemctl restart netbox
```

---

## Verify Service Status

```bash
systemctl status netbox
```

Expected:

```text
Active: active (running)
```

---

# Validation

## Verify Port 8001

```bash
ss -tulpn | grep 8001
```

Expected:

```text
127.0.0.1:8001
```

---

## Verify Gunicorn Processes

```bash
ps -ef | grep gunicorn
```

Expected:

```text
master process
worker process
worker process
```

---

## Verify NetBox Application

```bash
curl http://127.0.0.1:8001
```

Expected:

```html
<!DOCTYPE html>
<html>
...
```

---

## Verify NGINX Connectivity

```bash
curl http://127.0.0.1
```

---

# Optional Memory Optimization

For systems with limited RAM (4 GB or less), reduce worker count:

```ini
ExecStart=/opt/netbox/venv/bin/gunicorn \
  --bind 127.0.0.1:8001 \
  --timeout 300 \
  --workers 1 \
  --worker-class gthread \
  --threads 4 \
  netbox.wsgi
```

---

# Optional Swap Configuration

## Check Existing Swap

```bash
swapon --show
```

---

## Create 4 GB Swap File

```bash
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
```

---

## Persist Swap

```bash
echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
```

---

# Troubleshooting Commands

## Follow Service Logs

```bash
journalctl -u netbox -f
```

---

## Review System Errors

```bash
journalctl -xe
```

---

## Verify Gunicorn Processes

```bash
ps -ef | grep gunicorn
```

---

## Check Memory Utilization

```bash
free -h
```

```bash
top
```

---

## Check Top Memory Consumers

```bash
ps aux --sort=-%mem | head
```

---

# Validation Checklist

## Service Configuration

* [ ] Service file backed up
* [ ] Duplicate ExecStart removed
* [ ] Gunicorn tuning applied

## Service Validation

* [ ] daemon-reload completed
* [ ] NetBox restarted successfully
* [ ] Service running

## Connectivity

* [ ] Port 8001 listening
* [ ] NetBox UI accessible
* [ ] NGINX connectivity verified

## Memory Optimization

* [ ] Memory usage reduced
* [ ] No OOM events
* [ ] No worker crashes
* [ ] No timeout errors

---

# Completion Criteria

The implementation is considered successful when:

* NetBox service remains stable.
* Gunicorn workers do not crash.
* Memory consumption remains within acceptable limits.
* No timeout or OOM events occur.
* NetBox UI loads consistently.
* Logs show healthy worker operation.

---

# Quick Recovery Commands

```bash
cp /etc/systemd/system/netbox.service \
   /etc/systemd/system/netbox.service.bak

vi /etc/systemd/system/netbox.service

systemctl daemon-reload

systemctl restart netbox

systemctl status netbox

journalctl -u netbox -f
```

---

> **Note:** For most NetBox lab environments (2–4 vCPU, 4–8 GB RAM), using `workers=2` and `threads=4` provides a good balance between performance and memory utilization.
