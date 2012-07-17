#!/bin/bash

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

echo "Creating postgresql user 'mediaclouduser' with password '$PASSWORD'"

sudo su -c "$PSQL -c \"CREATE USER mediaclouduser WITH SUPERUSER password '$PASSWORD' ; \" " - postgres
echo "creating database mediacloud"
sudo su -c "$CREATEDB --owner mediaclouduser mediacloud" - postgres
echo "creating database mediacloud_test"
sudo su -c "$CREATEDB --owner mediaclouduser mediacloud_test" - postgres
