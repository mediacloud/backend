#!/bin/bash

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir

if [ `uname` == 'Darwin' ]; then
	# On OS X, these modules get lost in the process for some reason
	./script/run_carton.sh install YAML::Syck

	# Install BerkeleyDB correctly before installing the remaining modules from carton.lock
	BERKELEYDB_INCLUDE=/opt/local/include/db44 BERKELEYDB_LIB=/opt/local/lib/db44 ./script/run_carton.sh install BerkeleyDB
fi

./script/run_carton.sh install --deployment || echo "initial carton run "
./script/run_carton.sh install --deployment

echo "Successfully installed Perl and modules for MediaCloud"
