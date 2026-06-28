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

HAMMER="hammer --username admin --password zqs977dXzqfEvTML"

###############################################################################
[root@cent-07-01 ~]# cat foreman-bootstrap.sh | head -30
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

HAMMER="hammer --username admin --password zqs977dXzqfEvTML"

###############################################################################
# 1. Create Installation Media
###############################################################################

echo "============================================================"
echo "[1/13] Creating Installation Media"
echo "============================================================"

###############################################################################
# CentOS 7 Installation Media
###############################################################################

echo "Checking CentOS 7 Installation Media..."

if $HAMMER medium info --name "CentOS 7 Remote" >/dev/null 2>&1; then
    echo "[SKIP] CentOS 7 Remote already exists."
else
    echo "Creating CentOS 7 Remote..."

    $HAMMER medium create \
        --name "CentOS 7 Remote" \
        --path "http://192.168.253.136/repo/centos/" \
        --os-family "Redhat"

    echo "[OK] CentOS 7 Remote created."
fi

echo

###############################################################################
# Rocky Linux 8 Installation Media
###############################################################################

echo "Checking Rocky Linux 8 Installation Media..."

if $HAMMER medium info --name "Rocky 8 Remote" >/dev/null 2>&1; then
    echo "[SKIP] Rocky 8 Remote already exists."
else
    echo "Creating Rocky 8 Remote..."

    $HAMMER medium create \
        --name "Rocky 8 Remote" \
        --path "http://192.168.253.136/repo/rocky8/" \
        --os-family "Redhat"

    echo "[OK] Rocky 8 Remote created."
fi

echo

###############################################################################
# Verification
###############################################################################

echo "============================================================"
echo "Installation Media"
echo "============================================================"

$HAMMER medium list

echo

###############################################################################
# 2. Create Operating Systems
###############################################################################

echo "============================================================"
echo "[2/13] Creating Operating Systems"
echo "============================================================"

###############################################################################
# CentOS Linux 7
###############################################################################

echo "Checking CentOS Linux 7..."

if $HAMMER os info --title "CentOSLinux 7" >/dev/null 2>&1; then
    echo "[SKIP] CentOSLinux 7 already exists."
else
    echo "Creating CentOSLinux 7..."

    $HAMMER os create \
        --name "CentOSLinux" \
        --major 7 \
        --family Redhat \
        --architectures x86_64 \
        --partition-tables "Kickstart default" \
        --media "CentOS 7 Remote"

    echo "[OK] CentOSLinux 7 created."
fi

echo

###############################################################################
# Rocky Linux 8.10
###############################################################################

echo "Checking Rocky Linux 8.10..."

if $HAMMER os info --title "RockyLinux 8.10" >/dev/null 2>&1; then
    echo "[SKIP] RockyLinux 8.10 already exists."
else
    echo "Creating RockyLinux 8.10..."

    $HAMMER os create \
        --name "RockyLinux" \
        --major 8 \
        --minor 10 \
        --family Redhat \
        --architectures x86_64 \
        --partition-tables "Kickstart default" \
        --media "Rocky 8 Remote"

    echo "[OK] RockyLinux 8.10 created."
fi

echo

###############################################################################
# Verification
###############################################################################

echo "============================================================"
echo "Operating Systems"
echo "============================================================"

$HAMMER os list

echo
echo "Part 2 Completed Successfully."
echo

###############################################################################
# 3. Create PXEGrub2 Provisioning Template - Rocky Linux 8.10
###############################################################################

echo "============================================================"
echo "[3/13] Creating Rocky Linux PXEGrub2 Template"
echo "============================================================"

###############################################################################
# Create Template File
###############################################################################

echo "Generating Rocky PXEGrub2 template..."

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

echo "[OK] Template file generated."
echo

###############################################################################
# Import Template
###############################################################################

echo "Checking PXE Template..."

if $HAMMER template info \
    --name "PXEGrub2 RockyOS UEFI Static Kickstart" >/dev/null 2>&1; then

    echo "[SKIP] Template already exists."

