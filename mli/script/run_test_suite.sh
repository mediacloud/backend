#!/bin/bash

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir

cd ..

prove -l -r lib/ script/ t/