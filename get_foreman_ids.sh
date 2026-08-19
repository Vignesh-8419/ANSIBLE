#!/bin/bash

###############################################################################
# FOREMAN DYNAMIC ID LOOKUP
#
# This script dynamically looks up:
#
#   - RAID Hostgroup ID
#   - SingleDisk Hostgroup ID
#   - RAID Operating System ID
#   - SingleDisk Operating System ID
#   - Installation Medium ID
#   - Subnet Name
#
# Then generates separate AWX / Ansible variable blocks for:
#
#   1. CentOS Linux 7
#   2. Rocky Linux 8.10
#   3. Rocky Linux 9.2
#   4. Rocky Linux 9.8
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
# STATIC SETTINGS
#
# Update Content View IDs here if they change in Foreman.
###############################################################################

PTABLE_ID=126
LIFECYCLE_ENVIRONMENT_ID=1


###############################################################################
# COLORS
###############################################################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'


###############################################################################
# FUNCTIONS
###############################################################################

header() {
    echo
    echo "============================================================"
    echo -e "${CYAN}$1${NC}"
    echo "============================================================"
}


section() {
    echo
    echo "------------------------------------------------------------"
    echo "$1"
    echo "------------------------------------------------------------"
}


ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}


error() {
    echo -e "${RED}[ERROR]${NC} $1"
}


warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}


###############################################################################
# HAMMER COMMAND
###############################################################################

hammer_cmd() {

    hammer \
        --server "$FOREMAN_SERVER" \
        --username "$FOREMAN_USER" \
        --password "$FOREMAN_PASS" \
        "$@"
}


###############################################################################
# CHECK FOREMAN CONNECTION
###############################################################################

header "        FOREMAN DYNAMIC ID LOOKUP"

if ! hammer_cmd hostgroup list >/dev/null 2>&1; then
    error "Unable to connect to Foreman"
    error "Check FOREMAN_SERVER, username and password"
    exit 1
fi

ok "Foreman connection successful"


###############################################################################
# HOSTGROUP DEFINITIONS
###############################################################################

declare -A OS_DISPLAY_NAME

declare -A RAID_HOSTGROUP_NAME
declare -A SINGLE_HOSTGROUP_NAME

declare -A CONTENT_VIEW_ID


OS_DISPLAY_NAME["1"]="CentOS Linux 7"
OS_DISPLAY_NAME["2"]="Rocky Linux 8.10"
OS_DISPLAY_NAME["3"]="Rocky Linux 9.2"
OS_DISPLAY_NAME["4"]="Rocky Linux 9.8"


###############################################################################
# HOSTGROUP NAMES
###############################################################################

RAID_HOSTGROUP_NAME["1"]="CentOSLinux7-RAID"
SINGLE_HOSTGROUP_NAME["1"]="CentOSLinux7-SingleDisk"

RAID_HOSTGROUP_NAME["2"]="RockyLinux8.10-RAID"
SINGLE_HOSTGROUP_NAME["2"]="RockyLinux8.10-SingleDisk"

RAID_HOSTGROUP_NAME["3"]="RockyLinux9.2-RAID"
SINGLE_HOSTGROUP_NAME["3"]="RockyLinux9.2-SingleDisk"

RAID_HOSTGROUP_NAME["4"]="RockyLinux9.8-RAID"
SINGLE_HOSTGROUP_NAME["4"]="RockyLinux9.8-SingleDisk"


###############################################################################
# KATELLO CONTENT VIEW IDS
#
# Existing values based on your current configuration.
###############################################################################

CONTENT_VIEW_ID["1"]=1
CONTENT_VIEW_ID["2"]=3
CONTENT_VIEW_ID["3"]=4
CONTENT_VIEW_ID["4"]=5


###############################################################################
# RESULT ARRAYS
###############################################################################

declare -A RAID_HOSTGROUP_ID
declare -A SINGLE_HOSTGROUP_ID

declare -A RAID_OS_NAME
declare -A SINGLE_OS_NAME

declare -A RAID_OS_ID
declare -A SINGLE_OS_ID

declare -A MEDIUM_NAME
declare -A MEDIUM_ID

