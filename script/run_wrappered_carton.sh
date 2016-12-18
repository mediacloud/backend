#!/bin/bash

working_dir=`dirname $0`

source $working_dir/set_perl_brew_environment.sh

set -u
set -o  errexit

# Make sure Inline::Python uses correct virtualenv
set +u; cd "$working_dir/../"; source mc-venv/bin/activate; set -u

#echo carton "$@"
exec $working_dir/mediawords_carton_wrapper.pl "$@"