#!/bin/bash

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir

./script/run_carton.sh install --deployment || echo "initial carton run "
./script/run_carton.sh install --deployment

# On OS X, these modules get lost in the process for some reason
if [ `uname` == 'Darwin' ]; then
	./script/run_carton.sh install YAML::Syck

	# INSTALL orders to install 'db44' on OS X, thus a hardcoded path
	BERKELEYDB_INCLUDE=/opt/local/include/db44 BERKELEYDB_LIB=/opt/local/lib/db44 ./script/run_carton.sh install BerkeleyDB
fi

echo "Successfully installed Perl and modules for MediaCloud"
