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

#echo "foo"
echo $CREATEUSER_RUN

if [[ "$CREATEUSER_RUN" == *"ERROR"* ]]; then
if [[ "$CREATEUSER_RUN" == *"already exists"* ]]; then
    echo "postgresql user 'mediaclouduser' already exists, skipping creation."
    echo "if you want to purge everything and start from scratch, run purge_mediacloud_databases.sh manually."
else
    echo "postgresql error while creating user 'mediaclouduser': $CREATEUSER_RUN"
    exit 1
fi
fi

function createdb {
DB_NAME=$1
echo "creating database 'mediacloud'"
CREATEDB_MEDIACLOUD_RUN=`sudo su -l postgres -c "$CREATEDB --owner mediaclouduser $DB_NAME 2>&1" || echo "Oops."`
echo "DB CREATE OUTPUT '$CREATEDB_MEDIACLOUD_RUN'"

if [[ "$CREATEDB_MEDIACLOUD_RUN" == *"already exists"* ]]; then
    echo "postgresql database '$DB_NAME' already exists, skipping creation."
    echo "if you want to purge everything and start from scratch, run purge_mediacloud_databases.sh manually."
elif [[ -n "$CREATEDB_MEDIACLOUD_RUN" ]]; then
    echo "postgresql error while creating database '$DB_NAME': $CREATEDB_MEDIACLOUD_RUN"
    exit 1
else
   echo "created database $DB_NAME"
fi
}

createdb 'mediacloud'
createdb 'mediacloud_test'

