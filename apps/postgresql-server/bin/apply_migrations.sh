#!/bin/bash

set -u
set -e

MC_POSTGRESQL_BIN_DIR="/usr/lib/postgresql/11/bin/"
MC_POSTGRESQL_DATA_DIR="/var/lib/postgresql/11/main/"
MC_POSTGRESQL_CONF_PATH="/etc/postgresql/11/main/postgresql.conf"

SCHEMA_DIR="/opt/postgresql-server/schema/"
SCHEMA_PATH="${SCHEMA_DIR}/mediawords.sql"
MIGRATIONS_DIR="${SCHEMA_DIR}/migrations/"

# Apply migrations when running on a different port so that clients don't end
# up connecting in the middle of migrating
TEMP_PORT=12345

# In case the database is in recovery, wait for up to 1 hour for it to complete
PGCTL_START_TIMEOUT=3600

if [ ! -f "${SCHEMA_PATH}" ]; then
    echo "Schema ${SCHEMA_PATH} does not exist."
    exit 1
fi

if [ ! -d "${MIGRATIONS_DIR}" ]; then
    echo "Migrations directory ${MIGRATIONS_DIR} does not exist."
    exit 1
fi


validate_schema_version() {
    schema_version="$1"
    if [[ ! "${schema_version}" =~ ^[0-9]+$ ]]; then
        echo "Invalid schema version; got: ${schema_version}"
        exit 1
    fi
}

# Read new (mediawords.sql) schema version
NEW_SCHEMA_VERSION=$(cat ${SCHEMA_PATH} | \
    grep "MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT" | \
    awk '{ print $5 }' | \
    sed 's/;//')

validate_schema_version "${NEW_SCHEMA_VERSION}"

echo "New schema version: ${NEW_SCHEMA_VERSION}"

# Start PostgreSQL on a temporary port
"${MC_POSTGRESQL_BIN_DIR}/pg_ctl" \
    -o "-c config_file=${MC_POSTGRESQL_CONF_PATH} -p ${TEMP_PORT}" \
    -D "${MC_POSTGRESQL_DATA_DIR}" \
    -t "${PGCTL_START_TIMEOUT}" \
    -w \
    start

# Read old (database) schema version
OLD_SCHEMA_VERSION=$(psql -v ON_ERROR_STOP=1 -p "${TEMP_PORT}" -t -c \
    "SELECT value FROM database_variables WHERE name = 'database-schema-version';" | \
    xargs)

validate_schema_version "${OLD_SCHEMA_VERSION}"

echo "Old schema version: ${OLD_SCHEMA_VERSION}"

# Run migration if needed
if (( "${OLD_SCHEMA_VERSION}" == "${NEW_SCHEMA_VERSION}" )); then
    echo "Schema is up-to-date, nothing to do."
elif (( "${OLD_SCHEMA_VERSION}" > "${NEW_SCHEMA_VERSION}" )); then
    echo "Schema is newer in the database, go write a migration and rebuild this image."
    echo "old version: $OLD_SCHEMA_VERSION, new_version: $NEW_SCHEMA_VERSION"
    exit 1
else
    echo "Upgrading from ${OLD_SCHEMA_VERSION} to ${NEW_SCHEMA_VERSION}..."
    CONCAT_MIGRATION=$(mktemp /var/tmp/migration-${OLD_SCHEMA_VERSION}-${NEW_SCHEMA_VERSION}.XXXXXX)

    # Run concatenated migration files in a single transaction
    echo "BEGIN;" >> "${CONCAT_MIGRATION}"

    for SCHEMA_VERSION in $(seq "${OLD_SCHEMA_VERSION}" "$(( ${NEW_SCHEMA_VERSION} - 1 ))"); do
        MIGRATION_FILENAME="mediawords-${SCHEMA_VERSION}-$(( ${SCHEMA_VERSION} + 1 )).sql"
        MIGRATION_PATH="${MIGRATIONS_DIR}/${MIGRATION_FILENAME}"

        if [ ! -f "${MIGRATION_PATH}" ]; then
            echo "Migration at ${MIGRATION_PATH} does not exist."
            exit 1
        fi
        
        cat "${MIGRATION_PATH}" >> "${CONCAT_MIGRATION}"

    done

    # Add shim which verifies that schema version has been set to correct value
    cat >> "${CONCAT_MIGRATION}" << EOF

        DO \$\$
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM database_variables
                WHERE name = 'database-schema-version'
                  AND value = '${NEW_SCHEMA_VERSION}'
            ) THEN
                RAISE EXCEPTION 'Schema version has not been updated after applying the migration';
            END IF;
        END\$\$;

EOF

    # Commit transaction
    echo "COMMIT;" >> "${CONCAT_MIGRATION}"

    # Apply migration
    psql -v ON_ERROR_STOP=1 -p "${TEMP_PORT}" -f "${CONCAT_MIGRATION}"

    rm "${CONCAT_MIGRATION}"
fi

# Stop PostgreSQL
"${MC_POSTGRESQL_BIN_DIR}/pg_ctl" \
    -D "${MC_POSTGRESQL_DATA_DIR}" \
    -m fast \
    -w \
    stop
