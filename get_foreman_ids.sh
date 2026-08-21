#!/bin/bash

###############################################################################
# FOREMAN DYNAMIC ID LOOKUP
#
# Dynamically retrieves Foreman/Katello IDs and generates AWX/Ansible
# variable blocks for:
#
#   1. CentOS Linux 7
#   2. Rocky Linux 8.10
#   3. Rocky Linux 9.2
#   4. Rocky Linux 9.8
#
# IMPORTANT:
#
# Each OS version has TWO separate Foreman Operating Systems:
#
#   1 = SingleDisk
#   2 = RAID
#
# Therefore BOTH:
#
#   - hostgroup_id
#   - operatingsystem_id
#
# are dynamically selected from the AWX Survey value.
#
###############################################################################

set -o pipefail

###############################################################################
# FOREMAN CONNECTION
###############################################################################

FOREMAN_SERVER="https://cent-07-01.vgs.com"
FOREMAN_USER="admin"

# Export before running:
#
# export FOREMAN_PASSWORD='your-password'
#
FOREMAN_PASSWORD="${FOREMAN_PASSWORD:-}"

if [[ -z "${FOREMAN_PASSWORD}" ]]; then
    echo "[ERROR] FOREMAN_PASSWORD environment variable is not set"
    echo
    echo "Run:"
    echo "export FOREMAN_PASSWORD='your-foreman-password'"
    echo "./get_foreman_ids.sh"
    exit 1
fi

HAMMER="hammer \
  --server ${FOREMAN_SERVER} \
  --username ${FOREMAN_USER} \
  --password ${FOREMAN_PASSWORD}"

###############################################################################
# COMMON FOREMAN RESOURCE NAMES
###############################################################################

ORG_NAME="Default Organization"
LOCATION_NAME="Default Location"

PTABLE_NAME="Kickstart default"
ARCH_NAME="x86_64"
DOMAIN_NAME="vgs.com"

LIFECYCLE_ENVIRONMENT_NAME="Library"

PXE_LOADER="Grub2 UEFI"

###############################################################################
# DISPLAY FUNCTIONS
###############################################################################

header() {
    echo
    echo "============================================================"
    echo "        $1"
    echo "============================================================"
}

separator() {
    echo
    echo "------------------------------------------------------------"
    echo "$1"
    echo "------------------------------------------------------------"
}

ok() {
    echo "[OK] $1"
}

warn() {
    echo "[WARN] $1"
}

error() {
    echo "[ERROR] $1"
}

die() {
    error "$1"
    exit 1
}

###############################################################################
# GENERIC HAMMER ID LOOKUP
#
# Searches Hammer table output for an EXACT resource name.
# Returns the first numeric ID from the matching row.
#
###############################################################################

get_id_from_output() {
    local NAME="$1"

    awk -F'|' -v name="$NAME" '
        NR <= 2 {
            next
        }

        {
            found = 0
            id = ""

            for (i = 1; i <= NF; i++) {

                field = $i

                gsub(/^[ \t]+/, "", field)
                gsub(/[ \t]+$/, "", field)

                if (id == "" && field ~ /^[0-9]+$/) {
                    id = field
                }

                if (field == name) {
                    found = 1
                }
            }

            if (found == 1 && id != "") {
                print id
                exit
            }
        }
    '
}

###############################################################################
# ORGANIZATION LOOKUP
###############################################################################

get_organization_id() {
    local NAME="$1"

    $HAMMER organization list \
        --per-page 9999 2>/dev/null |
        get_id_from_output "$NAME"
}

###############################################################################
# LOCATION LOOKUP
###############################################################################

get_location_id() {
    local NAME="$1"

    $HAMMER location list \
        --per-page 9999 2>/dev/null |
        get_id_from_output "$NAME"
}

###############################################################################
# HOSTGROUP LOOKUP
###############################################################################

get_hostgroup_id() {
    local NAME="$1"

    $HAMMER hostgroup list \
        --per-page 9999 2>/dev/null |
        get_id_from_output "$NAME"
}

###############################################################################
# OPERATING SYSTEM LOOKUP
###############################################################################

get_os_id() {
    local NAME="$1"

    $HAMMER os list \
        --per-page 9999 2>/dev/null |
        get_id_from_output "$NAME"
}

###############################################################################
# INSTALLATION MEDIUM LOOKUP
###############################################################################