declare -A SUBNET_NAME


###############################################################################
# GET HOSTGROUP INFORMATION
###############################################################################

get_hostgroup_info() {

    local HOSTGROUP="$1"

    hammer_cmd \
        hostgroup info \
        --name "$HOSTGROUP" 2>/dev/null
}


###############################################################################
# GET HOSTGROUP ID
###############################################################################

get_hostgroup_id() {

    local HOSTGROUP="$1"

    hammer_cmd \
        hostgroup info \
        --name "$HOSTGROUP" 2>/dev/null |
    awk -F': *' '
        /^Id:/ {
            print $2
            exit
        }
    '
}


###############################################################################
# GET OS NAME FROM HOSTGROUP
###############################################################################

get_os_name() {

    local HOSTGROUP="$1"

    get_hostgroup_info "$HOSTGROUP" |
    awk -F': *' '
        /^[[:space:]]*Operating System:/ {
            print $2
            exit
        }
    '
}


###############################################################################
# GET MEDIUM NAME FROM HOSTGROUP
###############################################################################

get_medium_name() {

    local HOSTGROUP="$1"

    get_hostgroup_info "$HOSTGROUP" |
    awk -F': *' '
        /^[[:space:]]*Medium:/ {
            print $2
            exit
        }
    '
}


###############################################################################
# GET SUBNET NAME FROM HOSTGROUP
###############################################################################

get_subnet_name() {

    local HOSTGROUP="$1"

    get_hostgroup_info "$HOSTGROUP" |
    awk -F': *' '
        /^[[:space:]]*Subnet ipv4:/ {
            print $2
            exit
        }
    '
}


###############################################################################
# GET OPERATING SYSTEM ID
###############################################################################

get_os_id() {

    local OS_NAME="$1"

    hammer_cmd os list |
    awk -F'|' -v wanted="$OS_NAME" '

        NR > 2 {

            id=$1
            title=$2

            gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", title)

            if (title == wanted) {
                print id
                exit
            }
        }
    '
}


###############################################################################
# GET MEDIUM ID
###############################################################################

get_medium_id() {

    local TARGET_MEDIUM="$1"

    hammer_cmd medium list |
    awk -F'|' -v wanted="$TARGET_MEDIUM" '

        NR > 2 {

            id=$1
            name=$2

            gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)

            if (name == wanted) {
                print id
                exit
            }
        }
    '
}


###############################################################################
# LOOK UP ALL FOREMAN IDS
###############################################################################

header "        LOOKING UP FOREMAN IDS"


