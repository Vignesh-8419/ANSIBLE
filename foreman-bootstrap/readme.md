# Foreman Bootstrap - Complete Execution Commands

## Full Deployment Execution Order

Run all Foreman bootstrap scripts in this order.

```bash
###############################################################################
# 01 - PXE Bootstrap
# Creates:
#   - Installation Media
#   - Operating Systems
#   - RAID PXE Templates
#   - Subnets
#   - PXE Configuration
###############################################################################

TARGET_VERSION=9.8 ./01_foreman_pxe_bootstrap.sh
TARGET_VERSION=9.2 ./01_foreman_pxe_bootstrap.sh


###############################################################################
# 02 - Katello Bootstrap
# Creates:
#   - Products
#   - Repositories
#   - Content Views
#   - Activation Keys
###############################################################################

TARGET_VERSION=9.8 ./02_foreman_katello_bootstrap.sh
TARGET_VERSION=9.2 ./02_foreman_katello_bootstrap.sh

###############################################################################
# 02 - Single Disk PXE Bootstrap
# Creates:
#   - Single Disk PXE Templates
#   - Single Disk OS Template Mapping
###############################################################################

TARGET_VERSION=ALL ./02_foreman_pxe_bootstrap_single_disk.sh


###############################################################################
# 03 - RAID Hostgroup Bootstrap
# Creates:
#   - RAID Hostgroups
#   - RAID Template Mapping
###############################################################################

TARGET_VERSION=ALL ./03_foreman_hostgroup_bootstrap_raid.sh


###############################################################################
# 03 - Single Disk Hostgroup Bootstrap
# Creates:
#   - Single Disk Hostgroups
#   - Single Disk Template Mapping
###############################################################################

TARGET_VERSION=ALL ./03_foreman_hostgroup_bootstrap_single_disk.sh


###############################################################################
# 04 - EL7 To EL8 Bootstrap
# Creates:
#   - ELevate / Leapp EL7 to EL8 Migration Configuration
###############################################################################

./04-bootstrap-el7toel8.sh


###############################################################################
# 05 - EL8 To EL9 Bootstrap
# Creates:
#   - Leapp EL8 to EL9 Migration Configuration
###############################################################################

./05-bootstrap-el8toel9.sh
