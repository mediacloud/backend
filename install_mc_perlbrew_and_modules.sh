#!/bin/bash

working_dir=`dirname $0`

cd $working_dir

set -u
set -o  errexit

if [[ -z "$TRAVIS_SKIP_INSTALL_MC_PERLBREW" ]]; then
    echo "starting perlbrew install "
    ./install_mc_perlbrew.sh
fi
echo "starting non-carton-based modules install "
./install_modules_outside_of_carton.sh
echo "starting carton-based modules install "
./install_modules_with_carton.sh
echo "Install complete"
