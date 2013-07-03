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

    # Mac OS X
    JAVA_HOME=/System/Library/Frameworks/JavaVM.framework/Versions/CurrentJDK/

else

    # Assume Ubuntu
    JAVA_HOME=/usr/lib/jvm/java-7-openjdk-amd64/

fi

# Install the rest of the modules
./script/run_carton.sh install --deployment

echo "Successfully installed Perl and modules for MediaCloud"
