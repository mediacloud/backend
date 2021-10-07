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
# Update PgBackRest configuration
#

MC_POSTGRESQL_PGBACKREST_CONF_PATH="/var/run/postgresql/postgresql-pgbackrest.conf"
MC_BACKREST_CONF_D_S3_CONF_PATH="/etc/pgbackrest/conf.d/s3.conf"


if [ -z ${MC_PGBACKREST_ENABLE+x} ]; then

    echo "PgBackRest is disabled."

    cat > "${MC_POSTGRESQL_PGBACKREST_CONF_PATH}" << EOF
#
# Auto-generated, please don't edit!
#

archive_mode = off
EOF

    cat > "${MC_BACKREST_CONF_D_S3_CONF_PATH}" << EOF
#
# Auto-generated, please don't edit!
#

# S3 archiving disabled
EOF

else

    echo "PgBackRest is enabled."

    cat > "${MC_POSTGRESQL_PGBACKREST_CONF_PATH}" << EOF
#
# Auto-generated, please don't edit!
#

# Back up with PgBackRest
# (stanzas of all users of postgresql-base are called "main")
archive_mode = on
archive_command = 'pgbackrest --stanza=main archive-push %p'
EOF

    cat > "${MC_BACKREST_CONF_D_S3_CONF_PATH}" << EOF
#
# Auto-generated, please don't edit!
#

# S3 credentials
[global]
repo1-retention-full=${MC_PGBACKREST_RETENTION_FULL}
repo1-s3-endpoint=${MC_PGBACKREST_S3_ENDPOINT}
repo1-s3-bucket=${MC_PGBACKREST_S3_BUCKET}
repo1-storage-verify-tls=${MC_PGBACKREST_S3_VERIFY_TLS}
repo1-s3-key=${MC_PGBACKREST_S3_KEY}
repo1-s3-key-secret=${MC_PGBACKREST_S3_KEY_SECRET}
repo1-s3-region=${MC_PGBACKREST_S3_REGION}
repo1-path=${MC_PGBACKREST_S3_PATH}
EOF

fi
