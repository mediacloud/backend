#!/bin/bash

set -u
set -e

# Update memory configuration
/opt/postgresql-base/bin/update_memory_config.sh

# Run schema migrations if needed
if [ -e /var/lib/postgresql/first_run ]; then
    echo "Skipping schema migrations on first run..."
    rm /var/lib/postgresql/first_run
elif [ ! -z ${MC_TEMPORAL_SKIP_MIGRATIONS+x} ]; then
    echo "Skipping schema migrations because 'MC_TEMPORAL_SKIP_MIGRATIONS' is set."
else
    echo "Applying schema migrations..."
    /opt/temporal-postgresql/bin/apply_migrations.sh
    echo "Done applying schema migrations."
fi

# Start PostgreSQL
exec /opt/postgresql-base/bin/postgresql.sh
