#!/bin/bash

###############################################################################
# FOREMAN DYNAMIC ID LOOKUP
#
# Dynamically retrieves Foreman IDs and generates AWX/Ansible variable blocks
# for:
#
#   - CentOS Linux 7
#   - Rocky Linux 8.10
#   - Rocky Linux 9.2
#   - Rocky Linux 9.8
#
###############################################################################

set -o pipefail

###############################################################################
# FOREMAN CONNECTION
###############################################################################

FOREMAN_SERVER="https://cent-07-01.vgs.com"
FOREMAN_USER="admin"
FOREMAN_PASSWORD="zqs977dXzqfEvTML"

HAMMER="hammer \
  --server ${FOREMAN_SERVER} \
  --username ${FOREMAN_USER} \
  --password ${FOREMAN_PASSWORD}"

###############################################################################
# DEFAULT RESOURCE NAMES
###############################################################################

ORG_NAME="Default Organization"
LOCATION_NAME="Default Location"

PTABLE_NAME="Kickstart default"

ARCH_NAME="x86_64"
DOMAIN_NAME="vgs.com"

PXE_LOADER="Grub2 UEFI"

###############################################################################
# OUTPUT HELPERS
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
# HAMMER ID LOOKUP FUNCTIONS
###############################################################################

get_hostgroup_id() {
    local NAME="$1"

    $HAMMER hostgroup list \
        --search "name=\"${NAME}\"" \
        --per-page 9999 2>/dev/null |
        awk -F'|' -v name="$NAME" '
            NR > 2 {
                gsub(/^[ \t]+|[ \t]+$/, "", $2)
                gsub(/^[ \t]+|[ \t]+$/, "", $3)

                if ($3 == name || $2 == name) {
                    print $2
                    exit
                }
            }
        '
}

get_os_id() {
    local NAME="$1"

    $HAMMER os list \
        --search "title=\"${NAME}\"" \
        --per-page 9999 2>/dev/null |
        awk -F'|' -v name="$NAME" '
            NR > 2 {
                gsub(/^[ \t]+|[ \t]+$/, "", $2)
                gsub(/^[ \t]+|[ \t]+$/, "", $3)

                if ($3 == name) {
                    print $2
                    exit
                }
            }
        '
}

get_medium_id() {
    local NAME="$1"

    $HAMMER medium list \
        --search "name=\"${NAME}\"" \
        --per-page 9999 2>/dev/null |
        awk -F'|' -v name="$NAME" '
            NR > 2 {
                gsub(/^[ \t]+|[ \t]+$/, "", $2)
                gsub(/^[ \t]+|[ \t]+$/, "", $3)

                if ($3 == name) {
                    print $2
                    exit
                }
            }
        '
}

get_subnet_id() {
    local NAME="$1"

    $HAMMER subnet list \
        --search "name=\"${NAME}\"" \
        --per-page 9999 2>/dev/null |
        awk -F'|' -v name="$NAME" '
            NR > 2 {
                gsub(/^[ \t]+|[ \t]+$/, "", $2)
                gsub(/^[ \t]+|[ \t]+$/, "", $3)

                if ($3 == name) {
                    print $2
                    exit
                }
            }
        '
}

get_ptable_id() {
    local NAME="$1"

    $HAMMER partition-table list \
        --search "name=\"${NAME}\"" \
        --per-page 9999 2>/dev/null |
        awk -F'|' -v name="$NAME" '
            NR > 2 {
                gsub(/^[ \t]+|[ \t]+$/, "", $2)
                gsub(/^[ \t]+|[ \t]+$/, "", $3)

                if ($3 == name) {
                    print $2
                    exit
                }
            }
        '
}

get_architecture_id() {
    local NAME="$1"

    $HAMMER architecture list \
        --search "name=\"${NAME}\"" \
        --per-page 9999 2>/dev/null |
        awk -F'|' -v name="$NAME" '
            NR > 2 {
                gsub(/^[ \t]+|[ \t]+$/, "", $2)
                gsub(/^[ \t]+|[ \t]+$/, "", $3)

                if ($3 == name) {
                    print $2
                    exit
                }
            }
        '
}

