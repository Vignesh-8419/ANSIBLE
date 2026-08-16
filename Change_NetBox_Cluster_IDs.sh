#!/bin/bash
set -euo pipefail

############################################################
# NETBOX CLUSTER ID REMAPPING
#
# centos-07-servers : 7 -> 1
# rocky-8-servers   : 8 -> 2
# rocky-9-servers   : 9 -> 3
#
# Cluster Group IDs are already:
# centos-07-servers : 1
# rocky-8-servers   : 2
# rocky-9-servers   : 3
#
# This script also updates:
# - dcim_device.cluster_id
# - virtualization_virtualmachine.cluster_id
############################################################

DB_NAME="netbox"
PG_BIN="/usr/pgsql-15/bin"

BACKUP_DIR="/root/netbox-backup"

NETBOX_SERVICE="netbox"
NETBOX_WORKER_SERVICE="netbox-worker"

CENTOS_NAME="centos-07-servers"
ROCKY8_NAME="rocky-8-servers"
ROCKY9_NAME="rocky-9-servers"

CENTOS_NEW_ID=1
ROCKY8_NEW_ID=2
ROCKY9_NEW_ID=3

TEMP_CENTOS_ID=10001
TEMP_ROCKY8_ID=10002
TEMP_ROCKY9_ID=10003

############################################################
# COLORS
############################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

############################################################
# DISPLAY FUNCTIONS
############################################################

print_line() {
    printf "%b\n" "${BLUE}=================================================================${NC}"
}

header() {
    echo
    print_line
    printf "%b\n" "${CYAN}$1${NC}"
    print_line
    echo
}

info() {
    printf "%b\n" "${GREEN}[INFO] $1${NC}"
}

warn() {
    printf "%b\n" "${YELLOW}[WARN] $1${NC}"
}

error() {
    printf "%b\n" "${RED}[ERROR] $1${NC}"
}

############################################################
# ROOT CHECK
############################################################

header "NETBOX CLUSTER ID REMAPPING"

if [[ "${EUID}" -ne 0 ]]; then
    error "Run this script as root"
    exit 1
fi

info "Running as root"

############################################################
# POSTGRESQL CHECK
############################################################

header "CHECKING POSTGRESQL"

if [[ ! -x "${PG_BIN}/psql" ]]; then
    error "psql not found: ${PG_BIN}/psql"
    exit 1
fi

if [[ ! -x "${PG_BIN}/pg_dump" ]]; then
    error "pg_dump not found: ${PG_BIN}/pg_dump"
    exit 1
fi

if ! systemctl is-active --quiet postgresql-15; then
    error "PostgreSQL 15 is not running"
    exit 1
fi

info "PostgreSQL 15 is running"

############################################################
# DATABASE CHECK
############################################################

header "CHECKING NETBOX DATABASE"

DB_EXISTS=$(
    su - postgres -c \
    "${PG_BIN}/psql -tAc \"SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'\""
)

if [[ "${DB_EXISTS}" != "1" ]]; then
    error "Database '${DB_NAME}' not found"
    exit 1
fi

info "Database '${DB_NAME}' found"

############################################################
# TABLE CHECK
############################################################

header "CHECKING NETBOX DATABASE TABLES"

REQUIRED_TABLES=(
    "virtualization_cluster"
    "virtualization_virtualmachine"
    "dcim_device"
)

for TABLE in "${REQUIRED_TABLES[@]}"; do

    TABLE_EXISTS=$(
        su - postgres -c \
        "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
        SELECT COUNT(*)
        FROM information_schema.tables
        WHERE table_schema='public'
          AND table_name='${TABLE}'
        \""
    )

    if [[ "${TABLE_EXISTS}" != "1" ]]; then
        error "Required table not found: ${TABLE}"
        exit 1
    fi

    info "Found table: ${TABLE}"

done

############################################################
# CURRENT CLUSTERS
############################################################

header "CURRENT NETBOX CLUSTERS"

su - postgres -c \
"${PG_BIN}/psql -d ${DB_NAME} -c \"
SELECT
    c.id,
    c.name,
    ct.name AS cluster_type,
    c.status,
    c.group_id,
    g.name AS group_name
