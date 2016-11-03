#!/bin/bash
#
# Update Perl module dependencies to their latest versions.
#

if [ ! -f cpanfile ]; then
    echo "Run this script from the root of the Media Cloud repository."
    exit 1
fi

# Update Carton
source ./script/set_perl_brew_environment.sh
cpanm Carton

./script/run_carton.sh update
