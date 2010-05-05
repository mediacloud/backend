#!/bin/bash

# References see the following for the inspiration behind the implementation
# tmp files:  http://www.linuxsecurity.com/content/view/115462/81/
# prove & cron:  http://www.perlmonks.org/?node_id=491553
#

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir

cd ..

which mktemp > /dev/null || (echo "mktemp not installed" && exit -1)

tmp_file_name=`mktemp -d`/test_s$RANDOM.$RANDOM.$RANDOM.$$;
./script/run_test_suite_with_code_update.sh > "$tmp_file_name" 2>&1 || cat "$tmp_file_name"
