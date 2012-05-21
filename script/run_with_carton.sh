#!/bin/bash

cmd_str="$1"
shift
full_path_str=`readlink -m $cmd_str`

working_dir=`dirname $0`

cd $working_dir

set -u
set -o  errexit

cd ..
#echo "$BASHPID"
echo ./script/run_carton.sh exec -- $full_path_str $@
exec ./script/run_carton.sh exec -- $full_path_str $@

