#!/bin/bash

###############################################################################
# Foreman Dynamic ID Lookup
#
# Usage:
#   ./get_foreman_ids.sh "VGS HOSTS ROCKY 9.2"
#   ./get_foreman_ids.sh "VGS HOSTS ROCKY 9.8"
#   ./get_foreman_ids.sh "VGS HOSTS ROCKY 8"
#   ./get_foreman_ids.sh "VGS HOSTS CENTOS 7"
###############################################################################

FOREMAN_SERVER="https://cent-07-01.vgs.com"
FOREMAN_USER="admin"
FOREMAN_PASS="zqs977dXzqfEvTML"

HOSTGROUP="$1"

if [[ -z "$HOSTGROUP" ]]; then
    echo
    echo "Usage:"
    echo "  $0 \"VGS HOSTS ROCKY 9.2\""
    echo "  $0 \"VGS HOSTS ROCKY 9.8\""
    echo "  $0 \"VGS HOSTS ROCKY 8\""
    echo "  $0 \"VGS HOSTS CENTOS 7\""
    echo
    exit 1
fi

###############################################################################
# Get Host Group Information
###############################################################################

HG_INFO=$(hammer \
    --server "$FOREMAN_SERVER" \
    --username "$FOREMAN_USER" \
    --password "$FOREMAN_PASS" \
    hostgroup info --name "$HOSTGROUP" 2>/dev/null)

if [[ $? -ne 0 || -z "$HG_INFO" ]]; then
    echo "ERROR: Host Group '$HOSTGROUP' not found."
    exit 1
fi

###############################################################################
# Extract Information
###############################################################################

HOSTGROUP_ID=$(echo "$HG_INFO" | awk -F': *' '/^Id:/ {print $2}')

OS_NAME=$(echo "$HG_INFO" | awk -F': *' '/Operating System:/ {print $2}')

MEDIUM_NAME=$(echo "$HG_INFO" | awk -F': *' '/Medium:/ {print $2}')

PTABLE_NAME=$(echo "$HG_INFO" | awk -F': *' '/Partition Table:/ {print $2}')

ARCH_NAME=$(echo "$HG_INFO" | awk -F': *' '/Architecture:/ {print $2}')

PXE_LOADER=$(echo "$HG_INFO" | awk -F': *' '/PXE Loader:/ {print $2}')

###############################################################################
# Get OS ID
###############################################################################

OS_ID=$(hammer \
    --server "$FOREMAN_SERVER" \
    --username "$FOREMAN_USER" \
    --password "$FOREMAN_PASS" \
    os list | \
    awk -F'|' -v os="$OS_NAME" '
        {
            gsub(/^ +| +$/, "", $2)
            gsub(/^ +| +$/, "", $1)
            if ($2==os)
                print $1
        }')

###############################################################################
# Get Medium ID
###############################################################################

MEDIUM_ID=$(hammer \
    --server "$FOREMAN_SERVER" \
    --username "$FOREMAN_USER" \
    --password "$FOREMAN_PASS" \
    medium list | \
    awk -F'|' -v m="$MEDIUM_NAME" '
        {
            gsub(/^ +| +$/, "", $2)
            gsub(/^ +| +$/, "", $1)
            if ($2==m)
                print $1
        }')

###############################################################################
# Get Partition Table ID
###############################################################################

PTABLE_ID=$(hammer \
    --server "$FOREMAN_SERVER" \
    --username "$FOREMAN_USER" \
    --password "$FOREMAN_PASS" \
    partition-table list | \
    awk -F'|' -v p="$PTABLE_NAME" '
        {
            gsub(/^ +| +$/, "", $2)
            gsub(/^ +| +$/, "", $1)
            if ($2==p)
                print $1
        }')

###############################################################################
# Get Architecture ID
###############################################################################

ARCH_ID=$(hammer \
    --server "$FOREMAN_SERVER" \
    --username "$FOREMAN_USER" \
    --password "$FOREMAN_PASS" \
    architecture list | \
    awk -F'|' -v a="$ARCH_NAME" '
        {
            gsub(/^ +| +$/, "", $2)
            gsub(/^ +| +$/, "", $1)
            if ($2==a)
                print $1
        }')

###############################################################################
# Display
###############################################################################

echo
echo "============================================================"
echo "Foreman Configuration"
echo "============================================================"
echo "Host Group      : $HOSTGROUP"
echo "Host Group ID   : $HOSTGROUP_ID"
echo
echo "Operating System: $OS_NAME"
echo "OS ID           : $OS_ID"
echo
echo "Medium          : $MEDIUM_NAME"
echo "Medium ID       : $MEDIUM_ID"
echo
echo "Architecture    : $ARCH_NAME"
echo "Architecture ID : $ARCH_ID"
echo
echo "Partition Table : $PTABLE_NAME"
echo "Partition ID    : $PTABLE_ID"
echo
echo "PXE Loader      : $PXE_LOADER"
echo "============================================================"

###############################################################################
# Ansible Variables
###############################################################################

echo
echo "Ansible Variables"
echo "-----------------"

cat <<EOF
hostgroup_id: $HOSTGROUP_ID
operatingsystem_id: $OS_ID
medium_id: $MEDIUM_ID
ptable_id: $PTABLE_ID
architecture_id: $ARCH_ID
pxe_loader: "$PXE_LOADER"
EOF