else

    echo "Importing template..."

    $HAMMER template create \
        --name "PXEGrub2 RockyOS UEFI Static Kickstart" \
        --type PXEGrub2 \
        --file /tmp/rocky-pxegrub2.erb

    echo "[OK] Template imported."

fi

echo

###############################################################################
# Assign Template to OS
###############################################################################

echo "Checking template assignment..."

if $HAMMER os info \
    --title "RockyLinux 8.10" | \
    grep -q "PXEGrub2 RockyOS UEFI Static Kickstart"; then

    echo "[SKIP] Template already assigned."

else

    echo "Assigning template..."

    $HAMMER os add-provisioning-template \
        --title "RockyLinux 8.10" \
        --provisioning-template "PXEGrub2 RockyOS UEFI Static Kickstart"

    echo "[OK] Template assigned."

fi

echo

###############################################################################
# Verification
###############################################################################

echo "============================================================"
echo "Rocky PXE Templates"
echo "============================================================"

$HAMMER template list | grep -i Rocky || true

echo
echo "Rocky PXE Template Completed."
echo

###############################################################################
# 4. Create PXEGrub2 Provisioning Template - CentOS Linux 7
###############################################################################

echo "============================================================"
echo "[4/13] Creating CentOS Linux PXEGrub2 Template"
echo "============================================================"

###############################################################################
# Create Template File
###############################################################################

echo "Generating CentOS PXEGrub2 template..."

cat >/tmp/centos-pxegrub2.erb <<'EOF'
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

echo "[OK] Template file generated."
echo

###############################################################################
# Import Template
###############################################################################

echo "Checking PXE Template..."

if $HAMMER template info \
    --name "PXEGrub2 CentOS UEFI Static Kickstart" >/dev/null 2>&1; then

    echo "[SKIP] Template already exists."

else

    echo "Importing template..."

    $HAMMER template create \
        --name "PXEGrub2 CentOS UEFI Static Kickstart" \
        --type PXEGrub2 \
        --file /tmp/centos-pxegrub2.erb

    echo "[OK] Template imported."

fi

echo

###############################################################################
# Assign Template to OS
###############################################################################

echo "Checking template assignment..."

if $HAMMER os info \
    --title "CentOSLinux 7" | \
    grep -q "PXEGrub2 CentOS UEFI Static Kickstart"; then

    echo "[SKIP] Template already assigned."

else

    echo "Assigning template..."

    $HAMMER os add-provisioning-template \
        --title "CentOSLinux 7" \
        --provisioning-template "PXEGrub2 CentOS UEFI Static Kickstart"

    echo "[OK] Template assigned."

fi

echo

###############################################################################
# Verification
###############################################################################

echo "============================================================"
echo "Current PXE Templates"
echo "============================================================"

$HAMMER template list | grep -i UEFI || true

echo
echo "CentOS PXE Template Completed."
echo

###############################################################################
# 5. Create Subnets
###############################################################################

echo "============================================================"
echo "[5/13] Creating Subnets"
echo "============================================================"

###############################################################################
# CentOS Subnet
###############################################################################

echo "Checking CentOS Subnet..."

if $HAMMER subnet info \
    --name "vgs-subnet-centos" >/dev/null 2>&1; then

    echo "[SKIP] vgs-subnet-centos already exists."

else

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

    echo "[OK] CentOS subnet created."

fi

echo

###############################################################################
# Rocky Linux Subnet
###############################################################################

echo "Checking Rocky Linux Subnet..."

if $HAMMER subnet info \
    --name "vgs-subnet-rockyos" >/dev/null 2>&1; then

    echo "[SKIP] vgs-subnet-rockyos already exists."

else

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

    echo "[OK] Rocky subnet created."

fi

echo

###############################################################################
# Verification
###############################################################################

echo "============================================================"
echo "Verifying Subnets"
echo "============================================================"

$HAMMER subnet list

echo
echo "Subnets Verified."
echo

###############################################################################
# 6. Create Host Groups
###############################################################################

echo "============================================================"
echo "[6/13] Creating Host Groups"
echo "============================================================"

###############################################################################
# CentOS 7 Host Group
###############################################################################

echo "Checking CentOS 7 Host Group..."

