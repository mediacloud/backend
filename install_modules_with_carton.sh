#!/bin/bash

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir

if pwd | grep ' ' ; then
    echo "Media Cloud cannot be installed in a file path with spaces in its name"
    exit 1
fi

if [ `uname` == 'Darwin' ]; then
	# On OS X, these modules get lost in the process for some reason
	./script/run_carton.sh install YAML::Syck

	# Install BerkeleyDB correctly before installing the remaining modules from carton.lock
	BERKELEYDB_INCLUDE=/usr/local/include/db44 \
	BERKELEYDB_LIB=/usr/local/lib \
	./script/run_carton.sh install BerkeleyDB
fi

# Install custom version of Lingua::Stem::Snowball with Lithuanian additions
./script/run_carton.sh install foreign_modules/Lingua-Stem-Snowball-0.96.tar.gz

# Install the rest of the modules
./script/run_carton.sh install --deployment || echo "initial carton run "
./script/run_carton.sh install --deployment

echo "Successfully installed Perl and modules for MediaCloud"
