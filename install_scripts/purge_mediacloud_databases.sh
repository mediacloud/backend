#!/bin/bash

set -u
set -o  errexit

# Include PostgreSQL path helpers
PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$PWD/postgresql_path_helpers.inc.sh"


echo "WARNING: This will delete the media cloud database.  Are you sure you want to do this (y/n)?"
read REPLY

if [ $REPLY != "y" ]; then
    echo "Exiting..."
    exit 1
fi

# Drop databases
for db_name in "mediacloud" "mediacloud_test" "mediacloud_gearman"; do
	echo "DROPPING db $db_name"
	run_dropdb "$db_name"
done

set -u
set -o errexit

# Remove user
run_psql "DROP USER IF EXISTS mediaclouduser "