FROM virtualization_cluster c
LEFT JOIN virtualization_clustertype ct
    ON c.type_id = ct.id
LEFT JOIN virtualization_clustergroup g
    ON c.group_id = g.id
ORDER BY c.id;
\""

############################################################
# VALIDATE REQUIRED CLUSTERS
############################################################

header "VALIDATING REQUIRED CLUSTERS"

for CLUSTER_NAME in \
    "${CENTOS_NAME}" \
    "${ROCKY8_NAME}" \
    "${ROCKY9_NAME}"
do

    COUNT=$(
        su - postgres -c \
        "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
        SELECT COUNT(*)
        FROM virtualization_cluster
        WHERE name='${CLUSTER_NAME}'
        \""
    )

    if [[ "${COUNT}" != "1" ]]; then
        error "Expected exactly one cluster named '${CLUSTER_NAME}'"
        error "Found: ${COUNT}"
        exit 1
    fi

done

info "All required clusters found"

############################################################
# GET CURRENT IDS
############################################################

header "CHECKING CURRENT CLUSTER IDS"

CENTOS_CURRENT_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id
    FROM virtualization_cluster
    WHERE name='${CENTOS_NAME}'
    \""
)

ROCKY8_CURRENT_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id
    FROM virtualization_cluster
    WHERE name='${ROCKY8_NAME}'
    \""
)

ROCKY9_CURRENT_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id
    FROM virtualization_cluster
    WHERE name='${ROCKY9_NAME}'
    \""
)

info "${CENTOS_NAME} current Cluster ID: ${CENTOS_CURRENT_ID}"
info "${ROCKY8_NAME} current Cluster ID: ${ROCKY8_CURRENT_ID}"
info "${ROCKY9_NAME} current Cluster ID: ${ROCKY9_CURRENT_ID}"

############################################################
# ALREADY CORRECT CHECK
############################################################

if [[ "${CENTOS_CURRENT_ID}" == "1" &&
      "${ROCKY8_CURRENT_ID}" == "2" &&
      "${ROCKY9_CURRENT_ID}" == "3" ]]; then

    header "CLUSTER IDS ALREADY CORRECT"

    info "${CENTOS_NAME}: ID 1"
    info "${ROCKY8_NAME}: ID 2"
    info "${ROCKY9_NAME}: ID 3"

    exit 0
fi

############################################################
# CHECK TARGET IDS
############################################################

header "CHECKING TARGET CLUSTER IDS"

check_target_id() {

    local TARGET_ID="$1"
    local EXPECTED_NAME="$2"

    EXISTING_NAME=$(
        su - postgres -c \
        "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
        SELECT COALESCE(name,'')
        FROM virtualization_cluster
        WHERE id=${TARGET_ID}
        \""
    )

    if [[ -n "${EXISTING_NAME}" &&
          "${EXISTING_NAME}" != "${EXPECTED_NAME}" ]]; then

        error "Target Cluster ID ${TARGET_ID} is already used by '${EXISTING_NAME}'"
        exit 1

    fi

    if [[ -z "${EXISTING_NAME}" ]]; then
        info "Target Cluster ID ${TARGET_ID} is available"
    else
        info "Target Cluster ID ${TARGET_ID} already correctly assigned"
    fi
}

check_target_id 1 "${CENTOS_NAME}"
check_target_id 2 "${ROCKY8_NAME}"
check_target_id 3 "${ROCKY9_NAME}"

############################################################
# CHECK TEMPORARY IDS
############################################################

header "CHECKING TEMPORARY IDS"

for TEMP_ID in \
    "${TEMP_CENTOS_ID}" \
    "${TEMP_ROCKY8_ID}" \
    "${TEMP_ROCKY9_ID}"
do

    COUNT=$(
        su - postgres -c \
        "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
        SELECT COUNT(*)
        FROM virtualization_cluster
        WHERE id=${TEMP_ID}
        \""
    )

    if [[ "${COUNT}" != "0" ]]; then
        error "Temporary ID ${TEMP_ID} is already in use"
        exit 1
    fi

    info "Temporary Cluster ID ${TEMP_ID} is available"

