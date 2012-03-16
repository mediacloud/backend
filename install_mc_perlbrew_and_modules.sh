#!/bin/bash

working_dir=`dirname $0`

cd $working_dir

set -u
set -o  errexit

TMPDIR="." ./foreign_modules/perlbrew_install.sh
set +u
source ~/perl5/perlbrew/etc/bashrc
set -u
perlbrew init
nice perlbrew install perl-5.14.2 -Duseithreads -Dusemultiplicity -Duse64bitint -Duse64bitall -Duseposix -Dusethreads -Duselargefiles -Dccflags=-DDEBIAN
perlbrew switch perl-5.14.2
perlbrew install-cpanm
perlbrew lib create mediacloud
perlbrew switch perl-5.14.2@mediacloud
cpanm foreign_modules/carton-v0.9.3.tar.gz
cpanm foreign_modules/List-MoreUtils-0.33.tgz
cpanm foreign_modules/Devel-NYTProf-4.06.tar.gz 
carton install --deploy
carton install --deploy
carton install foreign_modules/YAML-Syck-1.20.tar.gz || echo " Yaml localy installed"
echo "starting install of carton within carton"
carton install foreign_modules/carton-v0.9.3.tar.gz || carton install foreign_modules/carton-v0.9.3.tar.gz  || echo " carton installed"
echo "Successfully installed Perl and modules for MediaCloud"
