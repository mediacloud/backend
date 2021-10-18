#!/bin/bash

set -u
set -e


#
# Update memory configuration based on the amount of RAM available to the
# container
#

MC_POSTGRESQL_MEMORY_CONF_PATH="/var/run/postgresql/postgresql-memory.conf"
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


#
# Update WAL-G configuration
#

MC_POSTGRESQL_WALG_CONF_PATH="/var/run/postgresql/postgresql-walg.conf"

# Keep in sync with wal-g.sh
MC_POSTGRESQL_WALG_ENV_PATH="/var/run/postgresql/walg.env"

if [ ! -f "${MC_POSTGRESQL_WALG_CONF_PATH}" ]; then
    echo "PostgreSQL WAL-G configuration file does not exist in ${MC_POSTGRESQL_WALG_CONF_PATH}"
    exit 1
fi
if [ ! -f "${MC_POSTGRESQL_WALG_ENV_PATH}" ]; then
    echo "PostgreSQL WAL-G environment file does not exist in ${MC_POSTGRESQL_WALG_ENV_PATH}"
    exit 1
fi

if [ -z ${MC_WALG_ENABLE+x} ]; then

    echo "WAL-G is disabled."

    cat > "${MC_POSTGRESQL_WALG_CONF_PATH}" << EOF
#
# Auto-generated, please don't edit!
#

archive_mode = off
EOF

    cat > "${MC_POSTGRESQL_WALG_ENV_PATH}" << EOF
#
# Auto-generated, please don't edit!
#

# WAL-G is disabled.
EOF

else

    echo "WAL-G is enabled."

    cat > "${MC_POSTGRESQL_WALG_CONF_PATH}" << EOF
#
# Auto-generated, please don't edit!
#

# Back up with WAL-G
archive_mode = on
archive_command = '/opt/postgresql-base/bin/wal-g.sh wal-push %p'
EOF

    if [[ ! "${MC_WALG_S3_BUCKET_PREFIX}" == "s3://"* ]]; then
        echo "S3 bucket + prefix must start with 's3://': ${MC_WALG_S3_BUCKET_PREFIX}"
        exit 1
    fi

    if [ "${MC_WALG_S3_BUCKET_PREFIX: -1}" == "/" ]; then
        echo "S3 bucket + prefix can't end with a slash: ${MC_WALG_S3_BUCKET_PREFIX}"
        exit 1
    fi

    if [ -z ${MC_WALG_S3_ENDPOINT+x} ]; then
        MC_WALG_S3_ENDPOINT="https://s3.amazonaws.com"
    fi

    if [[ ! "${MC_WALG_S3_ENDPOINT}" == "http"* ]]; then
        echo "S3 endpoint must be 'https://' or 'http://': ${MC_WALG_S3_ENDPOINT}"
        exit 1
    fi

    if [ -z ${MC_WALG_S3_STORAGE_CLASS+x} ]; then
        MC_WALG_S3_STORAGE_CLASS="STANDARD"
    fi
    if [ -z ${MC_WALG_S3_FORCE_PATH_STYLE+x} ]; then
        MC_WALG_S3_FORCE_PATH_STYLE="false"
    fi
    if [ -z ${MC_WALG_S3_USE_LIST_OBJECTS_V1+x} ]; then
        MC_WALG_S3_USE_LIST_OBJECTS_V1="false"
    fi

    cat > "${MC_POSTGRESQL_WALG_ENV_PATH}" << EOF
#
# Auto-generated, please don't edit!
#

# Keep up to 6 delta backups
export WALG_DELTA_MAX_STEPS=6

export AWS_ACCESS_KEY_ID=${MC_WALG_S3_ACCESS_KEY_ID}
export AWS_SECRET_ACCESS_KEY=${MC_WALG_S3_SECRET_ACCESS_KEY}
export AWS_REGION=${MC_WALG_S3_REGION}
export AWS_ENDPOINT=${MC_WALG_S3_ENDPOINT}
export WALG_S3_PREFIX=${MC_WALG_S3_BUCKET_PREFIX}
export WALG_S3_STORAGE_CLASS=${MC_WALG_S3_STORAGE_CLASS}
export AWS_S3_FORCE_PATH_STYLE=${MC_WALG_S3_FORCE_PATH_STYLE}
export S3_USE_LIST_OBJECTS_V1=${MC_WALG_S3_USE_LIST_OBJECTS_V1}
EOF

    if [ ! -z ${MC_WALG_S3_CA_CERT_BASE64+x} ]; then
        MC_WALG_S3_CA_CERT_FILE=/var/run/postgresql/walg.cert
        echo "${MC_WALG_S3_CA_CERT_BASE64}" | base64 -d > "${MC_WALG_S3_CA_CERT_FILE}"
        echo "export WALG_S3_CA_CERT_FILE=${MC_WALG_S3_CA_CERT_FILE}" >> \
            "${MC_POSTGRESQL_WALG_ENV_PATH}"
    fi
fi