for IDX in 1 2 3 4
do

    OS_LABEL="${OS_DISPLAY_NAME[$IDX]}"

    RAID_HG="${RAID_HOSTGROUP_NAME[$IDX]}"
    SINGLE_HG="${SINGLE_HOSTGROUP_NAME[$IDX]}"


    section "Checking ${OS_LABEL}"


    ###########################################################################
    # RAID HOSTGROUP
    ###########################################################################

    RAID_HOSTGROUP_ID[$IDX]=$(
        get_hostgroup_id "$RAID_HG"
    )


    if [[ -z "${RAID_HOSTGROUP_ID[$IDX]}" ]]; then
        error "RAID Hostgroup not found: $RAID_HG"
        exit 1
    fi


    ok "RAID Hostgroup"
    echo "     Name : $RAID_HG"
    echo "     ID   : ${RAID_HOSTGROUP_ID[$IDX]}"


    ###########################################################################
    # SINGLE DISK HOSTGROUP
    ###########################################################################

    SINGLE_HOSTGROUP_ID[$IDX]=$(
        get_hostgroup_id "$SINGLE_HG"
    )


    if [[ -z "${SINGLE_HOSTGROUP_ID[$IDX]}" ]]; then
        error "SingleDisk Hostgroup not found: $SINGLE_HG"
        exit 1
    fi


    ok "SingleDisk Hostgroup"
    echo "     Name : $SINGLE_HG"
    echo "     ID   : ${SINGLE_HOSTGROUP_ID[$IDX]}"


    ###########################################################################
    # RAID OPERATING SYSTEM
    ###########################################################################

    RAID_OS_NAME[$IDX]=$(
        get_os_name "$RAID_HG"
    )


    if [[ -z "${RAID_OS_NAME[$IDX]}" ]]; then
        error "Operating System is empty for RAID Hostgroup: $RAID_HG"
        exit 1
    fi


    RAID_OS_ID[$IDX]=$(
        get_os_id "${RAID_OS_NAME[$IDX]}"
    )


    if [[ -z "${RAID_OS_ID[$IDX]}" ]]; then
        error "Operating System ID not found: ${RAID_OS_NAME[$IDX]}"
        exit 1
    fi


    ###########################################################################
    # SINGLE DISK OPERATING SYSTEM
    ###########################################################################

    SINGLE_OS_NAME[$IDX]=$(
        get_os_name "$SINGLE_HG"
    )


    if [[ -z "${SINGLE_OS_NAME[$IDX]}" ]]; then
        error "Operating System is empty for SingleDisk Hostgroup: $SINGLE_HG"
        exit 1
    fi


    SINGLE_OS_ID[$IDX]=$(
        get_os_id "${SINGLE_OS_NAME[$IDX]}"
    )


    if [[ -z "${SINGLE_OS_ID[$IDX]}" ]]; then
        error "Operating System ID not found: ${SINGLE_OS_NAME[$IDX]}"
        exit 1
    fi


    ###########################################################################
    # MEDIUM
    ###########################################################################

    MEDIUM_NAME[$IDX]=$(
        get_medium_name "$RAID_HG"
    )


    if [[ -z "${MEDIUM_NAME[$IDX]}" ]]; then
        error "Installation Medium is empty for Hostgroup: $RAID_HG"
        exit 1
    fi


    MEDIUM_ID[$IDX]=$(
        get_medium_id "${MEDIUM_NAME[$IDX]}"
    )


    if [[ -z "${MEDIUM_ID[$IDX]}" ]]; then
        error "Medium ID not found: ${MEDIUM_NAME[$IDX]}"
        exit 1
    fi


    ###########################################################################
    # SUBNET
    ###########################################################################

    SUBNET_NAME[$IDX]=$(
        get_subnet_name "$RAID_HG"
    )


    if [[ -z "${SUBNET_NAME[$IDX]}" ]]; then
        error "Subnet is empty for Hostgroup: $RAID_HG"
        exit 1
    fi


    ###########################################################################
    # DISPLAY OS / MEDIUM DETAILS
    ###########################################################################

    echo
    echo "     RAID Operating System"
    echo "       Name : ${RAID_OS_NAME[$IDX]}"
    echo "       ID   : ${RAID_OS_ID[$IDX]}"

    echo
    echo "     SingleDisk Operating System"
    echo "       Name : ${SINGLE_OS_NAME[$IDX]}"
    echo "       ID   : ${SINGLE_OS_ID[$IDX]}"

    echo
    echo "     Installation Medium"
    echo "       Name : ${MEDIUM_NAME[$IDX]}"
    echo "       ID   : ${MEDIUM_ID[$IDX]}"

    echo
    echo "     Subnet"
    echo "       Name : ${SUBNET_NAME[$IDX]}"

done


###############################################################################
# GENERATE AWX / ANSIBLE VARIABLES
###############################################################################

header "        GENERATED AWX / ANSIBLE VARIABLES"


###############################################################################
# CENTOS LINUX 7
###############################################################################

