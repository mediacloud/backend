#!/bin/sh
sudo su -c "psql  -c \"CREATE USER mediaclouduser WITH SUPERUSER password 'mediacloud' ; \" " - postgres
echo "creating database mediacloud"
sudo su -c 'createdb --owner mediaclouduser mediacloud' - postgres
echo "creating database mediacloud_test"
sudo su -c 'createdb --owner mediaclouduser mediacloud_test' - postgres