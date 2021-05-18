#!/bin/bash

set -u
set -e

MC_POSTGRESQL_BIN_DIR="/usr/lib/postgresql/13/bin/"
MC_POSTGRESQL_DATA_DIR="/var/lib/postgresql/13/main/"
MC_POSTGRESQL_MEMORY_CONF_PATH="/var/run/postgresql/postgresql-memory.conf"

# Adjust configuration based on amount of RAM
MC_RAM_SIZE=$(/container_memory_limit.sh)
MC_POSTGRESQL_CONF_SHARED_BUFFERS=$((MC_RAM_SIZE / 3))
MC_POSTGRESQL_CONF_EFFECTIVE_CACHE_SIZE=$((MC_RAM_SIZE / 3))

cat > "${MC_POSTGRESQL_MEMORY_CONF_PATH}" << EOF
#
# Auto-generated, please don't edit!
#

shared_buffers = ${MC_POSTGRESQL_CONF_SHARED_BUFFERS}MB
effective_cache_size = ${MC_POSTGRESQL_CONF_EFFECTIVE_CACHE_SIZE}MB
EOF
