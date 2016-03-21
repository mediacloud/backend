#!/bin/bash

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir

if pwd | grep ' ' ; then
    echo "Media Cloud cannot be installed in a file path with spaces in its name"
    exit 1
fi

# Install dependency modules; run the command twice because the first
# attempt might fail
ATTEMPT=1
CARTON_INSTALL_SUCCEEDED=0
until [ $ATTEMPT -ge 3 ]; do
    JAVA_HOME=$JAVA_HOME ./script/run_carton.sh install && {
        echo "Successfully installed Carton modules"
        CARTON_INSTALL_SUCCEEDED=1
        break
    } || {
        echo "Attempt $ATTEMPT to install Carton modules failed"
    }
    ATTEMPT=$[$ATTEMPT+1]
done
if [ $CARTON_INSTALL_SUCCEEDED -ne 1 ]; then
    echo "Gave up installing Carton modules."
    exit 1
fi

# Install Mallet-CrfWrapper (don't run unit tests because the web service test
# ends up as a Perl zombie process during the Vagrant test run)
JAVA_HOME=$JAVA_HOME ./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm \
    --local-lib-contained local/ \
    --verbose \
    --notest \
    https://github.com/dlarochelle/Mallet-CrfWrapper/tarball/0.02

echo "Successfully installed Perl and modules for Media Cloud"