if $HAMMER hostgroup info \
    --organization "Default Organization" \
    --name "VGS HOSTS CENTOS 7" >/dev/null 2>&1; then

    echo "[SKIP] Host Group 'VGS HOSTS CENTOS 7' already exists."

else

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

    echo "[OK] CentOS Host Group created."

fi

echo

###############################################################################
# Rocky Linux 8 Host Group
###############################################################################

echo "Checking Rocky Linux 8 Host Group..."

if $HAMMER hostgroup info \
    --organization "Default Organization" \
    --name "VGS HOSTS ROCKY 8" >/dev/null 2>&1; then

    echo "[SKIP] Host Group 'VGS HOSTS ROCKY 8' already exists."

else

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

    echo "[OK] Rocky Host Group created."

fi

echo

###############################################################################
# Verification
###############################################################################

echo "============================================================"
echo "Host Groups"
echo "============================================================"

$HAMMER hostgroup list

echo
echo "Host Groups Verified."
echo

###############################################################################
# 7. Set Default PXE Templates
###############################################################################

echo "============================================================"
echo "[7/13] Setting Default PXE Templates"
echo "============================================================"

echo "Current Operating Systems"
$HAMMER os list

echo
echo "Current PXE Templates"
$HAMMER template list | grep -i UEFI || true

echo

###############################################################################
# Get IDs Dynamically
###############################################################################

CENTOS_OS_ID=$(
$HAMMER os list | \
awk -F'|' '/CentOSLinux 7/ {gsub(/ /,"",$1); print $1}'
)

ROCKY_OS_ID=$(
$HAMMER os list | \
awk -F'|' '/RockyLinux 8.10/ {gsub(/ /,"",$1); print $1}'
)

CENTOS_TEMPLATE_ID=$(
$HAMMER template list | \
awk -F'|' '/PXEGrub2 CentOS UEFI Static Kickstart/ {gsub(/ /,"",$1); print $1}'
)

ROCKY_TEMPLATE_ID=$(
$HAMMER template list | \
awk -F'|' '/PXEGrub2 RockyOS UEFI Static Kickstart/ {gsub(/ /,"",$1); print $1}'
)

###############################################################################
# Validation
###############################################################################

if [[ -z "$CENTOS_OS_ID" || -z "$CENTOS_TEMPLATE_ID" ]]; then
    echo "[ERROR] Unable to locate CentOS OS or Template."
    exit 1
fi

if [[ -z "$ROCKY_OS_ID" || -z "$ROCKY_TEMPLATE_ID" ]]; then
    echo "[ERROR] Unable to locate Rocky OS or Template."
    exit 1
fi

###############################################################################
# CentOS Default Template
###############################################################################

echo "Checking CentOS default template..."

if $HAMMER os info --id "$CENTOS_OS_ID" | \
grep -q "PXEGrub2 CentOS UEFI Static Kickstart"; then

    echo "[SKIP] CentOS default template already configured."

else

    echo "Setting CentOS default template..."

    $HAMMER os set-default-template \
        --id "$CENTOS_OS_ID" \
        --provisioning-template-id "$CENTOS_TEMPLATE_ID"

    echo "[OK] CentOS default template configured."

fi

echo

###############################################################################
# Rocky Default Template
###############################################################################

echo "Checking Rocky default template..."

if $HAMMER os info --id "$ROCKY_OS_ID" | \
grep -q "PXEGrub2 RockyOS UEFI Static Kickstart"; then

    echo "[SKIP] Rocky default template already configured."

else

    echo "Setting Rocky default template..."

    $HAMMER os set-default-template \
        --id "$ROCKY_OS_ID" \
        --provisioning-template-id "$ROCKY_TEMPLATE_ID"

    echo "[OK] Rocky default template configured."

fi

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
$HAMMER template list | grep -i UEFI || true

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
# 8. Create Katello Products
###############################################################################

echo "============================================================"
echo "[8/13] Creating Katello Products"
echo "============================================================"

###############################################################################
# Rocky Linux 8 Product
###############################################################################

echo "Checking Product : Rocky Linux 8"

