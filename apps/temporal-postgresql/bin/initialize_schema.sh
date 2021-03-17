#!/bin/bash
#
# FIXME reuse code between "initialize_schema.sh" and "apply_migrations.sh"
#

set -u
set -e

MC_POSTGRESQL_BIN_DIR="/usr/lib/postgresql/11/bin/"
MC_POSTGRESQL_DATA_DIR="/var/lib/postgresql/11/main/"
MC_POSTGRESQL_CONF_PATH="/etc/postgresql/11/main/postgresql.conf"

# Update memory configuration
/opt/postgresql-base/bin/update_memory_config.sh

"${MC_POSTGRESQL_BIN_DIR}/pg_ctl" \
    -o "-c config_file=${MC_POSTGRESQL_CONF_PATH}" \
    -D "${MC_POSTGRESQL_DATA_DIR}" \
    -w \
    -t 1200 \
    start

psql -v ON_ERROR_STOP=1 -c "CREATE USER temporal WITH PASSWORD 'temporal' SUPERUSER;"

SCHEMAS_DIR="/opt/temporal-postgresql/schema/v96"
TSQL="temporal-sql-tool \
    --plugin postgres \
    --ep 127.0.0.1 \
    -p 5432 \
    -u temporal \
    --pw temporal \
"

MAIN_SCHEMA_DIR="${SCHEMAS_DIR}/temporal/versioned"
$TSQL create --db temporal
$TSQL --db temporal setup-schema -v 0.0
$TSQL --db temporal update-schema -d "${MAIN_SCHEMA_DIR}"

VISIBILITY_SCHEMA_DIR="${SCHEMAS_DIR}/visibility/versioned"
$TSQL create --db temporal_visibility
$TSQL --db temporal_visibility setup-schema -v 0.0
$TSQL --db temporal_visibility update-schema -d "${VISIBILITY_SCHEMA_DIR}"

# Given that "temporal-sql-tool" returns 0 on errors too, make sure that something got created
psql -d temporal -c 'SELECT * FROM visibility_tasks' > /dev/null
psql -d temporal_visibility -c 'SELECT * FROM schema_version' > /dev/null

# Stop PostgreSQL
"${MC_POSTGRESQL_BIN_DIR}/pg_ctl" \
    -D "${MC_POSTGRESQL_DATA_DIR}" \
    -m fast \
    -w \
    -t 1200 \
    stop

# Create a file that will denote that we're running off a fresh data volume and
# it's the first time ever that we've started the server
cat > /var/lib/postgresql/first_run << EOF
If this file exists, it means that a fresh data volume was just mounted to the
container, and the container is about to run for the first time ever, so
there's no point in attempting to check the schema version and apply
migrations.

After the first time this container gets run, this file will get deleted and
every subsequent run of the same container will then attempt to apply
migrations in order to upgrade the schema before continuing with anything else.
EOF
chown postgres:postgres /var/lib/postgresql/first_run
