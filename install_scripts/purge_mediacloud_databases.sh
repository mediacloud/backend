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
echo "DROPPING db mediacloud"
run_dropdb mediacloud
echo "DROPPING db mediacloud_test"
run_dropdb mediacloud_test

set -u
set -o errexit

# Remove user
run_psql "DROP USER IF EXISTS mediaclouduser "
