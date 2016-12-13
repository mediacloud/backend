#!/bin/bash

set -u
set -o  errexit

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/set_mc_root_dir.inc.sh"

cd "$MC_ROOT_DIR"

echo "installing media cloud dependencies"
echo

./install_scripts/install_postgresql_server_packages.sh
./install_scripts/install_mediacloud_system_package_dependencies.sh

echo
echo "sucessfully installed media cloud dependencies"
