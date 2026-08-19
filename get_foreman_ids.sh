#!/bin/bash

###############################################################################
# FOREMAN DYNAMIC ID LOOKUP
#
# Dynamically looks up:
#
# - RAID Hostgroup ID
# - SingleDisk Hostgroup ID
# - Operating System ID
# - Installation Medium ID
#
# Generates separate YAML blocks for:
#
# 1. CentOS Linux 7
# 2. Rocky Linux 8.10
# 3. Rocky Linux 9.2
# 4. Rocky Linux 9.8
#
###############################################################################

set -o pipefail

###############################################################################
# FOREMAN CONNECTION
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
    echo "$1"
    echo "============================================================"
}

section() {
    echo
    echo "------------------------------------------------------------"
    echo "$1"
    echo "------------------------------------------------------------"
}

ok() {
    echo "[OK] $1"
}

error() {
    echo "[ERROR] $1"
}

###############################################################################
# CHECK FOREMAN CONNECTION
###############################################################################

header "        FOREMAN DYNAMIC ID LOOKUP"

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
# HOSTGROUP DEFINITIONS
###############################################################################

declare -A RAID_HOSTGROUP
declare -A SINGLE_HOSTGROUP
declare -A OS_LABEL
declare -A SUBNET_NAME
declare -A CONTENT_VIEW_ID

RAID_HOSTGROUP["1"]="CentOSLinux7-RAID"
SINGLE_HOSTGROUP["1"]="CentOSLinux7-SingleDisk"
OS_LABEL["1"]="CentOS Linux 7"
SUBNET_NAME["1"]="vgs-subnet-centos"
CONTENT_VIEW_ID["1"]="1"

RAID_HOSTGROUP["2"]="RockyLinux8.10-RAID"
SINGLE_HOSTGROUP["2"]="RockyLinux8.10-SingleDisk"
OS_LABEL["2"]="Rocky Linux 8.10"
SUBNET_NAME["2"]="vgs-subnet-rockyos"
CONTENT_VIEW_ID["2"]="3"

RAID_HOSTGROUP["3"]="RockyLinux9.2-RAID"
SINGLE_HOSTGROUP["3"]="RockyLinux9.2-SingleDisk"
OS_LABEL["3"]="Rocky Linux 9.2"
SUBNET_NAME["3"]="vgs-subnet-rockyos"
CONTENT_VIEW_ID["3"]="4"

RAID_HOSTGROUP["4"]="RockyLinux9.8-RAID"
SINGLE_HOSTGROUP["4"]="RockyLinux9.8-SingleDisk"
OS_LABEL["4"]="Rocky Linux 9.8"
SUBNET_NAME["4"]="vgs-subnet-rockyos"
CONTENT_VIEW_ID["4"]="5"

###############################################################################
# RESULT ARRAYS
###############################################################################

declare -A RAID_HOSTGROUP_ID
declare -A SINGLE_HOSTGROUP_ID
declare -A OPERATINGSYSTEM_ID
declare -A MEDIUM_ID
declare -A OS_NAME
declare -A MEDIUM_NAME

###############################################################################
# GET HOSTGROUP ID
###############################################################################

get_hostgroup_id() {

    local HG_NAME="$1"

    hammer \
        --server "$FOREMAN_SERVER" \
        --username "$FOREMAN_USER" \
        --password "$FOREMAN_PASS" \
        hostgroup list |
    awk -F'|' -v hg="$HG_NAME" '
    NR > 2 {
        for (i=1; i<=NF; i++) {
            gsub(/^ +| +$/, "", $i)
        }

        if ($2 == hg) {
            print $1
            exit
        }
    }'
}

###############################################################################
# GET OS ID
###############################################################################

get_os_id() {

    local SEARCH_OS="$1"

    hammer \
        --server "$FOREMAN_SERVER" \
        --username "$FOREMAN_USER" \
        --password "$FOREMAN_PASS" \
        os list |
    awk -F'|' -v os="$SEARCH_OS" '
    NR > 2 {
        for (i=1; i<=NF; i++) {
            gsub(/^ +| +$/, "", $i)
        }

        if ($2 == os) {
            print $1
            exit
        }
    }'
}

###############################################################################
# GET MEDIUM ID
###############################################################################

get_medium_id() {

    local SEARCH_MEDIUM="$1"

    hammer \
        --server "$FOREMAN_SERVER" \
        --username "$FOREMAN_USER" \
        --password "$FOREMAN_PASS" \
        medium list |
    awk -F'|' -v medium="$SEARCH_MEDIUM" '
    NR > 2 {
        for (i=1; i<=NF; i++) {
            gsub(/^ +| +$/, "", $i)
        }

        if ($2 == medium) {
            print $1
            exit
        }
    }'
}

