#!/bin/bash

working_dir=`dirname $0`

cd $working_dir

source ./script/set_perl_brew_environment.sh
perl -v
set -u
set -o  errexit

if [ `uname` == 'Darwin' ]; then

    # Mac OS X
    if [ -x /opt/local/bin/cpanm ]; then
        CPANM=/opt/local/bin/cpanm
    elif [ -x /opt/local/libexec/perl5.12/sitebin/cpanm ]; then
        CPANM=/opt/local/libexec/perl5.12/sitebin/cpanm
    else
        echo "I have tried to install 'cpanm' (App::cpanminus) previously, but not I am unable to locate it."
        exit 1
    fi

else

    # assume Ubuntu
    CPANM=cpanm

fi

$CPANM foreign_modules/carton-v0.9.4.tar.gz
$CPANM foreign_modules/List-MoreUtils-0.33.tgz
$CPANM foreign_modules/Devel-NYTProf-4.06.tar.gz 
