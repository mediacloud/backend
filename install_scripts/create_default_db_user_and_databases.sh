#!/bin/bash

set -u
set -o  errexit

# Include PostgreSQL path helpers
PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$PWD/postgresql_helpers.inc.sh"

QUERY_CONFIG="$PWD/../script/run_with_carton.sh $PWD/../script/mediawords_query_config.pl"

for db_selector in "${DB_CREDENTIALS_SELECTORS[@]}"; do

    db_credentials_label=`$QUERY_CONFIG "$db_selector/label"`
    echo "Initializing database with label '$db_credentials_label'..."

    db_credentials_host=`$QUERY_CONFIG "$db_selector/host"`
    db_credentials_user=`$QUERY_CONFIG "$db_selector/user"`
    db_credentials_pass=`$QUERY_CONFIG "$db_selector/pass"`
    db_credentials_db=`$QUERY_CONFIG "$db_selector/db"`

    #
    # Create user if it doesn't exist already
    #
    echo "    Creating user '$db_credentials_user' with password '$db_credentials_pass'..."

    createuser_sql=$( cat <<EOF

        CREATE ROLE $db_credentials_user
        WITH SUPERUSER LOGIN
        PASSWORD '$db_credentials_pass'

EOF
)
    createuser_exec=`run_psql "$db_credentials_host" "$createuser_sql"`
    if [[ "$createuser_exec" == *"already exists"* ]]; then
        echo "        User '$db_credentials_user' already exists, skipping creation."
    elif [[ -n "$createuser_exec" ]]; then
        echo "        PostgreSQL error while creating user '$db_credentials_user': $createuser_exec"
        exit 1
    fi
    echo "    Done creating user '$db_credentials_user'."

    #
    # Create database
    #
    echo "    Creating database '$db_credentials_db' on host '$db_credentials_host' with owner '$db_credentials_user'..."
    createdb_exec=`run_createdb "$db_credentials_host" "$db_credentials_db" "$db_credentials_user"`

    if [[ "$createdb_exec" == *"already exists"* ]]; then
        echo "        Database '$db_credentials_db' already exists, skipping creation."
        echo "        If you want to purge everything and start from scratch, run purge_mediacloud_databases.sh manually."
    elif [[ -n "$createdb_exec" ]]; then
        echo "        PostgreSQL error while creating database '$db_credentials_db': $createdb_exec"
        exit 1
    fi
    echo "    Done creating database '$db_credentials_db'."

    echo "Done initializing database with label '$db_credentials_label'."

done
