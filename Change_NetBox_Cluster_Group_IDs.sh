#!/bin/bash
set -euo pipefail

############################################################
# NETBOX CLUSTER GROUP ID REMAPPING
#
# centos-07-servers -> ID 1
# rocky-8-servers   -> ID 2
# rocky-9-servers   -> ID 3
#
# NetBox Database:
# PostgreSQL 15
# Database: netbox
############################################################

DB_NAME="netbox"
PG_BIN="/usr/pgsql-15/bin"

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

if [[ "${EUID}" -ne 0 ]]; then
    error "Run this script as root."
    exit 1
fi

############################################################
# CHECK POSTGRESQL
############################################################

header "CHECKING POSTGRESQL"

if ! systemctl is-active --quiet postgresql-15; then
    error "PostgreSQL 15 is not running."
    exit 1
fi

if [[ ! -x "${PG_BIN}/psql" ]]; then
    error "psql not found at ${PG_BIN}/psql"
    exit 1
fi

info "PostgreSQL 15 is running"

############################################################
# STOP NETBOX SERVICES
############################################################

header "STOPPING NETBOX SERVICES"

systemctl stop netbox 2>/dev/null || true
systemctl stop netbox-worker 2>/dev/null || true

info "NetBox services stopped"

############################################################
# DISPLAY CURRENT CLUSTER GROUPS
############################################################

header "CURRENT NETBOX CLUSTER GROUPS"

su - postgres -c \
"${PG_BIN}/psql -d ${DB_NAME} -c \"
SELECT id, name, slug
FROM virtualization_clustergroup
ORDER BY id;
\""

############################################################
# VALIDATE REQUIRED SOURCE GROUPS
############################################################

header "VALIDATING CLUSTER GROUPS"

CENTOS_COUNT=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT COUNT(*)
    FROM virtualization_clustergroup
    WHERE name = 'centos-07-servers';
    \""
)

ROCKY8_COUNT=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT COUNT(*)
    FROM virtualization_clustergroup
    WHERE name = 'rocky-8-servers';
    \""
)

ROCKY9_COUNT=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT COUNT(*)
    FROM virtualization_clustergroup
    WHERE name = 'rocky-9-servers';
    \""
)

if [[ "${CENTOS_COUNT}" != "1" ]]; then
    error "Expected exactly one cluster group: centos-07-servers"
    exit 1
fi

if [[ "${ROCKY8_COUNT}" != "1" ]]; then
    error "Expected exactly one cluster group: rocky-8-servers"
    exit 1
fi

if [[ "${ROCKY9_COUNT}" != "1" ]]; then
    error "Expected exactly one cluster group: rocky-9-servers"
    exit 1
fi

info "Required cluster groups found"

############################################################
# GET CURRENT IDs
############################################################

CENTOS_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id
    FROM virtualization_clustergroup
    WHERE name = 'centos-07-servers';
    \""
)

ROCKY8_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id
    FROM virtualization_clustergroup
    WHERE name = 'rocky-8-servers';
    \""
)

ROCKY9_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id
    FROM virtualization_clustergroup
    WHERE name = 'rocky-9-servers';
    \""
)

info "centos-07-servers current ID: ${CENTOS_ID}"
info "rocky-8-servers current ID: ${ROCKY8_ID}"
info "rocky-9-servers current ID: ${ROCKY9_ID}"

############################################################
# CHECK TARGET IDS
############################################################

header "CHECKING TARGET IDS"

# IDs 1, 2, 3 must either already belong to the correct
# group or be completely unused.

for TARGET_ID in 1 2 3; do

    TARGET_NAME=$(
        su - postgres -c \
        "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
        SELECT COALESCE(name, '')
        FROM virtualization_clustergroup
        WHERE id = ${TARGET_ID};
        \""
    )

    if [[ -n "${TARGET_NAME}" ]]; then

        case "${TARGET_ID}" in
            1)
                EXPECTED_NAME="centos-07-servers"
                ;;
            2)
                EXPECTED_NAME="rocky-8-servers"
                ;;
            3)
                EXPECTED_NAME="rocky-9-servers"
                ;;
        esac

        if [[ "${TARGET_NAME}" != "${EXPECTED_NAME}" ]]; then
            error "Target ID ${TARGET_ID} is already used by: ${TARGET_NAME}"
            error "Cannot continue safely."
            exit 1
        fi
    fi

