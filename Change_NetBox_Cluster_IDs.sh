#!/bin/bash
set -euo pipefail

############################################################
# NETBOX CLUSTER ID REMAPPING SCRIPT
#
# NetBox: v4.4.9
# PostgreSQL: 15
#
# REQUIRED CLUSTER ID MAPPING
#
# centos-07-servers -> ID 1
# rocky-8-servers   -> ID 2
# rocky-9-servers   -> ID 3
#
# This script changes ONLY:
#   virtualization_cluster.id
#
# It does NOT change:
#   virtualization_clustergroup.id
############################################################

DB_NAME="netbox"
PG_BIN="/usr/pgsql-15/bin"

NETBOX_SERVICE="netbox"
NETBOX_WORKER_SERVICE="netbox-worker"

BACKUP_DIR="/root/netbox-backup"

# Temporary IDs
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
# FUNCTIONS
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
    error "Run this script as root."
    exit 1
fi

info "Running as root"

############################################################
# CHECK POSTGRESQL
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
    error "PostgreSQL 15 is not running."
    exit 1
fi

info "PostgreSQL 15 is running"

############################################################
# CHECK NETBOX DATABASE
############################################################

header "CHECKING NETBOX DATABASE"

DB_EXISTS=$(
    su - postgres -c \
    "${PG_BIN}/psql -tAc \"SELECT 1 FROM pg_database WHERE datname='${DB_NAME}';\""
)

if [[ "${DB_EXISTS}" != "1" ]]; then
    error "Database '${DB_NAME}' does not exist."
    exit 1
fi

info "Database '${DB_NAME}' found"

############################################################
# CHECK REQUIRED TABLES
############################################################

header "CHECKING NETBOX DATABASE TABLES"

for TABLE in \
    virtualization_cluster \
    virtualization_clustertype \
    virtualization_virtualmachine
do
    TABLE_EXISTS=$(
        su - postgres -c \
        "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
        SELECT COUNT(*)
        FROM information_schema.tables
        WHERE table_schema='public'
          AND table_name='${TABLE}';
        \""
    )

    if [[ "${TABLE_EXISTS}" != "1" ]]; then
        error "Required table not found: ${TABLE}"
        exit 1
    fi

    info "Found table: ${TABLE}"
done

############################################################
# CURRENT NETBOX CLUSTERS
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

CENTOS_COUNT=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT COUNT(*)
    FROM virtualization_cluster
    WHERE name='centos-07-servers';
    \""
)

ROCKY8_COUNT=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT COUNT(*)
    FROM virtualization_cluster
    WHERE name='rocky-8-servers';
    \""
)

ROCKY9_COUNT=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT COUNT(*)
    FROM virtualization_cluster
    WHERE name='rocky-9-servers';
    \""
)

if [[ "${CENTOS_COUNT}" != "1" ]]; then
    error "Expected exactly one cluster: centos-07-servers"
    error "Found: ${CENTOS_COUNT}"
    exit 1
fi

if [[ "${ROCKY8_COUNT}" != "1" ]]; then
    error "Expected exactly one cluster: rocky-8-servers"
    error "Found: ${ROCKY8_COUNT}"
    exit 1
fi

if [[ "${ROCKY9_COUNT}" != "1" ]]; then
    error "Expected exactly one cluster: rocky-9-servers"
    error "Found: ${ROCKY9_COUNT}"
    exit 1
fi

info "All required clusters found"

############################################################
# GET CURRENT CLUSTER IDs
############################################################

header "CHECKING CURRENT CLUSTER IDS"

CENTOS_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id
    FROM virtualization_cluster
    WHERE name='centos-07-servers';
    \""
)

ROCKY8_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id
    FROM virtualization_cluster
    WHERE name='rocky-8-servers';
    \""
)

ROCKY9_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id
    FROM virtualization_cluster
    WHERE name='rocky-9-servers';
    \""
)

info "centos-07-servers current Cluster ID: ${CENTOS_ID}"
info "rocky-8-servers current Cluster ID: ${ROCKY8_ID}"
info "rocky-9-servers current Cluster ID: ${ROCKY9_ID}"

############################################################
# CHECK IF ALREADY CORRECT
############################################################

if [[ "${CENTOS_ID}" == "1" &&
      "${ROCKY8_ID}" == "2" &&
      "${ROCKY9_ID}" == "3" ]]; then

    header "CLUSTER IDS ALREADY CORRECT"

    info "centos-07-servers -> Cluster ID 1"
    info "rocky-8-servers   -> Cluster ID 2"
    info "rocky-9-servers   -> Cluster ID 3"

    exit 0
fi

############################################################
# CHECK TARGET IDs
############################################################

header "CHECKING TARGET CLUSTER IDS"

