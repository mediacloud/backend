#!/bin/bash

set -u
set -o  errexit

# Include PostgreSQL path helpers
PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$PWD/postgresql_helpers.inc.sh"

#
QUERY_CONFIG="$PWD/../script/run_with_carton.sh $PWD/../script/mediawords_query_config.pl"


echo "WARNING: This script will delete the following Media Cloud databases and users:"
for db_selector in "${DB_CREDENTIALS_SELECTORS[@]}"; do
    db_credentials_label=`$QUERY_CONFIG "$db_selector/label"`
    echo "    * Label: $db_credentials_label"
    db_credentials_host=`$QUERY_CONFIG "$db_selector/host"`
    echo "      Host: $db_credentials_host"
    db_credentials_user=`$QUERY_CONFIG "$db_selector/user"`
    echo "      Username: $db_credentials_user"
    db_credentials_db=`$QUERY_CONFIG "$db_selector/db"`
    echo "      Database: $db_credentials_db"
    echo
done
echo "Are you sure you want to do this (y/n)?"
read REPLY

if [ "$REPLY" != "y" ]; then
    echo "Exiting..."
    exit 1
fi

for db_selector in "${DB_CREDENTIALS_SELECTORS[@]}"; do

    db_credentials_label=`$QUERY_CONFIG "$db_selector/label"`
    echo "Dropping database with label '$db_credentials_label'..."

    db_credentials_host=`$QUERY_CONFIG "$db_selector/host"`
    db_credentials_user=`$QUERY_CONFIG "$db_selector/user"`
    db_credentials_db=`$QUERY_CONFIG "$db_selector/db"`

    #
    # Drop database
    #
    echo "    Dropping database '$db_credentials_db' on host '$db_credentials_host'..."
    dropdb_exec=`run_dropdb "$db_credentials_host" "$db_credentials_db"`

    if [[ "$dropdb_exec" == *"ERROR"* ]]; then
        if [[ "$dropdb_exec" == *"does not exist"* ]]; then
            echo "        Database '$db_credentials_db' does not exist, skipping."
        elif [[ -n "$dropdb_exec" ]]; then
            echo "        PostgreSQL error while dropping database '$db_credentials_db': $dropdb_exec"
            exit 1
        fi
    fi
    echo "    Done dropping database '$db_credentials_db'."

    #
    # Drop user if there are no more databases owned by it
    #
    echo "    Dropping user '$db_credentials_user' on host '$db_credentials_host'..."
    dropuser_exec=`run_psql "$db_credentials_host" "DROP USER IF EXISTS $db_credentials_user ; " postgres`
    if [[ "$dropuser_exec" == *"ERROR"* ]]; then
        if [[ "$dropuser_exec" == *"some objects depend on it"* ]]; then
            echo "        User '$db_credentials_user' wasn't dropped yet because some objects still depend on it."
        elif [[ -n "$dropuser_exec" ]]; then
            echo "        PostgreSQL error while dropping user '$db_credentials_user': $dropuser_exec"
            exit 1
        fi
    fi
    echo "    Done dropping user '$db_credentials_user'."

    echo "Done dropping database with label '$db_credentials_label'."

done
