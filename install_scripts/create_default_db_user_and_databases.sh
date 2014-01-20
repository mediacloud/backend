#!/bin/bash

set -u
set -o  errexit

# Default password
PASSWORD="mediacloud"

# Include PostgreSQL path helpers
PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$PWD/postgresql_path_helpers.inc.sh"


# Create user
echo "creating postgresql user 'mediaclouduser' with password '$PASSWORD'"
CREATEUSER_RUN=`run_psql "CREATE USER mediaclouduser WITH SUPERUSER password '$PASSWORD' ; "`
echo "$CREATEUSER_RUN"

if [[ "$CREATEUSER_RUN" == *"ERROR"* ]]; then
    if [[ "$CREATEUSER_RUN" == *"already exists"* ]]; then
        echo "postgresql user 'mediaclouduser' already exists, skipping creation."
        echo "if you want to purge everything and start from scratch, run purge_mediacloud_databases.sh manually."
    else
        echo "postgresql error while creating user 'mediaclouduser': $CREATEUSER_RUN"
        exit 1
    fi
fi

# Create databases
for db_name in "mediacloud" "mediacloud_test" "mediacloud_gearman"; do
    echo "$db_name"

    echo "creating database '$db_name'"
    CREATEDB_MEDIACLOUD_RUN=`run_createdb $db_name`
    echo "$CREATEDB_MEDIACLOUD_RUN"

    if [[ "$CREATEDB_MEDIACLOUD_RUN" == *"already exists"* ]]; then
        echo "postgresql database '$db_name' already exists, skipping creation."
        echo "if you want to purge everything and start from scratch, run purge_mediacloud_databases.sh manually."
    elif [[ -n "$CREATEDB_MEDIACLOUD_RUN" ]]; then
        echo "postgresql error while creating database '$db_name': $CREATEDB_MEDIACLOUD_RUN"
        exit 1
    else
       echo "created database $db_name"
    fi
done
