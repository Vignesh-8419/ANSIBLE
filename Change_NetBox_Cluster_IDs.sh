#!/bin/bash
set -euo pipefail

############################################################
# NETBOX CLUSTER ID REMAPPING SCRIPT
#
# NetBox: v4.4.9
# Database: PostgreSQL 15
#
# REQUIRED CLUSTER ID MAPPING
#
# centos-07-servers -> ID 1
# rocky-8-servers   -> ID 2
# rocky-9-servers   -> ID 3
#
# This script changes:
#   virtualization_cluster.id
#
# It does NOT modify:
#   virtualization_clustergroup.id
############################################################

DB_NAME="netbox"
PG_BIN="/usr/pgsql-15/bin"

NETBOX_SERVICE="netbox"
NETBOX_WORKER_SERVICE="netbox-worker"

BACKUP_DIR="/root/netbox-backup"

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
# SERVICE RECOVERY ON FAILURE
############################################################

NETBOX_STOPPED=0

cleanup() {
    EXIT_CODE=$?

    if [[ "${NETBOX_STOPPED}" -eq 1 ]]; then
        warn "Ensuring NetBox services are running..."

        systemctl start "${NETBOX_SERVICE}" 2>/dev/null || true
        systemctl start "${NETBOX_WORKER_SERVICE}" 2>/dev/null || true
    fi

    exit "${EXIT_CODE}"
}

trap cleanup EXIT

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
    error "PostgreSQL psql not found:"
    error "${PG_BIN}/psql"
    exit 1
fi

if [[ ! -x "${PG_BIN}/pg_dump" ]]; then
    error "PostgreSQL pg_dump not found:"
    error "${PG_BIN}/pg_dump"
    exit 1
fi

if ! systemctl is-active --quiet postgresql-15; then
    error "PostgreSQL 15 is not running."
    exit 1
fi

info "PostgreSQL 15 is running"

############################################################
# CHECK DATABASE
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
# DISPLAY CURRENT CLUSTERS
############################################################

header "CURRENT NETBOX CLUSTERS"

su - postgres -c \
"${PG_BIN}/psql -d ${DB_NAME} -c \"
SELECT
    c.id,
    c.name,
    c.type,
    c.status,
    c.group_id,
    g.name AS group_name
FROM virtualization_cluster c
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
    error "Expected exactly one cluster named: centos-07-servers"
    error "Found: ${CENTOS_COUNT}"
    exit 1
fi

if [[ "${ROCKY8_COUNT}" != "1" ]]; then
    error "Expected exactly one cluster named: rocky-8-servers"
    error "Found: ${ROCKY8_COUNT}"
    exit 1
fi

if [[ "${ROCKY9_COUNT}" != "1" ]]; then
    error "Expected exactly one cluster named: rocky-9-servers"
    error "Found: ${ROCKY9_COUNT}"
    exit 1
fi

info "All required clusters found"

############################################################
# GET CURRENT CLUSTER IDS
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

if [[ "${CENTOS_ID}" == "1" && \
      "${ROCKY8_ID}" == "2" && \
      "${ROCKY9_ID}" == "3" ]]; then

    header "CLUSTER IDS ALREADY CORRECT"

    info "centos-07-servers -> ID 1"
    info "rocky-8-servers   -> ID 2"
    info "rocky-9-servers   -> ID 3"

    trap - EXIT
    exit 0
fi

############################################################
# CHECK TARGET IDS
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

    if [[ -n "${EXISTING_NAME}" && \
          "${EXISTING_NAME}" != "${EXPECTED_NAME}" ]]; then

        error "Cluster ID ${TARGET_ID} is already used by:"
        error "${EXISTING_NAME}"
        error "Cannot safely continue."
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
# CHECK TEMPORARY IDS
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
        error "Cannot continue safely."
        exit 1
    fi

    info "Temporary ID ${TEMP_ID} is available"
done

############################################################
# COUNT VMS BEFORE CHANGE
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

info "centos-07-servers VMs: ${VM_COUNT_CENTOS}"
info "rocky-8-servers VMs: ${VM_COUNT_ROCKY8}"
info "rocky-9-servers VMs: ${VM_COUNT_ROCKY9}"

############################################################
# CREATE DATABASE BACKUP
############################################################

header "CREATING NETBOX DATABASE BACKUP"

mkdir -p "${BACKUP_DIR}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/netbox_before_cluster_id_change_${TIMESTAMP}.sql"

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

