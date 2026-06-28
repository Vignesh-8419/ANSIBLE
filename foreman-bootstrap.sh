#!/bin/bash
###############################################################################
# Foreman PXE Provisioning + Katello Bootstrap
# CentOS 7 & Rocky Linux 8.10
###############################################################################

set -e

echo "============================================================"
echo " Foreman PXE Provisioning + Katello Bootstrap"
echo "============================================================"
echo

###############################################################################
# Variables
###############################################################################

HAMMER="hammer --username admin --password 'zqs977dXzqfEvTML'"

###############################################################################
# 1. Create Installation Media
###############################################################################

echo "============================================================"
echo "[1/13] Creating Installation Media"
echo "============================================================"

echo "Creating CentOS 7 Installation Media..."

$HAMMER medium create \
--name "CentOS 7 Remote" \
--path "http://192.168.253.136/repo/centos/" \
--os-family "Redhat"

echo "Done."
echo

echo "Creating Rocky Linux 8 Installation Media..."

$HAMMER medium create \
--name "Rocky 8 Remote" \
--path "http://192.168.253.136/repo/rocky8/" \
--os-family "Redhat"

echo "Done."
echo

###############################################################################
# 2. Create Operating Systems
###############################################################################

echo "============================================================"
echo "[2/13] Creating Operating Systems"
echo "============================================================"

echo "Creating CentOS Linux 7..."

$HAMMER os create \
--name CentOSLinux \
--major 7 \
--family Redhat \
--architectures x86_64 \
--partition-tables "Kickstart default" \
--media "CentOS 7 Remote"

echo "Done."
echo

echo "Creating Rocky Linux 8.10..."

$HAMMER os create \
--name RockyLinux \
--major 8 \
--minor 10 \
--family Redhat \
--architectures x86_64 \
--partition-tables "Kickstart default" \
--media "Rocky 8 Remote"

echo "Done."
echo

###############################################################################
# Verification
###############################################################################

echo "============================================================"
echo "Verifying Installation Media"
echo "============================================================"

$HAMMER medium list

echo

echo "============================================================"
echo "Verifying Operating Systems"
echo "============================================================"

$HAMMER os list

echo
echo "Part 1A Completed Successfully."
echo

###############################################################################
# 3. Create PXEGrub2 Provisioning Template
# Rocky Linux 8.10
###############################################################################

echo "============================================================"
echo "[3/13] Creating Rocky Linux PXEGrub2 Template"
echo "============================================================"

echo "Creating Rocky PXEGrub2 template file..."

cat > /tmp/rocky-pxegrub2.erb <<'EOF'
<%#
name: PXEGrub2 RockyOS UEFI Static Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5

menuentry 'Install RockyOS via Kickstart' {

    linuxefi /rockyos/vmlinuz \
inst.stage2=http://192.168.253.136/repo/rocky8/ \
inst.ks=http://192.168.253.136/repo/rocky8/kickstart/rockyos.cfg \
inst.text \
inst.default_fstype=ext4 \
inst.ks.device=bootif \
BOOTIF=01-${net_default_mac} \
hostname=<%= @host.name %>

    initrdefi /rockyos/initrd.img

}
EOF

echo "Template file created."
echo

echo "Importing Rocky PXEGrub2 template into Foreman..."

$HAMMER template create \
--name "PXEGrub2 RockyOS UEFI Static Kickstart" \
--type PXEGrub2 \
--file /tmp/rocky-pxegrub2.erb

echo "Done."
echo

echo "Assigning Rocky PXEGrub2 template to RockyLinux 8.10..."

$HAMMER os add-provisioning-template \
--title "RockyLinux 8.10" \
--provisioning-template "PXEGrub2 RockyOS UEFI Static Kickstart"

echo "Done."
echo

echo "Current PXE Templates"

$HAMMER template list | grep -i Rocky

echo
echo "Rocky PXE Template Completed."
echo

###############################################################################
# 3. Create PXEGrub2 Provisioning Template
# CentOS Linux 7
###############################################################################

echo "============================================================"
echo "[4/13] Creating CentOS Linux PXEGrub2 Template"
echo "============================================================"

echo "Creating CentOS PXEGrub2 template file..."

cat > /tmp/centos-pxegrub2.erb <<'EOF'
<%#
name: PXEGrub2 CentOS UEFI Static Kickstart
kind: PXEGrub2
oses:
- CentOSLinux
%>
set default=0
set timeout=5

