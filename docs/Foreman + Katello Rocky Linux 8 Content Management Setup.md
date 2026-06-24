# Foreman + Katello Rocky Linux 8 Content Management Setup

## Overview

This guide configures Foreman and Katello as a Satellite-like content management server for Rocky Linux 8.

The setup provides:

* Centralized repository management
* Content Views
* Lifecycle Environments
* Activation Keys
* Host Registration
* Controlled Patch Management
* Dev → QA → Prod Promotion Workflow

---

# Environment

## Foreman Server

| Component    | Value                     |
| ------------ | ------------------------- |
| Foreman      | Installed                 |
| Katello      | Installed                 |
| Pulp         | Running                   |
| Organization | Default Organization      |
| Lifecycle    | Library → Dev → QA → Prod |

---

# Repository Layout

Rocky Linux 8 uses the following repositories:

## BaseOS

Contains core operating system packages.

Examples:

* kernel
* glibc
* systemd
* bash
* coreutils

Repository URL:

```text
http://<repo-server>/rocky8/BaseOS/x86_64/os/
```

Repository Name:

```text
Rocky8-BaseOS
```

---

## AppStream

Contains applications and module streams.

Examples:

* python
* php
* nodejs
* postgresql
* mariadb
* podman

Repository URL:

```text
http://<repo-server>/rocky8/AppStream/x86_64/os/
```

Repository Name:

```text
Rocky8-AppStream
```

---

## Extras (Optional)

Contains additional packages.

Repository URL:

```text
http://<repo-server>/rocky8/extras/x86_64/os/
```

Repository Name:

```text
Rocky8-Extras
```

---

# Create Product

Navigate to:

```text
Content → Products
```

Create Product:

```text
Rocky8
```

```text
Restrict to OS - No restriction (Else repositories will be empty)
```

Add repositories:

```text
Rocky8-BaseOS
Rocky8-AppStream
Rocky8-Extras
```

---

# Synchronize Repositories

Navigate to:

```text
Content → Products → Rocky8
```

Select each repository and click:

```text
Sync Now
```

Verify status:

```text
Content → Sync Status
```

Expected:

```text
Last Sync: Success
```

---

# Create Lifecycle Environments

Navigate to:

```text
Content → Lifecycle Environments
```

Create:

```text
Library
 └── Dev
      └── QA
           └── Prod
```

Purpose:

* Dev = Testing
* QA = Validation
* Prod = Production

---

# Create Content View

Navigate to:

```text
Content → Content Views
```

Create:

```text
Rocky8-CV
```

Add repositories:

```text
Rocky8-BaseOS
Rocky8-AppStream
Rocky8-Extras
```

Publish:

```text
Publish New Version
```

Example:

```text
Version 1.0
```

---

# Promote Content View

Promote content through environments:

```text
Library → Dev
Dev → QA
QA → Prod
```

Benefits:

* Controlled software rollout
* Testing before production deployment
* Easy rollback

---

# Create Activation Key

Navigate to:

```text
Content → Activation Keys
```

Create:

```text
Name: rocky8-prod-key
Lifecycle Environment: Prod
Content View: Rocky8-CV
```

Enable repositories:

```text
Rocky8-BaseOS
Rocky8-AppStream
Rocky8-Extras
```

Save activation key.

---

# Register Rocky Linux 8 Client

Install Katello CA package:

```bash
rpm -Uvh http://<foreman-server>/pub/katello-ca-consumer-latest.noarch.rpm
```

Register host:

```bash
subscription-manager register \
  --org="Default_Organization" \
  --activationkey="rocky8-prod-key"
```

Verify registration:

```bash
subscription-manager identity
```

---

# Verify Enabled Repositories

Check repositories:

```bash
dnf repolist
```

Expected:

```text
Rocky8-BaseOS
Rocky8-AppStream
Rocky8-Extras
```

---

# Perform Updates

Update system:

```bash
dnf update -y
```

Packages will now be served by Katello.

---

# Verify Host in Foreman

Navigate to:

```text
Hosts → Content Hosts
```

Verify:

* Host appears
* Activation key assigned
* Content View assigned
* Lifecycle Environment assigned

---

# Recommended Workflow

```text
Internet/Repo Server
        ↓
Katello Sync
        ↓
Content View
        ↓
Lifecycle Environment
        ↓
Activation Key
        ↓
Registered Host
        ↓
dnf update
```
## RHEL 8

```text
mkdir /etc/yum.repos.d/backup
mv /etc/yum.repos.d/* /etc/yum.repos.d/backup/

cat <<EOF > /etc/yum.repos.d/rocky8-baseos.repo
rocky8-baseos
name=Rocky Linux 8 BaseOS
baseurl=https://192.168.253.136/repo/rocky8/BaseOS
enabled=1
gpgcheck=0
sslverify=0
module_hotfixes=true
EOF

cat <<EOF > /etc/yum.repos.d/rocky8-appstream.repo
rocky8-appstream
name=Rocky Linux 8 AppStream
baseurl=https://192.168.253.136/repo/rocky8/Appstream
enabled=1
gpgcheck=0
sslverify=0
module_hotfixes=true
EOF

cat <<EOF > /etc/yum.repos.d/rocky8-rhel-installed.repo
rocky8-rhel-installed
name=Rocky Linux 8 Installed RHEL
baseurl=https://192.168.253.136/repo/installed_rhel8
enabled=1
gpgcheck=0
sslverify=0
module_hotfixes=true
EOF

yum clean all
yum install -y subscription-manager
rm -rf /etc/yum.repos.d/rocky8-appstream.repo
rm -rf /etc/yum.repos.d/rocky8-baseos.repo
rm -rf /etc/yum.repos.d/rocky8-rhel-installed.repo
```

## RHEL 7

```text
mkdir /etc/yum.repos.d/backup
mv /etc/yum.repos.d/* /etc/yum.repos.d/backup/
cat >/etc/yum.repos.d/patch.repo <<EOF
[patch]
name=patch-repo
baseurl=http://http-server-01/repo/installed_rhel7
enabled=1
gpgcheck=0
EOF

cat >/etc/yum.repos.d/base.repo <<EOF
[base]
name=base-repo
baseurl=http://http-server-01/repo/centos/
enabled=1
gpgcheck=0
EOF

yum clean all
yum install -y subscription-manager
rm -rf /etc/yum.repos.d/base.repo
rm -rf /etc/yum.repos.d/patch.repo
```

---

# Benefits

* Centralized repository management
* Controlled updates
* Versioned content
* Lifecycle promotion
* Enterprise patch management
* Satellite-like functionality using Foreman and Katello

```
```
