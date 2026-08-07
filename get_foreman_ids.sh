#!/bin/bash

###############################################################################
# Foreman Dynamic ID Lookup
#
# Supports:
#
# RAID:
#   CentOS Linux 7 RAID
#   Rocky Linux 8.10 RAID
#   Rocky Linux 9.2 RAID
#   Rocky Linux 9.8 RAID
#
# Single Disk:
#   CentOS Linux 7 SingleDisk
#   Rocky Linux 8.10 SingleDisk
#   Rocky Linux 9.2 SingleDisk
#   Rocky Linux 9.8 SingleDisk
#
###############################################################################


FOREMAN_SERVER="https://cent-07-01.vgs.com"

FOREMAN_USER="admin"

FOREMAN_PASS="zqs977dXzqfEvTML"



###############################################################################
# Hostgroup Mapping
###############################################################################

declare -A HOSTGROUP_MAP


HOSTGROUP_MAP["CentOSLinux 7 RAID"]="1"
HOSTGROUP_MAP["RockyLinux 8.10 RAID"]="2"
HOSTGROUP_MAP["RockyLinux 9.2 RAID"]="3"
HOSTGROUP_MAP["RockyLinux 9.8 RAID"]="4"


HOSTGROUP_MAP["CentOSLinux 7 SingleDisk"]="5"
HOSTGROUP_MAP["RockyLinux 8.10 SingleDisk"]="6"
HOSTGROUP_MAP["RockyLinux 9.2 SingleDisk"]="7"
HOSTGROUP_MAP["RockyLinux 9.8 SingleDisk"]="8"



declare -A HOSTGROUP_IDS

declare -A OS_IDS

declare -A MEDIUM_IDS

declare -A PTABLE_IDS



HOSTGROUPS=(

"CentOSLinux 7 RAID"

"RockyLinux 8.10 RAID"

"RockyLinux 9.2 RAID"

"RockyLinux 9.8 RAID"


"CentOSLinux 7 SingleDisk"

"RockyLinux 8.10 SingleDisk"

"RockyLinux 9.2 SingleDisk"

"RockyLinux 9.8 SingleDisk"

)



ARCH_ID=""



###############################################################################
# Lookup IDs
###############################################################################

for HG in "${HOSTGROUPS[@]}"
do


echo "Checking Hostgroup : ${HG}"


INFO=$(hammer \
    --server "$FOREMAN_SERVER" \
    --username "$FOREMAN_USER" \
    --password "$FOREMAN_PASS" \
    hostgroup info \
    --name "$HG" 2>/dev/null)



IDX=${HOSTGROUP_MAP[$HG]}



HOSTGROUP_IDS[$IDX]=$(echo "$INFO" |
awk -F': *' '/^Id:/ {print $2}')



OS_NAME=$(echo "$INFO" |
awk -F': *' '/Operating System:/ {print $2}')



MEDIUM_NAME=$(echo "$INFO" |
awk -F': *' '/Medium:/ {print $2}')



PTABLE_NAME=$(echo "$INFO" |
awk -F': *' '/Partition Table:/ {print $2}')



ARCH_NAME=$(echo "$INFO" |
awk -F': *' '/Architecture:/ {print $2}')



OS_IDS[$IDX]=$(
hammer \
--server "$FOREMAN_SERVER" \
--username "$FOREMAN_USER" \
--password "$FOREMAN_PASS" \
os list |
awk -F'|' -v os="$OS_NAME" '

{
gsub(/^ +| +$/,"",$1)
gsub(/^ +| +$/,"",$2)

if ($2==os)
print $1

}
'
)



MEDIUM_IDS[$IDX]=$(
hammer \
--server "$FOREMAN_SERVER" \
--username "$FOREMAN_USER" \
--password "$FOREMAN_PASS" \
medium list |
awk -F'|' -v m="$MEDIUM_NAME" '

{
gsub(/^ +| +$/,"",$1)
gsub(/^ +| +$/,"",$2)

if ($2==m)
print $1

}
'
)