echo "Cluster Name                 Current ID       New ID"
echo "-------------------------------------------------------"
printf "%-28s %-16s %-10s\n" \
    "centos-07-servers" "${CENTOS_ID}" "1"

printf "%-28s %-16s %-10s\n" \
    "rocky-8-servers" "${ROCKY8_ID}" "2"

printf "%-28s %-16s %-10s\n" \
    "rocky-9-servers" "${ROCKY9_ID}" "3"

echo
warn "Cluster Groups will NOT be changed."
warn "Only Cluster IDs will be changed."

############################################################
# CONFIRM
############################################################

read -rp "Continue with Cluster ID remapping? Type YES: " CONFIRM

if [[ "${CONFIRM}" != "YES" ]]; then
    warn "Operation cancelled."

    trap - EXIT
    exit 0
fi

############################################################
# STOP NETBOX SERVICES
############################################################

header "STOPPING NETBOX SERVICES"

systemctl stop "${NETBOX_SERVICE}"
systemctl stop "${NETBOX_WORKER_SERVICE}"

NETBOX_STOPPED=1

info "NetBox services stopped"

############################################################
# REMAP CLUSTER IDS
############################################################

header "REMAPPING NETBOX CLUSTER IDS"

su - postgres -c \
"${PG_BIN}/psql -v ON_ERROR_STOP=1 -d ${DB_NAME}" <<SQL

BEGIN;

-- =========================================================
-- Defer foreign-key checking until transaction commit
-- =========================================================

SET CONSTRAINTS ALL DEFERRED;

-- =========================================================
-- STEP 1: Move Cluster IDs to temporary IDs
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
-- STEP 2: Update Virtual Machine cluster references
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
-- STEP 3: Assign final Cluster IDs
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
-- STEP 4: Update Virtual Machine references to final IDs
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
-- STEP 5: Reset Cluster ID sequence
-- =========================================================

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

info "Cluster ID remapping transaction completed"

############################################################
# VERIFY CLUSTERS
############################################################

header "VERIFYING FINAL CLUSTER IDS"

su - postgres -c \
"${PG_BIN}/psql -d ${DB_NAME} -c \"
SELECT
    c.id,
    c.name,
    c.type,
    c.status,
    c.group_id,
    g.name AS group_name
FROM virtualization_cluster c
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

header "VERIFYING VIRTUAL MACHINE CLUSTER REFERENCES"

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

if [[ "${FINAL_CENTOS_ID}" != "1" ]]; then
    error "centos-07-servers validation failed."
    exit 1
fi

if [[ "${FINAL_ROCKY8_ID}" != "2" ]]; then
    error "rocky-8-servers validation failed."
    exit 1
fi

if [[ "${FINAL_ROCKY9_ID}" != "3" ]]; then
    error "rocky-9-servers validation failed."
    exit 1
fi

info "centos-07-servers Cluster ID: 1"
info "rocky-8-servers Cluster ID: 2"
info "rocky-9-servers Cluster ID: 3"

############################################################
# START NETBOX SERVICES
############################################################

header "STARTING NETBOX SERVICES"

systemctl start "${NETBOX_SERVICE}"
systemctl start "${NETBOX_WORKER_SERVICE}"

sleep 5

if systemctl is-active --quiet "${NETBOX_SERVICE}"; then
    info "netbox service: RUNNING"
else
    error "netbox service: FAILED"
    exit 1
fi

if systemctl is-active --quiet "${NETBOX_WORKER_SERVICE}"; then
    info "netbox-worker service: RUNNING"
else
    error "netbox-worker service: FAILED"
    exit 1
fi

NETBOX_STOPPED=0

############################################################
# FINAL SUMMARY
############################################################

header "NETBOX CLUSTER ID REMAPPING COMPLETE"

echo
printf "%b\n" "${GREEN}============================================================${NC}"
printf "%b\n" "${GREEN} CLUSTER ID MAPPING${NC}"
printf "%b\n" "${GREEN}============================================================${NC}"
printf "%b\n" "${GREEN} centos-07-servers : Cluster ID 1${NC}"
printf "%b\n" "${GREEN} rocky-8-servers   : Cluster ID 2${NC}"
printf "%b\n" "${GREEN} rocky-9-servers   : Cluster ID 3${NC}"
printf "%b\n" "${GREEN}============================================================${NC}"
echo

info "Cluster Group IDs were not modified by this script."
info "Database backup:"
info "${BACKUP_FILE}"

trap - EXIT

exit 0
