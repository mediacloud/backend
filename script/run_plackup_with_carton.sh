#!/bin/bash

working_dir=`dirname $0`
cd $working_dir

source ./set_perl_brew_environment.sh

set -u
set -o errexit

cd ..

# Make sure Inline::Python uses correct virtualenv
set +u; source mc-venv/bin/activate; set -u

echo "Running plackup on Carton on PID $$ and arguments: $@" >&2
exec carton exec plackup -I lib $@
