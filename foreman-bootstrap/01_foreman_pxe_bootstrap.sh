#!/bin/bash
###############################################################################
# 01 - Foreman PXE Bootstrap
# Installation Media, Operating Systems, PXE Templates & Subnets
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



header "01 - Foreman PXE Bootstrap"
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

header "[1/6] Creating Installation Media"

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

info "Checking Rocky Linux 9.2 Installation Media..."

if $HAMMER medium info --name "Rocky 9.2 Remote" >/dev/null 2>&1; then
    skip "Rocky 9.2 Remote already exists."
else
    info "Creating Rocky 9.2 Remote..."

    $HAMMER medium create \
        --name "Rocky 9.2 Remote" \
        --path "http://192.168.253.136/repo/rocky9.2/" \
        --os-family "Redhat"

    if [ $? -eq 0 ]; then
        ok "Rocky 9.2 Remote created."
    else
        error "Failed to create Rocky 9.2 Remote."
        record_failure "Rocky 9.2 Remote"
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

header "[2/6] Creating Operating Systems"

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

if $HAMMER os info --title "RockyLinux 9.8" >/dev/null 2>&1; then
    skip "RockyLinux 9.8 already exists."
else
    info "Creating RockyLinux 9.8..."

    $HAMMER os create \
        --name "RockyLinux" \
        --major 9 \
        --minor 8 \
        --family Redhat \
        --architectures x86_64 \
        --partition-tables "Kickstart default" \
        --media "Rocky 9 Remote"

    if [ $? -eq 0 ]; then
        ok "RockyLinux 9.8 created."
    else
        error "RockyLinux 9.8 creation failed."
        record_failure "RockyLinux 9.8"
    fi
fi



###############################################################################
# Rocky Linux 9.2
###############################################################################

info "Checking Rocky Linux 9.2..."

if $HAMMER os info --title "RockyLinux 9.2" >/dev/null 2>&1; then
    skip "RockyLinux 9.2 already exists."
else
    info "Creating RockyLinux 9.2..."

    $HAMMER os create \
        --name "RockyLinux" \
        --major 9 \
        --minor 2 \
        --family Redhat \
        --architectures x86_64 \
        --partition-tables "Kickstart default" \
        --media "Rocky 9.2 Remote"

    if [ $? -eq 0 ]; then
        ok "RockyLinux 9.2 created."
    else
        error "RockyLinux 9.2 creation failed."
        record_failure "RockyLinux 9.2"
    fi
fi

###############################################################################
# Verification
###############################################################################

header "Operating Systems"

$HAMMER os list

echo
ok "Operating Systems configured successfully."
echo


###############################################################################
# 3. Create PXEGrub2 Provisioning Template - Rocky Linux 8.10
###############################################################################

header "[3/6] Creating Rocky Linux PXE Template"

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

menuentry 'Install Rocky 8 via Kickstart' {

    linuxefi /rocky8/vmlinuz \
inst.stage2=http://192.168.253.136/repo/rocky8/ \
inst.ks=http://192.168.253.136/repo/rocky8/kickstart/rockyos.cfg \
inst.text \
inst.default_fstype=ext4 \
inst.ks.device=bootif \
BOOTIF=01-${net_default_mac} \
hostname=<%= @host.name %>

    initrdefi /rocky8/initrd.img

}
EOF

ok "Template file generated."
echo

cat > /tmp/rocky-9-pxegrub2.erb <<'EOF'
<%#
name: PXEGrub2 Rocky9.8 UEFI Static Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5

menuentry 'Install Rocky Linux 9.8 (UEFI)' {

    linuxefi /rocky9/vmlinuz \
    ip=dhcp \
    inst.repo=http://192.168.253.136/repo/rocky9/ \
    inst.ks=http://192.168.253.136/repo/rocky9/kickstart/rockyos.cfg \
    inst.text \
    hostname=<%= @host.name %>

    initrdefi /rocky9/initrd.img
}
EOF

ok "Template file generated."
echo


cat > /tmp/rocky92-pxegrub2.erb <<'EOF'
<%#
name: PXEGrub2 Rocky9.2 UEFI Static Kickstart
kind: PXEGrub2
oses:
- RockyLinux
%>

set default=0
set timeout=5