menuentry 'Install CentOS via Kickstart' {

    linuxefi /centos/vmlinuz \
inst.stage2=http://192.168.253.136/repo/centos/ \
inst.ks=http://192.168.253.136/repo/centos/kickstart/centos.cfg \
inst.text \
inst.default_fstype=ext4 \
inst.ks.device=bootif \
BOOTIF=01-${net_default_mac} \
hostname=<%= @host.name %>

    initrdefi /centos/initrd.img

}
EOF

echo "Template file created."
echo

echo "Importing CentOS PXEGrub2 template into Foreman..."

$HAMMER template create \
--name "PXEGrub2 CentOS UEFI Static Kickstart" \
--type PXEGrub2 \
--file /tmp/centos-pxegrub2.erb

echo "Done."
echo

echo "Assigning CentOS PXEGrub2 template to CentOSLinux 7..."

$HAMMER os add-provisioning-template \
--title "CentOSLinux 7" \
--provisioning-template "PXEGrub2 CentOS UEFI Static Kickstart"

echo "Done."
echo

###############################################################################
# Verify Templates
###############################################################################

echo "============================================================"
echo "Current PXE Templates"
echo "============================================================"

$HAMMER template list | grep -i UEFI

echo
echo "CentOS PXE Template Completed."
echo

###############################################################################
# 4. Create Subnets
###############################################################################

echo "============================================================"
echo "[5/13] Creating Subnets"
echo "============================================================"

###############################################################################
# Create CentOS Subnet
###############################################################################

echo "Creating CentOS Subnet..."

$HAMMER subnet create \
--name "vgs-subnet-centos" \
--network "192.168.253.0" \
--mask "255.255.255.0" \
--gateway "192.168.253.2" \
--dns-primary "192.168.253.1" \
--from "192.168.253.10" \
--to "192.168.253.240" \
--ipam DHCP \
--boot-mode DHCP \
--mtu 1500 \
--domains "vgs.com" \
--dhcp "cent-07-01.vgs.com" \
--tftp "cent-07-01.vgs.com"

echo "CentOS subnet created."
echo

###############################################################################
# Create Rocky Linux Subnet
###############################################################################

echo "Creating Rocky Linux Subnet..."

$HAMMER subnet create \
--name "vgs-subnet-rockyos" \
--network "192.168.253.0" \
--mask "255.255.255.0" \
--gateway "192.168.253.2" \
--dns-primary "192.168.253.1" \
--from "192.168.253.10" \
--to "192.168.253.240" \
--ipam DHCP \
--boot-mode DHCP \
--mtu 1500 \
--domains "vgs.com" \
--dhcp "cent-07-02.vgs.com" \
--tftp "cent-07-02.vgs.com"

echo "Rocky subnet created."
echo

###############################################################################
# Verify Subnets
###############################################################################

echo "============================================================"
echo "Verifying Subnets"
echo "============================================================"

$HAMMER subnet list

echo
echo "Subnets Created Successfully."
echo

###############################################################################
# 5. Create Host Groups
###############################################################################

echo "============================================================"
echo "[6/13] Creating Host Groups"
echo "============================================================"

###############################################################################
# CentOS 7 Host Group
###############################################################################

echo "Creating CentOS 7 Host Group..."

$HAMMER hostgroup create \
--organization "Default Organization" \
--name "VGS HOSTS CENTOS 7" \
--architecture x86_64 \
--operatingsystem "CentOSLinux 7" \
--medium "CentOS 7 Remote" \
--partition-table "Kickstart default" \
--pxe-loader "Grub2 UEFI" \
--domain "vgs.com" \
--subnet "vgs-subnet-centos" \
--content-source "cent-07-01.vgs.com" \
--content-view "Default Organization View" \
--lifecycle-environment "Library"

echo "CentOS Host Group created."
echo

###############################################################################
# Rocky Linux 8 Host Group
###############################################################################

echo "Creating Rocky Linux 8 Host Group..."

$HAMMER hostgroup create \
--organization "Default Organization" \
--name "VGS HOSTS ROCKY 8" \
--architecture x86_64 \
--operatingsystem "RockyLinux 8.10" \
--medium "Rocky 8 Remote" \
--partition-table "Kickstart default" \
--pxe-loader "Grub2 UEFI" \
--domain "vgs.com" \
--subnet "vgs-subnet-rockyos" \
--content-source "cent-07-01.vgs.com" \
--content-view "Default Organization View" \
--lifecycle-environment "Library"

echo "Rocky Host Group created."
echo

###############################################################################
# 6. Set Default PXE Templates
###############################################################################

echo "============================================================"
echo "[7/13] Setting Default PXE Templates"
echo "============================================================"

echo "Current Operating Systems"

$HAMMER os list

echo
echo "Current PXE Templates"

