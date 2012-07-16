#!/bin/sh
set -u
set -o  errexit

working_dir=`dirname $0`
cd $working_dir
cd ..
echo "starting system wide pg/pl dependency modules install"
echo
sudo -u root -H cpanm  -V > /dev/null
cat lib/MediaWords/Pg/DependsList.pm | grep -v '#' | grep -v MediaWords | grep '^use' | grep -v 'strict;' | grep -v 'HTML::StripPP' | sed -e 's/^use //' | sed -e 's/ qw.*//' | sed -e 's/;$//' | xargs -n 1 sudo -n -u root -H cpanm
echo
echo "sucessfully completed system wide pg/pl dependency modules install"

