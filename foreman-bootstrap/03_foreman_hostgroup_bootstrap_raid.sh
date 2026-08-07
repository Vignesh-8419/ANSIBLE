#!/bin/bash
###############################################################################
# 03 - Foreman Hostgroup Bootstrap RAID
#
# Creates:
#   - CentOS7 RAID Hostgroup
#   - Rocky8 RAID Hostgroup
#   - Rocky9.2 RAID Hostgroup
#   - Rocky9.8 RAID Hostgroup
#
# RAID provisioning is controlled by Hostgroup
# OS objects remain single per release
###############################################################################

set +e


FAILED_STEPS=()


record_failure()
{
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
# Logging
###############################################################################

info()
{
    echo -e "${CYAN}$1${NC}"
}


ok()
{
    echo -e "${GREEN}[OK]${NC} $1"
}


skip()
{
    echo -e "${YELLOW}[SKIP]${NC} $1"
}


warn()
{
    echo -e "${YELLOW}[WARN]${NC} $1"
}


error()
{
    echo -e "${RED}[ERROR]${NC} $1"
}


header()
{
    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}



###############################################################################
# Variables
###############################################################################

FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"


HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"


header "03 - Foreman RAID Hostgroup Bootstrap"



###############################################################################
# Verify Required Objects
###############################################################################

verify_required()
{

TYPE="$1"
NAME="$2"


case "$TYPE" in


os)

    if $HAMMER os info \
        --title "$NAME" >/dev/null 2>&1
    then
        ok "Operating System exists : $NAME"
    else
        error "Operating System missing : $NAME"
        record_failure "$NAME OS missing"
    fi

;;


medium)

    if $HAMMER medium info \
        --name "$NAME" >/dev/null 2>&1
    then
        ok "Installation Media exists : $NAME"
    else
        error "Installation Media missing : $NAME"
        record_failure "$NAME Media missing"
    fi

;;


template)

    if $HAMMER template info \
        --name "$NAME" >/dev/null 2>&1
    then
        ok "PXE Template exists : $NAME"
    else
        error "PXE Template missing : $NAME"
        record_failure "$NAME Template missing"
    fi

;;


partition)

    if $HAMMER partition-table list | grep -q "$NAME"
    then
        ok "Partition Table exists : $NAME"
    else
        error "Partition Table missing : $NAME"
        record_failure "$NAME Partition missing"
    fi

;;


esac

}


###############################################################################
# Verify RAID Dependencies
###############################################################################

header "Checking RAID Dependencies"


verify_required os "CentOSLinux 7"
verify_required os "RockyLinux 8.10"
verify_required os "RockyLinux 9.2"
verify_required os "RockyLinux 9.8"


verify_required medium "CentOS 7 Remote"
verify_required medium "Rocky 8 Remote"
verify_required medium "Rocky 9.2 Remote"
verify_required medium "Rocky 9 Remote"


verify_required template \
"PXEGrub2 CentOS UEFI Static Kickstart"


verify_required template \
"PXEGrub2 RockyOS UEFI Static Kickstart"


verify_required template \
"PXEGrub2 Rocky9.2 UEFI Static Kickstart"


verify_required template \
"PXEGrub2 Rocky9.8 UEFI Static Kickstart"


echo

###############################################################################
# Hostgroup Create / Update Function
###############################################################################

create_hostgroup()
{

HG_NAME="$1"
PARENT="$2"
OS="$3"
MEDIA="$4"
PARTITION="$5"
PXE_TEMPLATE="$6"


header "Configuring Hostgroup : ${HG_NAME}"


###############################################################################
# Check Hostgroup
###############################################################################

info "Checking Hostgroup ${HG_NAME}"


if $HAMMER hostgroup info \
    --name "${HG_NAME}" >/dev/null 2>&1
then

    skip "Hostgroup already exists."

else

    info "Creating Hostgroup..."

    $HAMMER hostgroup create \
        --name "${HG_NAME}" \
        --parent "${PARENT}" \
        --organization "Default Organization" \
        --location "Default Location"


    if [ $? -eq 0 ]; then

        ok "Hostgroup created."

    else

        error "Hostgroup creation failed."
        record_failure "${HG_NAME}"

        return

    fi

fi



###############################################################################
# Assign Operating System
###############################################################################

info "Assigning Operating System : ${OS}"


$HAMMER hostgroup set-parameter \
    --hostgroup "${HG_NAME}" \
    --name "os_title" \
    --value "${OS}" \
    >/dev/null 2>&1 || true



###############################################################################
# Assign Installation Media
###############################################################################

info "Assigning Installation Media : ${MEDIA}"


$HAMMER hostgroup update \
    --name "${HG_NAME}" \
    --medium "${MEDIA}" \
    >/dev/null 2>&1


if [ $? -eq 0 ]; then

    ok "Installation Media assigned."

else

    warn "Installation Media assignment failed."

fi



###############################################################################
# Assign Partition Table
###############################################################################

info "Assigning Partition Table : ${PARTITION}"


$HAMMER hostgroup update \
    --name "${HG_NAME}" \
    --partition-table "${PARTITION}" \
    >/dev/null 2>&1


if [ $? -eq 0 ]; then

    ok "Partition Table assigned."

else

    warn "Partition Table assignment failed."

fi



###############################################################################
# Assign PXE Template
###############################################################################

info "Assigning PXE Template : ${PXE_TEMPLATE}"


$HAMMER os add-provisioning-template \
    --title "${OS}" \
    --provisioning-template "${PXE_TEMPLATE}" \
    >/dev/null 2>&1


if [ $? -eq 0 ]; then

    ok "PXE Template assigned."

else

    warn "PXE Template assignment failed."

fi



###############################################################################
# RAID Parameters
###############################################################################

info "Setting RAID parameters"


$HAMMER hostgroup set-parameter \
    --hostgroup "${HG_NAME}" \
    --name "storage_layout" \
    --value "raid1" \
    >/dev/null 2>&1 || true



$HAMMER hostgroup set-parameter \
    --hostgroup "${HG_NAME}" \
    --name "disk_mode" \
    --value "RAID" \
    >/dev/null 2>&1 || true



ok "${HG_NAME} configuration completed."


echo


}



