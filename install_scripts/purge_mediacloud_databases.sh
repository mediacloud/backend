#!/bin/bash

set -u
set -o errexit

if [ `uname` == 'Darwin' ]; then
    # Mac OS X
    PSQL=/opt/local/lib/postgresql84/bin/psql
    DROPDB=/opt/local/lib/postgresql84/bin/dropdb
else
    # assume Ubuntu
    PSQL="psql"
    DROPDB="dropdb"
fi

sudo su -l postgres -c "$DROPDB mediacloud"
sudo su -l postgres -c "$DROPDB mediacloud_test"
sudo su -l postgres -c "$PSQL -c \"DROP USER IF EXISTS mediaclouduser \" "