get_medium_id() {
    local NAME="$1"

    $HAMMER medium list \
        --per-page 9999 2>/dev/null |
        get_id_from_output "$NAME"
}

###############################################################################
# SUBNET LOOKUP
###############################################################################

get_subnet_id() {
    local NAME="$1"

    $HAMMER subnet list \
        --per-page 9999 2>/dev/null |
        get_id_from_output "$NAME"
}

###############################################################################
# PARTITION TABLE LOOKUP
###############################################################################

get_ptable_id() {
    local NAME="$1"

    $HAMMER partition-table list \
        --per-page 9999 2>/dev/null |
        get_id_from_output "$NAME"
}

###############################################################################
# ARCHITECTURE LOOKUP
###############################################################################

get_architecture_id() {
    local NAME="$1"

    $HAMMER architecture list \
        --per-page 9999 2>/dev/null |
        get_id_from_output "$NAME"
}

###############################################################################
# DOMAIN LOOKUP
###############################################################################

get_domain_id() {
    local NAME="$1"

    $HAMMER domain list \
        --per-page 9999 2>/dev/null |
        get_id_from_output "$NAME"
}

###############################################################################
# CONTENT VIEW LOOKUP
###############################################################################

get_content_view_id() {
    local NAME="$1"

    $HAMMER content-view list \
        --organization "${ORG_NAME}" \
        --per-page 9999 2>/dev/null |
        get_id_from_output "$NAME"
}

###############################################################################
# LIFECYCLE ENVIRONMENT LOOKUP
###############################################################################

get_lifecycle_environment_id() {
    local NAME="$1"

    $HAMMER lifecycle-environment list \
        --organization "${ORG_NAME}" \
        --per-page 9999 2>/dev/null |
        get_id_from_output "$NAME"
}

###############################################################################
# VALIDATE REQUIRED ID
###############################################################################

require_id() {
    local DESCRIPTION="$1"
    local ID="$2"

    if [[ -z "${ID}" ]]; then
        die "${DESCRIPTION} not found"
    fi
}

###############################################################################
# VERIFY FOREMAN CONNECTION
###############################################################################

header "FOREMAN DYNAMIC ID LOOKUP"

if ! $HAMMER organization list --per-page 1 >/dev/null 2>&1; then
    die "Unable to connect to Foreman"
fi

ok "Foreman connection successful"

###############################################################################
# LOOKUP COMMON FOREMAN IDS
###############################################################################

header "LOOKING UP COMMON FOREMAN IDS"

ORG_ID=$(get_organization_id "${ORG_NAME}")
LOCATION_ID=$(get_location_id "${LOCATION_NAME}")

PTABLE_ID=$(get_ptable_id "${PTABLE_NAME}")
ARCHITECTURE_ID=$(get_architecture_id "${ARCH_NAME}")
DOMAIN_ID=$(get_domain_id "${DOMAIN_NAME}")

LIFECYCLE_ENVIRONMENT_ID=$(get_lifecycle_environment_id \
    "${LIFECYCLE_ENVIRONMENT_NAME}")

require_id "Organization '${ORG_NAME}'" "${ORG_ID}"
require_id "Location '${LOCATION_NAME}'" "${LOCATION_ID}"
require_id "Partition Table '${PTABLE_NAME}'" "${PTABLE_ID}"
require_id "Architecture '${ARCH_NAME}'" "${ARCHITECTURE_ID}"
require_id "Domain '${DOMAIN_NAME}'" "${DOMAIN_ID}"
require_id "Lifecycle Environment '${LIFECYCLE_ENVIRONMENT_NAME}'" \
    "${LIFECYCLE_ENVIRONMENT_ID}"

ok "Organization ID          : ${ORG_ID}"
ok "Location ID              : ${LOCATION_ID}"
ok "Partition Table ID       : ${PTABLE_ID}"
ok "Architecture ID          : ${ARCHITECTURE_ID}"
ok "Domain ID                : ${DOMAIN_ID}"
ok "Lifecycle Environment ID : ${LIFECYCLE_ENVIRONMENT_ID}"

###############################################################################
# CENTOS LINUX 7 CONFIGURATION
###############################################################################

CENTOS7_NAME="CentOS Linux 7"

CENTOS7_RAID_HG="CentOSLinux7-RAID"
CENTOS7_SINGLE_HG="CentOSLinux7-SingleDisk"