$HAMMER template list | grep -i UEFI

echo

###############################################################################
# IMPORTANT
#
# Verify the IDs below before running the next commands.
#
# Example:
#
# OS ID 2   = CentOSLinux 7
# OS ID 3   = RockyLinux 8.10
#
# Template ID 172 = PXEGrub2 CentOS UEFI Static Kickstart
# Template ID 173 = PXEGrub2 RockyOS UEFI Static Kickstart
#
###############################################################################

echo "Assigning Default Template for CentOS..."

$HAMMER os set-default-template \
--id 2 \
--provisioning-template-id 172

echo "Done."
echo

echo "Assigning Default Template for Rocky Linux..."

$HAMMER os set-default-template \
--id 3 \
--provisioning-template-id 173

echo "Done."
echo

###############################################################################
# Verification
###############################################################################

echo "============================================================"
echo "PXE Provisioning Configuration Summary"
echo "============================================================"

echo
echo "Installation Media"
$HAMMER medium list

echo
echo "Operating Systems"
$HAMMER os list

echo
echo "PXE Templates"
$HAMMER template list | grep -i UEFI

echo
echo "Subnets"
$HAMMER subnet list

echo
echo "Host Groups"
$HAMMER hostgroup list

echo
echo "============================================================"
echo "PXE Provisioning Setup Completed Successfully"
echo "============================================================"
echo

###############################################################################
# Katello Products and Repositories Setup
###############################################################################

echo "============================================================"
echo "[8/13] Creating Katello Products"
echo "============================================================"

###############################################################################
# Create Products
###############################################################################

echo "Creating Rocky Linux 8 Product..."

$HAMMER product create \
--organization "Default Organization" \
--name "Rocky Linux 8"

echo "Done."
echo

echo "Creating CentOS 7 Product..."

$HAMMER product create \
--organization "Default Organization" \
--name "CentOS 7"

echo "Done."
echo

###############################################################################
# CentOS 7 Repositories
###############################################################################

echo "============================================================"
echo "Creating CentOS 7 Repositories"
echo "============================================================"

echo "Creating CentOS-07-BaseOS Repository..."

$HAMMER repository create \
--organization "Default Organization" \
--product "CentOS 7" \
--name "CentOS-07-BaseOS" \
--content-type yum \
--url "http://http-server-01/repo/centos/"

echo "Done."
echo

echo "Creating CentOS-07-Updates Repository..."

$HAMMER repository create \
--organization "Default Organization" \
--product "CentOS 7" \
--name "CentOS-07-Updates" \
--content-type yum \
--url "http://http-server-01/repo/installed_rhel7/"

echo "Done."
echo

###############################################################################
# Rocky Linux 8 Repositories
###############################################################################

echo "============================================================"
echo "Creating Rocky Linux 8 Repositories"
echo "============================================================"

echo "Creating Rocky-08-BaseOS Repository..."

$HAMMER repository create \
--organization "Default Organization" \
--product "Rocky Linux 8" \
--name "Rocky-08-BaseOS" \
--content-type yum \
--url "http://192.168.253.136/repo/rocky8/BaseOS"

echo "Done."
echo

echo "Creating Rocky-08-AppStream Repository..."

$HAMMER repository create \
--organization "Default Organization" \
--product "Rocky Linux 8" \
--name "Rocky-08-AppStream" \
--content-type yum \
--url "http://192.168.253.136/repo/rocky8/Appstream"

echo "Done."
echo

echo "Creating Rocky-08-RHEL-Installed Repository..."

$HAMMER repository create \
--organization "Default Organization" \
--product "Rocky Linux 8" \
--name "Rocky-08-RHEL-Installed" \
--content-type yum \
--url "http://192.168.253.136/repo/installed_rhel8"

echo "Done."
echo

echo "============================================================"
echo "Products and Repository Creation Completed"
echo "============================================================"
echo

###############################################################################
# Synchronize Repositories
###############################################################################

echo "============================================================"
echo "[9/13] Synchronizing Repositories"
echo "============================================================"

###############################################################################
# CentOS 7 Repository Synchronization
###############################################################################

echo "Synchronizing CentOS-07-BaseOS..."

$HAMMER repository synchronize \
--organization "Default Organization" \
--product "CentOS 7" \
--name "CentOS-07-BaseOS"

echo "Done."
echo

echo "Synchronizing CentOS-07-Updates..."

$HAMMER repository synchronize \
--organization "Default Organization" \
--product "CentOS 7" \
--name "CentOS-07-Updates"

echo "Done."
echo

###############################################################################
# Rocky Linux 8 Repository Synchronization
###############################################################################

