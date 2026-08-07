#!/bin/bash
###############################################################################
# 03 - Foreman Hostgroup Bootstrap (Single Disk)
#
# Creates Hostgroups:
#
#   CentOSLinux 7 SingleDisk
#   RockyLinux 8.10 SingleDisk
#   RockyLinux 9.2 SingleDisk
#   RockyLinux 9.8 SingleDisk
#
# Features:
#   - Single disk partition layout
#   - PXEGrub2 UEFI SingleDisk Kickstart
#   - Installation Media mapping
#   - Operating System mapping
#   - Subnet mapping
#   - Root password
#
###############################################################################

set +e


###############################################################################
# Foreman Credentials
###############################################################################

FOREMAN_USER="${FOREMAN_USER:-admin}"
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-zqs977dXzqfEvTML}"

HAMMER="hammer --username ${FOREMAN_USER} --password ${FOREMAN_PASSWORD}"


###############################################################################
# Global Configuration
###############################################################################

ORGANIZATION="Default Organization"
LOCATION="Default Location"

TARGET_VERSION="${TARGET_VERSION:-9.8}"


###############################################################################
# Logging
###############################################################################

FAILED_STEPS=()


record_failure()
{
    FAILED_STEPS+=("$1")
}


header()
{
echo
echo "============================================================"
echo "$1"
echo "============================================================"
echo
}


ok()
{
echo "[OK] $1"
}


skip()
{
echo "[SKIP] $1"
}


error()
{
echo "[ERROR] $1"
}



###############################################################################
# Select Rocky Version
###############################################################################

case "$TARGET_VERSION" in

9.2)

    ROCKY_OS="RockyLinux 9.2"

    ROCKY_HOSTGROUP="RockyLinux 9.2 SingleDisk"

    ROCKY_MEDIA="Rocky 9.2 Remote"

    ROCKY_TEMPLATE="PXEGrub2 Rocky9.2 UEFI SingleDisk Kickstart"

    ROCKY_REPO="http://192.168.253.136/repo/rocky9.2/"

    ROCKY_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9-kickstart/Rocky9_2_Golden_SingleDisk_Minimal.cfg"

    ;;


9.8)

    ROCKY_OS="RockyLinux 9.8"

    ROCKY_HOSTGROUP="RockyLinux 9.8 SingleDisk"

    ROCKY_MEDIA="Rocky 9 Remote"

    ROCKY_TEMPLATE="PXEGrub2 Rocky9.8 UEFI SingleDisk Kickstart"

    ROCKY_REPO="http://192.168.253.136/repo/rocky9/"

    ROCKY_KS="http://192.168.253.136/repo/Foreman-Kickstarts/rocky9_8-kickstart/Rocky9_Golden_SingleDisk_Minimal.cfg"

    ;;


*)

    echo "Unsupported TARGET_VERSION: ${TARGET_VERSION}"
    exit 1

    ;;


esac

###############################################################################
# Create CentOS 7 Single Disk Hostgroup
###############################################################################

create_centos_hostgroup()
{

HOSTGROUP="CentOSLinux 7 SingleDisk"


echo
echo "Checking Hostgroup : ${HOSTGROUP}"


if $HAMMER hostgroup list --search "name=\"${HOSTGROUP}\"" | grep -q "${HOSTGROUP}"
then

    skip "${HOSTGROUP} already exists."

else

    echo "Creating ${HOSTGROUP}..."


    $HAMMER hostgroup create \
    --name "${HOSTGROUP}" \
    --organization "${ORGANIZATION}" \
    --location "${LOCATION}" \
    --operatingsystem "CentOSLinux 7" \
    --architecture x86_64 \
    --medium "CentOS 7 Remote" \
    --partition-table "Kickstart default" \
    --root-password "password" \
    --pxe-loader "Grub2 UEFI"



    if [ $? -eq 0 ]
    then

        ok "${HOSTGROUP} created."

    else

        error "Failed creating ${HOSTGROUP}"
        record_failure "${HOSTGROUP}"

    fi

fi

}



###############################################################################
# Create Rocky Linux 8 Single Disk Hostgroup
###############################################################################

create_rocky8_hostgroup()
{

HOSTGROUP="RockyLinux 8.10 SingleDisk"


echo
echo "Checking Hostgroup : ${HOSTGROUP}"


if $HAMMER hostgroup list --search "name=\"${HOSTGROUP}\"" | grep -q "${HOSTGROUP}"
then

    skip "${HOSTGROUP} already exists."

else

    echo "Creating ${HOSTGROUP}..."


    $HAMMER hostgroup create \
    --name "${HOSTGROUP}" \
    --organization "${ORGANIZATION}" \
    --location "${LOCATION}" \
    --operatingsystem "RockyLinux 8.10" \
    --architecture x86_64 \
    --medium "Rocky 8 Remote" \
    --partition-table "Kickstart default" \
    --root-password "password" \
    --pxe-loader "Grub2 UEFI"



    if [ $? -eq 0 ]
    then

        ok "${HOSTGROUP} created."

    else

        error "Failed creating ${HOSTGROUP}"
        record_failure "${HOSTGROUP}"

    fi

fi

}

