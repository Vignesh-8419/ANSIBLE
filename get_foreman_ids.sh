#!/bin/bash

###############################################################################
# Foreman Dynamic ID Lookup
#
# Hostgroup:
#
# 1 = CentOS Linux 7
# 2 = Rocky Linux 8.10
# 3 = Rocky Linux 9.2
# 4 = Rocky Linux 9.8
#
# Disk Layout:
#
# raid
# single
#
###############################################################################

FOREMAN_SERVER="https://cent-07-01.vgs.com"
FOREMAN_USER="admin"
FOREMAN_PASS="zqs977dXzqfEvTML"


###############################################################################
# Hostgroup Names
#
# IMPORTANT:
# These names must exactly match Foreman Hostgroup names.
###############################################################################

declare -A HOSTGROUP_NAMES

HOSTGROUP_NAMES["1"]="CentOSLinux7-RAID"
HOSTGROUP_NAMES["2"]="RockyLinux8.10-RAID"
HOSTGROUP_NAMES["3"]="RockyLinux9.2-RAID"
HOSTGROUP_NAMES["4"]="RockyLinux9.8-RAID"


###############################################################################
# Hostgroup IDs
###############################################################################

declare -A RAID_HOSTGROUP_IDS
declare -A SINGLE_HOSTGROUP_IDS


# RAID

RAID_HOSTGROUP_IDS["1"]=5
RAID_HOSTGROUP_IDS["2"]=6
RAID_HOSTGROUP_IDS["3"]=8
RAID_HOSTGROUP_IDS["4"]=7


# Single Disk

SINGLE_HOSTGROUP_IDS["1"]=9
SINGLE_HOSTGROUP_IDS["2"]=10
SINGLE_HOSTGROUP_IDS["3"]=11
SINGLE_HOSTGROUP_IDS["4"]=12


###############################################################################
# Arrays
###############################################################################

declare -A OS_IDS
declare -A MEDIUM_IDS


###############################################################################
# Check Hammer Connectivity
###############################################################################

echo
echo "============================================================"
echo "        FOREMAN DYNAMIC ID LOOKUP"
echo "============================================================"
echo

if ! hammer \
    --server "$FOREMAN_SERVER" \
    --username "$FOREMAN_USER" \
    --password "$FOREMAN_PASS" \
    organization list >/dev/null 2>&1
then
    echo "[ERROR] Cannot connect to Foreman using Hammer"
    exit 1
fi

echo "[OK] Foreman connection successful"


###############################################################################
# Lookup Operating System and Medium
###############################################################################

for IDX in 1 2 3 4
do

    HG="${HOSTGROUP_NAMES[$IDX]}"

    echo
    echo "------------------------------------------------------------"
    echo "Checking Hostgroup : ${HG}"
    echo "------------------------------------------------------------"


    INFO=$(
        hammer \
        --server "$FOREMAN_SERVER" \
        --username "$FOREMAN_USER" \
        --password "$FOREMAN_PASS" \
        hostgroup info \
        --name "$HG" 2>&1
    )


    # Check whether hostgroup exists
    if echo "$INFO" | grep -qi "hostgroup not found"
    then
        echo "[ERROR] Hostgroup not found: ${HG}"
        exit 1
    fi


    # Check Hammer command failure
    if [ $? -ne 0 ]
    then
        echo "[ERROR] Unable to get information for Hostgroup: ${HG}"
        echo "$INFO"
        exit 1
    fi


    ###########################################################################
    # Extract Operating System
    ###########################################################################

    OS_NAME=$(
        echo "$INFO" |
        awk -F': *' '
            /^Operating System:/ {
                sub(/^[[:space:]]+/, "", $2)
                sub(/[[:space:]]+$/, "", $2)
                print $2
                exit
            }
        '
    )


    ###########################################################################
    # Extract Installation Medium
    ###########################################################################

    MEDIUM_NAME=$(
        echo "$INFO" |
        awk -F': *' '
            /^Medium:/ {
                sub(/^[[:space:]]+/, "", $2)
                sub(/[[:space:]]+$/, "", $2)
                print $2
                exit
            }
        '
    )


    echo "OS     : ${OS_NAME}"
    echo "Medium : ${MEDIUM_NAME}"


    ###########################################################################
    # Validate OS
    ###########################################################################

    if [ -z "$OS_NAME" ]
    then
        echo
        echo "[ERROR] Operating System is empty for Hostgroup: ${HG}"
        echo
        echo "Hostgroup information:"
        echo "$INFO"
        exit 1
    fi


    ###########################################################################
    # Validate Medium
    ###########################################################################

    if [ -z "$MEDIUM_NAME" ]
    then
        echo
        echo "[ERROR] Installation Medium is empty for Hostgroup: ${HG}"
        echo
        echo "Hostgroup information:"
        echo "$INFO"
        exit 1
    fi


    ###########################################################################
    # Resolve Operating System ID
    ###########################################################################

    OS_IDS[$IDX]=$(
        hammer \
        --server "$FOREMAN_SERVER" \
        --username "$FOREMAN_USER" \
        --password "$FOREMAN_PASS" \
        os list |
        awk -F'|' -v os="$OS_NAME" '
        {
            id=$1
            name=$2

            gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)

            if (name == os) {
                print id
                exit
            }
        }'
    )


    ###########################################################################
    # Resolve Medium ID
    ###########################################################################

    MEDIUM_IDS[$IDX]=$(
        hammer \
        --server "$FOREMAN_SERVER" \
        --username "$FOREMAN_USER" \
        --password "$FOREMAN_PASS" \
        medium list |
        awk -F'|' -v m="$MEDIUM_NAME" '
        {
            id=$1
            name=$2

            gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)

            if (name == m) {
                print id
                exit
            }
        }'
    )


    ###########################################################################
    # Validate IDs
    ###########################################################################

    if [ -z "${OS_IDS[$IDX]}" ]
    then
        echo
        echo "[ERROR] Could not resolve Operating System ID"
        echo "Hostgroup : ${HG}"
        echo "OS Name   : ${OS_NAME}"
        exit 1
    fi


    if [ -z "${MEDIUM_IDS[$IDX]}" ]
    then
        echo
        echo "[ERROR] Could not resolve Medium ID"
        echo "Hostgroup   : ${HG}"
        echo "Medium Name : ${MEDIUM_NAME}"
        exit 1
    fi


    echo "OS ID     : ${OS_IDS[$IDX]}"
    echo "Medium ID : ${MEDIUM_IDS[$IDX]}"

