#!/bin/bash

working_dir=`dirname $0`

cd $working_dir

./script/run_carton.sh install --deployment || echo "initial carton run "
./script/run_carton.sh install --deployment

echo "Successfully installed Perl and modules for MediaCloud"