if $HAMMER product info \
    --organization "Default Organization" \
    --name "Rocky Linux 8" >/dev/null 2>&1; then

    echo "[SKIP] Product 'Rocky Linux 8' already exists."

else

    echo "Creating Product : Rocky Linux 8"

    $HAMMER product create \
        --organization "Default Organization" \
        --name "Rocky Linux 8"

    echo "[OK] Product created."

fi

echo

###############################################################################
# CentOS 7 Product
###############################################################################

echo "Checking Product : CentOS 7"

if $HAMMER product info \
    --organization "Default Organization" \
    --name "CentOS 7" >/dev/null 2>&1; then

    echo "[SKIP] Product 'CentOS 7' already exists."

else

    echo "Creating Product : CentOS 7"

    $HAMMER product create \
        --organization "Default Organization" \
        --name "CentOS 7"

    echo "[OK] Product created."

fi

echo

###############################################################################
# Verification
###############################################################################

echo "============================================================"
echo "Products"
echo "============================================================"

$HAMMER product list \
    --organization "Default Organization"

echo

###############################################################################
# CentOS 7 Repositories
###############################################################################

echo "============================================================"
echo "Creating CentOS 7 Repositories"
echo "============================================================"

###############################################################################
# CentOS-07-BaseOS
###############################################################################

echo "Checking Repository : CentOS-07-BaseOS"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "CentOS 7" \
    --name "CentOS-07-BaseOS" >/dev/null 2>&1; then

    echo "[SKIP] Repository already exists."

else

    echo "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "CentOS 7" \
        --name "CentOS-07-BaseOS" \
        --content-type yum \
        --url "http://http-server-01/repo/centos/"

    echo "[OK] Repository created."

fi

echo

###############################################################################
# CentOS-07-Updates
###############################################################################

echo "Checking Repository : CentOS-07-Updates"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "CentOS 7" \
    --name "CentOS-07-Updates" >/dev/null 2>&1; then

    echo "[SKIP] Repository already exists."

else

    echo "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "CentOS 7" \
        --name "CentOS-07-Updates" \
        --content-type yum \
        --url "http://http-server-01/repo/installed_rhel7/"

    echo "[OK] Repository created."

fi

echo

###############################################################################
# Rocky Linux 8 Repositories
###############################################################################

echo "============================================================"
echo "Creating Rocky Linux 8 Repositories"
echo "============================================================"

###############################################################################
# Rocky-08-BaseOS
###############################################################################

echo "Checking Repository : Rocky-08-BaseOS"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "Rocky Linux 8" \
    --name "Rocky-08-BaseOS" >/dev/null 2>&1; then

    echo "[SKIP] Repository already exists."

else

    echo "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "Rocky Linux 8" \
        --name "Rocky-08-BaseOS" \
        --content-type yum \
        --url "http://192.168.253.136/repo/rocky8/BaseOS"

    echo "[OK] Repository created."

fi

echo

###############################################################################
# Rocky-08-AppStream
###############################################################################

echo "Checking Repository : Rocky-08-AppStream"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "Rocky Linux 8" \
    --name "Rocky-08-AppStream" >/dev/null 2>&1; then

    echo "[SKIP] Repository already exists."

else

    echo "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "Rocky Linux 8" \
        --name "Rocky-08-AppStream" \
        --content-type yum \
        --url "http://192.168.253.136/repo/rocky8/Appstream"

    echo "[OK] Repository created."

fi

echo

###############################################################################
# Rocky-08-RHEL-Installed
###############################################################################

echo "Checking Repository : Rocky-08-RHEL-Installed"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "Rocky Linux 8" \
    --name "Rocky-08-RHEL-Installed" >/dev/null 2>&1; then

    echo "[SKIP] Repository already exists."

else

    echo "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "Rocky Linux 8" \
        --name "Rocky-08-RHEL-Installed" \
        --content-type yum \
        --url "http://192.168.253.136/repo/installed_rhel8"

    echo "[OK] Repository created."

fi

echo

###############################################################################
# Verification
###############################################################################

echo "============================================================"
echo "Repositories"
echo "============================================================"

echo
echo "CentOS 7"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "CentOS 7"

echo
echo "Rocky Linux 8"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "Rocky Linux 8"

