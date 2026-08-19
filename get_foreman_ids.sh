#!/bin/bash

###############################################################################
# FOREMAN DYNAMIC ID LOOKUP
###############################################################################

FOREMAN_SERVER="https://cent-07-01.vgs.com"
FOREMAN_USER="admin"
FOREMAN_PASS="zqs977dXzqfEvTML"

###############################################################################
# FUNCTIONS
###############################################################################

header() {
    echo
    echo "============================================================"
    echo "        $1"
    echo "============================================================"
}

ok() {
    echo "[OK] $1"
}

error() {
    echo "[ERROR] $1"
}

separator() {
    echo
    echo "------------------------------------------------------------"
    echo "$1"
    echo "------------------------------------------------------------"
}

###############################################################################
# HOSTGROUP NAMES
###############################################################################

declare -A RAID_HOSTGROUP_NAMES
declare -A SINGLE_HOSTGROUP_NAMES

RAID_HOSTGROUP_NAMES["1"]="CentOSLinux7-RAID"
RAID_HOSTGROUP_NAMES["2"]="RockyLinux8.10-RAID"
RAID_HOSTGROUP_NAMES["3"]="RockyLinux9.2-RAID"
RAID_HOSTGROUP_NAMES["4"]="RockyLinux9.8-RAID"

SINGLE_HOSTGROUP_NAMES["1"]="CentOSLinux7-SingleDisk"
SINGLE_HOSTGROUP_NAMES["2"]="RockyLinux8.10-SingleDisk"
SINGLE_HOSTGROUP_NAMES["3"]="RockyLinux9.2-SingleDisk"
SINGLE_HOSTGROUP_NAMES["4"]="RockyLinux9.8-SingleDisk"

###############################################################################
# ARRAYS
###############################################################################

declare -A RAID_HOSTGROUP_IDS
declare -A SINGLE_HOSTGROUP_IDS

declare -A OS_NAMES
declare -A OS_IDS

declare -A MEDIUM_NAMES
declare -A MEDIUM_IDS

###############################################################################
# CHECK FOREMAN CONNECTION
###############################################################################

header "FOREMAN DYNAMIC ID LOOKUP"

if ! hammer \
    --server "$FOREMAN_SERVER" \
    --username "$FOREMAN_USER" \
    --password "$FOREMAN_PASS" \
    organization list >/dev/null 2>&1
then
    error "Unable to connect to Foreman"
    exit 1
fi

ok "Foreman connection successful"

###############################################################################
# LOOK UP HOSTGROUP IDS
###############################################################################

header "LOOKING UP HOSTGROUP IDS"

for IDX in 1 2 3 4
do

    RAID_HG="${RAID_HOSTGROUP_NAMES[$IDX]}"

    separator "Checking RAID Hostgroup : ${RAID_HG}"

    RAID_ID=$(
        hammer \
            --server "$FOREMAN_SERVER" \
            --username "$FOREMAN_USER" \
            --password "$FOREMAN_PASS" \
            hostgroup list |
        awk -F'|' -v hg="$RAID_HG" '
        {
            id=$1
            name=$2

            gsub(/^ +| +$/, "", id)
            gsub(/^ +| +$/, "", name)

            if (name == hg)
                print id
        }'
    )

    if [ -z "$RAID_ID" ]; then
        error "RAID Hostgroup not found: ${RAID_HG}"
        exit 1
    fi

    RAID_HOSTGROUP_IDS[$IDX]="$RAID_ID"

    ok "Hostgroup ID : ${RAID_ID}"


    SINGLE_HG="${SINGLE_HOSTGROUP_NAMES[$IDX]}"

    separator "Checking Single Disk Hostgroup : ${SINGLE_HG}"

    SINGLE_ID=$(
        hammer \
            --server "$FOREMAN_SERVER" \
            --username "$FOREMAN_USER" \
            --password "$FOREMAN_PASS" \
            hostgroup list |
        awk -F'|' -v hg="$SINGLE_HG" '
        {
            id=$1
            name=$2

            gsub(/^ +| +$/, "", id)
            gsub(/^ +| +$/, "", name)

            if (name == hg)
                print id
        }'
    )

    if [ -z "$SINGLE_ID" ]; then
        error "Single Disk Hostgroup not found: ${SINGLE_HG}"
        exit 1
    fi

    SINGLE_HOSTGROUP_IDS[$IDX]="$SINGLE_ID"

    ok "Hostgroup ID : ${SINGLE_ID}"

