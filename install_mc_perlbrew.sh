#!/bin/bash

working_dir=`dirname $0`

cd $working_dir

set -u
set -o  errexit

if [ `getconf LONG_BIT` != '64' ]; then
    echo "Install failed, you must have a 64 bit OS."
    exit 1
fi

\curl -L http://install.perlbrew.pl | bash

set +u
source ~/perl5/perlbrew/etc/bashrc
set -u
perlbrew init
nice perlbrew install perl-5.16.3 -Duseithreads -Dusemultiplicity -Duse64bitint -Duse64bitall -Duseposix -Dusethreads -Duselargefiles -Dccflags=-DDEBIAN
perlbrew switch perl-5.16.3
perlbrew install-cpanm
perlbrew lib create mediacloud
perlbrew switch perl-5.16.3@mediacloud
