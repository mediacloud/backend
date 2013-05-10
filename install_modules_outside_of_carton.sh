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

$CPANM foreign_modules/carton-v0.9.4.tar.gz
$CPANM foreign_modules/List-MoreUtils-0.33.tgz
$CPANM foreign_modules/Devel-NYTProf-4.06.tar.gz 
$CPANM foreign_modules/Lingua-Stem-Snowball-0.96.tar.gz