done

###############################################################################
# LOOK UP OPERATING SYSTEM AND MEDIUM IDS
###############################################################################

header "LOOKING UP OPERATING SYSTEM AND MEDIUM IDS"

for IDX in 1 2 3 4
do

    HG="${RAID_HOSTGROUP_NAMES[$IDX]}"

    separator "Checking Hostgroup : ${HG}"

    INFO=$(
        hammer \
            --server "$FOREMAN_SERVER" \
            --username "$FOREMAN_USER" \
            --password "$FOREMAN_PASS" \
            hostgroup info \
            --name "$HG"
    )

    OS_NAME=$(
        echo "$INFO" |
        awk -F': *' '
        /^[[:space:]]*Operating System:/ {
            sub(/^[[:space:]]*Operating System:[[:space:]]*/, "")
            print
            exit
        }'
    )

    MEDIUM_NAME=$(
        echo "$INFO" |
        awk -F': *' '
        /^[[:space:]]*Medium:/ {
            sub(/^[[:space:]]*Medium:[[:space:]]*/, "")
            print
            exit
        }'
    )

    echo "OS     : ${OS_NAME}"
    echo "Medium : ${MEDIUM_NAME}"
    echo

    if [ -z "$OS_NAME" ]; then
        error "Operating System is empty for Hostgroup: ${HG}"
        echo
        echo "Hostgroup information:"
        echo "$INFO"
        exit 1
    fi

    if [ -z "$MEDIUM_NAME" ]; then
        error "Medium is empty for Hostgroup: ${HG}"
        echo
        echo "Hostgroup information:"
        echo "$INFO"
        exit 1
    fi

    OS_NAMES[$IDX]="$OS_NAME"
    MEDIUM_NAMES[$IDX]="$MEDIUM_NAME"

    OS_ID=$(
        hammer \
            --server "$FOREMAN_SERVER" \
            --username "$FOREMAN_USER" \
            --password "$FOREMAN_PASS" \
            os list |
        awk -F'|' -v os="$OS_NAME" '
        {
            id=$1
            name=$2

            gsub(/^ +| +$/, "", id)
            gsub(/^ +| +$/, "", name)

            if (name == os)
                print id
        }'
    )

    if [ -z "$OS_ID" ]; then
        error "Operating System ID not found: ${OS_NAME}"
        exit 1
    fi

    OS_IDS[$IDX]="$OS_ID"

    MEDIUM_ID=$(
        hammer \
            --server "$FOREMAN_SERVER" \
            --username "$FOREMAN_USER" \
            --password "$FOREMAN_PASS" \
            medium list |
        awk -F'|' -v medium="$MEDIUM_NAME" '
        {
            id=$1
            name=$2

            gsub(/^ +| +$/, "", id)
            gsub(/^ +| +$/, "", name)

            if (name == medium)
                print id
        }'
    )

    if [ -z "$MEDIUM_ID" ]; then
        error "Medium ID not found: ${MEDIUM_NAME}"
        exit 1
    fi

    MEDIUM_IDS[$IDX]="$MEDIUM_ID"

    ok "OS ID     : ${OS_ID}"
    ok "Medium ID : ${MEDIUM_ID}"

done

###############################################################################
# FINAL SUMMARY
###############################################################################

header "FINAL LOOKUP SUMMARY"

for IDX in 1 2 3 4
do

    echo
    echo "Hostgroup Selection : ${IDX}"

    echo "  RAID Hostgroup"
    echo "    Name : ${RAID_HOSTGROUP_NAMES[$IDX]}"
    echo "    ID   : ${RAID_HOSTGROUP_IDS[$IDX]}"

    echo "  Single Disk Hostgroup"
    echo "    Name : ${SINGLE_HOSTGROUP_NAMES[$IDX]}"
    echo "    ID   : ${SINGLE_HOSTGROUP_IDS[$IDX]}"

    echo "  Operating System"
    echo "    Name : ${OS_NAMES[$IDX]}"
    echo "    ID   : ${OS_IDS[$IDX]}"

    echo "  Installation Medium"
    echo "    Name : ${MEDIUM_NAMES[$IDX]}"
    echo "    ID   : ${MEDIUM_IDS[$IDX]}"

