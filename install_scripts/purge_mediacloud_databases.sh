#!/bin/bash

if [ `uname` == 'Darwin' ]; then
    # Mac OS X
    PSQL=/opt/local/lib/postgresql84/bin/psql
    DROPDB=/opt/local/lib/postgresql84/bin/dropdb
else
    # assume Ubuntu
    PSQL=/usr/bin/env psql
    DROPDB=/usr/bin/env dropdb
fi

sudo su -c "$DROPDB mediacloud" - postgres
sudo su -c "$DROPDB mediacloud_test" - postgres
sudo su -c "$PSQL -c \"DROP USER IF EXISTS mediaclouduser \" " - postgres
