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

echo "Copying configuration file 'mediawords.yml.dist' to 'mediawords.yml'..."
if [ ! -f mediawords.yml ]; then
    cp mediawords.yml.dist mediawords.yml
fi

echo "Installing Ansible..."
sudo pip install --upgrade ansible ansible-lint

echo "Setting up host using Ansible..."
ANSIBLE_CONFIG=ansible/ansible.cfg \
    ansible-playbook -i "localhost," -c local ansible/playbook.yml -vvv

# This will create a PostgreSQL user called "mediaclouduser" and two databases
# owned by this user: "mediacloud" and "mediacloud_test".
#
# ("create_default_db_user_and_databases.sh" uses configuration mediawords.yml
# so it needs a working Perl environment)
echo "Creating default PostgreSQL user and databases for Media Cloud..."
sudo ./install/create_default_db_user_and_databases.sh

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
