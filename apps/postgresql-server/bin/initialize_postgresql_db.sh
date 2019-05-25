#!/bin/bash

set -u
set -e

MC_POSTGRESQL_BIN_DIR="/usr/lib/postgresql/11/bin/"
MC_POSTGRESQL_DATA_DIR="/var/lib/postgresql/11/main/"
MC_POSTGRESQL_CONF_PATH="/etc/postgresql/11/main/postgresql.conf"

# Run initdb
mkdir -p ${MC_POSTGRESQL_DATA_DIR}
${MC_POSTGRESQL_BIN_DIR}/initdb \
    --pgdata=${MC_POSTGRESQL_DATA_DIR} \
    --data-checksums \
    --encoding=UTF-8 \
    --lc-collate='en_US.UTF-8' \
    --lc-ctype='en_US.UTF-8'

${MC_POSTGRESQL_BIN_DIR}/pg_ctl \
    -o "-c config_file=$MC_POSTGRESQL_CONF_PATH -c listen_addresses=" \
    -D ${MC_POSTGRESQL_DATA_DIR} \
    -w \
    start

psql -c "CREATE USER mediacloud WITH PASSWORD 'mediacloud' SUPERUSER;"

# * "template1" is preinitialized with "LATIN1" encoding on some systems
#   and thus doesn't work, so using a cleaner "template0";
#
# * Force UTF-8 encoding because some PostgreSQL installations default to
#   "LATIN1" and then LENGTH() and similar functions don't work correctly
psql -c "CREATE DATABASE mediacloud WITH OWNER = mediacloud TEMPLATE = template0 ENCODING = 'UTF-8' LC_COLLATE = 'en_US.UTF-8' LC_CTYPE = 'en_US.UTF-8';"

${MC_POSTGRESQL_BIN_DIR}/pg_ctl \
    -D ${MC_POSTGRESQL_DATA_DIR} \
    -m fast \
    -w \
    stop
