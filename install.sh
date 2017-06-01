#!/bin/bash

set -u
set -o errexit

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/install/set_mc_root_dir.inc.sh"

cd "$MC_ROOT_DIR"

if [ `getconf LONG_BIT` != '64' ]; then
   echo "Install failed, you must have a 64 bit OS."
   exit 1
fi

echo "Copying configuration file 'mediawords.yml.dist' to 'mediawords.yml'..."
if [ ! -f mediawords.yml ]; then
    cp mediawords.yml.dist mediawords.yml
fi

# This will install PostgreSQL 9.1+ and a number of system libraries needed by
# CPAN modules
echo "Installing the necessary Ubuntu / OS X packages..."
./install/install_mediacloud_package_dependencies.sh

echo "Installing PostgreSQL packages..."
./install/install_postgresql_server_packages.sh

echo "Installing Python dependencies..."
./install/install_python_dependencies.sh

echo "Installing MeCab..."
./install/install_mecab-ipadic-neologd.sh

echo "Setting kernel parameters..."
./install/set_kernel_parameters.sh

echo "Setting PostgreSQL parameters..."
./install/set_postgresql_parameters.sh

echo "Installing Perlbrew, Carton and the required modules..."
echo "Note: that the script will take a long time to complete."
./install/install_mc_perlbrew_and_modules.sh

# This will create a PostgreSQL user called "mediaclouduser" and two databases
# owned by this user: "mediacloud" and "mediacloud_test".
#
# ("create_default_db_user_and_databases.sh" uses configuration mediawords.yml
# so it needs a working Carton environment)
echo "Creating default PostgreSQL user and databases for Media Cloud..."
sudo ./install/create_default_db_user_and_databases.sh

echo "Initializing PostgreSQL database with Media Cloud schema..."
./script/run_with_carton.sh ./script/mediawords_create_db.pl

echo "Creating new administrator user 'jdoe@mediacloud.org' with password 'mediacloud'"
./script/run_with_carton.sh ./script/mediawords_manage_users.pl \
    --action=add \
    --email="jdoe@mediacloud.org" \
    --full_name="John Doe" \
    --notes="Media Cloud administrator" \
    --roles="admin" \
    --password="mediacloud"

echo "Setting up Git pre-commit hooks..."
./install/setup_git_precommit_hooks.sh

echo
echo "Media Cloud install succeeded!"
echo
echo "See doc/ for more information on using Media Cloud."
echo
echo "Run ./script/run_server_with_carton.sh to start the Media Cloud server."
echo
echo "(Log in with email address 'jdoe@mediacloud.org' and password 'mediacloud')"
echo