###############################################################################
# LOOK UP ALL IDs
###############################################################################

header "        LOOKING UP FOREMAN IDS"

for IDX in 1 2 3 4
do

    section "Checking ${OS_LABEL[$IDX]}"

    ###########################################################################
    # RAID HOSTGROUP
    ###########################################################################

    RAID_HOSTGROUP_ID[$IDX]=$(get_hostgroup_id "${RAID_HOSTGROUP[$IDX]}")

    if [ -z "${RAID_HOSTGROUP_ID[$IDX]}" ]; then
        error "RAID Hostgroup not found: ${RAID_HOSTGROUP[$IDX]}"
        exit 1
    fi

    ok "RAID Hostgroup"
    echo "     Name : ${RAID_HOSTGROUP[$IDX]}"
    echo "     ID   : ${RAID_HOSTGROUP_ID[$IDX]}"

    ###########################################################################
    # SINGLE DISK HOSTGROUP
    ###########################################################################

    SINGLE_HOSTGROUP_ID[$IDX]=$(get_hostgroup_id "${SINGLE_HOSTGROUP[$IDX]}")

    if [ -z "${SINGLE_HOSTGROUP_ID[$IDX]}" ]; then
        error "SingleDisk Hostgroup not found: ${SINGLE_HOSTGROUP[$IDX]}"
        exit 1
    fi

    ok "SingleDisk Hostgroup"
    echo "     Name : ${SINGLE_HOSTGROUP[$IDX]}"
    echo "     ID   : ${SINGLE_HOSTGROUP_ID[$IDX]}"

    ###########################################################################
    # GET OS AND MEDIUM FROM RAID HOSTGROUP
    ###########################################################################

    HG_INFO=$(
        hammer \
            --server "$FOREMAN_SERVER" \
            --username "$FOREMAN_USER" \
            --password "$FOREMAN_PASS" \
            hostgroup info \
            --name "${RAID_HOSTGROUP[$IDX]}" 2>/dev/null
    )

    OS_NAME[$IDX]=$(
        echo "$HG_INFO" |
        awk -F': *' '
            /^[[:space:]]*Operating System:/ {
                sub(/^[[:space:]]*/, "", $2)
                print $2
                exit
            }
        '
    )

    MEDIUM_NAME[$IDX]=$(
        echo "$HG_INFO" |
        awk -F': *' '
            /^[[:space:]]*Medium:/ {
                sub(/^[[:space:]]*/, "", $2)
                print $2
                exit
            }
        '
    )

    if [ -z "${OS_NAME[$IDX]}" ]; then
        error "Operating System is empty for: ${RAID_HOSTGROUP[$IDX]}"
        exit 1
    fi

    if [ -z "${MEDIUM_NAME[$IDX]}" ]; then
        error "Installation Medium is empty for: ${RAID_HOSTGROUP[$IDX]}"
        exit 1
    fi

    echo
    echo "     Operating System : ${OS_NAME[$IDX]}"
    echo "     Medium           : ${MEDIUM_NAME[$IDX]}"

    ###########################################################################
    # OS ID
    ###########################################################################

    OPERATINGSYSTEM_ID[$IDX]=$(get_os_id "${OS_NAME[$IDX]}")

    if [ -z "${OPERATINGSYSTEM_ID[$IDX]}" ]; then
        error "Operating System ID not found: ${OS_NAME[$IDX]}"
        exit 1
    fi

    ok "Operating System ID : ${OPERATINGSYSTEM_ID[$IDX]}"

    ###########################################################################
    # MEDIUM ID
    ###########################################################################

    MEDIUM_ID[$IDX]=$(get_medium_id "${MEDIUM_NAME[$IDX]}")

    if [ -z "${MEDIUM_ID[$IDX]}" ]; then
        error "Medium ID not found: ${MEDIUM_NAME[$IDX]}"
        exit 1
    fi

    ok "Medium ID : ${MEDIUM_ID[$IDX]}"

done

###############################################################################
# GENERATE SEPARATE YAML OUTPUT
###############################################################################

header "        GENERATED AWX / ANSIBLE VARIABLES"

###############################################################################
# CENTOS 7
###############################################################################

