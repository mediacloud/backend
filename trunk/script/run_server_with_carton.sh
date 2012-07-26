#!/bin/bash

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir

./run_with_carton.sh ./mediawords_server.pl
