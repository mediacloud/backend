#!/bin/bash

if [ `uname` == 'Darwin' ]; then
    # Mac OS X
    PSQL=/opt/local/lib/postgresql84/bin/psql
    CREATEDB=/opt/local/lib/postgresql84/bin/createdb
else
    # assume Ubuntu
    PSQL=/usr/bin/env psql
    CREATEDB=/usr/bin/env createdb
fi

sudo su -c "$PSQL -c \"CREATE USER mediaclouduser WITH SUPERUSER password 'mediacloud' ; \" " - postgres
echo "creating database mediacloud"
sudo su -c "$CREATEDB --owner mediaclouduser mediacloud" - postgres
echo "creating database mediacloud_test"
sudo su -c "$CREATEDB --owner mediaclouduser mediacloud_test" - postgres
