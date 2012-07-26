#!/bin/bash

if [ `uname` == 'Darwin' ]; then
    # Mac OS X
    PSQL=/opt/local/lib/postgresql84/bin/psql
    DROPDB=/opt/local/lib/postgresql84/bin/dropdb
else
    # assume Ubuntu
    PSQL="psql"
    DROPDB="dropdb"
fi

echo "DROPPING db mediacloud"
sudo su -l postgres -c "$DROPDB mediacloud"
echo "DROPPING db mediacloud_test"
sudo su -l postgres -c "$DROPDB mediacloud_test"

set -u
set -o errexit

sudo su -l postgres -c "$PSQL -c \"DROP USER IF EXISTS mediaclouduser \" "
