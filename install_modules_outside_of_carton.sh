#!/bin/bash

working_dir=`dirname $0`

cd $working_dir

source ./script/set_perl_brew_environment.sh
perl -v
set -u
set -o  errexit

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
# purge Perl with ./install_scripts/purge_mc_perl_brew.sh and
# ./install_scripts/purge_carton_install.sh)
$CPANM Carton~1.0.9

$CPANM List::MoreUtils

# Install profiler and tools
$CPANM Sub::Name~0.09   # contains the required fixes for Devel::NYTProf to install correctly
$CPANM Devel::NYTProf
$CPANM Devel::Cover
$CPANM lib::core::only
