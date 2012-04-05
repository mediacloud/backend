#!/bin/bash

#cmd_str="$1"
#shift
#full_path_str=`readlink -m $cmd_str`

working_dir=`dirname $0`

cd $working_dir

source ./set_perl_brew_environment.sh

set -u
set -o  errexit

cd ..
#echo "$BASHPID"
echo carton exec -- plackup -I lib $@
exec carton exec -- plackup -I lib $@