# TWO SEPARATE OPERATING SYSTEMS
CENTOS7_RAID_OS="CentOSLinux7-RAID 7"
CENTOS7_SINGLE_OS="CentOSLinux7-SingleDisk 7"

CENTOS7_MEDIUM="CentOS 7 Remote"
CENTOS7_SUBNET="vgs-subnet-centos"
CENTOS7_CONTENT_VIEW="CentOS7-CV"

###############################################################################
# ROCKY LINUX 8.10 CONFIGURATION
###############################################################################

ROCKY8_NAME="Rocky Linux 8.10"

ROCKY8_RAID_HG="RockyLinux8.10-RAID"
ROCKY8_SINGLE_HG="RockyLinux8.10-SingleDisk"

# TWO SEPARATE OPERATING SYSTEMS
ROCKY8_RAID_OS="RockyLinux8.10-RAID 8.10"
ROCKY8_SINGLE_OS="RockyLinux8.10-SingleDisk 8.10"

ROCKY8_MEDIUM="Rocky 8 Remote"
ROCKY8_SUBNET="vgs-subnet-rockyos"
ROCKY8_CONTENT_VIEW="Rocky8-CV"

###############################################################################
# ROCKY LINUX 9.2 CONFIGURATION
###############################################################################

ROCKY92_NAME="Rocky Linux 9.2"

ROCKY92_RAID_HG="RockyLinux9.2-RAID"
ROCKY92_SINGLE_HG="RockyLinux9.2-SingleDisk"

# TWO SEPARATE OPERATING SYSTEMS
ROCKY92_RAID_OS="RockyLinux9.2-RAID 9.2"
ROCKY92_SINGLE_OS="RockyLinux9.2-SingleDisk 9.2"

ROCKY92_MEDIUM="Rocky 9.2 Remote"
ROCKY92_SUBNET="vgs-subnet-rockyos"
ROCKY92_CONTENT_VIEW="Rocky9.2-CV"

###############################################################################
# ROCKY LINUX 9.8 CONFIGURATION
###############################################################################

ROCKY98_NAME="Rocky Linux 9.8"

ROCKY98_RAID_HG="RockyLinux9.8-RAID"
ROCKY98_SINGLE_HG="RockyLinux9.8-SingleDisk"

# TWO SEPARATE OPERATING SYSTEMS
ROCKY98_RAID_OS="RockyLinux9.8-RAID 9.8"
ROCKY98_SINGLE_OS="RockyLinux9.8-SingleDisk 9.8"

ROCKY98_MEDIUM="Rocky 9 Remote"
ROCKY98_SUBNET="vgs-subnet-rockyos"
ROCKY98_CONTENT_VIEW="Rocky9.8-CV"

###############################################################################
# LOOKUP CENTOS LINUX 7 IDS
###############################################################################

separator "Checking CentOS Linux 7"

CENTOS7_RAID_HG_ID=$(get_hostgroup_id "${CENTOS7_RAID_HG}")
CENTOS7_SINGLE_HG_ID=$(get_hostgroup_id "${CENTOS7_SINGLE_HG}")

CENTOS7_RAID_OS_ID=$(get_os_id "${CENTOS7_RAID_OS}")
CENTOS7_SINGLE_OS_ID=$(get_os_id "${CENTOS7_SINGLE_OS}")

CENTOS7_MEDIUM_ID=$(get_medium_id "${CENTOS7_MEDIUM}")
CENTOS7_SUBNET_ID=$(get_subnet_id "${CENTOS7_SUBNET}")
CENTOS7_CV_ID=$(get_content_view_id "${CENTOS7_CONTENT_VIEW}")

require_id "CentOS 7 RAID Hostgroup '${CENTOS7_RAID_HG}'" \
    "${CENTOS7_RAID_HG_ID}"
require_id "CentOS 7 SingleDisk Hostgroup '${CENTOS7_SINGLE_HG}'" \
    "${CENTOS7_SINGLE_HG_ID}"

require_id "CentOS 7 RAID OS '${CENTOS7_RAID_OS}'" \
    "${CENTOS7_RAID_OS_ID}"
require_id "CentOS 7 SingleDisk OS '${CENTOS7_SINGLE_OS}'" \
    "${CENTOS7_SINGLE_OS_ID}"

require_id "CentOS 7 Medium '${CENTOS7_MEDIUM}'" \
    "${CENTOS7_MEDIUM_ID}"
