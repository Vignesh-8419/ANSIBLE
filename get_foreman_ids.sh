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
###############################################################################

declare -A HOSTGROUP_NAMES

HOSTGROUP_NAMES["1"]="CentOSLinux 7 RAID"
HOSTGROUP_NAMES["2"]="RockyLinux 8.10 RAID"
HOSTGROUP_NAMES["3"]="RockyLinux 9.2 RAID"
HOSTGROUP_NAMES["4"]="RockyLinux 9.8 RAID"



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
# Lookup Operating System and Medium
###############################################################################

for IDX in 1 2 3 4
do

    HG="${HOSTGROUP_NAMES[$IDX]}"

    echo
    echo "Checking Hostgroup : ${HG}"


    INFO=$(
    hammer \
    --server "$FOREMAN_SERVER" \
    --username "$FOREMAN_USER" \
    --password "$FOREMAN_PASS" \
    hostgroup info \
    --name "$HG" 2>/dev/null
    )


    OS_NAME=$(echo "$INFO" | awk -F': *' '/Operating System:/ {print $2}')

    MEDIUM_NAME=$(echo "$INFO" | awk -F': *' '/Medium:/ {print $2}')


    echo "OS     : ${OS_NAME}"

    echo "Medium : ${MEDIUM_NAME}"



    OS_IDS[$IDX]=$(
    hammer \
    --server "$FOREMAN_SERVER" \
    --username "$FOREMAN_USER" \
    --password "$FOREMAN_PASS" \
    os list |
    awk -F'|' -v os="$OS_NAME" '
    {
        gsub(/^ +| +$/, "", $1)
        gsub(/^ +| +$/, "", $2)

        if($2==os)
            print $1
    }'
    )



    MEDIUM_IDS[$IDX]=$(
    hammer \
    --server "$FOREMAN_SERVER" \
    --username "$FOREMAN_USER" \
    --password "$FOREMAN_PASS" \
    medium list |
    awk -F'|' -v m="$MEDIUM_NAME" '
    {
        gsub(/^ +| +$/, "", $1)
        gsub(/^ +| +$/, "", $2)

        if($2==m)
            print $1
    }'
    )


    echo "OS ID     : ${OS_IDS[$IDX]}"

    echo "Medium ID : ${MEDIUM_IDS[$IDX]}"

done



###############################################################################
# Generate Ansible Variables
###############################################################################

cat <<EOF


###########################################################################
# Host Group Selection
#
# 1 = CentOS Linux 7
# 2 = Rocky Linux 8.10
# 3 = Rocky Linux 9.2
# 4 = Rocky Linux 9.8
#
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
# 1-raid = CentOS Linux 7 RAID
# 2-raid = Rocky Linux 8.10 RAID
# 3-raid = Rocky Linux 9.2 RAID
# 4-raid = Rocky Linux 9.8 RAID
#
#
# SINGLE
#
# 1-single = CentOS Linux 7 SingleDisk
# 2-single = Rocky Linux 8.10 SingleDisk
# 3-single = Rocky Linux 9.2 SingleDisk
# 4-single = Rocky Linux 9.8 SingleDisk
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