echo "Synchronizing Rocky-08-AppStream..."

$HAMMER repository synchronize \
--organization "Default Organization" \
--product "Rocky Linux 8" \
--name "Rocky-08-AppStream"

echo "Done."
echo

echo "Synchronizing Rocky-08-BaseOS..."

$HAMMER repository synchronize \
--organization "Default Organization" \
--product "Rocky Linux 8" \
--name "Rocky-08-BaseOS"

echo "Done."
echo

echo "Synchronizing Rocky-08-RHEL-Installed..."

$HAMMER repository synchronize \
--organization "Default Organization" \
--product "Rocky Linux 8" \
--name "Rocky-08-RHEL-Installed"

echo "Done."
echo

###############################################################################
# Verify Products
###############################################################################

echo "============================================================"
echo "Verifying Products"
echo "============================================================"

$HAMMER product list \
--organization "Default Organization"

echo

###############################################################################
# Verify CentOS 7 Repositories
###############################################################################

echo "============================================================"
echo "CentOS 7 Repositories"
echo "============================================================"

$HAMMER repository list \
--organization "Default Organization" \
--product "CentOS 7"

echo

###############################################################################
# Verify Rocky Linux 8 Repositories
###############################################################################

echo "============================================================"
echo "Rocky Linux 8 Repositories"
echo "============================================================"

$HAMMER repository list \
--organization "Default Organization" \
--product "Rocky Linux 8"

echo

echo "============================================================"
echo "Katello Products & Repositories Setup Completed Successfully"
echo "============================================================"
echo

###############################################################################
# Katello Content Views and Activation Keys
###############################################################################

echo "============================================================"
echo "[10/13] Creating Content Views"
echo "============================================================"

###############################################################################
# CentOS 7 Content View
###############################################################################

echo "Creating Content View : CentOS7-CV"

$HAMMER content-view create \
--organization "Default Organization" \
--name "CentOS7-CV"

echo "Done."
echo

echo "Adding CentOS-07-BaseOS..."

$HAMMER content-view add-repository \
--organization "Default Organization" \
--name "CentOS7-CV" \
--product "CentOS 7" \
--repository "CentOS-07-BaseOS"

echo "Done."
echo

echo "Adding CentOS-07-Updates..."

$HAMMER content-view add-repository \
--organization "Default Organization" \
--name "CentOS7-CV" \
--product "CentOS 7" \
--repository "CentOS-07-Updates"

echo "Done."
echo

echo "Publishing CentOS7-CV..."

$HAMMER content-view publish \
--organization "Default Organization" \
--name "CentOS7-CV" \
--description "Initial Publish"

echo "Done."
echo

echo "Creating Activation Key : centos7-prod-key"

$HAMMER activation-key create \
--organization "Default Organization" \
--name "centos7-prod-key" \
--lifecycle-environment "Library" \
--content-view "CentOS7-CV"

echo "Done."
echo

###############################################################################
# Rocky Linux 8 Content View
###############################################################################

echo "============================================================"
echo "Creating Rocky8-CV"
echo "============================================================"

$HAMMER content-view create \
--organization "Default Organization" \
--name "Rocky8-CV"

echo "Done."
echo

echo "Adding Rocky-08-BaseOS..."

$HAMMER content-view add-repository \
--organization "Default Organization" \
--name "Rocky8-CV" \
--product "Rocky Linux 8" \
--repository "Rocky-08-BaseOS"

echo "Done."
echo

echo "Adding Rocky-08-AppStream..."

$HAMMER content-view add-repository \
--organization "Default Organization" \
--name "Rocky8-CV" \
--product "Rocky Linux 8" \
--repository "Rocky-08-AppStream"

echo "Done."
echo

echo "Adding Rocky-08-RHEL-Installed..."

$HAMMER content-view add-repository \
--organization "Default Organization" \
--name "Rocky8-CV" \
--product "Rocky Linux 8" \
--repository "Rocky-08-RHEL-Installed"

echo "Done."
echo

echo "Publishing Rocky8-CV..."

$HAMMER content-view publish \
--organization "Default Organization" \
--name "Rocky8-CV" \
--description "Initial Publish"

echo "Done."
echo

echo "Creating Activation Key : rocky8-prod-key"

$HAMMER activation-key create \
--organization "Default Organization" \
--name "rocky8-prod-key" \
--lifecycle-environment "Library" \
--content-view "Rocky8-CV"

echo "Done."
echo

echo "============================================================"
echo "Content Views Created Successfully"
echo "============================================================"
echo

###############################################################################
# Verification
###############################################################################