done

############################################################
# CHECK DEPENDENCIES
############################################################

header "CHECKING CLUSTER DEPENDENCIES"

CENTOS_DEVICES=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT COUNT(*)
    FROM dcim_device
    WHERE cluster_id=${CENTOS_CURRENT_ID}
    \""
)

ROCKY8_DEVICES=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT COUNT(*)
    FROM dcim_device
    WHERE cluster_id=${ROCKY8_CURRENT_ID}
    \""
)

ROCKY9_DEVICES=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT COUNT(*)
    FROM dcim_device
    WHERE cluster_id=${ROCKY9_CURRENT_ID}
    \""
)

CENTOS_VMS=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT COUNT(*)
    FROM virtualization_virtualmachine
    WHERE cluster_id=${CENTOS_CURRENT_ID}
    \""
)

ROCKY8_VMS=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT COUNT(*)
    FROM virtualization_virtualmachine
    WHERE cluster_id=${ROCKY8_CURRENT_ID}
    \""
)

ROCKY9_VMS=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT COUNT(*)
    FROM virtualization_virtualmachine
    WHERE cluster_id=${ROCKY9_CURRENT_ID}
    \""
)

info "${CENTOS_NAME} Devices: ${CENTOS_DEVICES}"
info "${ROCKY8_NAME} Devices: ${ROCKY8_DEVICES}"
info "${ROCKY9_NAME} Devices: ${ROCKY9_DEVICES}"

info "${CENTOS_NAME} Virtual Machines: ${CENTOS_VMS}"
info "${ROCKY8_NAME} Virtual Machines: ${ROCKY8_VMS}"
info "${ROCKY9_NAME} Virtual Machines: ${ROCKY9_VMS}"

############################################################
# DATABASE BACKUP
############################################################

header "CREATING NETBOX DATABASE BACKUP"

mkdir -p "${BACKUP_DIR}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

BACKUP_FILE="${BACKUP_DIR}/netbox_before_cluster_id_change_${TIMESTAMP}.dump"

su - postgres -c \
"${PG_BIN}/pg_dump -Fc ${DB_NAME}" > "${BACKUP_FILE}"

chmod 600 "${BACKUP_FILE}"

if [[ ! -s "${BACKUP_FILE}" ]]; then
    error "Database backup failed"
    exit 1
fi

info "Database backup completed successfully"
info "Backup file: ${BACKUP_FILE}"

############################################################
# REMAPPING PLAN
############################################################

header "CLUSTER ID REMAPPING PLAN"

echo
printf "%-28s %-15s %-15s\n" "CLUSTER" "CURRENT ID" "NEW ID"
echo "---------------------------------------------------------------"

printf "%-28s %-15s %-15s\n" \
    "${CENTOS_NAME}" \
    "${CENTOS_CURRENT_ID}" \
    "1"

printf "%-28s %-15s %-15s\n" \
    "${ROCKY8_NAME}" \
    "${ROCKY8_CURRENT_ID}" \
    "2"

printf "%-28s %-15s %-15s\n" \
    "${ROCKY9_NAME}" \
    "${ROCKY9_CURRENT_ID}" \
    "3"

echo

warn "Cluster Group IDs remain unchanged."
warn "Device and Virtual Machine cluster references will also be updated."

############################################################
# CONFIRMATION
############################################################

read -rp "Continue with Cluster ID remapping? Type YES: " CONFIRM

if [[ "${CONFIRM}" != "YES" ]]; then
    warn "Operation cancelled"
    exit 0
fi

############################################################
# STOP NETBOX
############################################################

header "STOPPING NETBOX SERVICES"

systemctl stop "${NETBOX_SERVICE}" || true
systemctl stop "${NETBOX_WORKER_SERVICE}" || true

info "NetBox services stopped"

############################################################
# REMAPPING
#
# Temporarily disable FK triggers in the database session.
# All references are updated in the same transaction.
############################################################

header "REMAPPING NETBOX CLUSTER IDS"

su - postgres -c \
"${PG_BIN}/psql -v ON_ERROR_STOP=1 -d ${DB_NAME}" <<SQL

BEGIN;

