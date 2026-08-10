# Foreman Bootstrap Scripts - Run Commands

## Make All Scripts Executable

chmod +x 01_foreman_pxe_bootstrap_api.sh
chmod +x 02_foreman_katello_bootstrap_api.sh
chmod +x 02_foreman_pxe_bootstrap_single_disk_api.sh
chmod +x 03_foreman_hostgroup_bootstrap_raid_api.sh
chmod +x 03_foreman_hostgroup_bootstrap_single_disk_api.sh
chmod +x 04-bootstrap-el7toel8_api.sh
chmod +x 05-bootstrap-el8toel9_api.sh


###############################################################################
# 01 - Foreman PXE Bootstrap
###############################################################################

export FOREMAN_USER='admin'
export FOREMAN_TOKEN='oUzg-aMfjcT3q_wZ8NRLfQ'

TARGET_VERSION=9.2 ./01_foreman_pxe_bootstrap_api.sh

TARGET_VERSION=9.8 ./01_foreman_pxe_bootstrap_api.sh


###############################################################################
# 02 - Foreman Katello Bootstrap
###############################################################################

export FOREMAN_USER='admin'
export FOREMAN_PASSWORD='oUzg-aMfjcT3q_wZ8NRLfQ'

TARGET_VERSION=9.2 ./02_foreman_katello_bootstrap_api.sh

TARGET_VERSION=9.8 ./02_foreman_katello_bootstrap_api.sh


###############################################################################
# 02 - Foreman PXE Bootstrap Single Disk
###############################################################################

export FOREMAN_USER='admin'
export FOREMAN_TOKEN='oUzg-aMfjcT3q_wZ8NRLfQ'

TARGET_VERSION=9.2 ./02_foreman_pxe_bootstrap_single_disk_api.sh

TARGET_VERSION=9.8 ./02_foreman_pxe_bootstrap_single_disk_api.sh


###############################################################################
# 03 - Foreman Hostgroup Bootstrap RAID
###############################################################################

export FOREMAN_USER='admin'
export FOREMAN_PASSWORD='oUzg-aMfjcT3q_wZ8NRLfQ'

TARGET_VERSION=9.2 ./03_foreman_hostgroup_bootstrap_raid_api.sh

TARGET_VERSION=9.8 ./03_foreman_hostgroup_bootstrap_raid_api.sh

TARGET_VERSION=ALL ./03_foreman_hostgroup_bootstrap_raid_api.sh


###############################################################################
# 03 - Foreman Hostgroup Bootstrap Single Disk
###############################################################################

export FOREMAN_USER='admin'
export FOREMAN_PASSWORD='oUzg-aMfjcT3q_wZ8NRLfQ'

TARGET_VERSION=9.2 ./03_foreman_hostgroup_bootstrap_single_disk_api.sh

TARGET_VERSION=9.8 ./03_foreman_hostgroup_bootstrap_single_disk_api.sh

TARGET_VERSION=ALL ./03_foreman_hostgroup_bootstrap_single_disk_api.sh


###############################################################################
# 04 - EL7 To EL8 Bootstrap
###############################################################################

export FOREMAN_USER='admin'
export FOREMAN_PASSWORD='oUzg-aMfjcT3q_wZ8NRLfQ'

./04-bootstrap-el7toel8_api.sh


###############################################################################
# 05 - EL8 To EL9 Bootstrap
###############################################################################

export FOREMAN_USER='admin'
export FOREMAN_PASSWORD='oUzg-aMfjcT3q_wZ8NRLfQ'

TARGET_VERSION=9.2 ./05-bootstrap-el8toel9_api.sh

TARGET_VERSION=9.8 ./05-bootstrap-el8toel9_api.sh
