#!/bin/bash

set -u
set -o errexit

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/set_mc_root_dir.inc.sh"

cd "$MC_ROOT_DIR"

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
    brew install postgresql

    # Initialize PostgreSQL if installing for the first time
    if [ ! -d /usr/local/var/postgres ]; then
        initdb /usr/local/var/postgres -E utf8
    fi

    brew services restart postgresql
    sleep 5
    createdb || echo "User's database already exists, nothing to do."    # for the current user
    createuser postgres || echo "User 'postgres' already exists, nothing to do."
    createuser --superuser --createdb --createrole --replication root || echo "User 'root' already exists, nothing to do."

else

    echo | sudo ./install/setup_postgresql_apt.sh
    # assume Ubuntu
    sudo apt-get --assume-yes install \
        postgresql-9.6 \
        postgresql-client-9.6 \
        postgresql-contrib-9.6 \
        postgresql-plperl-9.6 \
        postgresql-server-dev-all

fi

echo
echo "sucessfully installed postgresql packages"