###############################################################################
# Create RAID Hostgroups
###############################################################################

header "Creating RAID Hostgroups"



###############################################################################
# CentOS 7 RAID
###############################################################################

create_hostgroup \
"CentOS7-RAID" \
"" \
"CentOSLinux 7" \
"CentOS 7 Remote" \
"CentOS7 RAID" \
"PXEGrub2 CentOS UEFI Static Kickstart"



###############################################################################
# Rocky 8 RAID
###############################################################################

create_hostgroup \
"Rocky8-RAID" \
"" \
"RockyLinux 8.10" \
"Rocky 8 Remote" \
"Rocky8 RAID" \
"PXEGrub2 RockyOS UEFI Static Kickstart"



###############################################################################
# Rocky 9.2 RAID
###############################################################################

create_hostgroup \
"Rocky9.2-RAID" \
"" \
"RockyLinux 9.2" \
"Rocky 9.2 Remote" \
"Rocky9.2 RAID" \
"PXEGrub2 Rocky9.2 UEFI Static Kickstart"



###############################################################################
# Rocky 9.8 RAID
###############################################################################

create_hostgroup \
"Rocky9.8-RAID" \
"" \
"RockyLinux 9.8" \
"Rocky 9 Remote" \
"Rocky9.8 RAID" \
"PXEGrub2 Rocky9.8 UEFI Static Kickstart"



echo

###############################################################################
# Verification
###############################################################################

header "RAID Hostgroup Verification"


###############################################################################
# Hostgroup List
###############################################################################

info "Current Hostgroups"


$HAMMER hostgroup list


echo



###############################################################################
# Detailed Hostgroup Verification
###############################################################################

verify_hostgroup()
{

HG="$1"


echo
info "Checking Hostgroup : ${HG}"


$HAMMER hostgroup info \
    --name "${HG}"


echo

}



###############################################################################
# Verify RAID Hostgroups
###############################################################################

verify_hostgroup "CentOS7-RAID"

verify_hostgroup "Rocky8-RAID"

verify_hostgroup "Rocky9.2-RAID"

verify_hostgroup "Rocky9.8-RAID"



###############################################################################
# Verify RAID Parameters
###############################################################################

header "RAID Parameter Verification"



check_parameter()
{

HG="$1"
PARAM="$2"


info "Checking ${PARAM} on ${HG}"


$HAMMER hostgroup info \
    --name "${HG}" |
    grep "${PARAM}" || true


echo

}



check_parameter \
"CentOS7-RAID" \
"storage_layout"


check_parameter \
"Rocky8-RAID" \
"storage_layout"


check_parameter \
"Rocky9.2-RAID" \
"storage_layout"


check_parameter \
"Rocky9.8-RAID" \
"storage_layout"



###############################################################################
# PXE Template Mapping Verification
###############################################################################

header "RAID PXE Template Mapping"



verify_os_template()
{

OS="$1"
TEMPLATE="$2"


info "${OS}"


if $HAMMER os info \
    --title "${OS}" |
    grep -q "${TEMPLATE}"

then

    ok "${TEMPLATE} mapped."

else

    warn "${TEMPLATE} not mapped."

fi


echo

}



verify_os_template \
"CentOSLinux 7" \
"PXEGrub2 CentOS UEFI Static Kickstart"



verify_os_template \
"RockyLinux 8.10" \
"PXEGrub2 RockyOS UEFI Static Kickstart"



verify_os_template \
"RockyLinux 9.2" \
"PXEGrub2 Rocky9.2 UEFI Static Kickstart"



verify_os_template \
"RockyLinux 9.8" \
"PXEGrub2 Rocky9.8 UEFI Static Kickstart"




###############################################################################
# RAID Hostgroup Summary
###############################################################################

header "RAID Hostgroup Summary"


echo

printf "%-20s %-25s %-45s\n" \
"HOSTGROUP" \
"OPERATING SYSTEM" \
"PXE TEMPLATE"


echo "--------------------------------------------------------------------------------"



printf "%-20s %-25s %-45s\n" \
"CentOS7-RAID" \
"CentOSLinux 7" \
"PXEGrub2 CentOS UEFI Static Kickstart"



printf "%-20s %-25s %-45s\n" \
"Rocky8-RAID" \
"RockyLinux 8.10" \
"PXEGrub2 RockyOS UEFI Static Kickstart"



printf "%-20s %-25s %-45s\n" \
"Rocky9.2-RAID" \
"RockyLinux 9.2" \
"PXEGrub2 Rocky9.2 UEFI Static Kickstart"



printf "%-20s %-25s %-45s\n" \
"Rocky9.8-RAID" \
"RockyLinux 9.8" \
"PXEGrub2 Rocky9.8 UEFI Static Kickstart"



echo




###############################################################################
# Final Summary
###############################################################################

header "03 - RAID Hostgroup Bootstrap Completed"



if [ ${#FAILED_STEPS[@]} -eq 0 ]
then

    ok "RAID Hostgroup Bootstrap completed successfully."

else

    warn "Completed with ${#FAILED_STEPS[@]} failure(s)."


    for step in "${FAILED_STEPS[@]}"
    do

        error "${step}"

    done

fi



echo


ok "03_foreman_hostgroup_bootstrap_raid.sh finished."


exit 0
