#!/bin/bash

#cmd_str="$1"
#shift
#if [ `uname` == 'Darwin' ]; then
#	greadlink from coreutils
#	full_path_str=`greadlink -m $cmd_str`
#else
#	full_path_str=`readlink -m $cmd_str`
#fi

working_dir=`dirname $0`

cd $working_dir

source ./set_perl_brew_environment.sh

set -u
set -o  errexit

cd ..
#echo "$BASHPID"
echo $$ run_plackup_with_carton.sh pid >&2

echo carton exec -- plackup -I lib $@
exec carton exec -- plackup -I lib $@