PTABLE_IDS[$IDX]=$(
hammer \
--server "$FOREMAN_SERVER" \
--username "$FOREMAN_USER" \
--password "$FOREMAN_PASS" \
partition-table list |
awk -F'|' -v p="$PTABLE_NAME" '

{
gsub(/^ +| +$/,"",$1)
gsub(/^ +| +$/,"",$2)

if ($2==p)
print $1

}
'
)



if [[ -z "$ARCH_ID" ]]
then

ARCH_ID=$(
hammer \
--server "$FOREMAN_SERVER" \
--username "$FOREMAN_USER" \
--password "$FOREMAN_PASS" \
architecture list |
awk -F'|' -v a="$ARCH_NAME" '

{
gsub(/^ +| +$/,"",$1)
gsub(/^ +| +$/,"",$2)

if ($2==a)
print $1

}
'
)

fi


done



###############################################################################
# Generate Ansible Variables
###############################################################################

cat <<EOF


###############################################################################
# Host Group
#
# 1 = CentOS Linux 7 RAID
# 2 = Rocky Linux 8.10 RAID
# 3 = Rocky Linux 9.2 RAID
# 4 = Rocky Linux 9.8 RAID
#
# 5 = CentOS Linux 7 SingleDisk
# 6 = Rocky Linux 8.10 SingleDisk
# 7 = Rocky Linux 9.2 SingleDisk
# 8 = Rocky Linux 9.8 SingleDisk
#
###############################################################################

hostgroup: "{{ hostgroup | default('1', true) }}"



subnet_id: >-
  {{
    {
      '1': 1,
      '2': 2,
      '3': 2,
      '4': 2,

      '5': 1,
      '6': 2,
      '7': 2,
      '8': 2

    }[hostgroup | string]
  }}



hostgroup_id: >-
  {{
    {
      '1': ${HOSTGROUP_IDS[1]},
      '2': ${HOSTGROUP_IDS[2]},
      '3': ${HOSTGROUP_IDS[3]},
      '4': ${HOSTGROUP_IDS[4]},

      '5': ${HOSTGROUP_IDS[5]},
      '6': ${HOSTGROUP_IDS[6]},
      '7': ${HOSTGROUP_IDS[7]},
      '8': ${HOSTGROUP_IDS[8]}

    }[hostgroup | string]
  }}



operatingsystem_id: >-
  {{
    {
      '1': ${OS_IDS[1]},
      '2': ${OS_IDS[2]},
      '3': ${OS_IDS[3]},
      '4': ${OS_IDS[4]},

      '5': ${OS_IDS[5]},
      '6': ${OS_IDS[6]},
      '7': ${OS_IDS[7]},
      '8': ${OS_IDS[8]}

    }[hostgroup | string]
  }}



medium_id: >-
  {{
    {
      '1': ${MEDIUM_IDS[1]},
      '2': ${MEDIUM_IDS[2]},
      '3': ${MEDIUM_IDS[3]},
      '4': ${MEDIUM_IDS[4]},

      '5': ${MEDIUM_IDS[5]},
      '6': ${MEDIUM_IDS[6]},
      '7': ${MEDIUM_IDS[7]},
      '8': ${MEDIUM_IDS[8]}

    }[hostgroup | string]
  }}



ptable_id: >-
  {{
    {
      '1': ${PTABLE_IDS[1]},
      '2': ${PTABLE_IDS[2]},
      '3': ${PTABLE_IDS[3]},
      '4': ${PTABLE_IDS[4]},

      '5': ${PTABLE_IDS[5]},
      '6': ${PTABLE_IDS[6]},
      '7': ${PTABLE_IDS[7]},
      '8': ${PTABLE_IDS[8]}

    }[hostgroup | string]
  }}



architecture_id: ${ARCH_ID}



EOF
