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

# FIXME Install ExtUtils::MakeMaker (a Carton dependency) separately
# without testing it because t/meta_convert.t fails on some machines
# (https://rt.cpan.org/Public/Bug/Display.html?id=85861)
$CPANM --notest ExtUtils::MakeMaker

# Carton's tarball is hardcoded in case v0.9.15 becomes unavailable
# at some time in the future
$CPANM ./foreign_modules/carton-v0.9.15.tar.gz

$CPANM List::MoreUtils
$CPANM Devel::NYTProf
