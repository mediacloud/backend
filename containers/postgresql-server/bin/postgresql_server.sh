#!/bin/bash

set -u
set -e

MC_POSTGRESQL_BIN_DIR="/usr/lib/postgresql/11/bin/"
MC_POSTGRESQL_DATA_DIR="/var/lib/postgresql/11/main/"
MC_POSTGRESQL_CONF_PATH="/etc/postgresql/11/main/postgresql.conf"

# Adjust configuration based on amount of RAM
MC_RAM_SIZE=$(free -m | grep Mem | awk '{ print $2 }')
MC_POSTGRESQL_CONF_SHARED_BUFFERS=$((MC_RAM_SIZE / 3))
MC_POSTGRESQL_CONF_EFFECTIVE_CACHE_SIZE=$((MC_RAM_SIZE / 3))
echo "shared_buffers = ${MC_POSTGRESQL_CONF_SHARED_BUFFERS}MB" >> "$MC_POSTGRESQL_CONF_PATH"
echo "effective_cache_size = ${MC_POSTGRESQL_CONF_EFFECTIVE_CACHE_SIZE}MB" >> "$MC_POSTGRESQL_CONF_PATH"

# Start PostgreSQL
exec ${MC_POSTGRESQL_BIN_DIR}/postgres \
    -D ${MC_POSTGRESQL_DATA_DIR} \
    -c "config_file=$MC_POSTGRESQL_CONF_PATH"