echo

###############################################################################
# 9. Synchronize Repositories
###############################################################################

echo "============================================================"
echo "[9/13] Synchronizing Repositories"
echo "============================================================"

sync_repository() {

    PRODUCT="$1"
    REPO="$2"

    echo
    echo "Checking Repository : $REPO"

    SYNC_STATUS=$(
        $HAMMER repository info \
            --organization "Default Organization" \
            --product "$PRODUCT" \
            --name "$REPO" 2>/dev/null | \
        awk -F': ' '/Sync State/ {print $2}'
    )

    case "$SYNC_STATUS" in

        running|Running)
            echo "[SKIP] Synchronization already running."
            ;;

        *)
            echo "Starting synchronization..."

            $HAMMER repository synchronize \
                --organization "Default Organization" \
                --product "$PRODUCT" \
                --name "$REPO"

            echo "[OK] Synchronization started."
            ;;

    esac

}

###############################################################################
# CentOS 7
###############################################################################

sync_repository "CentOS 7" "CentOS-07-BaseOS"
sync_repository "CentOS 7" "CentOS-07-Updates"

###############################################################################
# Rocky Linux 8
###############################################################################

sync_repository "Rocky Linux 8" "Rocky-08-BaseOS"
sync_repository "Rocky Linux 8" "Rocky-08-AppStream"
sync_repository "Rocky Linux 8" "Rocky-08-RHEL-Installed"

###############################################################################
# Verification
###############################################################################

echo
echo "============================================================"
echo "Repository Synchronization"
echo "============================================================"

echo
echo "CentOS 7"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "CentOS 7"

echo
echo "Rocky Linux 8"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "Rocky Linux 8"

echo

###############################################################################
# 10. Create Content Views
###############################################################################

echo "============================================================"
echo "[10/13] Creating Content Views"
echo "============================================================"

###############################################################################
# Function : Create Content View if Missing
###############################################################################

create_content_view() {

    CV_NAME="$1"

    echo "Checking Content View : $CV_NAME"

    if $HAMMER content-view info \
        --organization "Default Organization" \
        --name "$CV_NAME" >/dev/null 2>&1; then

        echo "[SKIP] Content View '$CV_NAME' already exists."

    else

        echo "Creating Content View..."

        $HAMMER content-view create \
            --organization "Default Organization" \
            --name "$CV_NAME"

        echo "[OK] Content View created."

    fi

    echo
}

###############################################################################
# Create Content Views
###############################################################################

create_content_view "CentOS7-CV"
create_content_view "Rocky8-CV"

###############################################################################
# 11. Verify Content Views and Activation Keys
###############################################################################

echo "============================================================"
echo "[11/13] Verifying Content Views and Activation Keys"
echo "============================================================"

###############################################################################
# Content Views
###############################################################################

echo
echo "Content Views"
echo "-------------"

$HAMMER content-view list || true

###############################################################################
# Activation Keys
###############################################################################

echo
echo "Activation Keys"
echo "---------------"

$HAMMER activation-key list \
    --organization "Default Organization" || true

###############################################################################
# CentOS7-CV
###############################################################################

echo
echo "============================================================"
echo "CentOS7-CV"
echo "============================================================"

$HAMMER content-view info \
    --organization "Default Organization" \
    --name "CentOS7-CV" || true

###############################################################################
# Rocky8-CV
###############################################################################

echo
echo "============================================================"
echo "Rocky8-CV"
echo "============================================================"

$HAMMER content-view info \
    --organization "Default Organization" \
    --name "Rocky8-CV" || true

###############################################################################
# CentOS Repositories
###############################################################################

echo
echo "============================================================"
echo "CentOS Repositories"
echo "============================================================"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "CentOS 7" || true

###############################################################################
# Rocky Repositories
###############################################################################

echo
echo "============================================================"
echo "Rocky Repositories"
echo "============================================================"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "Rocky Linux 8" || true

echo
echo "[OK] Verification completed."
echo

###############################################################################
# 12. Available Subscriptions & Activation Keys
###############################################################################

echo "============================================================"
echo "[12/13] Available Subscriptions"
echo "============================================================"