require_id "CentOS 7 Subnet '${CENTOS7_SUBNET}'" \
    "${CENTOS7_SUBNET_ID}"
require_id "CentOS 7 Content View '${CENTOS7_CONTENT_VIEW}'" \
    "${CENTOS7_CV_ID}"

ok "RAID Hostgroup"
echo "     Name : ${CENTOS7_RAID_HG}"
echo "     ID   : ${CENTOS7_RAID_HG_ID}"

ok "SingleDisk Hostgroup"
echo "     Name : ${CENTOS7_SINGLE_HG}"
echo "     ID   : ${CENTOS7_SINGLE_HG_ID}"

echo
ok "RAID Operating System"
echo "     Name : ${CENTOS7_RAID_OS}"
echo "     ID   : ${CENTOS7_RAID_OS_ID}"

ok "SingleDisk Operating System"
echo "     Name : ${CENTOS7_SINGLE_OS}"
echo "     ID   : ${CENTOS7_SINGLE_OS_ID}"

echo
echo "     Medium : ${CENTOS7_MEDIUM}"
echo "     Subnet : ${CENTOS7_SUBNET}"

ok "Medium ID       : ${CENTOS7_MEDIUM_ID}"
ok "Subnet ID       : ${CENTOS7_SUBNET_ID}"
ok "Content View ID : ${CENTOS7_CV_ID}"

###############################################################################
# LOOKUP ROCKY LINUX 8.10 IDS
###############################################################################

separator "Checking Rocky Linux 8.10"

ROCKY8_RAID_HG_ID=$(get_hostgroup_id "${ROCKY8_RAID_HG}")
ROCKY8_SINGLE_HG_ID=$(get_hostgroup_id "${ROCKY8_SINGLE_HG}")

ROCKY8_RAID_OS_ID=$(get_os_id "${ROCKY8_RAID_OS}")
ROCKY8_SINGLE_OS_ID=$(get_os_id "${ROCKY8_SINGLE_OS}")

ROCKY8_MEDIUM_ID=$(get_medium_id "${ROCKY8_MEDIUM}")
ROCKY8_SUBNET_ID=$(get_subnet_id "${ROCKY8_SUBNET}")
ROCKY8_CV_ID=$(get_content_view_id "${ROCKY8_CONTENT_VIEW}")

require_id "Rocky 8 RAID Hostgroup '${ROCKY8_RAID_HG}'" \
    "${ROCKY8_RAID_HG_ID}"
require_id "Rocky 8 SingleDisk Hostgroup '${ROCKY8_SINGLE_HG}'" \
    "${ROCKY8_SINGLE_HG_ID}"

require_id "Rocky 8 RAID OS '${ROCKY8_RAID_OS}'" \
    "${ROCKY8_RAID_OS_ID}"
require_id "Rocky 8 SingleDisk OS '${ROCKY8_SINGLE_OS}'" \
    "${ROCKY8_SINGLE_OS_ID}"

require_id "Rocky 8 Medium '${ROCKY8_MEDIUM}'" \
    "${ROCKY8_MEDIUM_ID}"
require_id "Rocky 8 Subnet '${ROCKY8_SUBNET}'" \
    "${ROCKY8_SUBNET_ID}"
require_id "Rocky 8 Content View '${ROCKY8_CONTENT_VIEW}'" \
    "${ROCKY8_CV_ID}"

ok "RAID Hostgroup"
echo "     Name : ${ROCKY8_RAID_HG}"
echo "     ID   : ${ROCKY8_RAID_HG_ID}"

ok "SingleDisk Hostgroup"
echo "     Name : ${ROCKY8_SINGLE_HG}"
echo "     ID   : ${ROCKY8_SINGLE_HG_ID}"

echo
ok "RAID Operating System"
echo "     Name : ${ROCKY8_RAID_OS}"
echo "     ID   : ${ROCKY8_RAID_OS_ID}"

ok "SingleDisk Operating System"
echo "     Name : ${ROCKY8_SINGLE_OS}"
echo "     ID   : ${ROCKY8_SINGLE_OS_ID}"

echo
echo "     Medium : ${ROCKY8_MEDIUM}"
echo "     Subnet : ${ROCKY8_SUBNET}"

ok "Medium ID       : ${ROCKY8_MEDIUM_ID}"
ok "Subnet ID       : ${ROCKY8_SUBNET_ID}"
ok "Content View ID : ${ROCKY8_CV_ID}"

