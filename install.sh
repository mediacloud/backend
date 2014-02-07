#!/bin/sh

set -u
set -o errexit

working_dir=`dirname $0`
cd $working_dir

if [ `getconf LONG_BIT` != '64' ]; then
   echo "Install failed, you must have a 64 bit OS."
   exit 1
fi

if [ ! -f mediawords.yml ]; then
    # Don't overrride the existing configuration (if any)
    cp mediawords.yml.dist mediawords.yml
fi

sudo ./install_scripts/install_mediacloud_package_dependencies.sh
./install_mc_perlbrew_and_modules.sh
./python_scripts/pip_installs.sh

echo "install complete"
echo "running compile test"

./script/run_carton.sh exec prove -Ilib/ -r t/compile.t

echo "compile test succeeded"
echo "creating new database"

# "create_default_db_user_and_databases.sh" uses configuration mediawords.yml
# so it needs a working Carton environment
sudo ./install_scripts/create_default_db_user_and_databases.sh
./script/run_with_carton.sh ./script/mediawords_create_db.pl

echo "creating new user 'jdoe@mediacloud.org' with password 'mediacloud'"
./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
    --action=add \
    --email="jdoe@mediacloud.org" \
    --full_name="John Doe" \
    --notes="Media Cloud administrator" \
    --roles="admin" \
    --password="mediacloud"

echo "Media Cloud install succeeded!!!!"
echo "See doc/ for more information on using Media Cloud"
echo "Run ./script/start_mediacloud_server.sh to start the Media Cloud server"
echo "(Log in with email address 'jdoe@mediacloud.org' and password 'mediacloud')"
