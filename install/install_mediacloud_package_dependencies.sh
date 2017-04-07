#!/bin/bash

set -u
set -o  errexit

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/set_mc_root_dir.inc.sh"

cd "$MC_ROOT_DIR"

echo "Installing PostgreSQL server packages..."
./install/install_postgresql_server_packages.sh

echo "Installing system package dependencies..."
./install/install_mediacloud_system_package_dependencies.sh
