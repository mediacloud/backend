#!/bin/bash

set -u
set -o errexit

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/set_mc_root_dir.inc.sh"

cd "$MC_ROOT_DIR"

source ./script/set_perl_brew_environment.sh
echo "Using Perl version: `perl -e 'print substr($^V, 1)'`"

if [ `uname` == 'Darwin' ]; then

    # Mac OS X
    CPANM=/usr/local/bin/cpanm

else

    # assume Ubuntu
    CPANM=cpanm

fi

$CPANM CPAN~2.10

# 1.0.9 or newer
# (if the install of Carton 1.0.9 fails because of CPAN::Meta failure,
# purge Perl with ./install/purge_mc_perl_brew.sh and
# ./install/purge_carton_install.sh)
$CPANM Carton~1.0.22

$CPANM "List::MoreUtils@0.419"

# Always print stack traces when die()ing
$CPANM Carp::Always

# Install profiler and tools
$CPANM Devel::NYTProf
$CPANM Devel::Cover
$CPANM lib::core::only