cat <<EOF

    # ==============================================================================
    # CentOS Linux 7 Host Group / OS Selection
    #
    # AWX Survey:
    #
    # 1 = ${SINGLE_HOSTGROUP_NAME[1]}
    # 2 = ${RAID_HOSTGROUP_NAME[1]}
    #
    # ==============================================================================

    hostgroup: "{{ hostgroup | default('1', true) }}"

    hostgroup_id: >-
      {{
        {{
          '1': ${SINGLE_HOSTGROUP_ID[1]},
          '2': ${RAID_HOSTGROUP_ID[1]}
        }}[hostgroup | string]
      }}

    operatingsystem_id: >-
      {{
        {{
          '1': ${SINGLE_OS_ID[1]},
          '2': ${RAID_OS_ID[1]}
        }}[hostgroup | string]
      }}

    # ${MEDIUM_NAME[1]}
    medium_id: ${MEDIUM_ID[1]}

    # Kickstart default
    ptable_id: ${PTABLE_ID}

    # CentOS 7 subnet
    subnet_name: "${SUBNET_NAME[1]}"

    # Katello Content
    content_view_id: ${CONTENT_VIEW_ID[1]}
    lifecycle_environment_id: ${LIFECYCLE_ENVIRONMENT_ID}

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
    # 1 = ${SINGLE_HOSTGROUP_NAME[2]}
    # 2 = ${RAID_HOSTGROUP_NAME[2]}
    #
    # ==============================================================================

    hostgroup: "{{ hostgroup | default('1', true) }}"

    hostgroup_id: >-
      {{
        {{
          '1': ${SINGLE_HOSTGROUP_ID[2]},
          '2': ${RAID_HOSTGROUP_ID[2]}
        }}[hostgroup | string]
      }}

    operatingsystem_id: >-
      {{
        {{
          '1': ${SINGLE_OS_ID[2]},
          '2': ${RAID_OS_ID[2]}
        }}[hostgroup | string]
      }}

    # ${MEDIUM_NAME[2]}
    medium_id: ${MEDIUM_ID[2]}

    # Kickstart default
    ptable_id: ${PTABLE_ID}

    # Rocky Linux 8 subnet
    subnet_name: "${SUBNET_NAME[2]}"

    # Katello Content
    content_view_id: ${CONTENT_VIEW_ID[2]}
    lifecycle_environment_id: ${LIFECYCLE_ENVIRONMENT_ID}

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
    # 1 = ${SINGLE_HOSTGROUP_NAME[3]}
    # 2 = ${RAID_HOSTGROUP_NAME[3]}
    #
    # ==============================================================================

    hostgroup: "{{ hostgroup | default('1', true) }}"

    hostgroup_id: >-
      {{
        {{
          '1': ${SINGLE_HOSTGROUP_ID[3]},
          '2': ${RAID_HOSTGROUP_ID[3]}
        }}[hostgroup | string]
      }}

    operatingsystem_id: >-
      {{
        {{
          '1': ${SINGLE_OS_ID[3]},
          '2': ${RAID_OS_ID[3]}
        }}[hostgroup | string]
      }}

    # ${MEDIUM_NAME[3]}
    medium_id: ${MEDIUM_ID[3]}

    # Kickstart default
    ptable_id: ${PTABLE_ID}

    # Rocky Linux 9 subnet
    subnet_name: "${SUBNET_NAME[3]}"

    # Katello Content
    content_view_id: ${CONTENT_VIEW_ID[3]}
    lifecycle_environment_id: ${LIFECYCLE_ENVIRONMENT_ID}

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
    # 1 = ${SINGLE_HOSTGROUP_NAME[4]}
    # 2 = ${RAID_HOSTGROUP_NAME[4]}
    #
    # ==============================================================================

    hostgroup: "{{ hostgroup | default('1', true) }}"

    hostgroup_id: >-
      {{
        {{
          '1': ${SINGLE_HOSTGROUP_ID[4]},
          '2': ${RAID_HOSTGROUP_ID[4]}
        }}[hostgroup | string]
      }}

    operatingsystem_id: >-
      {{
        {{
          '1': ${SINGLE_OS_ID[4]},
          '2': ${RAID_OS_ID[4]}
        }}[hostgroup | string]
      }}

    # ${MEDIUM_NAME[4]}
    medium_id: ${MEDIUM_ID[4]}

    # Kickstart default
    ptable_id: ${PTABLE_ID}

    # Rocky Linux 9 subnet
    subnet_name: "${SUBNET_NAME[4]}"

    # Katello Content
    content_view_id: ${CONTENT_VIEW_ID[4]}
    lifecycle_environment_id: ${LIFECYCLE_ENVIRONMENT_ID}

EOF


###############################################################################
# FINAL SUMMARY
###############################################################################

header "        FOREMAN ID LOOKUP COMPLETED SUCCESSFULLY"
