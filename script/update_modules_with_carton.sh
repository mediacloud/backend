#!/bin/bash
#
# Update Perl module dependencies to their latest versions.
#
# This script removes cpanfile.snapshot, Carton's cache and modules themselves so Carton is then
# forced to check for new versions of modules.
#

if [ ! -f cpanfile ]; then
    echo "Run this script from the root of the Media Cloud repository."
    exit 1
fi

# Update Carton
source ./script/set_perl_brew_environment.sh
cpanm Carton

# Remove modules and Carton's cache, then reinstall the modules
rm -rf .carton/
rm -rf local/
rm cpanfile.snapshot

# Gearman::XS, the dependency of Gearman::JobScheduler, depends on
# Module::Install, but the author of the module (probably) forgot to add it so
# the list of dependencies (https://rt.cpan.org/Ticket/Display.html?id=89690),
# so installing it separately
mkdir -p local/
./script/run_with_carton.sh ~/perl5/perlbrew/bin/cpanm -L local/ Module::Install

source ./script/set_java_home.sh
JAVA_HOME=$JAVA_HOME ./script/run_carton.sh install  # running with "--deployment" would not regenerate cpanfile.snapshot