check_target_id() {
    local TARGET_ID="$1"
    local EXPECTED_NAME="$2"
    local EXISTING_NAME

    EXISTING_NAME=$(
        su - postgres -c \
        "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
        SELECT COALESCE(name, '')
        FROM virtualization_cluster
        WHERE id=${TARGET_ID};
        \""
    )

    if [[ -n "${EXISTING_NAME}" &&
          "${EXISTING_NAME}" != "${EXPECTED_NAME}" ]]; then

        error "Target Cluster ID ${TARGET_ID} is already used by:"
        error "${EXISTING_NAME}"
        error "Cannot continue safely."
        exit 1
    fi

    if [[ -z "${EXISTING_NAME}" ]]; then
        info "Target Cluster ID ${TARGET_ID} is available"
    else
        info "Target Cluster ID ${TARGET_ID} already belongs to ${EXPECTED_NAME}"
    fi
}

check_target_id 1 "centos-07-servers"
check_target_id 2 "rocky-8-servers"
check_target_id 3 "rocky-9-servers"

############################################################
# CHECK TEMPORARY IDs
############################################################

header "CHECKING TEMPORARY IDS"

for TEMP_ID in \
    "${TEMP_CENTOS_ID}" \
    "${TEMP_ROCKY8_ID}" \
    "${TEMP_ROCKY9_ID}"
do

    TEMP_EXISTS=$(
        su - postgres -c \
        "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
        SELECT COUNT(*)
        FROM virtualization_cluster
        WHERE id=${TEMP_ID};
        \""
    )

    if [[ "${TEMP_EXISTS}" != "0" ]]; then
        error "Temporary ID ${TEMP_ID} is already in use."
        exit 1
    fi

    info "Temporary Cluster ID ${TEMP_ID} is available"
done

############################################################
# CHECK VM DEPENDENCIES
############################################################

header "CHECKING CLUSTER DEPENDENCIES"

VM_COUNT_CENTOS=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT COUNT(*)
    FROM virtualization_virtualmachine
    WHERE cluster_id=${CENTOS_ID};
    \""
)

VM_COUNT_ROCKY8=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT COUNT(*)
    FROM virtualization_virtualmachine
    WHERE cluster_id=${ROCKY8_ID};
    \""
)

VM_COUNT_ROCKY9=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT COUNT(*)
    FROM virtualization_virtualmachine
    WHERE cluster_id=${ROCKY9_ID};
    \""
)

info "centos-07-servers Virtual Machines: ${VM_COUNT_CENTOS}"
info "rocky-8-servers Virtual Machines: ${VM_COUNT_ROCKY8}"
info "rocky-9-servers Virtual Machines: ${VM_COUNT_ROCKY9}"

############################################################
# CREATE DATABASE BACKUP
############################################################

header "CREATING NETBOX DATABASE BACKUP"

mkdir -p "${BACKUP_DIR}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/netbox_before_cluster_id_change_${TIMESTAMP}.dump"

su - postgres -c \
"${PG_BIN}/pg_dump -Fc ${DB_NAME}" > "${BACKUP_FILE}"

chmod 600 "${BACKUP_FILE}"

if [[ ! -s "${BACKUP_FILE}" ]]; then
    error "Database backup failed or is empty."
    exit 1
fi

info "Database backup completed successfully"
info "Backup file: ${BACKUP_FILE}"

############################################################
# DISPLAY REMAPPING PLAN
############################################################

header "CLUSTER ID REMAPPING PLAN"

echo
printf "%-28s %-16s %-10s\n" "CLUSTER" "CURRENT ID" "NEW ID"
echo "---------------------------------------------------------------"

printf "%-28s %-16s %-10s\n" \
    "centos-07-servers" "${CENTOS_ID}" "1"

printf "%-28s %-16s %-10s\n" \
    "rocky-8-servers" "${ROCKY8_ID}" "2"

printf "%-28s %-16s %-10s\n" \
    "rocky-9-servers" "${ROCKY9_ID}" "3"

echo

warn "Only Cluster IDs will be changed."
warn "Cluster Group IDs will NOT be changed."

############################################################
# CONFIRMATION
############################################################

read -rp "Continue with Cluster ID remapping? Type YES: " CONFIRM

if [[ "${CONFIRM}" != "YES" ]]; then
    warn "Operation cancelled."
    exit 0
fi

############################################################
# STOP NETBOX SERVICES
############################################################

header "STOPPING NETBOX SERVICES"

systemctl stop "${NETBOX_SERVICE}"
systemctl stop "${NETBOX_WORKER_SERVICE}"

info "NetBox services stopped"

############################################################
# REMAP CLUSTER IDs
#
# Foreign keys are deferred inside one transaction.
############################################################

header "REMAPPING NETBOX CLUSTER IDS"

su - postgres -c \
"${PG_BIN}/psql -v ON_ERROR_STOP=1 -d ${DB_NAME}" <<SQL

BEGIN;

SET CONSTRAINTS ALL DEFERRED;

-- =========================================================
-- STEP 1: Move old IDs to temporary IDs
-- =========================================================