menuentry 'Install Rocky Linux 9.8 via Kickstart (UEFI)' {

    linuxefi /rocky92/vmlinuz \
    ip=dhcp \
    inst.repo=http://192.168.253.136/repo/rocky9.2/ \
    inst.ks=http://192.168.253.136/repo/rocky9.2/kickstart/rocky92.cfg \
    inst.text \
    hostname=<%= @host.name %>

    initrdefi /rocky92/initrd.img
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

info "Checking Rocky 9.8 PXE Template..."

if $HAMMER template info \
    --name "PXEGrub2 Rocky9.8 UEFI Static Kickstart" >/dev/null 2>&1; then

    skip "Rocky 9.8 Template already exists."

else

    info "Importing Rocky 9.8 template..."

    $HAMMER template create \
        --name "PXEGrub2 Rocky9.8 UEFI Static Kickstart" \
        --type PXEGrub2 \
        --file /tmp/rocky-9-pxegrub2.erb

    if [ $? -eq 0 ]; then
        ok "Template imported."
    else
        error "Template import failed."
        record_failure "PXEGrub2 Rocky9.8 UEFI Static Kickstart"
    fi

fi

echo


###############################################################################
# Import Rocky Linux 9.2 PXE Template
###############################################################################

info "Checking Rocky 9.2 PXE Template..."

if $HAMMER template info \
    --name "PXEGrub2 Rocky9.2 UEFI Static Kickstart" >/dev/null 2>&1; then

    skip "Rocky 9.2 Template already exists."

else

    info "Importing Rocky 9.2 template..."

    $HAMMER template create \
        --name "PXEGrub2 Rocky9.2 UEFI Static Kickstart" \
        --type PXEGrub2 \
        --file /tmp/rocky92-pxegrub2.erb

    if [ $? -eq 0 ]; then
        ok "Template imported."
    else
        error "Template import failed."
        record_failure "PXEGrub2 Rocky9.2 UEFI Static Kickstart"
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

info "Checking Rocky Linux 9.8 template assignment..."

if $HAMMER os info \
    --title "RockyLinux 9.8" | \
    grep -q "PXEGrub2 Rocky9.8 UEFI Static Kickstart"; then

    skip "Rocky 9.8 template already assigned."

else

    info "Assigning Rocky 9.8 template..."

    $HAMMER os add-provisioning-template \
        --title "RockyLinux 9.8" \
        --provisioning-template "PXEGrub2 Rocky9.8 UEFI Static Kickstart"

    if [ $? -eq 0 ]; then
        ok "Template assigned."
    else
        error "Template assignment failed."
        record_failure "RockyLinux 9.8 Template Assignment"
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

header "[4/6] Creating CentOS Linux PXE Template"

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

menuentry 'Install CentOS 7 via Kickstart' {

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
# Assign Rocky Linux 9.2 Template
###############################################################################

info "Checking Rocky Linux 9.2 template assignment..."

if $HAMMER os info \
    --title "RockyLinux 9.2" | \
    grep -q "PXEGrub2 Rocky9.2 UEFI Static Kickstart"; then

    skip "Rocky 9.2 template already assigned."

else

    info "Assigning Rocky 9.2 template..."

    $HAMMER os add-provisioning-template \
        --title "RockyLinux 9.2" \
        --provisioning-template "PXEGrub2 Rocky9.2 UEFI Static Kickstart"

    if [ $? -eq 0 ]; then
        ok "Rocky 9.2 template assigned."
    else
        error "Template assignment failed."
        record_failure "RockyLinux 9.2 Template Assignment"
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

header "[5/6] Creating Subnets"

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

header "[6/6] Setting Default PXE Templates"

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
awk -F'|' '/RockyLinux 9.8/ {gsub(/ /,"",$1); print $1}'
)

ROCKY9_TEMPLATE_ID=$(
$HAMMER template list | \
awk -F'|' '/PXEGrub2 Rocky9.8 UEFI Static Kickstart/ {gsub(/ /,"",$1); print $1}'
)

ROCKY92_OS_ID=$(
$HAMMER os list | \
awk -F'|' '/RockyLinux 9.2/ {gsub(/ /,"",$1); print $1}'
)

ROCKY92_TEMPLATE_ID=$(
$HAMMER template list | \
awk -F'|' '/PXEGrub2 Rocky9.2 UEFI Static Kickstart/ {gsub(/ /,"",$1); print $1}'
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

if [[ -z "$ROCKY92_OS_ID" || -z "$ROCKY92_TEMPLATE_ID" ]]; then
    error "Unable to locate Rocky 9.2 OS or Template."
    record_failure "Rocky 9.2 OS or Template Missing"
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
    grep -q "PXEGrub2 Rocky9.8 UEFI Static Kickstart"; then

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

echo

echo

###############################################################################
# Rocky Linux 9.2 Default Template
###############################################################################

info "Checking Rocky Linux 9.2 default template..."

if $HAMMER os info --id "$ROCKY92_OS_ID" | \
    awk '/Default templates:/,/Architectures:/' | \
    grep -q "PXEGrub2 Rocky9.2 UEFI Static Kickstart"; then

    skip "Rocky 9.2 default template already configured."

else

    info "Setting Rocky 9.2 default template..."

    $HAMMER os set-default-template \
        --id "$ROCKY92_OS_ID" \
        --provisioning-template-id "$ROCKY92_TEMPLATE_ID" \
        >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        ok "Rocky 9.2 default template configured."
    else
        error "Failed to configure Rocky 9.2 default template."
        record_failure "Rocky 9.2 Default Template"
    fi

fi

echo


###############################################################################
# Verify Default Templates
###############################################################################

header "Default PXE Templates"

$HAMMER os info --title "CentOSLinux 7" | \
    awk '/Default templates:/,/Architectures:/'

echo

$HAMMER os info --title "RockyLinux 8.10" | \
    awk '/Default templates:/,/Architectures:/'

echo

$HAMMER os info --title "RockyLinux 9.8" | \
    awk '/Default templates:/,/Architectures:/'

echo

$HAMMER os info --title "RockyLinux 9.2" | \
    awk '/Default templates:/,/Architectures:/'

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
header "01 - Foreman PXE Bootstrap Completed"

if [ ${#FAILED_STEPS[@]} -eq 0 ]; then
    ok "Foreman PXE Bootstrap completed successfully."
else
    warn "Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."

    for step in "${FAILED_STEPS[@]}"; do
        error "$step"
    done
fi

echo
