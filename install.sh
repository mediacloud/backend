#!/bin/bash

set -u
set -o errexit

PWD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PWD/script/set_mc_root_dir.inc.sh"

cd "$MC_ROOT_DIR"

if [ `getconf LONG_BIT` != '64' ]; then
   echo "Install failed, you must have a 64 bit OS."
   exit 1
fi

echo "Pulling submodules..."    # in case user forgot to do it
git submodule update --init --recursive

echo "Installing Ansible..."
sudo apt-get -y install python-pip python-setuptools
sudo pip install --upgrade urllib3[secure]
sudo pip install --upgrade pip
sudo pip install --upgrade ansible

echo "Setting up host using Ansible..."
ANSIBLE_CONFIG=ansible/ansible.cfg \
    ansible-playbook \
    --inventory="localhost," \
    --connection=local \
    ansible/setup.yml

# This will create a PostgreSQL user called "mediaclouduser" and two databases
# owned by this user: "mediacloud" and "mediacloud_test".
#
# ("create_default_db_user_and_databases.sh" uses configuration mediawords.yml
# so it needs a working Perl environment)
echo "Creating default PostgreSQL user and databases for Media Cloud..."
sudo ./tools/db/create_default_db_user_and_databases.sh

echo "Initializing PostgreSQL database with Media Cloud schema..."
./script/run_in_env.sh ./script/mediawords_create_db.pl

echo "Creating new administrator user 'jdoe@mediacloud.org' with password 'mediacloud'"
./script/run_in_env.sh ./script/mediawords_manage_users.pl \
    --action=add \
    --email="jdoe@mediacloud.org" \
    --full_name="John Doe" \
    --notes="Media Cloud administrator" \
    --roles="admin" \
    --password="mediacloud"

echo
echo "Media Cloud install succeeded!"
echo
echo "See doc/ for more information on using Media Cloud."
echo
echo "Run ./script/run_dev_server.sh to start the Media Cloud server."
echo
echo "(Log in with email address 'jdoe@mediacloud.org' and password 'mediacloud')"
echo
