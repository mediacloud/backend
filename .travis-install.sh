#!/bin/bash

set -u
set -e

echo "Provisioning container with Ansible..."
sudo lxc exec $MC_LXD_CONTAINER -- sudo -H -u $MC_LXD_USER /bin/bash -c "\
    cd $MC_LXD_MEDIACLOUD_ROOT/ansible/; \
    ansible-playbook --inventory='localhost,' --connection=local --skip-tags='hostname' setup.yml \
    "

echo "Creating PostgreSQL databases on container..."
sudo lxc exec $MC_LXD_CONTAINER -- sudo -H -u $MC_LXD_USER /bin/bash -c "\
    cd $MC_LXD_MEDIACLOUD_ROOT; \
    ./tools/db/create_default_db_user_and_databases.sh \
    "

echo "Initializing PostgreSQL databases with schema on container..."
sudo lxc exec $MC_LXD_CONTAINER -- sudo -H -u $MC_LXD_USER /bin/bash -c "\
    cd $MC_LXD_MEDIACLOUD_ROOT; \
    export MEDIAWORDS_CREATE_DB_DO_NOT_CONFIRM=1; \
    ./script/run_in_env.sh ./script/mediawords_create_db.pl \
    "

# Travis's own scripts might have undefined variables or errors
set +u
set +e