UPDATE virtualization_cluster
SET id = ${TEMP_CENTOS_ID}
WHERE id = ${CENTOS_ID}
  AND name = 'centos-07-servers';

UPDATE virtualization_cluster
SET id = ${TEMP_ROCKY8_ID}
WHERE id = ${ROCKY8_ID}
  AND name = 'rocky-8-servers';

UPDATE virtualization_cluster
SET id = ${TEMP_ROCKY9_ID}
WHERE id = ${ROCKY9_ID}
  AND name = 'rocky-9-servers';

-- =========================================================
-- STEP 2: Update VM references
-- =========================================================

UPDATE virtualization_virtualmachine
SET cluster_id = ${TEMP_CENTOS_ID}
WHERE cluster_id = ${CENTOS_ID};

UPDATE virtualization_virtualmachine
SET cluster_id = ${TEMP_ROCKY8_ID}
WHERE cluster_id = ${ROCKY8_ID};

UPDATE virtualization_virtualmachine
SET cluster_id = ${TEMP_ROCKY9_ID}
WHERE cluster_id = ${ROCKY9_ID};

-- =========================================================
-- STEP 3: Assign required final IDs
-- =========================================================

UPDATE virtualization_cluster
SET id = 1
WHERE id = ${TEMP_CENTOS_ID}
  AND name = 'centos-07-servers';

UPDATE virtualization_cluster
SET id = 2
WHERE id = ${TEMP_ROCKY8_ID}
  AND name = 'rocky-8-servers';

UPDATE virtualization_cluster
SET id = 3
WHERE id = ${TEMP_ROCKY9_ID}
  AND name = 'rocky-9-servers';

-- =========================================================
-- STEP 4: Update VM references to final IDs
-- =========================================================

UPDATE virtualization_virtualmachine
SET cluster_id = 1
WHERE cluster_id = ${TEMP_CENTOS_ID};

UPDATE virtualization_virtualmachine
SET cluster_id = 2
WHERE cluster_id = ${TEMP_ROCKY8_ID};

UPDATE virtualization_virtualmachine
SET cluster_id = 3
WHERE cluster_id = ${TEMP_ROCKY9_ID};

-- =========================================================
-- STEP 5: Reset PostgreSQL sequence
-- =========================================================

SELECT setval(
    pg_get_serial_sequence('virtualization_cluster', 'id'),
    GREATEST(
        COALESCE((SELECT MAX(id) FROM virtualization_cluster), 1),
        3
    ),
    true
);

COMMIT;

SQL

info "Cluster ID remapping completed"

############################################################
# VERIFY FINAL CLUSTER IDs
############################################################

header "VERIFYING FINAL CLUSTER IDS"

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
WHERE c.name IN (
    'centos-07-servers',
    'rocky-8-servers',
    'rocky-9-servers'
)
ORDER BY c.id;
\""

############################################################
# VERIFY VM REFERENCES
############################################################

header "VERIFYING VIRTUAL MACHINE REFERENCES"

su - postgres -c \
"${PG_BIN}/psql -d ${DB_NAME} -c \"
SELECT
    c.id AS cluster_id,
    c.name AS cluster_name,
    COUNT(vm.id) AS virtual_machine_count
FROM virtualization_cluster c
LEFT JOIN virtualization_virtualmachine vm
    ON vm.cluster_id = c.id
WHERE c.name IN (
    'centos-07-servers',
    'rocky-8-servers',
    'rocky-9-servers'
)
GROUP BY c.id, c.name
ORDER BY c.id;
\""

############################################################
# FINAL VALIDATION
############################################################

header "FINAL VALIDATION"

FINAL_CENTOS_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id
    FROM virtualization_cluster
    WHERE name='centos-07-servers';
    \""
)

FINAL_ROCKY8_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id
    FROM virtualization_cluster
    WHERE name='rocky-8-servers';
    \""
)

FINAL_ROCKY9_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id
    FROM virtualization_cluster
    WHERE name='rocky-9-servers';
    \""
)

if [[ "${FINAL_CENTOS_ID}" != "1" ||
      "${FINAL_ROCKY8_ID}" != "2" ||
      "${FINAL_ROCKY9_ID}" != "3" ]]; then

    error "Cluster ID validation failed."
    exit 1
fi

info "Cluster ID validation successful"

############################################################
# START NETBOX SERVICES
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
printf "%b\n" "${GREEN} CLUSTER ID MAPPING${NC}"
printf "%b\n" "${GREEN}============================================================${NC}"
printf "%b\n" "${GREEN} centos-07-servers : Cluster ID 1${NC}"
printf "%b\n" "${GREEN} rocky-8-servers   : Cluster ID 2${NC}"
printf "%b\n" "${GREEN} rocky-9-servers   : Cluster ID 3${NC}"
printf "%b\n" "${GREEN}============================================================${NC}"

echo
info "Cluster Group IDs were NOT modified."
info "Database backup: ${BACKUP_FILE}"

exit 0
