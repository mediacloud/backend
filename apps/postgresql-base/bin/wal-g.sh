#!/bin/bash
#
# Wrapper around "wal-g" binary which reads pre-configured credentials
#

set -u
set -e

# Keep in sync with generate_runtime_config.sh
MC_POSTGRESQL_WALG_ENV_PATH="/var/run/postgresql/walg.env"

if [ ! -f "${MC_POSTGRESQL_WALG_ENV_PATH}" ]; then
    echo "WAL-G environment file ${MC_POSTGRESQL_WALG_ENV_PATH} does not exist;"
    echo "maybe you haven't run PostgreSQL yet?"
    exit 1
fi

source /var/run/postgresql/walg.env

exec /usr/bin/_wal-g "$@"