###############################################################################
# Create Rocky Linux 9 Single Disk Hostgroup
###############################################################################

create_rocky9_hostgroup()
{

HOSTGROUP="${ROCKY_HOSTGROUP}"


echo
echo "Checking Hostgroup : ${HOSTGROUP}"


if $HAMMER hostgroup list --search "name=\"${HOSTGROUP}\"" | grep -q "${HOSTGROUP}"
then

    skip "${HOSTGROUP} already exists."

else

    echo "Creating ${HOSTGROUP}..."


    $HAMMER hostgroup create \
    --name "${HOSTGROUP}" \
    --organization "${ORGANIZATION}" \
    --location "${LOCATION}" \
    --operatingsystem "${ROCKY_OS}" \
    --architecture x86_64 \
    --medium "${ROCKY_MEDIA}" \
    --partition-table "Kickstart default" \
    --root-password "password" \
    --pxe-loader "Grub2 UEFI"



    if [ $? -eq 0 ]
    then

        ok "${HOSTGROUP} created."

    else

        error "Failed creating ${HOSTGROUP}"
        record_failure "${HOSTGROUP}"

    fi

fi


}



###############################################################################
# Assign Single Disk PXE Templates
###############################################################################

assign_template()
{

OS_NAME="$1"

TEMPLATE="$2"


echo
echo "Checking PXE Template:"
echo "${OS_NAME} -> ${TEMPLATE}"


EXISTING=$(
$HAMMER os info \
--title "${OS_NAME}" 2>/dev/null |
grep "${TEMPLATE}"
)


if echo "${EXISTING}" | grep -q "${TEMPLATE}"
then

    skip "Template already assigned."

else


    echo "Assigning template..."


    $HAMMER os add-provisioning-template \
    --title "${OS_NAME}" \
    --provisioning-template "${TEMPLATE}"



    if [ $? -eq 0 ]
    then

        ok "Template assigned."

    else

        error "Failed assigning template ${TEMPLATE}"
        record_failure "${OS_NAME} -> ${TEMPLATE}"

    fi


fi

}



###############################################################################
# Create Single Disk Hostgroups
###############################################################################

header "03 - Creating Single Disk Hostgroups"


create_centos_hostgroup


create_rocky8_hostgroup


create_rocky9_hostgroup

###############################################################################
# Configure Single Disk PXE Templates
###############################################################################

configure_pxe_defaults()
{

header "Setting Single Disk PXE Templates"


echo "Checking CentOSLinux 7..."

assign_template \
"CentOSLinux 7" \
"PXEGrub2 CentOS UEFI SingleDisk Kickstart"



echo
echo "Checking RockyLinux 8.10..."

assign_template \
"RockyLinux 8.10" \
"PXEGrub2 Rocky8 UEFI SingleDisk Kickstart"



echo
echo "Checking ${ROCKY_OS}..."

assign_template \
"${ROCKY_OS}" \
"${ROCKY_TEMPLATE}"


}



###############################################################################
# Verification
###############################################################################

verify_templates()
{

header "Single Disk Template Verification"


echo
echo "CentOSLinux 7"

$HAMMER os info \
--title "CentOSLinux 7" \
| grep -A20 Templates



echo
echo "RockyLinux 8.10"

$HAMMER os info \
--title "RockyLinux 8.10" \
| grep -A20 Templates



echo
echo "${ROCKY_OS}"

$HAMMER os info \
--title "${ROCKY_OS}" \
| grep -A20 Templates


}



###############################################################################
# Summary
###############################################################################

summary()
{

header "03 - Foreman Single Disk Hostgroup Summary"


echo
echo "Hostgroups"
echo "------------------------------------------------------------"

$HAMMER hostgroup list


echo
echo "Operating Systems"
echo "------------------------------------------------------------"

$HAMMER os list


echo
echo "PXE Templates"
echo "------------------------------------------------------------"

$HAMMER template list \
--search "PXEGrub2"



echo
echo "Selected Single Disk Configuration"
echo "------------------------------------------------------------"


echo "TARGET_VERSION       : ${TARGET_VERSION}"
echo "Operating System     : ${ROCKY_OS}"
echo "Hostgroup            : ${ROCKY_HOSTGROUP}"
echo "PXE Template         : ${ROCKY_TEMPLATE}"
echo "Installation Media   : ${ROCKY_MEDIA}"
echo "Repository           : ${ROCKY_REPO}"
echo "Kickstart            : ${ROCKY_KS}"

}



###############################################################################
# Main Execution
###############################################################################

configure_pxe_defaults


verify_templates


summary



header "03 - Foreman Hostgroup Bootstrap (Single Disk) Completed"



if [ ${#FAILED_STEPS[@]} -eq 0 ]
then

    echo "[OK] Single Disk Hostgroup Bootstrap completed successfully."

else

    echo "[WARN] Bootstrap completed with ${#FAILED_STEPS[@]} failure(s)."


    for ITEM in "${FAILED_STEPS[@]}"
    do
        echo "[ERROR] ${ITEM}"
    done

fi
