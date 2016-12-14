#!/bin/bash

working_dir=`dirname $0`
cd $working_dir

echo "Running FCGI plackup on Carton on PID $$" >&2
exec ./run_plackup_with_carton.sh -s FCGI --nproc 0 --manager MediaWords::MyFCgiManager
