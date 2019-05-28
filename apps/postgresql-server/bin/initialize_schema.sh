#!/bin/bash

set -u
set -e

MC_POSTGRESQL_BIN_DIR="/usr/lib/postgresql/11/bin/"
MC_POSTGRESQL_DATA_DIR="/var/lib/postgresql/11/main/"
MC_POSTGRESQL_CONF_PATH="/etc/postgresql/11/main/postgresql.conf"

# Update memory configuration
/opt/mediacloud/bin/update_memory_config.sh

# Remove APT-initialized data directory because it doesn't have the right
# locale, doesn't use checksums etc.
rm -rf /var/lib/postgresql/11/main/

# Run initdb
mkdir -p "${MC_POSTGRESQL_DATA_DIR}"
"${MC_POSTGRESQL_BIN_DIR}/initdb" \
    --pgdata="${MC_POSTGRESQL_DATA_DIR}" \
    --data-checksums \
    --encoding=UTF-8 \
    --lc-collate='en_US.UTF-8' \
    --lc-ctype='en_US.UTF-8'

"${MC_POSTGRESQL_BIN_DIR}/pg_ctl" \
    -o "-c config_file=${MC_POSTGRESQL_CONF_PATH}" \
    -D "${MC_POSTGRESQL_DATA_DIR}" \
    -w \
    start

psql -v ON_ERROR_STOP=1 -c "CREATE USER mediacloud WITH PASSWORD 'mediacloud' SUPERUSER;"

# * "template1" is preinitialized with "LATIN1" encoding on some systems
#   and thus doesn't work, so using a cleaner "template0";
#
# * Force UTF-8 encoding because some PostgreSQL installations default to
#   "LATIN1" and then LENGTH() and similar functions don't work correctly
read -d '' CREATE_DB_SQL << EOF || true
CREATE DATABASE mediacloud WITH
    OWNER = mediacloud
    TEMPLATE = template0
    ENCODING = 'UTF-8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
;
EOF
psql -v ON_ERROR_STOP=1 -c "${CREATE_DB_SQL}"

# Initialize with schema
psql -v ON_ERROR_STOP=1 -d mediacloud -f /opt/mediacloud/schema/mediawords.sql

# Stop PostgreSQL
"${MC_POSTGRESQL_BIN_DIR}/pg_ctl" \
    -D "${MC_POSTGRESQL_DATA_DIR}" \
    -m fast \
    -w \
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
