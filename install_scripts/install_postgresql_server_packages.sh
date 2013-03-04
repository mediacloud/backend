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

    # Install PostgreSQL and Perl bindings
    brew install postgresql9
    sudo cpan DBD::Pg

    # Initialize PostgreSQL if installing for the first time
    if [ ! -d /usr/local/var/postgres ]; then
        initdb /usr/local/var/postgres -E utf8
    fi

    # Upgrading?    
    if [ -f ~/Library/LaunchAgents/org.postgresql.postgres.plist ]; then
        launchctl unload -w ~/Library/LaunchAgents/homebrew.mxcl.postgresql.plist
        ln -sfv /usr/local/opt/postgresql/*.plist ~/Library/LaunchAgents
    fi

    # Start PostgreSQL
    launchctl load ~/Library/LaunchAgents/homebrew.mxcl.postgresql.plist
    sleep 5
    createdb    # for the current user
    createuser postgres

else

    # assume Ubuntu
    sudo apt-get --assume-yes install \
        postgresql postgresql-client postgresql-contrib postgresql-plperl postgresql-server-dev-all

fi

echo
echo "sucessfully installed postgresql packages"
