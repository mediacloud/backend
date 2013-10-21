#!/bin/bash

cmd_str="$1"
shift

working_dir=`dirname $0`

cd $working_dir

set -u
set -o  errexit

cd ..

exec ./script/run_carton.sh exec prove -Ilib/ -r t/compile.t


