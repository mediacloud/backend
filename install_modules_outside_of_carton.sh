#!/bin/bash

working_dir=`dirname $0`

cd $working_dir

source ./script/set_perl_brew_environment.sh
perl -v
set -u
set -o  errexit

cpanm foreign_modules/carton-v0.9.4.tar.gz
cpanm foreign_modules/List-MoreUtils-0.33.tgz
cpanm foreign_modules/Devel-NYTProf-4.06.tar.gz 
