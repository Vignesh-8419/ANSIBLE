rocky8_errata_repo_setup
=========

A comprehensive reference guide and system engineering documentation role outlining the sequence of manual commands executed on `http-server-01.vgs.com` to establish a writable local hybrid repository layer. This implementation bypasses the permission restrictions of an immutable/read-only SMB ISO mount and successfully injects errata update metadata.

Requirements
------------

* **Target OS:** Rocky Linux 8 / RHEL 8 or compatible repository hosting distribution.
* **Storage Requirement:** Minimum 1GB free disk space on the local root partition (`/var/www/html/`) to replicate repository index metadata layers.
* **Privileges:** Full root access (`sudo` or direct root shell) to modify infrastructure mount bindings and localized directory tables.

Role Variables
--------------

No variables are required for this workflow, as it relies on standard system paths.

Dependencies
------------

* `createrepo_c` - For custom metadata compilation.
* `wget` - To safely download upstream errata matrices.

Example Playbook
----------------

To fully build the hybrid metadata repos and inject errata across BaseOS, AppStream, and Updates channels, run the following commands sequentially in your system console terminal:

```bash
# 1. Verify filesystem capacity and ensure the read-only SMB network share is correctly mounted
df -h

# 2. Install necessary tools required for metadata modification and network downloads
dnf install -y createrepo_c wget

# 3. Create a temporary workshop space for managing errata definitions
mkdir -p /tmp/errata && cd /tmp/errata

# 4. Clear historical partial download loops if they exist
rm -f errata.xml*

# 5. Fetch the latest community-verified errata advisory definitions mapping file
wget [https://cefs.steve-meier.de/errata.latest.xml.bz2](https://cefs.steve-meier.de/errata.latest.xml.bz2)

# 6. Decompress the data structure array using bunzip2 tools
bunzip2 errata.latest.xml.bz2

# 7. Standardize the data file identifier name for optimal utility ingestion tracking
mv errata.latest.xml errata.xml

# 8. Construct the active local storage hierarchy partitions on the system root drive
mkdir -p /var/www/html/local_repo/Rocky8-BaseOS
mkdir -p /var/www/html/local_repo/Rocky8-AppStream
mkdir -p /var/www/html/local_repo/Rocky8-Updates

# 9. Duplicate the baseline read-only metadata structures to the new writeable local directories
cp -r /var/www/html/repo/rocky8/BaseOS/repodata /var/www/html/local_repo/Rocky8-BaseOS/
cp -r /var/www/html/repo/rocky8/AppStream/repodata /var/www/html/local_repo/Rocky8-AppStream/
cp -r /var/www/html/repo/installed_rhel8/repodata /var/www/html/local_repo/Rocky8-Updates/

# 10. Link the underlying multi-gigabyte package payload blocks using POSIX symlinks
ln -s /var/www/html/repo/rocky8/BaseOS/Packages /var/www/html/local_repo/Rocky8-BaseOS/Packages
ln -s /var/www/html/repo/rocky8/AppStream/Packages /var/www/html/local_repo/Rocky8-AppStream/Packages
ln -s /var/www/html/repo/installed_rhel8/Packages /var/www/html/local_repo/Rocky8-Updates/Packages

# 11. Run localized modification tools to officially inject errata records into BaseOS channel
modifyrepo_c /tmp/errata/errata.xml /var/www/html/local_repo/Rocky8-BaseOS/repodata/

# 12. Run localized modification tools to officially inject errata records into AppStream channel
modifyrepo_c /tmp/errata/errata.xml /var/www/html/local_repo/Rocky8-AppStream/repodata/

# 13. Run localized modification tools to officially inject errata records into Updates channel
modifyrepo_c /tmp/errata/errata.xml /var/www/html/local_repo/Rocky8-Updates/repodata/

##foreman-installer --enable-foreman-proxy-plugin-remote-execution-script
Go to Hosts > Run Job.Set Job category to Commands and Job template to Run Command - SSH.Select your target group of servers using the Search Query bar.Paste the script above into the Command field.Scroll down to Scheduling, select Once, set your target maintenance window time, and click Submit.
[ "$(uname -r)" = "4.18.0-553.132.1.el8_10.x86_64" ] && echo "Target kernel already active. Skipping." || (echo "Outdated kernel found. Patching..." && dnf update -y && shutdown -r +1 "Patch applied. Rebooting.")