$HAMMER subscription list \
    --organization "Default Organization"

echo

###############################################################################
# Function : Attach Subscription
###############################################################################

attach_subscription() {

    KEY="$1"
    SUB_ID="$2"

    echo "Checking Activation Key : $KEY"

    if $HAMMER activation-key info \
        --organization "Default Organization" \
        --name "$KEY" | grep -q "Subscription ID.*$SUB_ID"; then

        echo "[SKIP] Subscription $SUB_ID already attached."

    else

        echo "Attaching Subscription $SUB_ID..."

        $HAMMER activation-key add-subscription \
            --organization "Default Organization" \
            --name "$KEY" \
            --subscription-id "$SUB_ID"

        echo "[OK] Subscription attached."

    fi

    echo
}

###############################################################################
# Attach Subscriptions
###############################################################################

attach_subscription "centos7-prod-key" 2
attach_subscription "rocky8-prod-key" 1

###############################################################################
# Verification
###############################################################################

echo "============================================================"
echo "Activation Keys"
echo "============================================================"

$HAMMER activation-key list \
    --organization "Default Organization"

echo

echo "============================================================"
echo "CentOS Activation Key"
echo "============================================================"

$HAMMER activation-key info \
    --organization "Default Organization" \
    --name "centos7-prod-key"

echo

echo "============================================================"
echo "Rocky Activation Key"
echo "============================================================"

$HAMMER activation-key info \
    --organization "Default Organization" \
    --name "rocky8-prod-key"

echo

###############################################################################
# 13. Host Registration Commands
###############################################################################

echo "============================================================"
echo "[13/13] Host Registration Commands"
echo "============================================================"

echo
echo "CentOS 7 Registration"
echo "------------------------------------------------------------"

cat <<EOF
subscription-manager register \
    --org="Default Organization" \
    --activationkey="centos7-prod-key"
EOF

echo
echo "Rocky Linux 8 Registration"
echo "------------------------------------------------------------"

cat <<EOF
subscription-manager register \
    --org="Default Organization" \
    --activationkey="rocky8-prod-key"
EOF

echo

###############################################################################
# Repository Assignment
###############################################################################

echo "============================================================"
echo "Repository Assignment"
echo "============================================================"

cat <<EOF

CentOS7-CV
-----------
  - CentOS-07-BaseOS
  - CentOS-07-Updates

Rocky8-CV
----------
  - Rocky-08-BaseOS
  - Rocky-08-AppStream
  - Rocky-08-RHEL-Installed

EOF

###############################################################################
# Final Verification
###############################################################################

echo
echo "============================================================"
echo "Final Verification"
echo "============================================================"

echo
echo "Installation Media"
$HAMMER medium list || true

echo
echo "Operating Systems"
$HAMMER os list || true

echo
echo "Host Groups"
$HAMMER hostgroup list || true

echo
echo "Products"
$HAMMER product list \
    --organization "Default Organization" || true

echo
echo "Repositories"
$HAMMER repository list \
    --organization "Default Organization" || true

echo
echo "Content Views"
$HAMMER content-view list || true

echo
echo "Activation Keys"
$HAMMER activation-key list \
    --organization "Default Organization" || true

###############################################################################
# Completed
###############################################################################

echo
echo "============================================================"
echo " Foreman PXE Provisioning + Katello Bootstrap Completed"
echo "============================================================"

echo
printf "%-35s %s\n" "Installation Media"          "[OK]"
printf "%-35s %s\n" "Operating Systems"           "[OK]"
printf "%-35s %s\n" "PXE Templates"               "[OK]"
printf "%-35s %s\n" "Subnets"                     "[OK]"
printf "%-35s %s\n" "Host Groups"                 "[OK]"
printf "%-35s %s\n" "Products"                    "[OK]"
printf "%-35s %s\n" "Repositories"                "[OK]"
printf "%-35s %s\n" "Repository Synchronization"  "[OK]"
printf "%-35s %s\n" "Content Views"               "[OK]"
printf "%-35s %s\n" "Activation Keys"             "[OK]"

echo
echo "Bootstrap completed successfully."
echo