###############################################################################
# LOOKUP ROCKY LINUX 9.2 IDS
###############################################################################

separator "Checking Rocky Linux 9.2"

ROCKY92_RAID_HG_ID=$(get_hostgroup_id "${ROCKY92_RAID_HG}")
ROCKY92_SINGLE_HG_ID=$(get_hostgroup_id "${ROCKY92_SINGLE_HG}")

ROCKY92_RAID_OS_ID=$(get_os_id "${ROCKY92_RAID_OS}")
ROCKY92_SINGLE_OS_ID=$(get_os_id "${ROCKY92_SINGLE_OS}")

ROCKY92_MEDIUM_ID=$(get_medium_id "${ROCKY92_MEDIUM}")
ROCKY92_SUBNET_ID=$(get_subnet_id "${ROCKY92_SUBNET}")
ROCKY92_CV_ID=$(get_content_view_id "${ROCKY92_CONTENT_VIEW}")

require_id "Rocky 9.2 RAID Hostgroup '${ROCKY92_RAID_HG}'" \
    "${ROCKY92_RAID_HG_ID}"
require_id "Rocky 9.2 SingleDisk Hostgroup '${ROCKY92_SINGLE_HG}'" \
    "${ROCKY92_SINGLE_HG_ID}"

require_id "Rocky 9.2 RAID OS '${ROCKY92_RAID_OS}'" \
    "${ROCKY92_RAID_OS_ID}"
require_id "Rocky 9.2 SingleDisk OS '${ROCKY92_SINGLE_OS}'" \
    "${ROCKY92_SINGLE_OS_ID}"

require_id "Rocky 9.2 Medium '${ROCKY92_MEDIUM}'" \
    "${ROCKY92_MEDIUM_ID}"
require_id "Rocky 9.2 Subnet '${ROCKY92_SUBNET}'" \
    "${ROCKY92_SUBNET_ID}"
require_id "Rocky 9.2 Content View '${ROCKY92_CONTENT_VIEW}'" \
    "${ROCKY92_CV_ID}"

ok "RAID Hostgroup"
echo "     Name : ${ROCKY92_RAID_HG}"
echo "     ID   : ${ROCKY92_RAID_HG_ID}"

ok "SingleDisk Hostgroup"
echo "     Name : ${ROCKY92_SINGLE_HG}"
echo "     ID   : ${ROCKY92_SINGLE_HG_ID}"

echo
ok "RAID Operating System"
echo "     Name : ${ROCKY92_RAID_OS}"
echo "     ID   : ${ROCKY92_RAID_OS_ID}"

ok "SingleDisk Operating System"
echo "     Name : ${ROCKY92_SINGLE_OS}"
echo "     ID   : ${ROCKY92_SINGLE_OS_ID}"

echo
echo "     Medium : ${ROCKY92_MEDIUM}"
echo "     Subnet : ${ROCKY92_SUBNET}"

ok "Medium ID       : ${ROCKY92_MEDIUM_ID}"
ok "Subnet ID       : ${ROCKY92_SUBNET_ID}"
ok "Content View ID : ${ROCKY92_CV_ID}"

###############################################################################
# LOOKUP ROCKY LINUX 9.8 IDS
###############################################################################

separator "Checking Rocky Linux 9.8"

ROCKY98_RAID_HG_ID=$(get_hostgroup_id "${ROCKY98_RAID_HG}")
ROCKY98_SINGLE_HG_ID=$(get_hostgroup_id "${ROCKY98_SINGLE_HG}")

ROCKY98_RAID_OS_ID=$(get_os_id "${ROCKY98_RAID_OS}")
ROCKY98_SINGLE_OS_ID=$(get_os_id "${ROCKY98_SINGLE_OS}")

ROCKY98_MEDIUM_ID=$(get_medium_id "${ROCKY98_MEDIUM}")
ROCKY98_SUBNET_ID=$(get_subnet_id "${ROCKY98_SUBNET}")
ROCKY98_CV_ID=$(get_content_view_id "${ROCKY98_CONTENT_VIEW}")

require_id "Rocky 9.8 RAID Hostgroup '${ROCKY98_RAID_HG}'" \
    "${ROCKY98_RAID_HG_ID}"
require_id "Rocky 9.8 SingleDisk Hostgroup '${ROCKY98_SINGLE_HG}'" \
    "${ROCKY98_SINGLE_HG_ID}"

