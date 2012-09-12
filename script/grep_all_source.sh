#!/bin/bash

working_dir=`dirname $0`

cd $working_dir
cd ..

set -u
set -o  errexit
find lib script t -iname '*.pm' -print0 -or -iname '*.pl' -print0 -or -iname '*.t' -print0 | xargs -0 grep $@
