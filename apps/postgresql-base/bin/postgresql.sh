#!/bin/bash

set -u
set -e

MC_POSTGRESQL_BIN_DIR="/usr/lib/postgresql/13/bin/"
MC_POSTGRESQL_DATA_DIR="/var/lib/postgresql/13/main/"
MC_POSTGRESQL_CONF_PATH="/etc/postgresql/13/main/postgresql.conf"

# Update memory configuration
/opt/postgresql-base/bin/update_memory_config.sh

# Start PostgreSQL
exec "${MC_POSTGRESQL_BIN_DIR}/postgres" \
    -D "${MC_POSTGRESQL_DATA_DIR}" \
    -c "config_file=${MC_POSTGRESQL_CONF_PATH}"
