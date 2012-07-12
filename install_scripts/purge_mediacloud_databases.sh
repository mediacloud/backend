#!/bin/sh
sudo su -c 'dropdb mediacloud' - postgres
sudo su -c 'dropdb mediacloud_test' - postgres
sudo su -c "psql  -c \"DROP USER IF EXISTS mediaclouduser \" " - postgres
