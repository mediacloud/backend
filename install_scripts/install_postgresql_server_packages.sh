#!/bin/bash

set -u
set -o errexit

echo "installing postgresql packages"
echo

if [ `uname` == 'Darwin' ]; then

    # Mac OS X
    sudo port install \
        postgresql84 +perl \
        postgresql84-server \
        p5.12-dbd-pg +postgresql84

else

    # assume Ubuntu
    sudo apt-get --assume-yes install \
        postgresql-8.4 postgresql-client-8.4 postgresql-plperl-8.4 postgresql-server-dev-8.4

fi

echo
echo "sucessfully installed postgresql packages"
