#!/bin/bash

working_dir=`dirname $0`

source $working_dir/set_perl_brew_environment.sh

set -u
set -o  errexit

#echo carton "$@"
exec $working_dir/mediawords_carton_wrapper.pl "$@"