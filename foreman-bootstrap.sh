#!/bin/bash
###############################################################################
# Foreman PXE Provisioning + Katello Bootstrap
# CentOS 7 & Rocky Linux 8.10
###############################################################################

set +e

FAILED_STEPS=()

record_failure() {
    FAILED_STEPS+=("$1")
}

###############################################################################
# Colors
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

###############################################################################
# Logging Functions
###############################################################################

info() {
    echo -e "${CYAN}$1${NC}"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

header() {
    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

summary_ok() {
    printf "%-35s ${GREEN}[OK]${NC}\n" "$1"
}

header "Foreman PXE Provisioning + Katello Bootstrap"
echo

###############################################################################
# Variables
###############################################################################

FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"

HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"

###############################################################################

###############################################################################
# 1. Create Installation Media
###############################################################################

header "[1/12] Creating Installation Media"

###############################################################################
# CentOS 7 Installation Media
###############################################################################

info "Checking CentOS 7 Installation Media..."

if $HAMMER medium info --name "CentOS 7 Remote" >/dev/null 2>&1; then
    skip "CentOS 7 Remote already exists."
else
    info "Creating CentOS 7 Remote..."

    $HAMMER medium create \
        --name "CentOS 7 Remote" \
        --path "http://192.168.253.136/repo/centos/" \
        --os-family "Redhat"
    
    if [ $? -eq 0 ]; then
        ok "CentOS 7 Remote created."
    else
        error "Failed to create CentOS 7 Remote."
        record_failure "CentOS 7 Remote"
    fi
fi

echo

###############################################################################
# Rocky Linux 8 Installation Media
###############################################################################

info "Checking Rocky Linux 8 Installation Media..."

if $HAMMER medium info --name "Rocky 8 Remote" >/dev/null 2>&1; then
    skip "Rocky 8 Remote already exists."
else
    info "Creating Rocky 8 Remote..."

    $HAMMER medium create \
        --name "Rocky 8 Remote" \
        --path "http://192.168.253.136/repo/rocky8/" \
        --os-family "Redhat"
    
    if [ $? -eq 0 ]; then
        ok "Rocky 8 Remote created."
    else
        error "Failed to create Rocky 8 Remote."
        record_failure "Rocky 8 Remote"
    fi
fi

echo

###############################################################################
# Rocky Linux 9 Installation Media
###############################################################################

info "Checking Rocky Linux 9 Installation Media..."

if $HAMMER medium info --name "Rocky 9 Remote" >/dev/null 2>&1; then
    skip "Rocky 9 Remote already exists."
else
    info "Creating Rocky 9 Remote..."

    $HAMMER medium create \
        --name "Rocky 9 Remote" \
        --path "http://192.168.253.136/repo/rocky9/" \
        --os-family "Redhat"
    
    if [ $? -eq 0 ]; then
        ok "Rocky 9 Remote created."
    else
        error "Failed to create Rocky 9 Remote."
        record_failure "Rocky 9 Remote"
    fi
fi

###############################################################################
# Verification
###############################################################################

header "Installation Media"

$HAMMER medium list

echo

###############################################################################
# 2. Create Operating Systems
###############################################################################

header "[2/12] Creating Operating Systems"

###############################################################################
# CentOS Linux 7
###############################################################################

info "Checking CentOS Linux 7..."

if $HAMMER os info --title "CentOSLinux 7" >/dev/null 2>&1; then
    skip "CentOSLinux 7 already exists."
else
    info "Creating CentOSLinux 7..."

    $HAMMER os create \
        --name "CentOSLinux" \
        --major 7 \
        --family Redhat \
        --architectures x86_64 \
        --partition-tables "Kickstart default" \
        --media "CentOS 7 Remote"

    if [ $? -eq 0 ]; then
        ok "CentOSLinux 7 created."
    else
        error "CentOSLinux 7 creation failed."
        record_failure "CentOSLinux 7"
    fi
fi

echo

###############################################################################
# Rocky Linux 8.10
###############################################################################

info "Checking Rocky Linux 8.10..."

if $HAMMER os info --title "RockyLinux 8.10" >/dev/null 2>&1; then
    skip "RockyLinux 8.10 already exists."
else
    info "Creating RockyLinux 8.10..."

    $HAMMER os create \
        --name "RockyLinux" \
        --major 8 \
        --minor 10 \
        --family Redhat \
        --architectures x86_64 \
        --partition-tables "Kickstart default" \
        --media "Rocky 8 Remote"

    if [ $? -eq 0 ]; then
        ok "RockyLinux 8.10 created."
    else
        error "RockyLinux 8.10 creation failed."
        record_failure "RockyLinux 8.10"
    fi
fi

echo

###############################################################################
# Rocky Linux 9
###############################################################################

info "Checking Rocky Linux 9..."

if $HAMMER os info --title "RockyLinux 9.6" >/dev/null 2>&1; then
    skip "RockyLinux 9.6 already exists."
else
    info "Creating RockyLinux 9.6..."

    $HAMMER os create \
        --name "RockyLinux" \
        --major 9 \
        --minor 6 \
        --family Redhat \
        --architectures x86_64 \
        --partition-tables "Kickstart default" \
        --media "Rocky 9 Remote"

    if [ $? -eq 0 ]; then
        ok "RockyLinux 9.6 created."
    else
        error "RockyLinux 9.6 creation failed."
        record_failure "RockyLinux 9.6"
    fi
fi

###############################################################################
# Verification
###############################################################################

header "Operating Systems"

$HAMMER os list

echo
ok "Part 2 Completed Successfully."
echo

###############################################################################
# 3. Create PXEGrub2 Provisioning Template - Rocky Linux 8.10
###############################################################################

header "[3/12] Creating Rocky Linux PXE Template"

###############################################################################
# Create Template File
###############################################################################

info "Generating Rocky PXEGrub2 template..."

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

ok "Template file generated."
echo

cat > /tmp/rocky-9-pxegrub2.erb <<'EOF'
<%#
name: PXEGrub2 Rocky9 UEFI Static Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>
set default=0
set timeout=5

menuentry 'Install RockyOS via Kickstart' {

    linuxefi /rocky9/vmlinuz \
inst.stage2=http://192.168.253.136/repo/rocky9/ \
inst.ks=http://192.168.253.136/repo/rocky9/kickstart/rockyos.cfg \
inst.text \
inst.default_fstype=ext4 \
inst.ks.device=bootif \
BOOTIF=01-${net_default_mac} \
hostname=<%= @host.name %>

    initrdefi /rocky9/initrd.img

}
EOF

ok "Template file generated."
echo


###############################################################################
# Import Template
###############################################################################

info "Checking PXE Template..."

if $HAMMER template info \
    --name "PXEGrub2 RockyOS UEFI Static Kickstart" >/dev/null 2>&1; then

    skip "Template already exists."

else

    info "Importing template..."

    $HAMMER template create \
        --name "PXEGrub2 RockyOS UEFI Static Kickstart" \
        --type PXEGrub2 \
        --file /tmp/rocky-pxegrub2.erb
    
    if [ $? -eq 0 ]; then
        ok "Template imported."
    else
        error "Template import failed."
        record_failure "PXEGrub2 RockyOS UEFI Static Kickstart"
    fi

fi

echo

###############################################################################
# Import Rocky Linux 9 PXE Template
###############################################################################

info "Checking Rocky 9 PXE Template..."

if $HAMMER template info \
    --name "PXEGrub2 Rocky9 UEFI Static Kickstart" >/dev/null 2>&1; then

    skip "Rocky 9 Template already exists."

else

    info "Importing Rocky 9 template..."

    $HAMMER template create \
        --name "PXEGrub2 Rocky9 UEFI Static Kickstart" \
        --type PXEGrub2 \
        --file /tmp/rocky-9-pxegrub2.erb

    if [ $? -eq 0 ]; then
        ok "Template imported."
    else
        error "Template import failed."
        record_failure "PXEGrub2 Rocky9 UEFI Static Kickstart"
    fi

fi

echo

###############################################################################
# Assign Template to OS
###############################################################################

info "Checking template assignment..."

if $HAMMER os info \
    --title "RockyLinux 8.10" | \
    grep -q "PXEGrub2 RockyOS UEFI Static Kickstart"; then

    skip "Template already assigned."

else

    info "Assigning template..."

    $HAMMER os add-provisioning-template \
        --title "RockyLinux 8.10" \
        --provisioning-template "PXEGrub2 RockyOS UEFI Static Kickstart"
    
    if [ $? -eq 0 ]; then
        ok "Template assigned."
    else
        error "Template assignment failed."
        record_failure "RockyLinux 8 Template Assignment"
    fi

fi

echo

###############################################################################
# Assign Rocky Linux 9 Template
###############################################################################

info "Checking Rocky Linux 9 template assignment..."

if $HAMMER os info \
    --title "RockyLinux 9.6" | \
    grep -q "PXEGrub2 Rocky9 UEFI Static Kickstart"; then

    skip "Rocky 9 template already assigned."

else

    info "Assigning Rocky 9 template..."

    $HAMMER os add-provisioning-template \
        --title "RockyLinux 9.6" \
        --provisioning-template "PXEGrub2 Rocky9 UEFI Static Kickstart"

    if [ $? -eq 0 ]; then
        ok "Template assigned."
    else
        error "Template assignment failed."
        record_failure "RockyLinux 9.6 Template Assignment"
    fi

fi

echo

###############################################################################
# Verification
###############################################################################

header "Rocky PXE Templates"

$HAMMER template list | grep -i Rocky || true

echo
ok "Rocky PXE Template Completed."
echo

###############################################################################
# 4. Create PXEGrub2 Provisioning Template - CentOS Linux 7
###############################################################################

header "[4/12] Creating CentOS Linux PXE Template"

###############################################################################
# Create Template File
###############################################################################

info "Generating CentOS PXEGrub2 template..."

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

ok "Template file generated."
echo

###############################################################################
# Import Template
###############################################################################

info "Checking PXE Template..."

if $HAMMER template info \
    --name "PXEGrub2 CentOS UEFI Static Kickstart" >/dev/null 2>&1; then

    skip "Template already exists."

else

    info "Importing template..."

    $HAMMER template create \
        --name "PXEGrub2 CentOS UEFI Static Kickstart" \
        --type PXEGrub2 \
        --file /tmp/centos-pxegrub2.erb

    if [ $? -eq 0 ]; then
        ok "Template imported."
    else
        error "Template import failed."
        record_failure "PXEGrub2 CentOS UEFI Static Kickstart"
    fi

fi

echo

###############################################################################
# Assign Template to OS
###############################################################################

info "Checking template assignment..."

if $HAMMER os info \
    --title "CentOSLinux 7" | \
    grep -q "PXEGrub2 CentOS UEFI Static Kickstart"; then

    skip "Template already assigned."

else

    info "Assigning template..."

    $HAMMER os add-provisioning-template \
        --title "CentOSLinux 7" \
        --provisioning-template "PXEGrub2 CentOS UEFI Static Kickstart"

    if [ $? -eq 0 ]; then
        ok "Template assigned."
    else
        error "Template assignment failed."
        record_failure "CentOSLinux 7 Template Assignment"
    fi

fi

echo

###############################################################################
# Verification
###############################################################################

header "Current PXE Templates"

$HAMMER template list | grep -i UEFI || true

echo
ok "CentOS PXE Template Completed."
echo

###############################################################################
# 5. Create Subnets
###############################################################################

header "[5/12] Creating Subnets"

###############################################################################
# CentOS Subnet
###############################################################################

info "Checking CentOS Subnet..."

if $HAMMER subnet info \
    --name "vgs-subnet-centos" >/dev/null 2>&1; then

    skip "vgs-subnet-centos already exists."

else

    info "Creating CentOS Subnet..."

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

    if [ $? -eq 0 ]; then
        ok "CentOS subnet created."
    else
        error "CentOS subnet creation failed."
        record_failure "vgs-subnet-centos"
    fi


fi

echo

###############################################################################
# Rocky Linux Subnet
###############################################################################

info "Checking Rocky Linux Subnet..."

if $HAMMER subnet info \
    --name "vgs-subnet-rockyos" >/dev/null 2>&1; then

    skip "vgs-subnet-rockyos already exists."

else

    info "Creating Rocky Linux Subnet..."

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

    if [ $? -eq 0 ]; then
        ok "RockyOS subnet created."
    else
        error "RockyOS subnet creation failed."
        record_failure "vgs-subnet-rockyos"
    fi


fi

echo

###############################################################################
# Verification
###############################################################################

header "Verifying Subnets"


$HAMMER subnet list

echo
ok "Subnets Verified."
echo

header "[6/12] Creating Host Groups"

###############################################################################
# CentOS 7 Host Group
###############################################################################

info "Checking CentOS 7 Host Group..."

if $HAMMER hostgroup info \
    --organization "Default Organization" \
    --name "VGS HOSTS CENTOS 7" >/dev/null 2>&1; then

    skip "Host Group 'VGS HOSTS CENTOS 7' already exists."

else

    info "Creating CentOS 7 Host Group..."

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

    if [ $? -eq 0 ]; then
        ok "CentOS 7 Host Group created."
    else
        error "Host Group creation failed."
        record_failure "VGS HOSTS CentOS 7"
    fi

fi

echo

###############################################################################
# Rocky Linux 8 Host Group
###############################################################################

info "Checking Rocky Linux 8 Host Group..."

if $HAMMER hostgroup info \
    --organization "Default Organization" \
    --name "VGS HOSTS ROCKY 8" >/dev/null 2>&1; then

    skip "Host Group 'VGS HOSTS ROCKY 8' already exists."

else

    info "Creating Rocky Linux 8 Host Group..."

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

    if [ $? -eq 0 ]; then
        ok "Rocky Host Group created."
    else
        error "Host Group creation failed."
        record_failure "VGS HOSTS ROCKY 8"
    fi

fi

echo

###############################################################################
# Rocky Linux 9 Host Group
###############################################################################

info "Checking Rocky Linux 9 Host Group..."

if $HAMMER hostgroup info \
    --organization "Default Organization" \
    --name "VGS HOSTS ROCKY 9" >/dev/null 2>&1; then

    skip "Host Group 'VGS HOSTS ROCKY 9' already exists."

else

    info "Creating Rocky Linux 9 Host Group..."

    $HAMMER hostgroup create \
        --organization "Default Organization" \
        --name "VGS HOSTS ROCKY 9" \
        --architecture x86_64 \
        --operatingsystem "RockyLinux 9.6" \
        --medium "Rocky 9 Remote" \
        --partition-table "Kickstart default" \
        --pxe-loader "Grub2 UEFI" \
        --domain "vgs.com" \
        --subnet "vgs-subnet-rockyos" \
        --content-source "cent-07-01.vgs.com" \
        --content-view "Default Organization View" \
        --lifecycle-environment "Library"

    if [ $? -eq 0 ]; then
        ok "Rocky 9 Host Group created."
    else
        error "Host Group creation failed."
        record_failure "VGS HOSTS ROCKY 9"
    fi

fi

echo

###############################################################################
# Verification
###############################################################################

header "Host Groups"


$HAMMER hostgroup list

echo
ok "Host Groups Verified."
echo

header "[7/12] Setting Default PXE Templates"

info "Current Operating Systems"
$HAMMER os list

echo
info "Current PXE Templates"
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

ROCKY9_OS_ID=$(
$HAMMER os list | \
awk -F'|' '/RockyLinux 9.6/ {gsub(/ /,"",$1); print $1}'
)

ROCKY9_TEMPLATE_ID=$(
$HAMMER template list | \
awk -F'|' '/PXEGrub2 Rocky9 UEFI Static Kickstart/ {gsub(/ /,"",$1); print $1}'
)

###############################################################################
# Validation
###############################################################################

if [[ -z "$CENTOS_OS_ID" || -z "$CENTOS_TEMPLATE_ID" ]]; then
    error "Unable to locate CentOS OS or Template."
    record_failure "CentOS OS or Template Missing"
fi

if [[ -z "$ROCKY_OS_ID" || -z "$ROCKY_TEMPLATE_ID" ]]; then
    error "Unable to locate Rocky OS or Template."
    record_failure "Rocky OS or Template Missing"
fi

if [[ -z "$ROCKY9_OS_ID" || -z "$ROCKY9_TEMPLATE_ID" ]]; then
    error "Unable to locate Rocky 9 OS or Template."
    record_failure "Rocky 9 OS or Template Missing"
fi

###############################################################################
# CentOS Default Template
###############################################################################

info "Checking CentOS default template..."

if $HAMMER os info --id "$CENTOS_OS_ID" | \
    awk '/Default templates:/,/Architectures:/' | \
    grep -q "PXEGrub2 CentOS UEFI Static Kickstart"; then

    skip "CentOS default template already configured."

else

    info "Setting CentOS default template..."


    $HAMMER os set-default-template \
        --id "$CENTOS_OS_ID" \
        --provisioning-template-id "$CENTOS_TEMPLATE_ID" \
        >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        ok "CentOS default template configured."
    else
        error "Failed to configure CentOS default template."
        record_failure "CentOS Default Template"
    fi

fi

echo

###############################################################################
# Rocky Default Template
###############################################################################

info "Checking Rocky default template..."

if $HAMMER os info --id "$ROCKY_OS_ID" | \
    awk '/Default templates:/,/Architectures:/' | \
    grep -q "PXEGrub2 RockyOS UEFI Static Kickstart"; then

    skip "Rocky default template already configured."

else

    info "Setting Rocky default template..."

    $HAMMER os set-default-template \
        --id "$ROCKY_OS_ID" \
        --provisioning-template-id "$ROCKY_TEMPLATE_ID" \
        >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        ok "RockyOS default template configured."
    else
        error "Failed to configure RockyOS default template."
        record_failure "RockyOS Default Template"
    fi

fi

echo

###############################################################################
# Rocky Linux 9 Default Template
###############################################################################

info "Checking Rocky Linux 9 default template..."

if $HAMMER os info --id "$ROCKY9_OS_ID" | \
    awk '/Default templates:/,/Architectures:/' | \
    grep -q "PXEGrub2 Rocky9 UEFI Static Kickstart"; then

    skip "Rocky 9 default template already configured."

else

    info "Setting Rocky 9 default template..."

    $HAMMER os set-default-template \
        --id "$ROCKY9_OS_ID" \
        --provisioning-template-id "$ROCKY9_TEMPLATE_ID" \
        >/dev/null 2>&1
        
    if [ $? -eq 0 ]; then
        ok "Rocky 9 default template configured."
    else
        error "Failed to configure Rocky 9 default template."
        record_failure "Rocky 9 Default Template"
    fi

fi

echo

###############################################################################
# Verification
###############################################################################

header "PXE Provisioning Configuration Summary"


echo
info "Installation Media"
$HAMMER medium list

echo
info "Operating Systems"
$HAMMER os list

echo
info "PXE Templates"
$HAMMER template list | grep -i UEFI || true

echo
info "Subnets"
$HAMMER subnet list

echo
info "Host Groups"
$HAMMER hostgroup list

echo
header "PXE Provisioning Setup Completed Successfully"

echo


header "[8/12] Creating Katello Products"


###############################################################################
# Rocky Linux 8 Product
###############################################################################

info "Checking Product : Rocky Linux 8"

if $HAMMER product info \
    --organization "Default Organization" \
    --name "Rocky Linux 8" >/dev/null 2>&1; then

    skip "Product 'Rocky Linux 8' already exists."

else

    info "Creating Product : Rocky Linux 8"

    $HAMMER product create \
        --organization "Default Organization" \
        --name "Rocky Linux 8"
    
    if [ $? -eq 0 ]; then
        ok "Product created."
    else
        error "Product creation failed."
        record_failure "Rocky Linux 8 Product"
    fi

fi

echo

###############################################################################
# CentOS 7 Product
###############################################################################

info "Checking Product : CentOS 7"

if $HAMMER product info \
    --organization "Default Organization" \
    --name "CentOS 7" >/dev/null 2>&1; then

    skip "Product 'CentOS 7' already exists."

else

    info "Creating Product : CentOS 7"

    $HAMMER product create \
        --organization "Default Organization" \
        --name "CentOS 7"
    
    if [ $? -eq 0 ]; then
        ok "Product created."
    else
        error "Product creation failed."
        record_failure "CentOS 7 Product"
    fi

fi

echo

###############################################################################
# Rocky 9 Product
###############################################################################

info "Checking Product : Rocky Linux 9"

if $HAMMER product info \
    --organization "Default Organization" \
    --name "Rocky Linux 9" >/dev/null 2>&1; then

    skip "Product 'Rocky Linux 9' already exists."

else

    info "Creating Product : Rocky Linux 9"

        $HAMMER product create \
            --organization "Default Organization" \
            --name "Rocky Linux 9"
        
        if [ $? -eq 0 ]; then
            ok "Product created."
        else
            error "Product creation failed."
            record_failure "Rocky Linux 9 Product"
        fi
        

fi

echo

###############################################################################
# Verification
###############################################################################

header "Products"

$HAMMER product list \
    --organization "Default Organization"

echo

###############################################################################
# CentOS 7 Repositories
###############################################################################

header "Creating CentOS 7 Repositories"


###############################################################################
# CentOS-07-BaseOS
###############################################################################

info "Checking Repository : CentOS-07-BaseOS"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "CentOS 7" \
    --name "CentOS-07-BaseOS" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "CentOS 7" \
        --name "CentOS-07-BaseOS" \
        --content-type yum \
        --url "http://192.168.253.136/repo/centos/"

    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "$PRODUCT -> $REPO"
    fi

fi

echo

###############################################################################
# CentOS-07-Updates
###############################################################################

info "Checking Repository : CentOS-07-Updates"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "CentOS 7" \
    --name "CentOS-07-Updates" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "CentOS 7" \
        --name "CentOS-07-Updates" \
        --content-type yum \
        --url "http://192.168.253.136/repo/installed_rhel7/"

    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "$PRODUCT -> $REPO"
    fi

fi

echo

###############################################################################
# Rocky Linux 8 Repositories
###############################################################################


header "Creating Rocky Linux 8 Repositories"


###############################################################################
# Rocky-08-BaseOS
###############################################################################

info "Checking Repository : Rocky-08-BaseOS"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "Rocky Linux 8" \
    --name "Rocky-08-BaseOS" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "Rocky Linux 8" \
        --name "Rocky-08-BaseOS" \
        --content-type yum \
        --url "http://192.168.253.136/repo/rocky8/BaseOS"

    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "$PRODUCT -> $REPO"
    fi

fi

echo

###############################################################################
# Rocky-08-AppStream
###############################################################################

info "Checking Repository : Rocky-08-AppStream"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "Rocky Linux 8" \
    --name "Rocky-08-AppStream" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "Rocky Linux 8" \
        --name "Rocky-08-AppStream" \
        --content-type yum \
        --url "http://192.168.253.136/repo/rocky8/AppStream"
    
    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "Rocky Linux 8 -> Rocky-08-AppStream"
    fi

fi

echo

###############################################################################
# Rocky-08-RHEL-Installed
###############################################################################

info "Checking Repository : Rocky-08-RHEL-Installed"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "Rocky Linux 8" \
    --name "Rocky-08-RHEL-Installed" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "Rocky Linux 8" \
        --name "Rocky-08-RHEL-Installed" \
        --content-type yum \
        --url "http://192.168.253.136/repo/installed_rhel8"

    
    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "Rocky Linux 8 -> Rocky-08-RHEL-Installed"
    fi
fi

echo

###############################################################################
# Rocky-09-BaseOS
###############################################################################

info "Checking Repository : Rocky-09-BaseOS"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "Rocky Linux 9" \
    --name "Rocky-09-BaseOS" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."


    $HAMMER repository create \
        --organization "Default Organization" \
        --product "Rocky Linux 9" \
        --name "Rocky-09-BaseOS" \
        --content-type yum \
        --url "http://192.168.253.136/repo/rocky9/BaseOS"

    
    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "Rocky Linux 9 -> Rocky-09-BaseOS"
    fi
fi

echo

###############################################################################
# Rocky-09-AppStream
###############################################################################

info "Checking Repository : Rocky-09-AppStream"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "Rocky Linux 9" \
    --name "Rocky-09-AppStream" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "Rocky Linux 9" \
        --name "Rocky-09-AppStream" \
        --content-type yum \
        --url "http://192.168.253.136/repo/rocky9/AppStream"

    
    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "Rocky Linux 9 -> Rocky-09-AppStream"
    fi

fi

echo

###############################################################################
# Rocky-09-RHEL-Installed
###############################################################################

info "Checking Repository : Rocky-09-RHEL-Installed"

if $HAMMER repository info \
    --organization "Default Organization" \
    --product "Rocky Linux 9" \
    --name "Rocky-09-RHEL-Installed" >/dev/null 2>&1; then

    skip "Repository already exists."

else

    info "Creating Repository..."

    $HAMMER repository create \
        --organization "Default Organization" \
        --product "Rocky Linux 9" \
        --name "Rocky-09-RHEL-Installed" \
        --content-type yum \
        --url "http://192.168.253.136/repo/installed_rhel9"

    
    if [ $? -eq 0 ]; then
        ok "Repository created."
    else
        error "Repository creation failed."
        record_failure "Rocky Linux 9 -> Rocky-09-RHEL-Installed"
    fi
fi

echo

###############################################################################
# Verification
###############################################################################

header "Repositories"

echo
info "CentOS 7"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "CentOS 7"

echo
info "Rocky Linux 8"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "Rocky Linux 8"

echo

header "[9/12] Synchronizing Repositories"

sync_repository() {

    PRODUCT="$1"
    REPO="$2"

    echo
    info  "Checking Repository : $REPO"

    SYNC_STATUS=$(
        $HAMMER repository info \
            --organization "Default Organization" \
            --product "$PRODUCT" \
            --name "$REPO" 2>/dev/null | \
        awk -F': ' '/Sync State/ {print $2}'
    )

    case "$SYNC_STATUS" in

        running|Running)
            skip "Synchronization already running."
            ;;

        *)
            info "Starting synchronization..."

            $HAMMER repository synchronize \
                --organization "Default Organization" \
                --product "$PRODUCT" \
                --name "$REPO"
            
            if [ $? -eq 0 ]; then
                ok "Synchronization started."
            else
                error "Synchronization failed."
                record_failure "$PRODUCT -> $REPO"
            fi
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
# Rocky Linux 9
###############################################################################

sync_repository "Rocky Linux 9" "Rocky-09-BaseOS"
sync_repository "Rocky Linux 9" "Rocky-09-AppStream"
sync_repository "Rocky Linux 9" "Rocky-09-RHEL-Installed"

###############################################################################
# Verification
###############################################################################

echo
header "Repository Synchronization"

echo
info "CentOS 7"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "CentOS 7"

echo
info "Rocky Linux 8"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "Rocky Linux 8"

echo

header "[10/12] Creating Content Views"


###############################################################################
# Function : Create Content View if Missing
###############################################################################

create_content_view() {

    CV_NAME="$1"

    info "Checking Content View : $CV_NAME"

    if $HAMMER content-view info \
        --organization "Default Organization" \
        --name "$CV_NAME" >/dev/null 2>&1; then

        skip "Content View '$CV_NAME' already exists."

    else

        info "Creating Content View..."

        $HAMMER content-view create \
            --organization "Default Organization" \
            --name "$CV_NAME"
        
        if [ $? -eq 0 ]; then
            ok "Content View created."
        else
            error "Content View creation failed."
            record_failure "Content View : $CV_NAME"
        fi

    fi

    echo
}

###############################################################################
# Create Content Views
###############################################################################

create_content_view "CentOS7-CV"
create_content_view "Rocky8-CV"
create_content_view "Rocky9-CV"

###############################################################################
# Function : Add Repository to Content View
###############################################################################

add_repository_to_cv() {

    CV="$1"
    PRODUCT="$2"
    REPO="$3"

    info "Checking Repository '$REPO' in '$CV'..."

    if $HAMMER content-view info \
        --organization "Default Organization" \
        --name "$CV" | grep -q "$REPO"; then

        skip "Repository already assigned."

    else

        info "Adding Repository..."

        $HAMMER content-view add-repository \
            --organization "Default Organization" \
            --name "$CV" \
            --product "$PRODUCT" \
            --repository "$REPO"
        
        if [ $? -eq 0 ]; then
            ok "Repository added."
        else
            error "Failed to add repository."
            record_failure "$REPO -> $CV"
        fi

    fi

    echo
}

###############################################################################
# Add Repositories
###############################################################################

add_repository_to_cv "CentOS7-CV" "CentOS 7" "CentOS-07-BaseOS"
add_repository_to_cv "CentOS7-CV" "CentOS 7" "CentOS-07-Updates"

add_repository_to_cv "Rocky8-CV" "Rocky Linux 8" "Rocky-08-BaseOS"
add_repository_to_cv "Rocky8-CV" "Rocky Linux 8" "Rocky-08-AppStream"
add_repository_to_cv "Rocky8-CV" "Rocky Linux 8" "Rocky-08-RHEL-Installed"

add_repository_to_cv "Rocky9-CV" "Rocky Linux 9" "Rocky-09-BaseOS"
add_repository_to_cv "Rocky9-CV" "Rocky Linux 9" "Rocky-09-AppStream"
add_repository_to_cv "Rocky9-CV" "Rocky Linux 9" "Rocky-09-RHEL-Installed"

###############################################################################
# Function : Publish Content View
###############################################################################

publish_cv() {

    CV="$1"

    info "Checking Content View : $CV"

    if $HAMMER content-view info \
        --organization "Default Organization" \
        --name "$CV" | grep -q "Last published"; then

        skip "Content View already published."

    else

        $HAMMER content-view publish \
            --organization "Default Organization" \
            --name "$CV" \
            --description "Bootstrap Publish $(date '+%Y-%m-%d %H:%M:%S')"
        
        if [ $? -eq 0 ]; then
            ok "Content View published."
        else
            error "Content View publish failed."
            record_failure "Publish : $CV"
        fi

    fi

    echo
}

###############################################################################
# Publish Content Views
###############################################################################

publish_cv "CentOS7-CV"
publish_cv "Rocky8-CV"
publish_cv "Rocky9-CV"

###############################################################################
# Function : Create Activation Key
###############################################################################

create_activation_key() {

    KEY="$1"
    CV="$2"

    info "Checking Activation Key : $KEY"

    if $HAMMER activation-key info \
        --organization "Default Organization" \
        --name "$KEY" >/dev/null 2>&1; then

        skip "Activation Key already exists."

    else

        $HAMMER activation-key create \
            --organization "Default Organization" \
            --name "$KEY" \
            --lifecycle-environment "Library" \
            --content-view "$CV"
        
        if [ $? -eq 0 ]; then
            ok "Activation Key created."
        else
            error "Activation Key creation failed."
            record_failure "Activation Key : $KEY"
        fi

    fi

    echo
}

###############################################################################
# Create Activation Keys
###############################################################################

create_activation_key "centos7-prod-key" "CentOS7-CV"
create_activation_key "rocky8-prod-key" "Rocky8-CV"
create_activation_key "rocky9-prod-key" "Rocky9-CV"

###############################################################################
# Attach Subscriptions to Activation Keys
###############################################################################

header "Attaching Subscriptions"

CENTOS_SUB_ID=$(
$HAMMER subscription list \
  --organization "Default Organization" |
awk -F'|' '$3 ~ /CentOS 7/ {gsub(/ /,"",$1); print $1}'
)

ROCKY_SUB_ID=$(
$HAMMER subscription list \
  --organization "Default Organization" |
awk -F'|' '$3 ~ /Rocky Linux 8/ {gsub(/ /,"",$1); print $1}'
)

ROCKY9_SUB_ID=$(
$HAMMER subscription list \
  --organization "Default Organization" |
awk -F'|' '$3 ~ /Rocky Linux 9/ {gsub(/ /,"",$1); print $1}'
)

info "Attaching CentOS 7 subscription..."

OUTPUT=$(
$HAMMER activation-key add-subscription \
    --organization "Default Organization" \
    --name "centos7-prod-key" \
    --subscription-id "$CENTOS_SUB_ID" 2>&1
)

echo "$OUTPUT"

if echo "$OUTPUT" | grep -qi "already been registered"; then
    skip "CentOS 7 subscription already attached."
elif echo "$OUTPUT" | grep -qi "added"; then
    ok "CentOS 7 subscription attached."
elif [ $? -eq 0 ]; then
    ok "CentOS 7 subscription attached."
else
    error "Subscription attachment failed."
    record_failure "centos7-prod-key"
fi

echo

info "Attaching Rocky Linux 8 subscription..."

OUTPUT=$(
$HAMMER activation-key add-subscription \
    --organization "Default Organization" \
    --name "rocky8-prod-key" \
    --subscription-id "$ROCKY_SUB_ID" 2>&1
)

echo "$OUTPUT"

if echo "$OUTPUT" | grep -qi "already been registered"; then
    skip "Rocky Linux 8 subscription already attached."
elif echo "$OUTPUT" | grep -qi "added"; then
    ok "Rocky Linux 8 subscription attached."
elif [ $? -eq 0 ]; then
    ok "Rocky Linux 8 subscription attached."
else
    error "Subscription attachment failed."
    record_failure "rocky8-prod-key"
fi

###############################################################################
# Verification
###############################################################################

header "[11/12] Verification"

###############################################################################
# Content Views
###############################################################################

echo
header "Content Views"

$HAMMER content-view list || true

###############################################################################
# Activation Keys
###############################################################################

echo
header "Activation Keys"

$HAMMER activation-key list \
    --organization "Default Organization" || true

###############################################################################
# CentOS7-CV
###############################################################################

echo
header "CentOS7-CV"


$HAMMER content-view info \
    --organization "Default Organization" \
    --name "CentOS7-CV" || true

###############################################################################
# Rocky8-CV
###############################################################################

echo
header "Rocky8-CV"

$HAMMER content-view info \
    --organization "Default Organization" \
    --name "Rocky8-CV" || true

###############################################################################
# CentOS Repositories
###############################################################################

echo
header "CentOS Repositories"


$HAMMER repository list \
    --organization "Default Organization" \
    --product "CentOS 7" || true

###############################################################################
# Rocky 9 Repositories
###############################################################################

echo
header "Rocky9-CV"

$HAMMER content-view info \
    --organization "Default Organization" \
    --name "Rocky9-CV"

echo
header "Rocky Linux 9 Repositories"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "Rocky Linux 9" || true

###############################################################################
# Rocky Repositories
###############################################################################

echo
header "Rocky Repositories"

$HAMMER repository list \
    --organization "Default Organization" \
    --product "Rocky Linux 8" || true

echo
ok "Verification completed."
echo

header "[12/12] Registration Commands"

echo
info "CentOS 7"

echo "subscription-manager register \\"
echo "  --org=\"Default Organization\" \\"
echo "  --activationkey=\"centos7-prod-key\""

echo
info "Rocky Linux 8"

echo "subscription-manager register \\"
echo "  --org=\"Default Organization\" \\"
echo "  --activationkey=\"rocky8-prod-key\""

echo

echo
info "Rocky Linux 9"

echo "subscription-manager register \\"
echo "  --org=\"Default Organization\" \\"
echo "  --activationkey=\"rocky9-prod-key\""

echo
header "FAILED OPERATIONS"

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
    ok "No failures detected."
else
    for i in "${FAILED_STEPS[@]}"; do
        error "$i"
    done
fi

echo

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
    ok "Foreman PXE Provisioning + Katello Bootstrap Completed Successfully."
else
    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."
fi
