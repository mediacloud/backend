#!/bin/bash

#cmd_str="$1"
#shift
#full_path_str=`readlink -m $cmd_str`

working_dir=`dirname $0`

cd $working_dir

echo $$ run_fcgi_with_plackup_and_carton.sh pid >&2

exec ./run_plackup_with_carton.sh -s FCGI --nproc 0 --manager MediaWords::MyFCgiManager
