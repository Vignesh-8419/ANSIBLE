# Build Custom leapp-data-rocky RPM for Offline EL8 → EL9 Upgrades

## Overview

By default, `leapp-data-rocky` installs:

```
/etc/leapp/files/leapp_upgrade_repositories.repo
```

which contains the online Rocky mirror URLs.

For an offline/Katello environment, we rebuild the `leapp-data-rocky` RPM so that it automatically installs our own repository configuration.

We build two RPMs:

- Rocky 9.2
- Rocky 9.8

---

# Prerequisites

```bash
dnf install -y rpm-build rpmdevtools python3-jsonschema
rpmdev-setuptree
```

---

# Download Source RPM

```bash
curl -LO https://build.almalinux.org/pulp/content/prod/almalinux8-baseos/Packages/l/leapp-data-rocky-0.9-1.el8.20250505.src.rpm
```

Install the source RPM.

```bash
rpm -ivh leapp-data-rocky-0.9-1.el8.20250505.src.rpm
```

Verify.

```bash
ls ~/rpmbuild/SPECS
```

Expected

```
leapp-data.spec
```

---

# Verify Source Archive

```bash
file ~/rpmbuild/SOURCES/leapp-data-0.9.tar.gz
```

Output

```
bzip2 compressed data
```

---

# Extract Source

```bash
cd ~/rpmbuild/SOURCES

tar -xjf leapp-data-0.9.tar.gz
```

Verify.

```bash
ls
```

Expected

```
leapp-data-0.9.tar.gz
leapp-data-rocky-0.9
```

---

# Locate Repository File

```bash
cd ~/rpmbuild/SOURCES/leapp-data-rocky-0.9/files/rocky
```

Verify.

```bash
ls
```

You should see

```
leapp_upgrade_repositories.repo.el8
leapp_upgrade_repositories.repo.el9
repomap.json.el8
repomap.json.el9
...
```

---

# ==========================================================
# Build Rocky 9.2 RPM
# ==========================================================

Edit

```bash
vi leapp_upgrade_repositories.repo.el9
```

Replace contents with

```ini
[rocky9-baseos]
name=Rocky Linux 9 - BaseOS
baseurl=http://http-server-01/repo/rocky9.2/BaseOS/
gpgcheck=1
enabled=1
gpgkey=file:///etc/leapp/repos.d/system_upgrade/common/files/rpm-gpg/9/RPM-GPG-KEY-Rocky-9

[rocky9-appstream]
name=Rocky Linux 9 - AppStream
baseurl=http://http-server-01/repo/rocky9.2/AppStream/
gpgcheck=1
enabled=1
gpgkey=file:///etc/leapp/repos.d/system_upgrade/common/files/rpm-gpg/9/RPM-GPG-KEY-Rocky-9
```

Go back to SOURCES.

```bash
cd ~/rpmbuild/SOURCES
```

Remove old archive.

```bash
rm -f leapp-data-0.9.tar.gz
```

Create new archive.

```bash
tar -cjf leapp-data-0.9.tar.gz leapp-data-rocky-0.9
```

Rebuild RPM.

```bash
rpmbuild -ba ~/rpmbuild/SPECS/leapp-data.spec \
    --define "dist_name rocky"
```

Copy RPM.

```bash
cp ~/rpmbuild/RPMS/noarch/leapp-data-rocky-0.9-1.el8.20250505.noarch.rpm \
   ~/rpmbuild/RPMS/noarch/leapp-data-rocky-9.2.noarch.rpm
```

---

# Verify Rocky 9.2 RPM

```bash
mkdir /tmp/test92

cd /tmp/test92
```

Extract.

```bash
rpm2cpio ~/rpmbuild/RPMS/noarch/leapp-data-rocky-9.2.noarch.rpm | cpio -idmv
```

Verify.

```bash
cat etc/leapp/files/leapp_upgrade_repositories.repo
```

Expected

```ini
baseurl=http://http-server-01/repo/rocky9.2/BaseOS/

baseurl=http://http-server-01/repo/rocky9.2/AppStream/
```

---

# ==========================================================
# Build Rocky 9.8 RPM
# ==========================================================

Go back.

```bash
cd ~/rpmbuild/SOURCES/leapp-data-rocky-0.9/files/rocky
```

Edit

```bash
vi leapp_upgrade_repositories.repo.el9
```

Replace contents with

```ini
[rocky9-baseos]
name=Rocky Linux 9 - BaseOS
baseurl=http://http-server-01/repo/rocky9/BaseOS/
gpgcheck=1
enabled=1
gpgkey=file:///etc/leapp/repos.d/system_upgrade/common/files/rpm-gpg/9/RPM-GPG-KEY-Rocky-9

[rocky9-appstream]
name=Rocky Linux 9 - AppStream
baseurl=http://http-server-01/repo/rocky9/AppStream/
gpgcheck=1
enabled=1
gpgkey=file:///etc/leapp/repos.d/system_upgrade/common/files/rpm-gpg/9/RPM-GPG-KEY-Rocky-9
```

Return to SOURCES.

```bash
cd ~/rpmbuild/SOURCES
```

Delete archive.

```bash
rm -f leapp-data-0.9.tar.gz
```

Recreate archive.

```bash
tar -cjf leapp-data-0.9.tar.gz leapp-data-rocky-0.9
```

Rebuild.

```bash
rpmbuild -ba ~/rpmbuild/SPECS/leapp-data.spec \
    --define "dist_name rocky"
```

Save RPM.

```bash
cp ~/rpmbuild/RPMS/noarch/leapp-data-rocky-0.9-1.el8.20250505.noarch.rpm \
   ~/rpmbuild/RPMS/noarch/leapp-data-rocky-9.8.noarch.rpm
```

---

# Verify Rocky 9.8 RPM

```bash
mkdir /tmp/test98

cd /tmp/test98
```

Extract.

```bash
rpm2cpio ~/rpmbuild/RPMS/noarch/leapp-data-rocky-9.8.noarch.rpm | cpio -idmv
```

Verify.

```bash
cat etc/leapp/files/leapp_upgrade_repositories.repo
```

Expected

```ini
baseurl=http://http-server-01/repo/rocky9/BaseOS/

baseurl=http://http-server-01/repo/rocky9/AppStream/
```

---

# Final RPMs

```
~/rpmbuild/RPMS/noarch/leapp-data-rocky-9.2.noarch.rpm

~/rpmbuild/RPMS/noarch/leapp-data-rocky-9.8.noarch.rpm
```

---

# Installing on Upgrade Servers

## Rocky 9.2 Upgrade

```bash
dnf remove -y leapp-data-rocky

dnf install -y leapp-data-rocky-9.2.noarch.rpm
```

Verify

```bash
cat /etc/leapp/files/leapp_upgrade_repositories.repo
```

---

## Rocky 9.8 Upgrade

```bash
dnf remove -y leapp-data-rocky

dnf install -y leapp-data-rocky-9.8.noarch.rpm
```

Verify

```bash
cat /etc/leapp/files/leapp_upgrade_repositories.repo
```

---

# Result

After installing the appropriate custom RPM:

- `/etc/leapp/files/leapp_upgrade_repositories.repo` is automatically installed with the correct offline repository URLs.
- No manual editing of the Leapp repository configuration is required.
- The RPM can be distributed through Katello or any local repository and installed before running `leapp preupgrade` or `leapp upgrade`.