get_domain_id() {
    local NAME="$1"

    $HAMMER domain list \
        --search "name=\"${NAME}\"" \
        --per-page 9999 2>/dev/null |
        awk -F'|' -v name="$NAME" '
            NR > 2 {
                gsub(/^[ \t]+|[ \t]+$/, "", $2)
                gsub(/^[ \t]+|[ \t]+$/, "", $3)

                if ($3 == name) {
                    print $2
                    exit
                }
            }
        '
}

get_content_view_id() {
    local NAME="$1"

    $HAMMER content-view list \
        --organization "${ORG_NAME}" \
        --search "name=\"${NAME}\"" \
        --per-page 9999 2>/dev/null |
        awk -F'|' -v name="$NAME" '
            NR > 2 {
                gsub(/^[ \t]+|[ \t]+$/, "", $2)
                gsub(/^[ \t]+|[ \t]+$/, "", $3)

                if ($3 == name) {
                    print $2
                    exit
                }
            }
        '
}

get_lifecycle_environment_id() {
    local NAME="$1"

    $HAMMER lifecycle-environment list \
        --organization "${ORG_NAME}" \
        --search "name=\"${NAME}\"" \
        --per-page 9999 2>/dev/null |
        awk -F'|' -v name="$NAME" '
            NR > 2 {
                gsub(/^[ \t]+|[ \t]+$/, "", $2)
                gsub(/^[ \t]+|[ \t]+$/, "", $3)

                if ($3 == name) {
                    print $2
                    exit
                }
            }
        '
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
# GET COMMON IDS
###############################################################################

header "LOOKING UP COMMON FOREMAN IDS"

ORG_ID=$($HAMMER organization list \
    --search "name=\"${ORG_NAME}\"" \
    --per-page 9999 2>/dev/null |
    awk -F'|' -v name="$ORG_NAME" '
        NR > 2 {
            gsub(/^[ \t]+|[ \t]+$/, "", $2)
            gsub(/^[ \t]+|[ \t]+$/, "", $3)
            if ($3 == name) {
                print $2
                exit
            }
        }
    ')

LOCATION_ID=$($HAMMER location list \
    --search "name=\"${LOCATION_NAME}\"" \
    --per-page 9999 2>/dev/null |
    awk -F'|' -v name="$LOCATION_NAME" '
        NR > 2 {
            gsub(/^[ \t]+|[ \t]+$/, "", $2)
            gsub(/^[ \t]+|[ \t]+$/, "", $3)
            if ($3 == name) {
                print $2
                exit
            }
        }
    ')

PTABLE_ID=$(get_ptable_id "${PTABLE_NAME}")
ARCHITECTURE_ID=$(get_architecture_id "${ARCH_NAME}")
DOMAIN_ID=$(get_domain_id "${DOMAIN_NAME}")

LIFECYCLE_ENVIRONMENT_ID=$(get_lifecycle_environment_id "Library")

ok "Organization ID          : ${ORG_ID:-NOT FOUND}"
ok "Location ID              : ${LOCATION_ID:-NOT FOUND}"
ok "Partition Table ID       : ${PTABLE_ID:-NOT FOUND}"
ok "Architecture ID          : ${ARCHITECTURE_ID:-NOT FOUND}"
ok "Domain ID                : ${DOMAIN_ID:-NOT FOUND}"
ok "Lifecycle Environment ID : ${LIFECYCLE_ENVIRONMENT_ID:-NOT FOUND}"

###############################################################################
# CENTOS 7
###############################################################################

CENTOS7_RAID_HG="CentOSLinux7-RAID"
CENTOS7_SINGLE_HG="CentOSLinux7-SingleDisk"

CENTOS7_RAID_OS="CentOSLinux7-RAID 7"
CENTOS7_MEDIUM="CentOS 7 Remote"
CENTOS7_SUBNET="vgs-subnet-centos"

# Change if your actual Content View name differs
CENTOS7_CONTENT_VIEW="CentOS7-CV"

###############################################################################
# ROCKY 8.10
###############################################################################

ROCKY8_RAID_HG="RockyLinux8.10-RAID"
ROCKY8_SINGLE_HG="RockyLinux8.10-SingleDisk"

ROCKY8_RAID_OS="RockyLinux8.10-RAID 8.10"
ROCKY8_MEDIUM="Rocky 8 Remote"
ROCKY8_SUBNET="vgs-subnet-rockyos"

# Change if your actual Content View name differs
ROCKY8_CONTENT_VIEW="Rocky8-CV"

###############################################################################
# ROCKY 9.2
###############################################################################

ROCKY92_RAID_HG="RockyLinux9.2-RAID"
ROCKY92_SINGLE_HG="RockyLinux9.2-SingleDisk"

ROCKY92_RAID_OS="RockyLinux9.2-RAID 9.2"
ROCKY92_MEDIUM="Rocky 9.2 Remote"
ROCKY92_SUBNET="vgs-subnet-rockyos"

# Change if your actual Content View name differs
ROCKY92_CONTENT_VIEW="Rocky9.2-CV"

###############################################################################
# ROCKY 9.8
###############################################################################

ROCKY98_RAID_HG="RockyLinux9.8-RAID"
ROCKY98_SINGLE_HG="RockyLinux9.8-SingleDisk"

ROCKY98_RAID_OS="RockyLinux9.8-RAID 9.8"
ROCKY98_MEDIUM="Rocky 9 Remote"
ROCKY98_SUBNET="vgs-subnet-rockyos"

# Change if your actual Content View name differs
ROCKY98_CONTENT_VIEW="Rocky9.8-CV"

###############################################################################
# LOOKUP CENTOS 7
###############################################################################

separator "Checking CentOS Linux 7"

CENTOS7_RAID_HG_ID=$(get_hostgroup_id "${CENTOS7_RAID_HG}")
CENTOS7_SINGLE_HG_ID=$(get_hostgroup_id "${CENTOS7_SINGLE_HG}")
CENTOS7_OS_ID=$(get_os_id "${CENTOS7_RAID_OS}")
CENTOS7_MEDIUM_ID=$(get_medium_id "${CENTOS7_MEDIUM}")
CENTOS7_SUBNET_ID=$(get_subnet_id "${CENTOS7_SUBNET}")
CENTOS7_CV_ID=$(get_content_view_id "${CENTOS7_CONTENT_VIEW}")

ok "RAID Hostgroup"
echo "     Name : ${CENTOS7_RAID_HG}"
echo "     ID   : ${CENTOS7_RAID_HG_ID:-NOT FOUND}"

ok "SingleDisk Hostgroup"
echo "     Name : ${CENTOS7_SINGLE_HG}"
echo "     ID   : ${CENTOS7_SINGLE_HG_ID:-NOT FOUND}"

echo
echo "     Operating System : ${CENTOS7_RAID_OS}"
echo "     Medium           : ${CENTOS7_MEDIUM}"
echo "     Subnet           : ${CENTOS7_SUBNET}"

ok "Operating System ID : ${CENTOS7_OS_ID:-NOT FOUND}"
ok "Medium ID           : ${CENTOS7_MEDIUM_ID:-NOT FOUND}"
ok "Subnet ID           : ${CENTOS7_SUBNET_ID:-NOT FOUND}"
ok "Content View ID     : ${CENTOS7_CV_ID:-NOT FOUND}"

###############################################################################
# LOOKUP ROCKY 8
###############################################################################

separator "Checking Rocky Linux 8.10"

ROCKY8_RAID_HG_ID=$(get_hostgroup_id "${ROCKY8_RAID_HG}")
ROCKY8_SINGLE_HG_ID=$(get_hostgroup_id "${ROCKY8_SINGLE_HG}")
ROCKY8_OS_ID=$(get_os_id "${ROCKY8_RAID_OS}")
ROCKY8_MEDIUM_ID=$(get_medium_id "${ROCKY8_MEDIUM}")
ROCKY8_SUBNET_ID=$(get_subnet_id "${ROCKY8_SUBNET}")
ROCKY8_CV_ID=$(get_content_view_id "${ROCKY8_CONTENT_VIEW}")

ok "RAID Hostgroup"
echo "     Name : ${ROCKY8_RAID_HG}"
echo "     ID   : ${ROCKY8_RAID_HG_ID:-NOT FOUND}"

ok "SingleDisk Hostgroup"
echo "     Name : ${ROCKY8_SINGLE_HG}"
echo "     ID   : ${ROCKY8_SINGLE_HG_ID:-NOT FOUND}"

echo
echo "     Operating System : ${ROCKY8_RAID_OS}"
echo "     Medium           : ${ROCKY8_MEDIUM}"
echo "     Subnet           : ${ROCKY8_SUBNET}"

ok "Operating System ID : ${ROCKY8_OS_ID:-NOT FOUND}"
ok "Medium ID           : ${ROCKY8_MEDIUM_ID:-NOT FOUND}"
ok "Subnet ID           : ${ROCKY8_SUBNET_ID:-NOT FOUND}"
ok "Content View ID     : ${ROCKY8_CV_ID:-NOT FOUND}"

###############################################################################
# LOOKUP ROCKY 9.2
###############################################################################

separator "Checking Rocky Linux 9.2"

ROCKY92_RAID_HG_ID=$(get_hostgroup_id "${ROCKY92_RAID_HG}")
ROCKY92_SINGLE_HG_ID=$(get_hostgroup_id "${ROCKY92_SINGLE_HG}")
ROCKY92_OS_ID=$(get_os_id "${ROCKY92_RAID_OS}")
ROCKY92_MEDIUM_ID=$(get_medium_id "${ROCKY92_MEDIUM}")
ROCKY92_SUBNET_ID=$(get_subnet_id "${ROCKY92_SUBNET}")
ROCKY92_CV_ID=$(get_content_view_id "${ROCKY92_CONTENT_VIEW}")

ok "RAID Hostgroup"
echo "     Name : ${ROCKY92_RAID_HG}"
echo "     ID   : ${ROCKY92_RAID_HG_ID:-NOT FOUND}"

ok "SingleDisk Hostgroup"
echo "     Name : ${ROCKY92_SINGLE_HG}"
echo "     ID   : ${ROCKY92_SINGLE_HG_ID:-NOT FOUND}"

echo
echo "     Operating System : ${ROCKY92_RAID_OS}"
echo "     Medium           : ${ROCKY92_MEDIUM}"
echo "     Subnet           : ${ROCKY92_SUBNET}"

ok "Operating System ID : ${ROCKY92_OS_ID:-NOT FOUND}"
ok "Medium ID           : ${ROCKY92_MEDIUM_ID:-NOT FOUND}"
ok "Subnet ID           : ${ROCKY92_SUBNET_ID:-NOT FOUND}"
ok "Content View ID     : ${ROCKY92_CV_ID:-NOT FOUND}"

###############################################################################
# LOOKUP ROCKY 9.8
###############################################################################

separator "Checking Rocky Linux 9.8"

ROCKY98_RAID_HG_ID=$(get_hostgroup_id "${ROCKY98_RAID_HG}")
ROCKY98_SINGLE_HG_ID=$(get_hostgroup_id "${ROCKY98_SINGLE_HG}")
ROCKY98_OS_ID=$(get_os_id "${ROCKY98_RAID_OS}")
ROCKY98_MEDIUM_ID=$(get_medium_id "${ROCKY98_MEDIUM}")
ROCKY98_SUBNET_ID=$(get_subnet_id "${ROCKY98_SUBNET}")
ROCKY98_CV_ID=$(get_content_view_id "${ROCKY98_CONTENT_VIEW}")

ok "RAID Hostgroup"
echo "     Name : ${ROCKY98_RAID_HG}"
echo "     ID   : ${ROCKY98_RAID_HG_ID:-NOT FOUND}"

ok "SingleDisk Hostgroup"
echo "     Name : ${ROCKY98_SINGLE_HG}"
echo "     ID   : ${ROCKY98_SINGLE_HG_ID:-NOT FOUND}"

echo
echo "     Operating System : ${ROCKY98_RAID_OS}"
echo "     Medium           : ${ROCKY98_MEDIUM}"
echo "     Subnet           : ${ROCKY98_SUBNET}"

ok "Operating System ID : ${ROCKY98_OS_ID:-NOT FOUND}"
ok "Medium ID           : ${ROCKY98_MEDIUM_ID:-NOT FOUND}"
ok "Subnet ID           : ${ROCKY98_SUBNET_ID:-NOT FOUND}"
ok "Content View ID     : ${ROCKY98_CV_ID:-NOT FOUND}"

###############################################################################
# GENERATED YAML OUTPUT
###############################################################################

header "GENERATED AWX / ANSIBLE VARIABLES"

cat <<EOF

    # ==========================================================================
    # CentOS Linux 7 Host Group / OS Selection
    #
    # AWX Survey:
    #
    # 1 = ${CENTOS7_SINGLE_HG}
    # 2 = ${CENTOS7_RAID_HG}
    #
    # ==========================================================================

    hostgroup: "{{ hostgroup | default('1', true) }}"

    hostgroup_id: >-
      {{
        {{
          '1': ${CENTOS7_SINGLE_HG_ID},
          '2': ${CENTOS7_RAID_HG_ID}
        }}[hostgroup | string]
      }}

    # ${CENTOS7_RAID_OS}
    #
    # OS ID is common for both RAID and SingleDisk provisioning.
    #
    operatingsystem_id: ${CENTOS7_OS_ID}

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


    # ==========================================================================
    # Rocky Linux 8.10 Host Group / OS Selection
    #
    # AWX Survey:
    #
    # 1 = ${ROCKY8_SINGLE_HG}
    # 2 = ${ROCKY8_RAID_HG}
    #
    # ==========================================================================

    hostgroup: "{{ hostgroup | default('1', true) }}"

    hostgroup_id: >-
      {{
        {{
          '1': ${ROCKY8_SINGLE_HG_ID},
          '2': ${ROCKY8_RAID_HG_ID}
        }}[hostgroup | string]
      }}

    # ${ROCKY8_RAID_OS}
    #
    # OS ID is common for both RAID and SingleDisk provisioning.
    #
    operatingsystem_id: ${ROCKY8_OS_ID}

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


    # ==========================================================================
    # Rocky Linux 9.2 Host Group / OS Selection
    #
    # AWX Survey:
    #
    # 1 = ${ROCKY92_SINGLE_HG}
    # 2 = ${ROCKY92_RAID_HG}
    #
    # ==========================================================================

    hostgroup: "{{ hostgroup | default('1', true) }}"

    hostgroup_id: >-
      {{
        {{
          '1': ${ROCKY92_SINGLE_HG_ID},
          '2': ${ROCKY92_RAID_HG_ID}
        }}[hostgroup | string]
      }}

    # ${ROCKY92_RAID_OS}
    #
    # OS ID is common for both RAID and SingleDisk provisioning.
    #
    operatingsystem_id: ${ROCKY92_OS_ID}

    # ${ROCKY92_MEDIUM}
    medium_id: ${ROCKY92_MEDIUM_ID}

    # ${PTABLE_NAME}
    ptable_id: ${PTABLE_ID}

    # Rocky Linux 9 subnet
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


    # ==========================================================================
    # Rocky Linux 9.8 Host Group / OS Selection
    #
    # AWX Survey:
    #
    # 1 = ${ROCKY98_SINGLE_HG}
    # 2 = ${ROCKY98_RAID_HG}
    #
    # ==========================================================================

    hostgroup: "{{ hostgroup | default('1', true) }}"

    hostgroup_id: >-
      {{
        {{
          '1': ${ROCKY98_SINGLE_HG_ID},
          '2': ${ROCKY98_RAID_HG_ID}
        }}[hostgroup | string]
      }}

    # ${ROCKY98_RAID_OS}
    #
    # OS ID is common for both RAID and SingleDisk provisioning.
    #
    operatingsystem_id: ${ROCKY98_OS_ID}

    # ${ROCKY98_MEDIUM}
    medium_id: ${ROCKY98_MEDIUM_ID}

    # ${PTABLE_NAME}
    ptable_id: ${PTABLE_ID}

    # Rocky Linux 9 subnet
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
# COMPLETED
###############################################################################

header "FOREMAN ID LOOKUP COMPLETED SUCCESSFULLY"