------------------------------------------------------------
-- Temporarily disable FK enforcement for this session.
-- Required because dcim_device.cluster_id references
-- virtualization_cluster.id without ON UPDATE CASCADE.
------------------------------------------------------------

SET session_replication_role = replica;

------------------------------------------------------------
-- PHASE 1
-- Move all child references to temporary IDs
------------------------------------------------------------

UPDATE dcim_device
SET cluster_id=${TEMP_CENTOS_ID}
WHERE cluster_id=${CENTOS_CURRENT_ID};

UPDATE dcim_device
SET cluster_id=${TEMP_ROCKY8_ID}
WHERE cluster_id=${ROCKY8_CURRENT_ID};

UPDATE dcim_device
SET cluster_id=${TEMP_ROCKY9_ID}
WHERE cluster_id=${ROCKY9_CURRENT_ID};

UPDATE virtualization_virtualmachine
SET cluster_id=${TEMP_CENTOS_ID}
WHERE cluster_id=${CENTOS_CURRENT_ID};

UPDATE virtualization_virtualmachine
SET cluster_id=${TEMP_ROCKY8_ID}
WHERE cluster_id=${ROCKY8_CURRENT_ID};

UPDATE virtualization_virtualmachine
SET cluster_id=${TEMP_ROCKY9_ID}
WHERE cluster_id=${ROCKY9_CURRENT_ID};

------------------------------------------------------------
-- PHASE 2
-- Move parent clusters to temporary IDs
------------------------------------------------------------

UPDATE virtualization_cluster
SET id=${TEMP_CENTOS_ID}
WHERE id=${CENTOS_CURRENT_ID}
  AND name='${CENTOS_NAME}';

UPDATE virtualization_cluster
SET id=${TEMP_ROCKY8_ID}
WHERE id=${ROCKY8_CURRENT_ID}
  AND name='${ROCKY8_NAME}';

UPDATE virtualization_cluster
SET id=${TEMP_ROCKY9_ID}
WHERE id=${ROCKY9_CURRENT_ID}
  AND name='${ROCKY9_NAME}';

------------------------------------------------------------
-- PHASE 3
-- Assign final Cluster IDs
------------------------------------------------------------

UPDATE virtualization_cluster
SET id=1
WHERE id=${TEMP_CENTOS_ID}
  AND name='${CENTOS_NAME}';

UPDATE virtualization_cluster
SET id=2
WHERE id=${TEMP_ROCKY8_ID}
  AND name='${ROCKY8_NAME}';

UPDATE virtualization_cluster
SET id=3
WHERE id=${TEMP_ROCKY9_ID}
  AND name='${ROCKY9_NAME}';

------------------------------------------------------------
-- PHASE 4
-- Update child references to final IDs
------------------------------------------------------------

UPDATE dcim_device
SET cluster_id=1
WHERE cluster_id=${TEMP_CENTOS_ID};

UPDATE dcim_device
SET cluster_id=2
WHERE cluster_id=${TEMP_ROCKY8_ID};

UPDATE dcim_device
SET cluster_id=3
WHERE cluster_id=${TEMP_ROCKY9_ID};

UPDATE virtualization_virtualmachine
SET cluster_id=1
WHERE cluster_id=${TEMP_CENTOS_ID};

UPDATE virtualization_virtualmachine
SET cluster_id=2
WHERE cluster_id=${TEMP_ROCKY8_ID};

UPDATE virtualization_virtualmachine
SET cluster_id=3
WHERE cluster_id=${TEMP_ROCKY9_ID};

------------------------------------------------------------
-- PHASE 5
-- Restore normal trigger / FK enforcement
------------------------------------------------------------

SET session_replication_role = origin;

------------------------------------------------------------
-- PHASE 6
-- Reset Cluster ID sequence
------------------------------------------------------------

SELECT setval(
    pg_get_serial_sequence('virtualization_cluster', 'id'),
    COALESCE(
        (SELECT MAX(id) FROM virtualization_cluster),
        1
    ),
    true
);

COMMIT;

SQL

info "Database Cluster ID remapping completed successfully"

############################################################
# VERIFY CLUSTERS
############################################################

