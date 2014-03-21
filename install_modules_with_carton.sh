#!/bin/bash

set -u
set -o  errexit

working_dir=`dirname $0`

cd $working_dir

if pwd | grep ' ' ; then
    echo "Media Cloud cannot be installed in a file path with spaces in its name"
    exit 1
fi

# Gearman::XS, the dependency of Gearman::JobScheduler, depends on
# Module::Install, but the author of the module (probably) forgot to add it so
# the list of dependencies (https://rt.cpan.org/Ticket/Display.html?id=89690),
# so installing it separately
mkdir -p local/
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm -L local/ Module::Install

# Install the rest of the modules; run the command twice because the first
# attempt might fail
source ./script/set_java_home.sh
JAVA_HOME=$JAVA_HOME ./script/run_carton.sh install --deployment || { echo "First attempt to install CPAN modules might fail"; }
JAVA_HOME=$JAVA_HOME ./script/run_carton.sh install --deployment

echo "Successfully installed Perl and modules for Media Cloud"
