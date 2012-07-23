#!/bin/bash

set -u
set -o  errexit

if [ `uname` == 'Darwin' ]; then
    # Mac OS X
    PSQL=/opt/local/lib/postgresql84/bin/psql
    CREATEDB=/opt/local/lib/postgresql84/bin/createdb
else
    # assume Ubuntu
    PSQL="psql"
    CREATEDB="createdb"
fi

PASSWORD="mediacloud"

echo "creating postgresql user 'mediaclouduser' with password '$PASSWORD'"
CREATEUSER_RUN=`sudo su -l postgres -c "$PSQL -c \"CREATE USER mediaclouduser WITH SUPERUSER password '$PASSWORD' ; \" 2>&1 " || echo "Oops."`
if [[ "$CREATEUSER_RUN" == *"already exists"* ]]; then
    echo "postgresql user 'mediaclouduser' already exists, skipping creation."
    echo "if you want to purge everything and start from scratch, run purge_mediacloud_databases.sh manually."
else
    echo "postgresql error while creating user 'mediaclouduser': $CREATEUSER_RUN"
    exit 1
fi

echo "creating database 'mediacloud'"
CREATEDB_MEDIACLOUD_RUN=`sudo su -l postgres -c "$CREATEDB --owner mediaclouduser mediacloud 2>&1" || echo "Oops."`
if [[ "$CREATEDB_MEDIACLOUD_RUN" == *"already exists"* ]]; then
    echo "postgresql database 'mediacloud' already exists, skipping creation."
    echo "if you want to purge everything and start from scratch, run purge_mediacloud_databases.sh manually."
else
    echo "postgresql error while creating database 'mediacloud': $CREATEDB_MEDIACLOUD_RUN"
    exit 1
fi

echo "creating database mediacloud_test"
CREATEDB_MEDIACLOUDTEST_RUN=`sudo su -l postgres -c "$CREATEDB --owner mediaclouduser mediacloud_test 2>&1" || echo "Oops."`
if [[ "$CREATEDB_MEDIACLOUDTEST_RUN" == *"already exists"* ]]; then
    echo "postgresql database 'mediacloud_test' already exists, skipping creation."
    echo "if you want to purge everything and start from scratch, run purge_mediacloud_databases.sh manually."
else
    echo "postgresql error while creating database 'mediacloud_test': $CREATEDB_MEDIACLOUDTEST_RUN"
    exit 1
fi
