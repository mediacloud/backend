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
source ./script/set_java_home.sh
JAVA_HOME=$JAVA_HOME ./script/run_carton.sh install || {
    echo "First attempt to install CPAN modules failed, trying again..."
    JAVA_HOME=$JAVA_HOME ./script/run_carton.sh install
}

# Install Mallet-CrfWrapper (don't run unit tests because the web service test
# ends up as a Perl zombie process during the Vagrant test run)
JAVA_HOME=$JAVA_HOME ./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm \
    --local-lib-contained local/ \
    --verbose \
    --notest \
    https://github.com/dlarochelle/Mallet-CrfWrapper/tarball/0.02

echo "Successfully installed Perl and modules for Media Cloud"
