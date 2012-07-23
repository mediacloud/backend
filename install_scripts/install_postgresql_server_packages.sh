#!/bin/bash

set -u
set -o errexit

echo "installing postgresql packages"
echo

if [ `uname` == 'Darwin' ]; then

    # Mac OS X

    if [ ! -x /opt/local/bin/port ]; then
        echo "You'll need MacPorts <http://www.macports.org/> to install the required packages on Mac OS X."
        echo "It might be possible to do that manually with Fink <http://www.finkproject.org/>, but you're at your own here."
        exit 1
    fi

    if [ ! -x /usr/bin/gcc ]; then
        echo "As a dependency to MacPorts, you need to install Xcode (available as a free download from Mac App Store or "
        echo "from http://developer.apple.com/) and Xcode's \"Command Line Tools\" (open Xcode, go to \"Xcode\" -> \"Preferences...\","
        echo "select \"Downloads\", choose \"Components\", click \"Install\" near the \"Command Line Tools\" entry, wait "
        echo "for a while)."
        exit 1
    fi

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
