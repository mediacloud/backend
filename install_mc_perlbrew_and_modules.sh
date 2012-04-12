#!/bin/bash

working_dir=`dirname $0`

cd $working_dir

set -u
set -o  errexit

./install_mc_perlbrew.sh
./install_modules_outside_of_carton.sh
./install_modules_with_carton.sh

