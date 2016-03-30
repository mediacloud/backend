#!/bin/bash

set -u
set -o  errexit

working_dir=`dirname $0`
cd $working_dir

echo "installing media cloud dependencies"
echo

./install_postgresql_server_packages.sh
./install_mediacloud_system_package_dependencies.sh
./set_kernel_parameters.sh

echo
echo "sucessfully installed media cloud dependencies"
