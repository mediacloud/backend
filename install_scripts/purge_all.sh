#!/bin/bash

set -u
set -o errexit

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/set_mc_root_dir.inc.sh"

cd "$MC_ROOT_DIR"

./install_scripts/purge_mediacloud_databases.sh
./install_scripts/purge_carton_install.sh
./install_scripts/purge_mc_perl_brew.sh
