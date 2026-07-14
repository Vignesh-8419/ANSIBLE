#!/bin/bash

###############################################################################
# Foreman Dynamic ID Lookup
#
# Usage:
###############################################################################

FOREMAN_SERVER="https://cent-07-01.vgs.com"
FOREMAN_USER="admin"
FOREMAN_PASS="zqs977dXzqfEvTML"

HOSTGROUPS=(
    "VGS HOSTS CENTOS 7"
    "VGS HOSTS ROCKY 8"
    "VGS HOSTS ROCKY 9.2"
    "VGS HOSTS ROCKY 9.8"
)

###############################################################################
# Generate Ansible Mapping
###############################################################################

declare -A HOSTGROUP_MAP
HOSTGROUP_MAP["VGS HOSTS CENTOS 7"]=1
HOSTGROUP_MAP["VGS HOSTS ROCKY 8"]=2
HOSTGROUP_MAP["VGS HOSTS ROCKY 9.2"]=3
HOSTGROUP_MAP["VGS HOSTS ROCKY 9.8"]=4

declare -A HOSTGROUP_IDS
declare -A OS_IDS
declare -A MEDIUM_IDS

HOSTGROUPS=(
    "VGS HOSTS CENTOS 7"
    "VGS HOSTS ROCKY 8"
    "VGS HOSTS ROCKY 9.2"
    "VGS HOSTS ROCKY 9.8"
)

PTABLE_ID=""
ARCH_ID=""

for HG in "${HOSTGROUPS[@]}"; do

    INFO=$(hammer \
        --server "$FOREMAN_SERVER" \
        --username "$FOREMAN_USER" \
        --password "$FOREMAN_PASS" \
        hostgroup info --name "$HG" 2>/dev/null)

    IDX=${HOSTGROUP_MAP[$HG]}

    HOSTGROUP_IDS[$IDX]=$(echo "$INFO" | awk -F': *' '/^Id:/ {print $2}')
    OS_NAME=$(echo "$INFO" | awk -F': *' '/Operating System:/ {print $2}')
    MEDIUM_NAME=$(echo "$INFO" | awk -F': *' '/Medium:/ {print $2}')
    PTABLE_NAME=$(echo "$INFO" | awk -F': *' '/Partition Table:/ {print $2}')
    ARCH_NAME=$(echo "$INFO" | awk -F': *' '/Architecture:/ {print $2}')

    OS_IDS[$IDX]=$(
        hammer --server "$FOREMAN_SERVER" \
               --username "$FOREMAN_USER" \
               --password "$FOREMAN_PASS" \
               os list |
        awk -F'|' -v os="$OS_NAME" '
        {
            gsub(/^ +| +$/, "", $1)
            gsub(/^ +| +$/, "", $2)
            if ($2==os)
                print $1
        }'
    )

    MEDIUM_IDS[$IDX]=$(
        hammer --server "$FOREMAN_SERVER" \
               --username "$FOREMAN_USER" \
               --password "$FOREMAN_PASS" \
               medium list |
        awk -F'|' -v m="$MEDIUM_NAME" '
        {
            gsub(/^ +| +$/, "", $1)
            gsub(/^ +| +$/, "", $2)
            if ($2==m)
                print $1
        }'
    )

    if [[ -z "$PTABLE_ID" ]]; then
        PTABLE_ID=$(
            hammer --server "$FOREMAN_SERVER" \
                   --username "$FOREMAN_USER" \
                   --password "$FOREMAN_PASS" \
                   partition-table list |
            awk -F'|' -v p="$PTABLE_NAME" '
            {
                gsub(/^ +| +$/, "", $1)
                gsub(/^ +| +$/, "", $2)
                if ($2==p)
                    print $1
            }'
        )
    fi

    if [[ -z "$ARCH_ID" ]]; then
        ARCH_ID=$(
            hammer --server "$FOREMAN_SERVER" \
                   --username "$FOREMAN_USER" \
                   --password "$FOREMAN_PASS" \
                   architecture list |
            awk -F'|' -v a="$ARCH_NAME" '
            {
                gsub(/^ +| +$/, "", $1)
                gsub(/^ +| +$/, "", $2)
                if ($2==a)
                    print $1
            }'
        )
    fi

done

cat <<EOF

###########################################################################
# Host Group
# 1 = CentOS 7
# 2 = Rocky Linux 8
# 3 = Rocky Linux 9.2
# 4 = Rocky Linux 9.8
###########################################################################

hostgroup: "{{ hostgroup | default('1', true) }}"

subnet_id: >-
  {{
    {
      '1': 1,
      '2': 2,
      '3': 2,
      '4': 2
    }[hostgroup | string]
  }}

hostgroup_id: >-
  {{
    {
      '1': ${HOSTGROUP_IDS[1]},
      '2': ${HOSTGROUP_IDS[2]},
      '3': ${HOSTGROUP_IDS[3]},
      '4': ${HOSTGROUP_IDS[4]}
    }[hostgroup | string]
  }}

operatingsystem_id: >-
  {{
    {
      '1': ${OS_IDS[1]},
      '2': ${OS_IDS[2]},
      '3': ${OS_IDS[3]},
      '4': ${OS_IDS[4]}
    }[hostgroup | string]
  }}

medium_id: >-
  {{
    {
      '1': ${MEDIUM_IDS[1]},
      '2': ${MEDIUM_IDS[2]},
      '3': ${MEDIUM_IDS[3]},
      '4': ${MEDIUM_IDS[4]}
    }[hostgroup | string]
  }}

ptable_id: ${PTABLE_ID}

architecture_id: ${ARCH_ID}

EOF
