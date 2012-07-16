#!/bin/sh
set -u
set -o  errexit

echo "installing postgresql packages"
echo

sudo apt-get --assume-yes install postgresql-8.4 postgresql-client-8.4 postgresql-plperl-8.4 postgresql-server-dev-8.4;

echo
echo sucessfully installed postgresql packages