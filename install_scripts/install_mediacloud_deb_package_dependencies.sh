#!/bin/sh
set -u
set -o  errexit

working_dir=`dirname $0`
cd $working_dir

echo "installing media cloud dependencies"
echo

./install_postgresql_server_deb_packages.sh
./install_mediacloud_system_deb_package_dependencies.sh

echo
echo  "sucessfully installed media cloud dependencies"