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

$CPANM Carton~0.9.15
$CPANM List::MoreUtils
$CPANM Devel::NYTProf
