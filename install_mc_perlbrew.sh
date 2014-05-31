#!/bin/bash

working_dir=`dirname $0`

cd $working_dir

set -u
set -o  errexit

if [ `getconf LONG_BIT` != '64' ]; then
    echo "Install failed, you must have a 64 bit OS."
    exit 1
fi

TMPDIR="." ./foreign_modules/perlbrew_install.sh
set +u
source ~/perl5/perlbrew/etc/bashrc
set -u
perlbrew init

CMD_PERLBREW_INSTALL="nice perlbrew install perl-5.16.3 -Duseithreads -Dusemultiplicity -Duse64bitint -Duse64bitall -Duseposix -Dusethreads -Duselargefiles -Dccflags=-DDEBIAN"
if [[ -z "$USE_TRAVIS_WAIT" ]]; then
    "$CMD_PERLBREW_INSTALL"
else
    # Allow Travis-CI to complete Perl install in 20 minutes (instead of the
    # default 10)
    travis_wait "$CMD_PERLBREW_INSTALL"
fi

perlbrew switch perl-5.16.3
perlbrew install-cpanm
perlbrew lib create mediacloud
perlbrew switch perl-5.16.3@mediacloud
