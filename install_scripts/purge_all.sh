#!/bin/bash

# Include PostgreSQL path helpers
PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$PWD/postgresql_path_helpers.inc.sh"

./install_scripts/purge_carton_install.sh
./install_scripts/purge_mc_perl_brew.sh
./install_scripts/purge_mediacloud_databases.sh
