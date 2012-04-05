#!/bin/bash

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir

source ./set_perl_brew_environment.sh

cd ..

carton exec -Ilib/ -- prove -r lib/ script/ t/
