#!/bin/bash

set -u
set -e

MC_POSTGRESQL_BIN_DIR="/usr/lib/postgresql/11/bin/"
MC_POSTGRESQL_DATA_DIR="/var/lib/postgresql/11/main/"
MC_POSTGRESQL_CONF_PATH="/etc/postgresql/11/main/postgresql.conf"

# Update memory configuration
/opt/mediacloud/bin/update_memory_config.sh

# Run schema migrations if needed
if [ -e /var/lib/postgresql/first_run ]; then
    echo "Skipping schema migrations on first run..."
    rm /var/lib/postgresql/first_run
else
    echo "Applying schema migrations..."
    /opt/mediacloud/bin/apply_migrations.sh
    echo "Done applying schema migrations."
fi

# Start PostgreSQL
exec "${MC_POSTGRESQL_BIN_DIR}/postgres" \
    -D "${MC_POSTGRESQL_DATA_DIR}" \
    -c "config_file=${MC_POSTGRESQL_CONF_PATH}"
