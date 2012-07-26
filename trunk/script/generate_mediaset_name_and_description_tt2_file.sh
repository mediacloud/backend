#!/bin/bash

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir
cd ..

psql -qtc " SELECT * from media_sets_tt2_locale_format"
