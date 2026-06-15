rhsm_client_fix
=========

A comprehensive reference guide and documentation role outlining the manual commands used to fix client-side host registration crashes and validation path failures when connecting Rocky Linux systems to an internal Katello / Satellite smart proxy infrastructure.

Requirements
------------

* **Target OS:** Rocky Linux 8 / RHEL 8 or compatible distributions.
* **Privileges:** Root access (`sudo` or direct root shell) is required to modify system-level paths and state engines.

Role Variables
--------------

No variables are required for this workflow, as it relies on standard system paths.

Dependencies
------------

None. These system engineering commands operate directly at the base filesystem and core package layers.

Example Playbook
----------------

To manually resolve the repository sync and agent tracking crash on the host, execute the following commands sequentially in your terminal:

```bash
# 1. Fix the core filesystem issue by creating the missing internal validation directory
mkdir -p /var/lib/rhsm/repo_server_val

# 2. Assign the standard system operational permissions to the new path
chmod 755 /var/lib/rhsm/repo_server_val

# 3. Refresh the subscription-manager local cache and sync properties with Katello
subscription-manager refresh

# 4. Wipe out old metadata and clean the package manager cache
dnf clean all

# 5. Rebuild the repository cache maps from your managed channels
dnf repolist
