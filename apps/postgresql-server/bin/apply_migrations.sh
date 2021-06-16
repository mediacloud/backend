#!/bin/bash

set -u
set -e

MC_POSTGRESQL_BIN_DIR="/usr/lib/postgresql/13/bin/"
MC_POSTGRESQL_DATA_DIR="/var/lib/postgresql/13/main/"
MC_POSTGRESQL_CONF_PATH="/etc/postgresql/13/main/postgresql.conf"

MIGRATIONS_DIR="/opt/postgresql-server/migrations"

# Apply migrations when running on a different port so that clients don't end
# up connecting in the middle of migrating
TEMP_PORT=12345

# In case the database is in recovery, wait for up to 1 hour for it to complete
PGCTL_START_TIMEOUT=3600

if [ ! -d "${MIGRATIONS_DIR}" ]; then
    echo "Migrations directory ${MIGRATIONS_DIR} does not exist."
    exit 1
fi

# Start PostgreSQL on a temporary port
"${MC_POSTGRESQL_BIN_DIR}/pg_ctl" \
    -o "-c config_file=${MC_POSTGRESQL_CONF_PATH} -p ${TEMP_PORT}" \
    -D "${MC_POSTGRESQL_DATA_DIR}" \
    -t "${PGCTL_START_TIMEOUT}" \
    -w \
    start

# apply migrations
cd /opt/postgresql-server && pgmigrate migrate --target latest --conn \ 
    "dbname=mediacloud user=mediacloud password=mediacloud host=localhost port=${TEMP_PORT}"

# Stop PostgreSQL
"${MC_POSTGRESQL_BIN_DIR}/pg_ctl" \
    -D "${MC_POSTGRESQL_DATA_DIR}" \
    -m fast \
    -w \
    stop
