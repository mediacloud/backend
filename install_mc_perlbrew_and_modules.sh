#!/bin/bash

working_dir=`dirname $0`

cd $working_dir

set -u
set -o  errexit

TMPDIR="." ./foreign_modules/perlbrew_install.sh
source ~/perl5/perlbrew/etc/bashrc
perlbrew init
nice perlbrew install perl-5.14.2 -Duseithreads -Dusemultiplicity -Duse64bitint -Duse64bitall -Duseposix -Dusethreads -Duselargefiles -Dccflags=-DDEBIAN
perlbrew switch perl-5.14.2
perlbrew install-cpanm
perlbrew lib create mediacloud
perlbrew switch perl-5.14.2@mediacloud
cpanm foreign_modules/carton-v0.9.3.tar.gz
cpanm foreign_modules/List-MoreUtils-0.33.tgz
carton install foreign_modules/YAML-Syck-1.20.tar.gz
carton install
carton install
cpanm foreign_modules/Devel-NYTProf-4.06.tar.gz 
