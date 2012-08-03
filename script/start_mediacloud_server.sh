#!/bin/bash

working_dir=`dirname $0`

cd $working_dir

set -u
set -o  errexit

cd ..
exec script/run_plackup_with_carton.sh $@