done

info "Target IDs are available or already correctly assigned"

############################################################
# CHECK IF ALREADY CORRECT
############################################################

if [[ "${CENTOS_ID}" == "1" && \
      "${ROCKY8_ID}" == "2" && \
      "${ROCKY9_ID}" == "3" ]]; then

    info "Cluster Group IDs are already correct."
    systemctl start netbox
    systemctl start netbox-worker
    exit 0
fi

############################################################
# CREATE BACKUP
############################################################

header "CREATING DATABASE BACKUP"

BACKUP_DIR="/root/netbox-backup"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/netbox_before_cluster_group_id_change_${TIMESTAMP}.sql"

mkdir -p "${BACKUP_DIR}"

su - postgres -c \
"${PG_BIN}/pg_dump ${DB_NAME}" > "${BACKUP_FILE}"

chmod 600 "${BACKUP_FILE}"

info "Database backup created:"
info "${BACKUP_FILE}"

############################################################
# CONFIRMATION
############################################################

header "ID REMAPPING PLAN"

echo
echo "  centos-07-servers : ${CENTOS_ID} -> 1"
echo "  rocky-8-servers   : ${ROCKY8_ID} -> 2"
echo "  rocky-9-servers   : ${ROCKY9_ID} -> 3"
echo

read -rp "Continue with ID remapping? Type YES: " CONFIRM

if [[ "${CONFIRM}" != "YES" ]]; then
    warn "Operation cancelled."
    systemctl start netbox
    systemctl start netbox-worker
    exit 0
fi

############################################################
# REMAP IDS
#
# Uses temporary IDs first:
#
# Current -> 10001/10002/10003
# Temporary -> 1/2/3
#
# The transaction protects against partial changes.
############################################################

header "REMAPPING CLUSTER GROUP IDS"

su - postgres -c \
"${PG_BIN}/psql -v ON_ERROR_STOP=1 -d ${DB_NAME}" <<SQL

BEGIN;

-- ---------------------------------------------------------
-- Temporarily defer foreign key validation where supported
-- ---------------------------------------------------------
SET CONSTRAINTS ALL DEFERRED;

-- ---------------------------------------------------------
-- STEP 1: Move source IDs to temporary IDs
-- ---------------------------------------------------------

UPDATE virtualization_clustergroup
SET id = 10001
WHERE id = ${CENTOS_ID}
  AND name = 'centos-07-servers';

UPDATE virtualization_clustergroup
SET id = 10002
WHERE id = ${ROCKY8_ID}
  AND name = 'rocky-8-servers';

UPDATE virtualization_clustergroup
SET id = 10003
WHERE id = ${ROCKY9_ID}
  AND name = 'rocky-9-servers';

-- ---------------------------------------------------------
-- STEP 2: Update cluster references
-- ---------------------------------------------------------

UPDATE virtualization_cluster
SET group_id = 10001
WHERE group_id = ${CENTOS_ID};

UPDATE virtualization_cluster
SET group_id = 10002
WHERE group_id = ${ROCKY8_ID};

UPDATE virtualization_cluster
SET group_id = 10003
WHERE group_id = ${ROCKY9_ID};

-- ---------------------------------------------------------
-- STEP 3: Assign final required IDs
-- ---------------------------------------------------------

UPDATE virtualization_clustergroup
SET id = 1
WHERE id = 10001
  AND name = 'centos-07-servers';

UPDATE virtualization_clustergroup
SET id = 2
WHERE id = 10002
  AND name = 'rocky-8-servers';

UPDATE virtualization_clustergroup
SET id = 3
WHERE id = 10003
  AND name = 'rocky-9-servers';

