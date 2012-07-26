#!/bin/bash

set -u
set -o errexit

working_dir=`dirname $0`
cd $working_dir
cd ..

echo "starting system wide pg/pl dependency modules install"
echo

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


sudo -u root -H $CPANM  -V > /dev/null

cat lib/MediaWords/Pg/DependsList.pm | \
    grep -v '#' | \
    grep -v MediaWords | \
    grep '^use' | \
    grep -v 'strict;' | \
    grep -v 'HTML::StripPP' | \
    sed -e 's/^use //' | \
    sed -e 's/ qw.*//' | \
    sed -e 's/;$//' | \
    xargs -n 1 sudo -n -u root -H $CPANM

echo
echo "sucessfully completed system wide pg/pl dependency modules install"