done


###############################################################################
# Generate Ansible Variables
###############################################################################

echo
echo "============================================================"
echo "        GENERATED ANSIBLE VARIABLES"
echo "============================================================"


cat <<EOF


###########################################################################
# Host Group Selection
#
# 1 = CentOS Linux 7
# 2 = Rocky Linux 8.10
# 3 = Rocky Linux 9.2
# 4 = Rocky Linux 9.8
#
# Disk Layout:
#
# raid   = RAID1 Installation
# single = Single Disk Installation
#
###########################################################################

hostgroup: "{{ hostgroup | default('1', true) }}"

disk_layout: "{{ disk_layout | default('raid', true) }}"


###########################################################################
# Subnet Mapping
###########################################################################

subnet_id: >-
  {{
    {
      '1': 1,
      '2': 2,
      '3': 2,
      '4': 2
    }[hostgroup | string]
  }}


###########################################################################
# Hostgroup Mapping
#
# RAID
#
# 1-raid = CentOSLinux7-RAID
# 2-raid = RockyLinux8.10-RAID
# 3-raid = RockyLinux9.2-RAID
# 4-raid = RockyLinux9.8-RAID
#
# SINGLE
#
# 1-single = CentOSLinux7-SingleDisk
# 2-single = RockyLinux8.10-SingleDisk
# 3-single = RockyLinux9.2-SingleDisk
# 4-single = RockyLinux9.8-SingleDisk
#
###########################################################################

hostgroup_id: >-
  {{
    {
      '1-raid': ${RAID_HOSTGROUP_IDS[1]},
      '2-raid': ${RAID_HOSTGROUP_IDS[2]},
      '3-raid': ${RAID_HOSTGROUP_IDS[3]},
      '4-raid': ${RAID_HOSTGROUP_IDS[4]},

      '1-single': ${SINGLE_HOSTGROUP_IDS[1]},
      '2-single': ${SINGLE_HOSTGROUP_IDS[2]},
      '3-single': ${SINGLE_HOSTGROUP_IDS[3]},
      '4-single': ${SINGLE_HOSTGROUP_IDS[4]}

    }[hostgroup ~ '-' ~ disk_layout]
  }}


###########################################################################
# Operating System Mapping
###########################################################################

operatingsystem_id: >-
  {{
    {
      '1': ${OS_IDS[1]},
      '2': ${OS_IDS[2]},
      '3': ${OS_IDS[3]},
      '4': ${OS_IDS[4]}
    }[hostgroup | string]
  }}


###########################################################################
# Installation Media Mapping
###########################################################################

medium_id: >-
  {{
    {
      '1': ${MEDIUM_IDS[1]},
      '2': ${MEDIUM_IDS[2]},
      '3': ${MEDIUM_IDS[3]},
      '4': ${MEDIUM_IDS[4]}
    }[hostgroup | string]
  }}


###########################################################################
# Partition Table
#
# Kickstart default
#
# RAID and Single Disk use same Foreman partition table
#
###########################################################################

ptable_id: 126


###########################################################################
# Architecture
###########################################################################

architecture_id: 1

EOF


echo
echo "============================================================"
echo "[OK] Foreman Dynamic ID Lookup Completed Successfully"
echo "============================================================"