header "VERIFYING FINAL NETBOX CLUSTERS"

su - postgres -c \
"${PG_BIN}/psql -d ${DB_NAME} -c \"
SELECT
    c.id,
    c.name,
    c.group_id,
    g.name AS group_name,
    (
        SELECT COUNT(*)
        FROM dcim_device d
        WHERE d.cluster_id=c.id
    ) AS devices,
    (
        SELECT COUNT(*)
        FROM virtualization_virtualmachine vm
        WHERE vm.cluster_id=c.id
    ) AS virtual_machines
FROM virtualization_cluster c
LEFT JOIN virtualization_clustergroup g
    ON g.id=c.group_id
WHERE c.name IN (
    '${CENTOS_NAME}',
    '${ROCKY8_NAME}',
    '${ROCKY9_NAME}'
)
ORDER BY c.id;
\""

############################################################
# VERIFY FINAL IDS
############################################################

header "FINAL VALIDATION"

FINAL_CENTOS_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id FROM virtualization_cluster
    WHERE name='${CENTOS_NAME}'
    \""
)

FINAL_ROCKY8_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id FROM virtualization_cluster
    WHERE name='${ROCKY8_NAME}'
    \""
)

FINAL_ROCKY9_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id FROM virtualization_cluster
    WHERE name='${ROCKY9_NAME}'
    \""
)

if [[ "${FINAL_CENTOS_ID}" != "1" ||
      "${FINAL_ROCKY8_ID}" != "2" ||
      "${FINAL_ROCKY9_ID}" != "3" ]]; then

    error "FINAL VALIDATION FAILED"
    exit 1
fi

info "centos-07-servers Cluster ID verified: 1"
info "rocky-8-servers Cluster ID verified: 2"
info "rocky-9-servers Cluster ID verified: 3"

############################################################
# VERIFY NO OLD REFERENCES
############################################################

OLD_REFERENCES=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT
        (SELECT COUNT(*)
         FROM dcim_device
         WHERE cluster_id IN (
             ${CENTOS_CURRENT_ID},
             ${ROCKY8_CURRENT_ID},
             ${ROCKY9_CURRENT_ID}
         ))
        +
        (SELECT COUNT(*)
         FROM virtualization_virtualmachine
         WHERE cluster_id IN (
             ${CENTOS_CURRENT_ID},
             ${ROCKY8_CURRENT_ID},
             ${ROCKY9_CURRENT_ID}
         ))
    \""
)

if [[ "${OLD_REFERENCES}" != "0" ]]; then
    error "Old Cluster ID references still exist: ${OLD_REFERENCES}"
    exit 1
fi

info "No old Cluster ID references remain"

############################################################
# START NETBOX
############################################################

header "STARTING NETBOX SERVICES"

systemctl start "${NETBOX_SERVICE}"
systemctl start "${NETBOX_WORKER_SERVICE}"

sleep 5

if ! systemctl is-active --quiet "${NETBOX_SERVICE}"; then
    error "netbox service failed to start"
    exit 1
fi

if ! systemctl is-active --quiet "${NETBOX_WORKER_SERVICE}"; then
    error "netbox-worker service failed to start"
    exit 1
fi

info "netbox service: RUNNING"
info "netbox-worker service: RUNNING"

############################################################
# FINAL SUMMARY
############################################################

header "NETBOX CLUSTER ID REMAPPING COMPLETE"

printf "%b\n" "${GREEN}============================================================${NC}"
printf "%b\n" "${GREEN} CLUSTER                      FINAL ID${NC}"
printf "%b\n" "${GREEN}============================================================${NC}"
printf "%b\n" "${GREEN} centos-07-servers            1${NC}"
printf "%b\n" "${GREEN} rocky-8-servers              2${NC}"
printf "%b\n" "${GREEN} rocky-9-servers              3${NC}"
printf "%b\n" "${GREEN}============================================================${NC}"

echo
info "Cluster Group IDs remain:"
info "centos-07-servers -> 1"
info "rocky-8-servers   -> 2"
info "rocky-9-servers   -> 3"

echo
info "Backup retained at:"
info "${BACKUP_FILE}"

exit 0
