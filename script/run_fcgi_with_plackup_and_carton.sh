#!/bin/bash

#cmd_str="$1"
#shift
#full_path_str=`readlink -m $cmd_str`

working_dir=`dirname $0`

cd $working_dir

exec ./run_plackup_with_carton.sh -s FCGI
