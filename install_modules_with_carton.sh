#!/bin/bash

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir

if pwd | grep ' ' ; then
    echo "Media Cloud cannot be installed in a file path with spaces in its name"
    exit 1
fi

## Assumes Ubuntu
export JAVA_HOME=/usr/lib/jvm/java-7-openjdk-amd64/

# Install the rest of the modules
./script/run_carton.sh install --deployment

echo "Successfully installed Perl and modules for MediaCloud"