echo "============================================================"
echo "[11/13] Verifying Content Views and Activation Keys"
echo "============================================================"

echo "Listing Content Views..."

$HAMMER content-view list

echo

echo "Listing Activation Keys..."

$HAMMER activation-key list

echo

###############################################################################
# Verify CentOS7-CV
###############################################################################

echo "============================================================"
echo "Verifying CentOS7-CV"
echo "============================================================"

$HAMMER content-view info \
--organization "Default Organization" \
--name "CentOS7-CV"

echo

###############################################################################
# Verify Rocky8-CV
###############################################################################

echo "============================================================"
echo "Verifying Rocky8-CV"
echo "============================================================"

$HAMMER content-view info \
--organization "Default Organization" \
--name "Rocky8-CV"

echo

###############################################################################
# Verify Repositories
###############################################################################

echo "============================================================"
echo "CentOS 7 Repositories"
echo "============================================================"

$HAMMER repository list \
--organization "Default Organization" \
--product "CentOS 7"

echo

echo "============================================================"
echo "Rocky Linux 8 Repositories"
echo "============================================================"

$HAMMER repository list \
--organization "Default Organization" \
--product "Rocky Linux 8"

echo

###############################################################################
# Available Subscriptions
###############################################################################

echo "============================================================"
echo "[12/13] Available Subscriptions"
echo "============================================================"

$HAMMER subscription list \
--organization "Default Organization"

echo

###############################################################################
# CentOS Activation Key
###############################################################################

echo "============================================================"
echo "CentOS 7 Activation Key"
echo "============================================================"

$HAMMER activation-key info \
--organization "Default Organization" \
--name "centos7-prod-key"

echo

echo "Attaching Subscription ID 2..."

$HAMMER activation-key add-subscription \
--organization "Default Organization" \
--name "centos7-prod-key" \
--subscription-id 2

echo "Done."
echo

###############################################################################
# Rocky Activation Key
###############################################################################

echo "============================================================"
echo "Rocky Linux 8 Activation Key"
echo "============================================================"

$HAMMER activation-key info \
--organization "Default Organization" \
--name "rocky8-prod-key"

echo

echo "Attaching Subscription ID 1..."

$HAMMER activation-key add-subscription \
--organization "Default Organization" \
--name "rocky8-prod-key" \
--subscription-id 1

echo "Done."
echo

###############################################################################
# Verify Activation Keys
###############################################################################

echo "============================================================"
echo "Activation Keys"
echo "============================================================"

$HAMMER activation-key list \
--organization "Default Organization"

echo

###############################################################################
# Registration Commands
###############################################################################

echo "============================================================"
echo "[13/13] Host Registration Commands"
echo "============================================================"

cat <<EOF

Register CentOS 7 Host

subscription-manager register \
--org="Default Organization" \
--activationkey="centos7-prod-key"

------------------------------------------------------------

Register Rocky Linux 8 Host

subscription-manager register \
--org="Default Organization" \
--activationkey="rocky8-prod-key"

EOF

echo

###############################################################################
# Repository Assignment
###############################################################################

cat <<EOF

============================================================
Repository Assignment
============================================================

CentOS7-CV

  - CentOS-07-BaseOS
  - CentOS-07-Updates

Rocky8-CV

  - Rocky-08-BaseOS
  - Rocky-08-AppStream
  - Rocky-08-RHEL-Installed

EOF

echo

###############################################################################
# Important Notes
###############################################################################

cat <<EOF

============================================================
Important
============================================================

Do NOT use:

hammer activation-key content-override ...

Repository overrides apply only to Red Hat CDN Repository Sets.

For custom repositories the correct workflow is:

1. Create Product
2. Create Repository
3. Synchronize Repository
4. Create Content View
5. Add Repository to Content View
6. Publish Content View
7. Create Activation Key
8. Attach Subscription
9. Register Host

Repositories assigned to a Content View are automatically
available to hosts registered with the corresponding
Activation Key.

EOF

echo

###############################################################################
# Completed
###############################################################################

echo "============================================================"
echo " Foreman PXE Provisioning + Katello Bootstrap Completed"
echo "============================================================"

echo
echo "Installation Media          : OK"
echo "Operating Systems           : OK"
echo "PXE Templates               : OK"
echo "Subnets                     : OK"
echo "Host Groups                 : OK"
echo "Products                    : OK"
echo "Repositories                : OK"
echo "Repository Synchronization  : OK"
echo "Content Views               : OK"
echo "Activation Keys             : OK"
echo "Subscriptions               : OK"

echo
echo "Bootstrap completed successfully."
echo