cat <<EOF

    # ==============================================================================
    # CentOS Linux 7 Host Group / OS Selection
    #
    # AWX Survey:
    #
    # 1 = ${SINGLE_HOSTGROUP[1]}
    # 2 = ${RAID_HOSTGROUP[1]}
    #
    # ==============================================================================

    hostgroup: "{{ hostgroup | default('1', true) }}"

    hostgroup_id: >-
      {{
        {
          '1': ${SINGLE_HOSTGROUP_ID[1]},
          '2': ${RAID_HOSTGROUP_ID[1]}
        }[hostgroup | string]
      }}

    operatingsystem_id: ${OPERATINGSYSTEM_ID[1]}

    # ${MEDIUM_NAME[1]}
    medium_id: ${MEDIUM_ID[1]}

    # Kickstart default
    ptable_id: 126

    # CentOS 7 subnet
    subnet_name: "${SUBNET_NAME[1]}"

    # Katello Content
    content_view_id: ${CONTENT_VIEW_ID[1]}
    lifecycle_environment_id: 1

EOF

###############################################################################
# ROCKY LINUX 8.10
###############################################################################

cat <<EOF

    # ==============================================================================
    # Rocky Linux 8.10 Host Group / OS Selection
    #
    # AWX Survey:
    #
    # 1 = ${SINGLE_HOSTGROUP[2]}
    # 2 = ${RAID_HOSTGROUP[2]}
    #
    # ==============================================================================

    hostgroup: "{{ hostgroup | default('1', true) }}"

    hostgroup_id: >-
      {{
        {
          '1': ${SINGLE_HOSTGROUP_ID[2]},
          '2': ${RAID_HOSTGROUP_ID[2]}
        }[hostgroup | string]
      }}

    operatingsystem_id: ${OPERATINGSYSTEM_ID[2]}

    # ${MEDIUM_NAME[2]}
    medium_id: ${MEDIUM_ID[2]}

    # Kickstart default
    ptable_id: 126

    # Rocky Linux 8 subnet
    subnet_name: "${SUBNET_NAME[2]}"

    # Katello Content
    content_view_id: ${CONTENT_VIEW_ID[2]}
    lifecycle_environment_id: 1

EOF

###############################################################################
# ROCKY LINUX 9.2
###############################################################################

cat <<EOF

    # ==============================================================================
    # Rocky Linux 9.2 Host Group / OS Selection
    #
    # AWX Survey:
    #
    # 1 = ${SINGLE_HOSTGROUP[3]}
    # 2 = ${RAID_HOSTGROUP[3]}
    #
    # ==============================================================================

    hostgroup: "{{ hostgroup | default('1', true) }}"

    hostgroup_id: >-
      {{
        {
          '1': ${SINGLE_HOSTGROUP_ID[3]},
          '2': ${RAID_HOSTGROUP_ID[3]}
        }[hostgroup | string]
      }}

    operatingsystem_id: ${OPERATINGSYSTEM_ID[3]}

    # ${MEDIUM_NAME[3]}
    medium_id: ${MEDIUM_ID[3]}

    # Kickstart default
    ptable_id: 126

    # Rocky Linux 9 subnet
    subnet_name: "${SUBNET_NAME[3]}"

    # Katello Content
    content_view_id: ${CONTENT_VIEW_ID[3]}
    lifecycle_environment_id: 1

EOF

###############################################################################
# ROCKY LINUX 9.8
###############################################################################

cat <<EOF

    # ==============================================================================
    # Rocky Linux 9.8 Host Group / OS Selection
    #
    # AWX Survey:
    #
    # 1 = ${SINGLE_HOSTGROUP[4]}
    # 2 = ${RAID_HOSTGROUP[4]}
    #
    # ==============================================================================

    hostgroup: "{{ hostgroup | default('1', true) }}"

    hostgroup_id: >-
      {{
        {
          '1': ${SINGLE_HOSTGROUP_ID[4]},
          '2': ${RAID_HOSTGROUP_ID[4]}
        }[hostgroup | string]
      }}

    operatingsystem_id: ${OPERATINGSYSTEM_ID[4]}

    # ${MEDIUM_NAME[4]}
    medium_id: ${MEDIUM_ID[4]}

    # Kickstart default
    ptable_id: 126

    # Rocky Linux 9 subnet
    subnet_name: "${SUBNET_NAME[4]}"

    # Katello Content
    content_view_id: ${CONTENT_VIEW_ID[4]}
    lifecycle_environment_id: 1

EOF

header "        FOREMAN ID LOOKUP COMPLETED SUCCESSFULLY"
