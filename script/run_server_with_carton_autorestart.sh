#!/bin/bash
#
# Run Catalyst webserver on port 3000, auto-restart on code changes
#

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir

./run_with_carton.sh ./mediawords_server.pl \
	--restart \
	--restart_regex '\.yml$|\.yaml$|\.conf|\.pm|\.txt|\.pot?$'