require_id "Rocky 9.8 RAID OS '${ROCKY98_RAID_OS}'" \
    "${ROCKY98_RAID_OS_ID}"
require_id "Rocky 9.8 SingleDisk OS '${ROCKY98_SINGLE_OS}'" \
    "${ROCKY98_SINGLE_OS_ID}"

require_id "Rocky 9.8 Medium '${ROCKY98_MEDIUM}'" \
    "${ROCKY98_MEDIUM_ID}"
require_id "Rocky 9.8 Subnet '${ROCKY98_SUBNET}'" \
    "${ROCKY98_SUBNET_ID}"
require_id "Rocky 9.8 Content View '${ROCKY98_CONTENT_VIEW}'" \
    "${ROCKY98_CV_ID}"

ok "RAID Hostgroup"
echo "     Name : ${ROCKY98_RAID_HG}"
echo "     ID   : ${ROCKY98_RAID_HG_ID}"

ok "SingleDisk Hostgroup"
echo "     Name : ${ROCKY98_SINGLE_HG}"
echo "     ID   : ${ROCKY98_SINGLE_HG_ID}"

echo
ok "RAID Operating System"
echo "     Name : ${ROCKY98_RAID_OS}"
echo "     ID   : ${ROCKY98_RAID_OS_ID}"

ok "SingleDisk Operating System"
echo "     Name : ${ROCKY98_SINGLE_OS}"
echo "     ID   : ${ROCKY98_SINGLE_OS_ID}"

echo
echo "     Medium : ${ROCKY98_MEDIUM}"
echo "     Subnet : ${ROCKY98_SUBNET}"

ok "Medium ID       : ${ROCKY98_MEDIUM_ID}"
ok "Subnet ID       : ${ROCKY98_SUBNET_ID}"
ok "Content View ID : ${ROCKY98_CV_ID}"

###############################################################################
# GENERATED AWX / ANSIBLE VARIABLES
###############################################################################

header "GENERATED AWX / ANSIBLE VARIABLES"

