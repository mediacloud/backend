#!/bin/sh

set -u
set -o errexit

working_dir=`dirname $0`
cd $working_dir

if [ `uname -m` != 'x86_64' ]; then
   echo "Install failed, you must have a 64 bit OS";
   exit 1;
fi

sudo ./install_scripts/install_mediacloud_package_dependencies.sh
sudo ./install_scripts/create_default_db_user_and_databases.sh

if [ ! -f mediawords.yml ]; then
    # Don't overrride the existing configuration (if any)
    cp mediawords.yml.dist mediawords.yml
fi

sudo ./install_scripts/install_system_wide_modules_for_plpg_perl.sh
./install_mc_perlbrew_and_modules.sh

echo "install complete"
echo "running compile test"

./script/run_carton.sh  exec -Ilib/ -- prove -r t/compile.t

echo "compile test succeeded"
echo "creating new database"

./script/run_with_carton.sh ./script/mediawords_create_db.pl

echo "Media Cloud install succeeded!!!!"
echo "See doc/ for more information on using Media Cloud"
echo "Run ./script/run_plackup_with_carton.sh to start the Media Cloud server"