done

###############################################################################
# GENERATED ANSIBLE VARIABLES
#
# IMPORTANT:
# Everything below is PRINTED by Bash.
# It is NOT executed as Bash.
###############################################################################

header "GENERATED ANSIBLE VARIABLES"

cat <<EOF

###############################################################################
# FOREMAN / AWX HOST PROVISIONING VARIABLES
#
# Operating System Selection:
#
# 1 = CentOS Linux 7
# 2 = Rocky Linux 8.10
# 3 = Rocky Linux 9.2
# 4 = Rocky Linux 9.8
#
# Disk Layout:
#
# single = Single Disk Installation
# raid   = RAID1 Installation
#
###############################################################################

###############################################################################
# AWX SURVEY VARIABLES
###############################################################################

hostgroup: "{{ hostgroup | default('1', true) }}"

disk_layout: "{{ disk_layout | default('raid', true) }}"


###############################################################################
# FOREMAN SUBNET NAME
###############################################################################

subnet_name: >-
  {{
    {
      '1': 'vgs-subnet-centos',
      '2': 'vgs-subnet-rockyos',
      '3': 'vgs-subnet-rockyos',
      '4': 'vgs-subnet-rockyos'
    }[hostgroup | string]
  }}


###############################################################################
# FOREMAN SUBNET ID
###############################################################################

subnet_id: >-
  {{
    {
      '1': 1,
      '2': 2,
      '3': 2,
      '4': 2
    }[hostgroup | string]
  }}


###############################################################################
# FOREMAN HOSTGROUP ID
###############################################################################

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
    }[hostgroup | string ~ '-' ~ disk_layout | string]
  }}


###############################################################################
# FOREMAN OPERATING SYSTEM ID
###############################################################################

operatingsystem_id: >-
  {{
    {
      '1': ${OS_IDS[1]},
      '2': ${OS_IDS[2]},
      '3': ${OS_IDS[3]},
      '4': ${OS_IDS[4]}
    }[hostgroup | string]
  }}


###############################################################################
# FOREMAN INSTALLATION MEDIUM ID
###############################################################################

medium_id: >-
  {{
    {
      '1': ${MEDIUM_IDS[1]},
      '2': ${MEDIUM_IDS[2]},
      '3': ${MEDIUM_IDS[3]},
      '4': ${MEDIUM_IDS[4]}
    }[hostgroup | string]
  }}


###############################################################################
# PARTITION TABLE
###############################################################################

ptable_id: 126


###############################################################################
# ARCHITECTURE
###############################################################################

architecture_id: 1


###############################################################################
# KATELLO CONTENT VIEW
#
# Update these IDs according to your actual Content Views.
###############################################################################

content_view_id: >-
  {{
    {
      '1': 1,
      '2': 3,
      '3': 4,
      '4': 5
    }[hostgroup | string]
  }}


###############################################################################
# KATELLO LIFECYCLE ENVIRONMENT
###############################################################################

lifecycle_environment_id: 1


###############################################################################
# PXE SETTINGS
###############################################################################

pxe_loader: "Grub2 UEFI"

build: true


###############################################################################
# SELECTION SUMMARY
###############################################################################

foreman_selection_summary:

  selected_os: >-
    {{
      {
        '1': 'CentOS Linux 7',
        '2': 'Rocky Linux 8.10',
        '3': 'Rocky Linux 9.2',
        '4': 'Rocky Linux 9.8'
      }[hostgroup | string]
    }}

  selected_disk_layout: "{{ disk_layout }}"

  selected_subnet_name: "{{ subnet_name }}"

  selected_subnet_id: "{{ subnet_id }}"

  selected_hostgroup_id: "{{ hostgroup_id }}"

  selected_operatingsystem_id: "{{ operatingsystem_id }}"

  selected_medium_id: "{{ medium_id }}"

  selected_ptable_id: "{{ ptable_id }}"

  selected_architecture_id: "{{ architecture_id }}"

  selected_content_view_id: "{{ content_view_id }}"

  selected_lifecycle_environment_id: "{{ lifecycle_environment_id }}"

EOF


header "FOREMAN ID LOOKUP COMPLETED SUCCESSFULLY"