cat <<EOF

    # ============================================================================
    # CentOS Linux 7 Host Group / Operating System Selection
    #
    # AWX Survey:
    #
    # 1 = ${CENTOS7_SINGLE_HG}
    #     OS = ${CENTOS7_SINGLE_OS}
    #
    # 2 = ${CENTOS7_RAID_HG}
    #     OS = ${CENTOS7_RAID_OS}
    #
    # ============================================================================
    
    hostgroup: "{{ hostgroup | default('1', true) }}"
    
    hostgroup_id: >-
      {{
        {
          '1': ${CENTOS7_SINGLE_HG_ID},
          '2': ${CENTOS7_RAID_HG_ID}
        }[hostgroup | string]
      }}
    
    operatingsystem_id: >-
      {{
        {
          '1': ${CENTOS7_SINGLE_OS_ID},
          '2': ${CENTOS7_RAID_OS_ID}
        }[hostgroup | string]
      }}
    
    # ${CENTOS7_MEDIUM}
    medium_id: ${CENTOS7_MEDIUM_ID}
    
    # ${PTABLE_NAME}
    ptable_id: ${PTABLE_ID}
    
    # CentOS 7 subnet
    subnet_name: "${CENTOS7_SUBNET}"
    
    # Katello Content
    content_view_id: ${CENTOS7_CV_ID}
    lifecycle_environment_id: ${LIFECYCLE_ENVIRONMENT_ID}
    
    # Architecture
    architecture_id: ${ARCHITECTURE_ID}
    
    # Domain
    domain_id: ${DOMAIN_ID}
    
    # PXE
    pxe_loader: "${PXE_LOADER}"
    
    
    # ============================================================================
    # Rocky Linux 8.10 Host Group / Operating System Selection
    #
    # AWX Survey:
    #
    # 1 = ${ROCKY8_SINGLE_HG}
    #     OS = ${ROCKY8_SINGLE_OS}
    #
    # 2 = ${ROCKY8_RAID_HG}
    #     OS = ${ROCKY8_RAID_OS}
    #
    # ============================================================================
    
    hostgroup: "{{ hostgroup | default('1', true) }}"
    
    hostgroup_id: >-
      {{
        {
          '1': ${ROCKY8_SINGLE_HG_ID},
          '2': ${ROCKY8_RAID_HG_ID}
        }[hostgroup | string]
      }}
    
    operatingsystem_id: >-
      {{
        {
          '1': ${ROCKY8_SINGLE_OS_ID},
          '2': ${ROCKY8_RAID_OS_ID}
        }[hostgroup | string]
      }}
    
    # ${ROCKY8_MEDIUM}
    medium_id: ${ROCKY8_MEDIUM_ID}
    
    # ${PTABLE_NAME}
    ptable_id: ${PTABLE_ID}
    
    # Rocky Linux 8 subnet
    subnet_name: "${ROCKY8_SUBNET}"
    
    # Katello Content
    content_view_id: ${ROCKY8_CV_ID}
    lifecycle_environment_id: ${LIFECYCLE_ENVIRONMENT_ID}
    
    # Architecture
    architecture_id: ${ARCHITECTURE_ID}
    
    # Domain
    domain_id: ${DOMAIN_ID}
    
    # PXE
    pxe_loader: "${PXE_LOADER}"
    
    
    # ============================================================================
    # Rocky Linux 9.2 Host Group / Operating System Selection
    #
    # AWX Survey:
    #
    # 1 = ${ROCKY92_SINGLE_HG}
    #     OS = ${ROCKY92_SINGLE_OS}
    #
    # 2 = ${ROCKY92_RAID_HG}
    #     OS = ${ROCKY92_RAID_OS}
    #
    # ============================================================================
    
    hostgroup: "{{ hostgroup | default('1', true) }}"
    
    hostgroup_id: >-
      {{
        {
          '1': ${ROCKY92_SINGLE_HG_ID},
          '2': ${ROCKY92_RAID_HG_ID}
        }[hostgroup | string]
      }}
    
    operatingsystem_id: >-
      {{
        {
          '1': ${ROCKY92_SINGLE_OS_ID},
          '2': ${ROCKY92_RAID_OS_ID}
        }[hostgroup | string]
      }}
    
    # ${ROCKY92_MEDIUM}
    medium_id: ${ROCKY92_MEDIUM_ID}
    
    # ${PTABLE_NAME}
    ptable_id: ${PTABLE_ID}
    
    # Rocky Linux 9.2 subnet
    subnet_name: "${ROCKY92_SUBNET}"
    
    # Katello Content
    content_view_id: ${ROCKY92_CV_ID}
    lifecycle_environment_id: ${LIFECYCLE_ENVIRONMENT_ID}
    
    # Architecture
    architecture_id: ${ARCHITECTURE_ID}
    
    # Domain
    domain_id: ${DOMAIN_ID}
    
    # PXE
    pxe_loader: "${PXE_LOADER}"
    
    
    # ============================================================================
    # Rocky Linux 9.8 Host Group / Operating System Selection
    #
    # AWX Survey:
    #
    # 1 = ${ROCKY98_SINGLE_HG}
    #     OS = ${ROCKY98_SINGLE_OS}
    #
    # 2 = ${ROCKY98_RAID_HG}
    #     OS = ${ROCKY98_RAID_OS}
    #
    # ============================================================================
    
    hostgroup: "{{ hostgroup | default('1', true) }}"
    
    hostgroup_id: >-
      {{
        {
          '1': ${ROCKY98_SINGLE_HG_ID},
          '2': ${ROCKY98_RAID_HG_ID}
        }[hostgroup | string]
      }}
    
    operatingsystem_id: >-
      {{
        {
          '1': ${ROCKY98_SINGLE_OS_ID},
          '2': ${ROCKY98_RAID_OS_ID}
        }[hostgroup | string]
      }}
    
    # ${ROCKY98_MEDIUM}
    medium_id: ${ROCKY98_MEDIUM_ID}
    
    # ${PTABLE_NAME}
    ptable_id: ${PTABLE_ID}
    
    # Rocky Linux 9.8 subnet
    subnet_name: "${ROCKY98_SUBNET}"
    
    # Katello Content
    content_view_id: ${ROCKY98_CV_ID}
    lifecycle_environment_id: ${LIFECYCLE_ENVIRONMENT_ID}
    
    # Architecture
    architecture_id: ${ARCHITECTURE_ID}
    
    # Domain
    domain_id: ${DOMAIN_ID}
    
    # PXE
    pxe_loader: "${PXE_LOADER}"

EOF

###############################################################################
# COMPLETION
###############################################################################

header "FOREMAN ID LOOKUP COMPLETED SUCCESSFULLY"