-- ---------------------------------------------------------
-- STEP 4: Update cluster references to final IDs
-- ---------------------------------------------------------

UPDATE virtualization_cluster
SET group_id = 1
WHERE group_id = 10001;

UPDATE virtualization_cluster
SET group_id = 2
WHERE group_id = 10002;

UPDATE virtualization_cluster
SET group_id = 3
WHERE group_id = 10003;

-- ---------------------------------------------------------
-- STEP 5: Reset the ID sequence
-- ---------------------------------------------------------

SELECT setval(
    pg_get_serial_sequence('virtualization_clustergroup', 'id'),
    COALESCE(
        (SELECT MAX(id) FROM virtualization_clustergroup),
        1
    ),
    true
);

COMMIT;

SQL

info "Cluster Group ID remapping completed"

############################################################
# VERIFY CLUSTER GROUPS
############################################################

header "VERIFYING CLUSTER GROUP IDS"

su - postgres -c \
"${PG_BIN}/psql -d ${DB_NAME} -c \"
SELECT id, name, slug
FROM virtualization_clustergroup
WHERE name IN (
    'centos-07-servers',
    'rocky-8-servers',
    'rocky-9-servers'
)
ORDER BY id;
\""

############################################################
# VERIFY CLUSTER REFERENCES
############################################################

header "VERIFYING CLUSTER REFERENCES"

su - postgres -c \
"${PG_BIN}/psql -d ${DB_NAME} -c \"
SELECT
    c.id,
    c.name AS cluster_name,
    g.id AS group_id,
    g.name AS group_name
FROM virtualization_cluster c
LEFT JOIN virtualization_clustergroup g
    ON c.group_id = g.id
WHERE g.name IN (
    'centos-07-servers',
    'rocky-8-servers',
    'rocky-9-servers'
)
ORDER BY g.id, c.name;
\""

############################################################
# FINAL VALIDATION
############################################################

header "FINAL VALIDATION"

FINAL_CENTOS_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id FROM virtualization_clustergroup
    WHERE name = 'centos-07-servers';
    \""
)

FINAL_ROCKY8_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id FROM virtualization_clustergroup
    WHERE name = 'rocky-8-servers';
    \""
)

FINAL_ROCKY9_ID=$(
    su - postgres -c \
    "${PG_BIN}/psql -d ${DB_NAME} -tAc \"
    SELECT id FROM virtualization_clustergroup
    WHERE name = 'rocky-9-servers';
    \""
)

if [[ "${FINAL_CENTOS_ID}" == "1" && \
      "${FINAL_ROCKY8_ID}" == "2" && \
      "${FINAL_ROCKY9_ID}" == "3" ]]; then

    info "SUCCESS: All Cluster Group IDs are correct."
else
    error "Validation failed."
    error "Restoring from backup may be required:"
    error "${BACKUP_FILE}"
    exit 1
fi

############################################################
# START NETBOX SERVICES
############################################################

header "STARTING NETBOX SERVICES"

systemctl start netbox
systemctl start netbox-worker

sleep 5

if systemctl is-active --quiet netbox; then
    info "netbox service: RUNNING"
else
    error "netbox service: FAILED"
fi

if systemctl is-active --quiet netbox-worker; then
    info "netbox-worker service: RUNNING"
else
    error "netbox-worker service: FAILED"
fi

############################################################
# SUMMARY
############################################################

header "NETBOX CLUSTER GROUP ID REMAPPING COMPLETE"

echo
printf "%b\n" "${GREEN}============================================================${NC}"
printf "%b\n" "${GREEN} centos-07-servers : ID 1${NC}"
printf "%b\n" "${GREEN} rocky-8-servers   : ID 2${NC}"
printf "%b\n" "${GREEN} rocky-9-servers   : ID 3${NC}"
printf "%b\n" "${GREEN}============================================================${NC}"
echo

info "Database backup retained at:"
info "${BACKUP_FILE}"
