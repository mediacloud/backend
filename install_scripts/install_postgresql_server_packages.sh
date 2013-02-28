#!/bin/bash

set -u
set -o errexit

echo "installing postgresql packages"
echo

if [ `uname` == 'Darwin' ]; then

    # Mac OS X

    if [ ! -x /usr/local/bin/brew ]; then
        echo "You'll need Homebrew <http://mxcl.github.com/homebrew/> to install the required packages on Mac OS X."
        echo "It might be possible to do that manually with Fink <http://www.finkproject.org/>"
        echo "or MacPorts <http://www.macports.org/>, but you're at your own here."
        exit 1
    fi

    if [ ! -x /usr/bin/gcc ]; then
        echo "As a dependency to Homebrew, you need to install Xcode (available as a free download from Mac App Store or"
        echo "from http://developer.apple.com/) and Xcode's \"Command Line Tools\" (open Xcode, go to "
        echo "\"Xcode\" -> \"Preferences...\", select \"Downloads\", choose \"Components\", click \"Install\" near"
        echo "the \"Command Line Tools\" entry, wait for a while)."
        exit 1
    fi

    # Install PostgreSQL and Perl bindings
    brew install postgresql8
    sudo cpan DBD::Pg

    # Initialize PostgreSQL if installing for the first time
    if [ ! -d /usr/local/var/postgres ]; then
        initdb /usr/local/var/postgres
    fi

    # Upgrading?    
    if [ -f ~/Library/LaunchAgents/org.postgresql.postgres.plist ]; then
        launchctl unload -w ~/Library/LaunchAgents/org.postgresql.postgres.plist
    fi
    cp /usr/local/Cellar/postgresql8/*/org.postgresql.postgres.plist ~/Library/LaunchAgents
    launchctl load -w ~/Library/LaunchAgents/org.postgresql.postgres.plist
    ln -sfv /usr/local/opt/postgresql8/*.plist ~/Library/LaunchAgents

    # Start PostgreSQL
    launchctl load ~/Library/LaunchAgents/homebrew.mxcl.postgresql8.plist

    # Initialize PostgreSQL if installing for the first time
    if [ ! -d /opt/local/var/db/postgresql84/defaultdb ]; then
        sudo mkdir -p /opt/local/var/db/postgresql84/defaultdb
        sudo chown postgres:postgres /opt/local/var/db/postgresql84/defaultdb
        sudo su postgres -c '/opt/local/lib/postgresql84/bin/initdb -D /opt/local/var/db/postgresql84/defaultdb'
    fi

    # Start PostgreSQL
    sudo port load postgresql84-server

else

    # assume Ubuntu
    sudo apt-get --assume-yes install \
        postgresql-8.4 postgresql-client-8.4 postgresql-contrib-8.4 postgresql-plperl-8.4 postgresql-server-dev-8.4

fi

echo
echo "sucessfully installed postgresql packages"
