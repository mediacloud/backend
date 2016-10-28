#!/bin/bash

working_dir=`dirname $0`
cd $working_dir

source ./set_perl_brew_environment.sh

set -u
set -o errexit

cd ..

echo "Running plackup on Carton on PID $$ and arguments: $@" >&2
exec carton exec plackup -I lib $@
