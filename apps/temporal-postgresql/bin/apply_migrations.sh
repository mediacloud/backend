#!/bin/bash

set -u
set -e

MC_POSTGRESQL_BIN_DIR="/usr/lib/postgresql/11/bin/"
MC_POSTGRESQL_DATA_DIR="/var/lib/postgresql/11/main/"
MC_POSTGRESQL_CONF_PATH="/etc/postgresql/11/main/postgresql.conf"

# Apply migrations when running on a different port so that clients don't end
# up connecting in the middle of migrating
TEMP_PORT=12345

# In case the database is in recovery, wait for up to 1 hour for it to complete
PGCTL_START_TIMEOUT=3600

# Start PostgreSQL on a temporary port
"${MC_POSTGRESQL_BIN_DIR}/pg_ctl" \
    -o "-c config_file=${MC_POSTGRESQL_CONF_PATH} -p ${TEMP_PORT}" \
    -D "${MC_POSTGRESQL_DATA_DIR}" \
    -t "${PGCTL_START_TIMEOUT}" \
    -w \
    start

SCHEMAS_DIR="/opt/temporal-postgresql/schema/v96"
TSQL="temporal-sql-tool \
    --plugin postgres \
    --ep 127.0.0.1 \
    -p 12345 \
    -u temporal \
    --pw temporal"

MAIN_SCHEMA_DIR="${SCHEMAS_DIR}/temporal/versioned"
$TSQL --db temporal update-schema -d "${MAIN_SCHEMA_DIR}"

VISIBILITY_SCHEMA_DIR="${SCHEMAS_DIR}/visibility/versioned"
$TSQL --db temporal_visibility update-schema -d "${VISIBILITY_SCHEMA_DIR}"

# Stop PostgreSQL
"${MC_POSTGRESQL_BIN_DIR}/pg_ctl" \
    -D "${MC_POSTGRESQL_DATA_DIR}" \
    -m fast \
    -w \
    stop
